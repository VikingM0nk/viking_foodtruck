Config = {}

--[[
    viking_foodtruck — standalone food truck business creator

    server.cfg:
        ensure oxmysql
        ensure ox_lib
        ensure viking_foodtruck

    Ace admin permission (recommended):
        add_ace group.admin foodtruck.admin allow
]]

-- Admin creator command
Config.Command = 'foodtruckcreator'

-- Ace permission checked first; framework groups used as fallback
Config.AdminAce = 'foodtruck.admin'
Config.AdminGroups = {
    'admin',
    'god',
    'superadmin',
}

-- auto | qb | qbox | esx | standalone
Config.Framework = 'auto'

-- auto | ox | qb | ps | qs | custom | none
Config.Inventory = 'auto'

-- Used when Config.Inventory = 'custom'
Config.CustomInventory = {
    resource = 'my_inventory',
    addItem = 'AddItem',       -- export(src, item, count, metadata?)
    removeItem = 'RemoveItem', -- export(src, item, count)
    getCount = 'GetItemCount', -- export(src, item) -> number
    canCarry = 'CanCarryItem', -- export(src, item, count) -> boolean (optional)
}

--[[
    Banking — bank account money for purchases / withdraw / customer pay (when account = bank)
    auto | framework | qb-banking | renewed | okok | wasabi | fd | snipe | custom | none
    framework/none = use framework cash/bank (or standalone wallets)
]]
Config.Banking = 'auto'

Config.CustomBanking = {
    resource = '',
    getBalance = 'GetBalance',     -- export(src) -> number
    removeMoney = 'RemoveMoney',   -- export(src, amount, reason) -> boolean
    addMoney = 'AddMoney',         -- export(src, amount, reason) -> boolean
    removeEvent = '',              -- optional server event (src, amount, reason)
    addEvent = '',                 -- optional server event (src, amount, reason)
}

-- Framework cash override / standalone wallet override (bank still prefers Banking bridge)
Config.CustomMoney = {
    resource = '',
    getMoney = 'GetMoney',       -- export(src, account) -> number
    removeMoney = 'RemoveMoney', -- export(src, account, amount) -> boolean
    addMoney = 'AddMoney',       -- export(src, account, amount) -> boolean
}

--[[
    Food delivery — how cooked items are given to customers
    auto | inventory | ox | qb | esx | custom
]]
Config.Food = 'auto'

Config.CustomFood = {
    resource = '',
    giveFoodExport = '',       -- export(src, item, count, metadata, menuItem) -> boolean
    giveFoodEvent = '',        -- server+client event fallback
    applyNeedsExport = '',     -- export(src, hunger, thirst, stress, menuItem)
    applyNeedsEvent = '',      -- apply hunger/thirst immediately (optional)
    applyNeedsOnGive = false,  -- if true, apply needs when order is fulfilled
}

--[[
    Restaurant integrations — optional hooks into any restaurant script
    auto | custom | none | detected
]]
Config.Restaurant = 'auto'

Config.CustomRestaurant = {
    resource = '',
    onShopOpenExport = '',
    onShopCloseExport = '',
    onSaleExport = '',
    resolvePriceExport = '',   -- export(truckId, menuItem, price) -> number
    onShopOpenEvent = 'viking_foodtruck:hook:shopOpen',
    onShopCloseEvent = 'viking_foodtruck:hook:shopClose',
    onSaleEvent = 'viking_foodtruck:hook:sale',
}

--[[
    Consumables — foodtruck items become useable and apply hunger/thirst/stress.
    Built-in: QB/Qbox metadata, ESX status, ox_inventory hooks, HUD events.
    auto | ox | qb | qb-smallresources | qs | esx | custom | builtin | none
]]
Config.Consumables = 'auto'

Config.CustomConsumables = {
    resource = '',
    registerExport = '',       -- export(payload)
    registerEvent = '',
    onGivenExport = '',        -- export(src, payload)
    onGivenEvent = '',
    applyNeedsExport = '',     -- export(src, hunger, thirst, stress, menuItem)
    applyNeedsEvent = '',
}

--[[
    Billing — pay instantly and/or send invoices
    System: auto | builtin | okok | jim | qb-phone | esx | qs | codem | renewed | custom | none
    Mode:   choice (pay now or bill) | instant | bill
]]
Config.Billing = 'auto'
Config.BillingMode = 'choice' -- choice | instant | bill
Config.AllowCustomerBilling = true
Config.BillOnFulfill = true   -- if true, bill is sent when food is ready; else on order place
Config.BillExpireHours = 72

Config.CustomBilling = {
    resource = '',
    createExport = '', -- export(senderSrc, targetSrc, amount, reason, meta)
    createEvent = '',  -- server event fallback
}

--[[
    Vehicle keys — auto-detects qb-vehiclekeys, qbx_vehiclekeys, wasabi, qs, Renewed,
    cd_garage, MrNewb, jaksam, t1ger, okok, tgiann, and more.
    auto | none  (use GiveKeys below for a forced custom script)
]]
Config.Keys = 'auto'

-- Also give keys to staff who retrieve the truck (owner always gets keys when online)
Config.KeysGiveToStaff = true

-- Optional forced custom key script (used in addition to auto when set)
Config.GiveKeys = {
    resource = '',          -- e.g. 'my_keys'
    export = '',            -- client export(plate, vehicle?, model?)
    event = '',             -- client event(plate)
    serverExport = '',      -- server export(src, plate, vehicle?)
    serverEvent = '',       -- server event(src, plate, netId?)
}

