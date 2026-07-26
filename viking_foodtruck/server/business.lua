Business = {}

local openShops = {} -- [truckId] = { netId = number|nil, coords = vector3, ownerSrc = number }
local pendingOrders = {} -- [orderId] = order
local orderSeq = 0

local function deepCopy(tbl)
    if type(tbl) ~= 'table' then return tbl end
    local copy = {}
    for k, v in pairs(tbl) do
        copy[k] = deepCopy(v)
    end
    return copy
end

function Business.GetOpenShops()
    return openShops
end

function Business.IsStaff(truck, account, identifier)
    if not truck or not identifier then return false end
    if truck.owner_id and truck.owner_id == identifier then return true end
    local employees = account and account.employees or {}
    for i = 1, #employees do
        if employees[i] == identifier then return true end
    end
    return false
end

function Business.SetShopOpen(truckId, isOpen, src, netId, coords)
    local truck = Trucks.Get(truckId)
    if isOpen then
        openShops[truckId] = {
            netId = netId,
            coords = coords,
            ownerSrc = src,
            openedAt = os.time(),
        }
        if Restaurant and Restaurant.OnShopOpen then
            Restaurant.OnShopOpen({
                truckId = truckId,
                label = truck and truck.label or truckId,
                ownerId = truck and truck.owner_id,
                coords = coords,
                netId = netId,
                source = src,
            })
        end
    else
        openShops[truckId] = nil
        if Restaurant and Restaurant.OnShopClose then
            Restaurant.OnShopClose({
                truckId = truckId,
                label = truck and truck.label or truckId,
                ownerId = truck and truck.owner_id,
                source = src,
            })
        end
    end
    TriggerClientEvent('viking_foodtruck:client:shopState', -1, truckId, openShops[truckId])
end

function Business.GetShop(truckId)
    return openShops[truckId]
end

local function stockHas(stock, item, count)
    return (tonumber(stock[item]) or 0) >= count
end

local function stockTake(stock, item, count)
    stock[item] = (tonumber(stock[item]) or 0) - count
    if stock[item] <= 0 then stock[item] = nil end
end

local function stockAdd(stock, item, count, maxStock)
    local nextCount = (tonumber(stock[item]) or 0) + count
    if maxStock and nextCount > maxStock then
        nextCount = maxStock
    end
    stock[item] = nextCount
end

function Business.CanFulfill(src, truck, account, menuItem)
    local cookFrom = Config.CookFrom or 'either'
    local ingredients = menuItem.ingredients or {}
    local fromStock = true
    local fromInv = Inv.GetType() ~= 'none'
    local hasIngredients = #ingredients > 0

    for i = 1, #ingredients do
        local ing = ingredients[i]
        local need = tonumber(ing.count) or 1
        if not stockHas(account.stock, ing.item, need) then
            fromStock = false
        end
        if fromInv and Inv.GetCount(src, ing.item) < need then
            fromInv = false
        end
    end

    -- No ingredients configured: allow fulfill from "stock" path
    if not hasIngredients then
        return true, 'stock'
    end

    if cookFrom == 'stock' then return fromStock, 'stock' end
    if cookFrom == 'inventory' then return fromInv, 'inventory' end
    if fromStock then return true, 'stock' end
    if fromInv then return true, 'inventory' end
    return false, nil
end

function Business.ConsumeIngredients(src, account, menuItem, sourceKind)
    local ingredients = menuItem.ingredients or {}
    if sourceKind == 'stock' then
        for i = 1, #ingredients do
            local ing = ingredients[i]
            stockTake(account.stock, ing.item, tonumber(ing.count) or 1)
        end
        return true
    end
    for i = 1, #ingredients do
        local ing = ingredients[i]
        if not Inv.RemoveItem(src, ing.item, tonumber(ing.count) or 1) then
            return false
        end
    end
    return true
end

