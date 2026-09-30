-- ==========================================================================
--  dp-doorlock – rdzeń klienta: callbacki, NUI, animacje, narzędzia
-- ==========================================================================
DL = {
    focus = nil,       -- id drzwi, przy których gracz stoi (interakcja)
    busy = false,      -- trwa minigra / panel / akcja czasowa
    admin = false,
}

local cbId, cbPending = 0, {}

function DL.Callback(name, ...)
    cbId = cbId + 1
    local id = cbId
    local p = promise.new()
    cbPending[id] = p
    TriggerServerEvent('dp-doorlock:server:cb', name, id, ...)
    SetTimeout(15000, function()
        if cbPending[id] then
            cbPending[id] = nil
            p:resolve(nil)
        end
    end)
    return Citizen.Await(p)
end

RegisterNetEvent('dp-doorlock:client:cb', function(id, res)
    local p = cbPending[id]
    if p then
        cbPending[id] = nil
        p:resolve(res)
    end
end)

function DL.Notify(msg, kind, time) Hooks.Notify(msg, kind, time) end
RegisterNetEvent('dp-doorlock:client:notify', function(msg, kind) DL.Notify(msg, kind) end)

--- Komunikat wyniku z serwera (jeśli jest)
function DL.Result(res, okKind)
    if not res then return DL.Notify(L('error'), 'error') end
    if res.msg then DL.Notify(res.msg, res.ok and not res.failed and (okKind or 'success') or 'error') end
end

-- --------------------------------------------------------------------------
--  Fokus NUI
-- --------------------------------------------------------------------------
local nuiOpen = 0
function DL.Focus(on)
    nuiOpen = math.max(0, nuiOpen + (on and 1 or -1))
    SetNuiFocus(nuiOpen > 0, nuiOpen > 0)
    SetNuiFocusKeepInput(false)
end

function DL.ResetFocus()
    nuiOpen = 0
    SetNuiFocus(false, false)
end

-- --------------------------------------------------------------------------
--  Zasoby i animacje
-- --------------------------------------------------------------------------
function DL.LoadDict(dict)
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 3000
    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() > timeout then return false end
        Wait(0)
    end
    return true
end

function DL.LoadPtfx(asset)
    if HasNamedPtfxAssetLoaded(asset) then return true end
    RequestNamedPtfxAsset(asset)
    local timeout = GetGameTimer() + 3000
    while not HasNamedPtfxAssetLoaded(asset) do
        if GetGameTimer() > timeout then return false end
        Wait(0)
    end
    return true
end

--- Odtwarza animację z Config.Anims. Zwraca funkcję zatrzymującą.
function DL.Anim(name)
    local a = Config.Anims[name]
    local ped = PlayerPedId()
    if not a then return function() end end
    if a.scenario then
        TaskStartScenarioInPlace(ped, a.scenario, 0, true)
        return function() ClearPedTasks(ped) end
    end
    if not DL.LoadDict(a.dict) then return function() end end
    TaskPlayAnim(ped, a.dict, a.clip, 4.0, -4.0, a.time or -1, a.flag or 0, 0.0, false, false, false)
    RemoveAnimDict(a.dict)
    return function() StopAnimTask(ped, a.dict, a.clip, 2.0) end
end

--- Obraca gracza twarzą do punktu (krótko, bez blokowania)
function DL.Face(pos)
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return end
    local p = GetEntityCoords(ped)
    local heading = GetHeadingFromVector_2d(pos.x - p.x, pos.y - p.y)
    if math.abs(((GetEntityHeading(ped) - heading + 180) % 360) - 180) > 25 then
        TaskTurnPedToFaceCoord(ped, pos.x, pos.y, pos.z, 450)
        Wait(450)
    end
end

-- --------------------------------------------------------------------------
--  Start NUI
-- --------------------------------------------------------------------------
CreateThread(function()
    SendNUIMessage({
        action = 'init', theme = Config.UI.theme, sounds = Config.UI.sounds, volume = Config.UI.volume,
        showNames = Config.UI.showNames, keys = Config.Keys,
        keypad = { min = Config.Keypad.minLength, max = Config.Keypad.maxLength },
    })
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    DL.ResetFocus()
end)
