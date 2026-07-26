--[[
    Restaurant bridge — notify / integrate with any restaurant script via exports or events.
    Does not require a restaurant resource; hooks are optional.
]]

Restaurant = Restaurant or {}

local detected

local function started(name)
    return type(name) == 'string' and name ~= '' and GetResourceState(name) == 'started'
end

local function detect()
    local mode = Config.Restaurant or 'auto'
    if mode ~= 'auto' then return mode end
    local c = Config.CustomRestaurant or {}
    if c.resource and started(c.resource) then return 'custom' end

    local known = {
        'jim-payments',
        'qb-restaurants',
        'restaurant',
        'okokRestaurant',
        'zat-restaurant',
        'cl-restaurants',
        'origen_restaurant',
    }
    for i = 1, #known do
        if started(known[i]) then
            return 'detected'
        end
    end
    return 'none'
end

function Restaurant.GetType()
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

local function fire(hookName, eventName, ...)
    local c = Config.CustomRestaurant or {}
    local exportName = c[hookName]
    if exportName and exportName ~= '' and c.resource and started(c.resource) then
        callExport(c.resource, exportName, ...)
    end
    local ev = c[eventName]
    if ev and ev ~= '' then
        TriggerEvent(ev, ...)
    end
end

--- payload: { truckId, label, ownerId, coords, netId }
function Restaurant.OnShopOpen(payload)
    if not IsDuplicityVersion() then return end
    fire('onShopOpenExport', 'onShopOpenEvent', payload)
    TriggerEvent('viking_foodtruck:restaurant:shopOpen', payload)
end

function Restaurant.OnShopClose(payload)
    if not IsDuplicityVersion() then return end
    fire('onShopCloseExport', 'onShopCloseEvent', payload)
    TriggerEvent('viking_foodtruck:restaurant:shopClose', payload)
end

--- payload: { truckId, label, staffSrc, customerSrc, item, label, price, menuItem }
function Restaurant.OnSale(payload)
    if not IsDuplicityVersion() then return end
    fire('onSaleExport', 'onSaleEvent', payload)
    TriggerEvent('viking_foodtruck:restaurant:sale', payload)
end

--- Optional: let a restaurant script validate/override menu pricing
function Restaurant.ResolvePrice(truckId, menuItem, fallbackPrice)
    local c = Config.CustomRestaurant or {}
    if c.resolvePriceExport and c.resolvePriceExport ~= '' and c.resource and started(c.resource) then
        local result, ok = callExport(c.resource, c.resolvePriceExport, truckId, menuItem, fallbackPrice)
        if ok and type(result) == 'number' then
            return math.floor(result)
        end
    end
    return math.floor(tonumber(fallbackPrice) or 0)
end
