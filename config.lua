Config = {
    Command = 'itemcheck',
    Adapter = 'ox_inventory',
    InventoryResource = 'ox_inventory',
    IncludeWeapons = true,
    -- Optional automatic console report when this resource starts.
    ScanOnStart = false,
    -- Maximum findings printed per command. Use `itemcheck all` for everything.
    MaxFindings = 100,
    CooldownSeconds = 10,
    -- Item names to exclude entirely (for intentional placeholders, etc.).
    IgnoreItems = {},
    -- Optional override; nil uses the inventory:imagepath convar.
    ImagePath = nil,
}
