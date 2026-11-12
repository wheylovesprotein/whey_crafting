lib.locale()

local config = require 'config.general'
local stations = require 'config.stations'
local hook = require 'config.logs'
local limits = require 'shared.limits'
local db = require 'server.db'
local permissions = require 'server.permissions'
local itemList = require 'server.items'

local MAX_UNWEIGHTED_AMOUNT = 9999
local TYPES_BYTES_PER_SECOND = 200000
local KEY_PATTERN = '^[a-z0-9_]+$'
local COOLDOWN_LOAD_LIMIT = 100000
local QUEUE_LOAD_LIMIT = 100000
local MODEL_PATTERN = '^[%w_%-]+$'
local STARTING_UP = locale('starting_up')

local ready = false
local inventory = exports.ox_inventory
local types = {}
local recipes = {}
local tables = {}
local queues = {}
local cooldowns = {}
local savingCooldowns = {}
local pendingPlacement = {}
local busy = {}
local props = {}
local propCount = 0
local pendingProps = {}

local function log(event, data)
    if config.debug then
        lib.print.info(event, json.encode(data))
    end

    hook(event, data)
end

local viewers = {}

local function markDirty()
    for playerId in pairs(viewers) do
        TriggerClientEvent('whey_crafting:client:dirty', playerId)
    end
end

local function itemSummary(list)
    local parts = {}

    for i, entry in ipairs(list) do
        parts[i] = ('%dx %s'):format(entry.count, entry.item)
    end

    return table.concat(parts, ', ')
end

local function cleanLabel(value)
    if type(value) ~= 'string' then return end

    local label = value:match('^%s*(.-)%s*$')
    local length = utf8.len(label)

    if not length or length < 1 or length > limits.label then return end

    return label
end

local function wholeNumber(value, min, max)
    local number = tonumber(value)

    if not number or number ~= number then return end

    number = math.floor(number)

    if math.type(number) ~= 'integer' or number < min or number > max then return end

    return number
end

local function itemName(value, checkItems)
    if not checkItems then
        return value
    end

    local item = inventory:Items(value)

    return item and item.name
end

local function isKey(name)
    return type(name) == 'string' and #name <= limits.key and name:find(KEY_PATTERN) ~= nil
end

local function sanitiseIngredients(list, checkItems)
    if type(list) ~= 'table' then
        return nil, locale('invalid_ingredients')
    end

    if #list > limits.ingredients then
        return nil, locale('too_many_ingredients', limits.ingredients)
    end

    local ingredients, seen = {}, {}

    for i = 1, #list do
        local ingredient = list[i]

        if type(ingredient) ~= 'table' or type(ingredient.item) ~= 'string' or ingredient.item == '' then
            return nil, locale('ingredient_no_item', i)
        end

        local name = itemName(ingredient.item, checkItems)

        if not name then
            return nil, locale('ingredient_unknown', ingredient.item)
        end

        if seen[name] then
            return nil, locale('ingredient_twice', name)
        end

        local count = wholeNumber(ingredient.count, 1, limits.ingredientCount)

        if not count then
            return nil, locale('ingredient_amount', name, limits.ingredientCount)
        end

        seen[name] = true
        ingredients[i] = { item = name, count = count }
    end

    return ingredients
end

local function sanitiseCooldown(value)
    if type(value) ~= 'table' then
        return nil, locale('invalid_cooldown')
    end

    local limit = wholeNumber(value.limit, 1, limits.cooldownLimit)

    if not limit then
        return nil, locale('cooldown_limit_range', limits.cooldownLimit)
    end

    local hours = wholeNumber(value.hours, 1, limits.cooldownHours)

    if not hours then
        return nil, locale('cooldown_hours_range', limits.cooldownHours)
    end

    return { limit = limit, hours = hours }
end

local function sanitiseRecipe(recipe, checkItems)
    if type(recipe) ~= 'table' or type(recipe.item) ~= 'string' or recipe.item == '' then
        return nil, locale('recipe_no_item')
    end

    local item = itemName(recipe.item, checkItems)

    if not item then
        return nil, locale('item_unknown', recipe.item)
    end

    local count = 1

    if recipe.count ~= nil then
        count = wholeNumber(recipe.count, 1, limits.recipeCount)

        if not count then
            return nil, locale('recipe_count_range', limits.recipeCount)
        end
    end

    local duration = wholeNumber(recipe.duration, 1, limits.duration)

    if not duration then
        return nil, locale('recipe_duration_range', limits.duration)
    end

    local blueprint

    if recipe.blueprint ~= nil and recipe.blueprint ~= '' then
        if type(recipe.blueprint) ~= 'string' then
            return nil, locale('invalid_blueprint')
        end

        blueprint = itemName(recipe.blueprint, checkItems)

        if not blueprint then
            return nil, locale('blueprint_unknown', recipe.blueprint)
        end
    end

    local cooldown

    if recipe.cooldown ~= nil then
        local err
        cooldown, err = sanitiseCooldown(recipe.cooldown)

        if not cooldown then
            return nil, err
        end
    end

    local ingredients, err = sanitiseIngredients(recipe.ingredients or {}, checkItems)

    if not ingredients then
        return nil, err
    end

    return {
        item = item,
        count = count,
        duration = duration,
        blueprint = blueprint,
        cooldown = cooldown,
        ingredients = ingredients,
    }
