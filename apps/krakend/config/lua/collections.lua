-- Two generic helpers for what KrakenD config cannot do with a list: collect
-- values out of it, and attach related data to each of its elements.
--
-- Nothing here knows about orders, events or users. Each route passes its own
-- key names, so what joins to what is written in the route's config:
--
--   "post": "pluck(response.load(), 'orders', 'id', 'order_ids')"
--
-- KrakenD's luaList is 0-based, unlike plain Lua tables.

-- pluck(response, list, field, into)
--
-- Collects `field` from every element of `list` into a new list `into`. When
-- the field is itself a list, its items are added one by one, so
--   pluck(r, 'orders', 'id', 'order_ids')                -> ["A-1006", "A-1008"]
--   pluck(r, 'events', 'participant_ids', 'all_ids')     -> ["42", "43", "43", ...]
-- A missing or empty `list` gives an empty `into`, never a missing one, so a
-- later {resp_...} placeholder always has something to substitute.
function pluck(response, list, field, into)
  local data = response:data()
  local items = data:get(list)
  local out = luaList.new()
  local count = 0

  if items ~= nil then
    for i = 0, items:len() - 1 do
      local value = items:get(i):get(field)
      if type(value) == "userdata" and value.len ~= nil then
        for j = 0, value:len() - 1 do
          out:set(count, value:get(j))
          count = count + 1
        end
      elseif value ~= nil then
        out:set(count, value)
        count = count + 1
      end
    end
  end

  data:set(into, out)
end

-- attach(response, spec)
--
-- For each element of spec.parents, finds the elements of spec.children whose
-- spec.child_key equals the parent's spec.key, collects their spec.ids, looks
-- those ids up in spec.lookup by spec.lookup_key, and stores the matches — each
-- once, ids with no match skipped — in the parent under spec.into.
--
--   attach(r, { parents = 'orders', key = 'id',
--               children = 'events', child_key = 'order_id', ids = 'participant_ids',
--               lookup = 'customers', lookup_key = 'customer_id',
--               into = 'participants' })
--
-- gives every order a `participants` list of the users from its own events.
function attach(response, spec)
  local data = response:data()
  local parents = data:get(spec.parents)
  local children = data:get(spec.children)
  local lookup = data:get(spec.lookup)

  local by_id = {}
  if lookup ~= nil then
    for i = 0, lookup:len() - 1 do
      local item = lookup:get(i)
      by_id[item:get(spec.lookup_key)] = item
    end
  end

  if parents == nil then
    return
  end

  for i = 0, parents:len() - 1 do
    local parent = parents:get(i)
    local matches = luaList.new()
    local seen = {}
    local count = 0

    if children ~= nil then
      for j = 0, children:len() - 1 do
        local child = children:get(j)
        if child:get(spec.child_key) == parent:get(spec.key) then
          local ids = child:get(spec.ids)
          for k = 0, ids:len() - 1 do
            local id = ids:get(k)
            if by_id[id] ~= nil and not seen[id] then
              seen[id] = true
              matches:set(count, by_id[id])
              count = count + 1
            end
          end
        end
      end
    end

    parent:set(spec.into, matches)
  end
end

-- drop(response, keys)
--
-- Removes top-level keys: the working data earlier steps left behind. Use it
-- after attach rather than an endpoint flatmap_filter, because an endpoint's
-- flatmap runs BEFORE its Lua post and would delete what attach still needs.
function drop(response, keys)
  local data = response:data()
  for _, key in ipairs(keys) do
    data:del(key)
  end
end
