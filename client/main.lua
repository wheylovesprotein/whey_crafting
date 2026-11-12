lib.locale()

local config = require 'config.general'
local stations = require 'config.stations'
local limits = require 'shared.limits'

local CONTROL_CONFIRM = 191
local CONTROL_CANCEL = 194
local CONTROL_ROTATE_LEFT = 241
local CONTROL_ROTATE_RIGHT = 242
local CONTROL_FINE_ROTATE = 21
local CONTROL_RAISE = 10
local CONTROL_LOWER = 11
local CONTROL_UNDO = 178
local DISABLED_CONTROLS = { 10, 11, 14, 15, 16, 17, 24, 25, 37, 140, 141, 142, 178, 257, 263 }
local RAY_WORLD = 1
local RAY_WORLD_AND_OBJECTS = 17
local RAISE_METRES_PER_SECOND = 0.5
local MAX_RAISE = 4.0
local BANNER_TXD = 'whey_crafting'

local placement
local session
local types = {}
local tables = {}
local props = {}
local menus = {}
local banners = {}
local bannerLabels = {}
local bannerCount = 0
local bannerTxd = CreateRuntimeTxd(BANNER_TXD)
local nuiReady = false
local tabletOpen = false

local function isIncapacitated()
    local metadata = QBX.PlayerData.metadata

    if not metadata then return true end

    return IsEntityDead(cache.ped) or metadata.isdead or metadata.inlaststand or metadata.ishandcuffed
end

local function inGang(gangs)
    if #gangs == 0 then
        return true
    end

    local gang = QBX.PlayerData.gang
    local name = gang and gang.name

    for i = 1, #gangs do
        if gangs[i] == name then
            return true
        end
    end

    return false
end