--- Craft a menu item using truck stock (and/or inventory).
--- destination: inventory | stock | both  (overrides Config.CraftOutput)
function Business.CraftFood(src, truckId, itemIndex, amount, destination)
    amount = math.floor(tonumber(amount) or 1)
    if amount < 1 then amount = 1 end
    if amount > 10 then amount = 10 end

    local truck = Trucks.Get(truckId)
    if not truck then return false, 'Truck missing' end
    local account = DB.GetAccount(truckId)
    if not Business.IsStaff(truck, account, Bridge.GetIdentifier(src)) then
        return false, Config.Locale.not_owner
    end

    local menu = truck.data and truck.data.menu or {}
    local menuItem = menu[itemIndex]
    if not menuItem then return false, 'Invalid menu item' end

    local craftTo = destination or Config.CraftOutput or 'ask'
    if craftTo == 'ask' or craftTo == '' then
        craftTo = 'inventory'
    end
    if craftTo ~= 'inventory' and craftTo ~= 'stock' and craftTo ~= 'both' then
        craftTo = 'inventory'
    end

    local crafted = 0
    for _ = 1, amount do
        local can, sourceKind = Business.CanFulfill(src, truck, account, menuItem)
        if not can then
            DB.SaveAccount(account)
            if crafted > 0 then
                return true, { account = account, crafted = crafted, destination = craftTo, partial = true }
            end
            return false, Config.Locale.no_stock
        end
        if not Business.ConsumeIngredients(src, account, menuItem, sourceKind) then
            DB.SaveAccount(account)
            return false, Config.Locale.no_stock
        end

        -- Give to player inventory first so a failed give never leaves orphan truck stock
        if craftTo == 'inventory' or craftTo == 'both' then
            if not Food.Give(src, menuItem) then
                if sourceKind == 'stock' then
                    for _, ing in ipairs(menuItem.ingredients or {}) do
                        stockAdd(account.stock, ing.item, tonumber(ing.count) or 1, truck.data and truck.data.maxStock)
                    end
                end
                DB.SaveAccount(account)
                return false, 'Failed to add food to your inventory (is the item registered?)'
            end
            if Consumables and Consumables.OnGiven then
                Consumables.OnGiven(src, menuItem)
            end
        end

        if craftTo == 'stock' or craftTo == 'both' then
            local maxStock = (truck.data and truck.data.maxStock) or Config.MaxStockPerItem
            stockAdd(account.stock, menuItem.item, 1, maxStock)
        end
        crafted = crafted + 1
    end

    DB.SaveAccount(account)
    return true, { account = account, crafted = crafted, destination = craftTo }
end

function Business.WithdrawStock(src, truckId, item, count)
    count = math.floor(tonumber(count) or 0)
    if count <= 0 or not item then return false, 'Invalid' end
    local truck = Trucks.Get(truckId)
    if not truck then return false, 'Truck missing' end
    local account = DB.GetAccount(truckId)
    if not Business.IsStaff(truck, account, Bridge.GetIdentifier(src)) then
        return false, Config.Locale.not_owner
    end
    if not stockHas(account.stock, item, count) then
        return false, Config.Locale.no_stock
    end
    if Inv.GetType() ~= 'none' and not Inv.CanCarry(src, item, count) then
        return false, 'Cannot carry that many'
    end

    local menuItem
    local menu = truck.data and truck.data.menu or {}
    for i = 1, #menu do
        if menu[i].item == item then
            menuItem = menu[i]
            break
        end
    end

    stockTake(account.stock, item, count)
    local given = false
    if menuItem then
        for _ = 1, count do
            if Food.Give(src, menuItem) then
                given = true
            else
                stockAdd(account.stock, item, 1, truck.data and truck.data.maxStock)
                break
            end
        end
    else
        given = Inv.AddItem(src, item, count)
        if not given then
            stockAdd(account.stock, item, count, truck.data and truck.data.maxStock)
        end
    end

    if not given then
        DB.SaveAccount(account)
        return false, 'Failed to give items'
    end
    DB.SaveAccount(account)
    return true, account
