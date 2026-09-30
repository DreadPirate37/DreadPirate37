-- ==========================================================================
--  dp-doorlock – panel administratora: CRUD drzwi, stany, dziennik
-- ==========================================================================
local S = Store

local function guard(src)
    return Bridge.IsAdmin(src)
end

local function counts()
    local c = { total = #S.order, locked = 0, broken = 0, lockdown = 0, alarm = 0 }
    local now = os.time()
    for _, id in ipairs(S.order) do
        local st = DL.states[id]
        if st.locked then c.locked = c.locked + 1 end
        if st.broken then c.broken = c.broken + 1 end
        if st.lockdown then c.lockdown = c.lockdown + 1 end
        if st.alarmUntil and st.alarmUntil > now then c.alarm = c.alarm + 1 end
    end
    return c
end

DL.Register('admin_open', function(src)
    if not guard(src) then return { ok = false, msg = L('no_access') } end
    local doors, states = {}, {}
    for _, id in ipairs(S.order) do
        doors[#doors + 1] = S.doors[id]
        states[tostring(id)] = DL.View(id)
    end
    local jobs = {}
    for _, j in ipairs(Config.Alarm.jobs) do jobs[#jobs + 1] = j end
    return {
        ok = true, doors = doors, states = states, stats = counts(),
        keycards = Config.Keycards, framework = Bridge.name, inventory = Bridge.inventory,
    }
end)

DL.Register('admin_save', function(src, def)
    if not guard(src) then return { ok = false, msg = L('no_access') } end
    local n, err = Door.Normalize(def)
    if not n then return { ok = false, msg = L('bad_door', err or '?') } end
    local isNew = not (n.id and S.doors[n.id])
    if isNew then
        n.id = nil
    else
        n.key = S.doors[n.id].key            -- klucz z configu jest stały
    end
    S.Put(n)
    if isNew then
        DL.InitState(n.id)
    elseif DL.states[n.id].scheduleOpen ~= nil and not n.schedule then
        DL.states[n.id].scheduleOpen = nil
    end
    DL.EnsureSchedule()
    S.Log(n.id, src, isNew and 'created' or 'edited')
    TriggerClientEvent('dp-doorlock:client:door', -1, n.id, Door.Public(n), DL.View(n.id))
    return { ok = true, id = n.id, door = n, state = DL.View(n.id), stats = counts(), msg = isNew and L('door_created') or L('door_saved') }
end)

DL.Register('admin_delete', function(src, id)
    if not guard(src) then return { ok = false, msg = L('no_access') } end
    id = tonumber(id)
    if not S.Remove(id) then return { ok = false, msg = L('no_door') } end
    DL.states[id] = nil
    TriggerClientEvent('dp-doorlock:client:door', -1, id, nil)
    return { ok = true, stats = counts(), msg = L('door_deleted') }
end)

DL.Register('admin_state', function(src, id, what)
    if not guard(src) then return { ok = false, msg = L('no_access') } end
    id = tonumber(id)
    if not S.doors[id] then return { ok = false, msg = L('no_door') } end
    local st = DL.states[id]
    if what == 'lock' then DL.SetLocked(id, true, src, 'admin')
    elseif what == 'unlock' then DL.SetLocked(id, false, src, 'admin')
    elseif what == 'repair' then DL.Repair(id, src, 'admin')
    elseif what == 'breach' then DL.SetBroken(id, Config.Breach.brokenSeconds, src, 'admin')
    elseif what == 'alarm' then st.lastAlarm = nil DL.Alarm(id, src, 'test')
    elseif what == 'lockdown' and S.doors[id].group ~= '' then DL.SetLockdown(S.doors[id].group, not st.lockdown, src)
    else return { ok = false, msg = L('cant_do') } end
    return { ok = true, state = DL.View(id), stats = counts() }
end)

DL.Register('admin_logs', function(src, id)
    if not guard(src) then return { ok = false, msg = L('no_access') } end
    return { ok = true, logs = S.GetLogs(tonumber(id)) }
end)
