local trucks = {}
local openShops = {}
local spawnedVehicle
local spawnedTruckId
local shopBlips = {}
local pendingOrders = {}
local staffCache = {} -- truckId -> { ok=bool, expires=ms }

local function normalizePlate(plate)
    if Keys and Keys.NormalizePlate then
        return Keys.NormalizePlate(plate)
    end
    return (tostring(plate or ''):gsub('^%s+', ''):gsub('%s+$', '')):upper()
end

local function findTruckByPlate(plate)
    plate = normalizePlate(plate)
    if plate == '' then return nil end
    for _, truck in pairs(trucks) do
        local tp = truck.data and truck.data.plate
        if tp and normalizePlate(tp) == plate then
            return truck
        end
    end
    return nil
end

local function findVehicleForTruck(truckId)
    local truck = trucks[truckId]
    local want = truck and truck.data and normalizePlate(truck.data.plate)
    if not want or want == '' then return nil end
    local vehicles = GetGamePool('CVehicle')
    for i = 1, #vehicles do
        local veh = vehicles[i]
        if veh and DoesEntityExist(veh) and normalizePlate(GetVehicleNumberPlateText(veh)) == want then
            return veh
        end
    end
    return nil
end

local function isStaffCached(truckId)
    local now = GetGameTimer()
    local cached = staffCache[truckId]
    if cached and cached.expires > now then
        return cached.ok
    end
    local ok = lib.callback.await('viking_foodtruck:isStaffOf', false, truckId)
    staffCache[truckId] = { ok = ok and true or false, expires = now + 8000 }
    return ok and true or false
end

--- Bind a world vehicle (garage pull / retrieve) so staff menus & shop open work
local function bindActiveTruck(vehicle, truck, opts)
    opts = opts or {}
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    if not truck or not truck.id then return false end

    local already = (spawnedVehicle == vehicle and spawnedTruckId == truck.id)
    spawnedVehicle = vehicle
    spawnedTruckId = truck.id
    trucks[truck.id] = trucks[truck.id] or truck
    if truck.data then
        trucks[truck.id].data = truck.data
    end

    if already and not opts.force then
        return true
    end

    SetVehicleHasBeenOwnedByPlayer(vehicle, true)
    local plate = normalizePlate((truck.data and truck.data.plate) or GetVehicleNumberPlateText(vehicle))
    if plate ~= '' then
        SetVehicleNumberPlateText(vehicle, plate)
        if truck.data then truck.data.plate = plate end
    end

    TriggerEvent('viking_foodtruck:client:vehicleSpawned', vehicle, truck.id)

    if opts.register ~= false then
        CreateThread(function()
            local veh = vehicle
            local truckId = truck.id
            local givePlate = plate
            if not veh or not DoesEntityExist(veh) then return end
            if Keys and Keys.GiveClient then
                Keys.GiveClient(veh, givePlate)
            end
            local netId = NetworkGetNetworkIdFromEntity(veh)
            local ok, savedPlate = lib.callback.await(
                'viking_foodtruck:registerVehicleKeys',
                false,
                truckId,
                givePlate,
                netId
            )
            if ok and type(savedPlate) == 'string' and savedPlate ~= '' then
                givePlate = savedPlate
                if trucks[truckId] and trucks[truckId].data then
                    trucks[truckId].data.plate = savedPlate
                end
            end
            local props = Garage and Garage.GetVehicleProperties and Garage.GetVehicleProperties(veh) or {
                plate = givePlate,
                model = GetEntityModel(veh),
            }
            lib.callback.await(
                'viking_foodtruck:syncGarageProps',
                false,
                truckId,
                givePlate,
                props,
                NetworkGetNetworkIdFromEntity(veh)
            )
        end)
    end
    return true
end

local function resolveVehicleEntity(netId, fallback)
    if fallback and fallback ~= 0 and DoesEntityExist(fallback) then
        return fallback
    end
    if netId then
        local ent = NetworkGetEntityFromNetworkId(netId)
        if ent and ent ~= 0 and DoesEntityExist(ent) then
            return ent
        end
    end
    return 0
end

RegisterNetEvent('viking_foodtruck:client:giveKeys', function(plate, netId)
    local vehicle = resolveVehicleEntity(netId, spawnedVehicle)
    if Keys and Keys.GiveClient then
        Keys.GiveClient(vehicle, plate)
    end
end)

RegisterNetEvent('viking_foodtruck:client:removeKeys', function(plate, netId)
    local vehicle = resolveVehicleEntity(netId, spawnedVehicle)
    if Keys and Keys.RemoveClient then
        Keys.RemoveClient(vehicle, plate)
    end
end)

