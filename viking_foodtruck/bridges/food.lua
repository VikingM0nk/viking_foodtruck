--[[
    Food bridge — deliver prepared food through inventory OR any food/restaurant give export.
    Optional needs (hunger/thirst/stress) metadata for consumable systems.
]]

Food = Food or {}

local detected

local function started(name)
    return type(name) == 'string' and name ~= '' and GetResourceState(name) == 'started'
end

local function detect()
    local mode = Config.Food or 'auto'
    if mode ~= 'auto' then return mode end
    if Config.CustomFood and started(Config.CustomFood.resource) then return 'custom' end
    if started('ox_inventory') then return 'ox' end
    if started('qb-core') or started('qbx_core') then return 'qb' end
    if started('es_extended') then return 'esx' end
    return 'inventory'
end

function Food.GetType()
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

--- Build metadata many food/consumable scripts understand
function Food.BuildMetadata(menuItem)
    menuItem = menuItem or {}
    local meta = type(menuItem.metadata) == 'table' and menuItem.metadata or {}
    local hunger = tonumber(menuItem.hunger)
    local thirst = tonumber(menuItem.thirst)
    local stress = tonumber(menuItem.stress)
    if hunger then
        meta.hunger = hunger
        meta.food = hunger
        meta.hungerAmount = hunger
    end
    if thirst then
        meta.thirst = thirst
        meta.drink = thirst
        meta.thirstAmount = thirst
    end
    if stress then
        meta.stress = stress
        meta.stressAmount = stress
    end
    meta.label = menuItem.label or meta.label
    meta.description = menuItem.description or meta.description
    meta.foodtruck = true
    return meta
end

--- Give prepared food to a player. Returns true/false.
function Food.Give(src, menuItem)
    if not IsDuplicityVersion() then return false end
    if type(menuItem) ~= 'table' or not menuItem.item or menuItem.item == '' then
        return false
    end

    local count = math.max(1, math.floor(tonumber(menuItem.giveCount) or 1))
    local meta = Food.BuildMetadata(menuItem)
    local kind = Food.GetType()
    local c = Config.CustomFood or {}

    -- Custom food/restaurant give export takes priority when configured
    if kind == 'custom' or (c.resource and started(c.resource) and c.giveFoodExport and c.giveFoodExport ~= '') then
        if c.giveFoodExport and c.giveFoodExport ~= '' then
            local result, ok = callExport(c.resource, c.giveFoodExport, src, menuItem.item, count, meta, menuItem)
            if ok then return result ~= false end
        end
        if c.giveFoodEvent and c.giveFoodEvent ~= '' then
            TriggerEvent(c.giveFoodEvent, src, menuItem.item, count, meta, menuItem)
            TriggerClientEvent(c.giveFoodEvent, src, menuItem.item, count, meta, menuItem)
            return true
        end
    end

    local itemName = tostring(menuItem.item):lower()

    if Inv.GetType() == 'none' then
        print(('[viking_foodtruck] Food.Give failed — no inventory bridge (item=%s). Set Config.Inventory.'):format(itemName))
        return false
    end

    if not Inv.CanCarry(src, itemName, count) then
        print(('[viking_foodtruck] Food.Give failed — cannot carry %s x%s'):format(itemName, count))
        return false
    end

    local added = Inv.AddItem(src, itemName, count, meta)
    if not added then
        -- Retry bare add (some inventories reject metadata / item case)
        added = Inv.AddItem(src, itemName, count, nil)
    end
    if not added and itemName ~= menuItem.item then
        added = Inv.AddItem(src, menuItem.item, count, meta)
    end
    if not added then
        print(('[viking_foodtruck] Food.Give failed — AddItem returned false for %s (inv=%s)'):format(
            itemName, Inv.GetType()
        ))
        return false
    end

    TriggerEvent('viking_foodtruck:foodGiven', src, itemName, count, meta, menuItem)
    return true
end

--- Optional immediate needs apply (some servers apply on use; others on receive)
function Food.ApplyNeeds(src, menuItem)
    if not IsDuplicityVersion() then return end
    menuItem = menuItem or {}
    if Consumables and Consumables.ApplyNeeds then
        Consumables.ApplyNeeds(src, menuItem)
        return
    end

    local hunger = tonumber(menuItem.hunger)
    local thirst = tonumber(menuItem.thirst)
    local stress = tonumber(menuItem.stress)
    if not hunger and not thirst and not stress then return end

    local c = Config.CustomFood or {}
    if c.applyNeedsExport and c.applyNeedsExport ~= '' and started(c.resource) then
        callExport(c.resource, c.applyNeedsExport, src, hunger or 0, thirst or 0, stress or 0, menuItem)
        return
    end
    if c.applyNeedsEvent and c.applyNeedsEvent ~= '' then
        TriggerEvent(c.applyNeedsEvent, src, hunger or 0, thirst or 0, stress or 0, menuItem)
        TriggerClientEvent(c.applyNeedsEvent, src, hunger or 0, thirst or 0, stress or 0, menuItem)
        return
    end

    TriggerEvent('viking_foodtruck:applyNeeds', src, hunger or 0, thirst or 0, stress or 0, menuItem)
end
