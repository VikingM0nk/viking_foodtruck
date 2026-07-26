--[[
    Consumables bridge — registers foodtruck menu items as useable and applies
    hunger / thirst / stress on use for QB, Qbox, ESX, ox_inventory, and custom.
]]

Consumables = Consumables or {}

local detected
local registered = {} -- item -> key
local itemDefs = {}   -- item -> menuItem snapshot
local useableBound = {} -- item -> true (CreateUseableItem already bound)

local function started(name)
    return type(name) == 'string' and name ~= '' and GetResourceState(name) == 'started'
end

local function detect()
    local mode = Config.Consumables or 'auto'
    if mode ~= 'auto' then return mode end
    local c = Config.CustomConsumables or {}
    if c.resource and started(c.resource) then return 'custom' end
    if started('ox_inventory') then return 'ox' end
    if started('qb-smallresources') then return 'qb-smallresources' end
    if started('qs-consumables') then return 'qs' end
    if started('esx_basicneeds') then return 'esx' end
    if started('consumables') then return 'generic' end
    if started('qb-core') or started('qbx_core') then return 'qb' end
    return 'builtin'
end

function Consumables.GetType()
    if not detected then detected = detect() end
    return detected
end

local function callExport(resource, exportName, ...)
    if not started(resource) or not exportName or exportName == '' then return nil, false end
    local exp = exports[resource]
    if exp and exp[exportName] then
        local ok, result = pcall(exp[exportName], exp, ...)
        if ok then return result, true end
    end
    local ok, result = pcall(function(...)
        return exports[resource][exportName](...)
    end, ...)
    return result, ok
end

local function clamp(n, a, b)
    n = tonumber(n) or 0
    if n < a then return a end
    if n > b then return b end
    return n
end

--- Apply hunger/thirst/stress for any common framework / HUD
function Consumables.ApplyNeeds(src, menuItem)
    if not IsDuplicityVersion() then return end
    if not src or not menuItem then return end

    local hunger = tonumber(menuItem.hunger) or 0
    local thirst = tonumber(menuItem.thirst) or 0
    local stress = tonumber(menuItem.stress) or 0
    if hunger == 0 and thirst == 0 and stress == 0 then return end

    local c = Config.CustomConsumables or {}
    if c.applyNeedsExport and c.applyNeedsExport ~= '' and c.resource and started(c.resource) then
        callExport(c.resource, c.applyNeedsExport, src, hunger, thirst, stress, menuItem)
    end
    if c.applyNeedsEvent and c.applyNeedsEvent ~= '' then
        TriggerEvent(c.applyNeedsEvent, src, hunger, thirst, stress, menuItem)
        TriggerClientEvent(c.applyNeedsEvent, src, hunger, thirst, stress, menuItem)
    end

    local foodCfg = Config.CustomFood or {}
    if foodCfg.applyNeedsExport and foodCfg.applyNeedsExport ~= '' and started(foodCfg.resource) then
        callExport(foodCfg.resource, foodCfg.applyNeedsExport, src, hunger, thirst, stress, menuItem)
    end

    -- Framework metadata (QB / Qbox)
    local fw = Bridge and Bridge.GetType and Bridge.GetType()
    if fw == 'qb' or fw == 'qbox' then
        local player = Bridge.GetPlayer(src)
        if player and player.Functions and player.PlayerData then
            local meta = player.PlayerData.metadata or {}
            if hunger ~= 0 then
                local cur = tonumber(meta.hunger) or 0
                player.Functions.SetMetaData('hunger', clamp(cur + hunger, 0, 100))
            end
            if thirst ~= 0 then
                local cur = tonumber(meta.thirst) or 0
                player.Functions.SetMetaData('thirst', clamp(cur + thirst, 0, 100))
            end
            if stress ~= 0 then
                local cur = tonumber(meta.stress) or 0
                -- stress on menu items = relief amount
                player.Functions.SetMetaData('stress', clamp(cur - math.abs(stress), 0, 100))
            end
        end
    elseif fw == 'esx' then
        if hunger ~= 0 then
            TriggerClientEvent('esx_status:add', src, 'hunger', math.floor(hunger * 10000))
        end
        if thirst ~= 0 then
            TriggerClientEvent('esx_status:add', src, 'thirst', math.floor(thirst * 10000))
        end
        if stress ~= 0 then
            TriggerClientEvent('esx_status:remove', src, 'stress', math.floor(math.abs(stress) * 10000))
            TriggerClientEvent('esx_status:add', src, 'stress', -math.floor(math.abs(stress) * 10000))
        end
    end

    -- ox_status (used by some ox_inventory setups)
    if started('ox_status') or started('ox_inventory') then
        if hunger ~= 0 then
            pcall(function()
                TriggerClientEvent('ox_status:add', src, 'hunger', hunger)
            end)
        end
        if thirst ~= 0 then
            pcall(function()
                TriggerClientEvent('ox_status:add', src, 'thirst', thirst)
            end)
        end
        if stress ~= 0 then
            pcall(function()
                TriggerClientEvent('ox_status:remove', src, 'stress', math.abs(stress))
            end)
        end
    end

    -- Common HUD events
    TriggerClientEvent('hud:client:UpdateNeeds', src,
        clamp((function()
            if fw == 'qb' or fw == 'qbox' then
                local p = Bridge.GetPlayer(src)
                return p and p.PlayerData and p.PlayerData.metadata and p.PlayerData.metadata.hunger or hunger
            end
            return hunger
        end)(), 0, 100),
        clamp((function()
            if fw == 'qb' or fw == 'qbox' then
                local p = Bridge.GetPlayer(src)
                return p and p.PlayerData and p.PlayerData.metadata and p.PlayerData.metadata.thirst or thirst
            end
            return thirst
        end)(), 0, 100)
    )
    if stress ~= 0 then
        TriggerClientEvent('hud:client:RelieveStress', src, math.abs(stress))
        TriggerClientEvent('hud:client:UpdateStress', src, (function()
            if fw == 'qb' or fw == 'qbox' then
                local p = Bridge.GetPlayer(src)
                return p and p.PlayerData and p.PlayerData.metadata and p.PlayerData.metadata.stress or 0
            end
            return 0
        end)())
    end

    -- qb-smallresources style
    TriggerClientEvent('consumables:client:UpdateNeeds', src, hunger, thirst)
    TriggerEvent('viking_foodtruck:applyNeeds', src, hunger, thirst, stress, menuItem)

    if Food and Food.ApplyNeeds then
        -- Keep Food bridge hooks in sync without re-entering custom exports twice
        TriggerEvent('viking_foodtruck:foodApplyNeeds', src, menuItem)
    end
