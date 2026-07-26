Bridge = Bridge or {}

local detected

local function resourceStarted(name)
    return GetResourceState(name) == 'started'
end

local function detectFramework()
    if Config and Config.Framework and Config.Framework ~= 'auto' then
        return Config.Framework
    end
    if resourceStarted('qbx_core') then return 'qbox' end
    if resourceStarted('qb-core') then return 'qb' end
    if resourceStarted('es_extended') then return 'esx' end
    return 'standalone'
end

function Bridge.GetType()
    if not detected then
        detected = detectFramework()
    end
    return detected
end

local function getQBCore()
    if Bridge.GetType() == 'qbox' then
        if exports['qb-core'] and exports['qb-core'].GetCoreObject then
            return exports['qb-core']:GetCoreObject()
        end
        return exports['qbx_core']:GetCoreObject()
    end
    return exports['qb-core']:GetCoreObject()
end

local function getESX()
    return exports['es_extended']:getSharedObject()
end

local function getLicense(src)
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:sub(1, 8) == 'license:' then
            return id
        end
    end
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:sub(1, 6) == 'fivem:' then
            return id
        end
    end
    return ('src:%s'):format(src)
end

function Bridge.GetPlayer(src)
    local fw = Bridge.GetType()
    if fw == 'qb' or fw == 'qbox' then
        local ok, player = pcall(function()
            return getQBCore().Functions.GetPlayer(src)
        end)
        return ok and player or nil
    elseif fw == 'esx' then
        local ok, player = pcall(function()
            return getESX().GetPlayerFromId(src)
        end)
        return ok and player or nil
    end
    if GetPlayerName(src) then
        return { source = src }
    end
    return nil
end

function Bridge.GetIdentifier(src)
    local fw = Bridge.GetType()
    if fw == 'qb' or fw == 'qbox' then
        local player = Bridge.GetPlayer(src)
        if player and player.PlayerData and player.PlayerData.citizenid then
            return player.PlayerData.citizenid
        end
    elseif fw == 'esx' then
        local player = Bridge.GetPlayer(src)
        if player and player.identifier then
            return player.identifier
        end
    end
    return getLicense(src)
end

function Bridge.GetName(src)
    local fw = Bridge.GetType()
    if fw == 'qb' or fw == 'qbox' then
        local player = Bridge.GetPlayer(src)
        if player and player.PlayerData and player.PlayerData.charinfo then
            local c = player.PlayerData.charinfo
            return (('%s %s'):format(c.firstname or '', c.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
        end
    elseif fw == 'esx' then
        local player = Bridge.GetPlayer(src)
        if player and player.getName then
            return player.getName()
        end
    end
    return GetPlayerName(src) or ('Player %s'):format(src)
end

function Bridge.GetJob(src)
    local fw = Bridge.GetType()
    if fw == 'qb' or fw == 'qbox' then
        local player = Bridge.GetPlayer(src)
        if player and player.PlayerData and player.PlayerData.job then
            local grade = player.PlayerData.job.grade
            local level = 0
            if type(grade) == 'table' then
                level = grade.level or 0
            else
                level = grade or 0
            end
            return player.PlayerData.job.name, level
        end
    elseif fw == 'esx' then
        local player = Bridge.GetPlayer(src)
        if player and player.job then
            return player.job.name, player.job.grade or 0
        end
    end
    return nil, 0
end

function Bridge.SetJob(src, jobName, grade)
    if not IsDuplicityVersion() then return false end
    if not jobName or jobName == '' then return false end
    grade = math.floor(tonumber(grade) or 0)

    local custom = Config and Config.Job and Config.Job.setJobExport
    if custom and custom.resource and custom.resource ~= '' and custom.export and custom.export ~= '' then
        if resourceStarted(custom.resource) then
            local ok, result = pcall(function()
                return exports[custom.resource][custom.export](exports[custom.resource], src, jobName, grade)
            end)
            if ok then return result ~= false end
        end
    end

    local fw = Bridge.GetType()
    if fw == 'qb' or fw == 'qbox' then
        local player = Bridge.GetPlayer(src)
        if not player then return false end
        local ok = pcall(function()
            player.Functions.SetJob(jobName, grade)
        end)
        return ok
    elseif fw == 'esx' then
        local player = Bridge.GetPlayer(src)
        if not player then return false end
        local ok = pcall(function()
            player.setJob(jobName, grade)
        end)
        return ok
    end

    if type(MySQL) == 'table' then
        local ownerId = Bridge.GetIdentifier(src)
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS viking_foodtruck_jobs (
                owner_id VARCHAR(64) NOT NULL,
                job VARCHAR(64) NOT NULL,
                grade INT NOT NULL DEFAULT 0,
                PRIMARY KEY (owner_id)
            )
        ]])
        MySQL.query.await([[
            INSERT INTO viking_foodtruck_jobs (owner_id, job, grade)
            VALUES (?, ?, ?)
            ON DUPLICATE KEY UPDATE job = VALUES(job), grade = VALUES(grade)
        ]], { ownerId, jobName, grade })
    end
    TriggerEvent('viking_foodtruck:jobAssigned', src, jobName, grade)
    return true
