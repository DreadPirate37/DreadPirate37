-- ==========================================================================
--  Haki do integracji z innymi skryptami serwera – edytuj pod siebie
-- ==========================================================================
Hooks = {}

-- klucze do pojazdu służbowego
function Hooks.GiveKeys(vehicle, plate)
    if GetResourceState('qbx_vehiclekeys') == 'started' then
        TriggerEvent('vehiclekeys:client:SetOwner', plate)
    elseif GetResourceState('qb-vehiclekeys') == 'started' then
        TriggerEvent('vehiclekeys:client:SetOwner', plate)
    elseif GetResourceState('wasabi_carlock') == 'started' then
        exports.wasabi_carlock:GiveKey(plate)
    end
end

-- paliwo
function Hooks.SetFuel(vehicle, value)
    if GetResourceState('ox_fuel') == 'started' then
        Entity(vehicle).state.fuel = value
    elseif GetResourceState('LegacyFuel') == 'started' then
        exports.LegacyFuel:SetFuel(vehicle, value)
    elseif GetResourceState('cdn-fuel') == 'started' then
        exports['cdn-fuel']:SetFuel(vehicle, value)
    else
        SetVehicleFuelLevel(vehicle, value)
    end
end

-- powiadomienia (domyślnie własne toasty NUI; możesz podpiąć ox_lib / okokNotify itd.)
function Hooks.Notify(msg, kind, time)
    SendNUIMessage({ action = 'toast', text = msg, kind = kind or 'info', time = time or 5000 })
end