local function clearShopBlips()
    for id, blip in pairs(shopBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
        shopBlips[id] = nil
    end
end

local function refreshShopBlip(truckId, shop)
    if shopBlips[truckId] and DoesBlipExist(shopBlips[truckId]) then
        RemoveBlip(shopBlips[truckId])
        shopBlips[truckId] = nil
    end
    if not shop then return end
    local def = trucks[truckId]
    if not def or not def.data or not def.data.blip or def.data.blip.enabled == false then return end
    local c = shop.coords
    if not c then return end
    local blip = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(blip, def.data.blip.sprite or 106)
    SetBlipColour(blip, def.data.blip.color or 5)
    SetBlipScale(blip, def.data.blip.scale or 0.75)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(def.label or 'Food Truck')
    EndTextCommandSetBlipName(blip)
    shopBlips[truckId] = blip
end

RegisterNetEvent('viking_foodtruck:client:sync', function(list, shops)
    trucks = {}
    for i = 1, #(list or {}) do
        local t = list[i]
        trucks[t.id] = t
    end
    openShops = shops or {}
    clearShopBlips()
    for id, shop in pairs(openShops) do
        refreshShopBlip(id, shop)
    end
end)

RegisterNetEvent('viking_foodtruck:client:shopState', function(truckId, shop)
    openShops[truckId] = shop
    refreshShopBlip(truckId, shop)
end)

RegisterNetEvent('viking_foodtruck:client:newOrder', function(order)
    pendingOrders[order.id] = order
    Bridge.NotifyLocal(('Order: %s'):format(order.menuItem and order.menuItem.label or 'Food'), 'inform')
end)

RegisterNetEvent('viking_foodtruck:client:orderUpdate', function(_, orderId, status)
    pendingOrders[orderId] = nil
    if status == 'done' then
        -- handled by notify
    end
end)

local function getWindowCoords(vehicle, truck)
    local offset = truck.data and truck.data.windowOffset or { x = 0.0, y = -2.0, z = 0.0 }
    return GetOffsetFromEntityInWorldCoords(vehicle, offset.x + 0.0, offset.y + 0.0, offset.z + 0.0)
end

local function resolveSpawnTransform(truck, opts)
    opts = opts or {}
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)

    -- Explicit spawn coords
    if opts.coords then
        local c = opts.coords
        return vector3(c.x + 0.0, c.y + 0.0, c.z + 0.0), (c.w or c.heading or heading) + 0.0
    end

    -- Purchase from vendor → spawn beside the broker ped (ground-aligned)
    if opts.atVendor and Config.PurchasePed and Config.PurchasePed.coords then
        local p = Config.PurchasePed.coords
        local offset = Config.PurchasePed.spawnOffset or vector3(0.0, 4.0, 0.0)
        local rad = math.rad(p.w or 0.0)
        local x = p.x + (offset.x * math.cos(rad) - offset.y * math.sin(rad))
        local y = p.y + (offset.x * math.sin(rad) + offset.y * math.cos(rad))
        local z = p.z + (offset.z or 0.0)
        RequestCollisionAtCoord(x, y, z)
        local found, groundZ = GetGroundZFor_3dCoord(x + 0.0, y + 0.0, z + 50.0, false)
        if found then z = groundZ end
        return vector3(x, y, z), (p.w or heading) + 0.0
    end

    -- Creator-defined retrieve spot (manual retrieve /foodtruck)
    if truck.data and truck.data.retrieve then
        local r = truck.data.retrieve
        return vector3(r.x + 0.0, r.y + 0.0, r.z + 0.0), (r.w or heading) + 0.0
    end

    return coords, heading
end

