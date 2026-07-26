Inv = Inv or {}

local detected

local function resourceStarted(name)
    return type(name) == 'string' and name ~= '' and GetResourceState(name) == 'started'
end

local function detectInventory()
    if Config.Inventory and Config.Inventory ~= 'auto' then
        return Config.Inventory
    end
    if resourceStarted('ox_inventory') then return 'ox' end
    if resourceStarted('qs-inventory') then return 'qs' end
    if resourceStarted('ps-inventory') then return 'ps' end
    if resourceStarted('lj-inventory') then return 'lj' end
    if resourceStarted('core_inventory') then return 'core' end
    if resourceStarted('origen_inventory') then return 'origen' end
    if resourceStarted('qb-inventory') then return 'qb' end
    -- qb-core player inventory API without a separate inventory resource name
    if resourceStarted('qb-core') or resourceStarted('qbx_core') then return 'qb' end
    return 'none'
end

function Inv.GetType()
    if not detected then
        detected = detectInventory()
        if IsDuplicityVersion() then
            print(('[viking_foodtruck] inventory bridge: %s'):format(detected))
        end
    end
    return detected
end

local function tryExport(resource, exportName, ...)
    if not resourceStarted(resource) then return false, nil end
    local args = { ... }
    local exp = exports[resource]
    -- FiveM's runtime `exports('Name', fn)` API wraps every export as
    -- function(self, ...) and DISCARDS `self`, forwarding only the `...`.
    -- That means the call must use colon-call semantics (an explicit leading
    -- "self" arg that gets thrown away) or the first real argument (usually
    -- the player source) gets silently dropped and every later arg shifts
    -- left by one — e.g. turning qb-inventory's RemoveItem(identifier, item,
    -- amount) into RemoveItem(item, amount) with `item` receiving a number.
    local ok, result = pcall(function()
        return exp[exportName](exp, table.unpack(args))
    end)
    if ok then return true, result end
    -- Fallback for legacy manifest-style exports (plain global function, no
    -- implicit self parameter) which some older/custom resources still use.
    ok, result = pcall(function()
        return exp[exportName](table.unpack(args))
    end)
    return ok, result
end

local function qbPlayerAdd(src, item, count, metadata)
    local player = Bridge.GetPlayer(src)
    if not player or not player.Functions or not player.Functions.AddItem then
        return false
    end
    local ok, result = pcall(function()
        return player.Functions.AddItem(item, count, false, metadata or {})
    end)
    if ok and result ~= false then
        TriggerClientEvent('inventory:client:ItemBox', src, { name = item, amount = count }, 'add')
        TriggerClientEvent('qb-inventory:client:ItemBox', src, { name = item, label = item, amount = count }, 'add')
        return true
    end
    return false
end

local function qbPlayerRemove(src, item, count)
    local player = Bridge.GetPlayer(src)
    if not player or not player.Functions or not player.Functions.RemoveItem then
        return false
    end
    local ok, result = pcall(function()
        return player.Functions.RemoveItem(item, count)
    end)
    return ok and result ~= false
end

function Inv.AddItem(src, item, count, metadata)
    count = math.floor(tonumber(count) or 0)
    if count <= 0 or not item or item == '' then return false end
    item = tostring(item):lower()
    metadata = metadata or {}
    local kind = Inv.GetType()

    if kind == 'none' then
        print(('[viking_foodtruck] Inv.AddItem skipped — inventory bridge is none (item=%s)'):format(item))
        return false
    end

    if kind == 'ox' then
        local ok, result = tryExport('ox_inventory', 'AddItem', src, item, count, metadata)
        if ok and result ~= false and result ~= nil then return true end
        -- Retry without metadata (some items reject unknown meta)
        ok, result = tryExport('ox_inventory', 'AddItem', src, item, count)
        return ok and result ~= false and result ~= nil
    end

    if kind == 'qb' or kind == 'ps' or kind == 'lj' then
        local resources = {
            kind == 'ps' and 'ps-inventory' or nil,
            kind == 'lj' and 'lj-inventory' or nil,
            'qb-inventory',
            'ps-inventory',
            'lj-inventory',
        }
        for i = 1, #resources do
            local res = resources[i]
            if res and resourceStarted(res) then
                -- Common signatures across qb-inventory forks
                local attempts = {
                    function() return exports[res]:AddItem(src, item, count, false, metadata) end,
                    function() return exports[res]:AddItem(src, item, count, nil, metadata) end,
                    function() return exports[res]:AddItem(src, item, count, false, metadata, 'viking_foodtruck') end,
                    function() return exports[res]:AddItem(src, item, count) end,
                }
                for a = 1, #attempts do
                    local ok, result = pcall(attempts[a])
                    if ok and result ~= false and result ~= nil then
                        return true
                    end
                    if ok and result == true then
                        return true
                    end
                end
            end
        end
        if qbPlayerAdd(src, item, count, metadata) then
            return true
        end
        print(('[viking_foodtruck] Inv.AddItem failed for qb player %s item=%s x%s'):format(src, item, count))
        return false
    end

    if kind == 'qs' then
        local ok, result = tryExport('qs-inventory', 'AddItem', src, item, count, false, metadata)
        if ok and result ~= false then return true end
        ok, result = tryExport('qs-inventory', 'AddItem', src, item, count)
        return ok and result ~= false
    end

    if kind == 'core' then
        local ok, result = tryExport('core_inventory', 'addItem', src, item, count, metadata)
        return ok and result ~= false
    end

    if kind == 'origen' then
        local ok, result = tryExport('origen_inventory', 'AddItem', src, item, count, metadata)
        return ok and result ~= false
    end

    if kind == 'custom' then
        local c = Config.CustomInventory
        if not c or not c.resource or not resourceStarted(c.resource) then return false end
        local ok, result = tryExport(c.resource, c.addItem, src, item, count, metadata)
        return ok and result ~= false
    end

    return false
