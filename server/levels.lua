local config = require 'config.general'
local limits = require 'shared.limits'
local db = require 'server.db'

local MAX_TOTAL_XP = 4000000000

local settings = config.levels or {}
local baseXp = math.max(1, math.floor(tonumber(settings.baseXp) or 100))
local growth = math.max(0, math.floor(tonumber(settings.xpGrowth) or 0))
local maxLevel = math.min(limits.level, math.max(1, math.floor(tonumber(settings.maxLevel) or 1)))
local cache = {}
local saving = {}

local function totalFor(level)
    local steps = level - 1

    return steps * baseXp + growth * steps * (steps - 1) // 2
end

while maxLevel > 1 and totalFor(maxLevel) > MAX_TOTAL_XP do
    maxLevel -= 1
end

local levels = {
    enabled = settings.enabled == true,
    maxLevel = maxLevel,
    defaultXp = math.min(limits.xp, math.max(0, math.floor(tonumber(settings.defaultXp) or 0))),
}

local function levelFor(xp)
    local level = 1

    while level < maxLevel and xp >= totalFor(level + 1) do
        level += 1
    end

    return level
end

local function load(citizenid)
    if cache[citizenid] then
        return cache[citizenid]
    end

    local xp = MySQL.scalar.await(db.queries.loadXp, { citizenid }) or 0

    if not cache[citizenid] then
        cache[citizenid] = math.min(xp, totalFor(maxLevel))
    end

    return cache[citizenid]
end

local function save(citizenid)
    if saving[citizenid] then
        saving[citizenid] = 'again'
        return
    end

    saving[citizenid] = 'saving'

    CreateThread(function()
        repeat
            saving[citizenid] = 'saving'

            local ok, err = pcall(MySQL.prepare.await, db.queries.saveXp, { citizenid, cache[citizenid] })

            if not ok then
                lib.print.error(('could not save the crafting XP of %s: %s'):format(citizenid, err))
            end
        until saving[citizenid] ~= 'again'

        saving[citizenid] = nil
    end)
end

function levels.level(citizenid)
    return levelFor(load(citizenid))
end

function levels.view(citizenid)
    local xp = load(citizenid)
    local level = levelFor(xp)

    return {
        level = level,
        xp = xp - totalFor(level),
        next = level < maxLevel and totalFor(level + 1) - totalFor(level) or 0,
    }
end

function levels.add(citizenid, amount)
    local xp = load(citizenid)
    local before = levelFor(xp)

    cache[citizenid] = math.min(xp + amount, totalFor(maxLevel))
    save(citizenid)

    local after = levelFor(cache[citizenid])

    return after > before and after or nil
end

function levels.set(citizenid, level)
    load(citizenid)

    cache[citizenid] = totalFor(level)
    save(citizenid)
end

return levels
