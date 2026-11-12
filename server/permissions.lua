local config = require 'config.permissions'

local permissions = {}
local customAnswers = {}

for i = 1, #config.principals do
    lib.addAce(config.principals[i], config.ace, true)
end

local function meetsGrade(group, required)
    if not group then return false end

    local minimum = required[group.name]

    if not minimum then return false end

    return (group.grade and group.grade.level or 0) >= minimum
end

local function passesCustom(source)
    if not config.custom then return false end

    local now = os.time()
    local cached = customAnswers[source]

    if cached and cached.expires > now then
        return cached.allowed
    end

    local ok, allowed = pcall(config.custom, source)

    if not ok then
        lib.print.error(('the custom permission check failed for player %s: %s'):format(source, allowed))
        allowed = false
    end

    allowed = allowed == true
    customAnswers[source] = { allowed = allowed, expires = now + config.customCacheSeconds }

    return allowed
end

AddEventHandler('playerDropped', function()
    customAnswers[source] = nil
end)

function permissions.canManage(source)
    if type(source) ~= 'number' or source < 1 then return false end

    if IsPlayerAceAllowed(source, config.ace) then
        return true
    end

    local player = exports.qbx_core:GetPlayer(source)

    if not player then return false end

    local data = player.PlayerData

    if meetsGrade(data.job, config.jobs) or meetsGrade(data.gang, config.gangs) then
        return true
    end

    for i = 1, #config.citizenids do
        if config.citizenids[i] == data.citizenid then
            return true
        end
    end

    return passesCustom(source)
end

return permissions
