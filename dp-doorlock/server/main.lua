-- ==========================================================================
--  dp-doorlock – serwer: stan zamków, autoryzacja, synchronizacja, harmonogramy
--  Serwer jest jedynym źródłem prawdy. Brak pętli odpytujących: autozamek i
--  wygasanie wyłamań idą na SetTimeout, harmonogram tyka co 30 s tylko wtedy,
--  gdy jakiekolwiek drzwi go mają.
-- ==========================================================================
DL = {
    states = {},       -- [id] = { locked, broken, brokenUntil, lockdown, alarmUntil, autoAt, autoToken, lastAlarm }
    sessions = {},     -- [src] = sesja minigry / akcji czasowej
    pinFails = {},     -- [src .. ':' .. id] = { n, until }
    handlers = {},
}
local S = Store

local function dbg(...)
    if Config.Debug then print('^3[dp-doorlock]^7', ...) end
end
DL.dbg = dbg

-- --------------------------------------------------------------------------
--  Callbacki (lekkie, z limitem 1 wywołanie / 200 ms / nazwa / gracz)
-- --------------------------------------------------------------------------
local lastCall = {}
function DL.Register(name, fn) DL.handlers[name] = fn end

RegisterNetEvent('dp-doorlock:server:cb', function(name, id, ...)
    local src = source
    if type(id) ~= 'number' or type(name) ~= 'string' then return end
    local h = DL.handlers[name]
    if not h then return TriggerClientEvent('dp-doorlock:client:cb', src, id, nil) end
    local lc = lastCall[src]
    if not lc then lc = {} lastCall[src] = lc end
    local now = GetGameTimer()
    if lc[name] and now - lc[name] < 200 then
        return TriggerClientEvent('dp-doorlock:client:cb', src, id, { ok = false, msg = L('slow_down') })
    end
    lc[name] = now
    local ok, res = pcall(h, src, ...)
    if not ok then
        print(('^1[dp-doorlock] błąd w %s: %s^7'):format(name, res))
        res = { ok = false, msg = L('error') }
    end
    TriggerClientEvent('dp-doorlock:client:cb', src, id, res)
end)

AddEventHandler('playerDropped', function()
    local src = source
    lastCall[src] = nil
    DL.sessions[src] = nil
    for k in pairs(DL.pinFails) do
        if k:find('^' .. src .. ':') then DL.pinFails[k] = nil end
    end
end)

-- --------------------------------------------------------------------------
--  Widok stanu dla klientów (kompaktowy – leci do wszystkich przy każdej zmianie)
-- --------------------------------------------------------------------------
function DL.View(id)
    local st = DL.states[id]
    if not st then return nil end
    local now = os.time()
    return {
        l = st.locked,
        b = st.broken or nil,
        d = st.lockdown or nil,
        a = (st.alarmUntil and st.alarmUntil > now) or nil,
        t = st.autoAt and math.max(0, st.autoAt - now) or nil,
    }
end

function DL.Broadcast(id)
    TriggerClientEvent('dp-doorlock:client:state', -1, id, DL.View(id))
end

-- --------------------------------------------------------------------------
--  Autoryzacja
-- --------------------------------------------------------------------------
local function gradeOk(map, who)
    if not who or not map then return false end
    local need = map[who.name]
    return need ~= nil and (who.grade or 0) >= need
end

--- Czy gracz ma dostęp „z urzędu” (praca / gang / właściciel / lista osób / przedmiot).
--- opts.noItems – nie sprawdzaj przedmiotów (np. czytnik biometryczny).
function DL.HasAccess(src, d, opts)
    if d.access.public then return true end
    if Config.AdminAccess and Bridge.IsAdmin(src) then return true end
    local ident = Bridge.GetIdentifier(src)
    if ident and (d.owner == ident or d.access.identifiers[ident]) then return true end
    local job = Bridge.GetJob(src)
    if job and (not Config.RequireDuty or job.duty) and gradeOk(d.access.jobs, job) then return true end
    if next(d.access.gangs) and gradeOk(d.access.gangs, Bridge.GetGang(src)) then return true end
    if not (opts and opts.noItems) and #d.access.items > 0 and Bridge.FirstItem(src, d.access.items) then return true end
    return false
end

function DL.JobIn(src, map)
    local job = Bridge.GetJob(src)
    return job ~= nil and (not Config.RequireDuty or job.duty) and gradeOk(map, job)
end

function DL.CanLockdown(src)
    return Bridge.IsAdmin(src) or DL.JobIn(src, Config.Lockdown.jobs)
end

function DL.IsOwner(src, d)
    return d.owner ~= nil and d.owner == Bridge.GetIdentifier(src)
end

--- Czy gracz stoi przy drzwiach (z zapasem na lag i pojazdy).
function DL.Near(src, id, extra)
    local d, pos = S.doors[id], S.pos[id]
    if not d or not pos then return false end
    local ped = GetPlayerPed(src)
    if ped == 0 then return false end
    local limit = d.distance + 2.5 + (extra or 0)
    if GetVehiclePedIsIn(ped, false) ~= 0 then limit = limit + 8.0 end
    return #(GetEntityCoords(ped) - pos) <= limit