end

function Business.GetShopMenu(truckId)
    local truck = Trucks.Get(truckId)
    if not truck or not truck.enabled then return nil end
    if not openShops[truckId] then return nil end
    local account = DB.GetAccount(truckId)
    local menu = truck.data and truck.data.menu or {}
    local items = {}
    for i = 1, #menu do
        local m = menu[i]
        items[#items + 1] = {
            index = i,
            item = m.item,
            label = m.label or m.item,
            price = math.floor(tonumber(m.price) or 0),
            category = m.category,
            prepared = tonumber(account.stock and account.stock[m.item]) or 0,
            description = m.description,
        }
    end
    return {
        id = truck.id,
        label = truck.label,
        menu = items,
    }
end

function Business.BuildStockView(truckId)
    local truck = Trucks.Get(truckId)
    if not truck then return nil end
    local account = DB.GetAccount(truckId)
    local menu = truck.data and truck.data.menu or {}
    local preparedNames = {}
    local prepared = {}
    for i = 1, #menu do
        local m = menu[i]
        if m.item then
            preparedNames[m.item] = m.label or m.item
            local count = tonumber(account.stock and account.stock[m.item]) or 0
            if count > 0 then
                prepared[#prepared + 1] = {
                    item = m.item,
                    label = m.label or m.item,
                    count = count,
                    kind = 'prepared',
                }
            end
        end
    end
    local ingredients = {}
    for item, count in pairs(account.stock or {}) do
        count = tonumber(count) or 0
        if count > 0 and not preparedNames[item] then
            ingredients[#ingredients + 1] = {
                item = item,
                label = item,
                count = count,
                kind = 'ingredient',
            }
        end
    end
    table.sort(prepared, function(a, b) return a.label < b.label end)
    table.sort(ingredients, function(a, b) return a.label < b.label end)
    return {
        truckId = truckId,
        title = truck.label .. ' — Stock',
        prepared = prepared,
        ingredients = ingredients,
    }
end

local function resolvePaymentMethod(requested)
    local mode = Config.BillingMode or 'choice'
    local allowBill = Config.AllowCustomerBilling ~= false and Billing and Billing.GetType() ~= 'none'
    if mode == 'instant' then return 'instant' end
    if mode == 'bill' then
        return allowBill and 'bill' or 'instant'
    end
    -- choice
    if requested == 'bill' and allowBill then return 'bill' end
    return 'instant'
end

--- Customer buys a prepared (already crafted) menu item from truck stock.
function Business.BuyPrepared(customerSrc, truckId, itemIndex, paymentMethod)
    local truck = Trucks.Get(truckId)
    if not truck or not truck.enabled then
        return false, 'Truck unavailable'
    end
    local shop = openShops[truckId]
    if not shop then
        return false, 'Shop is closed'
    end

    local identifier = Bridge.GetIdentifier(customerSrc)
    local isOwnTruck = truck.owner_id == identifier
    if isOwnTruck and Config.AllowOwnerCustomerPurchases == false then
        return false, 'You cannot order from your own food truck'
    end

    local menu = truck.data and truck.data.menu or {}
    local menuItem = menu[itemIndex]
    if not menuItem then
        return false, 'Invalid menu item'
    end

    local account = DB.GetAccount(truckId)
    if not stockHas(account.stock, menuItem.item, 1) then
        return false, 'That item is not ready — place a cook order instead'
    end

    local price = math.floor(tonumber(menuItem.price) or 0)
    if Restaurant and Restaurant.ResolvePrice then
        price = Restaurant.ResolvePrice(truckId, menuItem, price)
    end
    if price < 0 then return false, 'Invalid price' end

    local paid, accountUsed = Bridge.TryRemoveMoney(customerSrc, price, Config.PurchaseAccount)
    if not paid then
        return false, Config.Locale.not_enough_money
    end

    stockTake(account.stock, menuItem.item, 1)
    if not Food.Give(customerSrc, menuItem) then
        stockAdd(account.stock, menuItem.item, 1, truck.data and truck.data.maxStock)
        Bridge.AddMoney(customerSrc, accountUsed or 'cash', price)
        DB.SaveAccount(account)
        return false, 'Failed to give food item'
    end

    if Consumables and Consumables.OnGiven then
        Consumables.OnGiven(customerSrc, menuItem)
    end

    account.balance = (account.balance or 0) + price
    DB.SaveAccount(account)

    if Restaurant and Restaurant.OnSale then
        Restaurant.OnSale({
            truckId = truckId,
            label = truck.label,
            customerSrc = customerSrc,
            item = menuItem.item,
            price = price,
            menuItem = menuItem,
            prepared = true,
        })
    end

    return true, { item = menuItem.item, price = price }