local function syncBanners()
    if not nuiReady then return end

    local changed = {}

    for name, tableType in pairs(types) do
        if bannerLabels[name] ~= tableType.label then
            bannerLabels[name] = tableType.label
            changed[#changed + 1] = { name = name, label = tableType.label }
        end
    end

    for name in pairs(bannerLabels) do
        if not types[name] then
            bannerLabels[name] = nil
            banners[name] = nil
        end
    end

    if #changed > 0 then
        SendNUIMessage({ action = 'banners', types = changed })
    end
end

RegisterNUICallback('ready', function(_, cb)
    cb({
        locale = lib.getLocales(),
        limits = limits,
        key = stations.interaction.keyLabel,
        showKey = not stations.interaction.target,
    })
end)

RegisterNUICallback('mounted', function(_, cb)
    cb(1)
    nuiReady = true
    syncBanners()
end)

RegisterNUICallback('banner', function(data, cb)
    cb(1)

    if bannerLabels[data.name] ~= data.label then return end

    bannerCount += 1

    local texture = ('%s_%d'):format(data.name, bannerCount)

    if not CreateRuntimeTextureFromImage(bannerTxd, texture, data.image) then
        return lib.print.warn(('banner for table type %s did not load into a runtime texture'):format(data.name))
    end

    RequestStreamedTextureDict(BANNER_TXD)

    local timeout = GetGameTimer() + 5000

    while not HasStreamedTextureDictLoaded(BANNER_TXD) do
        if GetGameTimer() > timeout then
            return lib.print.warn(('texture dict %s never reported loaded'):format(BANNER_TXD))
        end

        Wait(50)
    end

    if bannerLabels[data.name] == data.label then
        banners[data.name] = texture
    end
end)

local function toWorld(coords, heading, offset)
    local rad = math.rad(heading)
    local sin, cos = math.sin(rad), math.cos(rad)

    return vec3(
        coords.x + offset.x * cos - offset.y * sin,
        coords.y + offset.x * sin + offset.y * cos,
        coords.z + offset.z
    )
end

local function getBannerCorners(coords, heading, offset)
    local halfWidth, halfDepth = stations.banner.width / 2, stations.banner.depth / 2

    return {
        toWorld(coords, heading, offset + vec3(-halfWidth, halfDepth, 0.0)),
        toWorld(coords, heading, offset + vec3(halfWidth, halfDepth, 0.0)),
        toWorld(coords, heading, offset + vec3(halfWidth, -halfDepth, 0.0)),
        toWorld(coords, heading, offset + vec3(-halfWidth, -halfDepth, 0.0)),
    }
end

local function findSurfaceZ(entity, point)
    for _ = 1, 3 do
        local _, entityHit, endCoords = lib.raycast.fromCoords(
            point + vec3(0.0, 0.0, 0.3),
            point - vec3(0.0, 0.0, 0.5),
            16,
            4
        )

        if entityHit == entity then
            return endCoords.z
        end

        Wait(100)
    end
end

local function drawTriangle(texture, alpha, a, b, c, ua, va, ub, vb, uc, vc)
    DrawSpritePoly(
        a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z,
        255, 255, 255, alpha, BANNER_TXD, texture,
        ua, va, 1.0, ub, vb, 1.0, uc, vc, 1.0
    )
end

local function drawBanner(texture, corners, alpha)
    local tl, tr, br, bl = corners[1], corners[2], corners[3], corners[4]

    drawTriangle(texture, alpha, tl, tr, br, 0.0, 0.0, 1.0, 0.0, 1.0, 1.0)
    drawTriangle(texture, alpha, tl, br, bl, 0.0, 0.0, 1.0, 1.0, 0.0, 1.0)
    drawTriangle(texture, alpha, tl, br, tr, 0.0, 0.0, 1.0, 1.0, 1.0, 0.0)
    drawTriangle(texture, alpha, tl, bl, br, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0)
end

local function getBannerAlpha(distance)
    local solid, start = stations.interaction.distance, stations.banner.fadeDistance

    if distance <= solid then
        return 255
    end

    return math.floor(255 * math.max(0.0, (start - distance) / (start - solid)))
end

local function itemData(name)
    local item = exports.ox_inventory:Items(name)

    return {
        name = name,
        label = item and item.label or name,
        weight = item and item.weight or 0,
        image = item and item.client and item.client.image or ('nui://ox_inventory/web/images/%s.png'):format(name),
    }
end

local function getMenu(typeName)
    if menus[typeName] then
        return menus[typeName]
    end

    local tableType = types[typeName]

    if not tableType then return end

    local seen = {}
    local categories, trackedItems = {}, {}

    local function track(name)
        if seen[name] then return end

        seen[name] = true
        trackedItems[#trackedItems + 1] = name
    end

    for i, category in ipairs(tableType.categories) do
        local recipes = {}

        for j, recipe in ipairs(category.recipes) do
            local entry = itemData(recipe.item)
            entry.count = recipe.count or 1
            entry.duration = recipe.duration
            entry.ingredients = {}

            for k, ingredient in ipairs(recipe.ingredients) do
                local data = itemData(ingredient.item)
                data.count = ingredient.count
                entry.ingredients[k] = data
                track(ingredient.item)
            end

            if recipe.blueprint then
                entry.blueprint = itemData(recipe.blueprint)
                track(recipe.blueprint)
            end

            recipes[j] = entry
        end

        categories[i] = { label = category.label, recipes = recipes }
    end

    menus[typeName] = { title = tableType.label, categories = categories, trackedItems = trackedItems }

    return menus[typeName]
end

local function getCounts(menu)
    local trackedItems = menu.trackedItems
    local counts = {}

    for i = 1, #trackedItems do
        local name = trackedItems[i]
        counts[name] = exports.ox_inventory:GetItemCount(name)
    end

    return counts
end

local function closeCrafting()
    if not session then return end

    local current = session
    session = nil

    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })

    if current.cam then
        RenderScriptCams(false, true, stations.camera.transition, true, true)
        DestroyCam(current.cam, false)
    end

    StopAnimTask(cache.ped, stations.workstation.animDict, stations.workstation.animClip, 1.0)
    RemoveAnimDict(stations.workstation.animDict)
end

local function canUse(tableId)
    local entry = tables[tableId]

    return entry ~= nil and inGang(entry.gangs)
