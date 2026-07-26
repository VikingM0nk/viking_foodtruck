--[[
    Built-in lib compatibility layer.
    ox_lib is optional — this resource provides its own callbacks/UI when ox_lib is missing or broken.
]]

FTLib = FTLib or { usingOx = false }

if type(lib) ~= 'table' then
    lib = {}
end
lib.callback = lib.callback or {}

local FALLBACK_CB_REQ = 'viking_foodtruck:fb:cb:req'
local FALLBACK_CB_RES = 'viking_foodtruck:fb:cb:res'

local function hasOxCallbacks()
    return type(lib) == 'table'
        and type(lib.callback) == 'table'
        and type(lib.callback.register) == 'function'
        and type(lib.callback.await) == 'function'
        and GetResourceState('ox_lib') == 'started'
end

if IsDuplicityVersion() then
    -- Server callbacks
    if not hasOxCallbacks() then
        local registered = {}

        function lib.callback.register(name, cb)
            registered[name] = cb
        end

        RegisterNetEvent(FALLBACK_CB_REQ, function(name, replyId, ...)
            local src = source
            local handler = registered[name]
            if not handler then
                TriggerClientEvent(FALLBACK_CB_RES, src, replyId, {})
                return
            end
            local ok, a, b, c, d, e = pcall(handler, src, ...)
            if not ok then
                print(('[viking_foodtruck] callback error %s: %s'):format(tostring(name), tostring(a)))
                TriggerClientEvent(FALLBACK_CB_RES, src, replyId, {})
                return
            end
            TriggerClientEvent(FALLBACK_CB_RES, src, replyId, { a, b, c, d, e })
        end)

        print('[viking_foodtruck] Using built-in server callbacks (ox_lib not required).')
    else
        FTLib.usingOx = true
    end
else
    -- Client callback await
    if not hasOxCallbacks() then
        local pending = {}
        local seq = 0

        RegisterNetEvent(FALLBACK_CB_RES, function(replyId, payload)
            local p = pending[replyId]
            if not p then return end
            pending[replyId] = nil
            p:resolve(payload or {})
        end)

        function lib.callback.await(name, _delay, ...)
            seq = seq + 1
            local replyId = seq
            local p = promise.new()
            pending[replyId] = p
            TriggerServerEvent(FALLBACK_CB_REQ, name, replyId, ...)
            local results = Citizen.Await(p)
            return results[1], results[2], results[3], results[4], results[5]
        end
    else
        FTLib.usingOx = true
    end
end