end

function Business.CreateOrder(customerSrc, truckId, itemIndex, paymentMethod)
    local truck = Trucks.Get(truckId)
    if not truck or not truck.enabled then
        return false, 'Truck unavailable'
    end
    local shop = openShops[truckId]
    if not shop then
        return false, 'Shop is closed'
    end

    -- Owners/employees may always buy from other trucks. Buying from your own
    -- open shop is also allowed when Config.AllowOwnerCustomerPurchases is true.
    local identifier = Bridge.GetIdentifier(customerSrc)
    local isOwnTruck = truck.owner_id == identifier
    if isOwnTruck and Config.AllowOwnerCustomerPurchases == false then
        return false, 'You cannot order from your own food truck'
    end

    local menu = truck.data and truck.data.menu or {}
    local menuItem = menu[itemIndex]
    if not menuItem then
        return false, 'Invalid menu item'
    end

    local price = math.floor(tonumber(menuItem.price) or 0)
    if Restaurant and Restaurant.ResolvePrice then
        price = Restaurant.ResolvePrice(truckId, menuItem, price)
    end
    if price < 0 then return false, 'Invalid price' end

    local method = resolvePaymentMethod(paymentMethod)
    local accountUsed
    local billId

    if method == 'instant' then
        local paid
        paid, accountUsed = Bridge.TryRemoveMoney(customerSrc, price, Config.PurchaseAccount)
        if not paid then
            return false, Config.Locale.not_enough_money
        end
    elseif method == 'bill' and Config.BillOnFulfill == false then
        -- Bill immediately on order (staff source = shop owner if available)
        local sender = shop.ownerSrc or customerSrc
        local ok, result = Billing.Create(sender, customerSrc, price, ('%s — %s'):format(truck.label, menuItem.label or menuItem.item), {
            truckId = truckId,
            society = 'foodtruck',
            label = truck.label,
            orderEarly = true,
        })
        if not ok then
            return false, type(result) == 'string' and result or 'Failed to create bill'
        end
        billId = result
    end

    orderSeq = orderSeq + 1
    local orderId = ('%s_%s_%s'):format(truckId, orderSeq, os.time())
    local order = {
        id = orderId,
        truckId = truckId,
        itemIndex = itemIndex,
        menuItem = deepCopy(menuItem),
        price = price,
        customer = customerSrc,
        customerName = Bridge.GetName(customerSrc),
        status = 'pending',
        createdAt = GetGameTimer(),
        paidFrom = accountUsed,
        paymentMethod = method,
        billId = billId,
        billed = method == 'bill' and Config.BillOnFulfill == false,
    }
    pendingOrders[orderId] = order

    SetTimeout(Config.OrderTimeoutMs or 120000, function()
        local o = pendingOrders[orderId]
        if o and o.status == 'pending' then
            if o.paymentMethod == 'instant' then
                Bridge.AddMoney(o.customer, o.paidFrom or 'cash', o.price)
                if GetPlayerName(o.customer) then
                    Bridge.Notify(o.customer, 'Order timed out — refunded', 'error')
                end
            elseif o.billId and Billing.UsesBuiltin and Billing.UsesBuiltin() then
                Billing.CancelBuiltin(o.billId)
            end
            pendingOrders[orderId] = nil
            TriggerClientEvent('viking_foodtruck:client:orderUpdate', -1, truckId, orderId, 'expired')
        end
    end)

    local ped = GetPlayerPed(customerSrc)
    local coords = GetEntityCoords(ped)
    for _, playerId in ipairs(GetPlayers()) do
        local sid = tonumber(playerId)
        local identifier = Bridge.GetIdentifier(sid)
        local account = DB.GetAccount(truckId)
        if Business.IsStaff(truck, account, identifier) then
            local staffPed = GetPlayerPed(sid)
            if staffPed and staffPed ~= 0 then
                local dist = #(GetEntityCoords(staffPed) - coords)
                if dist <= (Config.StaffNotifyDistance or 25.0) then
                    Bridge.Notify(sid, ('New order: %s x1 ($%s)'):format(menuItem.label or menuItem.item, price), 'inform')
                    TriggerClientEvent('viking_foodtruck:client:newOrder', sid, order)
                end
            end
        end
    end

    return true, order
