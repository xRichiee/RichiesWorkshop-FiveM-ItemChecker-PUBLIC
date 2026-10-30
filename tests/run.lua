-- Run from the project root with Lua 5.4: lua tests/run.lua
local passed = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if not ok then error(name .. ': ' .. tostring(err)) end
    passed = passed + 1
    print('PASS ' .. name)
end
local function eq(actual, expected)
    assert(actual == expected, ('expected %s, got %s'):format(tostring(expected), tostring(actual)))
end

dofile('config.lua')
dofile('server/checker.lua')
local function scan(entries, files, issues)
    return ItemChecker.scan({
        collect = function() return entries, issues end,
        resourceState = function(resource) return resource == 'running' and 'started' or 'missing' end,
        imagePath = function() return 'nui://ox_inventory/web/images' end,
        readFile = function(resource, path) return (files or {})[resource .. '/' .. path] end,
    }, Config)
end
local function has(report, code, name)
    for _, finding in ipairs(report.findings) do
        if finding.code == code and (not name or finding.item == name) then return true end
    end
    return false
end

test('ox defaults and fractional consumption are valid; definitions stay unchanged', function()
    local item = { label = 'Water', consume = 0.2, durability = true }
    local report = scan({ { name = 'water', data = item } }, { ['ox_inventory/web/images/water.png'] = 'png' })
    eq(report.errors, 0); eq(report.warnings, 0); eq(report.imagesChecked, 1)
    eq(item.weight, nil); eq(item.client, nil); eq(item.consume, 0.2)
end)

test('custom image, cross-resource image, remote URL, and default weapon image', function()
    local report = scan({
        { name = 'id', data = { label = 'ID', client = { image = 'card.webp' } } },
        { name = 'bank', data = { label = 'Bank', client = { image = 'https://cfx-nui-icons/cards/bank.png' } } },
        { name = 'remote', data = { label = 'Remote', client = { image = 'https://example.org/image.png' } } },
        { name = 'WEAPON_TEST', kind = 'Weapons', data = { label = 'Test', durability = 0.03 } },
    }, { ['ox_inventory/web/images/card.webp'] = 'webp', ['icons/cards/bank.png'] = 'png', ['ox_inventory/web/images/WEAPON_TEST.png'] = 'png' })
    eq(report.errors, 0); eq(report.warnings, 0); eq(report.info, 1)
    eq(report.imagesChecked, 3); eq(report.imagesSkipped, 1)
end)

test('missing and empty images list affected items', function()
    local report = scan({ { name = 'missing', data = { label = 'Missing' } }, { name = 'empty', data = { label = 'Empty' } } },
        { ['ox_inventory/web/images/empty.png'] = '' })
    eq(report.warnings, 2); assert(has(report, 'missing_image', 'missing')); assert(has(report, 'missing_image', 'empty'))
end)

test('malformed definitions and non-finite numeric fields do not crash', function()
    local report = scan({
        { name = 1, data = false },
        { name = 'bad name', data = { label = '', weight = -1, stack = 'false', close = 1, client = false, server = 'bad' } },
        { name = 'bad', data = { label = 'Bad', consume = 0/0, degrade = math.huge, durability = 'bad', client = { image = false, usetime = -1 } } },
    })
    assert(report.errors >= 12); assert(has(report, 'name')); assert(has(report, 'definition'))
    assert(has(report, 'client.image')); assert(has(report, 'consume')); assert(has(report, 'degrade'))
end)

test('collisions, missing ammo, malformed exports, stopped export resources', function()
    local report = scan({
        { name = 'Water', data = { label = 'Water' } },
        { name = 'water', data = { label = 'Water', server = { export = 'stopped.use' } } },
        { name = 'gun', data = { label = 'Gun', ammoname = 'missing-ammo', client = { export = 'broken' } } },
        { name = 'ok', data = { label = 'OK', server = { export = 'running.use' } } },
    })
    assert(has(report, 'name_collision')); assert(has(report, 'ammoname')); assert(has(report, 'client.export'))
    assert(has(report, 'server.export', 'water')); assert(not has(report, 'server.export', 'ok'))
end)

