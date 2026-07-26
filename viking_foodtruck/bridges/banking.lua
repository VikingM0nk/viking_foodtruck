--[[
    Banking bridge — works with any banking resource via auto-detect or Config.CustomBanking.
    When active, Bridge bank account operations prefer this layer.
]]

Banking = Banking or {}

local detected

local function started(name)
    return type(name) == 'string' and name ~= '' and GetResourceState(name) == 'started'
end

local function detect()
    local mode = Config.Banking or 'auto'
    if mode ~= 'auto' then return mode end

    local order = {
        { 'Renewed-Banking', 'renewed' },
        { 'qb-banking', 'qb-banking' },
        { 'okokBanking', 'okok' },
        { 'wasabi_banking', 'wasabi' },
        { 'fd_banking', 'fd' },
        { 'snipe-banking', 'snipe' },
        { 'renewed-banking', 'renewed' },
    }
    for i = 1, #order do
        if started(order[i][1]) then
            return order[i][2]
        end
    end

    if Config.CustomBanking and started(Config.CustomBanking.resource) then
        return 'custom'
    end
    return 'framework'
end

function Banking.GetType()
    if not detected then
        detected = detect()
    end
    return detected
end

local function callExport(resource, exportName, ...)
    if not started(resource) or not exportName or exportName == '' then return nil, false end
    local exp = exports[resource]
    if not exp or not exp[exportName] then return nil, false end
    local ok, result = pcall(exp[exportName], exp, ...)
    if ok then return result, true end
    -- some resources use exports without self
    ok, result = pcall(function(...)
        return exports[resource][exportName](...)
    end, ...)
    return result, ok
end

--- Get bank balance (nil = fall through to framework)
function Banking.GetBalance(src)
    if not IsDuplicityVersion() then return nil end
    local kind = Banking.GetType()
    if kind == 'framework' or kind == 'none' then return nil end

    if kind == 'custom' then
        local c = Config.CustomBanking or {}
        if c.getBalance and c.getBalance ~= '' then
            local result, ok = callExport(c.resource, c.getBalance, src)
            if ok and type(result) == 'number' then return result end
        end
        return nil
    end

    if kind == 'qb-banking' then
        local result, ok = callExport('qb-banking', 'GetAccountBalance', Bridge.GetIdentifier(src))
        if ok and type(result) == 'number' then return result end
        result, ok = callExport('qb-banking', 'GetAccount', Bridge.GetIdentifier(src))
        if ok and type(result) == 'table' and result.account_balance then
            return tonumber(result.account_balance) or 0
        end
        return nil
    end

    if kind == 'renewed' then
        local res = started('Renewed-Banking') and 'Renewed-Banking' or 'renewed-banking'
        local result, ok = callExport(res, 'getAccountMoney', Bridge.GetIdentifier(src))
        if ok and type(result) == 'number' then return result end
        return nil
    end

    if kind == 'okok' then
        local result, ok = callExport('okokBanking', 'GetAccount', Bridge.GetIdentifier(src))
        if ok and type(result) == 'number' then return result end
        return nil
    end

    if kind == 'wasabi' then
        local result, ok = callExport('wasabi_banking', 'GetAccountBalance', src)
        if ok and type(result) == 'number' then return result end
        return nil
    end

    if kind == 'fd' then
        local result, ok = callExport('fd_banking', 'GetAccount', Bridge.GetIdentifier(src))
        if ok and type(result) == 'table' and result.balance then
            return tonumber(result.balance) or 0
        end
        return nil
    end

    if kind == 'snipe' then
        local result, ok = callExport('snipe-banking', 'GetAccountBalance', src)
        if ok and type(result) == 'number' then return result end
        return nil
    end

    return nil
end

