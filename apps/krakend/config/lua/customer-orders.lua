-- GET /v1/customers/{id}/orders: give each order its own participants.
--
-- KrakenD config can chain calls but cannot loop over a list, and attaching
-- data to each order is a loop. These three functions do only the looping; the
-- calls themselves are declared in endpoints/customers.json.

-- Call 0 returned the customer's orders. List their ids, so call 1 can fetch the
-- events of all of them at once: /events?order_id={resp0_order_ids}
function collect_order_ids(response)
  local data = response:data()
  local orders = data:get("orders")
  local ids = luaList.new()
  for i = 0, orders:len() - 1 do
    ids:set(i, orders:get(i):get("id"))
  end
  data:set("order_ids", ids)
end

-- Call 1 returned those orders' events. List every participant id, so call 2 can
-- fetch all participants at once: /users?ids={resp1_participant_ids}
-- Repeats are fine: /users?ids= returns each user once.
function collect_participant_ids(response)
  local data = response:data()
  local events = data:get("events")
  local ids = luaList.new()
  local count = 0
  for i = 0, events:len() - 1 do
    local event_ids = events:get(i):get("participant_ids")
    for j = 0, event_ids:len() - 1 do
      ids:set(count, event_ids:get(j))
      count = count + 1
    end
  end
  data:set("participant_ids", ids)
end

-- All calls are done. Give each order the users from its own events, each once,
-- then remove the working data the calls left behind.
function attach_participants(response)
  local data = response:data()
  local orders = data:get("orders")
  local events = data:get("events")
  local users = data:get("customers")

  local user_by_id = {}
  for i = 0, users:len() - 1 do
    local user = users:get(i)
    user_by_id[user:get("customer_id")] = user
  end

  for i = 0, orders:len() - 1 do
    local order = orders:get(i)
    local participants = luaList.new()
    local seen = {}
    local count = 0
    for j = 0, events:len() - 1 do
      local event = events:get(j)
      if event:get("order_id") == order:get("id") then
        local ids = event:get("participant_ids")
        for k = 0, ids:len() - 1 do
          local id = ids:get(k)
          if user_by_id[id] ~= nil and not seen[id] then
            seen[id] = true
            participants:set(count, user_by_id[id])
            count = count + 1
          end
        end
      end
    end
    order:set("participants", participants)
  end

  for _, key in ipairs({ "order_ids", "events", "participant_ids", "customers", "requested", "returned", "missing" }) do
    data:del(key)
  end
end
