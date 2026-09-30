-- ==========================================================================
--  Haki do integracji z innymi skryptami serwera – edytuj pod siebie
-- ==========================================================================
Hooks = {}

-- powiadomienia (domyślnie własne toasty NUI; możesz podpiąć ox_lib / okokNotify itd.)
function Hooks.Notify(msg, kind, time)
    SendNUIMessage({ action = 'toast', text = msg, kind = kind or 'info', time = time or 5000 })
end

-- paliwo (hamownia/test silnika nie powinny „zjadać” paliwa – możesz tu podpiąć swój system)
function Hooks.GetFuel(vehicle)
    if GetResourceState('ox_fuel') == 'started' then
        return Entity(vehicle).state.fuel or GetVehicleFuelLevel(vehicle)
    elseif GetResourceState('LegacyFuel') == 'started' then
        return exports.LegacyFuel:GetFuel(vehicle)
    end
    return GetVehicleFuelLevel(vehicle)
end

-- czy gracz może używać menu (np. blokada w trakcie kajdanek / śmierci – podepnij swój framework)
function Hooks.CanInteract()
    local ped = PlayerPedId()
    if IsEntityDead(ped) or IsPedCuffed(ped) or IsPedRagdoll(ped) then return false end
    return true
end

-- wywoływane po zakończeniu montażu – np. zapis do własnego garażu po stronie klienta
function Hooks.OnVehicleModified(vehicle, props) end

-- HUD serwera – chowanie/pokazywanie własnego HUD-a przy otwieraniu menu
function Hooks.ToggleHud(visible)
    -- przykład: TriggerEvent('hud:toggle', visible)
end