end

function Business.FulfillOrder(staffSrc, orderId)
    local order = pendingOrders[orderId]
    if not order or order.status ~= 'pending' then
        return false, 'Order not found'
    end

    local truck = Trucks.Get(order.truckId)
    if not truck then return false, 'Truck missing' end
    local account = DB.GetAccount(order.truckId)
    local identifier = Bridge.GetIdentifier(staffSrc)
    if not Business.IsStaff(truck, account, identifier) then
        return false, Config.Locale.not_owner
    end

    local shop = openShops[order.truckId]
    if not shop then return false, 'Shop is closed' end

    local staffPed = GetPlayerPed(staffSrc)
    if not staffPed or staffPed == 0 then return false, 'Invalid staff' end
    local staffCoords = GetEntityCoords(staffPed)
    if shop.coords and #(staffCoords - shop.coords) > ((truck.data and truck.data.shopRadius) or Config.InteractDistance or 3.0) + 8.0 then
        return false, 'Too far from truck'
    end

    local can, sourceKind = Business.CanFulfill(staffSrc, truck, account, order.menuItem)
    if not can then
        return false, Config.Locale.no_stock
    end

    if not Business.ConsumeIngredients(staffSrc, account, order.menuItem, sourceKind) then
        return false, Config.Locale.no_stock
    end

    local customer = order.customer
    if not GetPlayerName(customer) then
        account.balance = (account.balance or 0) + order.price
        DB.SaveAccount(account)
        pendingOrders[orderId] = nil
        return true, account
    end

    local given = Food.Give(customer, order.menuItem)
    if not given then
        if sourceKind == 'stock' then
            for _, ing in ipairs(order.menuItem.ingredients or {}) do
                stockAdd(account.stock, ing.item, tonumber(ing.count) or 1, truck.data and truck.data.maxStock)
            end
            DB.SaveAccount(account)
        end
        return false, 'Failed to give food item'
    end

    if Consumables and Consumables.OnGiven then
        Consumables.OnGiven(customer, order.menuItem)
    end

    local foodCfg = Config.CustomFood or {}
    if foodCfg.applyNeedsOnGive and Food.ApplyNeeds then
        Food.ApplyNeeds(customer, order.menuItem)
    end

    -- Instant pay already collected → credit business now.
    -- Bill pay: send invoice (external or builtin); builtin credits balance when paid.
    if order.paymentMethod == 'instant' then
        account.balance = (account.balance or 0) + order.price
        DB.SaveAccount(account)
    elseif order.paymentMethod == 'bill' and not order.billed then
        local ok, result = Billing.Create(staffSrc, customer, order.price, ('%s — %s'):format(truck.label, order.menuItem.label or order.menuItem.item), {
            truckId = order.truckId,
            society = 'foodtruck',
            label = truck.label,
            orderId = order.id,
        })
        if not ok then
            -- Keep sale in business balance as fallback if billing fails after food given
            account.balance = (account.balance or 0) + order.price
            DB.SaveAccount(account)
            Bridge.Notify(staffSrc, 'Billing failed — charged to business balance instead', 'error')
        else
            order.billId = result
            order.billed = true
            -- External billing scripts usually pay the sender; credit truck only for builtin later
            if Billing.GetType() ~= 'builtin' then
                -- Optional: still track expected revenue without double-adding cash
                TriggerEvent('viking_foodtruck:billing:awaitingExternal', order.truckId, order.price, result)
            end
            Bridge.Notify(customer, Config.Locale.bill_sent or 'Invoice sent', 'inform')
        end
    end

    order.status = 'done'
    pendingOrders[orderId] = nil

    if Restaurant and Restaurant.OnSale then
        Restaurant.OnSale({
            truckId = order.truckId,
            label = truck.label,
            staffSrc = staffSrc,
            customerSrc = customer,
            item = order.menuItem.item,
            itemLabel = order.menuItem.label,
            price = order.price,
            menuItem = order.menuItem,
            paymentMethod = order.paymentMethod,
            billId = order.billId,
        })
    end

    Bridge.Notify(customer, Config.Locale.order_ready, 'success')
    TriggerClientEvent('viking_foodtruck:client:orderUpdate', -1, order.truckId, orderId, 'done')
    return true, account
