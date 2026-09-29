-- ==========================================================================
--  dp-spawacz – rdzeń klienta: callbacki, narzędzia, stan
-- ==========================================================================
Spawacz = {
    busy = false,        -- trwa minigra / tablet
    contract = nil,      -- aktywne zlecenie (widok z serwera)
    usingTarget = false,
}
local S = Spawacz

local cbId, cbPending = 0, {}

function S.Callback(name, ...)
    cbId = cbId + 1
    local id = cbId
    local p = promise.new()
    cbPending[id] = p
    TriggerServerEvent('dp-spawacz:server:cb', name, id, ...)
    SetTimeout(15000, function()
        if cbPending[id] then
            cbPending[id] = nil
            p:resolve(nil)
        end
    end)
    return Citizen.Await(p)
end

RegisterNetEvent('dp-spawacz:client:cb', function(id, res)
    local p = cbPending[id]
    if p then
        cbPending[id] = nil
        p:resolve(res)
    end
end)

function S.Notify(msg, kind, time)
    Hooks.Notify(msg, kind, time)
end
RegisterNetEvent('dp-spawacz:client:notify', function(msg, kind) S.Notify(msg, kind) end)

function S.Help(text)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, false, -1)
end

function S.LoadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) do
        if GetGameTimer() > timeout then return nil end
        Wait(10)
    end
    return hash
end

function S.LoadDict(dict)
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 5000
    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() > timeout then return false end
        Wait(10)
    end
    return true
end

-- dociąga Z do gruntu (config nie musi mieć idealnych wysokości)
function S.GroundZ(v)
    local found, z = GetGroundZFor_3dCoord(v.x, v.y, v.z + 3.0, false)
    if found and math.abs(z - v.z) < 6.0 then return z end
    return v.z
end

-- wybór systemu interakcji po starcie zasobów
CreateThread(function()
    Wait(1000)
    if Config.UseTarget then
        if GetResourceState('ox_target') == 'started' then S.usingTarget = 'ox'
        elseif GetResourceState('qb-target') == 'started' then S.usingTarget = 'qb' end
    end
end)

if Config.Debug then
    RegisterCommand('spawacz_pos', function()
        local ped = PlayerPedId()
        local c = GetEntityCoords(ped)
        local out = ('vec4(%.2f, %.2f, %.2f, %.1f)'):format(c.x, c.y, c.z, GetEntityHeading(ped))
        print(out)
        S.Notify(out, 'info', 10000)
    end, false)
end
