-- ==========================================================================
--  Most do NUI: minigry (UIX-08), pasek postępu, HUD (UIX-01) wysyłany tylko przy zmianie,
--  okna (laptop, paser, dialog, raport)
-- ==========================================================================
local ANIMS = {
    search   = { 'anim@gangops@facility@servers@bodysearch@', 'player_search', 49 },
    low      = { 'amb@prop_human_bum_bin@idle_b', 'idle_d', 1 },
    pry      = { 'veh@break_in@0h@p_m_one@', 'low_force_entry_ds', 1 },
    smash    = { 'veh@break_in@0h@p_m_one@', 'low_force_entry_ds', 0 },
    lockpick = { 'mp_arresting', 'a_uncuff', 49 },
    cutters  = { 'mp_arresting', 'a_uncuff', 49 },
    screw    = { 'mini@repair', 'fixing_a_ped', 1 },
    wire     = { 'mini@repair', 'fixing_a_ped', 1 },
    take     = { 'pickup_object', 'pickup_low', 0 },
    lift     = { 'pickup_object', 'pickup_low', 0 },
    key      = { 'pickup_object', 'pickup_low', 0 },
    safe     = { 'mini@safe_cracking', 'dial_turn_anti_fast', 1 },
    keypad   = { 'anim@heists@keypad@', 'idle_a', 1 },
    climb    = { 'move_climb', 'standclimbup_180', 0 },
    fuse     = { 'mini@repair', 'fixing_a_ped', 1 },
}
W.Anims = ANIMS

function W.PlayAnim(kind)
    local a = ANIMS[kind]
    if not a then return end
    local ped = PlayerPedId()
    if W.LoadDict(a[1]) then TaskPlayAnim(ped, a[1], a[2], 3.0, 3.0, -1, a[3], 0, false, false, false) end
end

function W.StopAnim(kind)
    local a = ANIMS[kind]
    if a then StopAnimTask(PlayerPedId(), a[1], a[2], 2.0) end
end

-- --------------------------------------------------------------------------
--  Minigry: Lua czeka na wynik, cała logika i rysowanie są w przeglądarce (TEC-17)
-- --------------------------------------------------------------------------
local gamePromise

local GAME_ANIM = { lockpick = 'lockpick', rake = 'lockpick', shim = 'cutters', pry = 'pry', glass = 'wire', keypad = 'keypad', safe = 'safe', fuse = 'fuse' }

function W.Game(params)
    if W.busy then return nil end
    W.busy = true
    W.PlayAnim(GAME_ANIM[params.game])
    gamePromise = promise.new()
    SetNuiFocus(true, true)
    params.precision = W.glovePrecision or 0
    params.locale = Config.Locale
    SendNUIMessage({ action = 'game', params = params })
    local res = Citizen.Await(gamePromise)
    SetNuiFocus(false, false)
    W.StopAnim(GAME_ANIM[params.game])
    W.busy = false
    return res or { ok = false }
end

RegisterNUICallback('gameResult', function(data, cb)
    cb({})
    if gamePromise then
        local p = gamePromise
        gamePromise = nil
        p:resolve(data or { ok = false })
    end
end)

-- hałas zgłaszany przez minigrę (grabie, pęknięcie wytrycha) – WYT-15
RegisterNUICallback('gameNoise', function(data, cb)
    cb({})
    if data and data.v then W.EmitNoise(tonumber(data.v) or 0, data.src) end
end)

-- ostrzeżenie w trakcie minigry, gdy domownik jest blisko (WYT-16)
function W.GameWarn(level)
    if gamePromise then SendNUIMessage({ action = 'gameWarn', level = level }) end
end

-- --------------------------------------------------------------------------
--  Pasek postępu z animacją; X przerywa. Zwraca true po ukończeniu.
-- --------------------------------------------------------------------------
function W.Progress(label, time, anim)
    if W.busy then return false end
    W.busy = true
    W.PlayAnim(anim)
    SendNUIMessage({ action = 'progress', label = label, time = time })
    local endAt = GetGameTimer() + math.floor(time * 1000)
    local done = true
    while GetGameTimer() < endAt do
        DisableControlAction(0, 30, true) DisableControlAction(0, 31, true)
        DisableControlAction(0, 21, true) DisableControlAction(0, 22, true)
        DisableControlAction(0, 24, true) DisableControlAction(0, 25, true)
        if IsControlJustPressed(0, 73) or IsEntityDead(PlayerPedId()) then done = false break end
        Wait(0)
    end
    W.StopAnim(anim)
    SendNUIMessage({ action = 'progressEnd', done = done })
    W.busy = false
    return done
end

-- uniwersalne uruchomienie gry z odpowiedzi serwera (progress albo minigra)
function W.RunGame(game)
    if game.game == 'progress' then
        local ok = W.Progress(game.label, game.time, game.anim)
        return { ok = ok, aborted = not ok }
    end
    return W.Game(game)
end

-- --------------------------------------------------------------------------
--  HUD – wysyłany tylko przy zmianie wartości
-- --------------------------------------------------------------------------
local hud = {}
function W.Hud(data)
    local diff, any = {}, false
    for k, v in pairs(data) do
        local old = hud[k]
        local changed = old ~= v
        if type(v) == 'table' and type(old) == 'table' then
            changed = json.encode(v) ~= json.encode(old)
        end
        if changed then diff[k] = v hud[k] = v any = true end
    end
    if any then SendNUIMessage({ action = 'hud', data = diff }) end
end

function W.HudShow(on)
    W.Hud({ show = on and true or false })
end

-- --------------------------------------------------------------------------
--  Okna z fokusem
-- --------------------------------------------------------------------------
local windowCb = {}
function W.OpenWindow(kind, data, handler)
    if W.busy then return end
    W.busy = true
    windowCb[kind] = handler
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', kind = kind, data = data })
end

function W.CloseWindow(kind)
    SendNUIMessage({ action = 'close', kind = kind })
    SetNuiFocus(false, false)
    windowCb[kind] = nil
    W.busy = false
    TriggerEvent('dp-wlamywacz:client:windowClosed', kind)
end

function W.UpdateWindow(kind, data)
    SendNUIMessage({ action = 'update', kind = kind, data = data })
end

RegisterNUICallback('window', function(data, cb)
    local kind = data and data.kind
    if data.action == 'close' then
        W.CloseWindow(kind)
        return cb({ ok = true })
    end
    local h = windowCb[kind]
    if not h then return cb({ ok = false }) end
    CreateThread(function() cb(h(data) or { ok = true }) end)
end)

function W.Report(data) SendNUIMessage({ action = 'report', data = data }) end
RegisterNetEvent('dp-wlamywacz:client:report', function(data) W.Report(data) end)

RegisterNetEvent('dp-wlamywacz:client:mail', function(subject)
    W.Notify(L('mail_new', subject), 'info', 7000)
    SendNUIMessage({ action = 'sound', kind = 'mail' })
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
end)