test('ignore list excludes items and findings', function()
    Config.IgnoreItems.ignored = true
    local report = scan({ { name = 'ignored', data = false } })
    eq(report.items, 0); eq(#report.findings, 0)
    Config.IgnoreItems.ignored = nil
end)

test('unsafe or unresolvable local image paths are not read', function()
    for _, image in ipairs({ '../secret.png', 'nested/../secret.png', 'nui://icons/a%20b.png', 'nui://icons/a.png?x=1', 'file://icons/a.png' }) do
        local resource = ItemChecker.resolveImage('nui://ox_inventory/web/images', image)
        eq(resource, nil)
    end
end)

local files, state = {}, 'started'
function LoadResourceFile(resource, path) return files[resource .. '/' .. path] end
function GetResourceState() return state end
function GetConvar(_, default) return default end
dofile('adapters/ox_inventory.lua')
local adapter = ItemChecker.adapters.ox_inventory

test('adapter reads item and weapon groups without invoking callbacks', function()
    files['ox_inventory/data/items.lua'] = [[return { bread = { label = 'Bread', client = { image = 'bread.webp', add = function() error('must not run') end } } }]]
    files['ox_inventory/data/weapons.lua'] = [[return { Weapons = { WEAPON_TEST = { label = 'Test' } }, Ammo = { ammo = { label = 'Ammo' } } }]]
    local entries, issues = adapter.collect(Config)
    eq(#entries, 3); eq(#issues, 0)
    local report = ItemChecker.scan(adapter, Config)
    eq(report.errors, 0); eq(report.items, 3)
end)

test('adapter reports missing, broken, unsupported-global and looping data sources', function()
    local beforeHook, beforeMask, beforeCount = debug.gethook()
    for _, source in ipairs({ 'return {', 'return 42', 'return exports.foo:GetItems()', 'while true do end' }) do
        files['ox_inventory/data/items.lua'] = source
        local _, issues = adapter.collect(Config)
        eq(#issues, 1)
        local hook, mask, count = debug.gethook()
        eq(hook, beforeHook); eq(mask, beforeMask); eq(count, beforeCount)
    end
    files['ox_inventory/data/items.lua'] = nil
    local _, issues = adapter.collect(Config)
    eq(#issues, 1)
end)

test('FiveM sandbox without debug hooks can still scan and report source errors', function()
    local originalDebug = debug
    local ok, err = pcall(function()
        for _, sandbox in ipairs({ {}, { traceback = originalDebug.traceback }, false }) do
            debug = sandbox or nil
            files['ox_inventory/data/items.lua'] = [[return { fixture = { label = 'Fixture', weight = -1, stack = 'false', client = { image = 'missing.png' } } }]]
            local report = ItemChecker.scan(adapter, Config)
            assert(has(report, 'weight', 'fixture'))
            assert(has(report, 'stack', 'fixture'))
            assert(has(report, 'missing_image', 'fixture'))
            files['ox_inventory/data/items.lua'] = 'return exports.foo:GetItems()'
            local _, issues = adapter.collect(Config)
            eq(#issues, 1)
        end
    end)
    debug = originalDebug
    assert(ok, err)
end)

test('stopped inventory is reported as a source error', function()
    state = 'stopped'
    local report = ItemChecker.scan(adapter, Config)
    eq(report.errors, 1); eq(report.items, 0)
    state = 'started'
end)

test('command is ACE restricted; output, cooldown, truncation and server export work', function()
    files['ox_inventory/data/items.lua'] = [[return { bread = { label = 'Bread' } }]]
    local command, exported, output = nil, nil, {}
    function RegisterCommand(name, callback, restricted)
        eq(name, 'itemcheck'); eq(restricted, true); command = callback
    end
    exports = function(name, callback) eq(name, 'Scan'); exported = callback end
    local oldPrint = print
    print = function(line) output[#output + 1] = line end
    dofile('server/main.lua')
    Config.MaxFindings = 1
    command(0, {})
    assert(output[1]:find('3 items', 1, true)); assert(output[#output]:find('more findings', 1, true))
    command(0, {})
    assert(output[#output]:find('Please wait', 1, true))
    local report = exported(); eq(report.items, 3)
    print = oldPrint
end)

print(('%d tests passed.'):format(passed))
