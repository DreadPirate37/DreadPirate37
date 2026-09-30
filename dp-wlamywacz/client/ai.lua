-- ==========================================================================
--  AI domowników (NPC). Liczy ją wyłącznie host ekipy (NPC-27): jeden koordynator na dom co
--  250 ms (NPC-26), pedy dostają natywne taski, a stan trafia do statebagów encji.
--  Percepcja „najtańsze najpierw”: dystans² → stożek → asynchroniczny raycast (TEC-15).
-- ==========================================================================
local AI = { running = false, res = {}, dog = nil, queue = {}, members = {}, membersAt = 0 }
local SLEEP_DICT, SLEEP_CLIP = 'timetable@tracy@sleep@', 'idle_c'
local U, N, P = WLM.U, WLM.Noise, WLM.Profile

local function tpl() return Config.Interiors[W.session.interior] end
local function wpos(p) return U.Rel(W.session.origin, p.pos) end

local function roomCenter(roomId)
    for _, r in ipairs(tpl().rooms) do
        if r.id == roomId then
            local c = vector3((r.min.x + r.max.x) / 2, (r.min.y + r.max.y) / 2, r.min.z + 0.6)
            return U.Rel(W.session.origin, c)
        end
    end
end

local function roomOf(ped)
    local c = GetEntityCoords(ped)
    local o = W.session.origin
    return N.RoomAt(W.session.interior, vector3(c.x - o.x, c.y - o.y, c.z - o.z))
end

