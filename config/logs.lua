-- Called on the server for every craft, collect, cancel and tablet change.
-- `event` is a short description such as 'Craft started', `data` is a table of details (player, item, count...).
-- Send it wherever you keep logs. It does nothing by default. Example with ox_lib's logger:
--
--   return function(event, data)
--       lib.logger(data.player or 0, event, json.encode(data))
--   end
return function(event, data) end
