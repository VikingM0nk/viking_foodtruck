--[[
    Billing bridge — external billing scripts OR built-in viking_foodtruck invoices.
    auto detects common resources; Config.Billing = 'builtin' forces internal system.
]]

Billing = Billing or {}

local detected

local function started(name)
    return type(name) == 'string' and name ~= '' and GetResourceState(name) == 'started'
end

local function detect()
    local mode = Config.Billing or 'auto'
    if mode ~= 'auto' then return mode end

    local c = Config.CustomBilling or {}
    if c.resource and started(c.resource) then return 'custom' end

    local order = {
        { 'okokBilling', 'okok' },
        { 'jim-payments', 'jim' },
        { 'qb-phone', 'qb-phone' },
        { 'qs-billing', 'qs' },
        { 'esx_billing', 'esx' },
        { 'codem-billing', 'codem' },
        { 'renewed-billing', 'renewed' },
        { 'Billing', 'generic' },
    }
    for i = 1, #order do
        if started(order[i][1]) then
            return order[i][2]
        end
    end

    return 'builtin'
end

function Billing.GetType()
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

--- Create an external or built-in bill.
--- @return boolean ok, string|nil billIdOrError
function Billing.Create(senderSrc, targetSrc, amount, reason, meta)
    if not IsDuplicityVersion() then return false, 'client' end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'invalid amount' end
    if not GetPlayerName(targetSrc) then return false, 'target offline' end

    reason = tostring(reason or 'Food Truck Order'):sub(1, 128)
    meta = type(meta) == 'table' and meta or {}
    local kind = Billing.GetType()
    local c = Config.CustomBilling or {}

    if kind == 'none' then
        return false, 'billing disabled'
    end

    if kind == 'custom' then
        if c.createExport and c.createExport ~= '' and started(c.resource) then
            local result, ok = callExport(c.resource, c.createExport, senderSrc, targetSrc, amount, reason, meta)
            if ok then return result ~= false, result end
        end
        if c.createEvent and c.createEvent ~= '' then
            TriggerEvent(c.createEvent, senderSrc, targetSrc, amount, reason, meta)
            return true, 'external'
        end
        -- fall through to builtin if custom misconfigured
        kind = 'builtin'
    end

    if kind == 'okok' and started('okokBilling') then
        local ok = pcall(function()
            TriggerEvent('okokBilling:CreateCustomInvoice', targetSrc, amount, reason, meta.society or 'foodtruck', meta.label or 'Food Truck')
        end)
        if not ok then
            callExport('okokBilling', 'CreateCustomInvoice', targetSrc, amount, reason, meta.society or 'foodtruck', meta.label or 'Food Truck')
        end
        TriggerEvent('viking_foodtruck:billing:external', senderSrc, targetSrc, amount, reason, meta)
        return true, 'okok'
    end

    if kind == 'jim' and started('jim-payments') then
        TriggerEvent('jim-payments:client:Charge', targetSrc, amount, reason)
        -- jim often uses client; also try export
        callExport('jim-payments', 'createBill', senderSrc, targetSrc, amount, reason)
        TriggerEvent('viking_foodtruck:billing:external', senderSrc, targetSrc, amount, reason, meta)
        return true, 'jim'
    end

    if kind == 'qb-phone' and started('qb-phone') then
        local senderName = Bridge.GetName(senderSrc)
        local ok = pcall(function()
            exports['qb-phone']:CreateBill(targetSrc, amount, reason, senderName)
        end)
        if not ok then
            TriggerEvent('qb-phone:server:sendBill', targetSrc, amount, reason, senderSrc)
            TriggerClientEvent('qb-phone:client:Bill', targetSrc, amount, reason, senderName)
        end
        TriggerEvent('viking_foodtruck:billing:external', senderSrc, targetSrc, amount, reason, meta)
        return true, 'qb-phone'
    end

    if kind == 'esx' and started('esx_billing') then
        TriggerEvent('esx_billing:sendBill', senderSrc, targetSrc, meta.society or 'society_foodtruck', reason, amount)
        TriggerEvent('viking_foodtruck:billing:external', senderSrc, targetSrc, amount, reason, meta)
        return true, 'esx'
    end

    if kind == 'qs' and started('qs-billing') then
        callExport('qs-billing', 'CreateBill', senderSrc, targetSrc, amount, reason)
        TriggerEvent('viking_foodtruck:billing:external', senderSrc, targetSrc, amount, reason, meta)
        return true, 'qs'
    end

    if kind == 'codem' and started('codem-billing') then
        callExport('codem-billing', 'CreateBill', senderSrc, targetSrc, amount, reason)
        TriggerEvent('viking_foodtruck:billing:external', senderSrc, targetSrc, amount, reason, meta)
        return true, 'codem'
    end

    if kind == 'renewed' and started('renewed-billing') then
        callExport('renewed-billing', 'CreateBill', senderSrc, targetSrc, amount, reason)
        TriggerEvent('viking_foodtruck:billing:external', senderSrc, targetSrc, amount, reason, meta)
        return true, 'renewed'
    end

    if kind == 'generic' and started('Billing') then
        callExport('Billing', 'CreateBill', senderSrc, targetSrc, amount, reason)
        TriggerEvent('viking_foodtruck:billing:external', senderSrc, targetSrc, amount, reason, meta)
        return true, 'generic'
    end

    -- Built-in invoices
    return Billing.CreateBuiltin(senderSrc, targetSrc, amount, reason, meta)