--[[
    Garage — ONE food truck vehicle per owner, saved to DB on purchase only.
    Spawn/park/sync only UPDATE that row (never insert another).
    Backends: player_vehicles / owned_vehicles / qbx_vehicles + garage hooks.
    Set GarageDefault to a garage id that exists in YOUR garage script.
]]
Config.Garage = 'auto' -- auto | qb | qbox | esx | jg | cd | okok | qs | custom | none
Config.GarageAllowPark = true
Config.GarageDefault = 'pillboxgarage' -- e.g. legion, motelgarage — must exist on your server

Config.CustomGarage = {
    resource = '',
    registerExport = '',   -- export(src, ownerId, model, plate, props, garage)
    setOutExport = '',
    setStoredExport = '',
    removeExport = '',
}

-- Purchase broker ped
Config.PurchasePed = {
    model = 's_m_m_linecook',
    coords = vector4(-1190.12, -889.45, 13.0, 210.0),
    scenario = 'WORLD_HUMAN_CLIPBOARD',
    blip = {
        enabled = true,
        sprite = 106,
        color = 5,
        scale = 0.8,
        label = 'Food Truck Broker',
    },
    interactDistance = 2.5,
    -- Where the truck spawns after purchase (relative to ped heading).
    -- If a truck has a retrieve spot set in the creator, that is used instead.
    spawnOffset = vector3(0.0, 4.0, 0.0),
}

-- Spawn truck immediately when bought from the vendor
Config.SpawnOnPurchase = true

--[[
    Auto job on purchase / hire
    Job must exist in your framework (qb shared/jobs, ESX jobs table), OR
    set autoRegister = true to create a basic job entry when possible.
]]
Config.Job = {
    enabled = true,
    name = 'foodtruck',
    label = 'Food Truck',
    ownerGrade = 1,       -- grade given to buyer
    employeeGrade = 0,    -- grade given when hired
    removeOnSell = true,  -- set unemployed (or offJob) when selling business
    removeOnFire = true,  -- remove job when fired as employee
    offJob = 'unemployed',
    offGrade = 0,
    autoRegister = true,  -- register job with QB/ESX on resource start if missing
    -- Optional custom export: export(src, jobName, grade)
    setJobExport = {
        resource = '',
        export = '',
    },
}

-- Economy
Config.PurchaseAccount = 'bank' -- cash | bank (tries this first, then the other)
Config.SellBackPercent = 0.5
Config.ClearBalanceOnSell = true

-- Cooking / crafting ingredient source: stock | inventory | either
Config.CookFrom = 'either'

--[[
    Crafted food destination:
      ask        — worker chooses: my inventory OR truck stock (for sale)
      inventory  — always give to worker
      stock      — always store on truck as prepared food (customers can buy ready)
      both       — give to worker AND store one on truck
]]
Config.CraftOutput = 'ask'

--[[
    Target system: auto | ox | qb | qtarget | interact | custom | none
    When none/unavailable, E-key prompts still work.
]]
Config.Target = 'auto'
Config.DebugTarget = false
Config.CustomTarget = {
    resource = '',
    addEntityExport = '',
    removeEntityExport = '',
    addZoneExport = '',
    removeZoneExport = '',
}

-- Owners/employees can always buy from OTHER open food trucks
Config.AllowOwnerCustomerPurchases = true

-- Limits
Config.MaxMenuItems = 24
Config.MaxIngredientsPerItem = 8
Config.MaxStockPerItem = 250
Config.OrderTimeoutMs = 120000
Config.InteractDistance = 3.0
Config.StaffNotifyDistance = 25.0

-- Defaults for new trucks in the creator
Config.DefaultBlip = {
    enabled = true,
    sprite = 106,
    color = 5,
    scale = 0.75,
}

Config.DefaultVehicle = 'taco'
Config.DefaultCookMs = 8000

Config.Categories = {
    { id = 'mexican', label = 'Mexican' },
    { id = 'american', label = 'American' },
    { id = 'asian', label = 'Asian' },
    { id = 'dessert', label = 'Dessert' },
    { id = 'drinks', label = 'Drinks' },
    { id = 'custom', label = 'Custom' },
}

-- Optional vehicle model whitelist (empty = allow any string)
Config.VehicleWhitelist = {
    'taco',
    'rumpo',
    'burrito3',
    'pony',
    'speedo',
}

Config.Locale = {
    purchase_prompt = '[E] Food Truck Broker',
    customer_prompt = '[E] Order Food',
    staff_prompt = '[E] Food Truck',
    bought = 'You purchased %s for $%s',
    sold = 'You sold %s for $%s',
    not_enough_money = 'Not enough money',
    already_owned = 'This food truck is already owned',
    not_owner = 'You do not own this food truck',
    shop_open = 'Shop is now open',
    shop_closed = 'Shop is now closed',
    order_placed = 'Order placed',
    order_ready = 'Your order is ready',
    bill_sent = 'Invoice sent',
    bill_paid = 'Bill paid',
    no_bills = 'No unpaid bills',
    no_stock = 'Not enough ingredients/stock',
    saved = 'Food truck saved',
    deleted = 'Food truck deleted',
    no_permission = 'No permission',
}
