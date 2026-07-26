local creatorOpen = false
local purchasePed
local purchaseBlip
local purchasePoint

local function setCreatorOpen(state)
    creatorOpen = state
    SetNuiFocus(state, state)
    TriggerServerEvent('viking_foodtruck:server:creatorState', state)
end

local function openCreator()
    local isAdmin = lib.callback.await('viking_foodtruck:isAdmin', false)
    if not isAdmin then
        Bridge.NotifyLocal(Config.Locale.no_permission, 'error')
        return
    end
    local data = lib.callback.await('viking_foodtruck:getCreatorData', false)
    if not data then
        Bridge.NotifyLocal(Config.Locale.no_permission, 'error')
        return
    end
    setCreatorOpen(true)
    SendNUIMessage({
        action = 'openCreator',
        data = data,
    })
end

local function closeCreator()
    setCreatorOpen(false)
    SendNUIMessage({ action = 'closeCreator' })
end

RegisterCommand(Config.Command or 'foodtruckcreator', function()
    if creatorOpen then
        closeCreator()
    else
        openCreator()
    end
end, false)

RegisterNUICallback('close', function(_, cb)
    closeCreator()
    cb('ok')
end)

RegisterNUICallback('getCoords', function(_, cb)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    cb({
        x = coords.x + 0.0,
        y = coords.y + 0.0,
        z = coords.z + 0.0,
        w = heading + 0.0,
    })
end)

RegisterNUICallback('saveTruck', function(data, cb)
    local ok, result = lib.callback.await('viking_foodtruck:saveTruck', false, data)
    cb({ ok = ok, result = result })
end)

RegisterNUICallback('deleteTruck', function(data, cb)
    local ok, err = lib.callback.await('viking_foodtruck:deleteTruck', false, data and data.id)
    cb({ ok = ok, error = err })
end)

RegisterNUICallback('importTemplate', function(data, cb)
    local result = lib.callback.await('viking_foodtruck:importTemplate', false, data and data.id)
    cb({ truck = result })
end)

RegisterNUICallback('refresh', function(_, cb)
    local data = lib.callback.await('viking_foodtruck:getCreatorData', false)
    cb(data or {})
end)

exports('IsCreatorOpen', function()
    return creatorOpen
end)

local function getGroundZ(x, y, z)
    local found, groundZ = GetGroundZFor_3dCoord(x + 0.0, y + 0.0, (z or 1000.0) + 50.0, false)
    if found then return groundZ end
    -- Fallback ray from above
    local handle = StartShapeTestRay(x, y, (z or 100.0) + 50.0, x, y, (z or 100.0) - 50.0, 1, 0, 0)
    local retval, hit, endCoords = GetShapeTestResult(handle)
    local timeout = GetGameTimer() + 500
    while retval == 1 and GetGameTimer() < timeout do
        Wait(0)
        retval, hit, endCoords = GetShapeTestResult(handle)
    end
    if hit == 1 and endCoords then
        return endCoords.z
    end
    return z
end