local function spawnOwnedTruck(truck, opts)
    if not truck or not truck.id then
        Bridge.NotifyLocal('Invalid truck data', 'error')
        return false
    end

    if spawnedVehicle and DoesEntityExist(spawnedVehicle) then
        if opts and opts.forceReplace then
            if spawnedTruckId and openShops[spawnedTruckId] then
                lib.callback.await('viking_foodtruck:setShopOpen', false, spawnedTruckId, false)
            end
            DeleteEntity(spawnedVehicle)
            spawnedVehicle = nil
            spawnedTruckId = nil
        else
            Bridge.NotifyLocal('Store your current food truck first', 'error')
            return false
        end
    end

    truck.data = truck.data or {}
    local modelName = truck.data.vehicle or Config.DefaultVehicle or 'taco'
    local model = joaat(modelName)
    if not IsModelInCdimage(model) or not IsModelAVehicle(model) then
        Bridge.NotifyLocal('Invalid vehicle model: ' .. modelName, 'error')
        return false
    end

    lib.requestModel(model)
    local coords, heading = resolveSpawnTransform(truck, opts)
    local ped = PlayerPedId()

    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    local found, groundZ = GetGroundZFor_3dCoord(coords.x + 0.0, coords.y + 0.0, coords.z + 50.0, false)
    if found then
        coords = vector3(coords.x, coords.y, groundZ)
    end

    spawnedVehicle = CreateVehicle(model, coords.x, coords.y, coords.z, heading, true, false)
    if not spawnedVehicle or spawnedVehicle == 0 then
        Bridge.NotifyLocal('Failed to spawn food truck', 'error')
        SetModelAsNoLongerNeeded(model)
        return false
    end

    SetEntityAsMissionEntity(spawnedVehicle, true, true)
    SetVehicleOnGroundProperly(spawnedVehicle)
    SetVehicleHasBeenOwnedByPlayer(spawnedVehicle, true)
    SetVehicleNeedsToBeHotwired(spawnedVehicle, false)
    SetVehicleEngineOn(spawnedVehicle, true, true, false)
    SetVehRadioStation(spawnedVehicle, 'OFF')
    SetVehicleDoorsLocked(spawnedVehicle, 1)
    SetVehicleDoorsLockedForAllPlayers(spawnedVehicle, false)

    -- Persistent business plate (owner plate stays with the truck)
    local plate = truck.data.plate
    if type(plate) ~= 'string' or plate == '' then
        plate = ((truck.data.platePrefix or 'FOOD') .. tostring(math.random(100, 999))):sub(1, 8)
    end
    plate = (Keys and Keys.NormalizePlate and Keys.NormalizePlate(plate)) or plate:upper()
    SetVehicleNumberPlateText(spawnedVehicle, plate)
    truck.data.plate = plate

    if truck.data.livery ~= nil then
        SetVehicleLivery(spawnedVehicle, truck.data.livery)
    end

    -- Keep truck data in local cache for interactions
    trucks[truck.id] = trucks[truck.id] or truck
    if truck.data then
        trucks[truck.id].data = truck.data
        trucks[truck.id].label = truck.label or trucks[truck.id].label
    end

    TaskWarpPedIntoVehicle(ped, spawnedVehicle, -1)

    -- Wait for network ownership, then register keys + garage ownership
    local netId = NetworkGetNetworkIdFromEntity(spawnedVehicle)
    SetNetworkIdCanMigrate(netId, true)
    SetNetworkIdExistsOnAllMachines(netId, true)

    CreateThread(function()
        local veh = spawnedVehicle
        local truckId = truck.id
        local givePlate = plate
        local timeout = GetGameTimer() + 5000
        while GetGameTimer() < timeout do
            if not veh or veh == 0 or not DoesEntityExist(veh) then return end
            if NetworkGetEntityIsNetworked(veh) and NetworkHasControlOfEntity(veh) then
                break
            end
            NetworkRequestControlOfEntity(veh)
            Wait(50)
        end
        if not veh or not DoesEntityExist(veh) then return end

        SetVehicleHasBeenOwnedByPlayer(veh, true)
        SetVehicleNumberPlateText(veh, givePlate)
        SetVehicleDoorsLocked(veh, 1)

        local props = Garage and Garage.GetVehicleProperties and Garage.GetVehicleProperties(veh) or nil
        if Keys and Keys.GiveClient then
            Keys.GiveClient(veh, givePlate)
        end

        local ok, savedPlate = lib.callback.await(
            'viking_foodtruck:registerVehicleKeys',
            false,
            truckId,
            givePlate,
            NetworkGetNetworkIdFromEntity(veh)
        )
        if ok and type(savedPlate) == 'string' and savedPlate ~= '' then
            if trucks[truckId] and trucks[truckId].data then
                trucks[truckId].data.plate = savedPlate
            end
            givePlate = savedPlate
        end

        -- Sync live props into garage DB while keeping vehicle OUT
        local vehNet = NetworkGetNetworkIdFromEntity(veh)
        lib.callback.await(
            'viking_foodtruck:syncGarageProps',
            false,
            truckId,
            givePlate,
            props or { plate = givePlate, model = GetEntityModel(veh) },
            vehNet
        )
    end)

    TriggerEvent('viking_foodtruck:client:vehicleSpawned', spawnedVehicle, truck.id)
    SetModelAsNoLongerNeeded(model)
    spawnedTruckId = truck.id
    Bridge.NotifyLocal(opts and opts.notify or 'Food truck ready', 'success')
    return true
end

local function storeOwnedTruck(silent)
    if not spawnedVehicle or not DoesEntityExist(spawnedVehicle) then
        if not silent then
            Bridge.NotifyLocal('No food truck out', 'error')
        end
        return false
    end
    local truckId = spawnedTruckId
    local cached = truckId and trucks[truckId]
    local plate = (cached and cached.data and cached.data.plate)
        or GetVehicleNumberPlateText(spawnedVehicle)
    plate = (Keys and Keys.NormalizePlate and Keys.NormalizePlate(plate))
        or tostring(plate or ''):gsub('^%s+', ''):gsub('%s+$', ''):upper()
    SetVehicleNumberPlateText(spawnedVehicle, plate)

    local netId = NetworkGetNetworkIdFromEntity(spawnedVehicle)
    local props = Garage and Garage.GetVehicleProperties and Garage.GetVehicleProperties(spawnedVehicle) or {}
    props.plate = plate
    if spawnedTruckId and openShops[spawnedTruckId] then
        lib.callback.await('viking_foodtruck:setShopOpen', false, spawnedTruckId, false)
    end

    -- Must succeed in DB before deleting the world vehicle
    local ok, err = lib.callback.await('viking_foodtruck:parkVehicle', false, truckId, plate, props)
    if not ok then
        if not silent then
            Bridge.NotifyLocal(err or 'Failed to save truck to garage', 'error')
        end
        return false
    end

    if Keys and Keys.RemoveClient then
        Keys.RemoveClient(spawnedVehicle, plate)
    end
    lib.callback.await('viking_foodtruck:unregisterVehicleKeys', false, truckId, plate, netId)
    if Target and Target.RemoveEntity then
        Target.RemoveEntity(spawnedVehicle)
    end
    DeleteEntity(spawnedVehicle)
    spawnedVehicle = nil
    spawnedTruckId = nil
    if not silent then
        Bridge.NotifyLocal('Food truck parked in garage', 'inform')
    end
    return true
end

--- Called after buying from the vendor ped
RegisterNetEvent('viking_foodtruck:client:spawnPurchasedTruck', function(truck)
    if not truck then return end
    spawnOwnedTruck(truck, {
        atVendor = true,
        forceReplace = true,
        notify = 'Your food truck has been delivered',
    })
end)

