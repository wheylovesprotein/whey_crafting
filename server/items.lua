local cache

local function loadData(file)
    local code = LoadResourceFile('ox_inventory', file)

    if not code then
        return {}
    end

    local fn = load(code, ('@@ox_inventory/%s'):format(file), 't', setmetatable({}, { __index = _G }))

    if not fn then
        return {}
    end

    local ok, result = pcall(fn)

    return ok and type(result) == 'table' and result or {}
end

return function()
    if cache then
        return cache
    end

    local list, seen = {}, {}

    local function add(name, definition, kind)
        if type(name) ~= 'string' or seen[name:lower()] then return end

        seen[name:lower()] = true
        list[#list + 1] = {
            name = name,
            label = type(definition) == 'table' and definition.label or name,
            kind = kind,
        }
    end

    for name, definition in pairs(loadData('data/items.lua')) do
        add(name, definition, 'item')
    end

    local weapons = loadData('data/weapons.lua')

    for name, definition in pairs(weapons.Weapons or {}) do
        add(name, definition, 'weapon')
    end

    for name, definition in pairs(weapons.Ammo or {}) do
        add(name, definition, 'ammo')
    end

    for name, definition in pairs(weapons.Components or {}) do
        add(name, definition, 'component')
    end

    table.sort(list, function(a, b) return tostring(a.label):lower() < tostring(b.label):lower() end)

    if #list > 0 then
        cache = list
    end

    return list
end
