# viking_foodtruck — Inventory Install

Item definitions + PNG icons for the starter food truck menus.

## Images

All icons are in [`images/`](images/) — name matches item spawn name (`burger.png` → item `burger`).

| Inventory | Copy images to |
|---|---|
| **ox_inventory** | `ox_inventory/web/images/` |
| **qb-inventory** | `qb-inventory/html/images/` |
| **ps-inventory** | `ps-inventory/html/images/` |
| **qs-inventory** | `qs-inventory/html/images/` |
| **ESX inventoryhud** | `esx_inventoryhud/html/img/items/` (path may vary) |
| **codem-inventory** | `codem-inventory/html/itemimages/` (path may vary) |

## Item definitions

| System | File |
|---|---|
| ox_inventory | [`ox_inventory/items_paste.lua`](ox_inventory/items_paste.lua) → paste into `ox_inventory/data/items.lua` |
| QBCore / Qbox | [`qb-core/items.lua`](qb-core/items.lua) → paste into `qb-core/shared/items.lua` |
| qs-inventory | [`qs-inventory/items.lua`](qs-inventory/items.lua) |
| ESX (SQL) | [`esx/items.sql`](esx/items.sql) |
| ESX (Lua) | [`esx/items.lua`](esx/items.lua) |
| ps-inventory | same as QBCore — see [`ps-inventory/README.md`](ps-inventory/README.md) |

## Quick install (ox_inventory)

1. Copy every file from `install/images/` → `ox_inventory/web/images/`
2. Open `ox_inventory/data/items.lua` and paste the entries from `install/ox_inventory/items.lua` (the `[\'taco\'] = { ... }` blocks)
3. `ensure ox_inventory` then `ensure viking_foodtruck`

## Quick install (QBCore)

1. Copy images → `qb-inventory/html/images/`
2. Paste items from `install/qb-core/items.lua` into `qb-core/shared/items.lua`
3. Restart `qb-core` and your inventory resource

## Notes

- If an item name already exists on your server, keep yours and update the food truck menu in `/foodtruckcreator` to match.
- Icons source: [Twemoji](https://github.com/twitter/twemoji) (CC-BY 4.0).
- Full name list: [`items_list.md`](items_list.md)
