-- ==========================================================================
--  Włamanie: wejścia (WEJ), sesje w routing bucketach (DOM-02), akcje w środku (LUP, ZAM),
--  alarm (ZAB-11/12/18/25), domownicy przez hosta AI (NPC-26/27), zdarzenia (ZLE-08), ocena (SKR-23)
-- ==========================================================================
Burglary = { sessions = {} }
local U, Profile, Noise = WLM.U, WLM.Profile, WLM.Noise
local sessions = Burglary.sessions
local bySrc = {}                   -- [src] = sid
local sidSeq = 0

-- --------------------------------------------------------------------------
--  Pomocnicze
-- --------------------------------------------------------------------------
local function tplOf(st) return Config.Interiors[st.cfg.interior] end
local function originOf(st) return U.InteriorOrigin(st.cfg, tplOf(st)) end
local function pointWorld(st, p) return U.Rel(originOf(st), p.pos) end
local function sessOf(src) local sid = bySrc[src] return sid and sessions[sid] end
Burglary.SessionOf = sessOf

local function gloved(src) return Player(src).state.wlmGloves == true end
local function masked(src) return Player(src).state.wlmMask == true end

local function toolItem(method)
    local I = Config.Items
    return ({ rake = I.rake, shim = I.shim, pry = I.crowbar, smash = I.crowbar, glasscut = I.glasscutter,
        wire = I.wire, cutters = I.cutters, force = I.crowbar, dvr_take = I.screwdriver, dvr_smash = I.crowbar })[method]
end

local function bestPick(src)
    local lps = Config.Items.lockpicks
    if not Config.RequireItems then return lps[2], 5 end
    local best, total = nil, 0
    for i = 1, #lps do
        local c = Bridge.ItemCount(src, lps[i].item)
        if c > 0 then total = total + c best = lps[i] end
    end
    return best, total
end

local function consumePicks(src, n)
    local lps = Config.Items.lockpicks
    for i = #lps, 1, -1 do
        if n <= 0 then return end
        local c = Bridge.ItemCount(src, lps[i].item)
        if c > 0 then
            local take = math.min(c, n)
            Bridge.RemoveItem(src, lps[i].item, take)
            n = n - take
        end
    end
end

local function lockGame(src, cls, seed)
    local lk = Config.Locks[cls] or Config.Locks.B
    local lp, count = bestPick(src)
    if not lp then return nil end
    return {
        game = 'lockpick', cls = cls, stages = lk.stages, tol = lk.tol + lp.bonus * 1.5, fall = lk.fall,
        dmg = lk.dmg, hp = lp.hp, picks = count, pick = lp.label, seed = seed,
    }, lk.stages * 0.8
end

Burglary.LockGame = function(...) return lockGame(...) end
Burglary.ConsumePicks = function(...) return consumePicks(...) end

local function fingerprint(src, st, where, sess)
    if gloved(src) then Tools.WearGloves(src) return end
    if math.random() > Config.Evidence.fingerprintChance then return end
    Police.AddEvidence(st.id, { kind = 'finger', cid = SV.P(src).id, name = Bridge.GetName(src), where = where })
    if sess then sess.prints = sess.prints + 1 end
end

function Burglary.PushMembers(sid, event, ...)
    local s = sessions[sid]
    if not s then return end
    for m in pairs(s.members) do SV.Client(m, event, ...) end
end

local function describe(st)
    local sess = st.sid and sessions[st.sid]
    return sess and sess.witness or st.witnessDesc or L('desc_unknown')
end

local function entryWhere(e) return (Config.EntryTypes[e.type] or {}).label or e.id end

