# viking_foodtruck

Standalone FiveM food truck business creator. Admins build fully custom trucks in-game; players buy them from a config ped and run the business.

## Dependencies

- [oxmysql](https://github.com/overextended/oxmysql) (**required**)
- [ox_lib](https://github.com/overextended/ox_lib) (**optional**) — if missing or broken, viking_foodtruck uses its built-in callbacks/menus

If you see `Unable to load UI. Build ox_lib...`, either install a full [ox_lib release zip](https://github.com/overextended/ox_lib/releases/latest/download/ox_lib.zip) or simply leave ox_lib out — this resource no longer hard-requires it.

Everything else is optional via bridges (framework, inventory, banking, billing, food, restaurant, consumables).

## Install

1. Copy `viking_foodtruck` into your resources folder.
2. Add to `server.cfg`:

```cfg
ensure oxmysql
ensure ox_lib
ensure viking_foodtruck
```

3. Tables auto-create on start (`sql/foodtruck.sql` optional).
4. Set `Config.PurchasePed.coords` in `config.lua`.
5. Grant admin Ace:

```cfg
add_ace group.admin foodtruck.admin allow
```

## Commands

| Command | Who | What |
|---|---|---|
| `/foodtruckcreator` | Admin | Open in-game creator NUI |
| `/foodtruck` | Owner / employee | Manage truck, open shop, cook orders |

## Bridges

All default to `'auto'` and fall back safely when a resource is missing.

```lua
Config.Framework   = 'auto' -- qb | qbox | esx | standalone
Config.Inventory   = 'auto' -- ox | qb | ps | qs | custom | none
Config.Banking     = 'auto' -- framework | qb-banking | renewed | okok | wasabi | fd | snipe | custom | none
Config.Billing     = 'auto' -- builtin | okok | jim | qb-phone | esx | qs | custom | none
Config.BillingMode = 'choice' -- choice | instant | bill
Config.Food        = 'auto' -- inventory | ox | qb | esx | custom
Config.Restaurant  = 'auto' -- custom | none | detected
Config.Consumables = 'auto' -- ox | qb-smallresources | qs | esx | custom | none
Config.Keys        = 'auto' -- auto | none (qb/qbx/wasabi/qs/Renewed/cd/MrNewb/…)
```

### Billing (any billing script + built-in)

- **`auto`**: uses okokBilling / jim-payments / qb-phone / esx_billing / etc. if started, otherwise **built-in** invoices.
- **`builtin`**: force `viking_foodtruck_bills` (pay with `/foodtruckbills`).
- **`custom`**: wire your own export/event via `Config.CustomBilling`.

Customers can **Pay Now** or **Send Bill** when `Config.BillingMode = 'choice'`. Built-in unpaid bills credit the truck balance when paid.

### Banking (any bank script)

Bank-account purchases / refunds / withdraw prefer the banking bridge, then framework money.

Wire an unsupported bank:

```lua
Config.Banking = 'custom'
Config.CustomBanking = {
    resource = 'my_banking',
    getBalance = 'GetBalance',
    removeMoney = 'RemoveMoney',
    addMoney = 'AddMoney',
}
```

### Food (any food delivery script)

Orders are delivered through `Food.Give` (inventory + metadata, or your export/event).

```lua
Config.Food = 'custom'
Config.CustomFood = {
    resource = 'my_food',
    giveFoodExport = 'GiveFood', -- (src, item, count, metadata, menuItem)
    applyNeedsOnGive = false,
    applyNeedsExport = 'ApplyNeeds',
}
```

### Restaurant (any restaurant script)

Optional hooks fire on shop open/close and each sale. Default events:

- `viking_foodtruck:hook:shopOpen`
- `viking_foodtruck:hook:shopClose`
- `viking_foodtruck:hook:sale`
- `viking_foodtruck:restaurant:sale` (always emitted)

```lua
Config.Restaurant = 'custom'
Config.CustomRestaurant = {
    resource = 'my_restaurant',
    onSaleExport = 'FoodTruckSale',
    resolvePriceExport = 'ResolveFoodTruckPrice',
}
```

### Consumables (any needs/use script)

Menu hunger / thirst / stress values are registered on save/load and attached as item metadata on give.

Listen for:

- `viking_foodtruck:consumables:register`
- `viking_foodtruck:consumables:given`

Or set `Config.CustomConsumables.registerExport` / `onGivenExport`.

## Player flow

1. Broker ped → buy truck  
2. `/foodtruck` → retrieve → open shop  
3. Customer **E** to order  
4. Staff cook → food bridge delivers item → sale to business balance  
5. Owner withdraws, restocks, hires, or sells back  

## Crafting & target

- **Craft Food (Stock)** in the staff menu cooks menu items using truck stock (`Config.CookFrom` / `Config.CraftOutput`).
- **Target**: auto-detects `ox_target`, `qb-target`, `qtarget`, `interact` (or `Config.CustomTarget`). E-key prompts still work as fallback.
- **Owners can buy from other trucks** (`Config.AllowOwnerCustomerPurchases = true`).

## Vehicle keys, ownership & garages

On spawn/purchase the script:

1. Assigns a **persistent plate** stored on the business (`data.plate`)
2. Marks the vehicle owner as the **business owner** (state bags)
3. Gives keys via every detected key system to the **owner** (and to staff who retrieved if `Config.KeysGiveToStaff = true`)
4. Registers the truck in **`player_vehicles` / `owned_vehicles`** so it can be parked at public garages

```lua
Config.Garage = 'auto'
Config.GarageAllowPark = true
Config.GarageDefault = 'pillboxgarage' -- change to a real garage id (legion, motelgarage, etc.)
```

On purchase/spawn/store the truck is written to every available backend (`player_vehicles`, `owned_vehicles`, qbx, JG, cd, okok, qs, loaf, rcore).  
`/foodtruck` → Store only deletes the world vehicle **after** the DB write succeeds (`state = 1`).

On start, console should show:  
`[viking_foodtruck] garage bridge: type=... pv=true ...`  
After buy/retrieve: `player_vehicles inserted/updated ...`

## Job on purchase

Buying a truck auto-sets `Config.Job.name` (default `foodtruck`, owner grade `1`). Selling clears it back to `unemployed`. Hiring/firing employees uses grade `0`.

```lua
Config.Job = {
    enabled = true,
    name = 'foodtruck',
    label = 'Food Truck',
    ownerGrade = 1,
    employeeGrade = 0,
    autoRegister = true, -- tries to register with QB/ESX on start
}
```

For QBCore, if auto-register fails, add the job to `qb-core/shared/jobs.lua`.

## Notes

- Creator menu fields include **Hunger / Thirst / Stress** for consumable scripts.
- Item spawn names must exist in your inventory (unless `Food` custom give handles them).
- Persistence is **oxmysql**; UI/callbacks use built-in lib (ox_lib optional).