end

local function openCrafting(craftTable)
    local menu = getMenu(craftTable.tableType)

    if not menu then return end

    local current = { tableId = craftTable.tableId, menu = menu }
    session = current

    local queue, cooldowns = lib.callback.await('whey_crafting:server:getQueue', false, current.tableId)

    if session ~= current then return end

    if not queue then
        session = nil
        return lib.notify({ type = 'error', description = cooldowns or locale('cannot_use') })
    end

    local workstation = stations.workstation
    local stand = toWorld(craftTable.tableCoords, craftTable.heading, workstation.standOffset)
    local timeout = GetGameTimer() + 2000

    TaskGoStraightToCoord(cache.ped, stand.x, stand.y, stand.z, 1.0, 2000, craftTable.heading, 0.05)

    while session == current and GetGameTimer() < timeout and #(GetEntityCoords(cache.ped).xy - stand.xy) > 0.15 do
        Wait(50)
    end

    if session ~= current then return end

    SetEntityHeading(cache.ped, craftTable.heading)
    lib.requestAnimDict(workstation.animDict)
    TaskPlayAnim(cache.ped, workstation.animDict, workstation.animClip, 4.0, 4.0, -1, 1, 0, false, false, false)

    local camCoords = toWorld(craftTable.tableCoords, craftTable.heading, stations.camera.offset)
    local target = toWorld(craftTable.tableCoords, craftTable.heading, stations.camera.target)
    local cam = CreateCamWithParams(
        'DEFAULT_SCRIPTED_CAMERA',
        camCoords.x,
        camCoords.y,
        camCoords.z,
        0.0,
        0.0,
        0.0,
        stations.camera.fov,
        false,
        0
    )

    PointCamAtCoord(cam, target.x, target.y, target.z)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, stations.camera.transition, true, true)
    current.cam = cam

    SendNUIMessage({
        action = 'open',
        title = current.menu.title,
        categories = current.menu.categories,
        counts = getCounts(current.menu),
        queue = queue,
        cooldowns = cooldowns,
        maxWeight = config.maxCraftWeight,
        queueSize = config.queueSize,
    })
    SetNuiFocus(true, true)

    local anchor = GetEntityCoords(cache.ped).xy

    while session == current do
        local moved = #(GetEntityCoords(cache.ped).xy - anchor) > 1.0

        if isIncapacitated() or cache.vehicle or moved or not canUse(current.tableId) then
            closeCrafting()
        end

        Wait(250)
    end
end

RegisterNUICallback('close', function(_, cb)
    cb(1)
    closeCrafting()
end)

RegisterNUICallback('craft', function(data, cb)
    local current = session

    if not current then
        return cb(false)
    end

    local queue, cooldowns = lib.callback.await(
        'whey_crafting:server:craft',
        false,
        current.tableId,
        data.recipe,
        math.tointeger(data.amount)
    )

    if not queue then
        lib.notify({ type = 'error', description = cooldowns or locale('craft_refused') })
        return cb(false)
    end

    cb({ queue = queue, cooldowns = cooldowns, counts = getCounts(current.menu) })
end)

RegisterNUICallback('collect', function(data, cb)
    local current = session

    if not current then
        return cb(false)
    end

    local queue, cooldowns = lib.callback.await('whey_crafting:server:collect', false, current.tableId, data.id)

    if not queue then
        lib.notify({ type = 'error', description = cooldowns or locale('collect_refused') })
        return cb(false)
    end

    cb({ queue = queue, cooldowns = cooldowns, counts = getCounts(current.menu) })
end)

RegisterNUICallback('cancel', function(data, cb)
    local current = session

    if not current then
        return cb(false)
    end

    local queue, cooldowns = lib.callback.await('whey_crafting:server:cancel', false, current.tableId, data.id)

    if not queue then
        lib.notify({ type = 'error', description = cooldowns or locale('cancel_refused') })
        return cb(false)
    end

    cb({ queue = queue, cooldowns = cooldowns, counts = getCounts(current.menu) })
end)

