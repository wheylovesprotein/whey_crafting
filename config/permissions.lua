-- Who can open the tablet, edit recipes and place or remove benches.
-- A player is allowed when ANY of the checks below passes. The server checks this on every action.
return {
    -- The ACE permission that grants access. Give it to anyone in server.cfg with:
    --   add_ace group.admin whey_crafting.manage allow
    --   add_ace identifier.license:xxxxxxxx whey_crafting.manage allow
    ace = 'whey_crafting.manage',

    -- Principals that are given the ACE above automatically when the resource starts.
    -- 'group.admin' covers txAdmin admins and anyone added with add_principal ... group.admin.
    -- Set to {} if you only want to grant it yourself in server.cfg.
    principals = { 'group.admin' },

    -- Qbox jobs allowed in, as job name = lowest grade allowed. Example: { police = 3, mechanic = 0 }
    jobs = {},

    -- Qbox gangs allowed in, as gang name = lowest grade allowed. Example: { ballas = 2 }
    gangs = {},

    -- Single characters allowed in, by citizenid. Example: { 'ABC12345' }
    citizenids = {},

    -- Your own check, for anything the options above do not cover, such as a Discord role.
    -- It runs on the server, gets the player's server id and must return true to allow them.
    -- Leave it as false to turn it off.
    --
    -- Example with wasabi_discord (replace the number with your Discord role id):
    --   custom = function(source)
    --       return exports.wasabi_discord:checkRole(source, '123456789012345678')
    --   end,
    --
    -- Example with Badger_Discord_API:
    --   custom = function(source)
    --       local roles = exports.Badger_Discord_API:GetDiscordRoles(source) or {}
    --
    --       for i = 1, #roles do
    --           if tostring(roles[i]) == '123456789012345678' then return true end
    --       end
    --
    --       return false
    --   end,
    custom = false,

    -- How long an answer from the custom check is remembered per player, in seconds.
    -- Discord checks call the Discord API, which blocks you if you ask too often, so keep this above 0 for those.
    customCacheSeconds = 60,
}