RegisterNetEvent('viking_foodtruck:client:despawnOwnedTruck', function()
    storeOwnedTruck(true)
end)

exports('SpawnOwnedTruck', function(truck, opts)
    return spawnOwnedTruck(truck, opts)
end)

exports('StoreOwnedTruck', function(silent)
    return storeOwnedTruck(silent)
end)

local function placeOrder(truckId, itemIndex, paymentMethod)
    local ok, err = lib.callback.await('viking_foodtruck:placeOrder', false, truckId, itemIndex, paymentMethod)
    if not ok then
        Bridge.NotifyLocal(type(err) == 'string' and err or 'Order failed', 'error')
    end
end

local function buyPrepared(truckId, itemIndex)
    local ok, err = lib.callback.await('viking_foodtruck:buyPrepared', false, truckId, itemIndex, 'instant')
    if not ok then
        Bridge.NotifyLocal(type(err) == 'string' and err or 'Purchase failed', 'error')
    end
end

local function openCustomerMenu(truckId)
    lib.hideTextUI()
    local shopData = lib.callback.await('viking_foodtruck:getShopMenu', false, truckId)
    if not shopData or not shopData.menu then
        Bridge.NotifyLocal('Shop unavailable or closed', 'error')
        return
    end
    -- Keep local cache warm
    trucks[truckId] = trucks[truckId] or { id = truckId, label = shopData.label, data = {} }

    local billing = lib.callback.await('viking_foodtruck:getBillingConfig', false) or {}
    local options = {}
    for i = 1, #shopData.menu do
        local item = shopData.menu[i]
        local price = item.price or 0
        local prepared = tonumber(item.prepared) or 0
        local idx = item.index or i

        if prepared > 0 then
            options[#options + 1] = {
                title = ('%s  ·  Ready x%s'):format(item.label or item.item, prepared),
                description = ('$%s — buy now (already made)'):format(price),
                icon = 'basket-shopping',
                onSelect = function()
                    buyPrepared(truckId, idx)
                end,
            }
        end

        if billing.mode == 'bill' and billing.allowBill then
            options[#options + 1] = {
                title = item.label or item.item,
                description = ('Invoice $%s — cook to order'):format(price),
                icon = 'file-invoice-dollar',
                onSelect = function()
                    placeOrder(truckId, idx, 'bill')
                end,
            }
        elseif billing.mode == 'choice' and billing.allowBill then
            options[#options + 1] = {
                title = item.label or item.item,
                description = ('$%s — order to cook'):format(price),
                icon = 'utensils',
                onSelect = function()
                    lib.registerContext({
                        id = 'viking_foodtruck_pay_choice',
                        title = item.label or item.item,
                        options = {
                            {
                                title = 'Pay Now',
                                description = ('Cash/Bank $%s'):format(price),
                                icon = 'money-bill',
                                onSelect = function()
                                    placeOrder(truckId, idx, 'instant')
                                end,
                            },
                            {
                                title = 'Send Bill',
                                description = ('Invoice $%s via %s'):format(price, billing.system or 'billing'),
                                icon = 'file-invoice-dollar',
                                onSelect = function()
                                    placeOrder(truckId, idx, 'bill')
                                end,
                            },
                        },
                    })
                    lib.showContext('viking_foodtruck_pay_choice')
                end,
            }
        else
            options[#options + 1] = {
                title = item.label or item.item,
                description = prepared > 0
                    and ('$%s — cook to order (or buy Ready above)'):format(price)
                    or ('$%s — cook to order'):format(price),
                icon = 'utensils',
                onSelect = function()
                    placeOrder(truckId, idx, 'instant')
                end,
            }
        end
    end
    if #options == 0 then
        Bridge.NotifyLocal('No menu items', 'error')
        return
    end
    lib.registerContext({
        id = 'viking_foodtruck_customer',
        title = ('Order — %s'):format(shopData.label or 'Food Truck'),
        options = options,
    })
    lib.showContext('viking_foodtruck_customer')
end

local function openMyBillsMenu()
    local bills = lib.callback.await('viking_foodtruck:getMyBills', false) or {}
    if #bills == 0 then
        Bridge.NotifyLocal(Config.Locale.no_bills or 'No unpaid bills', 'inform')
        return
    end
    local options = {}
    for i = 1, #bills do
        local bill = bills[i]
        options[#options + 1] = {
            title = ('$%s — %s'):format(bill.amount, bill.reason or bill.id),
            description = bill.id,
            icon = 'file-invoice',
            onSelect = function()
                local confirm = lib.alertDialog({
                    header = 'Pay Bill',
                    content = ('Pay $%s now?'):format(bill.amount),
                    centered = true,
                    cancel = true,
                })
                if confirm ~= 'confirm' then return end
                local ok, err = lib.callback.await('viking_foodtruck:payBill', false, bill.id)
                if not ok then
                    Bridge.NotifyLocal(type(err) == 'string' and err or 'Payment failed', 'error')
                end
            end,
        }
    end
    lib.registerContext({
        id = 'viking_foodtruck_bills',
        title = 'Food Truck Bills',
        options = options,
    })
    lib.showContext('viking_foodtruck_bills')
end

RegisterCommand('foodtruckbills', function()
    openMyBillsMenu()
end, false)

