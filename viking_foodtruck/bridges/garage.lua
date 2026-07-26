--[[
    Garage bridge — multi-backend ownership so food trucks park in
    qb-garages, qbx_garages/qbx_vehicles, jg-advancedgarages, cd_garage,
    okokGarage, qs-advancedgarages, loaf_garage, rcore_garage, ESX, custom.
]]

Garage = Garage or {}

local function started(name)
    return type(name) == 'string' and name ~= '' and GetResourceState(name) == 'started'
end

local function trimPlate(plate)
    return (tostring(plate or ''):gsub('^%s+', ''):gsub('%s+$', '')):upper()
end

--- Compact plate for fuzzy DB matching (no spaces)
local function compactPlate(plate)
    return trimPlate(plate):gsub('%s+', '')
end

--- GTA plates are often 8 chars; some garages pad with spaces
local function padPlate(plate)
    plate = trimPlate(plate)
    if #plate < 8 then
        plate = plate .. string.rep(' ', 8 - #plate)
    end
    return plate:sub(1, 8)
end

local function detect()
    local mode = Config.Garage or 'auto'
    if mode ~= 'auto' then return mode end
    if Config.CustomGarage and Config.CustomGarage.resource and started(Config.CustomGarage.resource) then
        return 'custom'
    end
    if started('jg-advancedgarages') then return 'jg' end
    if started('qbx_vehicles') or started('qbx_garages') then return 'qbox' end
    if started('cd_garage') then return 'cd' end
    if started('okokGarage') then return 'okok' end
    if started('qs-advancedgarages') then return 'qs' end
    if started('loaf_garage') then return 'loaf' end
    if started('rcore_garage') then return 'rcore' end
    if started('qb-garages') or started('qb-garage') or started('qb-core') then return 'qb' end
    if started('esx_garage') or started('es_extended') or started('esx_vehicleshop') then return 'esx' end
    return 'auto'
end

local detected

function Garage.GetType()
    if not detected then detected = detect() end
    return detected
end

function Garage.IsEnabled()
    return Config.GarageAllowPark ~= false and Garage.GetType() ~= 'none'
end

local function signedHash(modelName)
    local h = joaat(tostring(modelName or 'taco'))
    if type(h) ~= 'number' then h = tonumber(h) or 0 end
    -- MySQL INT is signed
    if h > 2147483647 then
        h = h - 4294967296
    end
    return h
end

local function getLicense(src)
    if not src then return nil end
    local fw = Bridge and Bridge.GetType and Bridge.GetType()
    if fw == 'qb' or fw == 'qbox' then
        local player = Bridge.GetPlayer(src)
        if player and player.PlayerData and player.PlayerData.license then
            return player.PlayerData.license
        end
    end
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:sub(1, 8) == 'license:' then
            return id
        end
    end
    return nil
end

local function encodeMods(props)
    if type(props) == 'string' and props ~= '' then return props end
    if type(props) == 'table' then
        local ok, encoded = pcall(json.encode, props)
        if ok and encoded then return encoded end
    end
    return '{}'
end

local function ensureProps(props, modelName, plate)
    props = type(props) == 'table' and props or {}
    local model = props.model
    if type(model) == 'string' then
        model = joaat(model)
    end
    props.model = model or joaat(modelName)
    props.plate = trimPlate(props.plate or plate)
    props.engineHealth = props.engineHealth or 1000.0
    props.bodyHealth = props.bodyHealth or 1000.0
    props.fuelLevel = props.fuelLevel or props.fuel or 100.0
    return props
end

if not IsDuplicityVersion() then
    function Garage.GetVehicleProperties(vehicle)
        if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return {} end

        if lib and type(lib.getVehicleProperties) == 'function' then
            local ok, props = pcall(lib.getVehicleProperties, vehicle)
            if ok and type(props) == 'table' then
                props.plate = trimPlate(props.plate or GetVehicleNumberPlateText(vehicle))
                return props
            end
        end

        for _, res in ipairs({ 'qb-core', 'qbx_core' }) do
            if started(res) then
                local ok, props = pcall(function()
                    return exports[res]:GetCoreObject().Functions.GetVehicleProperties(vehicle)
                end)
                if ok and type(props) == 'table' then
                    props.plate = trimPlate(props.plate or GetVehicleNumberPlateText(vehicle))
                    return props
                end
            end
        end

        local plate = trimPlate(GetVehicleNumberPlateText(vehicle))
        local c1, c2 = GetVehicleColours(vehicle)
        return {
            model = GetEntityModel(vehicle),
            plate = plate,
            plateIndex = GetVehicleNumberPlateTextIndex(vehicle),
            bodyHealth = GetVehicleBodyHealth(vehicle) + 0.0,
            engineHealth = GetVehicleEngineHealth(vehicle) + 0.0,
            tankHealth = GetVehiclePetrolTankHealth(vehicle) + 0.0,
            fuelLevel = GetVehicleFuelLevel(vehicle) + 0.0,
            dirtLevel = GetVehicleDirtLevel(vehicle) + 0.0,
            color1 = c1,
            color2 = c2,
        }
    end
    return
end

-- ===================== SERVER =====================

local columnCache = {}
local tableCache = {}
local resolvedDefaultGarage

local function tableExists(tableName)
    if tableCache[tableName] ~= nil then return tableCache[tableName] end
    local exists = false
    local ok, count = pcall(function()
        return MySQL.scalar.await(
            'SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?',
            { tableName }
        )
    end)
    if ok and tonumber(count) and tonumber(count) > 0 then
        exists = true
    else
        local ok2, rows = pcall(function()
            return MySQL.query.await('SHOW TABLES LIKE ?', { tableName })
        end)
        exists = ok2 and rows and rows[1] ~= nil
    end
    tableCache[tableName] = exists
    return exists
end

local function tableColumns(tableName)
    if columnCache[tableName] then return columnCache[tableName] end
    local cols = {}
    local ok, rows = pcall(function()
        return MySQL.query.await(('SHOW COLUMNS FROM `%s`'):format(tableName))
    end)
    if ok and rows then
        for i = 1, #rows do
            local name = rows[i].Field or rows[i].field
            if name then cols[name] = true end
        end
    end
    columnCache[tableName] = cols
    return cols
end

local function hasColumn(tableName, column)
    return tableColumns(tableName)[column] == true
end

--- Prefer garage / garage_id / parking depending on schema
local function garageColumnFor(tableName)
    if hasColumn(tableName, 'garage') then return 'garage' end
    if hasColumn(tableName, 'garage_id') then return 'garage_id' end
    if hasColumn(tableName, 'parking') then return 'parking' end
    return nil
end

local function tryExport(resource, exportName, ...)
    if not started(resource) then return false, nil end
    local args = { ... }
    local ok, a, b = pcall(function()
        return exports[resource][exportName](table.unpack(args))
    end)
    if ok then return true, a, b end
    ok, a, b = pcall(function()
        local exp = exports[resource]
        return exp[exportName](exp, table.unpack(args))
    end)
    return ok, a, b
end

local function resolveGarageName(preferred)
    local configured = preferred
    if type(configured) ~= 'string' or configured == '' then
        configured = Config.GarageDefault
    end
    if type(configured) ~= 'string' or configured == '' then
        configured = 'pillboxgarage'
    end

    -- Auto-resolve a real JG garage id when configured one is missing
    if started('jg-advancedgarages') then
        local ok, garages = tryExport('jg-advancedgarages', 'getAllGarages')
        if ok and type(garages) == 'table' and #garages > 0 then
            local names = {}
            for i = 1, #garages do
                local g = garages[i]
                local name = g and (g.name or g.id or g.garage)
                if type(name) == 'string' and name ~= '' then
                    names[name] = true
                end
            end
            if names[configured] then
                return configured
            end
            for i = 1, #garages do
                local g = garages[i]
                local name = g and (g.name or g.id or g.garage)
                local vtype = g and (g.vehicle or g.typeVehicle or 'car')
                local gtype = g and g.type or 'public'
                if type(name) == 'string' and name ~= ''
                    and (vtype == 'car' or vtype == 'vehicle' or not g.vehicle)
                    and (gtype == 'public' or gtype == 'job' or not g.type)
                then
                    if configured ~= name then
                        print(('[viking_foodtruck] GarageDefault "%s" not in JG list — using "%s"'):format(configured, name))
                    end
                    return name
                end
            end
            local fallback = garages[1].name or garages[1].id
            if type(fallback) == 'string' and fallback ~= '' then
                return fallback
            end
        end
    end

    return configured
end

local function defaultGarage()
    if resolvedDefaultGarage then return resolvedDefaultGarage end
    resolvedDefaultGarage = resolveGarageName(Config.GarageDefault)
    return resolvedDefaultGarage
end

local function findByPlate(tableName, plate)
    if not tableExists(tableName) then return nil end
    plate = trimPlate(plate)
    if plate == '' then return nil end
    local padded = padPlate(plate)
    local compact = compactPlate(plate)

    local queries = {
        { 'SELECT * FROM `%s` WHERE plate = ? LIMIT 1', { plate } },
        { 'SELECT * FROM `%s` WHERE plate = ? LIMIT 1', { padded } },
        { 'SELECT * FROM `%s` WHERE REPLACE(UPPER(TRIM(plate)), " ", "") = ? LIMIT 1', { compact } },
    }
    for i = 1, #queries do
        local sql, vals = queries[i][1], queries[i][2]
        local ok, row = pcall(function()
            return MySQL.single.await(sql:format(tableName), vals)
        end)
        if ok and row then return row end
    end
    return nil
end

local function findPlayerVehicle(plate)
    return findByPlate('player_vehicles', plate)
end

local function findOwnedVehicle(plate)
    return findByPlate('owned_vehicles', plate)
end

local function mysqlUpdate(sql, vals)
    local ok, err = pcall(function()
        MySQL.update.await(sql, vals)
    end)
    if not ok then
        print(('[viking_foodtruck] MySQL update failed: %s | %s'):format(tostring(err), sql))
        return false
    end
    return true
end

local function mysqlInsert(sql, vals)
    local ok, result = pcall(function()
        return MySQL.insert.await(sql, vals)
    end)
    if not ok then
        print(('[viking_foodtruck] MySQL insert failed: %s | %s'):format(tostring(result), sql))
        return false, result
    end
    return true, result
end

--- Dynamic insert into player_vehicles using only columns that exist
local function upsertPlayerVehicles(ownerSrc, ownerId, modelName, plate, props, state, garageName)
    if not tableExists('player_vehicles') then return false, 'no_table' end
    plate = trimPlate(plate)
    props = ensureProps(props, modelName, plate)
    local mods = encodeMods(props)
    local hashNum = signedHash(modelName)
    local hashStr = tostring(props.model or joaat(modelName))
    local license = getLicense(ownerSrc)
    garageName = garageName or defaultGarage()
    state = tonumber(state) or 0
    local gCol = garageColumnFor('player_vehicles')

    local existing = findPlayerVehicle(plate)
    if existing then
        local sets, vals = {}, {}
        local function set(col, val)
            if val == nil then return end
            if hasColumn('player_vehicles', col) then
                sets[#sets + 1] = ('`%s` = ?'):format(col)
                vals[#vals + 1] = val
            end
        end
        set('citizenid', ownerId)
        set('license', license)
        set('vehicle', modelName)
        if hasColumn('player_vehicles', 'hash') then
            -- Prefer numeric when column is int-like; string still works via coercion
            set('hash', hashNum)
        end
        set('mods', mods)
        if gCol then set(gCol, garageName) end
        set('state', state)
        set('stored', state == 1 and 1 or 0)
        set('in_garage', state == 1 and 1 or 0)
        set('fuel', math.floor(tonumber(props.fuelLevel) or 100))
        set('engine', tonumber(props.engineHealth) or 1000.0)
        set('body', tonumber(props.bodyHealth) or 1000.0)
        set('depotprice', 0)
        if #sets == 0 then return true, 'noop' end
        local wherePlate = existing.plate or plate
        vals[#vals + 1] = wherePlate
        if mysqlUpdate(
            ('UPDATE player_vehicles SET %s WHERE plate = ?'):format(table.concat(sets, ', ')),
            vals
        ) then
            return true, 'updated'
        end
        return false, 'update_failed'
    end

    local cols, vals, marks = {}, {}, {}
    local function add(col, val)
        if val == nil then return end
        if hasColumn('player_vehicles', col) then
            cols[#cols + 1] = ('`%s`'):format(col)
            vals[#vals + 1] = val
            marks[#marks + 1] = '?'
        end
    end

    add('license', license)
    add('citizenid', ownerId)
    add('vehicle', modelName)
    add('hash', hashNum)
    add('mods', mods)
    add('plate', plate)
    if gCol then add(gCol, garageName) end
    add('state', state)
    add('stored', state == 1 and 1 or 0)
    add('in_garage', state == 1 and 1 or 0)
    add('fuel', math.floor(tonumber(props.fuelLevel) or 100))
    add('engine', tonumber(props.engineHealth) or 1000.0)
    add('body', tonumber(props.bodyHealth) or 1000.0)
    add('depotprice', 0)
    add('drivingdistance', 0)
    add('balance', 0)
    add('paymentamount', 0)
    add('paymentsleft', 0)
    add('financetime', 0)
    add('nickname', '')
    add('damage', '')
    add('logs', '[]')

    if #cols == 0 then return false, 'no_columns' end

    local ok = mysqlInsert(
        ('INSERT INTO player_vehicles (%s) VALUES (%s)'):format(
            table.concat(cols, ', '),
            table.concat(marks, ', ')
        ),
        vals
    )
    if not ok then
        -- Retry without optional finance fields if schema is picky
        return false, 'insert_failed'
    end

    -- Verify row landed
    if not findPlayerVehicle(plate) then
        print(('[viking_foodtruck] player_vehicles insert reported ok but row missing for plate=%s'):format(plate))
        return false, 'verify_failed'
    end
    return true, 'inserted'
end

local function upsertOwnedVehicles(ownerId, modelName, plate, props, stored, garageName)
    if not tableExists('owned_vehicles') then return false, 'no_table' end
    plate = trimPlate(plate)
    props = ensureProps(props, modelName, plate)
    local vehicleJson = encodeMods(props)
    garageName = garageName or defaultGarage()
    stored = stored and 1 or 0

    local existing = findOwnedVehicle(plate)
    if existing then
        local sets, vals = {}, {}
        local function set(col, val)
            if val == nil then return end
            if hasColumn('owned_vehicles', col) then
                sets[#sets + 1] = ('`%s` = ?'):format(col)
                vals[#vals + 1] = val
            end
        end
        set('owner', ownerId)
        set('vehicle', vehicleJson)
        set('stored', stored)
        set('parking', garageName)
        set('garage', garageName)
        set('garage_id', garageName)
        set('type', 'car')
        if #sets == 0 then return true, 'noop' end
        vals[#vals + 1] = existing.plate or plate
        if mysqlUpdate(
            ('UPDATE owned_vehicles SET %s WHERE plate = ?'):format(table.concat(sets, ', ')),
            vals
        ) then
            return true, 'updated'
        end
        return false, 'update_failed'
    end

    local cols, vals, marks = {}, {}, {}
    local function add(col, val)
        if val == nil then return end
        if hasColumn('owned_vehicles', col) then
            cols[#cols + 1] = ('`%s`'):format(col)
            vals[#vals + 1] = val
            marks[#marks + 1] = '?'
        end
    end
    add('owner', ownerId)
    add('plate', plate)
    add('vehicle', vehicleJson)
    add('type', 'car')
    add('stored', stored)
    add('parking', garageName)
    add('garage', garageName)
    add('garage_id', garageName)

    if #cols == 0 then return false, 'no_columns' end
    local ok = mysqlInsert(
        ('INSERT INTO owned_vehicles (%s) VALUES (%s)'):format(
            table.concat(cols, ', '),
            table.concat(marks, ', ')
        ),
        vals
    )
    if not ok then return false, 'insert_failed' end
    if not findOwnedVehicle(plate) then
        return false, 'verify_failed'
    end
    return true, 'inserted'
end

local function registerQbx(ownerId, modelName, plate, props, garageName, asStored)
    if not started('qbx_vehicles') then return false end
    plate = trimPlate(plate)
    props = ensureProps(props, modelName, plate)
    garageName = garageName or defaultGarage()

    local existingId
    local okFind, id = tryExport('qbx_vehicles', 'GetVehicleIdByPlate', plate)
    if okFind and id then existingId = id end

    if existingId then
        pcall(function()
            exports.qbx_vehicles:SetPlayerVehicleOwner(existingId, ownerId)
        end)
        if asStored then
            pcall(function()
                exports.qbx_vehicles:SaveVehicle(existingId, {
                    garage = garageName,
                    state = 1,
                    props = props,
                })
            end)
        else
            pcall(function()
                MySQL.update.await('UPDATE player_vehicles SET state = 0, citizenid = ?, mods = ?, plate = ? WHERE id = ?', {
                    ownerId, encodeMods(props), plate, existingId,
                })
            end)
        end
        return true
    end

    local request = {
        model = modelName,
        citizenid = ownerId,
        props = props,
        garage = garageName,
    }

    local ok, vehicleId, err = tryExport('qbx_vehicles', 'CreatePlayerVehicle', request)
    if ok and vehicleId then
        -- Force our plate + desired state (CreatePlayerVehicle may assign random plate)
        pcall(function()
            MySQL.update.await(
                'UPDATE player_vehicles SET plate = ?, state = ?, citizenid = ?, mods = ?, garage = ? WHERE id = ?',
                { plate, asStored and 1 or 0, ownerId, encodeMods(props), garageName, vehicleId }
            )
        end)
        -- Also try garage_id if present
        if hasColumn('player_vehicles', 'garage_id') then
            pcall(function()
                MySQL.update.await('UPDATE player_vehicles SET garage_id = ? WHERE id = ?', { garageName, vehicleId })
            end)
        end
        print(('[viking_foodtruck] qbx_vehicles registered plate=%s id=%s'):format(plate, tostring(vehicleId)))
        return true
    end
    if err then
        print(('[viking_foodtruck] qbx_vehicles CreatePlayerVehicle failed: %s'):format(
            type(err) == 'table' and json.encode(err) or tostring(err)
        ))
    end
    return false
end

local function fireGarageHooks(ownerSrc, ownerId, modelName, plate, props, state, garageName, netId)
    plate = trimPlate(plate)
    garageName = garageName or defaultGarage()
    state = tonumber(state) or 0

    -- qb-garages (plural + singular resource names)
    TriggerEvent('qb-garages:server:updateVehicleState', state, plate, garageName)
    TriggerEvent('qb-garage:server:updateVehicleState', state, plate, garageName)
    if ownerSrc then
        TriggerEvent('qb-garages:server:UpdateOutsideVehicles', ownerSrc)
        TriggerClientEvent('qb-garages:client:updateVehicleState', ownerSrc, state, plate, garageName)
    end

    -- cd_garage
    if started('cd_garage') then
        if ownerSrc then
            pcall(function()
                TriggerEvent('cd_garage:AddKeys', ownerSrc, plate)
            end)
            TriggerClientEvent('cd_garage:AddKeys', ownerSrc, plate)
        end
        tryExport('cd_garage', 'AddOwnedVehicle', ownerSrc, plate, modelName, props)
        tryExport('cd_garage', 'SetVehicleState', plate, state, garageName)
        tryExport('cd_garage', 'UpdateVehicleState', plate, state, garageName)
    end

    -- okokGarage
    if started('okokGarage') then
        if ownerSrc then
            TriggerClientEvent('okokGarage:GiveKeys', ownerSrc, plate)
        end
        tryExport('okokGarage', 'GiveVehicle', ownerSrc, modelName, plate)
        tryExport('okokGarage', 'GiveKeys', ownerSrc, plate)
    end

    -- jg-advancedgarages
    if started('jg-advancedgarages') then
        if netId and state == 0 then
            tryExport('jg-advancedgarages', 'registerVehicleOutside', plate, netId)
            TriggerEvent('jg-advancedgarages:server:register-vehicle-outside', plate, netId)
        end
        if state == 1 then
            tryExport('jg-advancedgarages', 'deleteOutsideVehicle', plate)
        end
    end

    -- qs-advancedgarages
    if started('qs-advancedgarages') then
        tryExport('qs-advancedgarages', 'addVehicle', ownerSrc, modelName, plate, garageName)
        tryExport('qs-advancedgarages', 'setVehicleState', plate, state, garageName)
    end

    -- loaf_garage
    if started('loaf_garage') then
        tryExport('loaf_garage', 'AddVehicle', ownerId, plate, modelName, props)
    end

    -- rcore_garage
    if started('rcore_garage') then
        tryExport('rcore_garage', 'addVehicle', ownerSrc, modelName, plate)
    end

    TriggerEvent('garages:server:updateVehicleState', state, plate, garageName)
    TriggerEvent('vehiclekeys:server:SetVehicleOwner', plate, ownerId)
    TriggerEvent('viking_foodtruck:garageRegistered', ownerSrc, ownerId, modelName, plate, props, state, garageName)
end

--- Register / refresh ownership across every available garage backend
function Garage.RegisterVehicle(ownerSrc, ownerId, modelName, plate, props, opts)
    if Config.GarageAllowPark == false then return true end
    opts = opts or {}
    plate = trimPlate(plate)
    if plate == '' or not ownerId then
        print('[viking_foodtruck] Garage.RegisterVehicle aborted — missing plate/owner')
        return false, 'Invalid plate/owner'
    end
    modelName = tostring(modelName or Config.DefaultVehicle or 'taco'):lower()
    props = ensureProps(props, modelName, plate)
    local garageName = resolveGarageName(opts.garage)
    local state = opts.state
    if state == nil then state = 0 end
    local asStored = state == 1
    local okAny = false

    local custom = Config.CustomGarage or {}
    if custom.resource and custom.registerExport and started(custom.resource) then
        local ok = tryExport(custom.resource, custom.registerExport, ownerSrc, ownerId, modelName, plate, props, garageName)
        okAny = okAny or ok
    end

    if registerQbx(ownerId, modelName, plate, props, garageName, asStored) then
        okAny = true
    end

    local okPv, pvMsg = upsertPlayerVehicles(ownerSrc, ownerId, modelName, plate, props, state, garageName)
    if okPv then
        okAny = true
        print(('[viking_foodtruck] player_vehicles %s plate=%s owner=%s state=%s garage=%s'):format(
            tostring(pvMsg), plate, tostring(ownerId), tostring(state), garageName
        ))
    elseif pvMsg and pvMsg ~= 'no_table' then
        print(('[viking_foodtruck] player_vehicles failed (%s) plate=%s'):format(tostring(pvMsg), plate))
    end

    local okOv, ovMsg = upsertOwnedVehicles(ownerId, modelName, plate, props, asStored, garageName)
    if okOv then
        okAny = true
        print(('[viking_foodtruck] owned_vehicles %s plate=%s owner=%s'):format(tostring(ovMsg), plate, tostring(ownerId)))
    elseif ovMsg and ovMsg ~= 'no_table' then
        print(('[viking_foodtruck] owned_vehicles failed (%s) plate=%s'):format(tostring(ovMsg), plate))
    end

    fireGarageHooks(ownerSrc, ownerId, modelName, plate, props, state, garageName, opts.netId)

    if not okAny then
        print('[viking_foodtruck] WARNING: Garage.RegisterVehicle could not write to any garage DB/table')
        print('[viking_foodtruck] Ensure oxmysql is running and player_vehicles or owned_vehicles exists')
    end
    return okAny
end

function Garage.SetOut(plate, netId)
    if Config.GarageAllowPark == false then return true end
    plate = trimPlate(plate)
    if plate == '' then return false end
    local garageName = defaultGarage()

    if tableExists('player_vehicles') then
        local sets = { 'state = 0' }
        if hasColumn('player_vehicles', 'stored') then sets[#sets + 1] = 'stored = 0' end
        if hasColumn('player_vehicles', 'in_garage') then sets[#sets + 1] = 'in_garage = 0' end
        mysqlUpdate(
            ('UPDATE player_vehicles SET %s WHERE REPLACE(UPPER(TRIM(plate)), " ", "") = ? OR plate = ? OR plate = ?'):format(
                table.concat(sets, ', ')
            ),
            { compactPlate(plate), plate, padPlate(plate) }
        )
    end
    if tableExists('owned_vehicles') then
        mysqlUpdate(
            'UPDATE owned_vehicles SET stored = 0 WHERE REPLACE(UPPER(TRIM(plate)), " ", "") = ? OR plate = ? OR plate = ?',
            { compactPlate(plate), plate, padPlate(plate) }
        )
    end

    if started('qbx_vehicles') then
        local ok, vehicleId = tryExport('qbx_vehicles', 'GetVehicleIdByPlate', plate)
        if ok and vehicleId then
            pcall(function()
                MySQL.update.await('UPDATE player_vehicles SET state = 0 WHERE id = ?', { vehicleId })
            end)
        end
    end

    if started('jg-advancedgarages') and netId then
        tryExport('jg-advancedgarages', 'registerVehicleOutside', plate, netId)
        TriggerEvent('jg-advancedgarages:server:register-vehicle-outside', plate, netId)
    end

    TriggerEvent('qb-garages:server:updateVehicleState', 0, plate, garageName)
    TriggerEvent('qb-garage:server:updateVehicleState', 0, plate, garageName)
    return true
end

function Garage.SetStored(plate, garageName, props)
    if Config.GarageAllowPark == false then return true end
    plate = trimPlate(plate)
    if plate == '' then return false end
    garageName = resolveGarageName(garageName)
    props = type(props) == 'table' and props or nil

    if tableExists('player_vehicles') then
        local sets, vals = { 'state = 1' }, {}
        local gCol = garageColumnFor('player_vehicles')
        if gCol then
            sets[#sets + 1] = ('`%s` = ?'):format(gCol)
            vals[#vals + 1] = garageName
        end
        if hasColumn('player_vehicles', 'stored') then sets[#sets + 1] = 'stored = 1' end
        if hasColumn('player_vehicles', 'in_garage') then sets[#sets + 1] = 'in_garage = 1' end
        if props then
            if hasColumn('player_vehicles', 'mods') then
                sets[#sets + 1] = 'mods = ?'
                vals[#vals + 1] = encodeMods(ensureProps(props, props.model, plate))
            end
            if hasColumn('player_vehicles', 'fuel') then
                sets[#sets + 1] = 'fuel = ?'
                vals[#vals + 1] = math.floor(tonumber(props.fuelLevel or props.fuel) or 100)
            end
            if hasColumn('player_vehicles', 'engine') then
                sets[#sets + 1] = 'engine = ?'
                vals[#vals + 1] = tonumber(props.engineHealth) or 1000.0
            end
            if hasColumn('player_vehicles', 'body') then
                sets[#sets + 1] = 'body = ?'
                vals[#vals + 1] = tonumber(props.bodyHealth) or 1000.0
            end
        end
        vals[#vals + 1] = compactPlate(plate)
        vals[#vals + 1] = plate
        vals[#vals + 1] = padPlate(plate)
        mysqlUpdate(
            ('UPDATE player_vehicles SET %s WHERE REPLACE(UPPER(TRIM(plate)), " ", "") = ? OR plate = ? OR plate = ?'):format(
                table.concat(sets, ', ')
            ),
            vals
        )
    end

    if tableExists('owned_vehicles') then
        local sets, vals = { 'stored = 1' }, {}
        if hasColumn('owned_vehicles', 'parking') then
            sets[#sets + 1] = 'parking = ?'
            vals[#vals + 1] = garageName
        end
        if hasColumn('owned_vehicles', 'garage') then
            sets[#sets + 1] = 'garage = ?'
            vals[#vals + 1] = garageName
        end
        if hasColumn('owned_vehicles', 'garage_id') then
            sets[#sets + 1] = 'garage_id = ?'
            vals[#vals + 1] = garageName
        end
        if props and hasColumn('owned_vehicles', 'vehicle') then
            sets[#sets + 1] = 'vehicle = ?'
            vals[#vals + 1] = encodeMods(ensureProps(props, props.model, plate))
        end
        vals[#vals + 1] = compactPlate(plate)
        vals[#vals + 1] = plate
        vals[#vals + 1] = padPlate(plate)
        mysqlUpdate(
            ('UPDATE owned_vehicles SET %s WHERE REPLACE(UPPER(TRIM(plate)), " ", "") = ? OR plate = ? OR plate = ?'):format(
                table.concat(sets, ', ')
            ),
            vals
        )
    end

    if started('qbx_vehicles') then
        local ok, vehicleId = tryExport('qbx_vehicles', 'GetVehicleIdByPlate', plate)
        if ok and vehicleId and props then
            pcall(function()
                exports.qbx_vehicles:SaveVehicle(vehicleId, {
                    garage = garageName,
                    state = 1,
                    props = ensureProps(props, props.model, plate),
                })
            end)
        end
    end

    if started('jg-advancedgarages') then
        tryExport('jg-advancedgarages', 'deleteOutsideVehicle', plate)
    end

    TriggerEvent('qb-garages:server:updateVehicleState', 1, plate, garageName)
    TriggerEvent('qb-garage:server:updateVehicleState', 1, plate, garageName)
    TriggerEvent('garages:server:updateVehicleState', 1, plate, garageName)
    print(('[viking_foodtruck] Garage stored plate=%s garage=%s'):format(plate, garageName))
    return true
end

function Garage.RemoveVehicle(plate)
    if Config.GarageAllowPark == false then return true end
    plate = trimPlate(plate)
    if plate == '' then return false end

    if started('qbx_vehicles') then
        local ok, vehicleId = tryExport('qbx_vehicles', 'GetVehicleIdByPlate', plate)
        if ok and vehicleId then
            tryExport('qbx_vehicles', 'DeletePlayerVehicles', 'vehicleId', vehicleId)
            tryExport('qbx_vehicles', 'RemovePlayerVehicle', vehicleId)
        end
    end

    if tableExists('player_vehicles') then
        pcall(function()
            MySQL.query.await(
                'DELETE FROM player_vehicles WHERE REPLACE(UPPER(TRIM(plate)), " ", "") = ? OR plate = ? OR plate = ?',
                { compactPlate(plate), plate, padPlate(plate) }
            )
        end)
    end
    if tableExists('owned_vehicles') then
        pcall(function()
            MySQL.query.await(
                'DELETE FROM owned_vehicles WHERE REPLACE(UPPER(TRIM(plate)), " ", "") = ? OR plate = ? OR plate = ?',
                { compactPlate(plate), plate, padPlate(plate) }
            )
        end)
    end

    if started('jg-advancedgarages') then
        tryExport('jg-advancedgarages', 'deleteOutsideVehicle', plate)
    end
    return true
end

function Garage.IsOut(plate)
    plate = trimPlate(plate)
    if plate == '' then return true end
    local row = findPlayerVehicle(plate)
    if row and row.state ~= nil then
        return tonumber(row.state) == 0
    end
    if row and row.stored ~= nil then
        return tonumber(row.stored) == 0
    end
    row = findOwnedVehicle(plate)
    if row and row.stored ~= nil then
        return tonumber(row.stored) == 0
    end
    return true
end

function Garage.VerifyOwned(plate, ownerId)
    plate = trimPlate(plate)
    local row = findPlayerVehicle(plate)
    if row then
        local cid = row.citizenid or row.citizenId
        return true, cid == ownerId, row
    end
    row = findOwnedVehicle(plate)
    if row then
        return true, row.owner == ownerId, row
    end
    return false, false, nil
end

CreateThread(function()
    Wait(2000)
    -- Clear table cache after DB is ready
    tableCache = {}
    columnCache = {}
    resolvedDefaultGarage = nil
    local g = defaultGarage()
    print(('[viking_foodtruck] garage bridge: type=%s pv=%s ov=%s qbx=%s jg=%s cd=%s okok=%s default=%s'):format(
        Garage.GetType(),
        tostring(tableExists('player_vehicles')),
        tostring(tableExists('owned_vehicles')),
        tostring(started('qbx_vehicles')),
        tostring(started('jg-advancedgarages')),
        tostring(started('cd_garage')),
        tostring(started('okokGarage')),
        g
    ))
end)
