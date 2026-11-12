return {
    -- Prints every craft, collect, cancel and tablet change to the server console.
    debug = false,

    -- Checks GitHub for a newer release when the resource starts.
    versionCheck = true,
    repository = 'wheylovesprotein/whey_crafting',

    -- How the management tablet is opened. Only players allowed by config/permissions.lua can open it.
    -- It can also be opened with an ox_inventory item, see the README for the item definition.
    tablet = {
        command = 'crafttablet', -- chat command, or false for none
        keybind = '',            -- default key for the command (players can rebind it in GTA settings), '' for none
    },

    -- How many queue slots each player has per bench.
    queueSize = 10,

    -- Heaviest a single craft order can be, in grams (ox_inventory weights). 100000 = 100kg.
    -- There is no other limit on how many you can craft in one order.
    maxCraftWeight = 100000,
}