RegisterNetEvent('viking_foodtruck:client:billCreated', function(bill)
    Bridge.NotifyLocal(('Bill received: $%s'):format(bill.amount or 0), 'inform')
end)

local function doCraft(truckId, itemIndex, item, amount, destination)
    local cookMs = (item.cookMs or Config.DefaultCookMs or 8000) * math.max(1, math.min(amount, 3))
    local success = lib.progressBar({
        duration = math.min(cookMs, 20000),
        label = ('Crafting %s x%s'):format(item.label or item.item, amount),
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = {
            dict = 'amb@prop_human_bbq@male@base',
            clip = 'base',
        },
    })
    if not success then return end
    local ok, result = lib.callback.await('viking_foodtruck:craftFood', false, truckId, itemIndex, amount, destination)
    if not ok then
        Bridge.NotifyLocal(type(result) == 'string' and result or 'Craft failed', 'error')
        return
    end
    local crafted = type(result) == 'table' and result.crafted or amount
    local dest = type(result) == 'table' and result.destination or destination
    if dest == 'stock' then
        Bridge.NotifyLocal(('Stored %s x%s on truck (ready to sell)'):format(item.label or item.item, crafted), 'success')
    elseif dest == 'both' then
        Bridge.NotifyLocal(('Crafted %s x%s — inventory + truck stock'):format(item.label or item.item, crafted), 'success')
    else
        Bridge.NotifyLocal(('Crafted %s x%s into your inventory'):format(item.label or item.item, crafted), 'success')
    end
end

function openCraftMenu(truckId)
    local data = lib.callback.await('viking_foodtruck:getManageData', false, truckId)
    if not data then
        Bridge.NotifyLocal(Config.Locale.not_owner, 'error')
        return
    end
    local menu = (data.truck.data and data.truck.data.menu) or {}
    local options = {}
    for i = 1, #menu do
        local item = menu[i]
        local ingText = {}
        for _, ing in ipairs(item.ingredients or {}) do
            ingText[#ingText + 1] = ('%sx %s'):format(ing.count or 1, ing.item)
        end
        options[#options + 1] = {
            title = item.label or item.item,
            description = (#ingText > 0 and table.concat(ingText, ', ') or 'No ingredients') .. ' · cook from stock/inv',
            icon = 'fire-burner',
            onSelect = function()
                local input = lib.inputDialog('Craft ' .. (item.label or item.item), {
                    { type = 'number', label = 'Amount', default = 1, min = 1, max = 10, required = true },
                })
                local amount = input and tonumber(input[1]) or 1
                if amount < 1 then amount = 1 end

                local craftMode = Config.CraftOutput or 'ask'
                if craftMode == 'ask' then
                    lib.registerContext({
                        id = 'viking_foodtruck_craft_dest',
                        title = 'Where should it go?',
                        options = {
                            {
                                title = 'My Inventory',
                                description = 'Give cooked food to you',
                                icon = 'briefcase',
                                onSelect = function()
                                    doCraft(truckId, i, item, amount, 'inventory')
                                end,
                            },
                            {
                                title = 'Truck Stock (For Sale)',
                                description = 'Store on truck — customers can buy Ready items',
                                icon = 'store',
                                onSelect = function()
                                    doCraft(truckId, i, item, amount, 'stock')
                                end,
                            },
                            {
                                title = 'Both',
                                description = 'One set in inventory + one set on truck',
                                icon = 'clone',
                                onSelect = function()
                                    doCraft(truckId, i, item, amount, 'both')
                                end,
                            },
                        },
                    })
                    lib.showContext('viking_foodtruck_craft_dest')
                else
                    doCraft(truckId, i, item, amount, craftMode)
                end
            end,
        }
    end
    if #options == 0 then
        Bridge.NotifyLocal('No craftable menu items', 'error')
        return
    end
    lib.registerContext({
        id = 'viking_foodtruck_craft',
        title = 'Craft Food',
        options = options,
    })
    lib.showContext('viking_foodtruck_craft')
end

local function openStockInventory(truckId)
    local view = lib.callback.await('viking_foodtruck:getStockView', false, truckId)
    if not view then
        Bridge.NotifyLocal(Config.Locale.not_owner, 'error')
        return
    end
    lib.showStockInventory(view)
end

AddEventHandler('viking_foodtruck:client:stockInvAction', function(body)
    local truckId = body.truckId
    local item = body.item
    local action = body.action
    if not truckId or not action then return end

    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'stockInv', data = { show = false } })
    Wait(80)

    if action == 'take' then
        if not item then return end
        local input = lib.inputDialog('Take from Truck', {
            { type = 'number', label = 'Amount', default = 1, min = 1, max = 50, required = true },
        })
        local count = input and tonumber(input[1]) or 0
        if count < 1 then return end
        local ok, err = lib.callback.await('viking_foodtruck:withdrawStock', false, truckId, item, count)
        if not ok then
            Bridge.NotifyLocal(type(err) == 'string' and err or 'Failed', 'error')
        else
            Bridge.NotifyLocal(('Took %sx %s'):format(count, item), 'success')
        end
        openStockInventory(truckId)
    elseif action == 'deposit' then
        local input
        if item and item ~= '' then
            input = lib.inputDialog('Deposit to Truck', {
                { type = 'number', label = ('Amount of %s'):format(item), default = 1, min = 1, max = 50, required = true },
            })
            local count = input and tonumber(input[1]) or 0
            if count < 1 then return end
            local ok, err = lib.callback.await('viking_foodtruck:depositStock', false, truckId, item, count)
            if not ok then
                Bridge.NotifyLocal(type(err) == 'string' and err or 'Failed', 'error')
            else
                Bridge.NotifyLocal(('Deposited %sx %s'):format(count, item), 'success')
            end
        else
            input = lib.inputDialog('Deposit to Truck', {
                { type = 'input', label = 'Item name', required = true },
                { type = 'number', label = 'Amount', default = 1, min = 1, max = 50, required = true },
            })
            if not input then return end
            local ok, err = lib.callback.await('viking_foodtruck:depositStock', false, truckId, input[1], input[2])
            if not ok then
                Bridge.NotifyLocal(type(err) == 'string' and err or 'Failed', 'error')
            else
                Bridge.NotifyLocal('Stock deposited', 'success')
            end
        end
        openStockInventory(truckId)
    elseif action == 'refresh' then
        openStockInventory(truckId)
    end
end)