local function spawnPurchasePed()
    local cfg = Config.PurchasePed
    if not cfg or not cfg.coords then return end

    local model = cfg.model
    if type(model) == 'string' then model = joaat(model) end
    lib.requestModel(model)

    -- Request collision around the spawn so ground Z is accurate
    local c = cfg.coords
    RequestCollisionAtCoord(c.x, c.y, c.z)
    local colTimeout = GetGameTimer() + 2000
    while GetGameTimer() < colTimeout do
        RequestCollisionAtCoord(c.x, c.y, c.z)
        local found = GetGroundZFor_3dCoord(c.x + 0.0, c.y + 0.0, c.z + 50.0, false)
        if found then break end
        Wait(50)
    end

    local groundZ = getGroundZ(c.x, c.y, c.z)
    purchasePed = CreatePed(0, model, c.x, c.y, groundZ + 1.0, c.w or 0.0, false, true)
    SetEntityAsMissionEntity(purchasePed, true, true)
    SetBlockingOfNonTemporaryEvents(purchasePed, true)
    SetEntityInvincible(purchasePed, true)
    SetPedCanRagdoll(purchasePed, false)
    SetPedDiesWhenInjured(purchasePed, false)

    -- Drop onto ground, then freeze so they stand on top (not buried)
    Wait(0)
    local found, snapZ = GetGroundZFor_3dCoord(c.x + 0.0, c.y + 0.0, groundZ + 5.0, false)
    if found then groundZ = snapZ end
    SetEntityCoordsNoOffset(purchasePed, c.x, c.y, groundZ, false, false, false)
    SetEntityHeading(purchasePed, c.w or 0.0)
    FreezeEntityPosition(purchasePed, true)

    if cfg.scenario then
        TaskStartScenarioInPlace(purchasePed, cfg.scenario, 0, true)
    end
    SetModelAsNoLongerNeeded(model)

    local interactZ = GetEntityCoords(purchasePed).z
    if cfg.blip and cfg.blip.enabled then
        purchaseBlip = AddBlipForCoord(c.x, c.y, interactZ)
        SetBlipSprite(purchaseBlip, cfg.blip.sprite or 106)
        SetBlipColour(purchaseBlip, cfg.blip.color or 5)
        SetBlipScale(purchaseBlip, cfg.blip.scale or 0.8)
        SetBlipAsShortRange(purchaseBlip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(cfg.blip.label or 'Food Truck Broker')
        EndTextCommandSetBlipName(purchaseBlip)
    end

    purchasePoint = lib.points.new({
        coords = vector3(c.x, c.y, interactZ),
        distance = cfg.interactDistance or 2.5,
    })

    function purchasePoint:onEnter()
        lib.showTextUI(Config.Locale.purchase_prompt)
    end

    function purchasePoint:onExit()
        lib.hideTextUI()
    end

    function purchasePoint:nearby()
        if self.currentDistance < (cfg.interactDistance or 2.5) and IsControlJustReleased(0, 38) then
            openPurchaseMenu()
        end
    end
end

function openPurchaseMenu()
    local list = lib.callback.await('viking_foodtruck:getPurchaseList', false) or {}
    local options = {}

    for i = 1, #list do
        local t = list[i]
        local desc = t.description or ''
        if t.ownedByYou then
            options[#options + 1] = {
                title = t.label .. ' (Owned)',
                description = ('Sell back for ~$%s'):format(math.floor((t.price or 0) * (Config.SellBackPercent or 0.5))),
                icon = 'store',
                onSelect = function()
                    local confirm = lib.alertDialog({
                        header = 'Sell Food Truck',
                        content = ('Sell %s back to the broker?'):format(t.label),
                        centered = true,
                        cancel = true,
                    })
                    if confirm == 'confirm' then
                        local ok = lib.callback.await('viking_foodtruck:sellTruck', false, t.id)
                        if not ok then
                            Bridge.NotifyLocal('Could not sell truck', 'error')
                        end
                        -- Server also despawns the active truck entity
                    end
                end,
            }
        elseif t.available then
            options[#options + 1] = {
                title = t.label,
                description = ('$%s — %s\n%s'):format(t.price or 0, t.vehicle or 'truck', desc),
                icon = 'truck',
                onSelect = function()
                    local confirm = lib.alertDialog({
                        header = 'Buy Food Truck',
                        content = ('Purchase %s for $%s?'):format(t.label, t.price or 0),
                        centered = true,
                        cancel = true,
                    })
                    if confirm == 'confirm' then
                        local ok, err = lib.callback.await('viking_foodtruck:purchaseTruck', false, t.id)
                        if not ok then
                            Bridge.NotifyLocal(type(err) == 'string' and err or 'Purchase failed', 'error')
                        end
                        -- Server triggers viking_foodtruck:client:spawnPurchasedTruck
                    end
                end,
            }
        else
            options[#options + 1] = {
                title = t.label .. ' (Sold)',
                description = desc,
                icon = 'lock',
                disabled = true,
            }
        end
    end

    if #options == 0 then
        options[1] = {
            title = 'No trucks available',
            description = 'Ask an admin to create food trucks in /foodtruckcreator',
            disabled = true,
        }
    end

    lib.registerContext({
        id = 'viking_foodtruck_purchase',
        title = 'Food Truck Broker',
        options = options,
    })
    lib.showContext('viking_foodtruck_purchase')
end

CreateThread(function()
    Wait(500)
    spawnPurchasePed()
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if creatorOpen then
        setCreatorOpen(false)
    end
    if purchasePoint then purchasePoint:remove() end
    if purchaseBlip and DoesBlipExist(purchaseBlip) then RemoveBlip(purchaseBlip) end
    if purchasePed and DoesEntityExist(purchasePed) then DeleteEntity(purchasePed) end
    lib.hideTextUI()
end)
