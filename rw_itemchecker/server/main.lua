local lastRun
local function clean(value)
    return tostring(value):gsub('%c', ' '):gsub('%^%d', '')
end

local function run(showAll)
    local now = os.time()
    if lastRun and now - lastRun < Config.CooldownSeconds then
        print('[ItemChecker] Please wait before running another scan.')
        return
    end
    lastRun = now
    local adapter = ItemChecker.adapters[Config.Adapter]
    if not adapter then print('[ItemChecker] Unknown adapter: ' .. clean(Config.Adapter)); return end
    local ok, report = pcall(ItemChecker.scan, adapter, Config)
    if not ok then print('[ItemChecker] Scan failed: ' .. clean(report)); return end
    print(('[ItemChecker] %s | %d items | %d errors | %d warnings | %d informational | images: %d checked, %d skipped'):format(
        report.errors > 0 and 'INCOMPLETE / ERRORS' or 'COMPLETE', report.items, report.errors, report.warnings, report.info,
        report.imagesChecked, report.imagesSkipped))
    local limit = showAll and #report.findings or math.max(0, Config.MaxFindings)
    for index = 1, math.min(limit, #report.findings) do
        local finding = report.findings[index]
        print(('[ItemChecker] [%s] %s | %s | %s'):format(finding.severity:upper(), clean(finding.item), finding.code, clean(finding.message)))
    end
    if #report.findings > limit then
        print(('[ItemChecker] %d more findings. Run %s all to display everything.'):format(#report.findings - limit, Config.Command))
    end
end

RegisterCommand(Config.Command, function(source, args)
    if args[1] and args[1] ~= 'all' then print('[ItemChecker] Usage: ' .. Config.Command .. ' [all]'); return end
    run(args[1] == 'all')
    if source > 0 then TriggerClientEvent('chat:addMessage', source, { args = { 'ItemChecker', 'See the server console for checker output.' } }) end
end, true)

-- Server-side only; no network event is registered for scans.
exports('Scan', function()
    local adapter = assert(ItemChecker.adapters[Config.Adapter], 'Unknown item checker adapter')
    return ItemChecker.scan(adapter, Config)
end)

if Config.ScanOnStart then
    CreateThread(function()
        Wait(1000)
        run(false)
    end)
end
