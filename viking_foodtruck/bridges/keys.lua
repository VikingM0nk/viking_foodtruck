--[[
    Vehicle keys bridge — auto-detects common key systems.
    Gives keys to the business owner (and optionally the staff who spawned the truck).
]]

Keys = Keys or {}

local function started(name)
    return type(name) == 'string' and name ~= '' and GetResourceState(name) == 'started'
end

local function trimPlate(plate)
    return (tostring(plate or ''):gsub('^%s+', ''):gsub('%s+$', '')):upper()
end

--- Safely call an export. Missing exports must be caught — FiveM throws on
--- `exports[res][name]` when the export does not exist (before type checks).
local missingExports = {}

local function tryExport(resource, exportName, ...)
    if not started(resource) or not exportName or exportName == '' then return false end
    local key = resource .. ':' .. exportName
    if missingExports[key] then return false end
    local args = { ... }
    local ok = pcall(function()
        return exports[resource][exportName](table.unpack(args))
    end)
    if ok then return true end
    ok = pcall(function()
        local exp = exports[resource]
        return exp[exportName](exp, table.unpack(args))
    end)
    if not ok then
        missingExports[key] = true
    end
    return ok
end

function Keys.NormalizePlate(plate)
    return trimPlate(plate)
end

--- Client-side key give (local player)
function Keys.GiveClient(vehicle, plate)
    if IsDuplicityVersion() then return end
    plate = trimPlate(plate)
    if plate == '' then return end

    local model = (vehicle and vehicle ~= 0 and DoesEntityExist(vehicle)) and GetEntityModel(vehicle) or 0
    local modelName = model ~= 0 and (GetDisplayNameFromVehicleModel(model) or ''):lower() or ''

    local cfg = Config.GiveKeys or {}
    if cfg.event and cfg.event ~= '' then
        TriggerEvent(cfg.event, plate)
    end
    if cfg.resource and cfg.resource ~= '' and cfg.export and cfg.export ~= '' then
        tryExport(cfg.resource, cfg.export, plate, vehicle, modelName)
    end

    if Config.Keys == 'none' then return end

    -- qb-vehiclekeys: use events only (many builds have no GiveKeys/RemoveKeys exports)
    if started('qb-vehiclekeys') then
        TriggerEvent('vehiclekeys:client:SetOwner', plate)
        TriggerEvent('qb-vehiclekeys:client:AddKeys', plate)
    end
    -- qbx: server-side GiveKeys is preferred; client export is optional
    tryExport('qbx_vehiclekeys', 'GiveKeys', vehicle)

    -- cd_garage
    TriggerEvent('cd_garage:AddKeys', plate)

    -- wasabi
    tryExport('wasabi_carlock', 'GiveKey', plate)
    tryExport('wasabi_carlock', 'GiveKeys', plate)

    -- qs
    tryExport('qs-vehiclekeys', 'GiveKeys', plate, modelName)
    tryExport('qs-vehiclekeys', 'GiveKeysOwner', plate, modelName)

    -- Renewed (client variants)
    tryExport('Renewed-Vehiclekeys', 'addKey', plate)
    tryExport('Renewed-Vehiclekeys', 'GiveKey', plate)

    -- MrNewb
    tryExport('MrNewbVehicleKeys', 'GiveKeys', vehicle)
    tryExport('MrNewbVehicleKeys', 'GiveKeysByPlate', plate)

    -- jaksam / vehicles_keys
    TriggerEvent('vehicles_keys:selfGiveVehicleKeys', plate)
    TriggerServerEvent('vehicles_keys:selfGiveVehicleKeys', plate)

    -- t1ger
    tryExport('t1ger_keys', 'GiveKey', plate)
    TriggerEvent('t1ger_keys:updateOwnedKeys', plate, true)

    -- okokGarage
    tryExport('okokGarage', 'GiveKeys', plate)
    TriggerEvent('okokGarage:GiveKeys', plate)

    -- tgiann
    tryExport('tgiann-hotwire', 'GiveKeyVehicle', vehicle)
    tryExport('tgiann-hotwire', 'GiveKeyPlate', plate)
    if vehicle and vehicle ~= 0 then
        tryExport('tgiann-hotwire', 'SetNonRemoveableIgnition', vehicle, true)
    end

    -- mk / fivecode / loaf / ak47 / F_RealCarKeys
    tryExport('mk_vehiclekeys', 'AddKey', plate)
    tryExport('mk_vehiclekeys', 'GiveKeys', vehicle)
    tryExport('fivecode_carkeys', 'GiveKey', plate)
    tryExport('F_RealCarKeysSystem', 'GiveCarKey', plate)
    tryExport('loaf_keysystem', 'AddKey', plate)
    tryExport('ak47_vehiclekeys', 'GiveKey', plate)
    tryExport('mx_carkeys', 'GiveKey', plate)
    tryExport('ic3d_vehiclekeys', 'ClientInventoryKeys', 'add', plate)

    -- Legacy / misc events
    TriggerEvent('keys:addNew', vehicle, plate)
    TriggerEvent('x-vehiclekeys:client:AddKeys', plate)
    TriggerEvent('dusa_vehiclekeys:client:AddKeys', plate)
