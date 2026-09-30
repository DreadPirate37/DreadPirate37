-- ==========================================================================
--  dp-doorlock – akcje dodatkowe: menu, pukanie, dzwonek, wytrych, hakowanie,
--  termit, taran, naprawa, blokada budynku, klucze cyfrowe, zmiana PIN-u
--  Każda akcja czasowa / minigra ma sesję z jednorazowym tokenem i minimalnym
--  czasem trwania – klient nie może „zgłosić sukcesu” bez jej rozpoczęcia.
-- ==========================================================================
local S = Store
local sessions = DL.sessions
local hackLock = {}      -- [src .. ':' .. id] = os.time() końca blokady
local socialCd = {}      -- [src] = GetGameTimer()

local function token()
    return ('%08x%08x'):format(math.random(0, 0x7fffffff), math.random(0, 0x7fffffff))
end

local function startSession(src, kind, id, extra)
    local s = { kind = kind, id = id, token = token(), t = GetGameTimer() }
    if extra then for k, v in pairs(extra) do s[k] = v end end
    sessions[src] = s
    return s
end

local function takeSession(src, kind, id, tok, minMs)
    local s = sessions[src]
    if not s or s.kind ~= kind or s.id ~= id or s.token ~= tok then return nil, L('session_invalid') end
    sessions[src] = nil
    if GetGameTimer() - s.t < (minMs or 0) then return nil, L('suspicious') end
    if not DL.Near(src, id, 1.5) then return nil, L('too_far') end
    return s
end

local function door(id)
    id = tonumber(id)
    local d = id and S.doors[id]
    return d, d and DL.states[id], id
end

local function sounds(kind, coords, radius, except)
    local pos = vector3(coords.x, coords.y, coords.z)
    for _, p in ipairs(GetPlayers()) do
        local pid = tonumber(p)
        local ped = GetPlayerPed(pid)
        if ped ~= 0 and pid ~= except then
            local dist = #(GetEntityCoords(ped) - pos)
            if dist <= radius then
                TriggerClientEvent('dp-doorlock:client:sound', pid, kind, 1.0 - dist / radius, pid)
            end
        end
    end
end

