-- ==========================================================================
--  dp-doorlock – interakcje: klawisze, radial, klawiatura, czytniki, minigry,
--  akcje czasowe (termit, taran, naprawa), dźwięki i alarmy
--  Klawisze przez RegisterKeyMapping – żadnych pętli sprawdzających klawisze.
-- ==========================================================================
local Interact = {}

local function canAct()
    return not DL.busy and DL.focus and Hooks.CanInteract()
end

-- --------------------------------------------------------------------------
--  Otwórz / zamknij – ścieżka zależna od rodzaju zabezpieczenia
-- --------------------------------------------------------------------------
local function doToggle(id, data)
    local res = DL.Callback('toggle', id, data)
    if res and res.ok then
        Doors.Fx(id, 'ok')
    else
        Doors.Fx(id, 'deny')
        SendNUIMessage({ action = 'sound', name = 'deny', vol = 0.7 })
    end
    return res
end

local function openPanel(msg)
    DL.busy = true
    DL.Focus(true)
    SendNUIMessage(msg)
end

local function closePanel()
    DL.Focus(false)
    DL.busy = false
end

function Interact.Use(id)
    local door = Doors.Get(id)
    if not door then return end
    local d = door.def
    local target = Doors.Target(id)

    if d.security == 'standard' then
        DL.busy = true
        DL.Face(target)
        DL.Anim('key')
        Wait(350)
        local res = doToggle(id)
        if res and not res.ok and res.msg then DL.Notify(res.msg, 'error', 2500) end
        DL.busy = false
    elseif d.security == 'keypad' then
        DL.Face(target)
        openPanel({ action = 'keypad', id = id, name = d.name, group = d.group, mode = 'use', locked = door.st.l })
    else
        DL.Face(target)
        openPanel({ action = 'reader', id = id, name = d.name, group = d.group, kind = d.security, level = d.cardLevel, locked = door.st.l })
    end
end

-- NUI → klawiatura: { id, pin } | { id, badge = true } | { id, change = '1234' }
RegisterNUICallback('keypad', function(data, cb)
    CreateThread(function()
        local id = tonumber(data.id)
        if data.change then
            cb(DL.Callback('pin_change', id, tostring(data.change)) or { ok = false })
            return
        end
        DL.Anim('key')
        cb(doToggle(id, data.badge and {} or { pin = tostring(data.pin or '') }) or { ok = false })
    end)
end)

-- NUI → czytnik kart / biometria (wynik wraca do animacji w NUI)
RegisterNUICallback('reader', function(data, cb)
    CreateThread(function()
        DL.Anim('key')
        cb(doToggle(tonumber(data.id)) or { ok = false })
    end)
end)

RegisterNUICallback('close', function(_, cb)
    closePanel()
    cb(1)
end)

-- --------------------------------------------------------------------------
--  Menu radialne
-- --------------------------------------------------------------------------
function Interact.Menu(id)
    local door = Doors.Get(id)
    if not door then return end
    DL.busy = true
    local res = DL.Callback('menu', id)
    if not res or not res.ok then
        DL.busy = false
        return DL.Result(res)
    end
    DL.Focus(true)
    SendNUIMessage({
        action = 'radial', id = id, name = door.def.name, group = door.def.group,
        security = door.def.security, st = door.st, options = res.options,
    })
end

local run = {}

RegisterNUICallback('radial', function(data, cb)
    cb(1)
    closePanel()
    local id, opt = tonumber(data.id), data.option
    if not id or not opt or not run[opt] then return end
    CreateThread(function() run[opt](id) end)
end)

run.use = function(id) Interact.Use(id) end

run.knock = function(id)
    DL.busy = true
    DL.Face(Doors.Target(id))
    DL.Anim('knock')
    DL.Callback('knock', id)
    Wait(1200)
    DL.busy = false
end

run.bell = function(id)
    local res = DL.Callback('bell', id)
    if res and res.ok then DL.Notify(L('bell_sent'), 'info', 2500) end
end

run.lockdown = function(id)
    DL.Result(DL.Callback('lockdown', id), 'warn')
end

run.edit = function(id) Admin.Open(id) end

run.keys = function(id)
    local res = DL.Callback('keys_list', id)
    if not res or not res.ok then return DL.Result(res) end
    res.id = id
    openPanel({ action = 'keys', data = res })
end

run.pin = function(id)
    local door = Doors.Get(id)
    openPanel({ action = 'keypad', id = id, name = door.def.name, group = door.def.group, mode = 'change' })
end

-- --------------------------------------------------------------------------
--  Minigry: wytrych i hakowanie
-- --------------------------------------------------------------------------
local game = nil     -- { kind, id, token, stop }

local function startGame(kind, id)
    local res = DL.Callback(kind .. '_start', id)
    if not res or not res.ok then return DL.Result(res) end
    local target = Doors.Target(id)
    DL.Face(target)
    local cam = (kind == 'lockpick' and Config.Lockpick.camera and target) and DL.CloseCam(target) or nil
    game = { kind = kind, id = id, token = res.token, stop = DL.Anim(kind), cam = cam }
    res.token = nil
    openPanel({ action = kind, data = res })
end

run.lockpick = function(id) startGame('lockpick', id) end
run.hack = function(id) startGame('hack', id) end