end

local function removeOneItem(src, itemName, slot)
    local fw = Bridge and Bridge.GetType and Bridge.GetType()
    if (fw == 'qb' or fw == 'qbox') and slot then
        local player = Bridge.GetPlayer(src)
        if player and player.Functions and player.Functions.RemoveItem then
            local ok = player.Functions.RemoveItem(itemName, 1, slot)
            if ok then return true end
        end
    end
    if started('ox_inventory') then
        local ok, result = pcall(function()
            if slot then
                return exports.ox_inventory:RemoveItem(src, itemName, 1, nil, slot)
            end
            return exports.ox_inventory:RemoveItem(src, itemName, 1)
        end)
        if ok and result then return true end
    end
    if Inv and Inv.RemoveItem then
        return Inv.RemoveItem(src, itemName, 1) and true or false
    end
    return false
end

--- Server: player used a foodtruck item (after anim / inventory use)
function Consumables.UseItem(src, itemName, slot)
    if not IsDuplicityVersion() then return false end
    itemName = tostring(itemName or ''):lower()
    local def = itemDefs[itemName]
    if not def then
        -- try original case key
        def = itemDefs[tostring(itemName or '')]
    end
    if not def then return false end

    -- Prefer metadata from the actual inventory item when present
    if slot and started('ox_inventory') then
        local ok, slotData = pcall(function()
            return exports.ox_inventory:GetSlot(src, slot)
        end)
        if ok and type(slotData) == 'table' and type(slotData.metadata) == 'table' then
            local meta = slotData.metadata
            def = {
                item = def.item,
                label = def.label,
                hunger = tonumber(meta.hunger or meta.hungerAmount or meta.food) or def.hunger,
                thirst = tonumber(meta.thirst or meta.thirstAmount or meta.drink) or def.thirst,
                stress = tonumber(meta.stress or meta.stressAmount) or def.stress,
                category = def.category,
            }
        end
    end

    Consumables.ApplyNeeds(src, def)
    TriggerClientEvent('viking_foodtruck:client:consumeFx', src, def)
    TriggerEvent('viking_foodtruck:consumables:used', src, def)
    return true
end