end

function Billing.CreateBuiltin(senderSrc, targetSrc, amount, reason, meta)
    meta = meta or {}
    local billId = ('FTB-%s-%s'):format(os.time(), math.random(1000, 9999))
    local fromId = Bridge.GetIdentifier(senderSrc)
    local toId = Bridge.GetIdentifier(targetSrc)
    MySQL.insert.await([[
        INSERT INTO viking_foodtruck_bills
            (id, truck_id, from_id, to_id, from_src, to_src, amount, reason, status, meta, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'unpaid', ?, NOW())
    ]], {
        billId,
        meta.truckId or '',
        fromId,
        toId,
        senderSrc,
        targetSrc,
        amount,
        reason,
        json.encode(meta),
    })

    Bridge.Notify(targetSrc, ('New bill: $%s — %s'):format(amount, reason), 'inform')
    if GetPlayerName(senderSrc) then
        Bridge.Notify(senderSrc, ('Bill sent to %s for $%s'):format(Bridge.GetName(targetSrc), amount), 'success')
    end
    TriggerClientEvent('viking_foodtruck:client:billCreated', targetSrc, {
        id = billId,
        amount = amount,
        reason = reason,
        truckId = meta.truckId,
    })
    TriggerEvent('viking_foodtruck:billing:created', billId, senderSrc, targetSrc, amount, reason, meta)
    return true, billId
end

function Billing.GetUnpaidForPlayer(src)
    local identifier = Bridge.GetIdentifier(src)
    local rows = MySQL.query.await([[
        SELECT * FROM viking_foodtruck_bills
        WHERE to_id = ? AND status = 'unpaid'
        ORDER BY created_at DESC
    ]], { identifier }) or {}
    return rows
end

function Billing.GetUnpaidForTruck(truckId)
    local rows = MySQL.query.await([[
        SELECT * FROM viking_foodtruck_bills
        WHERE truck_id = ? AND status = 'unpaid'
        ORDER BY created_at DESC
    ]], { truckId }) or {}
    return rows
end

function Billing.PayBuiltin(src, billId, account)
    local row = MySQL.single.await('SELECT * FROM viking_foodtruck_bills WHERE id = ?', { billId })
    if not row or row.status ~= 'unpaid' then
        return false, 'Bill not found'
    end
    local identifier = Bridge.GetIdentifier(src)
    if row.to_id ~= identifier then
        return false, 'Not your bill'
    end

    local amount = math.floor(tonumber(row.amount) or 0)
    local preferred = account or Config.PurchaseAccount or 'bank'
    local paid, used = Bridge.TryRemoveMoney(src, amount, preferred)
    if not paid then
        return false, Config.Locale.not_enough_money
    end

    MySQL.update.await([[
        UPDATE viking_foodtruck_bills
        SET status = 'paid', paid_at = NOW(), paid_from = ?
        WHERE id = ?
    ]], { used or preferred, billId })

    local truckId = row.truck_id
    if truckId and truckId ~= '' and DB and DB.GetAccount then
        local accountRow = DB.GetAccount(truckId)
        accountRow.balance = (accountRow.balance or 0) + amount
        DB.SaveAccount(accountRow)
    else
        -- pay sender if online
        local fromSrc = tonumber(row.from_src)
        if fromSrc and GetPlayerName(fromSrc) then
            Bridge.AddMoney(fromSrc, Config.PurchaseAccount or 'bank', amount)
        end
    end

    Bridge.Notify(src, ('Paid bill $%s'):format(amount), 'success')
    local fromSrc = tonumber(row.from_src)
    if fromSrc and GetPlayerName(fromSrc) then
        Bridge.Notify(fromSrc, ('Bill %s paid ($%s)'):format(billId, amount), 'success')
    end
    TriggerEvent('viking_foodtruck:billing:paid', billId, src, amount, truckId)
    return true, amount
end

function Billing.CancelBuiltin(billId)
    MySQL.update.await([[
        UPDATE viking_foodtruck_bills SET status = 'cancelled' WHERE id = ? AND status = 'unpaid'
    ]], { billId })
end

function Billing.UsesBuiltin()
    return Billing.GetType() == 'builtin'
end