end

-- --------------------------------------------------------------------------
--  Zmiana stanu
-- --------------------------------------------------------------------------
function DL.SetLocked(id, locked, src, reason)
    local d, st = S.doors[id], DL.states[id]
    if not d or not st then return false end
    locked = locked == true
    st.locked = locked
    st.autoToken = (st.autoToken or 0) + 1
    st.autoAt = nil

    if not locked and d.autoLock > 0 and not st.broken and not st.scheduleOpen then
        local token = st.autoToken
        st.autoAt = os.time() + d.autoLock
        SetTimeout(d.autoLock * 1000, function()
            local s2 = DL.states[id]
            if s2 and s2.autoToken == token and not s2.locked and not s2.broken then
                DL.SetLocked(id, true, 0, 'auto')
            end
        end)
    end

    S.PersistLock(id, locked)
    S.Log(id, src, locked and 'lock' or 'unlock', reason)
    DL.Broadcast(id)
    TriggerEvent('dp-doorlock:changed', id, locked, src, reason)
    return true
end

function DL.SetBroken(id, seconds, src, reason)
    local st = DL.states[id]
    if not st then return end
    st.broken = true
    st.brokenToken = (st.brokenToken or 0) + 1
    local token = st.brokenToken
    DL.SetLocked(id, false, src, reason)
    if seconds and seconds > 0 then
        SetTimeout(seconds * 1000, function()
            local s2 = DL.states[id]
            if s2 and s2.broken and s2.brokenToken == token then DL.Repair(id, 0, 'expired') end
        end)
    end
end

function DL.Repair(id, src, reason)
    local st, d = DL.states[id], S.doors[id]
    if not st or not d then return end
    st.broken = false
    st.brokenToken = (st.brokenToken or 0) + 1
    S.Log(id, src, 'repair', reason)
    DL.SetLocked(id, d.locked, src, 'repair')
end

function DL.SetLockdown(group, on, src)
    local n = 0
    for _, id in ipairs(S.order) do
        local d = S.doors[id]
        if d.group ~= '' and d.group:lower() == group:lower() then
            local st = DL.states[id]
            st.lockdown = on or nil
            if on and not st.broken then
                DL.SetLocked(id, true, src, 'lockdown')
            else
                S.Log(id, src, on and 'lockdown' or 'lockdown_off')
                DL.Broadcast(id)
            end
            n = n + 1
        end
    end
    return n
end

-- --------------------------------------------------------------------------
--  Alarm → powiadomienie służb (+ hak na zewnętrzne dispatche)
-- --------------------------------------------------------------------------
local alarmJobs = {}
for _, j in ipairs(Config.Alarm.jobs) do alarmJobs[j] = true end

function DL.Alarm(id, src, reason)
    local d, st = S.doors[id], DL.states[id]
    if not d or not st then return end
    local now = os.time()
    if st.lastAlarm and now - st.lastAlarm < Config.Alarm.cooldown then return end
    st.lastAlarm = now
    st.alarmUntil = now + Config.Alarm.blipSeconds
    S.Log(id, src, 'alarm', reason)
    DL.Broadcast(id)

    local payload = {
        id = id, name = d.name, group = d.group, reason = reason,
        coords = d.coords, seconds = Config.Alarm.blipSeconds,
    }
    for _, p in ipairs(GetPlayers()) do
        local pid = tonumber(p)
        local job = Bridge.GetJob(pid)
        if job and alarmJobs[job.name] and (not Config.RequireDuty or job.duty) then
            TriggerClientEvent('dp-doorlock:client:alarm', pid, payload)
        end
    end
    if ServerHooks.Dispatch then ServerHooks.Dispatch(src, payload) end
    SetTimeout(Config.Alarm.blipSeconds * 1000 + 50, function() DL.Broadcast(id) end)
end

-- --------------------------------------------------------------------------
--  Inicjalizacja stanów
-- --------------------------------------------------------------------------
function DL.InitState(id)
    local d = S.doors[id]
    local saved = S.SavedLock(id)
    DL.states[id] = DL.states[id] or {}
    local st = DL.states[id]
    if saved == nil then st.locked = d.locked else st.locked = saved end
end

-- --------------------------------------------------------------------------
--  Harmonogram (czas serwera). Tyka tylko, jeśli są drzwi z harmonogramem.
-- --------------------------------------------------------------------------
local scheduleRunning = false
local function scheduleTick()
    local t = os.date('*t')
    local minute = t.hour * 60 + t.min
    local any = false
    for _, id in ipairs(S.order) do
        local d = S.doors[id]
        if d.schedule then
            any = true
            local st = DL.states[id]
            local open = Door.ScheduleOpen(d.schedule, minute)
            if st.scheduleOpen ~= open then
                st.scheduleOpen = open
                if not st.lockdown and not st.broken then
                    DL.SetLocked(id, not open, 0, 'schedule')
                end
            end
        end
    end
    return any
end

