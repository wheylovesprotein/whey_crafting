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

    -- Crafting levels. A player earns XP when they collect a finished craft and levels up as it adds up.
    -- Each recipe can give its own XP and need a level, both set in the tablet's recipe editor.
    -- Staff can set a player's level from the Levels page of the tablet.
    levels = {
        enabled = true,  -- false turns XP, levels and level requirements off everywhere
        maxLevel = 50,   -- highest level a player can reach (1000 at most)
        defaultXp = 10,  -- XP for one craft of a recipe that has no XP of its own
        baseXp = 100,    -- XP needed to go from level 1 to level 2
        xpGrowth = 50,   -- every level after that needs this much more XP than the one before
    },
}