local function points(kind)
    local out = {}
    for _, p in ipairs(tpl().points) do if p.type == kind then out[#out + 1] = p end end
    return out
end

local function setLvl(r, lvl)
    if r.lvl == lvl then return end
    r.lvl = lvl
    Entity(r.ped).state:set('wlmLvl', lvl, true)
end

local function idleAt(r, spot) end

local function sleepAt(r, bed)
    if not bed then return idleAt(r, r.sit) end
    local c = wpos(bed)
    SetEntityCoordsNoOffset(r.ped, c.x, c.y, c.z, false, false, false)
    SetEntityHeading(r.ped, bed.pos.w or 0.0)
    if W.LoadDict(SLEEP_DICT) then TaskPlayAnim(r.ped, SLEEP_DICT, SLEEP_CLIP, 8.0, -8.0, -1, 1, 0, false, false, false) end
    r.state = 'asleep'
    Entity(r.ped).state:set('wlmSt', 'asleep', true)
    setLvl(r, 'calm')
end

idleAt = function(r, spot)
    if spot then
        local c = wpos(spot)
        TaskStartScenarioAtPosition(r.ped, 'PROP_HUMAN_SEAT_CHAIR_MP_PLAYER', c.x, c.y, c.z + 0.45, spot.pos.w or 0.0, -1, true, true)
    else
        TaskStartScenarioInPlace(r.ped, 'WORLD_HUMAN_STAND_MOBILE', 0, true)
    end
    r.state = 'awake'
    Entity(r.ped).state:set('wlmSt', 'awake', true)
    setLvl(r, 'calm')
end

local function goTo(r, c)
    TaskGoToCoordAnyMeans(r.ped, c.x, c.y, c.z, 1.0, 0, false, 786603, 0xbf800000)
end

-- --------------------------------------------------------------------------
--  Start / stop
-- --------------------------------------------------------------------------
local function spawnPed(model, c, heading, net)
    local hash = W.LoadModel(model)
    if not hash then return nil end
    local ped = CreatePed(4, hash, c.x, c.y, c.z, heading, net, true)
    SetModelAsNoLongerNeeded(hash)
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCanPlayAmbientAnims(ped, true)
    return ped
end

function W.StartAI(s)
    if AI.running then return end
    AI.running = true
    AI.res, AI.queue, AI.dog = {}, {}, nil
    local profile = W.Profile(s.house)
    if not profile then AI.running = false return end
    AI.profile = profile
    local beds, sits = points('bed'), points('sit')
    local nets = {}
    local bi, si = 1, 1
    for idx, status in pairs(s.present or {}) do
        idx = tonumber(idx)
        local r = profile.residents[idx]
        if r then
            local rec = { idx = idx, r = r, sus = 0, lvl = nil, seen = {}, t = 0 }
            local bed = beds[((bi - 1) % math.max(1, #beds)) + 1]
            local sit = sits[((si - 1) % math.max(1, #sits)) + 1]
            rec.bed, rec.sit = bed, sit
            local spot = (status == 'asleep') and bed or sit
            if spot then
                local c = wpos(spot)
                rec.ped = spawnPed(r.model, c, spot.pos.w or 0.0, true)
            end
            if rec.ped then
                Entity(rec.ped).state:set('wlmRes', idx, true)
                if status == 'asleep' and bed then sleepAt(rec, bed) bi = bi + 1
                else
                    idleAt(rec, sit) si = si + 1
                    if status == 'woken' then rec.sus = Config.AI.suspicion.suspicious + 10 rec.state = 'investigate' rec.target = roomCenter(tpl().rooms[1].id) end
                end
                AI.res[#AI.res + 1] = rec
                nets[#nets + 1] = NetworkGetNetworkIdFromEntity(rec.ped)
            end
        end
    end
    if profile.dog then
        local p = U.FindPoint(tpl(), profile.dog.point)
        if p then
            local c = wpos(p)
            local dog = spawnPed(profile.dog.model, c, p.pos.w or 0.0, true)
            if dog then
                Entity(dog).state:set('wlmRes', 0, true)
                TaskWanderInArea(dog, c.x, c.y, c.z, 2.5, 2, 5.0)
                AI.dog = { ped = dog, big = profile.dog.big, barkAt = 0, bit = false }
                nets[#nets + 1] = NetworkGetNetworkIdFromEntity(dog)
            end
        end
    end
    W.Callback('ai:spawned', nets)
    CreateThread(function() AI.Loop() end)
end

function W.StopAI()
    AI.running = false
    AI.res, AI.queue, AI.dog = {}, {}, nil
end

-- przejęcie hosta (NPC-27): nowy host przejmuje istniejące pedy
RegisterNetEvent('dp-wlamywacz:client:aiHost', function(nets)
    if not W.session or AI.running then return end
    W.session.host = true
    AI.running = true
    AI.res, AI.queue = {}, {}
    AI.profile = W.Profile(W.session.house)
    local beds, sits = points('bed'), points('sit')
    for _, n in ipairs(nets or {}) do
        local ped = NetworkGetEntityFromNetworkId(n)
        if ped and ped ~= 0 and DoesEntityExist(ped) then
            NetworkRequestControlOfEntity(ped)
            local idx = Entity(ped).state.wlmRes
            if idx == 0 then
                AI.dog = { ped = ped, big = AI.profile.dog and AI.profile.dog.big, barkAt = 0 }
            elseif idx then
                local rec = { idx = idx, r = AI.profile.residents[idx], ped = ped, sus = 0, seen = {}, t = 0, bed = beds[1], sit = sits[1] }
                rec.state = Entity(ped).state.wlmSt or 'awake'
                rec.lvl = Entity(ped).state.wlmLvl
                AI.res[#AI.res + 1] = rec
            end
        end
    end
    CreateThread(function() AI.Loop() end)
end)

-- --------------------------------------------------------------------------
--  Hałas (SKR-04): kolejka zdarzeń przetwarzana w ticku
-- --------------------------------------------------------------------------
function W.AINoise(src, room, v)
    if not AI.running then return end
    AI.queue[#AI.queue + 1] = { src = src, room = room, v = v }
end

RegisterNetEvent('dp-wlamywacz:client:aiNoise', function(src, room, v)
    if room == '__outside' and W.session then
        local sp = tpl().spawns.front
        room = N.RoomAt(W.session.interior, vector3(sp.x, sp.y, sp.z + 0.5)) or tpl().rooms[1].id
    end
    W.AINoise(src, room, v)
end)

local function threshold(rec, minute)
    if rec.state == 'asleep' then
        local deep = P.SleepDepth(rec.r, minute) > 0.45 and not (rec.lightUntil and GetGameTimer() < rec.lightUntil)
        return deep and Config.AI.hearing.deep or Config.AI.hearing.light
    end
    return Config.AI.hearing.awake
end

local function hear(minute)
    if #AI.queue == 0 then return end
    local q = AI.queue
    AI.queue = {}
    for _, ev in ipairs(q) do
        local heard = N.Propagate(W.session.interior, ev.room, ev.v)
        for _, rec in ipairs(AI.res) do
            if rec.ped and not rec.room then rec.room = roomOf(rec.ped) end
            if rec.ped and rec.room then
                local rv = heard[rec.room] or 0
                local th = threshold(rec, minute)
                if rv >= th then
                    if rec.state == 'asleep' then
                        rec.state = 'woken'
                        rec.t = GetGameTimer() + 2500
                        rec.sus = math.max(rec.sus, Config.AI.suspicion.suspicious + (rv - th))
                        ClearPedTasks(rec.ped)
                        Entity(rec.ped).state:set('wlmSt', 'woken', true)
                    else
                        rec.sus = math.min(99, rec.sus + (rv - th) * 2.0)
                    end
                    rec.heardRoom = ev.room
                    rec.heardSrc = ev.src
                end
            end
        end
    end
end

-- --------------------------------------------------------------------------
--  Wzrok (NPC-05): dystans² → stożek → raycast asynchroniczny (wynik w następnym ticku)
-- --------------------------------------------------------------------------
local function members()
    local now = GetGameTimer()
    if now - AI.membersAt < 1000 then return AI.members end
    AI.membersAt = now
    local list = {}
    for _, pid in ipairs(GetActivePlayers()) do
        local sid = GetPlayerServerId(pid)
        if Player(sid).state.wlmInside == W.session.house then list[#list + 1] = { sid = sid, ped = GetPlayerPed(pid) } end
    end
    AI.members = list
    return list
end

local cosHalf = math.cos(math.rad(Config.AI.sight.fov / 2))
local function see(rec, dt)
    if rec.state == 'asleep' or rec.state == 'calling' or rec.state == 'cower' then return end
    local ped = rec.ped
    local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
    local fwd = GetEntityForwardVector(ped)
    -- odbierz wynik zeszłego raycastu
    if rec.ray then
        local st, hit = GetShapeTestResult(rec.ray)
        if st == 2 then
            if hit == 0 and rec.rayTarget then
                local m = rec.rayTarget
                local vis = (Player(m.sid).state.wlmVis or 30) / 100
                rec.sus = rec.sus + Config.AI.suspicion.rise * dt * (0.4 + vis)
                rec.seen[m.sid] = true
                rec.lastSeen = m
            end
            rec.ray, rec.rayTarget = nil, nil
        elseif st == 0 then
            rec.ray, rec.rayTarget = nil, nil
        end
    end
    if rec.ray then return end
    for _, m in ipairs(members()) do
        if DoesEntityExist(m.ped) and not Player(m.sid).state.wlmHidden then
            local tc = GetEntityCoords(m.ped)
            local d = tc - head
            local dist2 = d.x * d.x + d.y * d.y + d.z * d.z
            local vis = (Player(m.sid).state.wlmVis or 30) / 100
            local range = U.Lerp(Config.AI.sight.dark, Config.AI.sight.lit, vis)
            if dist2 < range * range then
                local dist = math.sqrt(dist2)
                local dot = (d.x * fwd.x + d.y * fwd.y) / math.max(0.01, math.sqrt(d.x * d.x + d.y * d.y))
                if dot > cosHalf or dist < 1.2 then
                    local to = GetPedBoneCoords(m.ped, 24818, 0.0, 0.0, 0.0)
                    rec.ray = StartShapeTestLosProbe(head.x, head.y, head.z, to.x, to.y, to.z, 1 + 16, ped, 4)
                    rec.rayTarget = m
                    return
                end
            end
        end
    end
end

-- --------------------------------------------------------------------------
--  Stany i reakcje (NPC-03, NPC-09)
-- --------------------------------------------------------------------------
local function report(rec, target, level)
    CreateThread(function() W.Callback('ai:detect', target, level, rec.idx) end)
end

local function alarm(rec)
    if rec.state == 'calling' or rec.state == 'cower' then return end
    setLvl(rec, 'alarm')
    local target = rec.lastSeen and rec.lastSeen.sid or rec.heardSrc
    if rec.lastSeen and DoesEntityExist(rec.lastSeen.ped) then
        local desc = W.DescribePed(rec.lastSeen.ped)
        CreateThread(function() W.Callback('ai:witness', desc) end)
    end
    if target then report(rec, target, 'alarmed') end
    -- NPC-09: telefon na policję, który można przerwać (5–8 s)
    local calling = false
    for _, o in ipairs(AI.res) do if o.state == 'calling' then calling = true end end
    if not calling then
        rec.state = 'calling'
        Entity(rec.ped).state:set('wlmSt', 'calling', true)
        setLvl(rec, 'call')
        ClearPedTasks(rec.ped)
        TaskStartScenarioInPlace(rec.ped, 'WORLD_HUMAN_STAND_MOBILE', 0, true)
        rec.t = GetGameTimer() + Config.AI.phoneTime * 1000
        CreateThread(function() W.Callback('ai:call', rec.idx) end)
    else
        rec.state = 'cower'
        ClearPedTasks(rec.ped)
        TaskCower(rec.ped, -1)
    end
end

local function step(rec, dt, now, minute)
    local s = Config.AI.suspicion
    rec.room = roomOf(rec.ped)
    see(rec, dt)
    if rec.sus >= s.alarmed and rec.state ~= 'calling' and rec.state ~= 'cower' then alarm(rec) return end
    if rec.state == 'woken' then
        if now > rec.t then
            if rec.sus >= s.suspicious then
                rec.state = 'investigate'
                rec.target = roomCenter(rec.heardRoom or rec.room)
                rec.t = now + Config.AI.investigate * 1000
                if rec.target then goTo(rec, rec.target) end
                -- domownik zapala światło w pokoju, do którego idzie (SKR-07)
                if rec.heardRoom and not W.session.lights[rec.heardRoom] then CreateThread(function() W.Callback('house:light', rec.heardRoom, true) end) end
                setLvl(rec, 'sus')
                if rec.heardSrc then report(rec, rec.heardSrc, 'suspicious') end
            else
                rec.lightUntil = now + 60000
                sleepAt(rec, rec.bed)
            end
        end
    elseif rec.state == 'awake' then
        if rec.sus >= s.suspicious then
            rec.state = 'investigate'
            rec.target = roomCenter(rec.heardRoom or rec.room)
            rec.t = now + Config.AI.investigate * 1000
            if rec.target then goTo(rec, rec.target) end
            setLvl(rec, 'sus')
            if rec.heardSrc then report(rec, rec.heardSrc, 'suspicious') end
        end
    elseif rec.state == 'investigate' then
        if rec.heardRoom and rec.target and rec.newRoom ~= rec.heardRoom then
            rec.newRoom = rec.heardRoom
            rec.target = roomCenter(rec.heardRoom)
            goTo(rec, rec.target)
        end
        if rec.target and #(GetEntityCoords(rec.ped) - rec.target) < 1.6 and not rec.looking then
            rec.looking = true
            TaskStartScenarioInPlace(rec.ped, 'WORLD_HUMAN_GUARD_STAND', 0, true)
        end
        if now > rec.t then
            rec.looking, rec.newRoom, rec.heardRoom = false, nil, nil
            rec.sus = math.min(rec.sus, s.suspicious - 5)
            rec.state = 'return'
            local home = (P.Status(rec.r, minute) == 'asleep' and rec.bed) or rec.sit or rec.bed
            rec.home = home
            if home then goTo(rec, wpos(home)) end
            rec.t = now + 20000
        end
    elseif rec.state == 'return' or rec.state == 'trip_back' then
        if rec.home and (#(GetEntityCoords(rec.ped) - wpos(rec.home)) < 1.5 or now > rec.t) then
            if rec.home.type == 'bed' then rec.lightUntil = now + 90000 sleepAt(rec, rec.home) else idleAt(rec, rec.home) end
        end
    elseif rec.state == 'trip' then
        if now > rec.t then
            rec.state = 'trip_back'
            rec.home = rec.bed
            if rec.bed then goTo(rec, wpos(rec.bed)) end
            rec.t = now + 20000
        end
    elseif rec.state == 'calling' then
        if now > rec.t then
            rec.state = 'cower'
            ClearPedTasks(rec.ped)
            TaskCower(rec.ped, -1)
        end
    elseif rec.state == 'asleep' then
        -- nocne wyjście do toalety (NPC-07 / archetyp emeryta)
        if rec.r.nightTrip and math.abs(minute - rec.r.nightTrip) < 2 and not rec.tripDone then
            rec.tripDone = true
            W.StartTrip(rec)
        end
    end
    if rec.state ~= 'investigate' and rec.state ~= 'woken' then
        rec.sus = math.max(0, rec.sus - s.fall * dt)
        if rec.lvl == 'sus' and rec.sus < s.suspicious * 0.5 and rec.state ~= 'calling' then setLvl(rec, 'calm') end
    end
end

function W.StartTrip(rec)
    local visit = points('visit')[1]
    if not visit or not rec.ped then return end
    ClearPedTasks(rec.ped)
    rec.state = 'trip'
    rec.t = GetGameTimer() + 30000
    Entity(rec.ped).state:set('wlmSt', 'trip', true)
    goTo(rec, wpos(visit))
end

-- pies (NPC-13): węszy, szczeka i budzi dom; duży może ugryźć
local function dogStep(now)
    local d = AI.dog
    if not d or not DoesEntityExist(d.ped) then return end
    local dc = GetEntityCoords(d.ped)
    local droom = roomOf(d.ped)
    for _, m in ipairs(members()) do
        if DoesEntityExist(m.ped) and not Player(m.sid).state.wlmHidden then
            local dist = #(GetEntityCoords(m.ped) - dc)
            if dist < Config.AI.dog.smell then
                if now > d.barkAt then
                    d.barkAt = now + 1500
                    PlayAnimalVocalization(d.ped, 3, 'BARK')
                    if droom then W.AINoise(m.sid, droom, 60) end
                    TaskTurnPedToFaceEntity(d.ped, m.ped, 1000)
                end
                if d.big and Config.AI.dog.attack and dist < 2.0 and not d.bit then
                    d.bit = true
                    TaskCombatPed(d.ped, m.ped, 0, 16)
                end
                return
            end
        end
    end
end

-- --------------------------------------------------------------------------
--  Pętla koordynatora
-- --------------------------------------------------------------------------
function AI.Loop()
    local last = GetGameTimer()
    while AI.running and W.session do
        local now = GetGameTimer()
        local dt = (now - last) / 1000
        last = now
        local minute = W.Minute()
        hear(minute)
        for _, rec in ipairs(AI.res) do
            if rec.ped and DoesEntityExist(rec.ped) and not IsPedDeadOrDying(rec.ped, true) then step(rec, dt, now, minute) end
        end
        dogStep(now)
        Wait(Config.AI.tick)
    end
end

-- --------------------------------------------------------------------------
--  Zdarzenia z serwera (ZLE-08, ZAB-18, ZAB-25)
-- --------------------------------------------------------------------------
RegisterNetEvent('dp-wlamywacz:client:aiEvent', function(ev)
    if not AI.running or not W.session then return end
    local kind = ev.kind
    if kind == 'siren' then
        for _, rec in ipairs(AI.res) do rec.sus = 100 end
    elseif kind == 'power' then
        for _, rec in ipairs(AI.res) do
            if rec.state == 'asleep' and P.SleepDepth(rec.r, W.Minute()) < 0.45 then
                rec.state = 'woken' rec.t = GetGameTimer() + 2500 rec.sus = Config.AI.suspicion.suspicious + 5
                rec.heardRoom = tpl().rooms[1].id
                ClearPedTasks(rec.ped)
            end
        end
    elseif kind == 'phone' then
        W.AINoise(0, tpl().rooms[1].id, 50)
    elseif kind == 'toilet' then
        for _, rec in ipairs(AI.res) do
            if rec.state == 'asleep' then W.StartTrip(rec) break end
        end
    elseif kind == 'return' then
        local r = AI.profile.residents[1]
        local sp = tpl().spawns.front
        local c = vector3(W.session.origin.x + sp.x, W.session.origin.y + sp.y, W.session.origin.z + sp.z)
        SetTimeout(30000, function()
            if not AI.running then return end
            local ped = spawnPed(r.model, c, sp.w, true)
            if not ped then return end
            Entity(ped).state:set('wlmRes', 1, true)
            local rec = { idx = 1, r = r, ped = ped, sus = 0, seen = {}, t = 0, bed = points('bed')[1], sit = points('sit')[1] }
            AI.res[#AI.res + 1] = rec
            W.Callback('ai:spawned', { NetworkGetNetworkIdFromEntity(ped) })
            -- ślady włamania na wejściu od razu go niepokoją
            local hs = W.houseState[W.session.house]
            local broken = false
            if hs then for _, e in pairs(hs.entries or {}) do if e.broken then broken = true end end end
            rec.sus = broken and 80 or 10
            rec.state = 'awake'
            rec.heardRoom = N.RoomAt(W.session.interior, vector3(sp.x, sp.y, sp.z + 0.5))
            if rec.sit then goTo(rec, wpos(rec.sit)) end
        end)
    elseif kind == 'callStopped' then
        for _, rec in ipairs(AI.res) do
            if rec.idx == ev.idx then rec.state = 'cower' ClearPedTasks(rec.ped) TaskCower(rec.ped, -1) setLvl(rec, 'alarm') end
        end
    end
end)

-- --------------------------------------------------------------------------
--  Dla wszystkich w domu: poziom zaniepokojenia na HUD i przerwanie telefonu (NPC-09)
-- --------------------------------------------------------------------------
function W.InterruptCall(ped)
    local idx = Entity(ped).state.wlmRes
    if not idx then return end
    W.Call('ai:interrupt', idx, NetworkGetNetworkIdFromEntity(ped))
end

CreateThread(function()
    Wait(1500)
    local label = L('interrupt_call')
    if W.targetMode == 'ox' then
        exports.ox_target:addGlobalPed({ {
            name = 'wlm_interrupt', label = label, icon = 'fa-solid fa-phone-slash', distance = 2.0,
            canInteract = function(entity) return W.session ~= nil and Entity(entity).state.wlmLvl == 'call' end,
            onSelect = function(data) CreateThread(function() W.InterruptCall(data.entity) end) end,
        } })
    elseif W.targetMode == 'qb' then
        exports['qb-target']:AddGlobalPed({
            options = { {
                icon = 'fas fa-phone-slash', label = label,
                canInteract = function(entity) return W.session ~= nil and Entity(entity).state.wlmLvl == 'call' end,
                action = function(entity) CreateThread(function() W.InterruptCall(entity) end) end,
            } },
            distance = 2.0,
        })
    end
    while true do
        local sleep = 1000
        if W.session then
            sleep = 500
            local best = 'calm'
            local rank = { calm = 0, sus = 1, alarm = 2, call = 3 }
            local calling
            for _, ped in ipairs(W.residentPeds) do
                if DoesEntityExist(ped) then
                    local l = Entity(ped).state.wlmLvl or 'calm'
                    if (rank[l] or 0) > (rank[best] or 0) then best = l end
                    if l == 'call' then calling = ped end
                end
            end
            W.Hud({ alert = best })
            if not W.targetMode and calling and #(GetEntityCoords(calling) - GetEntityCoords(PlayerPedId())) < 1.8 then
                sleep = 0
                W.Help('~INPUT_CONTEXT~ ' .. label)
                if IsControlJustReleased(0, 38) then W.InterruptCall(calling) end
            end
        end
        Wait(sleep)
    end
end)

RegisterNetEvent('dp-wlamywacz:client:aiLevel', function(idx, level)
    if level == 'alarmed' then SendNUIMessage({ action = 'sound', kind = 'alert' })
    elseif level == 'suspicious' then SendNUIMessage({ action = 'sound', kind = 'sus' }) end
end)