local function openStaffMenu(truckId)
    local data = lib.callback.await('viking_foodtruck:getManageData', false, truckId)
    if not data then
        Bridge.NotifyLocal(Config.Locale.not_owner, 'error')
        return
    end

    local options = {
        {
            title = data.shopOpen and 'Close Shop' or 'Open Shop',
            icon = data.shopOpen and 'store-slash' or 'store',
            onSelect = function()
                local veh = spawnedVehicle
                if (not veh or not DoesEntityExist(veh)) then
                    veh = findVehicleForTruck(truckId)
                    if veh and data.truck then
                        bindActiveTruck(veh, data.truck, { register = true })
                    end
                end
                local coords
                local netId
                if veh and DoesEntityExist(veh) then
                    coords = GetEntityCoords(veh)
                    netId = NetworkGetNetworkIdFromEntity(veh)
                else
                    coords = GetEntityCoords(PlayerPedId())
                end
                lib.callback.await('viking_foodtruck:setShopOpen', false, truckId, not data.shopOpen, netId, {
                    x = coords.x, y = coords.y, z = coords.z,
                })
            end,
        },
        {
            title = 'Retrieve / Store Truck',
            icon = 'truck',
            onSelect = function()
                local veh = spawnedVehicle
                if (not veh or not DoesEntityExist(veh)) then
                    veh = findVehicleForTruck(truckId)
                end
                if veh and DoesEntityExist(veh) then
                    bindActiveTruck(veh, data.truck or trucks[truckId], { register = false })
                    storeOwnedTruck()
                else
                    spawnOwnedTruck(data.truck)
                end
            end,
        },
        {
            title = ('Business Balance: $%s'):format(data.account.balance or 0),
            icon = 'wallet',
            disabled = true,
        },
    }

    if data.isOwner then
        options[#options + 1] = {
            title = 'Withdraw Balance',
            icon = 'money-bill',
            onSelect = function()
                local input = lib.inputDialog('Withdraw', {
                    { type = 'number', label = 'Amount', min = 1, required = true },
                })
                if not input then return end
                local ok, err = lib.callback.await('viking_foodtruck:withdrawBalance', false, truckId, input[1])
                if not ok then Bridge.NotifyLocal(type(err) == 'string' and err or 'Failed', 'error') end
            end,
        }
        options[#options + 1] = {
            title = 'Deposit Balance',
            icon = 'piggy-bank',
            onSelect = function()
                local input = lib.inputDialog('Deposit', {
                    { type = 'number', label = 'Amount', min = 1, required = true },
                })
                if not input then return end
                local ok, err = lib.callback.await('viking_foodtruck:depositBalance', false, truckId, input[1])
                if not ok then Bridge.NotifyLocal(type(err) == 'string' and err or 'Failed', 'error') end
            end,
        }
        options[#options + 1] = {
            title = 'Hire Nearby Player',
            icon = 'user-plus',
            onSelect = function()
                local input = lib.inputDialog('Hire Employee', {
                    { type = 'number', label = 'Server ID', min = 1, required = true },
                })
                if not input then return end
                local ok, err = lib.callback.await('viking_foodtruck:hire', false, truckId, input[1])
                if not ok then Bridge.NotifyLocal(type(err) == 'string' and err or 'Failed', 'error') end
            end,
        }
        if data.account.employees and #data.account.employees > 0 then
            for i = 1, #data.account.employees do
                local emp = data.account.employees[i]
                options[#options + 1] = {
                    title = 'Fire ' .. emp,
                    icon = 'user-minus',
                    onSelect = function()
                        lib.callback.await('viking_foodtruck:fire', false, truckId, emp)
                    end,
                }
            end
        end
    end

    options[#options + 1] = {
        title = 'Craft Food',
        icon = 'utensils',
        description = 'Cook into your inventory or truck stock (for sale)',
        onSelect = function()
            openCraftMenu(truckId)
        end,
    }

    options[#options + 1] = {
        title = 'View Stock',
        icon = 'boxes-stacked',
        description = 'Inventory of ingredients + prepared food',
        onSelect = function()
            openStockInventory(truckId)
        end,
    }

    options[#options + 1] = {
        title = 'Deposit Stock Item',
        icon = 'box',
        onSelect = function()
            local input = lib.inputDialog('Deposit Stock', {
                { type = 'input', label = 'Item name', required = true },
                { type = 'number', label = 'Count', min = 1, required = true },
            })
            if not input then return end
            local ok, err = lib.callback.await('viking_foodtruck:depositStock', false, truckId, input[1], input[2])
            if not ok then Bridge.NotifyLocal(type(err) == 'string' and err or 'Failed', 'error')
            else Bridge.NotifyLocal('Stock deposited', 'success') end
        end,
    }

    local truckBills = lib.callback.await('viking_foodtruck:getTruckBills', false, truckId) or {}
    if #truckBills > 0 then
        options[#options + 1] = {
            title = ('Unpaid Invoices (%s)'):format(#truckBills),
            icon = 'file-invoice-dollar',
            description = 'Customers still owe for orders',
            disabled = true,
        }
        for i = 1, math.min(#truckBills, 8) do
            local bill = truckBills[i]
            options[#options + 1] = {
                title = ('$%s — %s'):format(bill.amount, bill.reason or bill.id),
                description = bill.to_id or '',
                icon = 'receipt',
                disabled = true,
            }
        end
    end

    local orders = data.orders or {}
    for i = 1, #orders do
        local order = orders[i]
        options[#options + 1] = {
            title = ('Cook: %s ($%s)'):format(order.menuItem.label or order.menuItem.item, order.price),
            description = 'For ' .. (order.customerName or 'customer'),
            icon = 'fire-burner',
            onSelect = function()
                local cookMs = order.menuItem.cookMs or Config.DefaultCookMs or 8000
                local success = lib.progressBar({
                    duration = cookMs,
                    label = 'Cooking ' .. (order.menuItem.label or order.menuItem.item),
                    useWhileDead = false,
                    canCancel = true,
                    disable = { move = true, car = true, combat = true },
                    anim = {
                        dict = 'amb@prop_human_bbq@male@base',
                        clip = 'base',
                    },
                })
                if not success then return end
                local ok, err = lib.callback.await('viking_foodtruck:fulfillOrder', false, order.id)
                if not ok then
                    Bridge.NotifyLocal(type(err) == 'string' and err or 'Cook failed', 'error')
                else
                    Bridge.NotifyLocal('Order complete', 'success')
                end
            end,
        }
        options[#options + 1] = {
            title = 'Cancel Order: ' .. (order.menuItem.label or ''),
            icon = 'ban',
            onSelect = function()
                lib.callback.await('viking_foodtruck:cancelOrder', false, order.id, true)
            end,
        }
    end

    lib.registerContext({
        id = 'viking_foodtruck_staff',
        title = data.truck.label,
        options = options,
    })
    lib.showContext('viking_foodtruck_staff')
end

local function openMyTruckMenu()
    local owned = lib.callback.await('viking_foodtruck:getOwned', false)
    if not owned then
        Bridge.NotifyLocal('You do not own or work at a food truck', 'error')
        return
    end
    openStaffMenu(owned.id)
end

RegisterCommand('foodtruck', function()
    openMyTruckMenu()
end, false)

-- When a garage (or any script) spawns our plate, reclaim it for menus/targets
CreateThread(function()
    while true do
        local wait = 2000
        if spawnedVehicle and not DoesEntityExist(spawnedVehicle) then
            spawnedVehicle = nil
            spawnedTruckId = nil
        end

        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local veh = GetVehiclePedIsIn(ped, false)
        if veh == 0 then
            local vehicles = GetGamePool('CVehicle')
            local best, bestDist
            for i = 1, #vehicles do
                local v = vehicles[i]
                if v and DoesEntityExist(v) then
                    local d = #(coords - GetEntityCoords(v))
                    if d < 10.0 and (not bestDist or d < bestDist) then
                        local truck = findTruckByPlate(GetVehicleNumberPlateText(v))
                        if truck then
                            best, bestDist = v, d
                        end
                    end
                end
            end
            veh = best or 0
            if bestDist and bestDist < 10.0 then wait = 1000 end
        else
            wait = 1000
        end

        if veh and veh ~= 0 and DoesEntityExist(veh) then
            local truck = findTruckByPlate(GetVehicleNumberPlateText(veh))
            if truck and isStaffCached(truck.id) then
                if spawnedVehicle ~= veh or spawnedTruckId ~= truck.id then
                    bindActiveTruck(veh, truck, { register = true })
                end
            end
        end

        Wait(wait)
    end
end)

-- Interaction loop: owners can buy from OTHER trucks; staff window on own truck
local runtimePromptShown = false
local runtimePromptText = nil
CreateThread(function()
    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local prompt
        local promptAction
        local allowOwnerBuy = Config.AllowOwnerCustomerPurchases ~= false

        -- Re-resolve staff vehicle from plate if garage-spawned
        if (not spawnedVehicle or not DoesEntityExist(spawnedVehicle)) and spawnedTruckId then
            local veh = findVehicleForTruck(spawnedTruckId)
            if veh then
                bindActiveTruck(veh, trucks[spawnedTruckId], { register = false })
            end
        end

        -- Nearest open shop for customer ordering (prefer other trucks over own)
        local bestOtherId, bestOtherDist
        local bestAnyId, bestAnyDist
        for truckId, shop in pairs(openShops) do
            local truck = trucks[truckId]
            if truck and shop.coords then
                local dist = #(coords - vector3(shop.coords.x + 0.0, shop.coords.y + 0.0, shop.coords.z + 0.0))
                local radius = (truck.data and truck.data.shopRadius) or Config.InteractDistance or 3.0
                if dist < radius + 12.0 then
                    sleep = 0
                end
                if dist < radius then
                    if not bestAnyDist or dist < bestAnyDist then
                        bestAnyDist = dist
                        bestAnyId = truckId
                    end
                    if truckId ~= spawnedTruckId then
                        if not bestOtherDist or dist < bestOtherDist then
                            bestOtherDist = dist
                            bestOtherId = truckId
                        end
                    end
                end
            end
        end

        local customerId = bestOtherId
        if not customerId and bestAnyId and (not spawnedTruckId or bestAnyId ~= spawnedTruckId or allowOwnerBuy) then
            customerId = bestAnyId
        end

        local staffDist
        if spawnedVehicle and DoesEntityExist(spawnedVehicle) and spawnedTruckId then
            local window = getWindowCoords(spawnedVehicle, trucks[spawnedTruckId] or { data = {} })
            staffDist = #(coords - window)
            if staffDist < 12.0 then sleep = 0 end
        elseif not spawnedTruckId then
            -- Staff standing near their garage-pulled truck by plate
            local vehicles = GetGamePool('CVehicle')
            for i = 1, #vehicles do
                local v = vehicles[i]
                if v and DoesEntityExist(v) then
                    local truck = findTruckByPlate(GetVehicleNumberPlateText(v))
                    if truck and #(coords - GetEntityCoords(v)) < 12.0 and isStaffCached(truck.id) then
                        bindActiveTruck(v, truck, { register = true })
                        local window = getWindowCoords(v, truck)
                        staffDist = #(coords - window)
                        if staffDist < 12.0 then sleep = 0 end
                        break
                    end
                end
            end
        end

        -- Priority: other-truck customer > staff window > own-truck customer
        if bestOtherId then
            prompt = Config.Locale.customer_prompt
            promptAction = function()
                openCustomerMenu(bestOtherId)
            end
        elseif staffDist and staffDist < (Config.InteractDistance or 3.0) then
            prompt = Config.Locale.staff_prompt
            promptAction = function()
                openStaffMenu(spawnedTruckId)
            end
        elseif customerId and (not staffDist or staffDist >= (Config.InteractDistance or 3.0)) then
            prompt = Config.Locale.customer_prompt
            promptAction = function()
                openCustomerMenu(customerId)
            end
        end

        if prompt then
            if not runtimePromptShown or runtimePromptText ~= prompt then
                lib.showTextUI(prompt)
                runtimePromptShown = true
                runtimePromptText = prompt
            end
            if IsControlJustReleased(0, 38) and promptAction then
                promptAction()
            end
        elseif runtimePromptShown then
            lib.hideTextUI()
            runtimePromptShown = false
            runtimePromptText = nil
        end

        Wait(sleep)
    end
end)

-- Eat / drink progress for QB-ESX useable items (ox uses its own usetime + hook)
RegisterNetEvent('viking_foodtruck:client:useFood', function(itemName, slot)
    itemName = tostring(itemName or '')
    if itemName == '' then return end
    local isDrink = itemName == 'water' or itemName == 'cola' or itemName:find('drink') or itemName:find('soda')
    local label = isDrink and 'Drinking...' or 'Eating...'
    local anim = isDrink
        and { dict = 'mp_player_intdrink', clip = 'loop_bottle' }
        or { dict = 'mp_player_inteat@burger', clip = 'mp_player_int_eat_burger' }

    local success = true
    if lib and lib.progressBar then
        success = lib.progressBar({
            duration = isDrink and 2500 or 4000,
            label = label,
            useWhileDead = false,
            canCancel = true,
            disable = { combat = true },
            anim = anim,
        })
    else
        Wait(isDrink and 2500 or 4000)
    end
    if not success then return end
    TriggerServerEvent('viking_foodtruck:server:finishConsume', itemName, slot)
end)

RegisterNetEvent('viking_foodtruck:client:consumeFx', function(def)
    -- Light feedback when ox/other systems already handled the anim
    if not def then return end
end)

-- Exports / events for target bridge
exports('OpenCustomerMenu', function(truckId)
    openCustomerMenu(truckId)
end)

exports('OpenStaffMenu', function(truckId)
    openStaffMenu(truckId)
end)

exports('OpenCraftMenu', function(truckId)
    openCraftMenu(truckId)
end)

exports('GetSpawnedTruck', function()
    return spawnedVehicle, spawnedTruckId
end)

RegisterNetEvent('viking_foodtruck:client:openCustomer', function(truckId)
    openCustomerMenu(truckId)
end)

RegisterNetEvent('viking_foodtruck:client:openStaff', function(truckId)
    openStaffMenu(truckId or spawnedTruckId)
end)

RegisterNetEvent('viking_foodtruck:client:openCraft', function(truckId)
    openCraftMenu(truckId or spawnedTruckId)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearShopBlips()
    if Target and Target.ClearAll then Target.ClearAll() end
    if spawnedVehicle and DoesEntityExist(spawnedVehicle) then
        DeleteEntity(spawnedVehicle)
    end
end)

-- Request sync on start
CreateThread(function()
    Wait(1500)
    TriggerServerEvent('viking_foodtruck:server:requestSync')
end)
