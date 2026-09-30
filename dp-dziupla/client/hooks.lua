-- ==========================================================================
--  Haki do integracji z innymi skryptami serwera – edytuj pod siebie
-- ==========================================================================
Hooks = {}

-- klucze do auta (po wytrychu / przebitce)
function Hooks.GiveKeys(vehicle, plate)
    plate = plate or GetVehicleNumberPlateText(vehicle)
    if GetResourceState('qbx_vehiclekeys') == 'started' or GetResourceState('qb-vehiclekeys') == 'started' then
        TriggerEvent('vehiclekeys:client:SetOwner', plate)
    elseif GetResourceState('wasabi_carlock') == 'started' then
        exports.wasabi_carlock:GiveKey(plate)
    elseif GetResourceState('MrNewbVehicleKeys') == 'started' then
        exports.MrNewbVehicleKeys:GiveKeys(vehicle)
    end
end

-- powiadomienia (domyślnie własne toasty NUI; możesz podpiąć ox_lib / okokNotify itd.)
function Hooks.Notify(msg, kind, time)
    SendNUIMessage({ action = 'toast', text = msg, kind = kind or 'info', time = time or 5000 })
end

-- zgłoszenie na policję. kind: 'noise' | 'tracker' | 'alarm' | 'drop' | 'export' | 'dealer'
local Titles = {
    noise   = { code = '10-90', title = 'Hałas z warsztatu – możliwa dziupla', desc = 'Mieszkańcy zgłaszają szlifierki i klucze udarowe o dziwnej porze.' },
    tracker = { code = '10-16', title = 'Sygnał GPS skradzionego auta', desc = 'Nadajnik w skradzionym pojeździe nadaje pozycję.' },
    alarm   = { code = '10-16', title = 'Alarm samochodowy', desc = 'Ktoś próbuje ukraść auto.' },
    drop    = { code = '10-66', title = 'Podejrzana wymiana części', desc = 'Świadek widział przekazywanie części samochodowych.' },
    export  = { code = '10-16', title = 'Podejrzany załadunek w porcie', desc = 'Auto ładowane do kontenera bez dokumentów.' },
    dealer  = { code = '10-16', title = 'Auto z przebitymi numerami', desc = 'Handlarz zgłasza auto z podrobionym VIN.' },
}

function Hooks.Dispatch(kind, coords, data)
    local t = Titles[kind] or Titles.alarm
    data = data or {}
    if GetResourceState('ps-dispatch') == 'started' then
        exports['ps-dispatch']:CustomAlert({
            coords = coords, message = t.title, dispatchCode = t.code, description = t.desc,
            radius = kind == 'noise' and 60.0 or 0, sprite = 225, color = 1, scale = 1.0, length = 3,
            plate = data.plate, vehicle = data.model,
        })
    elseif GetResourceState('cd_dispatch') == 'started' then
        TriggerServerEvent('cd_dispatch:AddNotification', {
            job_table = Config.Police.jobs, coords = coords, title = t.code .. ' - ' .. t.title,
            message = t.desc .. (data.plate and (' Tablice: ' .. data.plate) or ''), flash = 0, unique_id = tostring(math.random(0, 9999999)),
            sound = 1, blip = { sprite = 225, scale = 1.0, colour = 1, flashes = false, text = t.title, time = 5, radius = 0 },
        })
    elseif GetResourceState('qs-dispatch') == 'started' then
        TriggerServerEvent('qs-dispatch:server:CreateDispatchCall', {
            job = Config.Police.jobs, callLocation = coords, callCode = { code = t.code, snippet = t.title },
            message = t.desc, flashes = false, blip = { sprite = 225, scale = 1.0, colour = 1, flashes = true, text = t.title, time = 60000 },
        })
    elseif GetResourceState('core_dispatch') == 'started' then
        TriggerServerEvent('core_dispatch:addCall', t.code, t.title, { { icon = 'fa-car', info = t.desc } }, { coords.x, coords.y, coords.z }, 'police', 5000, 225, 1)
    else
        -- brak skryptu dispatch – podepnij tu własny
        if Config.Debug then print(('[dp-dziupla] dispatch %s @ %s'):format(kind, tostring(coords))) end
    end
end

-- właściwości pojazdu (do zatrzymania auta po przebitce)
function Hooks.GetVehicleProps(vehicle)
    if GetResourceState('ox_lib') == 'started' and lib and lib.getVehicleProperties then
        return lib.getVehicleProperties(vehicle)
    elseif GetResourceState('qb-core') == 'started' then
        return exports['qb-core']:GetCoreObject().Functions.GetVehicleProperties(vehicle)
    elseif GetResourceState('es_extended') == 'started' then
        return exports.es_extended:getSharedObject().Game.GetVehicleProperties(vehicle)
    end
    return { model = GetEntityModel(vehicle), plate = GetVehicleNumberPlateText(vehicle) }
end