end

local function sanitiseType(name, data, checkItems)
    if not isKey(name) then
        return nil, locale('key_format', limits.key)
    end

    if type(data) ~= 'table' then
        return nil, locale('invalid_type')
    end

    local label = cleanLabel(data.label)

    if not label then
        return nil, locale('type_label_range', limits.label)
    end

    local categories = data.categories or {}

    if type(categories) ~= 'table' then
        return nil, locale('invalid_categories')
    end

    if #categories > limits.categories then
        return nil, locale('too_many_categories', limits.categories)
    end

    local clean = { label = label, categories = {} }
    local seen = {}

    for i = 1, #categories do
        local category = categories[i]
        local categoryLabel = type(category) == 'table' and cleanLabel(category.label)

        if not categoryLabel then
            return nil, locale('category_label_range', i, limits.label)
        end

        local list = category.recipes or {}

        if type(list) ~= 'table' then
            return nil, locale('invalid_recipes', categoryLabel)
        end

        if #list > limits.recipes then
            return nil, locale('too_many_recipes', categoryLabel, limits.recipes)
        end

        local cleanRecipes = {}

        for j = 1, #list do
            local raw = list[j]
            local recipe, err = sanitiseRecipe(raw, checkItems)

            if not recipe then
                local where = locale('recipe_n', j)

                if type(raw) == 'table' and type(raw.item) == 'string' and raw.item ~= '' then
                    where = raw.item
                end

                return nil, ('%s, %s: %s'):format(categoryLabel, where, err)
            end

            if seen[recipe.item] then
                return nil, locale('recipe_duplicate', categoryLabel, recipe.item)
            end

            seen[recipe.item] = true
            cleanRecipes[j] = recipe
        end

        clean.categories[i] = { label = categoryLabel, recipes = cleanRecipes }
    end

    return clean
end

local function setType(name, tableType)
    local byItem = {}

    for _, category in ipairs(tableType.categories) do
        for _, recipe in ipairs(category.recipes) do
            byItem[recipe.item] = recipe
        end
    end

    types[name] = tableType
    recipes[name] = byItem
end