local function deletePointProp(point)
    if point.entity and DoesEntityExist(point.entity) then
        DeleteEntity(point.entity)
    end

    point.entity = nil
    point.loading = nil
end

local function createProp(coords, heading, name)
    local model = lib.requestModel(name or stations.model)
    local entity = CreateObjectNoOffset(model, coords.x, coords.y, coords.z, false, false, false)
    SetModelAsNoLongerNeeded(model)
    SetEntityHeading(entity, heading)
    FreezeEntityPosition(entity, true)

    return entity
end

local function removeTable(id)
    local entry = tables[id]

    if not entry then return end

    if entry.zone then
        exports.ox_target:removeZone(entry.zone)
    end

    entry.render:remove()
    entry.interact:remove()
    deletePointProp(entry.render)
    tables[id] = nil
end

local function startCrafting(point)
    if session or placement or tabletOpen or cache.vehicle or not nuiReady or isIncapacitated() then return end

    CreateThread(function()
        local ok, err = pcall(openCrafting, point)

        if not ok then
            closeCrafting()
            error(err)
        end
    end)
end

local function addTable(craftTable)
    removeTable(craftTable.id)

    local bannerCenter = toWorld(craftTable.coords, craftTable.heading, stations.banner.offset)
    local entry = {
        banner = getBannerCorners(craftTable.coords, craftTable.heading, stations.banner.offset),
        gangs = craftTable.gangs,
    }

    entry.render = lib.points.new({
        coords = craftTable.coords,
        distance = stations.renderDistance,
        heading = craftTable.heading,
        onEnter = function(self)
            local token = {}
            self.loading = token

            CreateThread(function()
                local entity = createProp(self.coords, self.heading)

                if self.loading ~= token or tables[craftTable.id] ~= entry then
                    DeleteEntity(entity)
                    return
                end

                self.entity = entity

                local surfaceZ = findSurfaceZ(entity, bannerCenter)

                if surfaceZ and tables[craftTable.id] == entry then
                    local offset = stations.banner.offset
                    local flush = vec3(offset.x, offset.y, surfaceZ - craftTable.coords.z + 0.005)

                    entry.banner = getBannerCorners(craftTable.coords, craftTable.heading, flush)
                end
            end)
        end,
        onExit = deletePointProp,
    })

    entry.interact = lib.points.new({
        coords = bannerCenter,
        distance = math.max(stations.banner.fadeDistance, stations.interaction.distance),
        tableId = craftTable.id,
        tableType = craftTable.type,
        tableCoords = craftTable.coords,
        heading = craftTable.heading,
        nearby = function(self)
            if session or not inGang(entry.gangs) then return end

            local distance = #(GetEntityCoords(cache.ped) - self.coords)
            local texture = banners[craftTable.type]

            if texture then
                local alpha = getBannerAlpha(distance)

                if alpha > 0 then
                    drawBanner(texture, entry.banner, alpha)
                end
            end

            if stations.interaction.target or distance > stations.interaction.distance then return end

            if not IsControlJustReleased(0, stations.interaction.control) then return end

            startCrafting(self)
        end,
    })

    if stations.interaction.target then
        entry.zone = exports.ox_target:addSphereZone({
            coords = bannerCenter,
            radius = stations.interaction.distance,
            options = {
                {
                    name = ('whey_crafting:%d'):format(craftTable.id),
                    icon = 'fa-solid fa-hammer',
                    label = locale('target_open'),
                    distance = stations.interaction.distance + 1.0,
                    canInteract = function()
                        return not session and not placement and inGang(entry.gangs)
                    end,
                    onSelect = function()
                        startCrafting(entry.interact)
                    end,
                },
            },
        })
    end

    tables[craftTable.id] = entry
end

local function setTables(list)
    for id in pairs(tables) do
        removeTable(id)
    end

    for i = 1, #list do
        addTable(list[i])
    end
end

local function removePlacedProp(id)
    local point = props[id]

    if not point then return end

    point:remove()
    deletePointProp(point)
    props[id] = nil
end