end

--- Client-side key remove
function Keys.RemoveClient(vehicle, plate)
    if IsDuplicityVersion() then return end
    plate = trimPlate(plate)
    if plate == '' then return end
    local model = (vehicle and vehicle ~= 0 and DoesEntityExist(vehicle)) and GetEntityModel(vehicle) or 0
    local modelName = model ~= 0 and (GetDisplayNameFromVehicleModel(model) or ''):lower() or ''

    if started('qb-vehiclekeys') then
        TriggerEvent('qb-vehiclekeys:client:RemoveKeys', plate)
        TriggerEvent('vehiclekeys:client:RemoveKeys', plate)
    end
    tryExport('qs-vehiclekeys', 'RemoveKeys', plate, modelName)
    tryExport('wasabi_carlock', 'RemoveKey', plate)
    tryExport('wasabi_carlock', 'RemoveKeys', plate)
    tryExport('Renewed-Vehiclekeys', 'removeKey', plate)
    tryExport('MrNewbVehicleKeys', 'RemoveKeys', vehicle)
    tryExport('MrNewbVehicleKeys', 'RemoveKeysByPlate', plate)
    TriggerEvent('cd_garage:RemoveKeys', plate)
    tryExport('t1ger_keys', 'RemoveKey', plate)
    tryExport('ic3d_vehiclekeys', 'ClientInventoryKeys', 'remove', plate)
end