end

function Business.CancelOrder(src, orderId, asStaff)
    local order = pendingOrders[orderId]
    if not order or order.status ~= 'pending' then
        return false, 'Order not found'
    end
    if not asStaff and order.customer ~= src then
        return false, 'Not your order'
    end
    if asStaff then
        local truck = Trucks.Get(order.truckId)
        local account = DB.GetAccount(order.truckId)
        if not Business.IsStaff(truck, account, Bridge.GetIdentifier(src)) then
            return false, Config.Locale.not_owner
        end
    end
    if order.paymentMethod == 'instant' then
        Bridge.AddMoney(order.customer, order.paidFrom or 'cash', order.price)
    elseif order.billId and Billing.UsesBuiltin and Billing.UsesBuiltin() then
        Billing.CancelBuiltin(order.billId)
    end
    pendingOrders[orderId] = nil
    TriggerClientEvent('viking_foodtruck:client:orderUpdate', -1, order.truckId, orderId, 'cancelled')
    return true
end

function Business.GetPendingForTruck(truckId)
    local list = {}
    for _, order in pairs(pendingOrders) do
        if order.truckId == truckId and order.status == 'pending' then
            list[#list + 1] = order
        end
    end
    return list
end

function Business.DepositStock(src, truckId, item, count)
    count = math.floor(tonumber(count) or 0)
    if count <= 0 or not item then return false, 'Invalid' end
    local truck = Trucks.Get(truckId)
    if not truck then return false, 'Truck missing' end
    local account = DB.GetAccount(truckId)
    if not Business.IsStaff(truck, account, Bridge.GetIdentifier(src)) then
        return false, Config.Locale.not_owner
    end
    if Inv.GetType() == 'none' then
        return false, 'Inventory bridge is none — edit stock in creator or buy stock packs'
    end
    if Inv.GetCount(src, item) < count then
        return false, 'Not enough items'
    end
    if not Inv.RemoveItem(src, item, count) then
        return false, 'Failed to remove items'
    end
    local maxStock = (truck.data and truck.data.maxStock) or Config.MaxStockPerItem
    stockAdd(account.stock, item, count, maxStock)
    DB.SaveAccount(account)
    return true, account
end

function Business.WithdrawBalance(src, truckId, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'Invalid amount' end
    local truck = Trucks.Get(truckId)
    if not truck then return false, 'Truck missing' end
    if truck.owner_id ~= Bridge.GetIdentifier(src) then
        return false, Config.Locale.not_owner
    end
    local account = DB.GetAccount(truckId)
    if (account.balance or 0) < amount then
        return false, 'Insufficient business balance'
    end
    account.balance = account.balance - amount
    DB.SaveAccount(account)
    Bridge.AddMoney(src, Config.PurchaseAccount or 'bank', amount)
    return true, account
end

function Business.DepositBalance(src, truckId, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'Invalid amount' end
    local truck = Trucks.Get(truckId)
    if not truck then return false, 'Truck missing' end
    if truck.owner_id ~= Bridge.GetIdentifier(src) then
        return false, Config.Locale.not_owner
    end
    local ok = Bridge.TryRemoveMoney(src, amount, Config.PurchaseAccount)
    if not ok then
        return false, Config.Locale.not_enough_money
    end
    local account = DB.GetAccount(truckId)
    account.balance = (account.balance or 0) + amount
    DB.SaveAccount(account)
    return true, account
end

function Business.Hire(src, truckId, targetSrc)
    local truck = Trucks.Get(truckId)
    if not truck or truck.owner_id ~= Bridge.GetIdentifier(src) then
        return false, Config.Locale.not_owner
    end
    targetSrc = tonumber(targetSrc)
    if not targetSrc or not GetPlayerName(targetSrc) then
        return false, 'Player not found'
    end
    local targetId = Bridge.GetIdentifier(targetSrc)
    local account = DB.GetAccount(truckId)
    for i = 1, #account.employees do
        if account.employees[i] == targetId then
            return false, 'Already hired'
        end
    end
    account.employees[#account.employees + 1] = targetId
    DB.SaveAccount(account)

    local jobCfg = Config.Job
    if jobCfg and jobCfg.enabled ~= false then
        local jobName = (truck.data and truck.data.job) or jobCfg.name or 'foodtruck'
        Bridge.SetJob(targetSrc, jobName, jobCfg.employeeGrade or 0)
    end

    Bridge.Notify(targetSrc, ('You were hired at %s'):format(truck.label), 'success')
    return true, account
end

function Business.Fire(src, truckId, targetIdentifier)
    local truck = Trucks.Get(truckId)
    if not truck or truck.owner_id ~= Bridge.GetIdentifier(src) then
        return false, Config.Locale.not_owner
    end
    local account = DB.GetAccount(truckId)
    local nextEmployees = {}
    for i = 1, #account.employees do
        if account.employees[i] ~= targetIdentifier then
            nextEmployees[#nextEmployees + 1] = account.employees[i]
        end
    end
    account.employees = nextEmployees
    DB.SaveAccount(account)

    local jobCfg = Config.Job
    if jobCfg and jobCfg.enabled ~= false and jobCfg.removeOnFire ~= false then
        local jobName = (truck.data and truck.data.job) or jobCfg.name or 'foodtruck'
        for _, playerId in ipairs(GetPlayers()) do
            local sid = tonumber(playerId)
            if Bridge.GetIdentifier(sid) == targetIdentifier then
                local current = Bridge.GetJob(sid)
                if current == jobName then
                    Bridge.ClearJob(sid)
                end
                Bridge.Notify(sid, 'You were fired from the food truck', 'error')
                break
            end
        end
    end

    return true, account
end

exports('IsTruckOpen', function(truckId)
    return openShops[truckId] ~= nil
end)

exports('GetOwnedTruck', function(src)
    local identifier = Bridge.GetIdentifier(src)
    for _, truck in pairs(Trucks.All()) do
        if truck.owner_id == identifier then
            return truck
        end
    end
    return nil
end)
