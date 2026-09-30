-- ==========================================================================
--  Haki klienta – podmień powiadomienia, blipy alarmów itd. pod swój serwer
-- ==========================================================================
Hooks = {}

-- powiadomienia (domyślnie toasty NUI; możesz podpiąć ox_lib / okokNotify)
function Hooks.Notify(msg, kind, time)
    SendNUIMessage({ action = 'toast', text = msg, kind = kind or 'info', time = time or 4500 })
end

-- alarm dla służb (payload = { id, name, group, reason, coords, seconds })
function Hooks.Alarm(payload)
    local c = payload.coords
    local blip = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(blip, 161)
    SetBlipScale(blip, 1.1)
    SetBlipColour(blip, 1)
    SetBlipFlashes(blip, true)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(L('alarm_blip', payload.name))
    EndTextCommandSetBlipName(blip)
    PlaySoundFrontend(-1, 'Beep_Red', 'DLC_HEIST_HACKING_SNAKE_SOUNDS', true)
    Hooks.Notify(L('alarm_toast', payload.name, payload.group ~= '' and payload.group or '—'), 'alarm', 8000)
    SetTimeout(payload.seconds * 1000, function() RemoveBlip(blip) end)
end

-- czy gracz może teraz wchodzić w interakcje (np. nie jest skuty / martwy)
function Hooks.CanInteract()
    local ped = PlayerPedId()
    return not IsEntityDead(ped) and not IsPedCuffed(ped) and not IsPauseMenuActive()
end
