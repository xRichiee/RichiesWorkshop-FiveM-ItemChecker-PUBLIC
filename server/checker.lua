ItemChecker = { adapters = {} }

local function finite(value)
    return type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge
end

-- Resolve NUI URLs to resource files. External URLs are deliberately not fetched.
function ItemChecker.resolveImage(base, image)
    local url = image:match('^[%w]+://') and image or (base:gsub('/+$', '') .. '/' .. image)
    local resource, path = url:match('^nui://([^/]+)/(.+)$')
    if not resource then resource, path = url:match('^https?://cfx%-nui%-([^/]+)/(.+)$') end
    if not resource then
        if url:match('^https?://') then return nil, nil, 'remote' end
        return nil, nil, 'unsupported'
    end
    if path:find('[?#%%\\]') or path:find('//', 1, true) then return nil, nil, 'unsupported' end
    for segment in path:gmatch('[^/]+') do
        if segment == '..' or segment == '.' then return nil, nil, 'unsupported' end
    end
    return resource, path
end

function ItemChecker.scan(adapter, options)
    local report = { items = 0, imagesChecked = 0, imagesSkipped = 0, errors = 0, warnings = 0, info = 0, findings = {} }
    local function add(level, item, code, message)
        report[level] = report[level] + 1
        report.findings[#report.findings + 1] = { severity = level, item = tostring(item), code = code, message = message }
    end
    local entries, sourceIssues = adapter.collect(options)
    for _, issue in ipairs(sourceIssues or {}) do add('errors', '(source)', 'source', issue) end
    table.sort(entries, function(a, b) return tostring(a.name) < tostring(b.name) end)
    local names, known = {}, {}
    for _, entry in ipairs(entries) do
        if type(entry.name) == 'string' then known[entry.name] = true end
    end
    local imageCache = {}
    for _, entry in ipairs(entries) do
        local name, item = entry.name, entry.data
        if not options.IgnoreItems[name] then
            report.items = report.items + 1
            if type(name) ~= 'string' or name == '' or name:find('%s') then
                add('errors', name, 'name', 'Item key must be a non-empty string without whitespace.')
            end
            local key = tostring(name):lower()
            if names[key] then add('warnings', name, 'name_collision', 'Name overlaps with ' .. names[key] .. ' (case-insensitive).') end
            names[key] = tostring(name)
            if type(item) ~= 'table' then
                add('errors', name, 'definition', 'Item definition must be a table.')
            else
                if type(item.label) ~= 'string' or not item.label:find('%S') then add('errors', name, 'label', 'Missing or empty label.') end
                for _, field in ipairs({ 'weight', 'consume', 'degrade' }) do
                    local value = item[field]
                    if value ~= nil and (not finite(value) or value < 0) then
                        add('errors', name, field, field .. ' must be a finite, non-negative number.')
                    end
                end
                if item.durability ~= nil then
                    local valid = entry.kind == 'Weapons' and finite(item.durability) and item.durability >= 0
                        or entry.kind ~= 'Weapons' and type(item.durability) == 'boolean'
                    if not valid then add('errors', name, 'durability', entry.kind == 'Weapons'
                        and 'Weapon durability must be a finite, non-negative number.' or 'Item durability must be a boolean.') end
                end
                if finite(item.consume) and item.consume > 1 and item.consume % 1 ~= 0 then
                    add('warnings', name, 'consume', 'consume above 1 should be a whole item count; fractions below 1 consume durability.')
                end
                for _, field in ipairs({ 'stack', 'close', 'decay', 'allowArmed' }) do
                    if item[field] ~= nil and type(item[field]) ~= 'boolean' then add('errors', name, field, field .. ' must be a boolean.') end
                end
                for _, side in ipairs({ 'client', 'server' }) do
                    local value = item[side]
                    if value ~= nil and type(value) ~= 'table' then
                        add('errors', name, side, side .. ' must be a table.')
                    elseif type(value) == 'table' then
                        if value.export ~= nil then
                            if type(value.export) ~= 'string' or not value.export:match('^[^. %s]+%.[^%s]+$') then
                                add('errors', name, side .. '.export', 'Expected resource.exportName.')
                            else
                                local resource = value.export:match('^([^.]+)%.')
                                if adapter.resourceState(resource) ~= 'started' then
                                    add('warnings', name, side .. '.export', 'Export resource is not started: ' .. resource)
                                end
                            end
                        end
                    end
                end
                local client = type(item.client) == 'table' and item.client or {}
                if client.usetime ~= nil and (not finite(client.usetime) or client.usetime < 0) then
                    add('errors', name, 'client.usetime', 'usetime must be finite, non-negative milliseconds.')
                end
                if item.ammoname ~= nil and (type(item.ammoname) ~= 'string' or not known[item.ammoname]) then
                    add('errors', name, 'ammoname', 'Ammo item does not exist: ' .. tostring(item.ammoname))
                end
                local image = client.image
                if image ~= nil and (type(image) ~= 'string' or image == '') then
                    add('errors', name, 'client.image', 'Custom image must be a non-empty string.')
                    report.imagesSkipped = report.imagesSkipped + 1
                else
                    image = image or (tostring(name) .. '.png')
                    local resource, path, reason = ItemChecker.resolveImage(adapter.imagePath(options), image)
                    if not resource then
                        report.imagesSkipped = report.imagesSkipped + 1
                        add(reason == 'remote' and 'info' or 'warnings', name, 'image_unverified', 'Image not verified (' .. reason .. '): ' .. image)
                    else
                        report.imagesChecked = report.imagesChecked + 1
                        local imageKey = resource .. '/' .. path
                        if imageCache[imageKey] == nil then
                            local contents = adapter.readFile(resource, path)
                            imageCache[imageKey] = contents ~= nil and #contents > 0
                        end
                        if not imageCache[imageKey] then add('warnings', name, 'missing_image', 'Missing, empty, or unreadable image: ' .. imageKey) end
                    end
                end
            end
        end
    end
    local priority = { errors = 1, warnings = 2, info = 3 }
    table.sort(report.findings, function(a, b)
        if a.severity ~= b.severity then return priority[a.severity] < priority[b.severity] end
        if a.item ~= b.item then return a.item < b.item end
        if a.code ~= b.code then return a.code < b.code end
        return a.message < b.message
    end)
    return report
end
