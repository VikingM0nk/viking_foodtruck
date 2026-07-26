Trucks = {
    cache = {},
}

local creatorOpen = {}

local function sanitizeId(id)
    if type(id) ~= 'string' then return nil end
    id = id:lower():gsub('%s+', '_'):gsub('[^a-z0-9_]', '')
    if id == '' or #id > 64 then return nil end
    return id
end

local function clamp(n, min, max)
    n = tonumber(n) or min
    if n < min then return min end
    if n > max then return max end
    return n
end

local function vehicleAllowed(model)
    if type(model) ~= 'string' or model == '' then return false end
    model = model:lower()
    local list = Config.VehicleWhitelist
    if not list or #list == 0 then return true end
    for i = 1, #list do
        if list[i]:lower() == model then return true end
    end
    return false
end

local function sanitizeMenu(menu)
    local out = {}
    if type(menu) ~= 'table' then return out end
    local maxItems = Config.MaxMenuItems or 24
    local maxIng = Config.MaxIngredientsPerItem or 8
    for i = 1, math.min(#menu, maxItems) do
        local row = menu[i]
        if type(row) == 'table' and type(row.item) == 'string' and row.item ~= '' then
            local ingredients = {}
            if type(row.ingredients) == 'table' then
                for j = 1, math.min(#row.ingredients, maxIng) do
                    local ing = row.ingredients[j]
                    if type(ing) == 'table' and type(ing.item) == 'string' and ing.item ~= '' then
                        ingredients[#ingredients + 1] = {
                            item = ing.item:lower():gsub('%s+', '_'),
                            count = clamp(ing.count, 1, 50),
                        }
                    end
                end
            end
            out[#out + 1] = {
                item = row.item:lower():gsub('%s+', '_'),
                label = tostring(row.label or row.item):sub(1, 64),
                price = clamp(row.price, 0, 1000000),
                cookMs = clamp(row.cookMs or Config.DefaultCookMs, 500, 120000),
                category = tostring(row.category or 'food'):sub(1, 32),
                hunger = clamp(row.hunger or 0, 0, 100),
                thirst = clamp(row.thirst or 0, 0, 100),
                stress = clamp(row.stress or 0, 0, 100),
                ingredients = ingredients,
            }
        end
    end
    return out
end

local function sanitizeData(data)
    data = type(data) == 'table' and data or {}
    local vehicle = tostring(data.vehicle or Config.DefaultVehicle or 'taco'):lower()
    if not vehicleAllowed(vehicle) then
        vehicle = Config.DefaultVehicle or 'taco'
    end
    local blip = type(data.blip) == 'table' and data.blip or {}
    local window = type(data.windowOffset) == 'table' and data.windowOffset or {}
    local startingStock = {}
    if type(data.startingStock) == 'table' then
        for item, count in pairs(data.startingStock) do
            if type(item) == 'string' then
                startingStock[item:lower()] = clamp(count, 0, Config.MaxStockPerItem or 250)
            end
        end
    end
    local retrieve
    if type(data.retrieve) == 'table' and data.retrieve.x then
        retrieve = {
            x = tonumber(data.retrieve.x) + 0.0,
            y = tonumber(data.retrieve.y) + 0.0,
            z = tonumber(data.retrieve.z) + 0.0,
            w = tonumber(data.retrieve.w or data.retrieve.heading) or 0.0,
        }
    end
    return {
        description = tostring(data.description or ''):sub(1, 280),
        vehicle = vehicle,
        platePrefix = tostring(data.platePrefix or 'FOOD'):upper():gsub('[^A-Z0-9]', ''):sub(1, 6),
        livery = data.livery ~= nil and tonumber(data.livery) or nil,
        extras = type(data.extras) == 'table' and data.extras or {},
        blip = {
            enabled = blip.enabled ~= false,
            sprite = clamp(blip.sprite or Config.DefaultBlip.sprite, 1, 900),
            color = clamp(blip.color or Config.DefaultBlip.color, 0, 85),
            scale = clamp(blip.scale or Config.DefaultBlip.scale, 0.3, 2.0),
        },
        shopRadius = clamp(data.shopRadius or 3.0, 1.0, 15.0),
        windowOffset = {
            x = tonumber(window.x) or 0.0,
            y = tonumber(window.y) or -2.0,
            z = tonumber(window.z) or 0.0,
        },
        menu = sanitizeMenu(data.menu),
        maxStock = clamp(data.maxStock or Config.MaxStockPerItem, 1, 1000),
        startingStock = startingStock,
        retrieve = retrieve,
    }
end

function Trucks.All()
    return Trucks.cache
end

function Trucks.Get(id)
    return Trucks.cache[id]
end

function Trucks.List()
    local list = {}
    for _, truck in pairs(Trucks.cache) do
        list[#list + 1] = truck
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

function Trucks.EnabledPublic()
    local list = {}
    for _, truck in pairs(Trucks.cache) do
        if truck.enabled then
            list[#list + 1] = {
                id = truck.id,
                label = truck.label,
                category = truck.category,
                price = truck.price,
                description = (truck.data and truck.data.description) or truck.description or '',
                owner_id = truck.owner_id,
                data = {
                    vehicle = truck.data.vehicle,
                    blip = truck.data.blip,
                    shopRadius = truck.data.shopRadius,
                    windowOffset = truck.data.windowOffset,
                    menu = truck.data.menu,
                    platePrefix = truck.data.platePrefix,
                },
            }
        end
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

function Trucks.Reload()
    Trucks.cache = {}
    local rows = DB.LoadAllTrucks()
    for i = 1, #rows do
        local t = rows[i]
        t.data = sanitizeData(t.data)
        Trucks.cache[t.id] = t
        DB.EnsureAccount(t.id, t.data.startingStock)
        if Consumables and Consumables.RegisterMenu then
            Consumables.RegisterMenu(t.data.menu)
        end
    end
end

function Trucks.Sync(target)
    local payload = Trucks.EnabledPublic()
    if target then
        TriggerClientEvent('viking_foodtruck:client:sync', target, payload, Business.GetOpenShops())
    else
        TriggerClientEvent('viking_foodtruck:client:sync', -1, payload, Business.GetOpenShops())
    end
end

local function seedTemplates()
    if DB.CountTrucks() > 0 then return end
    for _, def in ipairs(FoodTruckTemplates.GetAll()) do
        local truck = {
            id = def.id,
            label = def.label,
            category = def.category,
            enabled = def.enabled ~= false,
            price = def.price or 0,
            data = sanitizeData(def.data),
            owner_id = nil,
            created_by = 'template',
            description = def.description,
        }
        truck.data.description = def.description or ''
        DB.UpsertTruck(truck)
        DB.EnsureAccount(truck.id, truck.data.startingStock)
    end
end

CreateThread(function()
    DB.EnsureTables()
    seedTemplates()
    Trucks.Reload()

    if type(Bridge) == 'table' and Bridge.EnsureFoodTruckJob then
        local ok, err = pcall(Bridge.EnsureFoodTruckJob)
        if not ok then
            print(('[viking_foodtruck] EnsureFoodTruckJob failed: %s'):format(tostring(err)))
        end
    else
        print('[viking_foodtruck] WARNING: Bridge missing — bridges/framework.lua did not load. Re-ensure the resource from FiveM Scripts/viking_foodtruck')
    end

    local fw = (type(Bridge) == 'table' and Bridge.GetType and Bridge.GetType()) or 'n/a'
    local inv = (type(Inv) == 'table' and Inv.GetType and Inv.GetType()) or 'n/a'
    local bank = (type(Banking) == 'table' and Banking.GetType and Banking.GetType()) or 'n/a'
    local billing = (type(Billing) == 'table' and Billing.GetType and Billing.GetType()) or 'n/a'
    local food = (type(Food) == 'table' and Food.GetType and Food.GetType()) or 'n/a'
    local restaurant = (type(Restaurant) == 'table' and Restaurant.GetType and Restaurant.GetType()) or 'n/a'
    local consumables = (type(Consumables) == 'table' and Consumables.GetType and Consumables.GetType()) or 'n/a'

    print(('[viking_foodtruck] Loaded %s trucks | fw=%s inv=%s bank=%s billing=%s food=%s restaurant=%s consumables=%s'):format(
        #Trucks.List(),
        fw, inv, bank, billing, food, restaurant, consumables
    ))
    Wait(1000)
    Trucks.Sync()
end)

AddEventHandler('playerJoining', function()
    local src = source
    SetTimeout(2000, function()
        if GetPlayerName(src) then
            Trucks.Sync(src)
        end
    end)
end)

lib.callback.register('viking_foodtruck:isAdmin', function(source)
    return Bridge.IsAdmin(source)
end)

lib.callback.register('viking_foodtruck:getCreatorData', function(source)
    if not Bridge.IsAdmin(source) then return nil end
    return {
        trucks = Trucks.List(),
        templates = FoodTruckTemplates.List(),
        categories = Config.Categories,
        vehicles = Config.VehicleWhitelist,
        defaults = {
            vehicle = Config.DefaultVehicle,
            cookMs = Config.DefaultCookMs,
            blip = Config.DefaultBlip,
            maxMenuItems = Config.MaxMenuItems,
            maxIngredients = Config.MaxIngredientsPerItem,
        },
        bridge = {
            framework = Bridge.GetType(),
            inventory = Inv.GetType(),
            banking = Banking and Banking.GetType() or 'framework',
            billing = Billing and Billing.GetType() or 'builtin',
            food = Food and Food.GetType() or 'inventory',
            restaurant = Restaurant and Restaurant.GetType() or 'none',
            consumables = Consumables and Consumables.GetType() or 'none',
        },
    }
end)

lib.callback.register('viking_foodtruck:saveTruck', function(source, payload)
    if not Bridge.IsAdmin(source) then
        return false, Config.Locale.no_permission
    end
    if type(payload) ~= 'table' then return false, 'Invalid payload' end

    local id = sanitizeId(payload.id)
    if not id then return false, 'Invalid id' end

    local existing = Trucks.Get(id)
    local data = sanitizeData(payload.data or {})
    if payload.description then
        data.description = tostring(payload.description):sub(1, 280)
    end
    -- Keep persistent vehicle plate tied to this business
    if existing and existing.data and type(existing.data.plate) == 'string' and existing.data.plate ~= '' then
        data.plate = existing.data.plate
    end

    local truck = {
        id = id,
        label = tostring(payload.label or id):sub(1, 128),
        category = tostring(payload.category or 'custom'):sub(1, 32),
        enabled = payload.enabled ~= false,
        price = clamp(payload.price, 0, 100000000),
        data = data,
        owner_id = existing and existing.owner_id or nil,
        created_by = existing and existing.created_by or Bridge.GetIdentifier(source),
        description = data.description,
    }

    DB.UpsertTruck(truck)
    DB.EnsureAccount(truck.id, truck.data.startingStock)
    Trucks.cache[truck.id] = truck
    if Consumables and Consumables.RegisterMenu then
        Consumables.RegisterMenu(truck.data.menu)
    end
    Trucks.Sync()
    return true, truck
end)

lib.callback.register('viking_foodtruck:deleteTruck', function(source, id)
    if not Bridge.IsAdmin(source) then
        return false, Config.Locale.no_permission
    end
    id = sanitizeId(id)
    if not id or not Trucks.Get(id) then return false, 'Not found' end
    Business.SetShopOpen(id, false)
    DB.DeleteTruck(id)
    Trucks.cache[id] = nil
    Trucks.Sync()
    return true
end)

lib.callback.register('viking_foodtruck:importTemplate', function(source, templateId)
    if not Bridge.IsAdmin(source) then return nil end
    local def = FoodTruckTemplates.Get(templateId)
    if not def then return nil end
    local copy = {
        id = def.id,
        label = def.label,
        category = def.category,
        enabled = true,
        price = def.price,
        description = def.description,
        data = sanitizeData(def.data),
    }
    copy.data.description = def.description or ''
    return copy
end)

lib.callback.register('viking_foodtruck:getPurchaseList', function(source)
    local identifier = Bridge.GetIdentifier(source)
    local list = {}
    for _, truck in ipairs(Trucks.List()) do
        if truck.enabled then
            list[#list + 1] = {
                id = truck.id,
                label = truck.label,
                category = truck.category,
                price = truck.price,
                description = (truck.data and truck.data.description) or '',
                vehicle = truck.data and truck.data.vehicle,
                ownedByYou = truck.owner_id == identifier,
                available = truck.owner_id == nil,
                owner_id = truck.owner_id,
            }
        end
    end
    return list
end)

lib.callback.register('viking_foodtruck:purchaseTruck', function(source, truckId)
    truckId = sanitizeId(truckId)
    local truck = truckId and Trucks.Get(truckId)
    if not truck or not truck.enabled then return false, 'Unavailable' end
    if truck.owner_id then return false, Config.Locale.already_owned end

    local identifier = Bridge.GetIdentifier(source)
    for _, other in pairs(Trucks.cache) do
        if other.owner_id == identifier then
            return false, 'You already own a food truck'
        end
    end

    local price = math.floor(tonumber(truck.price) or 0)
    local paid = Bridge.TryRemoveMoney(source, price, Config.PurchaseAccount)
    if not paid then
        return false, Config.Locale.not_enough_money
    end

    DB.SetOwner(truckId, identifier)
    truck.owner_id = identifier
    DB.EnsureAccount(truckId, truck.data.startingStock)

    -- Persistent plate + garage ownership immediately on purchase
    truck.data = truck.data or {}
    if type(truck.data.plate) ~= 'string' or truck.data.plate == '' then
        local prefix = tostring(truck.data.platePrefix or 'FOOD'):upper():gsub('[^A-Z0-9]', ''):sub(1, 6)
        truck.data.plate = (prefix .. tostring(math.random(100, 999))):sub(1, 8)
    end
    DB.UpsertTruck(truck)
    Trucks.cache[truckId] = truck

    if Garage and Garage.RegisterVehicle then
        local modelName = truck.data.vehicle or Config.DefaultVehicle or 'taco'
        local registered = Garage.RegisterVehicle(source, identifier, modelName, truck.data.plate, {
            model = joaat(modelName),
            plate = truck.data.plate,
        }, {
            state = 0,
            garage = Config.GarageDefault or 'pillboxgarage',
        })
        if registered then
            print(('[viking_foodtruck] Purchase registered garage vehicle plate=%s for %s'):format(
                truck.data.plate, identifier
            ))
        else
            print(('[viking_foodtruck] WARNING: garage register failed on purchase plate=%s'):format(truck.data.plate))
        end
    end

    -- Auto-assign food truck job to buyer
    local jobCfg = Config.Job
    if jobCfg and jobCfg.enabled ~= false then
        local jobName = (truck.data and truck.data.job) or jobCfg.name or 'foodtruck'
        local grade = jobCfg.ownerGrade or 1
        local okJob = Bridge.SetJob(source, jobName, grade)
        if okJob then
            Bridge.Notify(source, ('Job set: %s'):format(jobCfg.label or jobName), 'inform')
        else
            print(('[viking_foodtruck] Failed to set job "%s" for %s — ensure the job exists in your framework'):format(jobName, source))
        end
    end

    Trucks.Sync()
    Bridge.Notify(source, (Config.Locale.bought):format(truck.label, price), 'success')

    -- Full truck payload for client spawn (includes vehicle/menu/retrieve data)
    local spawnPayload = {
        id = truck.id,
        label = truck.label,
        category = truck.category,
        price = truck.price,
        owner_id = truck.owner_id,
        data = truck.data,
    }
    if Config.SpawnOnPurchase ~= false then
        TriggerClientEvent('viking_foodtruck:client:spawnPurchasedTruck', source, spawnPayload)
    end
    return true, spawnPayload
end)

lib.callback.register('viking_foodtruck:sellTruck', function(source, truckId)
    truckId = sanitizeId(truckId)
    local truck = truckId and Trucks.Get(truckId)
    if not truck then return false, 'Not found' end
    local identifier = Bridge.GetIdentifier(source)
    if truck.owner_id ~= identifier then return false, Config.Locale.not_owner end

    local refund = math.floor((tonumber(truck.price) or 0) * (Config.SellBackPercent or 0.5))
    Business.SetShopOpen(truckId, false)
    if Config.ClearBalanceOnSell then
        local account = DB.GetAccount(truckId)
        account.balance = 0
        account.employees = {}
        account.stock = truck.data.startingStock or {}
        DB.SaveAccount(account)
    end

    -- Remove from garage ownership so the old owner can't keep the truck
    if Garage and Garage.RemoveVehicle and truck.data and truck.data.plate then
        Garage.RemoveVehicle(truck.data.plate)
    end

    DB.SetOwner(truckId, nil)
    truck.owner_id = nil
    if refund > 0 then
        Bridge.AddMoney(source, Config.PurchaseAccount or 'bank', refund)
    end

    local jobCfg = Config.Job
    if jobCfg and jobCfg.enabled ~= false and jobCfg.removeOnSell ~= false then
        local currentJob = Bridge.GetJob(source)
        local jobName = (truck.data and truck.data.job) or jobCfg.name or 'foodtruck'
        if currentJob == jobName then
            Bridge.ClearJob(source)
        end
    end

    Trucks.Sync()
    TriggerClientEvent('viking_foodtruck:client:despawnOwnedTruck', source)
    Bridge.Notify(source, (Config.Locale.sold):format(truck.label, refund), 'success')
    return true, refund
end)

lib.callback.register('viking_foodtruck:getManageData', function(source, truckId)
    truckId = sanitizeId(truckId)
    local truck = truckId and Trucks.Get(truckId)
    if not truck then return nil end
    local account = DB.GetAccount(truckId)
    local identifier = Bridge.GetIdentifier(source)
    if not Business.IsStaff(truck, account, identifier) then return nil end
    return {
        truck = {
            id = truck.id,
            label = truck.label,
            price = truck.price,
            owner_id = truck.owner_id,
            data = truck.data,
        },
        account = account,
        isOwner = truck.owner_id == identifier,
        shopOpen = Business.GetShop(truckId) ~= nil,
        orders = Business.GetPendingForTruck(truckId),
    }
end)

lib.callback.register('viking_foodtruck:registerVehicleKeys', function(source, truckId, plate, netId)
    truckId = sanitizeId(truckId)
    if not truckId then return false, 'Invalid truck' end
    if not Keys or not Keys.RegisterOwnedVehicle then return false, 'Keys bridge missing' end
    return Keys.RegisterOwnedVehicle(source, truckId, plate, tonumber(netId))
end)

lib.callback.register('viking_foodtruck:unregisterVehicleKeys', function(source, truckId, plate, netId)
    truckId = sanitizeId(truckId)
    if Keys and Keys.UnregisterVehicle then
        Keys.UnregisterVehicle(source, truckId, plate, tonumber(netId))
    end
    return true
end)

lib.callback.register('viking_foodtruck:parkVehicle', function(source, truckId, plate, props)
    truckId = sanitizeId(truckId)
    local truck = truckId and Trucks.Get(truckId)
    if not truck then return false, 'Not found' end
    local account = DB.GetAccount(truckId)
    if not Business.IsStaff(truck, account, Bridge.GetIdentifier(source)) then
        return false, Config.Locale.not_owner
    end
    plate = (Keys and Keys.NormalizePlate and Keys.NormalizePlate(plate)) or tostring(plate or ''):upper()
    if plate == '' and truck.data and truck.data.plate then
        plate = truck.data.plate
    end
    if plate == '' then
        return false, 'Missing plate — retrieve the truck once then store again'
    end
    local modelName = (truck.data and truck.data.vehicle) or Config.DefaultVehicle or 'taco'
    local ownerId = truck.owner_id or Bridge.GetIdentifier(source)
    local ownerSrc = (Keys and Keys.GetSourceByIdentifier and Keys.GetSourceByIdentifier(ownerId)) or source
    if Garage and Garage.RegisterVehicle then
        local ok = Garage.RegisterVehicle(ownerSrc, ownerId, modelName, plate, props, {
            state = 1,
            garage = Config.GarageDefault,
        })
        Garage.SetStored(plate, Config.GarageDefault, props)
        local exists, owned, row = false, false, nil
        if Garage.VerifyOwned then
            exists, owned, row = Garage.VerifyOwned(plate, ownerId)
        end
        if not ok and not exists then
            return false, 'Garage registration failed — check server console for [viking_foodtruck] garage errors'
        end
        if row and ((row.state ~= nil and tonumber(row.state) ~= 1) or (row.stored ~= nil and tonumber(row.stored) ~= 1)) then
            Garage.SetStored(plate, Config.GarageDefault, props)
        end
        if exists and not owned then
            print(('[viking_foodtruck] WARNING: parked plate=%s but owner mismatch (expected %s)'):format(plate, tostring(ownerId)))
        end
    end
    if truck.data then
        truck.data.plate = plate
        DB.UpsertTruck(truck)
        Trucks.cache[truckId] = truck
    end
    Bridge.Notify(source, ('Truck parked in garage: %s'):format(tostring(Config.GarageDefault or 'default')), 'success')
    return true
end)

lib.callback.register('viking_foodtruck:setVehicleOut', function(source, truckId, plate, netId)
    truckId = sanitizeId(truckId)
    local truck = truckId and Trucks.Get(truckId)
    if not truck then return false end
    local account = DB.GetAccount(truckId)
    if not Business.IsStaff(truck, account, Bridge.GetIdentifier(source)) then
        return false
    end
    plate = (Keys and Keys.NormalizePlate and Keys.NormalizePlate(plate))
        or tostring(plate or (truck.data and truck.data.plate) or ''):upper()
    if Garage and Garage.SetOut then
        Garage.SetOut(plate, tonumber(netId))
    end
    return true
end)

lib.callback.register('viking_foodtruck:syncGarageProps', function(source, truckId, plate, props, netId)
    truckId = sanitizeId(truckId)
    local truck = truckId and Trucks.Get(truckId)
    if not truck then return false end
    local account = DB.GetAccount(truckId)
    if not Business.IsStaff(truck, account, Bridge.GetIdentifier(source)) then
        return false
    end
    plate = (Keys and Keys.NormalizePlate and Keys.NormalizePlate(plate))
        or tostring(plate or (truck.data and truck.data.plate) or ''):upper()
    local modelName = (truck.data and truck.data.vehicle) or Config.DefaultVehicle or 'taco'
    local ownerId = truck.owner_id or Bridge.GetIdentifier(source)
    local ownerSrc = (Keys and Keys.GetSourceByIdentifier and Keys.GetSourceByIdentifier(ownerId)) or source
    if Garage and Garage.RegisterVehicle then
        local ok = Garage.RegisterVehicle(ownerSrc, ownerId, modelName, plate, props, {
            state = 0,
            netId = tonumber(netId),
        })
        Garage.SetOut(plate, tonumber(netId))
        return ok and true or false
    end
    return false
end)

lib.callback.register('viking_foodtruck:setShopOpen', function(source, truckId, isOpen, netId, coords)
    truckId = sanitizeId(truckId)
    local truck = truckId and Trucks.Get(truckId)
    if not truck then return false, 'Not found' end
    local account = DB.GetAccount(truckId)
    if not Business.IsStaff(truck, account, Bridge.GetIdentifier(source)) then
        return false, Config.Locale.not_owner
    end
    local c
    if type(coords) == 'table' then
        c = vector3(tonumber(coords.x) or 0.0, tonumber(coords.y) or 0.0, tonumber(coords.z) or 0.0)
    else
        c = GetEntityCoords(GetPlayerPed(source))
    end
    Business.SetShopOpen(truckId, isOpen and true or false, source, tonumber(netId), c)
    Bridge.Notify(source, isOpen and Config.Locale.shop_open or Config.Locale.shop_closed, 'inform')
    return true
end)

lib.callback.register('viking_foodtruck:placeOrder', function(source, truckId, itemIndex, paymentMethod)
    truckId = sanitizeId(truckId)
    itemIndex = tonumber(itemIndex)
    if not truckId or not itemIndex then return false, 'Invalid' end
    local ok, result = Business.CreateOrder(source, truckId, itemIndex, paymentMethod)
    if ok then
        Bridge.Notify(source, Config.Locale.order_placed, 'success')
    end
    return ok, result
end)

lib.callback.register('viking_foodtruck:getMyBills', function(source)
    if not Billing or not Billing.UsesBuiltin or not Billing.UsesBuiltin() then
        return {}
    end
    return Billing.GetUnpaidForPlayer(source)
end)

lib.callback.register('viking_foodtruck:payBill', function(source, billId, account)
    if not Billing or not Billing.PayBuiltin then
        return false, 'Builtin billing unavailable'
    end
    return Billing.PayBuiltin(source, billId, account)
end)

lib.callback.register('viking_foodtruck:getTruckBills', function(source, truckId)
    truckId = sanitizeId(truckId)
    local truck = truckId and Trucks.Get(truckId)
    if not truck then return {} end
    local account = DB.GetAccount(truckId)
    if not Business.IsStaff(truck, account, Bridge.GetIdentifier(source)) then
        return {}
    end
    if not Billing or not Billing.UsesBuiltin or not Billing.UsesBuiltin() then
        return {}
    end
    return Billing.GetUnpaidForTruck(truckId)
end)

lib.callback.register('viking_foodtruck:getBillingConfig', function()
    return {
        mode = Config.BillingMode or 'choice',
        allowBill = Config.AllowCustomerBilling ~= false and (not Billing or Billing.GetType() ~= 'none'),
        system = Billing and Billing.GetType() or 'builtin',
        builtin = Billing and Billing.UsesBuiltin and Billing.UsesBuiltin() or false,
    }
end)

lib.callback.register('viking_foodtruck:fulfillOrder', function(source, orderId)
    local ok, result = Business.FulfillOrder(source, orderId)
    return ok, result
end)

lib.callback.register('viking_foodtruck:cancelOrder', function(source, orderId, asStaff)
    return Business.CancelOrder(source, orderId, asStaff and true or false)
end)

lib.callback.register('viking_foodtruck:depositStock', function(source, truckId, item, count)
    return Business.DepositStock(source, sanitizeId(truckId), item, count)
end)

lib.callback.register('viking_foodtruck:withdrawStock', function(source, truckId, item, count)
    return Business.WithdrawStock(source, sanitizeId(truckId), item, count)
end)

lib.callback.register('viking_foodtruck:getStockView', function(source, truckId)
    truckId = sanitizeId(truckId)
    local truck = truckId and Trucks.Get(truckId)
    if not truck then return nil end
    local account = DB.GetAccount(truckId)
    if not Business.IsStaff(truck, account, Bridge.GetIdentifier(source)) then
        return nil
    end
    return Business.BuildStockView(truckId)
end)

lib.callback.register('viking_foodtruck:getShopMenu', function(source, truckId)
    truckId = sanitizeId(truckId)
    return Business.GetShopMenu(truckId)
end)

lib.callback.register('viking_foodtruck:buyPrepared', function(source, truckId, itemIndex, paymentMethod)
    truckId = sanitizeId(truckId)
    itemIndex = tonumber(itemIndex)
    if not truckId or not itemIndex then return false, 'Invalid' end
    local ok, result = Business.BuyPrepared(source, truckId, itemIndex, paymentMethod)
    if ok then
        Bridge.Notify(source, Config.Locale.order_ready or 'Order ready', 'success')
    end
    return ok, result
end)

lib.callback.register('viking_foodtruck:craftFood', function(source, truckId, itemIndex, amount, destination)
    return Business.CraftFood(source, sanitizeId(truckId), tonumber(itemIndex), amount, destination)
end)

lib.callback.register('viking_foodtruck:isStaffOf', function(source, truckId)
    truckId = sanitizeId(truckId)
    local truck = truckId and Trucks.Get(truckId)
    if not truck then return false end
    local account = DB.GetAccount(truckId)
    return Business.IsStaff(truck, account, Bridge.GetIdentifier(source))
end)

lib.callback.register('viking_foodtruck:withdrawBalance', function(source, truckId, amount)
    return Business.WithdrawBalance(source, sanitizeId(truckId), amount)
end)

lib.callback.register('viking_foodtruck:depositBalance', function(source, truckId, amount)
    return Business.DepositBalance(source, sanitizeId(truckId), amount)
end)

lib.callback.register('viking_foodtruck:hire', function(source, truckId, targetSrc)
    return Business.Hire(source, sanitizeId(truckId), targetSrc)
end)

lib.callback.register('viking_foodtruck:fire', function(source, truckId, targetIdentifier)
    return Business.Fire(source, sanitizeId(truckId), targetIdentifier)
end)

lib.callback.register('viking_foodtruck:getOwned', function(source)
    local identifier = Bridge.GetIdentifier(source)
    for _, truck in pairs(Trucks.cache) do
        if truck.owner_id == identifier then
            return {
                id = truck.id,
                label = truck.label,
                data = truck.data,
            }
        end
    end
    local accountStaff = {}
    for _, truck in pairs(Trucks.cache) do
        local account = DB.GetAccount(truck.id)
        if Business.IsStaff(truck, account, identifier) then
            accountStaff[#accountStaff + 1] = {
                id = truck.id,
                label = truck.label,
                data = truck.data,
                employee = true,
            }
        end
    end
    return accountStaff[1]
end)

RegisterNetEvent('viking_foodtruck:server:creatorState', function(isOpen)
    local src = source
    creatorOpen[src] = isOpen and true or false
end)

RegisterNetEvent('viking_foodtruck:server:requestSync', function()
    Trucks.Sync(source)
end)

exports('IsCreatorOpen', function(src)
    return creatorOpen[src] == true
end)