end

function Inv.RemoveItem(src, item, count)
    count = math.floor(tonumber(count) or 0)
    if count <= 0 or not item or item == '' then return false end
    item = tostring(item):lower()
    local kind = Inv.GetType()

    if kind == 'none' then
        return false
    elseif kind == 'ox' then
        local ok, result = tryExport('ox_inventory', 'RemoveItem', src, item, count)
        return ok and result and true or false
    elseif kind == 'qb' or kind == 'ps' or kind == 'lj' then
        for _, res in ipairs({ 'qb-inventory', 'ps-inventory', 'lj-inventory' }) do
            if resourceStarted(res) then
                local ok, result = tryExport(res, 'RemoveItem', src, item, count)
                if ok and result ~= false then return true end
            end
        end
        return qbPlayerRemove(src, item, count)
    elseif kind == 'qs' then
        local ok, result = tryExport('qs-inventory', 'RemoveItem', src, item, count)
        return ok and result ~= false
    elseif kind == 'core' then
        local ok, result = tryExport('core_inventory', 'removeItem', src, item, count)
        return ok and result ~= false
    elseif kind == 'origen' then
        local ok, result = tryExport('origen_inventory', 'RemoveItem', src, item, count)
        return ok and result ~= false
    elseif kind == 'custom' then
        local c = Config.CustomInventory
        if not c or not c.resource or not resourceStarted(c.resource) then return false end
        local ok, result = tryExport(c.resource, c.removeItem, src, item, count)
        return ok and result ~= false
    end
    return false
end

function Inv.GetCount(src, item)
    if not item or item == '' then return 0 end
    item = tostring(item):lower()
    local kind = Inv.GetType()

    if kind == 'none' then
        return 0
    elseif kind == 'ox' then
        local ok, count = tryExport('ox_inventory', 'Search', src, 'count', item)
        if ok then return tonumber(count) or 0 end
        ok, count = tryExport('ox_inventory', 'GetItemCount', src, item)
        return ok and (tonumber(count) or 0) or 0
    elseif kind == 'qb' or kind == 'ps' or kind == 'lj' then
        local player = Bridge.GetPlayer(src)
        if player and player.Functions and player.Functions.GetItemByName then
            local it = player.Functions.GetItemByName(item)
            if it then return tonumber(it.amount or it.count) or 0 end
        end
        for _, res in ipairs({ 'qb-inventory', 'ps-inventory', 'lj-inventory' }) do
            if resourceStarted(res) then
                local ok, result = tryExport(res, 'GetItemCount', src, item)
                if ok then return tonumber(result) or 0 end
            end
        end
        return 0
    elseif kind == 'qs' then
        local ok, result = tryExport('qs-inventory', 'GetItemTotalAmount', src, item)
        return ok and (tonumber(result) or 0) or 0
    elseif kind == 'custom' then
        local c = Config.CustomInventory
        if not c or not c.resource or not resourceStarted(c.resource) then return 0 end
        local ok, result = tryExport(c.resource, c.getCount, src, item)
        return ok and (tonumber(result) or 0) or 0
    end
    return 0
end

function Inv.CanCarry(src, item, count)
    count = math.floor(tonumber(count) or 0)
    if count <= 0 then return true end
    item = tostring(item or ''):lower()
    local kind = Inv.GetType()

    if kind == 'none' then
        return false
    elseif kind == 'ox' then
        local ok, result = tryExport('ox_inventory', 'CanCarryItem', src, item, count)
        if ok then return result and true or false end
        return true
    elseif kind == 'custom' then
        local c = Config.CustomInventory
        if c and c.canCarry and c.resource and resourceStarted(c.resource) then
            local ok, result = tryExport(c.resource, c.canCarry, src, item, count)
            if ok then return result ~= false end
        end
        return true
    end
    return true
end
