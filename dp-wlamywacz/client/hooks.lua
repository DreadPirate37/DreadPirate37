-- ==========================================================================
--  Haki do integracji z innymi skryptami serwera – edytuj pod siebie
-- ==========================================================================
Hooks = {}

-- powiadomienia: domyślnie własne toasty NUI; możesz podpiąć ox_lib / okokNotify itd.
function Hooks.Notify(msg, kind, time)
    SendNUIMessage({ action = 'toast', text = msg, kind = kind or 'info', time = time or 5000 })
end

-- dispatch po stronie klienta (POL-01). mode wybiera serwer: ps | cd | core | qs
function Hooks.Dispatch(mode, d)
    local c = d.coords
    if mode == 'ps' then
        exports['ps-dispatch']:CustomAlert({
            coords = vector3(c.x, c.y, c.z), message = d.title, dispatchCode = d.code, description = d.message,
            radius = 0, sprite = 40, color = 1, scale = 1.0, length = 3,
        })
    elseif mode == 'cd' then
        TriggerServerEvent('cd_dispatch:AddNotification', {
            job_table = Config.Police.jobs, coords = vector3(c.x, c.y, c.z), title = d.code .. ' – ' .. d.title,
            message = d.message, flash = 0, unique_id = tostring(math.random(0, 9999999)), sound = 1,
            blip = { sprite = 40, scale = 1.2, colour = 1, flashes = false, text = d.title, time = 5, radius = 0 },
        })
    elseif mode == 'core' then
        exports['core_dispatch']:addCall(d.code, d.title, { { icon = 'fa-house', info = d.message } }, { c.x, c.y, c.z }, 'police', 3000, 40, 1)
    elseif mode == 'qs' then
        TriggerServerEvent('qs-dispatch:server:CreateDispatchCall', {
            job = Config.Police.jobs, callLocation = vector3(c.x, c.y, c.z),
            callCode = { code = d.code, snippet = d.title }, message = d.message, flashes = false, image = nil,
            blip = { sprite = 40, scale = 1.2, colour = 1, flashes = true, text = d.title, time = 5 * 60 * 1000 },
        })
    end
end

RegisterNetEvent('dp-wlamywacz:client:dispatch', function(mode, d)
    local ok, err = pcall(Hooks.Dispatch, mode, d)
    if not ok then print('^1[dp-wlamywacz] dispatch ' .. tostring(mode) .. ': ' .. tostring(err) .. '^7') end
end)

-- wbudowany dispatch: powiadomienie i migający blip na 90 s
RegisterNetEvent('dp-wlamywacz:client:policeAlert', function(d)
    W.Notify(('%s %s: %s'):format(d.code, d.title, d.message), 'bad', 9000)
    PlaySoundFrontend(-1, 'Lose_1st', 'GTAO_FM_Events_Soundset', false)
    local b = AddBlipForCoord(d.coords.x, d.coords.y, d.coords.z)
    SetBlipSprite(b, 40)
    SetBlipColour(b, 1)
    SetBlipScale(b, 1.1)
    SetBlipFlashes(b, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(d.title)
    EndTextCommandSetBlipName(b)
    SetTimeout(90000, function() if DoesBlipExist(b) then RemoveBlip(b) end end)
end)

-- klasa pojazdu dla pojemności bagażnika (LOG-01)
function Hooks.VehicleClass(veh) return GetVehicleClass(veh) end

-- czy postać ma rękawiczki z ubrania (NAR-14): drawable komponentu 3 z listy w configu
function Hooks.WearsGloves(ped)
    local d = GetPedDrawableVariation(ped, 3)
    local list = IsPedMale(ped) and Config.GloveDrawables.male or Config.GloveDrawables.female
    for _, v in ipairs(list) do if v == d then return true end end
    return false
end

-- czy postać ma maskę (NAR-15): komponent 1 różny od 0
function Hooks.WearsMask(ped) return GetPedDrawableVariation(ped, 1) ~= 0 end