-- NUI dostaje tylko starte cyfry (bez kolejności) – kod porównuje wyłącznie serwer
local function smudgeOf(code)
    local set, out = {}, {}
    for ch in tostring(code):gmatch('%d') do
        if not set[ch] then set[ch] = true out[#out + 1] = ch end
    end
    table.sort(out)
    return table.concat(out)
end

-- --------------------------------------------------------------------------
--  Alarm (ZAB-11, ZAB-12, ZAB-18, ZAB-22, ZAB-25)
-- --------------------------------------------------------------------------
local function alarmArmed(st)
    local sec = st.profile.security
    if not sec.alarm or st.alarm.stage == 'disarmed' then return false end
    if not st.power then
        if sec.ups <= 0 then return false end
        if os.time() - (st.powerOffAt or 0) > sec.ups then return false end
    end
    return true
end

function Burglary.Alert(st, kind, reporter)
    local c = st.cfg.entries[1].coords
    local eta = Police.Alert(kind, c, st.cfg.district, describe(st), reporter)
    local sess = st.sid and sessions[st.sid]
    if sess and not sess.police then
        sess.police = true
        Burglary.PushMembers(sess.id, 'notify', L('police_called', eta), 'bad')
        Burglary.PushMembers(sess.id, 'hud', { police = eta })
        SetTimeout(eta * 1000, function()
            if sessions[sess.id] == sess then
                sess.policeArrived = true
                Burglary.PushMembers(sess.id, 'notify', L('police_here'), 'bad')
            end
        end)
    end
    if reporter then Progress.AddHeat(reporter, Config.Heat.add.police) end
end

function Burglary.Siren(st, reporter)
    if st.siren then return end
    st.alarm.stage = 'siren'
    st.siren = true
    Houses.Push(st.id)
    local sess = st.sid and sessions[st.sid]
    if sess then
        sess.alarm = true
        Burglary.PushMembers(sess.id, 'alarm', { stage = 'siren' })
        if sess.host then SV.Client(sess.host, 'aiEvent', { kind = 'siren' }) end
    elseif reporter then
        SV.Client(reporter, 'alarm', { stage = 'siren' })
    end
    local sub = st.profile.security.sub
    if sub == 'reaction' then
        Burglary.Alert(st, 'alarm', reporter)
    elseif sub == 'monitor' then
        SetTimeout(Config.Security.monitorDelay * 1000, function()
            if st.siren then Burglary.Alert(st, 'security', reporter) end
        end)
    else
        SetTimeout(20000, function()
            if st.siren and math.random() < 0.7 then Burglary.Alert(st, 'witness', reporter) end
        end)
    end
    SetTimeout(Config.Security.siren.time * 1000, function()
        if st.siren then st.siren = false Houses.Push(st.id) end
    end)
end

local function contactTriggered(st, entryId, minute, src)
    if not alarmArmed(st) or not st.profile.security.contacts[entryId] then return end
    local mode = Profile.AlarmMode(st.profile, minute)
    if mode == 'off' then return end
    if mode == 'night' then Burglary.Siren(st, src) return end
    if st.alarm.stage ~= 'idle' then return end
    local delay = st.profile.security.delay
    st.alarm.stage = 'delay'
    st.alarm.deadline = os.time() + delay
    st.alarm.tries = 0
    st.alarm.n = (st.alarm.n or 0) + 1
    local my = st.alarm.n
    SV.Client(src, 'alarm', { stage = 'delay', left = delay })
    if st.sid then Burglary.PushMembers(st.sid, 'alarm', { stage = 'delay', left = delay }) end
    SetTimeout(delay * 1000, function()
        if st.alarm.n == my and st.alarm.stage == 'delay' then Burglary.Siren(st, src) end
    end)
end

-- --------------------------------------------------------------------------
--  Wejścia: początek (walidacja + parametry minigry) i koniec (walidacja wyniku)
-- --------------------------------------------------------------------------
local function canUseEntry(src, st, e, method)
    local es = st.entries[e.id]
    if es.open and method ~= 'enter' then return false, L('already_open') end
    if e.requires == 'gate' and not st.gateOpen then return false, L('gate_first') end
    local et = Config.EntryTypes[e.type]
    if not et or not U.HasValue(et.methods, method) then return false, L('method_invalid') end
    if method == 'rake' and (Config.Locks[es.lock or 'B'].rake or 0) <= 0 then return false, L('rake_no') end
    if method == 'wire' and es.state ~= 'tilted' then return false, L('wire_no') end
    if method == 'climb' and e.type == 'window' and es.state ~= 'open' then return false, L('climb_no') end
    if method == 'key' and not (e.front and st.keyTaken and st.keyHolder and (st.keyHolder == src or Crew.Same(src, st.keyHolder))) then
        return false, L('no_key')
    end
    if (method == 'lockpick' or method == 'rake') and not es.lock then return false, L('method_invalid') end
    if method == 'lockpick' then
        if not bestPick(src) then return false, L('need_item', L('item_lockpick')) end
    else
        local item = toolItem(method)
        if item and not Bridge.HasItem(src, item) then return false, L('need_item', Economy.ItemLabel(item)) end
    end
    return true
end

local function lockedByOther(src, st)
    if not st.sid then return false end
    local s = sessions[st.sid]
    if not s then return false end
    if s.members[src] then return false end
    return not Crew.Same(src, s.host)
end

SV.Register('entry:begin', function(src, houseId, entryId, method, clock)
    local st = Houses.state[houseId]
    if not st then return { ok = false, msg = L('house_inactive') } end
    local e = U.FindEntry(st.cfg, entryId)
    if not e then return { ok = false, msg = L('error') } end
    if not SV.Near(src, e.coords, 3.5) then return { ok = false, msg = L('too_far') } end
    if lockedByOther(src, st) then return { ok = false, msg = L('house_busy') } end
    if not st.sid then
        local ok, msg = Police.CanStart(src)
        if not ok then return { ok = false, msg = msg } end
    end
    local ok, msg = canUseEntry(src, st, e, method)
    if not ok then return { ok = false, msg = msg } end

    local es = st.entries[e.id]
    local seed = math.random(1, 2 ^ 30)
    local game, minT, noise = nil, 0, Config.Noise.actions
    if method == 'lockpick' then
        game, minT = lockGame(src, e.type == 'gate' and 'D' or es.lock, seed)
    elseif method == 'rake' then
        game = { game = 'rake', cls = es.lock, chance = Config.Locks[es.lock].rake, seed = seed }
        minT = 1.5
    elseif method == 'shim' then
        game = { game = 'shim', seed = seed }
        minT = 1.0
    elseif method == 'pry' then
        game = { game = 'pry', diff = (Config.EntryTypes[e.type].pryDiff or 1), seed = seed }
        minT = 1.5
    elseif method == 'glasscut' then
        game = { game = 'glass', seed = seed }
        minT = 3.0
    else
        local d = Config.Durations[method] or 2.0
        game = { game = 'progress', label = L('act_' .. method), time = d, anim = method }
        minT = d * 0.8
    end
    local token = SV.IssueToken(src, 'entry', { house = houseId, entry = entryId, method = method, clock = clock, picks = game.picks }, minT, 300)
    return { ok = true, token = token, game = game }
end, 400)

SV.Register('entry:finish', function(src, token, result)
    local data, err = SV.UseToken(src, token, 'entry')
    if not data then
        if err == 'too_quick' then SV.Suspicious(src, 'minigra wejścia za szybko') end
        return { ok = false, msg = L('session_invalid') }
    end
    local st = Houses.state[data.house]
    if not st then return { ok = false, msg = L('house_inactive') } end
    local e = U.FindEntry(st.cfg, data.entry)
    if not SV.Near(src, e.coords, 4.0) then return { ok = false, msg = L('too_far') } end
    result = type(result) == 'table' and result or {}

    local method = data.method
    local sess = st.sid and sessions[st.sid]
    local where = L('where_entry', entryWhere(e))
    local A = Config.Noise.actions

    -- zużyte wytrychy (WYT-05)
    local broken = math.floor(U.Clamp(tonumber(result.broken) or 0, 0, data.picks or 10))
    if method == 'lockpick' and broken > 0 then consumePicks(src, broken) end

    if not result.ok then
        if method == 'pry' then TriggerEvent('dp-wlamywacz:internal:worldNoise', st, e.coords, A.pryFail, src, SV.GameMinute(data.clock and data.clock.h, data.clock and data.clock.m)) end
        return { ok = true, opened = false }
    end

    local es = st.entries[e.id]
    es.open = true
    es.method = method
    if method == 'smash' or method == 'pry' or method == 'cutters' then es.broken = true end   -- WEJ-16
    if e.type == 'gate' then st.gateOpen = true end

    local nv = ({ lockpick = A.lockpick, rake = A.rake, shim = A.shim, pry = A.pry, smash = A.smash, glasscut = A.glasscut,
        cutters = A.gate, climb = A.climb, wire = A.hidden, key = A.hidden })[method] or 10
    TriggerEvent('dp-wlamywacz:internal:worldNoise', st, e.coords, nv, src, SV.GameMinute(data.clock and data.clock.h, data.clock and data.clock.m))

    -- ślady (POL-03, POL-04, POL-05)
    fingerprint(src, st, where, sess)
    if method == 'smash' and not gloved(src) and math.random() < 0.4 then
        Police.AddEvidence(st.id, { kind = 'blood', cid = SV.P(src).id, name = Bridge.GetName(src), where = where })
    end
    if es.broken then Police.AddEvidence(st.id, { kind = 'tool', desc = L('ev_' .. method), where = where }) end

    -- kontaktron (ZAB-12)
    if e.type ~= 'gate' then contactTriggered(st, e.id, SV.GameMinute(data.clock and data.clock.h, data.clock and data.clock.m), src) end
    Houses.Push(st.id)
    Contracts.Hook(src, 'entry', { house = st.id, method = method })
    return { ok = true, opened = true }
end, 200)

-- --------------------------------------------------------------------------
--  Ukryty klucz (WEJ-08) i skrzynka z bezpiecznikami (ZAB-18)
-- --------------------------------------------------------------------------
SV.Register('key:begin', function(src, houseId, spot)
    local st = Houses.state[houseId]
    spot = tonumber(spot)
    if not st or not spot or not st.cfg.keySpots or not st.cfg.keySpots[spot] then return { ok = false, msg = L('error') } end
    if not SV.Near(src, st.cfg.keySpots[spot], 3.0) then return { ok = false, msg = L('too_far') } end
    local d = Config.Durations.keySearch
    return { ok = true, token = SV.IssueToken(src, 'key', { house = houseId, spot = spot }, d * 0.8, 60), game = { game = 'progress', label = L('act_keysearch'), time = d, anim = 'low' } }
end, 500)

SV.Register('key:finish', function(src, token)
    local data = SV.UseToken(src, token, 'key')
    if not data then return { ok = false, msg = L('session_invalid') } end
    local st = Houses.state[data.house]
    if not st then return { ok = false } end
    TriggerEvent('dp-wlamywacz:internal:worldNoise', st, st.cfg.keySpots[data.spot], Config.Noise.actions.hidden, src)
    if st.profile.hiddenKey == data.spot and not st.keyTaken then
        st.keyTaken = true
        st.keyHolder = src
        Houses.Push(st.id)
        Recon.Note(src, st, 'key', L('nb_key'))
        return { ok = true, found = true, msg = L('key_found') }
    end
    return { ok = true, found = false, msg = L('key_nothing') }
end, 200)

SV.Register('fuse:begin', function(src, houseId)
    local st = Houses.state[houseId]
    if not st or not st.cfg.fuse then return { ok = false, msg = L('error') } end
    if not SV.Near(src, st.cfg.fuse, 3.0) then return { ok = false, msg = L('too_far') } end
    if not st.power then return { ok = false, msg = L('power_already') } end
    if lockedByOther(src, st) then return { ok = false, msg = L('house_busy') } end
    return { ok = true, token = SV.IssueToken(src, 'fuse', { house = houseId }, 2.0, 120), game = { game = 'fuse', seed = math.random(1, 2 ^ 30) } }
end, 500)

SV.Register('fuse:finish', function(src, token, result)
    local data = SV.UseToken(src, token, 'fuse')
    if not data or type(result) ~= 'table' or not result.ok then return { ok = false } end
    local st = Houses.state[data.house]
    if not st then return { ok = false } end
    st.power = false
    st.powerOffAt = os.time()
    TriggerEvent('dp-wlamywacz:internal:worldNoise', st, st.cfg.fuse, Config.Noise.actions.fuse, src)
    fingerprint(src, st, L('where_fuse'), st.sid and sessions[st.sid])
    Houses.Push(st.id)
    local s = st.sid and sessions[st.sid]
    if s and s.host then SV.Client(s.host, 'aiEvent', { kind = 'power' }) end
    local ups = st.profile.security.alarm and st.profile.security.ups or 0
    return { ok = true, msg = ups > 0 and L('power_off_ups', math.floor(ups / 60)) or L('power_off') }
end, 200)

-- --------------------------------------------------------------------------
--  Sesja: wejście do środka i wyjście (DOM-02, DOM-17, DOM-24)
-- --------------------------------------------------------------------------
local function activeCount()
    local n = 0
    for _ in pairs(sessions) do n = n + 1 end
    return n
end

local function newSession(src, st, minute)
    sidSeq = sidSeq + 1
    local sid = sidSeq
    local present = {}
    for _, p in ipairs(Profile.Present(st.profile, minute)) do present[p.idx] = p.status end
    -- domownicy obudzeni hałasem jeszcze przed wejściem zaczynają czujni (NPC-04)
    for idx in pairs(st.woken or {}) do if present[idx] then present[idx] = 'woken' end end
    -- światła: tam, gdzie ktoś nie śpi, pali się światło (SKR-07)
    local lights = {}
    for _, p in pairs(present) do
        if p == 'awake' or p == 'woken' then lights.salon = true lights.kuchnia = true lights.hall = true end
    end
    local s = {
        id = sid, house = st.id, bucket = 4200 + sid, host = src, members = {}, started = os.time(),
        minute = minute, present = present, lights = lights, noise = 0, detections = 0, prints = 0,
        alarm = st.siren, police = false, policeArrived = false, spotted = {}, lootCount = 0, value = 0,
        netIds = {}, call = nil, witness = nil, lastEvent = os.time(), unlocked = {}, safeOpen = false,
    }
    sessions[sid] = s
    st.sid = sid
    SetRoutingBucketPopulationEnabled(s.bucket, false)
    return s
end

local function sessionView(s, st, src)
    local tpl = tplOf(st)
    return {
        sid = s.id, house = st.id, seed = st.seed, interior = st.cfg.interior, origin = originOf(st),
        host = s.host == src, minute = s.minute, present = s.present, lights = s.lights,
        searched = st.searched, taken = st.taken, unlocked = s.unlocked, power = st.power,
        alarm = { stage = st.alarm.stage, left = st.alarm.deadline and math.max(0, st.alarm.deadline - os.time()) or nil },
        dvr = st.dvr, slots = st.profile.slots, cameras = st.profile.security.cameras,
        dog = st.profile.dog, hasAlarm = st.profile.security.alarm, safeKind = nil,
        started = s.started, tplRooms = #tpl.rooms,
    }
end

SV.Register('house:enter', function(src, houseId, entryId, clock)
    local st = Houses.state[houseId]
    if not st then return { ok = false, msg = L('house_inactive') } end
    if bySrc[src] then return { ok = false, msg = L('already_inside') } end
    local e = U.FindEntry(st.cfg, entryId)
    if not e or e.type == 'gate' or not st.entries[e.id].open then return { ok = false, msg = L('entry_closed') } end
    if not SV.Near(src, e.coords, 4.0) then return { ok = false, msg = L('too_far') } end
    if GetVehiclePedIsIn(GetPlayerPed(src), false) ~= 0 then return { ok = false, msg = L('in_vehicle') } end
    if lockedByOther(src, st) then return { ok = false, msg = L('house_busy') } end

    local prof = Progress.Get(src)
    local s = st.sid and sessions[st.sid]
    if not s then
        local ok, msg = Police.CanStart(src)
        if not ok then return { ok = false, msg = msg } end
        if activeCount() >= Config.Cooldowns.maxActive then return { ok = false, msg = L('too_many') } end
        if os.time() - (prof.lastBurglary or 0) < Config.Cooldowns.player then
            return { ok = false, msg = L('player_cooldown', math.ceil((Config.Cooldowns.player - (os.time() - prof.lastBurglary)) / 60)) }
        end
        if Progress.Level(src) < (Config.Tiers[st.cfg.tier].minLevel or 1) then return { ok = false, msg = L('level_low') } end
        s = newSession(src, st, SV.GameMinute(clock and clock.h, clock and clock.m))
    end
    s.members[src] = true
    bySrc[src] = s.id
    prof.lastBurglary = os.time()
    Store.Touch(prof.id)
    SetPlayerRoutingBucket(src, s.bucket)
    local c = Carry[src]
    if c and c.net then
        local ent = NetworkGetEntityFromNetworkId(c.net)
        if ent and ent ~= 0 then SetEntityRoutingBucket(ent, s.bucket) end
    end
    Player(src).state:set('wlmInside', st.id, true)
    Burglary.PushMembers(s.id, 'memberJoin', src)
    Houses.Push(st.id)
    local view = sessionView(s, st, src)
    view.spawn = e.spawn
    return { ok = true, session = view }
end, 1000)

local function leave(src, s, st, dropped)
    s.members[src] = nil
    bySrc[src] = nil
    if not dropped then
        SetPlayerRoutingBucket(src, 0)
        Player(src).state:set('wlmInside', false, true)
        Player(src).state:set('wlmHidden', false, true)
    end
    local c = Carry[src]
    if c and c.net then
        local ent = NetworkGetEntityFromNetworkId(c.net)
        if ent and ent ~= 0 then SetEntityRoutingBucket(ent, 0) end
    end
    s.leftAt = s.leftAt or {}
    s.leftAt[src] = os.time()
    s.done = s.done or {}
    s.done[src] = true
    if s.host == src then
        local nextHost = next(s.members)
        s.host = nextHost
        if nextHost then SV.Client(nextHost, 'aiHost', s.netIds) end
    end
    if not next(s.members) then Burglary.End(s, 'exit') end
end

SV.Register('house:exit', function(src, pointId)
    local s = sessOf(src)
    if not s then return { ok = false, msg = L('not_inside') } end
    local st = Houses.state[s.house]
    if not st then return { ok = false } end
    local p = U.FindPoint(tplOf(st), pointId)
    if not p or p.type ~= 'exit' then return { ok = false } end
    if not SV.Near(src, pointWorld(st, p), 4.0) then return { ok = false, msg = L('too_far') } end
    local target
    for _, e in ipairs(st.cfg.entries) do
        if e.spawn == p.spawn then target = e break end
    end
    target = target or st.cfg.entries[1]
    -- od środka można otworzyć drzwi i okna bez narzędzi
    st.entries[target.id].open = true
    Houses.Push(st.id)
    leave(src, s, st)
    return { ok = true, coords = { x = target.coords.x, y = target.coords.y, z = target.coords.z, w = target.coords.w } }
end, 1000)

-- --------------------------------------------------------------------------
--  Akcje w środku: przeszukanie, zamknięte szuflady, sejf, łup, rejestrator, panel alarmu
-- --------------------------------------------------------------------------
local function insidePoint(src, pointId, maxDist)
    local s = sessOf(src)
    if not s then return nil, nil, nil, L('not_inside') end
    local st = Houses.state[s.house]
    if not st then return nil, nil, nil, L('error') end
    local p = U.FindPoint(tplOf(st), pointId)
    if not p then return nil, nil, nil, L('error') end
    if not SV.Near(src, pointWorld(st, p), maxDist or 3.0) then return nil, nil, nil, L('too_far') end
    return s, st, p
end

local function furnitureRoll(st, s, furnKey)
    local f = Config.Furniture[furnKey]
    local rng = function(a, b) return a and b and math.random(a, b) or math.random() end
    local prof = st.profile
    local rolls = math.random(f.rolls[1], f.rolls[2])
    local out = {}
    for _ = 1, rolls do
        local list = {}
        for _, row in ipairs(f.table) do
            local key, w = row[1], row[2]
            local cat = key == 'gotowka' and 'cash' or (Config.Loot[key] and Config.Loot[key].cat)
            local m = cat and prof.lootMult[cat] or 1
            list[#list + 1] = { key, w * m }
        end
        out[#out + 1] = U.PickWeighted(rng, list)
    end
    return out
end

SV.Register('act:begin', function(src, pointId, action)
    local s, st, p, err = insidePoint(src, pointId)
    if not s then return { ok = false, msg = err } end
    local seed = math.random(1, 2 ^ 30)
    local game, minT = nil, 0.5
    if action == 'search' then
        if p.type ~= 'search' then return { ok = false } end
        if p.locked and not s.unlocked[p.id] then return { ok = false, msg = L('locked') } end
        if st.searched[p.id] and not (st.leftovers and st.leftovers[p.id]) then return { ok = false, msg = L('searched') } end
        local f = Config.Furniture[p.furniture]
        game = { game = 'progress', label = L('act_search', f.label), time = f.time, anim = f.anim }
        minT = f.time * 0.8
    elseif action == 'unlock' then
        if not p.locked or s.unlocked[p.id] then return { ok = false } end
        game, minT = lockGame(src, 'D', seed)
        if not game then return { ok = false, msg = L('need_item', L('item_lockpick')) } end
    elseif action == 'force' then
        if not p.locked or s.unlocked[p.id] then return { ok = false } end
        if not Bridge.HasItem(src, Config.Items.crowbar) then return { ok = false, msg = L('need_item', Economy.ItemLabel(Config.Items.crowbar)) } end
        game = { game = 'progress', label = L('act_force'), time = Config.Durations.force, anim = 'pry' }
        minT = Config.Durations.force * 0.8
    elseif action == 'safe' then
        if p.type ~= 'safe' or s.safeOpen then return { ok = false, msg = L('searched') } end
        if p.kind == 'furniture' then
            game = { game = 'keypad', len = 4, delay = 0, attempts = 3, smudge = smudgeOf(st.profile.safeFurniture), furniture = true }
        else
            game = { game = 'safe', cls = st.cfg.tier >= 4 and 'C' or st.cfg.tier >= 3 and 'B' or 'A', combo = st.profile.safe, seed = seed }
        end
        minT = 3.0
    elseif action == 'take' then
        if p.type ~= 'loot' or st.taken[p.id] or not st.profile.slots[p.id] then return { ok = false, msg = L('searched') } end
        local key = st.profile.slots[p.id]
        local large = Config.Loot[key].large
        if large and Carry[src] then return { ok = false, msg = L('hands_full') } end
        local d = large and Config.Durations.takeLarge or Config.Durations.take
        game = { game = 'progress', label = L('act_take', Config.Loot[key].label), time = d, anim = large and 'lift' or 'take' }
        minT = d * 0.8
    elseif action == 'dvr_take' or action == 'dvr_smash' then
        if p.type ~= 'dvr' or not st.profile.security.dvr or st.dvr ~= 'ok' then return { ok = false } end
        local item = toolItem(action)
        if not Bridge.HasItem(src, item) then return { ok = false, msg = L('need_item', Economy.ItemLabel(item)) } end
        local d = action == 'dvr_take' and Config.Durations.dvr or Config.Durations.dvrSmash
        game = { game = 'progress', label = L('act_' .. action), time = d, anim = action == 'dvr_take' and 'screw' or 'smash' }
        minT = d * 0.8
    elseif action == 'keypad' then
        if p.type ~= 'alarm' or not st.profile.security.alarm then return { ok = false } end
        if st.alarm.stage == 'disarmed' then return { ok = false, msg = L('alarm_off_already') } end
        local left = st.alarm.deadline and math.max(0, st.alarm.deadline - os.time()) or 0
        game = { game = 'keypad', len = 4, delay = st.alarm.stage == 'delay' and left or 0, attempts = 3 - (st.alarm.tries or 0),
            smudge = smudgeOf(st.profile.security.code), siren = st.siren }
        minT = 1.0
    else
        return { ok = false }
    end
    local token = SV.IssueToken(src, 'act', { point = p.id, action = action, picks = game.picks, sid = s.id }, minT, 300)
    return { ok = true, token = token, game = game }
end, 300)

local function noiseInside(s, st, room, v, src)
    s.noise = s.noise + v
    if s.host then SV.Client(s.host, 'aiNoise', src, room, v) end
    local out = Noise.Outside(st.cfg.interior, room, v)
    if out >= 40 then TriggerEvent('dp-wlamywacz:internal:worldNoise', st, st.cfg.entries[1].coords, out, src, s.minute) end
end

SV.Register('act:finish', function(src, token, result)
    local data, err = SV.UseToken(src, token, 'act')
    if not data then
        if err == 'too_quick' then SV.Suspicious(src, 'akcja w domu za szybko') end
        return { ok = false, msg = L('session_invalid') }
    end
    local s, st, p, e2 = insidePoint(src, data.point, 4.0)
    if not s or s.id ~= data.sid then return { ok = false, msg = e2 or L('error') } end
    result = type(result) == 'table' and result or {}
    local A = Config.Noise.actions
    local action = data.action
    local where = p.furniture and Config.Furniture[p.furniture].label or p.id

    if action == 'search' then
        local found, cash, left = {}, 0, {}
        local keys = (st.leftovers and st.leftovers[p.id]) or furnitureRoll(st, s, p.furniture)
        if st.leftovers then st.leftovers[p.id] = nil end
        st.searched[p.id] = true
        -- kartka z kodem alarmu w biurku / kuchni (ZAM-06, ZAB-11)
        if st.profile.security.alarm and (p.furniture == 'desk' or p.furniture == 'kitchen') and not s.codeNote and math.random() < 0.3 then
            s.codeNote = true
            Recon.Note(src, st, 'code', L('nb_code', st.profile.security.code))
            found[#found + 1] = L('found_code')
        end
        for _, key in ipairs(keys) do
            if key == 'gotowka' then
                local c = math.floor(st.profile.cash / 3 * (0.5 + math.random()))
                cash = cash + c
            elseif key ~= 'nic' and Config.Loot[key] then
                local item = Bag.Make(key, st.id, Bag.RollValue(key, st.profile.tierMult))
                local ok = Bag.Add(src, item)
                if ok then
                    found[#found + 1] = Config.Loot[key].label
                    s.lootCount = s.lootCount + 1
                    s.value = s.value + item.value
                else
                    left[#left + 1] = key
                end
            end
        end
        if cash > 0 then
            Bridge.AddMoney(src, cash, 'wlamanie')
            s.value = s.value + cash
            found[#found + 1] = L('cash_found', cash)
        end
        if #left > 0 then
            st.leftovers = st.leftovers or {}
            st.leftovers[p.id] = left
        end
        noiseInside(s, st, p.room, A.search, src)
        fingerprint(src, st, where, s)
        Bag.Sync(src)
        Burglary.PushMembers(s.id, 'pointState', p.id, { searched = true })
        return { ok = true, found = found, full = #left > 0 }
    elseif action == 'unlock' or action == 'force' then
        if action == 'unlock' then
            local broken = math.floor(U.Clamp(tonumber(result.broken) or 0, 0, data.picks or 10))
            if broken > 0 then consumePicks(src, broken) end
            if not result.ok then return { ok = true, opened = false } end
            noiseInside(s, st, p.room, A.lockpick, src)
        else
            noiseInside(s, st, p.room, A.pry, src)
        end
        s.unlocked[p.id] = true
        fingerprint(src, st, where, s)
        Burglary.PushMembers(s.id, 'pointState', p.id, { unlocked = true })
        return { ok = true, opened = true }
    elseif action == 'safe' then
        local ok = false
        if p.kind == 'furniture' then
            ok = result.code == st.profile.safeFurniture
        else
            local c = result.combo
            ok = type(c) == 'table' and #c == 3
            if ok then
                for i = 1, 3 do if tonumber(c[i]) ~= st.profile.safe[i] then ok = false end end
            end
        end
        if not ok then return { ok = true, opened = false } end
        s.safeOpen = true
        local cash = st.profile.cash * 2
        Bridge.AddMoney(src, cash, 'sejf')
        local found = { L('cash_found', cash) }
        for _, key in ipairs({ 'zegarek', 'naszyjnik', 'dokumenty' }) do
            if math.random() < 0.6 then
                local item = Bag.Make(key, st.id, Bag.RollValue(key, st.profile.tierMult * 1.3))
                if Bag.Add(src, item) then found[#found + 1] = Config.Loot[key].label s.lootCount = s.lootCount + 1 s.value = s.value + item.value end
            end
        end
        s.value = s.value + cash
        fingerprint(src, st, L('where_safe'), s)
        Bag.Sync(src)
        Burglary.PushMembers(s.id, 'pointState', p.id, { searched = true })
        return { ok = true, opened = true, found = found }
    elseif action == 'take' then
        local key = st.profile.slots[p.id]
        if st.taken[p.id] or not key then return { ok = false, msg = L('searched') } end
        local def = Config.Loot[key]
        local item = Bag.Make(key, st.id, Bag.RollValue(key, st.profile.tierMult))
        if def.large then
            if Carry[src] then return { ok = false, msg = L('hands_full') } end
            item.point = p.id
            item.sid = s.id
            Bag.StartCarry(src, item)
            noiseInside(s, st, p.room, A.takeLarge, src)
        else
            local ok, msg = Bag.Add(src, item)
            if not ok then return { ok = false, msg = msg } end
            Bag.Sync(src)
            noiseInside(s, st, p.room, A.take, src)
        end
        st.taken[p.id] = true
        s.lootCount = s.lootCount + 1
        s.value = s.value + item.value
        fingerprint(src, st, def.label, s)
        Burglary.PushMembers(s.id, 'pointState', p.id, { taken = true })
        Contracts.Hook(src, 'take', { house = st.id, key = key })
        return { ok = true, large = def.large == true, label = def.label }
    elseif action == 'dvr_take' or action == 'dvr_smash' then
        st.dvr = action == 'dvr_take' and 'taken' or 'destroyed'
        noiseInside(s, st, p.room, action == 'dvr_take' and A.dvrTake or A.dvrSmash, src)
        Burglary.PushMembers(s.id, 'pointState', p.id, { dvr = st.dvr })
        return { ok = true, msg = L('dvr_' .. st.dvr) }
    elseif action == 'keypad' then
        noiseInside(s, st, p.room, A.keypad, src)
        if tostring(result.code) == st.profile.security.code then
            st.alarm.stage = 'disarmed'
            st.alarm.n = (st.alarm.n or 0) + 1
            st.siren = false
            Houses.Push(st.id)
            Burglary.PushMembers(s.id, 'alarm', { stage = 'disarmed' })
            return { ok = true, opened = true, msg = L('alarm_disarmed') }
        end
        st.alarm.tries = (st.alarm.tries or 0) + 1
        if st.alarm.tries >= 3 then Burglary.Siren(st, src) end
        return { ok = true, opened = false, msg = L('code_wrong', math.max(0, 3 - st.alarm.tries)) }
    end
    return { ok = false }
end, 200)

-- przedmiot z rąk wraca na miejsce w domu (albo przepada poza nim)
function Burglary.ReturnCarry(src, c)
    local s = sessOf(src)
    if s and c.sid == s.id and c.point then
        local st = Houses.state[s.house]
        if st then
            st.taken[c.point] = nil
            s.lootCount = math.max(0, s.lootCount - 1)
            s.value = math.max(0, s.value - (c.value or 0))
            Burglary.PushMembers(s.id, 'pointState', c.point, { taken = false })
            return true
        end
    end
    return false
end

function Burglary.DropCarry(src) return Burglary_DropCarryInternal(src) end

-- --------------------------------------------------------------------------
--  Światła i kryjówki (SKR-07, SKR-10)
-- --------------------------------------------------------------------------
SV.Register('house:light', function(src, room, on)
    local s = sessOf(src)
    if not s then return { ok = false } end
    local st = Houses.state[s.house]
    if not st or not st.power then return { ok = false, msg = L('no_power') } end
    s.lights[room] = on and true or nil
    Burglary.PushMembers(s.id, 'lights', s.lights)
    noiseInside(s, st, room, Config.Noise.actions.light, src)
    return { ok = true }
end, 400)

SV.Register('house:hide', function(src, pointId, on)
    if on then
        local s, st, p, err = insidePoint(src, pointId, 2.5)
        if not s or p.type ~= 'hide' then return { ok = false, msg = err } end
    end
    Player(src).state:set('wlmHidden', on and pointId or false, true)
    return { ok = true }
end, 500)

-- --------------------------------------------------------------------------
--  Hałas od klientów (paczki, max 4/s) – trafia do hosta AI (SKR-04, TEC-16)
-- --------------------------------------------------------------------------
local noiseAt = {}
RegisterNetEvent('dp-wlamywacz:server:noise', function(room, v)
    local src = source
    local now = GetGameTimer()
    if noiseAt[src] and now - noiseAt[src] < 200 then return end
    noiseAt[src] = now
    local s = sessOf(src)
    if not s or type(room) ~= 'string' then return end
    v = U.Clamp(tonumber(v) or 0, 0, 100)
    if v >= 10 then s.noise = s.noise + v * 0.25 end
    if s.host then SV.Client(s.host, 'aiNoise', src, room, v) end
end)

-- --------------------------------------------------------------------------
--  Host AI: encje, wykrycia, telefon na policję (NPC-09), świadkowie (NPC-21)
-- --------------------------------------------------------------------------
SV.Register('ai:spawned', function(src, list)
    local s = sessOf(src)
    if not s or s.host ~= src or type(list) ~= 'table' then return { ok = false } end
    for _, n in ipairs(list) do if type(n) == 'number' then s.netIds[#s.netIds + 1] = n end end
    return { ok = true }
end, 200)

SV.Register('ai:detect', function(src, target, level, residentIdx)
    local s = sessOf(src)
    if not s or s.host ~= src then return { ok = false } end
    target = tonumber(target)
    if target and s.members[target] then
        if level == 'alarmed' then
            s.detections = s.detections + 1
            SV.Client(target, 'notify', L('detected'), 'bad')
            if not masked(target) then
                Police.AddEvidence(s.house, { kind = 'witness', cid = SV.P(target).id, name = Bridge.GetName(target), desc = L('ev_face') })
            end
        end
        Burglary.PushMembers(s.id, 'aiLevel', residentIdx, level)
    end
    return { ok = true }
end, 100)

SV.Register('ai:witness', function(src, desc)
    local s = sessOf(src)
    if not s or s.host ~= src or type(desc) ~= 'string' then return { ok = false } end
    s.witness = desc:sub(1, 200)
    return { ok = true }
end, 500)

SV.Register('ai:call', function(src, residentIdx)
    local s = sessOf(src)
    if not s or s.host ~= src or s.call then return { ok = false } end
    local st = Houses.state[s.house]
    if not st then return { ok = false } end
    s.call = { idx = residentIdx, at = os.time(), n = (s.callN or 0) + 1 }
    s.callN = s.call.n
    local my = s.call.n
    Burglary.PushMembers(s.id, 'notify', L('resident_calling'), 'bad')
    Burglary.PushMembers(s.id, 'hud', { calling = Config.AI.phoneTime })
    SetTimeout(Config.AI.phoneTime * 1000, function()
        if sessions[s.id] == s and s.call and s.call.n == my and not s.call.cancelled then
            Burglary.Alert(st, 'call', s.host)
        end
    end)
    return { ok = true }
end, 500)

SV.Register('ai:interrupt', function(src, residentIdx, netId)
    local s = sessOf(src)
    if not s or not s.call or s.call.cancelled then return { ok = false } end
    local ped = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not ped or ped == 0 or not SV.Near(src, GetEntityCoords(ped), 2.5) then return { ok = false, msg = L('too_far') } end
    if os.time() - s.call.at > Config.AI.phoneTime then return { ok = false, msg = L('too_late') } end
    s.call.cancelled = true
    s.call = nil
    s.detections = s.detections + 1
    SV.Client(s.host, 'aiEvent', { kind = 'callStopped', idx = residentIdx })
    Burglary.PushMembers(s.id, 'hud', { calling = false })
    return { ok = true, msg = L('call_stopped') }
end, 500)

SV.Register('cam:spotted', function(src, camId)
    local s = sessOf(src)
    if not s then return { ok = false } end
    local st = Houses.state[s.house]
    if not st or st.dvr ~= 'ok' or not st.power then return { ok = false } end
    if not s.spotted[src] then
        s.spotted[src] = { masked = masked(src), cam = camId }
        SV.Client(src, 'notify', L('camera_spotted'), 'warn')
        if st.profile.security.sub == 'reaction' and not s.police then Burglary.Alert(st, 'security', src) end
    end
    return { ok = true }
end, 1000)

-- --------------------------------------------------------------------------
--  Zdarzenia losowe (ZLE-08) i chciwość (LUP-22): szansa rośnie z czasem w środku
-- --------------------------------------------------------------------------
local function randomEvent(s, st)
    local mins = (os.time() - s.started) / 60
    local chance = Config.Events.base + Config.Events.perMinute * mins
    if math.random() > chance then return end
    local list = {}
    local anyAsleep, anyHome = false, false
    for _, status in pairs(s.present) do
        anyHome = true
        if status == 'asleep' then anyAsleep = true end
    end
    for _, ev in ipairs(Config.Events.list) do
        local ok = (ev.key == 'phone') or (ev.key == 'toilet' and anyAsleep) or (ev.key == 'return' and not anyHome and not s.returned) or (ev.key == 'power' and #st.profile.security.cameras > 0)
        if ok then list[#list + 1] = { ev.key, ev.weight } end
    end
    local key = U.PickWeighted(function() return math.random() end, list)
    if not key then return end
    if key == 'return' then s.returned = true end
    if key == 'power' then
        st.camsOffUntil = os.time() + 60
        Burglary.PushMembers(s.id, 'camsOff', 60)
    end
    Burglary.PushMembers(s.id, 'notify', L('event_' .. key), 'warn')
    if s.host then SV.Client(s.host, 'aiEvent', { kind = key }) end
end

-- --------------------------------------------------------------------------
--  Koniec sesji: ocena S–F, XP, heat, raport (SKR-23, PRO-06, UIX-14)
-- --------------------------------------------------------------------------
function Burglary.End(s, reason)
    if not sessions[s.id] then return end
    sessions[s.id] = nil
    local st = Houses.state[s.house]
    for m in pairs(s.members) do
        bySrc[m] = nil
        SetPlayerRoutingBucket(m, 0)
        Player(m).state:set('wlmInside', false, true)
        if st then
            local e = st.cfg.entries[1].coords
            SV.Client(m, 'forceExit', { x = e.x, y = e.y, z = e.z, w = e.w })
        end
        s.done = s.done or {}
        s.done[m] = true
    end
    for _, n in ipairs(s.netIds) do
        local ent = NetworkGetEntityFromNetworkId(n)
        if ent and ent ~= 0 and DoesEntityExist(ent) then DeleteEntity(ent) end
    end
    if not st then return end
    st.sid = nil

    -- nagrania: jeśli rejestrator został, kamera zapamiętała wszystkich, których widziała
    local footage = false
    if st.dvr == 'ok' then
        for src, sp in pairs(s.spotted) do
            footage = true
            Police.AddEvidence(st.id, {
                kind = 'footage', cid = not sp.masked and SV.P(src).id or nil,
                name = not sp.masked and Bridge.GetName(src) or nil, desc = sp.masked and L('ev_masked') or L('ev_face'),
            })
        end
    end
    s.footage = footage
    -- auto stojące długo pod domem zapisał sąsiad (LOG-14)
    if s.vehicle and (os.time() - s.started) > 240 then
        Police.AddEvidence(st.id, { kind = 'vehicle', desc = s.vehicle })
    end

    local P = Config.Rating.penalty
    local minutes = (os.time() - s.started) / 60
    local score = 100 - math.min(30, s.noise * P.noise) - s.detections * P.detected - (s.alarm and P.alarm or 0)
        - s.prints * P.fingerprint - (footage and P.footage or 0) - math.max(0, minutes - 5) * P.minute - (s.policeArrived and P.police or 0)
    if s.lootCount == 0 then score = score - (P.empty or 25) end   -- pusty skok to nie jest czysta robota
    score = math.floor(U.Clamp(score, 0, 100))
    local grade = U.Grade(score)

    local heat = Config.Heat.add.quiet
    if s.detections > 0 then heat = heat + Config.Heat.add.noticed end
    if s.alarm then heat = heat + Config.Heat.add.alarm end
    Police.AddDistrictHeat(st.cfg.district, heat / 2)

    local xpBase = (Config.XP.perHouse[st.cfg.tier] or 50) * (Config.XP.grade[grade] or 1) + s.lootCount * 3
    for src in pairs(s.done or {}) do
        if GetPlayerName(src) then
            local prof = Progress.Get(src)
            if prof then
                prof.stats.houses = (prof.stats.houses or 0) + 1
                prof.stats.loot = (prof.stats.loot or 0) + s.value
                if not prof.stats.best or score > prof.stats.best then prof.stats.best = score end
                Store.Touch(prof.id)
            end
            local xp = math.floor(xpBase)
            Progress.AddXP(src, xp, 'wlamanie')
            Progress.AddHeat(src, heat)
            SV.Client(src, 'report', {
                grade = grade, score = score, time = math.floor(minutes * 60), items = s.lootCount, value = s.value,
                noise = math.floor(s.noise), detections = s.detections, prints = s.prints, alarm = s.alarm,
                police = s.police, footage = footage, xp = xp, house = st.cfg.label,
            })
            Contracts.Hook(src, 'burglary', { house = st.id, grade = grade, tier = st.cfg.tier })
        end
    end
    SV.Log('wlamanie', ('%s: ocena %s (%d), łup %d szt. ~%d$, powód: %s'):format(st.cfg.label, grade, score, s.lootCount, s.value, reason))
    Houses.Finish(st.id)
end

-- pilnowanie sesji: limit czasu i zdarzenia losowe
CreateThread(function()
    while true do
        Wait(Config.Events.checkEvery * 1000)
        local now = os.time()
        for _, s in pairs(sessions) do
            local st = Houses.state[s.house]
            if not st or now - s.started > Config.Cooldowns.sessionTimeout then
                Burglary.End(s, 'timeout')
            else
                randomEvent(s, st)
            end
        end
    end
end)

AddEventHandler('dp-wlamywacz:internal:dropped', function(src)
    local s = sessOf(src)
    Carry[src] = nil
    if s then
        leave(src, s, Houses.state[s.house], true)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, s in pairs(sessions) do
        for m in pairs(s.members) do SetPlayerRoutingBucket(m, 0) end
        for _, n in ipairs(s.netIds) do
            local ent = NetworkGetEntityFromNetworkId(n)
            if ent and ent ~= 0 and DoesEntityExist(ent) then DeleteEntity(ent) end
        end
    end
end)

-- --------------------------------------------------------------------------
--  Hałas na zewnątrz domu: budzi domowników jeszcze przed wejściem (NPC-04), a klient
--  sprawcy sprawdza, czy widzieli to przechodnie (NPC-18)
-- --------------------------------------------------------------------------
AddEventHandler('dp-wlamywacz:internal:worldNoise', function(st, coords, value, src, minute)
    if not st or not value then return end
    minute = minute or 720
    if src and value >= 40 then SV.Client(src, 'worldNoise', value, { x = coords.x, y = coords.y, z = coords.z }, st.id) end
    local s = st.sid and sessions[st.sid]
    if s then
        if s.host then SV.Client(s.host, 'aiNoise', src or 0, '__outside', value * 0.5) end
        return
    end
    local heard = value * 0.5
    st.woken = st.woken or {}
    for _, p in ipairs(Profile.Present(st.profile, minute)) do
        local r = st.profile.residents[p.idx]
        local th
        if p.status == 'awake' then th = Config.AI.hearing.awake
        else th = Profile.SleepDepth(r, minute) > 0.45 and Config.AI.hearing.deep or Config.AI.hearing.light end
        if heard >= th then st.woken[p.idx] = true end
    end
    -- zbita szyba w nocy przy domownikach: dzwonią na policję, zanim ktokolwiek wejdzie
    if next(st.woken) and value >= 80 and not st.preCall then
        st.preCall = true
        SetTimeout(15000, function()
            if Houses.state[st.id] == st then Burglary.Alert(st, 'call', src) end
        end)
    end
end)

-- przechodnie widzieli coś głośnego (NPC-18, NPC-21): klient podaje liczbę świadków i opis
SV.Register('witness:report', function(src, houseId, count, desc)
    local st = Houses.state[houseId]
    count = math.floor(U.Clamp(tonumber(count) or 0, 0, 10))
    if not st or count <= 0 then return { ok = false } end
    if st.witnessAt and os.time() - st.witnessAt < 60 then return { ok = false } end
    if math.random() < 1 - 0.7 ^ count then
        st.witnessAt = os.time()
        if type(desc) == 'string' then
            st.witnessDesc = desc:sub(1, 200)
            local s = st.sid and sessions[st.sid]
            if s then s.witness = st.witnessDesc end
        end
        Burglary.Alert(st, 'witness', src)
        Progress.AddHeat(src, Config.Heat.add.witness)
        return { ok = true, reported = true }
    end
    return { ok = true }
end, 3000)

-- auto sprawcy zaparkowane pod domem (LOG-14)
SV.Register('witness:vehicle', function(src, desc)
    local s = sessOf(src)
    if not s or type(desc) ~= 'string' then return { ok = false } end
    s.vehicle = desc:sub(1, 120)
    return { ok = true }
end, 2000)
