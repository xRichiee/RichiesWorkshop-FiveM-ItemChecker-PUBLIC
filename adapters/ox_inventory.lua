local adapter = {}
ItemChecker.adapters.ox_inventory = adapter

adapter.readFile = LoadResourceFile
adapter.resourceState = GetResourceState

function adapter.imagePath(options)
    return options.ImagePath or GetConvar('inventory:imagepath', 'nui://ox_inventory/web/images')
end

-- Evaluate only data declarations. No exports, file APIs, events, or shared global
-- tables are available here. Callbacks are created but never invoked.
local function readDefinitions(resource, path)
    local source = LoadResourceFile(resource, path)
    if not source then return nil, 'Cannot read ' .. resource .. '/' .. path end
    local env = { vec3 = vec3, vec4 = vec4, vector3 = vector3, vector4 = vector4, joaat = joaat }
    local chunk, err = load(source, '@' .. resource .. '/' .. path, 't', env)
    if not chunk then return nil, 'Cannot compile ' .. path .. ': ' .. tostring(err) end
    -- FiveM's sandbox may omit debug.sethook. Apply a budget only where supported.
    -- A dedicated coroutine keeps the command thread's debugger/profiler hook intact.
    local thread = coroutine.create(chunk)
    local sethook = debug and debug.sethook
    if type(sethook) == 'function' then
        sethook(thread, function() error('Definition evaluation exceeded instruction budget.') end, '', 1000000)
    end
    local ok, result = coroutine.resume(thread)
    if type(sethook) == 'function' then sethook(thread) end
    if ok and coroutine.status(thread) ~= 'dead' then return nil, 'Definition evaluation unexpectedly yielded: ' .. path end
    if not ok then return nil, 'Cannot evaluate ' .. path .. ': ' .. tostring(result) end
    if type(result) ~= 'table' then return nil, path .. ' must return a table.' end
    return result
end

function adapter.collect(options)
    local entries, issues = {}, {}
    local resource = options.InventoryResource
    if GetResourceState(resource) ~= 'started' then
        return entries, { 'Inventory resource is not started: ' .. resource }
    end
    local function append(path, grouped)
        local data, err = readDefinitions(resource, path)
        if not data then issues[#issues + 1] = err; return end
        local function group(items, origin, kind)
            if type(items) ~= 'table' then issues[#issues + 1] = origin .. ' must be a table.'; return end
            for name, item in pairs(items) do entries[#entries + 1] = { name = name, data = item, kind = kind } end
        end
        if grouped then
            for _, name in ipairs({ 'Weapons', 'Ammo', 'Components', 'Tints' }) do
                if data[name] ~= nil then group(data[name], path .. ':' .. name, name) end
            end
        else group(data, path) end
    end
    append('data/items.lua', false)
    if options.IncludeWeapons then append('data/weapons.lua', true) end
    return entries, issues
end
