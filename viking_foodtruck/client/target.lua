--[[
    Wires Target bridge options onto open shops + spawned food truck entity.
]]

local function shopOptions(truckId)
    return {
        {
            name = 'ft_order_' .. truckId,
            label = 'Order Food',
            icon = 'fas fa-utensils',
            distance = Config.InteractDistance or 2.5,
            onSelect = function()
                exports[GetCurrentResourceName()]:OpenCustomerMenu(truckId)
            end,
        },
    }
end

local function staffVehicleOptions(truckId)
    local opts = {
        {
            name = 'ft_manage_' .. truckId,
            label = 'Manage Food Truck',
            icon = 'fas fa-clipboard-list',
            distance = Config.InteractDistance or 2.5,
            onSelect = function()
                exports[GetCurrentResourceName()]:OpenStaffMenu(truckId)
            end,
        },
        {
            name = 'ft_craft_' .. truckId,
            label = 'Craft Food',
            icon = 'fas fa-fire-burner',
            distance = Config.InteractDistance or 2.5,
            onSelect = function()
                exports[GetCurrentResourceName()]:OpenCraftMenu(truckId)
            end,
        },
    }
    return opts
end

local function refreshShopTargets()
    if not Target or not Target.IsActive or not Target.IsActive() then return end
    -- Rebuild from current open shops state via event payload cache on runtime
end

RegisterNetEvent('viking_foodtruck:client:shopState', function(truckId, shop)
    if not Target or not Target.IsActive or not Target.IsActive() then return end
    Target.RemoveShopZone(truckId)
    if shop and shop.coords then
        Target.AddShopZone(truckId, shop.coords, shopOptions(truckId))
    end
    -- Also target the vehicle entity if networked
    if shop and shop.netId then
        local ent = NetworkGetEntityFromNetworkId(shop.netId)
        if ent and ent ~= 0 and DoesEntityExist(ent) then
            Target.RemoveEntity(ent)
            local opts = shopOptions(truckId)
            -- Staff of this truck also get manage/craft on the entity
            local isStaff = lib.callback.await('viking_foodtruck:isStaffOf', false, truckId)
            if isStaff then
                local staffOpts = staffVehicleOptions(truckId)
                for i = 1, #staffOpts do
                    opts[#opts + 1] = staffOpts[i]
                end
            end
            Target.AddEntity(ent, opts)
        end
    end
end)

RegisterNetEvent('viking_foodtruck:client:sync', function(_, shops)
    if not Target or not Target.IsActive or not Target.IsActive() then return end
    Target.ClearAll()
    for truckId, shop in pairs(shops or {}) do
        if shop and shop.coords then
            Target.AddShopZone(truckId, shop.coords, shopOptions(truckId))
        end
        if shop and shop.netId then
            local ent = NetworkGetEntityFromNetworkId(shop.netId)
            if ent and ent ~= 0 and DoesEntityExist(ent) then
                local opts = shopOptions(truckId)
                local isStaff = lib.callback.await('viking_foodtruck:isStaffOf', false, truckId)
                if isStaff then
                    local staffOpts = staffVehicleOptions(truckId)
                    for i = 1, #staffOpts do
                        opts[#opts + 1] = staffOpts[i]
                    end
                end
                Target.AddEntity(ent, opts)
            end
        end
    end
end)

AddEventHandler('viking_foodtruck:client:vehicleSpawned', function(vehicle, truckId)
    if not vehicle or not DoesEntityExist(vehicle) then return end
    if not Target or not Target.IsActive or not Target.IsActive() then return end
    Target.RemoveEntity(vehicle)
    Target.AddEntity(vehicle, staffVehicleOptions(truckId))
end)

-- Re-attach targets when the truck was pulled from a garage (not script-spawned)
CreateThread(function()
    while true do
        Wait(4000)
        if Target and Target.IsActive and Target.IsActive() then
            local veh, truckId = exports[GetCurrentResourceName()]:GetSpawnedTruck()
            if veh and veh ~= 0 and DoesEntityExist(veh) and truckId then
                Target.RemoveEntity(veh)
                Target.AddEntity(veh, staffVehicleOptions(truckId))
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if Target and Target.ClearAll then Target.ClearAll() end
end)

CreateThread(function()
    Wait(2000)
    if Target and Target.GetType then
        print(('[viking_foodtruck] Target bridge: %s'):format(Target.GetType()))
    end
end)