end

function Bridge.ClearJob(src)
    local cfg = (Config and Config.Job) or {}
    local offJob = cfg.offJob or 'unemployed'
    local offGrade = cfg.offGrade or 0
    return Bridge.SetJob(src, offJob, offGrade)
end

function Bridge.EnsureFoodTruckJob()
    if not IsDuplicityVersion() then return end
    local cfg = Config and Config.Job
    if not cfg or cfg.enabled == false or not cfg.autoRegister then return end
    local jobName = cfg.name or 'foodtruck'
    local label = cfg.label or 'Food Truck'
    local fw = Bridge.GetType()

    if fw == 'qb' or fw == 'qbox' then
        local ok, core = pcall(getQBCore)
        if not ok or not core then return end
        local jobs = core.Shared and core.Shared.Jobs
        if jobs and jobs[jobName] then return end
        local jobData = {
            label = label,
            defaultDuty = true,
            offDutyPay = false,
            grades = {
                ['0'] = { name = 'Employee', payment = 50 },
                ['1'] = { name = 'Owner', payment = 100, isboss = true },
            },
        }
        pcall(function()
            if core.Functions and core.Functions.AddJob then
                core.Functions.AddJob(jobName, jobData)
            elseif resourceStarted('qb-core') then
                exports['qb-core']:AddJob(jobName, jobData)
            elseif resourceStarted('qbx_core') then
                exports['qbx_core']:CreateJob(jobName, jobData)
            end
        end)
        if core.Shared and core.Shared.Jobs and not core.Shared.Jobs[jobName] then
            core.Shared.Jobs[jobName] = jobData
        end
        print(('[viking_foodtruck] Registered QB job "%s"'):format(jobName))
    elseif fw == 'esx' then
        if type(MySQL) ~= 'table' then return end
        local ok, exists = pcall(function()
            return MySQL.scalar.await('SELECT COUNT(*) FROM jobs WHERE name = ?', { jobName })
        end)
        if not ok then return end
        if not exists or tonumber(exists) == 0 then
            pcall(function()
                MySQL.insert.await('INSERT INTO jobs (name, label) VALUES (?, ?)', { jobName, label })
                MySQL.insert.await(
                    "INSERT INTO job_grades (job_name, grade, name, label, salary, skin_male, skin_female) VALUES (?, 0, ?, ?, 50, '{}', '{}')",
                    { jobName, 'employee', 'Employee' }
                )
                MySQL.insert.await(
                    "INSERT INTO job_grades (job_name, grade, name, label, salary, skin_male, skin_female) VALUES (?, 1, ?, ?, 100, '{}', '{}')",
                    { jobName, 'owner', 'Owner' }
                )
            end)
            print(('[viking_foodtruck] Registered ESX job "%s"'):format(jobName))
            pcall(function()
                local ESX = getESX()
                if ESX and ESX.RefreshJobs then ESX.RefreshJobs() end
            end)
        end
    end
end

function Bridge.IsAdmin(src)
    if IsPlayerAceAllowed(src, (Config and Config.AdminAce) or 'foodtruck.admin') then
        return true
    end
    local fw = Bridge.GetType()
    local groups = (Config and Config.AdminGroups) or {}
    if fw == 'qb' or fw == 'qbox' then
        local player = Bridge.GetPlayer(src)
        if not player then return false end
        local perms = player.PlayerData and player.PlayerData.permission
        if type(perms) == 'string' then
            for _, g in ipairs(groups) do
                if perms == g then return true end
            end
        end
        local ok, core = pcall(getQBCore)
        if ok and core and core.Functions and core.Functions.HasPermission then
            for _, g in ipairs(groups) do
                if core.Functions.HasPermission(src, g) then return true end
            end
        end
        return IsPlayerAceAllowed(src, 'command') or IsPlayerAceAllowed(src, 'admin')
    elseif fw == 'esx' then
        local player = Bridge.GetPlayer(src)
        if not player then return false end
        local group = player.getGroup and player.getGroup() or player.group
        for _, g in ipairs(groups) do
            if group == g then return true end
        end
    end
    return false
end

local function customMoneyConfigured()
    local c = Config and Config.CustomMoney
    return c and c.resource and c.resource ~= '' and resourceStarted(c.resource)
end

local function ensureWallet(ownerId)
    if not IsDuplicityVersion() or not ownerId or type(MySQL) ~= 'table' then return end
    MySQL.insert.await([[
        INSERT IGNORE INTO viking_foodtruck_wallets (owner_id, cash, bank)
        VALUES (?, 0, 0)
    ]], { ownerId })
end

local function getStandaloneMoney(src, account)
    if not IsDuplicityVersion() or type(MySQL) ~= 'table' then return 0 end
    local ownerId = Bridge.GetIdentifier(src)
    ensureWallet(ownerId)
    local row = MySQL.single.await('SELECT cash, bank FROM viking_foodtruck_wallets WHERE owner_id = ?', { ownerId })
    if not row then return 0 end
    if account == 'bank' then return row.bank or 0 end
    return row.cash or 0
end

