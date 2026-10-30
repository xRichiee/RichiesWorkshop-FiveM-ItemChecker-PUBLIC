# Richie's Workshop — FiveM Item Checker

A read-only, server-side resource for checking **ox_inventory item definitions on Qbox servers**. No database, client scripts, ox_lib dependency, or configuration edits required. Other frameworks running the same ox_inventory data format can use it too; there is no framework-specific code.

Reports include item names, severity, field/check code, and an explanation. Scans never save files, change inventory items, execute item callbacks, or fetch external URLs.

## Installation

1. Copy this folder into your server's resources as `rw_itemchecker`.
2. Add this after your inventory startup in `server.cfg`:

```cfg
ensure ox_inventory
ensure rw_itemchecker

# Optional: allow your admin group to run /itemcheck in game.
add_ace group.admin command.itemcheck allow
```

The server console can always run the command. In-game access uses FiveM's restricted command ACE check; Qbox permissions do not automatically grant it. The report appears in the **server console**, with a brief chat notice for in-game callers if your server has chat enabled.

## Usage

```text
itemcheck         # Summary and up to 100 findings
itemcheck all     # Every finding
```

Use `/itemcheck` in game. Wait 10 seconds between commands. Defaults can be adjusted in `config.lua`; automatic startup scans are off. No scan writes a report file: copy the console output if you want to save it.

Example output:

```text
[ItemChecker] COMPLETE | 241 items | 0 errors | 2 warnings | 0 informational | images: 241 checked, 0 skipped
[ItemChecker] [WARNINGS] custom_burger | missing_image | Missing, empty, or unreadable image: ox_inventory/web/images/custom_burger.png
[ItemChecker] [WARNINGS] repairkit | server.export | Export resource is not started: mechanic
```

`COMPLETE` means all selected sources were read and no errors were found; review warnings too. `INCOMPLETE / ERRORS` means a source could not be checked or an invalid setting was found. Remote images are explicitly listed as unverified informational findings, never treated as confirmed working images.

## Checks

- Missing, empty, or unreadable default `<item>.png` and custom `client.image` files.
- Custom image directories from `inventory:imagepath`, NUI URLs, and `https://cfx-nui-...` resource URLs.
- Missing labels, malformed item keys/tables, and case-insensitive name collisions.
- Invalid weights, consumption, degradation, durability, booleans, and use times.
- Invalid client/server table shapes and export strings; export resources that are not started.
- Weapon ammo references that do not name a defined item.

Omitted weight, stack, close, and consume settings are allowed because ox_inventory supplies defaults. Fractional consumption below 1 is valid durability consumption. Weapons, ammo, components, and tints are included by default.

To ignore intentional placeholders:

```lua
IgnoreItems = {
    ['placeholder'] = true,
},
```

For a renamed inventory, set `InventoryResource` and configure its actual image directory through `ImagePath` or the `inventory:imagepath` convar. The normal image base is `nui://ox_inventory/web/images`.

## Scope and limitations

The adapter reads `data/items.lua` and optionally `data/weapons.lua` from the running inventory resource. It evaluates the returned tables in an isolated environment with vector constructors and `joaat`; callbacks are never called. An instruction budget applies where the runtime exposes `debug.sethook`. FiveM runtimes that omit this function evaluate without that budget, so scan trusted server definitions only; a loop in a definition can stall the scan. Custom files depending on other top-level globals or helpers produce a visible source error instead of silently skipping validation. FiveM Lua syntax, including backtick hashes, is supported by the FiveM runtime.

This checks **definitions on disk**, so changes saved since the last inventory restart may differ from active items. It does not enumerate live player slots, metadata image overrides, database items, shops, crafting recipes, or runtime-injected items. Duplicate keys within one Lua table have already been overwritten when the table is evaluated and cannot be detected. Case collisions across resulting entries can be detected.

Local checks confirm that a file is readable and nonempty; they do not decode images, validate browser MIME support, verify NUI manifest delivery, or guarantee Linux case compatibility when tested on Windows. Remote URLs, encoded paths, and paths with query strings or traversal segments are reported as unverified. Export checks verify resource startup, not the existence or behavior of an individual export. Missing-image findings can be intentional where a script supplies metadata images.

## Server export and adapters

Other server resources can get a fresh structured report without printing it:

```lua
local report = exports.rw_itemchecker:Scan()
-- report.items, errors, warnings, info, imagesChecked, imagesSkipped
-- report.findings = { { severity, item, code, message }, ... }
```

The export is server-only and does not use the command cooldown. Cache results if calling it from another resource. Source failures appear as errors in the report.

Inventory-specific reading lives in `adapters/ox_inventory.lua`. To add another inventory, register an adapter in `ItemChecker.adapters`, load it before `server/main.lua` in the manifest, and select it in `config.lua`. An adapter supplies `collect(options)` (entries plus source-error strings), `readFile(resource, path)`, `resourceState(resource)`, and `imagePath(options)`. Entries have `name`, `data`, and optionally `kind = 'Weapons'`. Validation currently follows ox field semantics; another inventory may need its own validation rules.

## Development

Run from the project root with Lua 5.4:

```sh
lua tests/run.lua
```

The suite mocks FiveM natives and tests validation, paths, source isolation/errors, instruction limits, command permissions registration, reporting, and the export. FiveM's native backtick/vector syntax and ACE enforcement need a real server smoke test: start after ox_inventory, run `itemcheck all`, and confirm an unprivileged player cannot run `/itemcheck`.

Reference behavior: [ox_inventory item creation](https://overextended.dev/docs/ox_inventory/Guides/creatingItems), [item normalization](https://github.com/overextended/ox_inventory/blob/main/modules/items/shared.lua), [UI image resolution](https://github.com/overextended/ox_inventory/blob/main/web/src/helpers/index.ts), and [FiveM restricted commands](https://docs.fivem.net/docs/scripting-manual/migrating-from-deprecated/creating-commands/).
