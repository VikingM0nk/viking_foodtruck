--[[
    Target bridge — ox_target, qb-target, qtarget, interact, or custom.
    Falls back to false (caller should keep E/text UI prompts).
]]

Target = Target or {}

local detected
local entityZones = {} -- [entity] = { ids... }
local shopZones = {}   -- [truckId] = zoneId/name

local function started(name)
    return type(name) == 'string' and name ~= '' and GetResourceState(name) == 'started'
end

local function detect()
    local mode = Config.Target or 'auto'
    if mode ~= 'auto' then return mode end
    local c = Config.CustomTarget or {}
    if c.resource and started(c.resource) then return 'custom' end
    if started('ox_target') then return 'ox' end
    if started('qb-target') then return 'qb' end
    if started('qtarget') then return 'qtarget' end
    if started('interact') then return 'interact' end
    return 'none'
end

function Target.GetType()
    if not detected then detected = detect() end
    return detected
end

function Target.IsActive()
    return Target.GetType() ~= 'none'
end

local function normalizeOptions(options)
    local out = {}
    for i = 1, #(options or {}) do
        local o = options[i]
        out[#out + 1] = {
            name = o.name or ('ft_opt_' .. i),
            label = o.label or o.title or 'Option',
            icon = o.icon or 'fas fa-hamburger',
            distance = o.distance or Config.InteractDistance or 2.5,
            canInteract = o.canInteract,
            onSelect = o.onSelect,
            action = o.onSelect, -- qb-target
            event = o.event,
            type = o.type or 'client',
        }
    end
    return out
end

--- Add options to a local/networked entity
function Target.AddEntity(entity, options)
    if not IsDuplicityVersion() then
        -- client only
    else
        return
    end
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end
    if not Target.IsActive() then return end

    local opts = normalizeOptions(options)
    local kind = Target.GetType()
    entityZones[entity] = entityZones[entity] or {}

    if kind == 'ox' then
        local oxOpts = {}
        for i = 1, #opts do
            local o = opts[i]
            oxOpts[#oxOpts + 1] = {
                name = o.name,
                label = o.label,
                icon = o.icon,
                distance = o.distance,
                canInteract = o.canInteract,
                onSelect = o.onSelect,
            }
        end
        exports.ox_target:addLocalEntity(entity, oxOpts)
        entityZones[entity] = { system = 'ox' }
    elseif kind == 'qb' or kind == 'qtarget' then
        local res = kind == 'qb' and 'qb-target' or 'qtarget'
        local qbOpts = {}
        for i = 1, #opts do
            local o = opts[i]
            qbOpts[#qbOpts + 1] = {
                icon = o.icon,
                label = o.label,
                canInteract = o.canInteract,
                action = function(ent)
                    if o.onSelect then o.onSelect({ entity = ent }) end
                end,
            }
        end
        exports[res]:AddTargetEntity(entity, {
            options = qbOpts,
            distance = opts[1] and opts[1].distance or 2.5,
        })
        entityZones[entity] = { system = kind }
    elseif kind == 'interact' then
        for i = 1, #opts do
            local o = opts[i]
            exports.interact:AddLocalEntityInteraction({
                entity = entity,
                name = o.name,
                id = o.name,
                distance = o.distance,
                interactDst = o.distance,
                options = {
                    {
                        label = o.label,
                        action = function()
                            if o.onSelect then o.onSelect() end
                        end,
                    },
                },
            })
        end
        entityZones[entity] = { system = 'interact' }
    elseif kind == 'custom' then
        local c = Config.CustomTarget or {}
        if c.addEntityExport and c.resource and started(c.resource) then
            pcall(function()
                exports[c.resource][c.addEntityExport](exports[c.resource], entity, opts)
            end)
            entityZones[entity] = { system = 'custom' }
        end
    end
end