function DL.EnsureSchedule()
    if scheduleRunning then return end
    if not scheduleTick() then return end
    scheduleRunning = true
    CreateThread(function()
        while scheduleRunning do
            Wait(30000)
            scheduleRunning = scheduleTick()
        end
    end)
end

-- --------------------------------------------------------------------------
--  Callbacki podstawowe
-- --------------------------------------------------------------------------
DL.Register('init', function(src)
    local doors, states = {}, {}
    for _, id in ipairs(S.order) do
        doors[#doors + 1] = Door.Public(S.doors[id])
        states[tostring(id)] = DL.View(id)
    end
    return { doors = doors, states = states, admin = Bridge.IsAdmin(src) }
end)

local function pinKey(src, id) return src .. ':' .. id end

--- Główna akcja: otwórz / zamknij. data = { pin = '1234' } | { badge = true } | nil
DL.Register('toggle', function(src, id, data)
    id = tonumber(id)
    local d, st = S.doors[id], DL.states[id]
    if not d then return { ok = false, msg = L('no_door') } end
    if not DL.Near(src, id) then return { ok = false, msg = L('too_far') } end
    data = type(data) == 'table' and data or {}

    if st.broken then return { ok = false, reason = 'broken', msg = L('door_broken') } end
    if st.lockdown and not DL.CanLockdown(src) then
        return { ok = false, reason = 'lockdown', msg = L('lockdown_active') }
    end

    local allowed, via = false, nil
    if d.security == 'standard' then
        allowed = DL.HasAccess(src, d)
        via = 'key'
    elseif d.security == 'keypad' then
        if type(data.pin) == 'string' then
            local k = pinKey(src, id)
            local f = DL.pinFails[k]
            if f and f.untilT and f.untilT > os.time() then
                return { ok = false, reason = 'lockout', seconds = f.untilT - os.time(), msg = L('keypad_locked', f.untilT - os.time()) }
            end
            if data.pin == d.pin then
                DL.pinFails[k] = nil
                allowed, via = true, 'pin'
            else
                f = f or { n = 0 }
                f.n = f.n + 1
                DL.pinFails[k] = f
                S.Log(id, src, 'pin_fail')
                if f.n >= Config.Keypad.maxAttempts then
                    f.n = 0
                    f.untilT = os.time() + Config.Keypad.lockoutSeconds
                    if Config.Keypad.alarmOnLockout and d.alarm then DL.Alarm(id, src, 'pin') end
                    return { ok = false, reason = 'lockout', seconds = Config.Keypad.lockoutSeconds, msg = L('keypad_locked', Config.Keypad.lockoutSeconds) }
                end
                return { ok = false, reason = 'wrong_pin', left = Config.Keypad.maxAttempts - f.n, msg = L('wrong_pin') }
            end
        else
            allowed, via = DL.HasAccess(src, d, { noItems = true }), 'badge'
        end
    elseif d.security == 'card' then
        allowed = Bridge.KeycardLevel(src) >= (d.cardLevel or 1) or DL.HasAccess(src, d, { noItems = true })
        via = 'card'
    elseif d.security == 'bio' then
        allowed, via = DL.HasAccess(src, d, { noItems = true }), 'bio'
    end

    if not allowed then
        S.Log(id, src, 'denied', via)
        return { ok = false, reason = 'denied', msg = L('no_access') }
    end

    local locked = not st.locked
    if data.want ~= nil then locked = data.want == true end
    DL.SetLocked(id, locked, src, via)
    return { ok = true, locked = locked }
end)

-- --------------------------------------------------------------------------
--  Start
-- --------------------------------------------------------------------------
CreateThread(function()
    S.Load()
    for _, id in ipairs(S.order) do DL.InitState(id) end
    DL.EnsureSchedule()
    TriggerClientEvent('dp-doorlock:client:reload', -1)
end)

-- --------------------------------------------------------------------------
--  Eksporty dla innych zasobów
-- --------------------------------------------------------------------------
local function byRef(ref)
    if type(ref) == 'number' then return S.doors[ref] and ref end
    if type(ref) == 'string' then
        for _, id in ipairs(S.order) do
            if S.doors[id].key == ref then return id end
        end
    end
end

exports('SetLocked', function(ref, locked) local id = byRef(ref) return id and DL.SetLocked(id, locked, 0, 'export') or false end)
exports('IsLocked', function(ref) local id = byRef(ref) return id and DL.states[id].locked end)
exports('GetDoor', function(ref) local id = byRef(ref) return id and Door.Public(S.doors[id]) end)
exports('GetState', function(ref) local id = byRef(ref) return id and DL.View(id) end)
exports('SetLockdown', function(group, on) return DL.SetLockdown(group, on == true, 0) end)
exports('Breach', function(ref, seconds) local id = byRef(ref) if id then DL.SetBroken(id, seconds or Config.Breach.brokenSeconds, 0, 'export') end end)
exports('Repair', function(ref) local id = byRef(ref) if id then DL.Repair(id, 0, 'export') end end)
exports('TriggerAlarm', function(ref, reason) local id = byRef(ref) if id then DL.Alarm(id, 0, reason or 'export') end end)