local function bindUseable(itemName)
    if not IsDuplicityVersion() then return end
    itemName = tostring(itemName or '')
    local key = itemName:lower()
    if useableBound[key] then return end
    useableBound[key] = true

    -- QB / Qbox
    if started('qb-core') or started('qbx_core') then
        local ok, core = pcall(function()
            if started('qbx_core') and exports.qbx_core and exports.qbx_core.GetCoreObject then
                return exports.qbx_core:GetCoreObject()
            end
            return exports['qb-core']:GetCoreObject()
        end)
        if ok and core and core.Functions and core.Functions.CreateUseableItem then
            core.Functions.CreateUseableItem(itemName, function(source, item)
                local name = (item and (item.name or item.item)) or itemName
                local slot = item and item.slot
                -- Client progress/anim first, then confirm consume
                TriggerClientEvent('viking_foodtruck:client:useFood', source, name, slot)
            end)
            -- Also bind lowercase alias if different
            if key ~= itemName then
                core.Functions.CreateUseableItem(key, function(source, item)
                    local name = (item and (item.name or item.item)) or key
                    local slot = item and item.slot
                    TriggerClientEvent('viking_foodtruck:client:useFood', source, name, slot)
                end)
            end
        end
    end

    -- ESX
    if started('es_extended') then
        local ok, esx = pcall(function()
            return exports['es_extended']:getSharedObject()
        end)
        if ok and esx and esx.RegisterUsableItem then
            esx.RegisterUsableItem(itemName, function(source)
                TriggerClientEvent('viking_foodtruck:client:useFood', source, itemName, nil)
            end)
            if key ~= itemName then
                esx.RegisterUsableItem(key, function(source)
                    TriggerClientEvent('viking_foodtruck:client:useFood', source, key, nil)
                end)
            end
        end
    end
end

local oxHookId

local function ensureOxHook()
    if not IsDuplicityVersion() or not started('ox_inventory') then return end
    if oxHookId then return end
    local ok, id = pcall(function()
        return exports.ox_inventory:registerHook('usingItem', function(payload)
            if type(payload) ~= 'table' or type(payload.item) ~= 'table' then return end
            local name = tostring(payload.item.name or ''):lower()
            local def = itemDefs[name] or itemDefs[payload.item.name]
            if not def then return end
            -- Apply needs; ox handles consume via item consume flag
            Consumables.ApplyNeeds(payload.source, def)
            TriggerClientEvent('viking_foodtruck:client:consumeFx', payload.source, def)
        end, {
            print = false,
        })
    end)
    if ok then
        oxHookId = id
        print('[viking_foodtruck] ox_inventory usingItem hook registered')
    end
end

--- Register a menu item as a consumable (hunger/thirst/stress).
function Consumables.Register(menuItem)
    if not IsDuplicityVersion() then return end
    if type(menuItem) ~= 'table' or not menuItem.item or menuItem.item == '' then return end

    local item = tostring(menuItem.item)
    local hunger = tonumber(menuItem.hunger) or 0
    local thirst = tonumber(menuItem.thirst) or 0
    local stress = tonumber(menuItem.stress) or 0
    local key = ('%s:%s:%s:%s'):format(item:lower(), hunger, thirst, stress)

    itemDefs[item] = menuItem
    itemDefs[item:lower()] = menuItem

    if registered[item:lower()] == key then
        bindUseable(item)
        return
    end
    registered[item:lower()] = key

    local kind = Consumables.GetType()
    local c = Config.CustomConsumables or {}
    local payload = {
        item = item,
        label = menuItem.label,
        hunger = hunger,
        thirst = thirst,
        stress = stress,
        type = menuItem.category or 'food',
        metadata = Food and Food.BuildMetadata and Food.BuildMetadata(menuItem) or {},
    }

    if kind == 'custom' or (c.resource and started(c.resource)) then
        if c.registerExport and c.registerExport ~= '' then
            callExport(c.resource, c.registerExport, payload)
        end
        if c.registerEvent and c.registerEvent ~= '' then
            TriggerEvent(c.registerEvent, payload)
        end
    end

    if kind == 'qb-smallresources' or started('qb-smallresources') then
        TriggerEvent('consumables:server:foodtruckRegister', payload)
        TriggerEvent('qb-smallresources:server:foodtruckRegister', payload)
        -- Inject into qb-smallresources Config tables when possible
        pcall(function()
            local cfg = exports['qb-smallresources'] and exports['qb-smallresources'].GetConfig
            -- Event-based inject is more compatible
            TriggerEvent('consumables:server:registerItem', item, {
                hunger = hunger,
                thirst = thirst,
                stress = stress,
            })
        end)
    end

    if kind == 'ox' or started('ox_inventory') then
        TriggerEvent('ox_inventory:foodtruckRegister', payload)
        ensureOxHook()
    end

    if kind == 'esx' or started('esx_basicneeds') then
        TriggerEvent('esx_basicneeds:foodtruckRegister', payload)
    end

    bindUseable(item)
    TriggerEvent('viking_foodtruck:consumables:register', payload)
end

function Consumables.RegisterMenu(menu)
    if type(menu) ~= 'table' then return end
    for i = 1, #menu do
        Consumables.Register(menu[i])
    end