function Target.RemoveEntity(entity)
    if IsDuplicityVersion() or not entity then return end
    local meta = entityZones[entity]
    if not meta then return end
    local kind = Target.GetType()
    if kind == 'ox' then
        pcall(function() exports.ox_target:removeLocalEntity(entity) end)
    elseif kind == 'qb' then
        pcall(function() exports['qb-target']:RemoveTargetEntity(entity) end)
    elseif kind == 'qtarget' then
        pcall(function() exports.qtarget:RemoveTargetEntity(entity) end)
    elseif kind == 'interact' then
        pcall(function() exports.interact:RemoveLocalEntityInteraction(entity) end)
    elseif kind == 'custom' then
        local c = Config.CustomTarget or {}
        if c.removeEntityExport and c.resource and started(c.resource) then
            pcall(function()
                exports[c.resource][c.removeEntityExport](exports[c.resource], entity)
            end)
        end
    end
    entityZones[entity] = nil
end

--- Sphere/box zone for an open shop location
function Target.AddShopZone(truckId, coords, options)
    if IsDuplicityVersion() then return end
    if not Target.IsActive() or not coords then return end
    Target.RemoveShopZone(truckId)

    local opts = normalizeOptions(options)
    local kind = Target.GetType()
    local name = ('viking_foodtruck_shop_%s'):format(truckId)
    local dist = (opts[1] and opts[1].distance) or Config.InteractDistance or 2.5

    if kind == 'ox' then
        local id = exports.ox_target:addSphereZone({
            coords = vector3(coords.x, coords.y, coords.z),
            radius = dist,
            debug = Config.DebugTarget or false,
            options = (function()
                local oxOpts = {}
                for i = 1, #opts do
                    local o = opts[i]
                    oxOpts[#oxOpts + 1] = {
                        name = o.name,
                        label = o.label,
                        icon = o.icon,
                        distance = o.distance,
                        canInteract = o.canInteract,
                        onSelect = o.onSelect,
                    }
                end
                return oxOpts
            end)(),
        })
        shopZones[truckId] = { system = 'ox', id = id, name = name }
    elseif kind == 'qb' or kind == 'qtarget' then
        local res = kind == 'qb' and 'qb-target' or 'qtarget'
        local qbOpts = {}
        for i = 1, #opts do
            local o = opts[i]
            qbOpts[#qbOpts + 1] = {
                icon = o.icon,
                label = o.label,
                canInteract = o.canInteract,
                action = function()
                    if o.onSelect then o.onSelect() end
                end,
            }
        end
        exports[res]:AddCircleZone(name, vector3(coords.x, coords.y, coords.z), dist, {
            name = name,
            debugPoly = Config.DebugTarget or false,
            useZ = true,
        }, {
            options = qbOpts,
            distance = dist,
        })
        shopZones[truckId] = { system = kind, name = name }
    elseif kind == 'custom' then
        local c = Config.CustomTarget or {}
        if c.addZoneExport and c.resource and started(c.resource) then
            pcall(function()
                exports[c.resource][c.addZoneExport](exports[c.resource], truckId, coords, opts)
            end)
            shopZones[truckId] = { system = 'custom', name = name }
        end
    end
end

function Target.RemoveShopZone(truckId)
    if IsDuplicityVersion() then return end
    local meta = shopZones[truckId]
    if not meta then return end
    if meta.system == 'ox' and meta.id then
        pcall(function() exports.ox_target:removeZone(meta.id) end)
    elseif meta.system == 'qb' and meta.name then
        pcall(function() exports['qb-target']:RemoveZone(meta.name) end)
    elseif meta.system == 'qtarget' and meta.name then
        pcall(function() exports.qtarget:RemoveZone(meta.name) end)
    elseif meta.system == 'custom' then
        local c = Config.CustomTarget or {}
        if c.removeZoneExport and c.resource and started(c.resource) then
            pcall(function()
                exports[c.resource][c.removeZoneExport](exports[c.resource], truckId)
            end)
        end
    end
    shopZones[truckId] = nil
end

function Target.ClearAll()
    if IsDuplicityVersion() then return end
    for entity in pairs(entityZones) do
        Target.RemoveEntity(entity)
    end
    for truckId in pairs(shopZones) do
        Target.RemoveShopZone(truckId)
    end
end