local function sanitiseGangs(value)
    if value == nil then
        return {}
    end

    if type(value) ~= 'table' then
        return nil, locale('invalid_gangs')
    end

    local known = exports.qbx_core:GetGangs()
    local gangs, seen = {}, {}

    for i = 1, #value do
        local name = value[i]

        if name == 'none' then
            return nil, locale('gang_none')
        end

        if type(name) ~= 'string' or not known[name] then
            return nil, locale('gang_unknown', tostring(name))
        end

        if not seen[name] then
            seen[name] = true
            gangs[#gangs + 1] = name
        end
    end

    return gangs
end

local function decodeGangs(value)
    local gangs = {}

    if type(value) ~= 'string' then
        return gangs
    end

    local ok, list = pcall(json.decode, value)

    if not ok or type(list) ~= 'table' then
        return gangs
    end

    for i = 1, #list do
        if type(list[i]) == 'string' then
            gangs[#gangs + 1] = list[i]
        end
    end

    return gangs
end

local function inGang(gangs, gang)
    if #gangs == 0 then
        return true
    end

    for i = 1, #gangs do
        if gangs[i] == gang then
            return true
        end
    end

    return false
end

local function getTableList()
    local list = {}

    for _, craftTable in pairs(tables) do
        if types[craftTable.type] then
            list[#list + 1] = craftTable
        end
    end

    return list
end

local function getPropList()
    local list = {}

    for _, prop in pairs(props) do
        list[#list + 1] = prop
    end

    return list
end

local function broadcastTypes()
    TriggerLatentClientEvent('whey_crafting:client:setTypes', -1, TYPES_BYTES_PER_SECOND, types)
    markDirty()
end

local function syncTable(craftTable)
    if types[craftTable.type] then
        TriggerClientEvent('whey_crafting:client:addTable', -1, craftTable)
    else
        TriggerClientEvent('whey_crafting:client:removeTable', -1, craftTable.id)
    end

    markDirty()
end

local function forgetTable(id)
    tables[id] = nil

    for _, byTable in pairs(queues) do
        byTable[id] = nil
    end

    TriggerClientEvent('whey_crafting:client:removeTable', -1, id)
    markDirty()
end

local function deleteTable(id)
    local removed = MySQL.update.await(db.queries.deleteTable, { id }) == 1

    forgetTable(id)

    return removed
end

local function findTable(id)
    return type(id) == 'number' and tables[id] or nil
end

local function warnMissingItems()
    local function check(typeName, name)
        if not inventory:Items(name) then
            lib.print.warn(('item "%s" in bench type "%s" does not exist in ox_inventory'):format(name, typeName))
        end
    end

    for typeName, byItem in pairs(recipes) do
        for _, recipe in pairs(byItem) do
            check(typeName, recipe.item)

            if recipe.blueprint then
                check(typeName, recipe.blueprint)
            end

            for _, ingredient in ipairs(recipe.ingredients) do
                check(typeName, ingredient.item)
            end
        end
    end
end

local function loadTypes()
    local rows = MySQL.query.await(db.queries.loadTypes)

    for i = 1, #rows do
        local row = rows[i]
        local ok, categories = pcall(json.decode, row.categories)
        local clean, err

        if ok and type(categories) == 'table' then
            clean, err = sanitiseType(row.name, { label = row.label, categories = categories }, false)
        else
            err = 'its categories are not valid JSON'
        end

        if clean then
            setType(row.name, clean)
        else
            lib.print.error(('bench type "%s" was not loaded: %s'):format(row.name, err))
        end
    end
end

local function loadCooldowns()
    local now = os.time()

    MySQL.update.await(db.queries.pruneCooldowns, { now, now - limits.cooldownHours * 3600 })

    local rows = MySQL.query.await(db.queries.loadCooldowns, { COOLDOWN_LOAD_LIMIT })

    for i = 1, #rows do
        local row = rows[i]
        local byItem = cooldowns[row.citizenid]

        if not byItem then
            byItem = {}
            cooldowns[row.citizenid] = byItem
        end

        byItem[row.item] = { crafted = row.crafted, startedAt = row.started_at, endsAt = row.ends_at }
    end

    if #rows >= COOLDOWN_LOAD_LIMIT then
        lib.print.warn(('only the first %d craft cooldowns were loaded'):format(COOLDOWN_LOAD_LIMIT))
    end
end

local function saveCooldown(citizenid, item)
    local key = ('%s:%s'):format(citizenid, item)

    if savingCooldowns[key] then
        savingCooldowns[key] = 'again'
        return
    end

    savingCooldowns[key] = 'saving'

    CreateThread(function()
        repeat
            savingCooldowns[key] = 'saving'

            local state = cooldowns[citizenid] and cooldowns[citizenid][item]

            if state then
                local params = { citizenid, item, state.crafted, state.startedAt, state.endsAt }
                local ok, err = pcall(MySQL.prepare.await, db.queries.saveCooldown, params)

                if not ok then
                    lib.print.error(('could not save the %s cooldown for %s: %s'):format(item, citizenid, err))
                end
            end
        until savingCooldowns[key] ~= 'again'

        savingCooldowns[key] = nil
    end)
end

local function timeLeft(seconds)
    local minutes = math.max(1, math.ceil(seconds / 60))

    if minutes < 60 then
        return locale('time_minutes', minutes)
    end

    local hours = minutes // 60

    if hours < 24 then
        return minutes % 60 > 0 and locale('time_hours_minutes', hours, minutes % 60) or locale('time_hours', hours)
    end

    return hours % 24 > 0 and locale('time_days_hours', hours // 24, hours % 24) or locale('time_days', hours // 24)
end

local function cooldownEnd(state, rule)
    return state.endsAt > 0 and state.endsAt or state.startedAt + rule.hours * 3600
end

local function cooldownFor(citizenid, item, rule, now)
    local byItem = cooldowns[citizenid]
    local state = byItem and byItem[item]

    if not state then return end

    if cooldownEnd(state, rule) > now then
        return state
    end

    byItem[item] = nil
end

local function cooldownBlock(rule, state, amount, label, now)
    local crafted = state and state.crafted or 0

    if state and (state.endsAt > 0 or crafted >= rule.limit) then
        return locale('cooldown_wait', label, timeLeft(cooldownEnd(state, rule) - now))
    end

    local left = rule.limit - crafted

    if amount > left then
        return locale(left == 1 and 'cooldown_left_one' or 'cooldown_left_many', label, left, rule.hours)
    end
end

local function recordCraft(citizenid, item, rule, state, amount, now)
    state = state or { crafted = 0, startedAt = now, endsAt = 0 }
    state.crafted += amount

    if state.crafted >= rule.limit then
        state.endsAt = now + rule.hours * 3600
    end

    local byItem = cooldowns[citizenid]

    if not byItem then
        byItem = {}
        cooldowns[citizenid] = byItem
    end

    byItem[item] = state
    saveCooldown(citizenid, item)
end

local function refundCooldown(citizenid, entry)
    local byItem = cooldowns[citizenid]
    local state = byItem and byItem[entry.item]

    if not state or state.startedAt ~= entry.cooldownStart then return end

    state.crafted = math.max(0, state.crafted - entry.amount)
    state.endsAt = 0
    saveCooldown(citizenid, entry.item)
end

local function loadProps()
    local rows = MySQL.query.await(db.queries.loadProps, { limits.props })

    for i = 1, #rows do
        local row = rows[i]

        props[row.id] = {
            id = row.id,
            model = row.model,
            coords = vec3(row.x, row.y, row.z),
            heading = row.heading + 0.0,
        }
    end

    propCount = #rows
end

local function queueFor(citizenid, tableId)
    local byTable = queues[citizenid]

    if not byTable then
        byTable = {}
        queues[citizenid] = byTable
    end

    local queue = byTable[tableId]

    if not queue then
        queue = {}
        byTable[tableId] = queue
    end

    return queue
end

local function loadQueues()
    local rows = MySQL.query.await(db.queries.loadQueue, { QUEUE_LOAD_LIMIT })

    for i = 1, #rows do
        local row = rows[i]
        local ok, ingredients = pcall(json.decode, row.ingredients)

        if not ok or type(ingredients) ~= 'table' then
            lib.print.error(('queued craft #%d has unreadable materials and cannot be refunded'):format(row.id))
            ingredients = {}
        end

        local queue = queueFor(row.citizenid, row.table_id)

        queue[#queue + 1] = {
            id = row.id,
            item = row.item,
            count = row.count,
            amount = row.amount,
            duration = row.duration,
            readyAt = row.ready_at,
            ingredients = ingredients,
            cooldownStart = row.cooldown_start,
        }
    end

    if #rows >= QUEUE_LOAD_LIMIT then
        lib.print.warn(('only the first %d queued crafts were loaded'):format(QUEUE_LOAD_LIMIT))
    end
end

MySQL.ready(function()
    db.install()

    loadTypes()
    loadCooldowns()
    loadQueues()

    local rows = MySQL.query.await(db.queries.loadTables)

    for i = 1, #rows do
        local row = rows[i]

        tables[row.id] = {
            id = row.id,
            coords = vec3(row.x, row.y, row.z),
            heading = row.heading + 0.0,
            type = row.type,
            gangs = decodeGangs(row.gangs),
        }

        if not types[row.type] then
            local message = 'crafting table #%d has type "%s", which is not a bench type, so it is hidden'

            lib.print.warn(message:format(row.id, row.type))
        end
    end

    warnMissingItems()
    loadProps()

    if not pcall(function() return inventory.Save end) then
        lib.print.error('ox_inventory has no Save export, so a crash can duplicate or lose crafting items')
    end

    ready = true
    broadcastTypes()
    TriggerClientEvent('whey_crafting:client:setTables', -1, getTableList())
    TriggerLatentClientEvent('whey_crafting:client:setProps', -1, TYPES_BYTES_PER_SECOND, getPropList())
end)

lib.callback.register('whey_crafting:server:getTables', function()
    if not ready then
        return false, STARTING_UP
    end

    return getTableList(), types
end)

lib.callback.register('whey_crafting:server:getProps', function(source)
    if not ready then return false end

    TriggerLatentClientEvent('whey_crafting:client:setProps', source, TYPES_BYTES_PER_SECOND, getPropList())

    return true
end)

lib.callback.register('whey_crafting:server:saveTable', function(source, coords, heading)
    if not ready then
        return false, STARTING_UP
    end

    local pending = pendingPlacement[source]

    if not pending then
        return false, locale('placement_not_started')
    end

    if not types[pending.type] then
        pendingPlacement[source] = nil
        return false, locale('type_gone')
    end

    if type(coords) ~= 'vector3' or type(heading) ~= 'number' or heading ~= heading then
        return false, locale('invalid_placement')
    end

    local player = exports.qbx_core:GetPlayer(source)

    if not player then
        return false, locale('player_not_loaded')
    end

    if not (#(GetEntityCoords(GetPlayerPed(source)) - coords) <= stations.placement.maxDistance + 2.0) then
        return false, locale('too_far')
    end

    heading = heading % 360

    local id = MySQL.insert.await(
        db.queries.insertTable,
        { coords.x, coords.y, coords.z, heading, pending.type, json.encode(pending.gangs), player.PlayerData.citizenid }
    )

    if not id then
        return false, locale('table_save_failed')
    end

    pendingPlacement[source] = nil

    local craftTable = { id = id, coords = coords, heading = heading, type = pending.type, gangs = pending.gangs }
    tables[id] = craftTable
    syncTable(craftTable)

    log('Crafting table placed', {
        player = source,
        by = GetPlayerName(source),
        citizenid = player.PlayerData.citizenid,
        tableId = id,
        tableType = pending.type,
        coords = ('%.1f, %.1f, %.1f'):format(coords.x, coords.y, coords.z),
    })

    return id
end)

local function manageData()
    if not ready then
        return false, STARTING_UP
    end

    local typeList, tableList, propList = {}, {}, {}

    for name, tableType in pairs(types) do
        typeList[#typeList + 1] = { name = name, label = tableType.label, categories = tableType.categories }
    end

    table.sort(typeList, function(a, b)
        local left, right = a.label:lower(), b.label:lower()

        if left == right then
            return a.name < b.name
        end

        return left < right
    end)

    for _, craftTable in pairs(tables) do
        local coords = craftTable.coords

        tableList[#tableList + 1] = {
            id = craftTable.id,
            type = craftTable.type,
            coords = { x = coords.x, y = coords.y, z = coords.z },
            heading = craftTable.heading,
            gangs = craftTable.gangs,
        }
    end

    table.sort(tableList, function(a, b) return a.id < b.id end)

    for _, prop in pairs(props) do
        local coords = prop.coords

        propList[#propList + 1] = {
            id = prop.id,
            model = prop.model,
            coords = { x = coords.x, y = coords.y, z = coords.z },
            heading = prop.heading,
        }
    end

    table.sort(propList, function(a, b) return a.id < b.id end)

    return true, { types = typeList, tables = tableList, props = propList }
end

local function saveType(name, data, isNew)
    if not ready then
        return false, STARTING_UP
    end

    if not isKey(name) then
        return false, locale('key_format', limits.key)
    end

    if isNew and types[name] then
        return false, locale('type_exists', name)
    end

    if not isNew and not types[name] then
        return false, locale('type_gone')
    end

    local clean, err = sanitiseType(name, data, true)

    if not clean then
        return false, err
    end

    MySQL.update.await(db.queries.saveType, { name, clean.label, json.encode(clean.categories) })

    setType(name, clean)
    broadcastTypes()

    if isNew then
        for _, craftTable in pairs(tables) do
            if craftTable.type == name then
                syncTable(craftTable)
            end
        end
    end

    return true
end

local function deleteType(name)
    if not ready then
        return false, STARTING_UP
    end

    if type(name) ~= 'string' or not types[name] then
        return false, locale('type_gone')
    end

    local ok = MySQL.transaction.await({
        { query = db.queries.deleteTablesOfType, values = { name } },
        { query = db.queries.deleteType, values = { name } },
    })

    if not ok then
        return false, locale('type_delete_failed')
    end

    local removed = 0

    for id, craftTable in pairs(tables) do
        if craftTable.type == name then
            forgetTable(id)
            removed += 1
        end
    end

    types[name] = nil
    recipes[name] = nil
    broadcastTypes()

    return true, removed
end

local function startPlacement(playerId, typeName, gangs)
    if not ready then
        return false, STARTING_UP
    end

    playerId = tonumber(playerId)

    if not playerId or not GetPlayerName(playerId) then
        return false, locale('player_offline')
    end

    if type(typeName) ~= 'string' or not types[typeName] then
        return false, locale('type_gone')
    end

    local lock, err = sanitiseGangs(gangs)

    if not lock then
        return false, err
    end

    pendingPlacement[playerId] = { type = typeName, gangs = lock }
    TriggerClientEvent('whey_crafting:client:startPlacement', playerId)

    return true
end

local function updateTable(id, changes)
    if not ready then
        return false, STARTING_UP
    end

    local craftTable = findTable(id)

    if not craftTable then
        return false, locale('bench_gone')
    end

    if type(changes) ~= 'table' or (changes.type == nil and changes.gangs == nil) then
        return false, locale('nothing_to_change')
    end

    local newType, newGangs = craftTable.type, craftTable.gangs

    if changes.type ~= nil then
        if type(changes.type) ~= 'string' or not types[changes.type] then
            return false, locale('type_missing')
        end

        newType = changes.type
    end

    if changes.gangs ~= nil then
        local err
        newGangs, err = sanitiseGangs(changes.gangs)

        if not newGangs then
            return false, err
        end
    end

    MySQL.update.await(db.queries.updateTable, { newType, json.encode(newGangs), craftTable.id })

    if tables[craftTable.id] ~= craftTable then
        return false, locale('bench_removed_meanwhile')
    end

    craftTable.type = newType
    craftTable.gangs = newGangs
    syncTable(craftTable)

    return true
end

local function removeBench(id)
    if not ready then
        return false, STARTING_UP
    end

    local craftTable = findTable(id)

    if not craftTable then
        return false, locale('bench_gone')
    end

    if not deleteTable(craftTable.id) then
        return false, locale('bench_already_removed')
    end


    return true
end

local function removeProp(id)
    local removed = MySQL.update.await(db.queries.deleteProp, { id }) == 1

    if props[id] then
        props[id] = nil
        propCount -= 1
    end

    TriggerClientEvent('whey_crafting:client:removeProp', -1, id)
    markDirty()

    return removed
end

local function startPropPlacement(playerId, model)
    if not ready then
        return false, STARTING_UP
    end

    playerId = tonumber(playerId)

    if not playerId or not GetPlayerName(playerId) then
        return false, locale('player_offline')
    end

    if type(model) ~= 'string' or #model > limits.model or not model:find(MODEL_PATTERN) then
        return false, locale('invalid_model')
    end

    if propCount >= limits.props then
        return false, locale('too_many_props', limits.props)
    end

    model = model:lower()
    pendingProps[playerId] = { model = model, placed = {} }
    TriggerClientEvent('whey_crafting:client:startPropPlacement', playerId, model)

    return true
end

local function deleteProp(id)
    if not ready then
        return false, STARTING_UP
    end

    if type(id) ~= 'number' or not props[id] then
        return false, locale('prop_gone')
    end

    if not removeProp(id) then
        return false, locale('prop_already_removed')
    end

    return true
end

lib.callback.register('whey_crafting:server:saveProp', function(source, coords, heading)
    if not ready then
        return false, STARTING_UP
    end

    local pending = pendingProps[source]

    if not pending then
        return false, locale('prop_placement_not_started')
    end

    if type(coords) ~= 'vector3' or type(heading) ~= 'number' or heading ~= heading then
        return false, locale('invalid_placement')
    end

    local player = exports.qbx_core:GetPlayer(source)

    if not player then
        return false, locale('player_not_loaded')
    end

    if not (#(GetEntityCoords(GetPlayerPed(source)) - coords) <= stations.placement.maxDistance + 6.0) then
        return false, locale('too_far')
    end

    if propCount >= limits.props then
        return false, locale('too_many_props', limits.props)
    end

    heading = heading % 360

    propCount += 1

    local ok, id = pcall(
        MySQL.insert.await,
        db.queries.insertProp,
        { pending.model, coords.x, coords.y, coords.z, heading, player.PlayerData.citizenid }
    )

    if not ok or not id then
        propCount -= 1
        lib.print.error(('could not save a %s prop: %s'):format(pending.model, id))

        return false, locale('prop_save_failed')
    end

    local prop = { id = id, model = pending.model, coords = coords, heading = heading }

    props[id] = prop
    pending.placed[#pending.placed + 1] = id
    TriggerClientEvent('whey_crafting:client:addProp', -1, prop)
    markDirty()

    return id
end)

lib.callback.register('whey_crafting:server:undoProp', function(source)
    local pending = pendingProps[source]
    local id = pending and table.remove(pending.placed)

    if not id then
        return false, locale('nothing_to_undo')
    end

    removeProp(id)

    return id
end)

lib.callback.register('whey_crafting:server:stopProps', function(source)
    pendingProps[source] = nil

    return true
end)

local function getQueue(playerId, tableId)
    if not ready then
        return nil, STARTING_UP
    end

    local craftTable = tables[tableId]

    if not craftTable or not types[craftTable.type] then
        return nil, locale('too_far_from_table')
    end

    if #(GetEntityCoords(GetPlayerPed(playerId)) - craftTable.coords) > stations.interaction.distance + 2.0 then
        return nil, locale('too_far_from_table')
    end

    local player = exports.qbx_core:GetPlayer(playerId)

    if not player then
        return nil, locale('player_not_loaded')
    end

    local gang = player.PlayerData.gang

    if not inGang(craftTable.gangs, gang and gang.name) then
        return nil, locale('bench_locked')
    end

    local metadata = player.PlayerData.metadata

    if metadata.isdead or metadata.inlaststand or metadata.ishandcuffed then
        return nil, locale('cannot_right_now')
    end

    local citizenid = player.PlayerData.citizenid
    local queue = queueFor(citizenid, tableId)

    return queue, craftTable, citizenid
end

local function queueView(queue)
    local now = os.time()
    local view = {}

    for i = 1, #queue do
        local entry = queue[i]

        view[i] = {
            id = entry.id,
            item = entry.item,
            count = entry.count,
            remaining = math.max(0, entry.readyAt - now) * 1000,
        }
    end

    return view
end

local function cooldownView(citizenid, typeName)
    local now = os.time()
    local view = {}

    for item, recipe in pairs(recipes[typeName] or {}) do
        local rule = recipe.cooldown

        if rule then
            local state = cooldownFor(citizenid, item, rule, now)
            local crafted = state and state.crafted or 0

            if state and (state.endsAt > 0 or crafted >= rule.limit) then
                view[item] = { wait = cooldownEnd(state, rule) - now, limit = rule.limit }
            else
                view[item] = { left = rule.limit - crafted }
            end
        end
    end

    return view
end

local function findEntry(queue, entryId)
    for i = 1, #queue do
        if queue[i].id == entryId then
            return i, queue[i]
        end
    end
end

local function takeItems(source, list)
    for i = 1, #list do
        if not inventory:RemoveItem(source, list[i].item, list[i].count) then
            for j = 1, i - 1 do
                inventory:AddItem(source, list[j].item, list[j].count)
            end

            return false
        end
    end

    return true
end

local function giveItems(source, list)
    for i = 1, #list do
        local fits = inventory:CanCarryItem(source, list[i].item, list[i].count)

        if not fits or not inventory:AddItem(source, list[i].item, list[i].count) then
            for j = 1, i - 1 do
                inventory:RemoveItem(source, list[j].item, list[j].count)
            end

            return false
        end
    end

    return true
end

local function carryableCount(source, item, count)
    if inventory:CanCarryItem(source, item, count) then return count end

    local fits, tooMany = 0, count

    while tooMany - fits > 1 do
        local middle = (fits + tooMany) // 2

        if inventory:CanCarryItem(source, item, middle) then
            fits = middle
        else
            tooMany = middle
        end
    end

    return fits
end

local function canCarryAll(source, list)
    local weight = 0

    for i = 1, #list do
        local item = inventory:Items(list[i].item)

        if not item then return false end

        weight += item.weight * list[i].count
    end

    return inventory:CanCarryWeight(source, weight) == true
end

local function undoItems(source, citizenid, move, list, action)
    local player = exports.qbx_core:GetPlayer(source)

    if player and player.PlayerData.citizenid == citizenid and move(source, list) then return end

    lib.print.error(('could not undo a failed %s for %s, fix by hand: %s'):format(action, citizenid, json.encode(list)))
    log('Crafting undo failed, fix by hand', {
        player = source,
        citizenid = citizenid,
        action = action,
        items = itemSummary(list),
    })
end

local function saveInventory(source)
    local ok, err = pcall(function()
        return inventory:Save(source)
    end)

    if not ok then
        lib.print.warn(('could not save the inventory of player %s: %s'):format(source, err))
    end
end

local function queueAction(name, action)
    lib.callback.register(name, function(source, tableId, ...)
        MySQL.scalar.await(db.queries.ping)

        local queue, craftTable, citizenid = getQueue(source, tableId)

        if not queue then
            return false, craftTable
        end

        if busy[citizenid] then
            return false, locale('please_wait')
        end

        busy[citizenid] = true

        local ok, refused = pcall(action, source, queue, citizenid, craftTable, ...)

        busy[citizenid] = nil

        if not ok then
            error(refused, 0)
        end

        if refused then
            return false, refused
        end

        return queueView(queue), cooldownView(citizenid, craftTable.type)
    end)
end

lib.callback.register('whey_crafting:server:getQueue', function(source, tableId)
    local queue, craftTable, citizenid = getQueue(source, tableId)

    if not queue then
        return false, craftTable
    end

    return queueView(queue), cooldownView(citizenid, craftTable.type)
end)

queueAction('whey_crafting:server:craft', function(source, queue, citizenid, craftTable, recipeId, amount)
    local recipe = recipes[craftTable.type][recipeId]

    if not recipe or math.type(amount) ~= 'integer' or amount < 1 then
        return locale('invalid_recipe')
    end

    if #queue >= config.queueSize then
        return locale('queue_full')
    end

    local item = inventory:Items(recipe.item)
    local now = os.time()
    local rule = recipe.cooldown
    local cooldown = rule and cooldownFor(citizenid, recipe.item, rule, now)
    local blocked = rule and cooldownBlock(rule, cooldown, amount, item and item.label or recipe.item, now)

    if blocked then
        return blocked
    end

    local craftWeight = (item and item.weight or 0) * (recipe.count or 1)
    local maxAmount = craftWeight > 0 and config.maxCraftWeight // craftWeight or MAX_UNWEIGHTED_AMOUNT

    if amount > maxAmount then
        return locale('too_heavy', config.maxCraftWeight / 1000)
    end

    if recipe.blueprint and inventory:GetItemCount(source, recipe.blueprint) < 1 then
        return locale('need_blueprint')
    end

    local taken = {}

    for i, ingredient in ipairs(recipe.ingredients) do
        taken[i] = { item = ingredient.item, count = ingredient.count * amount }

        if inventory:GetItemCount(source, ingredient.item) < taken[i].count then
            return locale('missing_materials')
        end
    end

    if not takeItems(source, taken) then
        return locale('missing_materials')
    end

    local last = queue[#queue]
    local duration = recipe.duration * amount
    local entry = {
        item = recipe.item,
        count = (recipe.count or 1) * amount,
        amount = amount,
        duration = duration,
        readyAt = math.max(now, last and last.readyAt or 0) + duration,
        ingredients = taken,
        cooldownStart = rule and (cooldown and cooldown.startedAt or now) or 0,
    }

    local ok, id = pcall(MySQL.insert.await, db.queries.insertOrder, {
        citizenid,
        craftTable.id,
        entry.item,
        entry.count,
        entry.amount,
        entry.duration,
        entry.readyAt,
        json.encode(entry.ingredients),
        entry.cooldownStart,
    })

    if not ok or not id then
        undoItems(source, citizenid, giveItems, taken, 'craft')
        lib.print.error(('could not save a %s craft for %s: %s'):format(entry.item, citizenid, id))

        return locale('craft_failed')
    end

    entry.id = id
    queue[#queue + 1] = entry

    if rule then
        recordCraft(citizenid, recipe.item, rule, cooldown, amount, now)
    end

    saveInventory(source)
    log('Craft started', {
        player = source,
        citizenid = citizenid,
        order = id,
        tableId = craftTable.id,
        tableType = craftTable.type,
        item = entry.item,
        count = entry.count,
        duration = entry.duration,
        materials = itemSummary(taken),
    })
end)

queueAction('whey_crafting:server:collect', function(source, queue, citizenid, craftTable, entryId)
    local index, entry = findEntry(queue, entryId)

    if not entry then
        return locale('nothing_to_collect')
    end

    if entry.readyAt > os.time() then
        return locale('not_ready')
    end

    local given = carryableCount(source, entry.item, entry.count)

    if given < 1 then
        return locale('cannot_carry')
    end

    if not inventory:AddItem(source, entry.item, given) then
        return locale('give_failed')
    end

    local left = entry.count - given
    local ok, err

    if left > 0 then
        ok, err = pcall(MySQL.update.await, db.queries.setOrderCount, { left, entry.id })
    else
        ok, err = pcall(MySQL.update.await, db.queries.deleteOrder, { entry.id })
    end

    if not ok then
        undoItems(source, citizenid, takeItems, { { item = entry.item, count = given } }, 'collect')
        lib.print.error(('could not update collected order #%d: %s'):format(entry.id, err))

        return locale('collect_failed')
    end

    if left > 0 then
        entry.count = left

        TriggerClientEvent('ox_lib:notify', source, {
            type = 'inform',
            description = locale('collected_part', given, left),
        })
    else
        table.remove(queue, index)
    end

    saveInventory(source)
    log('Craft collected', {
        player = source,
        citizenid = citizenid,
        order = entry.id,
        tableId = craftTable.id,
        tableType = craftTable.type,
        item = entry.item,
        count = given,
        left = left,
    })
end)

queueAction('whey_crafting:server:cancel', function(source, queue, citizenid, craftTable, entryId)
    local index, entry = findEntry(queue, entryId)

    if not entry then
        return locale('nothing_to_cancel')
    end

    local now = os.time()

    if entry.readyAt <= now then
        return locale('already_finished')
    end

    if not canCarryAll(source, entry.ingredients) or not giveItems(source, entry.ingredients) then
        return locale('cannot_carry_materials')
    end

    local shift = math.min(entry.readyAt - now, entry.duration)
    local ok, saved = pcall(MySQL.transaction.await, {
        { query = db.queries.deleteOrder, values = { entry.id } },
        {
            query = db.queries.shiftOrders,
            values = { shift, citizenid, craftTable.id, entry.id },
        },
    })

    if not ok or not saved then
        undoItems(source, citizenid, takeItems, entry.ingredients, 'cancel')
        lib.print.error(('could not cancel order #%d: %s'):format(entry.id, saved))

        return locale('cancel_failed')
    end

    table.remove(queue, index)

    for i = index, #queue do
        queue[i].readyAt -= shift
    end

    refundCooldown(citizenid, entry)
    saveInventory(source)
    log('Craft cancelled', {
        player = source,
        citizenid = citizenid,
        order = entry.id,
        tableId = craftTable.id,
        tableType = craftTable.type,
        item = entry.item,
        count = entry.count,
        refunded = itemSummary(entry.ingredients),
    })
end)

local function gangOptions()
    local options = {}

    for name, gang in pairs(exports.qbx_core:GetGangs()) do
        options[#options + 1] = { name = name, label = gang.label or name }
    end

    table.sort(options, function(a, b) return a.label:lower() < b.label:lower() end)

    return options
end

local function managePayload()
    local ok, data = manageData()

    if not ok then return end

    data.gangs = gangOptions()

    return data
end

local function standBeside(coords, heading)
    local rad = math.rad(heading)

    return vec3(coords.x + math.sin(rad) * 1.2, coords.y - math.cos(rad) * 1.2, coords.z + 1.0)
end

local function teleport(playerId, coords, heading)
    local stand = standBeside(coords, heading)

    SetEntityCoords(GetPlayerPed(playerId), stand.x, stand.y, stand.z, false, false, false, false)
end

local actions = {}

function actions.data()
    local data = managePayload()

    if not data then
        return false, STARTING_UP
    end

    return true, nil, data
end

function actions.items()
    return true, nil, itemList()
end

function actions.saveType(source, payload)
    local isNew = payload.isNew == true
    local ok, err = saveType(payload.name, payload.type, isNew)

    if not ok then
        return false, err
    end

    log(isNew and 'Bench type created' or 'Bench type changed', { player = source, tableType = payload.name })

    return true, locale(isNew and 'type_created' or 'type_saved', types[payload.name].label), managePayload()
end

function actions.deleteType(source, payload)
    local tableType = type(payload.name) == 'string' and types[payload.name]
    local label = tableType and tableType.label or tostring(payload.name)
    local ok, removed = deleteType(payload.name)

    if not ok then
        return false, removed
    end

    log('Bench type deleted', { player = source, tableType = payload.name, tablesRemoved = removed })

    return true, locale(removed == 1 and 'type_deleted_one' or 'type_deleted_many', label, removed), managePayload()
end

function actions.place(source, payload)
    local ok, err = startPlacement(source, payload.type, payload.gangs)

    if not ok then
        return false, err
    end

    TriggerClientEvent('whey_crafting:client:closeTablet', source)

    return true, locale('place_started')
end

function actions.updateTable(source, payload)
    local ok, err = updateTable(payload.id, { type = payload.type, gangs = payload.gangs })

    if not ok then
        return false, err
    end

    log('Bench changed', { player = source, tableId = payload.id })

    return true, locale('bench_updated', payload.id), managePayload()
end

function actions.deleteTable(source, payload)
    local ok, err = removeBench(payload.id)

    if not ok then
        return false, err
    end

    log('Bench removed', { player = source, tableId = payload.id })

    return true, locale('bench_removed', payload.id), managePayload()
end

function actions.teleport(source, payload)
    local craftTable = findTable(payload.id)

    if not craftTable then
        return false, locale('bench_gone')
    end

    teleport(source, craftTable.coords, craftTable.heading)

    return true, locale('teleported_bench', craftTable.id)
end

function actions.placeProp(source, payload)
    local ok, err = startPropPlacement(source, payload.model)

    if not ok then
        return false, err
    end

    TriggerClientEvent('whey_crafting:client:closeTablet', source)

    return true, locale('prop_place_started')
end

function actions.deleteProp(source, payload)
    local ok, err = deleteProp(payload.id)

    if not ok then
        return false, err
    end

    log('Prop removed', { player = source, propId = payload.id })

    return true, locale('prop_deleted', payload.id), managePayload()
end

function actions.teleportProp(source, payload)
    local prop = type(payload.id) == 'number' and props[payload.id]

    if not prop then
        return false, locale('prop_gone')
    end

    teleport(source, prop.coords, prop.heading)

    return true, locale('teleported_prop', prop.id)
end

lib.callback.register('whey_crafting:server:openTablet', function(source)
    if not permissions.canManage(source) then
        return false, locale('no_permission')
    end

    if not ready then
        return false, STARTING_UP
    end

    viewers[source] = true

    return true
end)

lib.callback.register('whey_crafting:server:manage', function(source, name, payload)
    if not permissions.canManage(source) then
        return { ok = false, error = locale('no_permission') }
    end

    if not ready then
        return { ok = false, error = STARTING_UP }
    end

    local action = type(name) == 'string' and actions[name]

    if not action then
        return { ok = false, error = locale('unknown_action') }
    end

    local ok, message, result = action(source, type(payload) == 'table' and payload or {})

    if not ok then
        return { ok = false, error = message or locale('action_failed') }
    end

    return { ok = true, message = message, result = result }
end)

RegisterNetEvent('whey_crafting:server:tabletClosed', function()
    viewers[source] = nil
end)

if config.versionCheck then
    lib.versionCheck(config.repository)
end

AddEventHandler('playerDropped', function()
    viewers[source] = nil
    pendingPlacement[source] = nil
    pendingProps[source] = nil
end)