local function waitForInterior(point, token)
    local coords = point.coords
    local interior = GetInteriorAtCoords(coords.x, coords.y, coords.z)

    if interior == 0 then return end

    while point.loading == token and not IsInteriorReady(interior) do
        Wait(250)
    end
end

local function addPlacedProp(prop)
    removePlacedProp(prop.id)

    if not IsModelInCdimage(joaat(prop.model)) then
        return lib.print.warn(('prop #%d uses "%s", which is not a model in the game'):format(prop.id, prop.model))
    end

    props[prop.id] = lib.points.new({
        coords = prop.coords,
        distance = stations.propRenderDistance,
        heading = prop.heading,
        model = prop.model,
        onEnter = function(self)
            local token = {}
            self.loading = token

            CreateThread(function()
                waitForInterior(self, token)

                if self.loading ~= token then return end

                local entity = createProp(self.coords, self.heading, self.model)

                if self.loading ~= token then
                    DeleteEntity(entity)
                    return
                end

                self.entity = entity
            end)
        end,
        onExit = deletePointProp,
    })
end

local function setPlacedProps(list)
    for id in pairs(props) do
        removePlacedProp(id)
    end

    for i = 1, #list do
        addPlacedProp(list[i])
    end
end

local function startProbe()
    local camCoords = GetFinalRenderedCamCoord()
    local rot = GetFinalRenderedCamRot(2)
    local pitch, yaw = math.rad(rot.x), math.rad(rot.z)
    local flat = math.abs(math.cos(pitch))
    local direction = vec3(-math.sin(yaw) * flat, math.cos(yaw) * flat, math.sin(pitch))
    local dest = camCoords + direction * stations.placement.rayLength

    return StartShapeTestLosProbe(
        camCoords.x,
        camCoords.y,
        camCoords.z,
        dest.x,
        dest.y,
        dest.z,
        placement.ray,
        cache.ped,
        4
    )
end

local function setValid(valid)
    if placement.valid == valid then return end

    placement.valid = valid

    if valid then
        SetEntityDrawOutlineColor(80, 220, 100, 255)
    else
        SetEntityDrawOutlineColor(230, 70, 70, 255)
    end
end

local function stopPlacement()
    if not placement then return end

    if DoesEntityExist(placement.entity) then
        DeleteEntity(placement.entity)
    end

    placement = nil
    lib.hideTextUI()
end

local function confirmPlacement()
    local coords, heading = placement.coords, placement.heading
    stopPlacement()

    local id, err = lib.callback.await('whey_crafting:server:saveTable', false, coords, heading)

    if id then
        lib.notify({ type = 'success', description = locale('table_saved', id) })
    else
        lib.notify({ type = 'error', description = err or locale('table_save_failed') })
    end
end

local function saveProp(coords, heading)
    CreateThread(function()
        local id, err = lib.callback.await('whey_crafting:server:saveProp', false, coords, heading)

        if id then
            lib.notify({ id = 'whey_crafting:prop', type = 'success', description = locale('prop_saved', id) })
        else
            lib.notify({ type = 'error', description = err or locale('prop_save_failed') })
        end
    end)
end

local function undoProp()
    CreateThread(function()
        local id, err = lib.callback.await('whey_crafting:server:undoProp', false)

        if id then
            lib.notify({ id = 'whey_crafting:prop', type = 'inform', description = locale('prop_removed', id) })
        else
            lib.notify({ type = 'error', description = err or locale('undo_failed') })
        end
    end)
end

local function runPropControls()
    local step = RAISE_METRES_PER_SECOND * GetFrameTime()

    if IsDisabledControlPressed(0, CONTROL_RAISE) then
        placement.raise = math.min(placement.raise + step, MAX_RAISE)
    elseif IsDisabledControlPressed(0, CONTROL_LOWER) then
        placement.raise = math.max(placement.raise - step, -MAX_RAISE)
    end

    if IsDisabledControlJustPressed(0, CONTROL_UNDO) then
        undoProp()
    end

    placement.coords = placement.aim + vec3(0.0, 0.0, placement.lift + placement.raise)
end