end

function Consumables.OnGiven(src, menuItem)
    if not IsDuplicityVersion() then return end
    if type(menuItem) == 'table' then
        Consumables.Register(menuItem)
    end
    local c = Config.CustomConsumables or {}
    local meta = Food and Food.BuildMetadata and Food.BuildMetadata(menuItem) or {}
    local payload = {
        source = src,
        item = menuItem.item,
        label = menuItem.label,
        hunger = tonumber(menuItem.hunger) or 0,
        thirst = tonumber(menuItem.thirst) or 0,
        stress = tonumber(menuItem.stress) or 0,
        metadata = meta,
        menuItem = menuItem,
    }

    if c.onGivenExport and c.onGivenExport ~= '' and c.resource and started(c.resource) then
        callExport(c.resource, c.onGivenExport, src, payload)
    end
    if c.onGivenEvent and c.onGivenEvent ~= '' then
        TriggerEvent(c.onGivenEvent, src, payload)
        TriggerClientEvent(c.onGivenEvent, src, payload)
    end

    TriggerEvent('viking_foodtruck:consumables:given', src, payload)
end

function Consumables.GetDef(itemName)
    if not itemName then return nil end
    return itemDefs[tostring(itemName):lower()] or itemDefs[tostring(itemName)]
end

if IsDuplicityVersion() then
    -- Client finished eat/drink progress → remove item + apply needs
    RegisterNetEvent('viking_foodtruck:server:finishConsume', function(itemName, slot)
        local src = source
        itemName = tostring(itemName or '')
        if itemName == '' then return end
        local def = Consumables.GetDef(itemName)
        if not def then return end
        if not removeOneItem(src, itemName, slot) then
            -- Try lowercase name
            if not removeOneItem(src, itemName:lower(), slot) then
                Bridge.Notify(src, 'Could not consume item', 'error')
                return
            end
        end
        Consumables.UseItem(src, itemName, slot)
    end)

    -- ox_inventory item server export: server = { export = 'viking_foodtruck.usedFoodItem' }
    -- Skip if usingItem hook already handled this source+item recently
    local recentOx = {}
    exports('usedFoodItem', function(event, item, inventory, slot)
        if event ~= 'usingItem' then return end
        local src = type(inventory) == 'table' and inventory.id or inventory
        local name = type(item) == 'table' and item.name or item
        local def = Consumables.GetDef(name)
        local meta = type(item) == 'table' and item.metadata or nil
        if not def and type(meta) == 'table' then
            def = {
                item = name,
                label = meta.label or name,
                hunger = tonumber(meta.hunger or meta.food or meta.hungerAmount) or 0,
                thirst = tonumber(meta.thirst or meta.drink or meta.thirstAmount) or 0,
                stress = tonumber(meta.stress or meta.stressAmount) or 0,
            }
        end
        if not def then return end
        local dedupe = ('%s:%s'):format(tostring(src), tostring(name):lower())
        local now = GetGameTimer()
        if recentOx[dedupe] and (now - recentOx[dedupe]) < 2000 then
            return
        end
        recentOx[dedupe] = now
        if type(meta) == 'table' then
            def = {
                item = def.item or name,
                label = def.label,
                hunger = tonumber(meta.hunger or meta.food or meta.hungerAmount) or def.hunger,
                thirst = tonumber(meta.thirst or meta.drink or meta.thirstAmount) or def.thirst,
                stress = tonumber(meta.stress or meta.stressAmount) or def.stress,
                category = def.category,
            }
        end
        Consumables.ApplyNeeds(src, def)
        TriggerClientEvent('viking_foodtruck:client:consumeFx', src, def)
    end)

    -- Dedupe ox hook vs export
    local _apply = Consumables.ApplyNeeds
    local recentApply = {}
    function Consumables.ApplyNeeds(src, menuItem)
        if not src or type(menuItem) ~= 'table' then return end
        local dedupe = ('%s:%s'):format(tostring(src), tostring(menuItem.item or ''):lower())
        local now = GetGameTimer()
        if recentApply[dedupe] and (now - recentApply[dedupe]) < 1500 then
            return
        end
        recentApply[dedupe] = now
        return _apply(src, menuItem)
    end

    CreateThread(function()
        Wait(2000)
        ensureOxHook()
        for name in pairs(itemDefs) do
            bindUseable(name)
        end
        print(('[viking_foodtruck] consumables bridge: type=%s items=%s'):format(
            Consumables.GetType(), tostring((function()
                local n = 0
                for _ in pairs(registered) do n = n + 1 end
                return n
            end)())
        ))
    end)
end