function Banking.Remove(src, amount, reason)
    if not IsDuplicityVersion() then return nil end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    local kind = Banking.GetType()
    if kind == 'framework' or kind == 'none' then return nil end
    reason = reason or 'foodtruck'

    if kind == 'custom' then
        local c = Config.CustomBanking or {}
        if c.removeMoney and c.removeMoney ~= '' then
            local result, ok = callExport(c.resource, c.removeMoney, src, amount, reason)
            if ok then return result ~= false end
        end
        if c.removeEvent and c.removeEvent ~= '' then
            TriggerEvent(c.removeEvent, src, amount, reason)
            return true
        end
        return nil
    end

    if kind == 'qb-banking' then
        local bal = Banking.GetBalance(src)
        if bal ~= nil and bal < amount then return false end
        local _, ok = callExport('qb-banking', 'RemoveMoney', Bridge.GetIdentifier(src), amount, reason)
        if ok then return true end
        _, ok = callExport('qb-banking', 'RemoveAccountMoney', Bridge.GetIdentifier(src), amount)
        if ok then return true end
        return nil
    end

    if kind == 'renewed' then
        local res = started('Renewed-Banking') and 'Renewed-Banking' or 'renewed-banking'
        local bal = Banking.GetBalance(src)
        if bal ~= nil and bal < amount then return false end
        local result, ok = callExport(res, 'removeAccountMoney', Bridge.GetIdentifier(src), amount)
        if ok then return result ~= false end
        return nil
    end

    if kind == 'okok' then
        local _, ok = callExport('okokBanking', 'RemoveMoney', Bridge.GetIdentifier(src), amount)
        if ok then return true end
        TriggerEvent('okokBanking:RemoveMoney', src, amount)
        return true
    end

    if kind == 'wasabi' then
        local result, ok = callExport('wasabi_banking', 'RemoveMoney', src, amount, reason)
        if ok then return result ~= false end
        return nil
    end

    if kind == 'fd' then
        local result, ok = callExport('fd_banking', 'RemoveMoney', Bridge.GetIdentifier(src), amount, reason)
        if ok then return result ~= false end
        return nil
    end

    if kind == 'snipe' then
        local result, ok = callExport('snipe-banking', 'RemoveMoney', src, amount, reason)
        if ok then return result ~= false end
        return nil
    end

    return nil
end

function Banking.Add(src, amount, reason)
    if not IsDuplicityVersion() then return nil end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    local kind = Banking.GetType()
    if kind == 'framework' or kind == 'none' then return nil end
    reason = reason or 'foodtruck'

    if kind == 'custom' then
        local c = Config.CustomBanking or {}
        if c.addMoney and c.addMoney ~= '' then
            local result, ok = callExport(c.resource, c.addMoney, src, amount, reason)
            if ok then return result ~= false end
        end
        if c.addEvent and c.addEvent ~= '' then
            TriggerEvent(c.addEvent, src, amount, reason)
            return true
        end
        return nil
    end

    if kind == 'qb-banking' then
        local _, ok = callExport('qb-banking', 'AddMoney', Bridge.GetIdentifier(src), amount, reason)
        if ok then return true end
        _, ok = callExport('qb-banking', 'AddAccountMoney', Bridge.GetIdentifier(src), amount)
        if ok then return true end
        return nil
    end

    if kind == 'renewed' then
        local res = started('Renewed-Banking') and 'Renewed-Banking' or 'renewed-banking'
        local result, ok = callExport(res, 'addAccountMoney', Bridge.GetIdentifier(src), amount)
        if ok then return result ~= false end
        return nil
    end

    if kind == 'okok' then
        local _, ok = callExport('okokBanking', 'AddMoney', Bridge.GetIdentifier(src), amount)
        if ok then return true end
        TriggerEvent('okokBanking:AddMoney', src, amount)
        return true
    end

    if kind == 'wasabi' then
        local result, ok = callExport('wasabi_banking', 'AddMoney', src, amount, reason)
        if ok then return result ~= false end
        return nil
    end

    if kind == 'fd' then
        local result, ok = callExport('fd_banking', 'AddMoney', Bridge.GetIdentifier(src), amount, reason)
        if ok then return result ~= false end
        return nil
    end

    if kind == 'snipe' then
        local result, ok = callExport('snipe-banking', 'AddMoney', src, amount, reason)
        if ok then return result ~= false end
        return nil
    end

    return nil
end