local function runPlacement()
    local current = placement
    local probe = startProbe()

    while placement == current do
        for i = 1, #DISABLED_CONTROLS do
            DisableControlAction(0, DISABLED_CONTROLS[i], true)
        end

        local status, hit, endCoords = GetShapeTestResult(probe)

        if status ~= 1 then
            if status == 2 then
                local inRange = hit == 1 and #(endCoords - GetEntityCoords(cache.ped)) <= stations.placement.maxDistance

                if inRange then
                    placement.aim = endCoords
                    placement.coords = endCoords
                end

                setValid(inRange)
            end

            probe = startProbe()
        end

        if placement.isProp then
            runPropControls()
        end

        local step = stations.placement.rotateStep

        if IsDisabledControlPressed(0, CONTROL_FINE_ROTATE) then
            step = stations.placement.fineRotateStep
        end

        if IsDisabledControlJustPressed(0, CONTROL_ROTATE_LEFT) then
            placement.heading = (placement.heading + step) % 360
        elseif IsDisabledControlJustPressed(0, CONTROL_ROTATE_RIGHT) then
            placement.heading = (placement.heading - step) % 360
        end

        SetEntityCoordsNoOffset(
            placement.entity,
            placement.coords.x,
            placement.coords.y,
            placement.coords.z,
            false,
            false,
            false
        )
        SetEntityHeading(placement.entity, placement.heading)

        if IsDisabledControlJustPressed(0, CONTROL_CANCEL) then
            local wasProp = placement.isProp

            stopPlacement()

            if wasProp then
                lib.callback.await('whey_crafting:server:stopProps', false)
                lib.notify({ type = 'inform', description = locale('props_finished') })
            else
                lib.notify({ type = 'inform', description = locale('placement_cancelled') })
            end
        elseif IsDisabledControlJustPressed(0, CONTROL_CONFIRM) then
            if placement.valid and placement.isProp then
                saveProp(placement.coords, placement.heading)
            elseif placement.valid then
                confirmPlacement()
            else
                lib.notify({ type = 'error', description = locale('aim_closer') })
            end
        end

        Wait(0)
    end
end

RegisterNetEvent('whey_crafting:client:startPlacement', function()
    if placement or session then return end

    local coords = GetOffsetFromEntityInWorldCoords(cache.ped, 0.0, 1.5, -1.0)
    local step = stations.placement.rotateStep
    local heading = math.floor(GetEntityHeading(cache.ped) / step + 0.5) * step % 360
    local entity = createProp(coords, heading)

    SetEntityCollision(entity, false, false)
    SetEntityAlpha(entity, 200, false)
    SetEntityDrawOutline(entity, true)

    placement = {
        entity = entity,
        coords = coords,
        heading = heading,
        ray = RAY_WORLD,
    }

    setValid(false)

    lib.showTextUI(locale('placement_help'))
    runPlacement()
end)

RegisterNetEvent('whey_crafting:client:startPropPlacement', function(model)
    local problem

    if (placement and not placement.isProp) or session then
        problem = locale('finish_first')
    elseif not IsModelInCdimage(joaat(model)) then
        problem = locale('model_missing', model)
    end

    if problem then
        if placement and placement.isProp then
            stopPlacement()
        end

        lib.callback.await('whey_crafting:server:stopProps', false)
        return lib.notify({ type = 'error', description = problem })
    end

    stopPlacement()

    local coords = GetOffsetFromEntityInWorldCoords(cache.ped, 0.0, 1.5, -1.0)
    local step = stations.placement.rotateStep
    local heading = math.floor(GetEntityHeading(cache.ped) / step + 0.5) * step % 360
    local entity = createProp(coords, heading, model)
    local bottom = GetModelDimensions(joaat(model))

    SetEntityCollision(entity, false, false)
    SetEntityAlpha(entity, 200, false)
    SetEntityDrawOutline(entity, true)

    placement = {
        entity = entity,
        coords = coords,
        aim = coords,
        heading = heading,
        ray = RAY_WORLD_AND_OBJECTS,
        isProp = true,
        lift = -bottom.z,
        raise = 0.0,
    }

    setValid(false)

    lib.showTextUI(locale('prop_placement_help'))
    runPlacement()
end)

