DB = {}

local function decodeJson(value, fallback)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' or value == '' then return fallback end
    local ok, decoded = pcall(json.decode, value)
    if ok and type(decoded) == 'table' then return decoded end
    return fallback
end

function DB.EnsureTables()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `viking_foodtrucks` (
            `id` VARCHAR(64) NOT NULL,
            `label` VARCHAR(128) NOT NULL,
            `category` VARCHAR(32) NOT NULL DEFAULT 'custom',
            `enabled` TINYINT(1) NOT NULL DEFAULT 1,
            `price` INT NOT NULL DEFAULT 0,
            `data` LONGTEXT NOT NULL,
            `owner_id` VARCHAR(64) DEFAULT NULL,
            `created_by` VARCHAR(64) DEFAULT NULL,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `viking_foodtruck_accounts` (
            `truck_id` VARCHAR(64) NOT NULL,
            `balance` INT NOT NULL DEFAULT 0,
            `employees` LONGTEXT NOT NULL,
            `stock` LONGTEXT NOT NULL,
            PRIMARY KEY (`truck_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `viking_foodtruck_wallets` (
            `owner_id` VARCHAR(64) NOT NULL,
            `cash` INT NOT NULL DEFAULT 0,
            `bank` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`owner_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `viking_foodtruck_bills` (
            `id` VARCHAR(64) NOT NULL,
            `truck_id` VARCHAR(64) NOT NULL DEFAULT '',
            `from_id` VARCHAR(64) NOT NULL,
            `to_id` VARCHAR(64) NOT NULL,
            `from_src` INT DEFAULT NULL,
            `to_src` INT DEFAULT NULL,
            `amount` INT NOT NULL DEFAULT 0,
            `reason` VARCHAR(128) NOT NULL DEFAULT '',
            `status` VARCHAR(16) NOT NULL DEFAULT 'unpaid',
            `paid_from` VARCHAR(16) DEFAULT NULL,
            `meta` LONGTEXT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `paid_at` TIMESTAMP NULL DEFAULT NULL,
            PRIMARY KEY (`id`),
            KEY `idx_to_status` (`to_id`, `status`),
            KEY `idx_truck_status` (`truck_id`, `status`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
end

function DB.RowToTruck(row)
    if not row then return nil end
    return {
        id = row.id,
        label = row.label,
        category = row.category,
        enabled = row.enabled == true or row.enabled == 1,
        price = tonumber(row.price) or 0,
        data = decodeJson(row.data, {}),
        owner_id = row.owner_id,
        created_by = row.created_by,
        updated_at = row.updated_at,
        description = (decodeJson(row.data, {})).description,
    }
end

function DB.LoadAllTrucks()
    local rows = MySQL.query.await('SELECT * FROM viking_foodtrucks') or {}
    local trucks = {}
    for i = 1, #rows do
        trucks[#trucks + 1] = DB.RowToTruck(rows[i])
    end
    return trucks
end

function DB.GetTruck(id)
    local row = MySQL.single.await('SELECT * FROM viking_foodtrucks WHERE id = ?', { id })
    return DB.RowToTruck(row)
end

function DB.UpsertTruck(truck)
    local data = truck.data or {}
    if truck.description then
        data.description = truck.description
    end
    MySQL.query.await([[
        INSERT INTO viking_foodtrucks (id, label, category, enabled, price, data, owner_id, created_by)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            label = VALUES(label),
            category = VALUES(category),
            enabled = VALUES(enabled),
            price = VALUES(price),
            data = VALUES(data),
            owner_id = VALUES(owner_id),
            created_by = COALESCE(created_by, VALUES(created_by))
    ]], {
        truck.id,
        truck.label,
        truck.category or 'custom',
        truck.enabled and 1 or 0,
        tonumber(truck.price) or 0,
        json.encode(data),
        truck.owner_id,
        truck.created_by,
    })
end

function DB.DeleteTruck(id)
    MySQL.query.await('DELETE FROM viking_foodtruck_accounts WHERE truck_id = ?', { id })
    MySQL.query.await('DELETE FROM viking_foodtrucks WHERE id = ?', { id })
end

function DB.SetOwner(id, ownerId)
    MySQL.update.await('UPDATE viking_foodtrucks SET owner_id = ? WHERE id = ?', { ownerId, id })
end

function DB.EnsureAccount(truckId, startingStock)
    local existing = MySQL.single.await('SELECT truck_id FROM viking_foodtruck_accounts WHERE truck_id = ?', { truckId })
    if existing then return end
    MySQL.insert.await([[
        INSERT INTO viking_foodtruck_accounts (truck_id, balance, employees, stock)
        VALUES (?, 0, ?, ?)
    ]], {
        truckId,
        json.encode({}),
        json.encode(startingStock or {}),
    })
end

function DB.GetAccount(truckId)
    local row = MySQL.single.await('SELECT * FROM viking_foodtruck_accounts WHERE truck_id = ?', { truckId })
    if not row then
        DB.EnsureAccount(truckId, {})
        row = MySQL.single.await('SELECT * FROM viking_foodtruck_accounts WHERE truck_id = ?', { truckId })
    end
    if not row then
        return { truck_id = truckId, balance = 0, employees = {}, stock = {} }
    end
    return {
        truck_id = row.truck_id,
        balance = tonumber(row.balance) or 0,
        employees = decodeJson(row.employees, {}),
        stock = decodeJson(row.stock, {}),
    }
end

function DB.SaveAccount(account)
    MySQL.query.await([[
        INSERT INTO viking_foodtruck_accounts (truck_id, balance, employees, stock)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            balance = VALUES(balance),
            employees = VALUES(employees),
            stock = VALUES(stock)
    ]], {
        account.truck_id,
        tonumber(account.balance) or 0,
        json.encode(account.employees or {}),
        json.encode(account.stock or {}),
    })
end

function DB.CountTrucks()
    local count = MySQL.scalar.await('SELECT COUNT(*) FROM viking_foodtrucks')
    return tonumber(count) or 0
end