local function setStandaloneMoney(src, account, amount)
    if not IsDuplicityVersion() or type(MySQL) ~= 'table' then return end
    local ownerId = Bridge.GetIdentifier(src)
    ensureWallet(ownerId)
    amount = math.max(0, math.floor(amount))
    if account == 'bank' then
        MySQL.update.await('UPDATE viking_foodtruck_wallets SET bank = ? WHERE owner_id = ?', { amount, ownerId })
    else
        MySQL.update.await('UPDATE viking_foodtruck_wallets SET cash = ? WHERE owner_id = ?', { amount, ownerId })
    end
end

function Bridge.GetMoney(src, account)
    account = account or 'cash'

    if account == 'bank' and Banking and Banking.GetBalance then
        local bankBal = Banking.GetBalance(src)
        if type(bankBal) == 'number' then return bankBal end
    end

    if customMoneyConfigured() then
        local c = Config.CustomMoney
        local ok, value = pcall(function()
            return exports[c.resource][c.getMoney](exports[c.resource], src, account)
        end)
        if ok and type(value) == 'number' then return value end
    end

    local fw = Bridge.GetType()
    if fw == 'qb' or fw == 'qbox' then
        local player = Bridge.GetPlayer(src)
        if not player then return 0 end
        return player.Functions.GetMoney(account) or 0
    elseif fw == 'esx' then
        local player = Bridge.GetPlayer(src)
        if not player then return 0 end
        if account == 'bank' then
            return player.getAccount('bank').money
        end
        return player.getMoney()
    end
    return getStandaloneMoney(src, account)
end

function Bridge.RemoveMoney(src, account, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    account = account or 'cash'

    if account == 'bank' and Banking and Banking.Remove then
        local handled = Banking.Remove(src, amount, 'foodtruck')
        if handled ~= nil then return handled end
    end

    if customMoneyConfigured() then
        local c = Config.CustomMoney
        local ok, value = pcall(function()
            return exports[c.resource][c.removeMoney](exports[c.resource], src, account, amount)
        end)
        if ok then return value ~= false end
    end

    local fw = Bridge.GetType()
    if fw == 'qb' or fw == 'qbox' then
        local player = Bridge.GetPlayer(src)
        if not player then return false end
        if (player.Functions.GetMoney(account) or 0) < amount then return false end
        player.Functions.RemoveMoney(account, amount, 'foodtruck')
        return true
    elseif fw == 'esx' then
        local player = Bridge.GetPlayer(src)
        if not player then return false end
        if account == 'bank' then
            if player.getAccount('bank').money < amount then return false end
            player.removeAccountMoney('bank', amount)
            return true
        end
        if player.getMoney() < amount then return false end
        player.removeMoney(amount)
        return true
    end

    local current = getStandaloneMoney(src, account)
    if current < amount then return false end
    setStandaloneMoney(src, account, current - amount)
    return true
end

function Bridge.AddMoney(src, account, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    account = account or 'cash'

    if account == 'bank' and Banking and Banking.Add then
        local handled = Banking.Add(src, amount, 'foodtruck')
        if handled ~= nil then return handled end
    end

    if customMoneyConfigured() then
        local c = Config.CustomMoney
        local ok, value = pcall(function()
            return exports[c.resource][c.addMoney](exports[c.resource], src, account, amount)
        end)
        if ok then return value ~= false end
    end

    local fw = Bridge.GetType()
    if fw == 'qb' or fw == 'qbox' then
        local player = Bridge.GetPlayer(src)
        if not player then return false end
        player.Functions.AddMoney(account, amount, 'foodtruck')
        return true
    elseif fw == 'esx' then
        local player = Bridge.GetPlayer(src)
        if not player then return false end
        if account == 'bank' then
            player.addAccountMoney('bank', amount)
        else
            player.addMoney(amount)
        end
        return true
    end

    local current = getStandaloneMoney(src, account)
    setStandaloneMoney(src, account, current + amount)
    return true
end

function Bridge.TryRemoveMoney(src, amount, preferred)
    preferred = preferred or (Config and Config.PurchaseAccount) or 'bank'
    local other = preferred == 'bank' and 'cash' or 'bank'
    if Bridge.GetMoney(src, preferred) >= amount and Bridge.RemoveMoney(src, preferred, amount) then
        return true, preferred
    end
    if Bridge.GetMoney(src, other) >= amount and Bridge.RemoveMoney(src, other, amount) then
        return true, other
    end
    return false, nil
end

function Bridge.Notify(src, message, nType)
    nType = nType or 'inform'
    TriggerClientEvent('viking_foodtruck:client:notify', src, message, nType)
end

if not IsDuplicityVersion() then
    function Bridge.NotifyLocal(message, nType)
        if lib and lib.notify then
            lib.notify({ description = message, type = nType or 'inform' })
        else
            BeginTextCommandThefeedPost('STRING')
            AddTextComponentSubstringPlayerName(message or '')
            EndTextCommandThefeedPostTicker(false, true)
        end
    end

    RegisterNetEvent('viking_foodtruck:client:notify', function(message, nType)
        Bridge.NotifyLocal(message, nType)
    end)
end