local function setTypes(list)
    types = list
    menus = {}
    syncBanners()
end

RegisterNetEvent('whey_crafting:client:setTypes', setTypes)
RegisterNetEvent('whey_crafting:client:setTables', setTables)
RegisterNetEvent('whey_crafting:client:addTable', addTable)
RegisterNetEvent('whey_crafting:client:removeTable', removeTable)
RegisterNetEvent('whey_crafting:client:setProps', setPlacedProps)
RegisterNetEvent('whey_crafting:client:addProp', addPlacedProp)
RegisterNetEvent('whey_crafting:client:removeProp', removePlacedProp)

CreateThread(function()
    local list, syncedTypes = lib.callback.await('whey_crafting:server:getTables', false)

    if list then
        setTypes(syncedTypes)
        setTables(list)
    end

    lib.callback.await('whey_crafting:server:getProps', false)
end)

local BLOCKED_CONTROLS = { 1, 2, 24, 25, 37, 44, 45, 140, 141, 142, 143, 199, 200, 257, 263, 264 }

local function blockControls()
    while tabletOpen do
        for i = 1, #BLOCKED_CONTROLS do
            DisableControlAction(0, BLOCKED_CONTROLS[i], true)
        end

        Wait(0)
    end

    local untilTime = GetGameTimer() + 300

    while GetGameTimer() < untilTime do
        DisableControlAction(0, 199, true)
        DisableControlAction(0, 200, true)
        Wait(0)
    end
end

local function closeTablet()
    if not tabletOpen then return end

    tabletOpen = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'tablet', visible = false })
    TriggerServerEvent('whey_crafting:server:tabletClosed')
end

local function openTablet()
    if tabletOpen or session or placement or not nuiReady then return end

    local ok, err = lib.callback.await('whey_crafting:server:openTablet', false)

    if not ok then
        return lib.notify({ type = 'error', description = err or locale('no_permission') })
    end

    if session or placement then
        return TriggerServerEvent('whey_crafting:server:tabletClosed')
    end

    tabletOpen = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(true)
    SendNUIMessage({ action = 'tablet', visible = true })
    CreateThread(blockControls)
end

local function toggleTablet()
    if tabletOpen then
        closeTablet()
    else
        openTablet()
    end
end

exports('openTablet', openTablet)

if config.tablet.command then
    RegisterCommand(config.tablet.command, toggleTablet, false)

    if config.tablet.keybind ~= '' then
        RegisterKeyMapping(config.tablet.command, locale('keybind_tablet'), 'keyboard', config.tablet.keybind)
    end
end

RegisterNetEvent('whey_crafting:client:closeTablet', closeTablet)

RegisterNetEvent('whey_crafting:client:dirty', function()
    if tabletOpen then
        SendNUIMessage({ action = 'dirty' })
    end
end)

RegisterNUICallback('closeTablet', function(_, cb)
    cb(1)
    closeTablet()
end)

RegisterNUICallback('typing', function(data, cb)
    cb(1)

    if tabletOpen then
        SetNuiFocusKeepInput(not data.typing)
    end
end)

RegisterNUICallback('request', function(data, cb)
    if not tabletOpen then
        return cb({ ok = false, error = locale('action_failed') })
    end

    local response = lib.callback.await('whey_crafting:server:manage', false, data.action, data.payload)

    cb(response or { ok = false, error = locale('action_failed') })
end)

RegisterNUICallback('myCoords', function(_, cb)
    local coords = GetEntityCoords(cache.ped)

    cb({ x = coords.x, y = coords.y, z = coords.z })
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end

    closeTablet()
    closeCrafting()
    stopPlacement()
    SetStreamedTextureDictAsNoLongerNeeded(BANNER_TXD)

    for _, entry in pairs(tables) do
        deletePointProp(entry.render)
    end

    for _, point in pairs(props) do
        deletePointProp(point)
    end
end)
