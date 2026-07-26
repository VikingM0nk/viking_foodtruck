--[[
    Built-in client UI — always used for menus/dialogs so Order Food / Stock always open.
    ox_lib callbacks can still be used separately via shared/lib_init.lua.
]]

if type(lib) ~= 'table' then lib = {} end

local textUiOpen = false
local contexts = {}
local nuiWait

local function nuiAsk(action, data)
    -- Cancel any previous waiter so nested menus don't deadlock
    if nuiWait then
        local old = nuiWait
        nuiWait = nil
        old:resolve(nil)
    end
    local p = promise.new()
    nuiWait = p
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({
        action = action,
        data = data or {},
    })
    return Citizen.Await(p)
end

RegisterNUICallback('ftlibResult', function(body, cb)
    local p = nuiWait
    nuiWait = nil
    SetNuiFocus(false, false)
    if p then p:resolve(body) end
    cb('ok')
end)

RegisterNUICallback('ftlibCancel', function(_, cb)
    local p = nuiWait
    nuiWait = nil
    SetNuiFocus(false, false)
    if p then p:resolve(nil) end
    cb('ok')
end)

RegisterNUICallback('stockInvClose', function(_, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'stockInv', data = { show = false } })
    cb('ok')
end)

RegisterNUICallback('stockInvAction', function(body, cb)
    cb('ok')
    if type(body) ~= 'table' then return end
    TriggerEvent('viking_foodtruck:client:stockInvAction', body)
end)

-- Always override notify when missing; otherwise keep ox notify if present
if type(lib.notify) ~= 'function' then
    function lib.notify(data)
        data = data or {}
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName(data.description or data.title or '')
        EndTextCommandThefeedPostTicker(false, true)
    end
end

-- Force built-in text UI / menus (ox_lib UI is often broken or missing)
function lib.showTextUI(text)
    textUiOpen = true
    SendNUIMessage({ action = 'textui', data = { show = true, text = text } })
end

function lib.hideTextUI()
    if not textUiOpen then
        SendNUIMessage({ action = 'textui', data = { show = false } })
        return
    end
    textUiOpen = false
    SendNUIMessage({ action = 'textui', data = { show = false } })
end

if type(lib.requestModel) ~= 'function' then
    function lib.requestModel(model)
        if type(model) == 'string' then model = joaat(model) end
        if HasModelLoaded(model) then return model end
        RequestModel(model)
        local timeout = GetGameTimer() + 10000
        while not HasModelLoaded(model) and GetGameTimer() < timeout do
            Wait(10)
        end
        return model
    end
end

function lib.progressBar(opts)
    opts = opts or {}
    local duration = tonumber(opts.duration) or 5000
    SendNUIMessage({
        action = 'progress',
        data = { show = true, label = opts.label or 'Working...', duration = duration },
    })
    if opts.anim and opts.anim.dict and opts.anim.clip then
        RequestAnimDict(opts.anim.dict)
        local t = GetGameTimer() + 3000
        while not HasAnimDictLoaded(opts.anim.dict) and GetGameTimer() < t do Wait(10) end
        TaskPlayAnim(PlayerPedId(), opts.anim.dict, opts.anim.clip, 8.0, -8.0, duration, 49, 0.0, false, false, false)
    end
    local ped = PlayerPedId()
    local endAt = GetGameTimer() + duration
    local cancelled = false
    while GetGameTimer() < endAt do
        if opts.canCancel and IsControlJustReleased(0, 200) then
            cancelled = true
            break
        end
        if opts.disable then
            DisableControlAction(0, 30, true)
            DisableControlAction(0, 31, true)
            DisableControlAction(0, 21, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
        end
        if opts.useWhileDead == false and IsEntityDead(ped) then
            cancelled = true
            break
        end
        Wait(0)
    end
    ClearPedTasks(ped)
    SendNUIMessage({ action = 'progress', data = { show = false } })
    return not cancelled
end

function lib.alertDialog(opts)
    opts = opts or {}
    lib.hideTextUI()
    local result = nuiAsk('alert', {
        header = opts.header or 'Confirm',
        content = opts.content or '',
        cancel = opts.cancel ~= false,
    })
    if not result then return 'cancel' end
    return result.confirm and 'confirm' or 'cancel'
end

function lib.inputDialog(title, rows)
    lib.hideTextUI()
    local result = nuiAsk('input', {
        title = title or 'Input',
        rows = rows or {},
    })
    if not result or not result.values then return nil end
    return result.values
end

function lib.registerContext(data)
    if type(data) ~= 'table' or not data.id then return end
    contexts[data.id] = data
end

function lib.showContext(id)
    local ctx = contexts[id]
    if not ctx then
        print(('[viking_foodtruck] Missing context menu: %s'):format(tostring(id)))
        return
    end
    lib.hideTextUI()
    local options = {}
    for i, opt in ipairs(ctx.options or {}) do
        options[#options + 1] = {
            index = i,
            title = opt.title or ('Option %s'):format(i),
            description = opt.description,
            disabled = opt.disabled and true or false,
        }
    end
    if #options == 0 then
        Bridge.NotifyLocal('No options available', 'error')
        return
    end
    local result = nuiAsk('context', {
        id = ctx.id,
        title = ctx.title or 'Menu',
        options = options,
    })
    if not result or type(result.index) ~= 'number' then return end
    local chosen = ctx.options[result.index]
    if chosen and not chosen.disabled and chosen.onSelect then
        -- Defer so NUI focus can clear before next menu opens
        SetTimeout(50, function()
            chosen.onSelect()
        end)
    end
end

--- Inventory-style stock viewer (NUI)
function lib.showStockInventory(payload)
    lib.hideTextUI()
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({
        action = 'stockInv',
        data = {
            show = true,
            title = payload.title or 'Truck Stock',
            truckId = payload.truckId,
            prepared = payload.prepared or {},
            ingredients = payload.ingredients or {},
        },
    })
end

if type(lib.points) ~= 'table' then
    lib.points = {}
    function lib.points.new(data)
        local point = {
            coords = data.coords,
            distance = data.distance or 2.5,
            currentDistance = 999.0,
            removed = false,
        }

        function point:remove()
            self.removed = true
        end

        CreateThread(function()
            while not point.removed do
                local coords = GetEntityCoords(PlayerPedId())
                local dist = #(coords - point.coords)
                point.currentDistance = dist
                local inside = dist <= point.distance
                if inside and not point._inside then
                    point._inside = true
                    if point.onEnter then point:onEnter() end
                elseif not inside and point._inside then
                    point._inside = false
                    if point.onExit then point:onExit() end
                end
                if inside and point.nearby then
                    point:nearby()
                    Wait(0)
                else
                    Wait(inside and 100 or 500)
                end
            end
        end)

        return point
    end
end

print('[viking_foodtruck] Built-in NUI menus active (Order Food / Staff / Stock).')
