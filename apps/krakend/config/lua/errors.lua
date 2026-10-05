-- Shaping what a client sees when a backend fails.
--
-- remap_status(response, error_key, from, to, message)
--
-- With "return_error_details" set on a backend, KrakenD records that backend's
-- failure in the response under error_<alias> instead of failing the whole
-- request. If the recorded status is `from`, the client gets `to` instead. Any
-- other failure, or none, passes through unchanged — so a backend that is down
-- is not mistaken for, say, a missing record.
--
-- `message` goes to the gateway log ("Error #01: No such customer"); the client
-- gets an empty body. KrakenD would only send it with the router's
-- return_error_msg on, which also puts backend URLs into every error body.
--
--   "post": "remap_status(response.load(), 'error_user', 404, 418, 'No such customer')"
function remap_status(response, error_key, from, to, message)
  local failure = response:data():get(error_key)
  if failure ~= nil and failure:get("http_status_code") == from then
    custom_error(message, to)
  end
end