if IsDuplicityVersion() then
    --- Find online player source by framework identifier / citizenid
    function Keys.GetSourceByIdentifier(identifier)
        if not identifier then return nil end
        identifier = tostring(identifier)
        for _, src in ipairs(GetPlayers()) do
            local id = tonumber(src)
            if id and Bridge.GetIdentifier(id) == identifier then
                return id
            end
        end
        return nil
    end

    --- Server-side key give for a specific player
    --- @param src number player source
    --- @param plate string
    --- @param netId number|nil vehicle network id
    function Keys.GiveServer(src, plate, netId)
        if not src or src <= 0 then return end
        plate = trimPlate(plate)
        if plate == '' then return end

        local vehicle = 0
        if netId then
            vehicle = NetworkGetEntityFromNetworkId(netId)
            if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
                vehicle = 0
            end
        end

        local cfg = Config.GiveKeys or {}
        if cfg.serverEvent and cfg.serverEvent ~= '' then
            TriggerEvent(cfg.serverEvent, src, plate, netId)
        end
        if cfg.resource and cfg.resource ~= '' and cfg.serverExport and cfg.serverExport ~= '' then
            tryExport(cfg.resource, cfg.serverExport, src, plate, vehicle)
        end

        if Config.Keys == 'none' then
            TriggerClientEvent('viking_foodtruck:client:giveKeys', src, plate, netId)
            return
        end

        -- qb-vehiclekeys: events only (exports often missing)
        if started('qb-vehiclekeys') then
            TriggerClientEvent('qb-vehiclekeys:client:AddKeys', src, plate)
            TriggerClientEvent('vehiclekeys:client:SetOwner', src, plate)
            -- Some forks expose a server event instead of an export
            TriggerEvent('qb-vehiclekeys:server:AcquireVehicleKeys', plate, src)
            TriggerClientEvent('qb-vehiclekeys:client:SetOwner', src, plate)
        end

        -- qbx_vehiclekeys (GiveKeys(source, vehicle)) — only if export exists
        if vehicle ~= 0 then
            tryExport('qbx_vehiclekeys', 'GiveKeys', src, vehicle, true)
        end

        -- Renewed
        tryExport('Renewed-Vehiclekeys', 'addKey', src, plate)

        -- wasabi (server variants)
        tryExport('wasabi_carlock', 'GiveKey', src, plate)
        tryExport('wasabi_carlock', 'GiveKeys', src, plate)

        -- qs (often client; also try server)
        tryExport('qs-vehiclekeys', 'GiveKeys', src, plate)
        TriggerClientEvent('qs-vehiclekeys:client:GiveKeys', src, plate)

        -- MrNewb
        if vehicle ~= 0 then
            tryExport('MrNewbVehicleKeys', 'GiveKeys', src, vehicle)
        end
        tryExport('MrNewbVehicleKeys', 'GiveKeysByPlate', src, plate)

        -- jaksam
        TriggerClientEvent('vehicles_keys:selfGiveVehicleKeys', src, plate)

        -- cd_garage
        TriggerClientEvent('cd_garage:AddKeys', src, plate)

        -- t1ger / okok / tgiann / others
        tryExport('t1ger_keys', 'GiveKey', src, plate)
        TriggerClientEvent('okokGarage:GiveKeys', src, plate)
        tryExport('tgiann-hotwire', 'GiveKeyPlate', src, plate)
        tryExport('mk_vehiclekeys', 'AddKey', src, plate)
        tryExport('loaf_keysystem', 'AddKey', src, plate)
        tryExport('ak47_vehiclekeys', 'GiveKey', src, plate)

        -- Always also run client bridge for systems that are client-only
        TriggerClientEvent('viking_foodtruck:client:giveKeys', src, plate, netId)
    end

    function Keys.RemoveServer(src, plate, netId)
        if not src or src <= 0 then return end
        plate = trimPlate(plate)
        if plate == '' then return end

        local vehicle = 0
        if netId then
            vehicle = NetworkGetEntityFromNetworkId(netId)
            if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
                vehicle = 0
            end
        end

        if started('qb-vehiclekeys') then
            TriggerClientEvent('qb-vehiclekeys:client:RemoveKeys', src, plate)
        end
        if vehicle ~= 0 then
            tryExport('qbx_vehiclekeys', 'RemoveKeys', src, vehicle, true)
        end
        tryExport('Renewed-Vehiclekeys', 'removeKey', src, plate)
        tryExport('wasabi_carlock', 'RemoveKey', src, plate)
        tryExport('MrNewbVehicleKeys', 'RemoveKeysByPlate', src, plate)
        TriggerClientEvent('viking_foodtruck:client:removeKeys', src, plate, netId)
    end

    --- Register spawned truck: persist plate, set owner state, give keys to business owner (+ staff if needed)
    function Keys.RegisterOwnedVehicle(src, truckId, plate, netId)
        local truck = Trucks and Trucks.Get and Trucks.Get(truckId)
        if not truck then return false, 'Truck not found' end

        local account = DB and DB.GetAccount and DB.GetAccount(truckId)
        local identifier = Bridge.GetIdentifier(src)
        if not Business.IsStaff(truck, account, identifier) then
            return false, 'Not staff'
        end

        plate = trimPlate(plate)
        if plate == '' then return false, 'Invalid plate' end

        truck.data = truck.data or {}
        if truck.data.plate ~= plate then
            truck.data.plate = plate
            DB.UpsertTruck(truck)
            Trucks.cache[truckId] = truck
        end

        local vehicle = netId and NetworkGetEntityFromNetworkId(netId) or 0
        local ownerId = truck.owner_id or identifier
        if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
            -- Mark entity ownership for scripts that read state bags
            pcall(function()
                Entity(vehicle).state:set('owner', ownerId, true)
                Entity(vehicle).state:set('vehicleOwner', ownerId, true)
                Entity(vehicle).state:set('foodtruckId', truckId, true)
                Entity(vehicle).state:set('foodtruckOwner', ownerId, true)
            end)
            SetVehicleNumberPlateText(vehicle, plate)
        end

        -- Register in garage DB so public garages accept parking this plate
        if Garage and Garage.RegisterVehicle then
            local modelName = (truck.data and truck.data.vehicle) or Config.DefaultVehicle or 'taco'
            local regSrc = Keys.GetSourceByIdentifier(truck.owner_id) or src
            Garage.RegisterVehicle(regSrc, ownerId, modelName, plate, {
                model = joaat(modelName),
                plate = plate,
            }, { state = 0, netId = netId })
            Garage.SetOut(plate, netId)
        end

        local ownerSrc = Keys.GetSourceByIdentifier(truck.owner_id)
        local giveStaff = Config.KeysGiveToStaff ~= false

        -- Business owner always gets keys / ownership when online
        if ownerSrc then
            Keys.GiveServer(ownerSrc, plate, netId)
        end

        -- Staff who spawned also gets keys so they can drive
        if giveStaff and src ~= ownerSrc then
            Keys.GiveServer(src, plate, netId)
        elseif not ownerSrc then
            -- Owner offline: still give to the staff who retrieved so the truck is usable
            Keys.GiveServer(src, plate, netId)
        end

        return true, plate
    end

    function Keys.UnregisterVehicle(src, truckId, plate, netId)
        plate = trimPlate(plate)
        if plate == '' then return end
        Keys.RemoveServer(src, plate, netId)
        local truck = Trucks and Trucks.Get and Trucks.Get(truckId)
        if truck and truck.owner_id then
            local ownerSrc = Keys.GetSourceByIdentifier(truck.owner_id)
            if ownerSrc and ownerSrc ~= src then
                Keys.RemoveServer(ownerSrc, plate, netId)
            end
        end
    end
end