-- --------------------------------------------------------------------------
--  Menu akcji (radial) – serwer decyduje, co gracz może zrobić
-- --------------------------------------------------------------------------
DL.Register('menu', function(src, id)
    local d, st
    d, st, id = door(id)
    if not d then return { ok = false, msg = L('no_door') } end
    if not DL.Near(src, id) then return { ok = false, msg = L('too_far') } end

    local admin = Bridge.IsAdmin(src)
    local owner = DL.IsOwner(src, d)
    local access = DL.HasAccess(src, d, { noItems = d.security ~= 'standard' })
    local opts = {}
    local function add(key, icon, label, desc, disabled, tone)
        opts[#opts + 1] = { id = key, icon = icon, label = label, desc = desc, disabled = disabled or nil, tone = tone }
    end
    local locked, broken = st.locked, st.broken

    local useIcon = ({ standard = locked and 'unlock' or 'lock', keypad = 'keypad', card = 'card', bio = 'finger' })[d.security]
    local useLabel = ({
        standard = locked and L('m_unlock') or L('m_lock'),
        keypad = L('m_keypad'), card = L('m_card'), bio = L('m_bio'),
    })[d.security]
    add('use', useIcon, useLabel, broken and L('door_broken') or nil, broken, 'primary')
    add('knock', 'knock', L('m_knock'))
    if d.doorbell then add('bell', 'bell', L('m_bell')) end

    if locked and not broken then
        if d.lockpick > 0 and d.security == 'standard' then
            local has, _, label = DL.LockTool(src, d)
            add('lockpick', 'pick', L(label), has and L('difficulty', d.lockpick) or L('need_item'), not has, 'crime')
        end
        if d.hack > 0 and Door.Electronic[d.security] then
            local has = Bridge.FirstItem(src, Config.Items.hackDevice)
            add('hack', 'chip', L('m_hack'), has and L('difficulty', d.hack) or L('need_item'), not has, 'crime')
        end
        if d.breach then
            local has = Bridge.FirstItem(src, Config.Items.thermite)
            add('thermite', 'fire', L('m_thermite'), has and L('alarm_warn') or L('need_item'), not has, 'crime')
        end
        if (d.breach or Config.Breach.ramAnyDoor) and DL.JobIn(src, Config.Breach.ramJobs) then
            local has = Config.Items.ram == nil or Bridge.FirstItem(src, Config.Items.ram)
            add('ram', 'ram', L('m_ram'), has and nil or L('need_item'), not has, 'danger')
        end
    end
    if broken and (access or DL.JobIn(src, Config.Breach.repairJobs) or admin) then
        add('repair', 'wrench', L('m_repair'))
    end
    if d.group ~= '' and DL.CanLockdown(src) then
        add('lockdown', 'shield', st.lockdown and L('m_lockdown_off') or L('m_lockdown'), d.group, nil, 'danger')
    end
    if owner or admin then add('keys', 'keys', L('m_keys'), L('m_keys_desc')) end
    if d.security == 'keypad' and (owner or admin or access) then add('pin', 'hash', L('m_pin')) end
    if admin then add('edit', 'edit', L('m_edit'), '#' .. id) end

    return { ok = true, options = opts }
end)

-- --------------------------------------------------------------------------
--  Pukanie i dzwonek
-- --------------------------------------------------------------------------
local function social(src)
    local now = GetGameTimer()
    if socialCd[src] and now - socialCd[src] < Config.Social.cooldown * 1000 then return false end
    socialCd[src] = now
    return true
end
AddEventHandler('playerDropped', function() socialCd[source] = nil sessions[source] = nil end)

DL.Register('knock', function(src, id)
    local d, _, id2 = door(id)
    if not d or not DL.Near(src, id2) then return { ok = false, msg = L('too_far') } end
    if not social(src) then return { ok = false } end
    sounds('knock', d.coords, Config.Social.knockRadius)
    return { ok = true }
end)

DL.Register('bell', function(src, id)
    local d, _, id2 = door(id)
    if not d or not d.doorbell or not DL.Near(src, id2) then return { ok = false, msg = L('too_far') } end
    if not social(src) then return { ok = false } end
    sounds('bell', d.coords, Config.Social.bellRadius)
    local pos, radius = S.pos[id2], Config.Social.bellRadius
    for _, p in ipairs(GetPlayers()) do
        local pid = tonumber(p)
        if pid ~= src then
            local ped = GetPlayerPed(pid)
            if ped ~= 0 and #(GetEntityCoords(ped) - pos) <= radius and DL.HasAccess(pid, d, { noItems = true }) then
                Bridge.Notify(pid, L('bell_ring', d.name), 'info')
            end
        end
    end
    S.Log(id2, src, 'bell')
    return { ok = true }
end)

-- --------------------------------------------------------------------------
--  Wytrych
-- --------------------------------------------------------------------------
--- Jakie narzędzie i jaka minigra dla tych drzwi (jak w symulatorach włamywacza)
local function lockTool(src, d)
    local C = Config.Lockpick
    if d.lockModel == 'round' then
        return Bridge.FirstItem(src, Config.Items.round), 'round', 'm_lockpick_round'
    end
    if d.lockpick <= C.diyMaxDifficulty then
        local item = Bridge.FirstItem(src, Config.Items.diy)
        if item then return item, 'diy', 'm_lockpick_diy' end
        item = Bridge.FirstItem(src, Config.Items.lockpick)
        return item, item and 'diy' or nil, 'm_lockpick_diy'
    end
    return Bridge.FirstItem(src, Config.Items.lockpick), 'standard', 'm_lockpick'
end
DL.LockTool = lockTool

DL.Register('lockpick_start', function(src, id)
    local d, st, id2 = door(id)
    if not d or d.lockpick == 0 or d.security ~= 'standard' then return { ok = false, msg = L('cant_do') } end
    if not DL.Near(src, id2) then return { ok = false, msg = L('too_far') } end
    if not st.locked or st.broken then return { ok = false, msg = L('already_open') } end
    local item, mode = lockTool(src, d)
    if not item then return { ok = false, msg = L('need_item') } end
    local C, diff = Config.Lockpick, d.lockpick
    local advanced = item == Config.Items.advanced
    local s = startSession(src, 'lockpick', id2, { item = item })
    local res = {
        ok = true, token = s.token, mode = mode, model = d.lockModel, difficulty = diff,
        advanced = advanced, seed = math.random(1, 2 ^ 30),
    }
    if mode == 'diy' then
        res.maxFails = C.diy.maxFails[math.min(diff, #C.diy.maxFails)]
    else
        local P = C.pins
        res.pins = mode == 'round' and 7 or P.count[diff]
        res.knockMax, res.spring, res.maxFails = P.knockMax[diff], P.spring[diff], P.maxFails
        res.stall = P.stall[diff] + (advanced and C.advancedBonus or 0)
    end
    return res
end)

-- porażka kosztuje tylko wtedy, gdy narzędzie pękło w minigrze; wyjście (ESC) jest darmowe
DL.Register('lockpick_finish', function(src, id, tok, success, snapped)
    local d, _, id2 = door(id)
    if not d then return { ok = false } end
    local s, err = takeSession(src, 'lockpick', id2, tok, success and Config.Lockpick.minSeconds * 1000 or 0)
    if not s then return { ok = false, msg = err } end
    if success then
        S.Log(id2, src, 'lockpick', 'ok')
        DL.SetLocked(id2, false, src, 'lockpick')
        return { ok = true, msg = L('picked') }
    end
    if snapped ~= true then return { ok = true, failed = true } end
    S.Log(id2, src, 'lockpick', 'fail')
    Bridge.RemoveItem(src, s.item, 1)
    if d.alarm and math.random() < Config.Lockpick.alarmOnBreak then DL.Alarm(id2, src, 'lockpick') end
    return { ok = true, failed = true, broke = true, msg = L('pick_broke') }
end)

-- --------------------------------------------------------------------------
--  Hakowanie
-- --------------------------------------------------------------------------
DL.Register('hack_start', function(src, id)
    local d, st, id2 = door(id)
    if not d or d.hack == 0 or not Door.Electronic[d.security] then return { ok = false, msg = L('cant_do') } end
    if not DL.Near(src, id2) then return { ok = false, msg = L('too_far') } end
    if not st.locked or st.broken then return { ok = false, msg = L('already_open') } end
    if not Bridge.FirstItem(src, Config.Items.hackDevice) then return { ok = false, msg = L('need_item') } end
    local k = src .. ':' .. id2
    if hackLock[k] and hackLock[k] > os.time() then return { ok = false, msg = L('hack_locked', hackLock[k] - os.time()) } end
    local s = startSession(src, 'hack', id2)
    return {
        ok = true, token = s.token, difficulty = d.hack, time = Config.Hack.timeLimit,
        stages = Config.Hack.stagesByDifficulty[d.hack], seed = math.random(1, 2 ^ 30),
    }
end)

DL.Register('hack_finish', function(src, id, tok, success)
    local d, _, id2 = door(id)
    if not d then return { ok = false } end
    local s, err = takeSession(src, 'hack', id2, tok, success and Config.Hack.minSeconds * 1000 or 0)
    if not s then return { ok = false, msg = err } end
    if success then
        S.Log(id2, src, 'hack', 'ok')
        DL.SetLocked(id2, false, src, 'hack')
        return { ok = true, msg = L('hacked') }
    end
    S.Log(id2, src, 'hack', 'fail')
    hackLock[src .. ':' .. id2] = os.time() + Config.Hack.lockoutSeconds
    if Config.Hack.alarmOnFail and d.alarm then DL.Alarm(id2, src, 'hack') end
    return { ok = true, failed = true, msg = L('hack_failed') }
end)

-- --------------------------------------------------------------------------
--  Akcje czasowe: termit, taran, naprawa
-- --------------------------------------------------------------------------
local timed = {
    thermite = {
        seconds = function() return Config.Breach.thermiteSeconds end,
        check = function(src, d, st)
            if not d.breach then return L('cant_do') end
            if not st.locked or st.broken then return L('already_open') end
            local item = Config.Items.thermite
            if Bridge.ItemCount(src, item) < 1 then return L('need_item') end
            Bridge.RemoveItem(src, item, 1)          -- ładunek zużywa się od razu
        end,
        finish = function(src, d, id)
            DL.SetBroken(id, Config.Breach.brokenSeconds, src, 'thermite')
            S.Log(id, src, 'breach', 'thermite')
            if d.alarm then DL.Alarm(id, src, 'thermite') end
            return L('breached')
        end,
    },
    ram = {
        seconds = function() return Config.Breach.ramSeconds end,
        check = function(src, d, st)
            if not (d.breach or Config.Breach.ramAnyDoor) or not DL.JobIn(src, Config.Breach.ramJobs) then return L('cant_do') end
            if not st.locked or st.broken then return L('already_open') end
            if Config.Items.ram and Bridge.ItemCount(src, Config.Items.ram) < 1 then return L('need_item') end
        end,
        finish = function(src, _, id)
            DL.SetBroken(id, Config.Breach.brokenSeconds, src, 'ram')
            S.Log(id, src, 'breach', 'ram')
            return L('rammed')
        end,
    },
    repair = {
        seconds = function() return Config.Breach.repairSeconds end,
        check = function(src, d, st)
            if not st.broken then return L('not_broken') end
            if not (DL.HasAccess(src, d) or DL.JobIn(src, Config.Breach.repairJobs) or Bridge.IsAdmin(src)) then return L('no_access') end
        end,
        finish = function(src, _, id)
            DL.Repair(id, src, 'manual')
            return L('repaired')
        end,
    },
}

DL.Register('timed_start', function(src, kind, id)
    local def = timed[kind]
    local d, st, id2 = door(id)
    if not def or not d then return { ok = false, msg = L('cant_do') } end
    if not DL.Near(src, id2) then return { ok = false, msg = L('too_far') } end
    local err = def.check(src, d, st)
    if err then return { ok = false, msg = err } end
    local secs = def.seconds()
    local s = startSession(src, 'timed:' .. kind, id2)
    return { ok = true, token = s.token, seconds = secs }
end)

DL.Register('timed_finish', function(src, kind, id, tok)
    local def = timed[kind]
    local d, _, id2 = door(id)
    if not def or not d then return { ok = false } end
    local s, err = takeSession(src, 'timed:' .. kind, id2, tok, def.seconds() * 1000 - 600)
    if not s then return { ok = false, msg = err } end
    return { ok = true, msg = def.finish(src, d, id2) }
end)

DL.Register('timed_cancel', function(src)
    local s = sessions[src]
    if s and s.kind:sub(1, 6) == 'timed:' then sessions[src] = nil end
    return { ok = true }
end)

-- --------------------------------------------------------------------------
--  Blokada budynku
-- --------------------------------------------------------------------------
DL.Register('lockdown', function(src, id)
    local d, st, id2 = door(id)
    if not d or d.group == '' then return { ok = false, msg = L('cant_do') } end
    if not DL.CanLockdown(src) then return { ok = false, msg = L('no_access') } end
    local on = not st.lockdown
    local n = DL.SetLockdown(d.group, on, src)
    return { ok = true, msg = on and L('lockdown_on', d.group, n) or L('lockdown_off', d.group) }
end)

RegisterCommand(Config.Lockdown.command, function(src, args)
    if src > 0 and not DL.CanLockdown(src) then return Bridge.Notify(src, L('no_access'), 'error') end
    local group, off = args[1], args[2] == 'off'
    if not group then return src > 0 and Bridge.Notify(src, L('lockdown_usage'), 'info') end
    local n = DL.SetLockdown(group, not off, src)
    local msg = off and L('lockdown_off', group) or L('lockdown_on', group, n)
    if src > 0 then Bridge.Notify(src, msg, 'warn') else print(msg) end
end, false)

-- --------------------------------------------------------------------------
--  Klucze cyfrowe (właściciel / admin) + dziennik
-- --------------------------------------------------------------------------
local function canManage(src, d) return DL.IsOwner(src, d) or Bridge.IsAdmin(src) end

local function keysView(d, id)
    local holders = {}
    for ident, label in pairs(d.access.identifiers) do holders[#holders + 1] = { id = ident, label = label } end
    table.sort(holders, function(a, b) return a.label < b.label end)
    return { ok = true, name = d.name, holders = holders, logs = S.GetLogs(id, 25), owner = d.owner ~= nil }
end

DL.Register('keys_list', function(src, id)
    local d, _, id2 = door(id)
    if not d or not canManage(src, d) then return { ok = false, msg = L('no_access') } end
    return keysView(d, id2)
end)

DL.Register('keys_add', function(src, id, target)
    local d, _, id2 = door(id)
    if not d or not canManage(src, d) then return { ok = false, msg = L('no_access') } end
    target = tonumber(target)
    if not target or not GetPlayerName(target) then return { ok = false, msg = L('no_player') } end
    local ident = Bridge.GetIdentifier(target)
    if not ident then return { ok = false, msg = L('no_player') } end
    local n = 0
    for _ in pairs(d.access.identifiers) do n = n + 1 end
    if n >= 64 then return { ok = false, msg = L('keys_full') } end
    d.access.identifiers[ident] = Bridge.GetName(target):sub(1, 32)
    S.Save()
    S.Log(id2, src, 'key_add', d.access.identifiers[ident])
    Bridge.Notify(target, L('key_received', d.name), 'success')
    local v = keysView(d, id2)
    v.msg = L('key_given')
    return v
end)

DL.Register('keys_remove', function(src, id, ident)
    local d, _, id2 = door(id)
    if not d or not canManage(src, d) then return { ok = false, msg = L('no_access') } end
    if type(ident) ~= 'string' or not d.access.identifiers[ident] then return { ok = false, msg = L('no_player') } end
    S.Log(id2, src, 'key_remove', d.access.identifiers[ident])
    d.access.identifiers[ident] = nil
    S.Save()
    local v = keysView(d, id2)
    v.msg = L('key_taken')
    return v
end)

DL.Register('pin_change', function(src, id, pin)
    local d, _, id2 = door(id)
    if not d or d.security ~= 'keypad' then return { ok = false, msg = L('cant_do') } end
    if not (DL.IsOwner(src, d) or Bridge.IsAdmin(src) or DL.HasAccess(src, d, { noItems = true })) then
        return { ok = false, msg = L('no_access') }
    end
    if not DL.Near(src, id2) then return { ok = false, msg = L('too_far') } end
    pin = tostring(pin or ''):gsub('%D', '')
    if #pin < Config.Keypad.minLength or #pin > Config.Keypad.maxLength then
        return { ok = false, msg = L('pin_len', Config.Keypad.minLength, Config.Keypad.maxLength) }
    end
    d.pin = pin
    S.Save()
    S.Log(id2, src, 'pin_change')
    return { ok = true, msg = L('pin_changed') }
end)