-- pęknięcie narzędzia w trakcie minigry – sesja trwa dalej
RegisterNUICallback('lpEvent', function(data, cb)
    local g = game
    if not g or g.kind ~= 'lockpick' then return cb({ ok = false }) end
    CreateThread(function()
        cb(DL.Callback('lockpick_event', g.id, g.token, tostring(data.kind)) or { ok = false })
    end)
end)

RegisterNUICallback('gameDone', function(data, cb)
    cb(1)
    closePanel()
    local g = game
    game = nil
    if not g then return end
    g.stop()
    if g.cam then g.cam() end
    CreateThread(function()
        local res = DL.Callback(g.kind .. '_finish', g.id, g.token, data.success == true)
        DL.Result(res)
        if res and res.ok and not res.failed then Doors.Fx(g.id, 'ok') end
    end)
end)

-- --------------------------------------------------------------------------
--  Akcje czasowe: termit, taran, naprawa
--  Pętla kontrolna (co 100 ms) działa tylko w trakcie akcji.
-- --------------------------------------------------------------------------
local timedFx = {
    thermite = function(pos)
        if not DL.LoadPtfx('scr_ornate_heist') then return function() end end
        UseParticleFxAssetNextCall('scr_ornate_heist')
        local fx = StartParticleFxLoopedAtCoord('scr_heist_ornate_thermal_burn', pos.x, pos.y, pos.z, 0.0, 0.0, 0.0, 1.0, false, false, false, false)
        return function() StopParticleFxLooped(fx, false) RemoveNamedPtfxAsset('scr_ornate_heist') end
    end,
}
local timedIcon = { thermite = 'fire', ram = 'ram', repair = 'wrench' }

local function timed(kind, id)
    local res = DL.Callback('timed_start', kind, id)
    if not res or not res.ok then return DL.Result(res) end
    DL.busy = true
    local target = Doors.Target(id)
    DL.Face(target)
    local stop = DL.Anim(kind)
    local stopFx = timedFx[kind] and timedFx[kind](target) or nil
    SendNUIMessage({ action = 'progress', label = L('p_' .. kind), icon = timedIcon[kind], ms = res.seconds * 1000 })
    if kind == 'thermite' then SendNUIMessage({ action = 'sound', name = 'sizzle', vol = 0.6, ms = res.seconds * 1000 }) end

    local ped = PlayerPedId()
    local start, endT = GetEntityCoords(ped), GetGameTimer() + res.seconds * 1000
    local cancelled = false
    while GetGameTimer() < endT do
        Wait(100)
        if IsEntityDead(ped) or #(GetEntityCoords(ped) - start) > 2.5 or IsPedRagdoll(ped) then
            cancelled = true
            break
        end
    end
    if kind ~= 'thermite' and stop then stop() end
    SendNUIMessage({ action = 'progressEnd', ok = not cancelled })

    if cancelled then
        if stopFx then stopFx() end
        if stop then stop() end
        DL.Callback('timed_cancel')
        DL.Notify(L('cancelled'), 'error')
    else
        if kind == 'ram' then SendNUIMessage({ action = 'sound', name = 'slam', vol = 1.0 }) end
        DL.Result(DL.Callback('timed_finish', kind, id, res.token), kind == 'repair' and 'success' or 'warn')
        if stop and kind == 'thermite' then stop() end
        if stopFx then SetTimeout(2500, stopFx) end
    end
    DL.busy = false
end

run.thermite = function(id) timed('thermite', id) end
run.ram = function(id) timed('ram', id) end
run.repair = function(id) timed('repair', id) end

-- --------------------------------------------------------------------------
--  Klucze cyfrowe / zapytania z paneli NUI (wąska biała lista)
-- --------------------------------------------------------------------------
local proxy = {
    keys_add = true, keys_remove = true, keys_list = true,
    admin_save = true, admin_delete = true, admin_state = true, admin_logs = true,
}

RegisterNUICallback('req', function(data, cb)
    if type(data) ~= 'table' or not proxy[data.name] then return cb({ ok = false }) end
    CreateThread(function()
        local args = type(data.args) == 'table' and data.args or {}
        cb(DL.Callback(data.name, table.unpack(args, 1, 4)) or { ok = false, msg = L('error') })
    end)
end)

-- --------------------------------------------------------------------------
--  Klawisze
-- --------------------------------------------------------------------------
RegisterCommand('+dpdl_use', function()
    if not canAct() then return end
    local id = DL.focus
    CreateThread(function() Interact.Use(id) end)
end, false)
RegisterCommand('-dpdl_use', function() end, false)
RegisterKeyMapping('+dpdl_use', L('key_use'), 'keyboard', Config.Keys.use)

RegisterCommand('+dpdl_menu', function()
    if not canAct() then return end
    local id = DL.focus
    CreateThread(function() Interact.Menu(id) end)
end, false)
RegisterCommand('-dpdl_menu', function() end, false)
RegisterKeyMapping('+dpdl_menu', L('key_menu'), 'keyboard', Config.Keys.menu)

-- --------------------------------------------------------------------------
--  Dźwięki i alarmy z serwera
-- --------------------------------------------------------------------------
RegisterNetEvent('dp-doorlock:client:sound', function(name, vol)
    SendNUIMessage({ action = 'sound', name = name, vol = math.max(0.08, vol or 1.0) })
end)

RegisterNetEvent('dp-doorlock:client:alarm', function(payload) Hooks.Alarm(payload) end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if game and game.stop then game.stop() end
    if game and game.cam then game.cam() end
end)
