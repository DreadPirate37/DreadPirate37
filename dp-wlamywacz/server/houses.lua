-- ==========================================================================
--  Domy: pula i rotacja celów (DOM-16), stan i cooldown (DOM-09), blokada „jeden dom –
--  jedna ekipa” (DOM-24), szopy (DOM-11). Klienci dostają tylko listę { id = seed } aktywnych
--  celów, a stan domu wyłącznie wtedy, gdy są w pobliżu (obserwatorzy).
-- ==========================================================================
Houses = { state = {}, sheds = {} }
local U, Profile = WLM.U, WLM.Profile
local watchers = {}                -- [houseId] = { [src] = true }
local rotationAt = 0

local function cooldownDoc() return Store.Doc('cooldowns', {}) end

function Houses.OnCooldown(id)
    return (cooldownDoc()[id] or 0) > os.time()
end

local function newState(house, seed)
    local st = {
        id = house.id, cfg = house, seed = seed, since = os.time(),
        profile = Profile.Build(house, seed),
        entries = {}, keyTaken = false, gateOpen = false,
        searched = {}, taken = {}, lights = {},
        power = true, powerOffAt = nil,
        alarm = { stage = 'idle' },
        dvr = 'ok', siren = false,
        sid = nil,
    }
    for _, e in ipairs(house.entries) do
        local pe = st.profile.entries[e.id] or {}
        st.entries[e.id] = { open = pe.state == 'open', broken = false, state = pe.state, lock = pe.lock }
    end
    return st
end

-- stan widoczny z zewnątrz, wysyłany obserwatorom (mały, bez profilu)
function Houses.Public(id)
    local st = Houses.state[id]
    if not st then return nil end
    local e = {}
    for eid, v in pairs(st.entries) do e[eid] = { open = v.open, broken = v.broken, state = v.state } end
    return { entries = e, power = st.power, siren = st.siren, keyTaken = st.keyTaken, gateOpen = st.gateOpen, busy = st.sid ~= nil }
end

function Houses.Push(id)
    local pub = Houses.Public(id)
    local w = watchers[id]
    if w then
        for src in pairs(w) do TriggerClientEvent('dp-wlamywacz:client:houseState', src, id, pub) end
    end
    local st = Houses.state[id]
    if st and st.sid then Burglary.PushMembers(st.sid, 'houseState', id, pub) end
end

function Houses.ActiveList()
    local out = {}
    for id, st in pairs(Houses.state) do out[id] = st.seed end
    return out
end

local function broadcast()
    TriggerClientEvent('dp-wlamywacz:client:houses', -1, Houses.ActiveList(), Houses.ShedList())
end

-- --------------------------------------------------------------------------
--  Rotacja puli: aktywne domy z trwającym włamaniem zostają, reszta się wymienia
-- --------------------------------------------------------------------------
function Houses.Rotate()
    local keep = {}
    for id, st in pairs(Houses.state) do
        if st.sid then keep[id] = st end
    end
    local candidates = {}
    for _, h in ipairs(Config.Houses) do
        if not keep[h.id] and not Houses.OnCooldown(h.id) and Config.Interiors[h.interior] then
            candidates[#candidates + 1] = h
        end
    end
    for i = #candidates, 2, -1 do
        local j = math.random(i)
        candidates[i], candidates[j] = candidates[j], candidates[i]
    end
    Houses.state = keep
    local n = 0
    for _ in pairs(keep) do n = n + 1 end
    for _, h in ipairs(candidates) do
        if n >= Config.Rotation.active then break end
        local seed = U.Hash(('%s:%d:%d'):format(h.id, os.time(), math.random(1, 1e9)))
        Houses.state[h.id] = newState(h, seed)
        n = n + 1
    end
    rotationAt = os.time()
    broadcast()
    SV.Debug('rotacja domów, aktywne:', n)
end

-- dom po włamaniu: cooldown i od razu zastępstwo w puli
function Houses.Finish(id)
    local doc = cooldownDoc()
    doc[id] = os.time() + Config.Cooldowns.house
    Store.TouchDoc('cooldowns')
    Houses.state[id] = nil
    for _, h in ipairs(Config.Houses) do
        if not Houses.state[h.id] and not Houses.OnCooldown(h.id) and h.id ~= id and Config.Interiors[h.interior] then
            local seed = U.Hash(('%s:%d:%d'):format(h.id, os.time(), math.random(1, 1e9)))
            Houses.state[h.id] = newState(h, seed)
            break
        end
    end
    broadcast()
end

-- --------------------------------------------------------------------------
--  Szopy i garaże (DOM-11)
-- --------------------------------------------------------------------------
function Houses.ShedList()
    local out = {}
    for _, s in ipairs(Config.Sheds) do
        local st = Houses.sheds[s.id]
        out[s.id] = { open = st and st.open or false, cooldown = Houses.OnCooldown(s.id) }
    end
    return out
end

function Houses.Shed(id)
    local st = Houses.sheds[id]
    if not st then
        st = { open = false, searched = false }
        Houses.sheds[id] = st
    end
    return st
end

function Houses.FinishShed(id)
    Houses.sheds[id] = nil
    local doc = cooldownDoc()
    doc[id] = os.time() + math.floor(Config.Cooldowns.house / 2)
    Store.TouchDoc('cooldowns')
    broadcast()
end

-- --------------------------------------------------------------------------
--  Obserwatorzy (klient w pobliżu domu dostaje stan i jego zmiany)
-- --------------------------------------------------------------------------
SV.Register('house:watch', function(src, id, on)
    if not Houses.state[id] then return { ok = false } end
    watchers[id] = watchers[id] or {}
    watchers[id][src] = on and true or nil
    return { ok = true, state = on and Houses.Public(id) or nil }
end, 100)

AddEventHandler('dp-wlamywacz:internal:dropped', function(src)
    for _, w in pairs(watchers) do w[src] = nil end
end)

-- --------------------------------------------------------------------------
--  Start klienta
-- --------------------------------------------------------------------------
SV.Register('init', function(src)
    local p = SV.P(src)
    local prof = Store.Profile(p.id)
    return {
        ok = true,
        houses = Houses.ActiveList(),
        sheds = Houses.ShedList(),
        level = Progress.Level(src),
        tutorial = prof and prof.tutorial or 0,
        bagKg = Bag.Weight(src), bagCap = Bag.Capacity(src),
    }
end, 2000)

CreateThread(function()
    Wait(500)
    Houses.Rotate()
    while true do
        Wait(30000)
        if os.time() - rotationAt >= Config.Rotation.every then Houses.Rotate() end
    end
end)

-- --------------------------------------------------------------------------
--  Szopy: kłódka (wytrych / shim / nożyce) i skrzynia z narzędziami (DOM-11, ZAM-04, WYT-09)
-- --------------------------------------------------------------------------
local function shedFinger(src, id)
    if Player(src).state.wlmGloves == true then Tools.WearGloves(src) return end
    if math.random() < Config.Evidence.fingerprintChance then
        Police.AddEvidence(id, { kind = 'finger', cid = SV.P(src).id, name = Bridge.GetName(src), where = L('where_padlock') })
    end
end

SV.Register('shed:begin', function(src, id, method)
    local s = WLM.ShedById[id]
    if not s then return { ok = false } end
    if Houses.OnCooldown(id) then return { ok = false, msg = L('shed_cooldown') } end
    if not SV.Near(src, s.coords, 3.0) then return { ok = false, msg = L('too_far') } end
    if Progress.Heat(src) >= Config.Police.heatMax then return { ok = false, msg = L('too_hot') } end
    local st = Houses.Shed(id)
    local seed = math.random(1, 2 ^ 30)
    local game, minT
    if method == 'search' then
        if not st.open then return { ok = false, msg = L('locked') } end
        if st.searched then return { ok = false, msg = L('searched') } end
        local f = Config.Furniture.toolchest
        game, minT = { game = 'progress', label = L('act_search', f.label), time = f.time, anim = 'low' }, f.time * 0.8
    elseif st.open then
        return { ok = false, msg = L('already_open') }
    elseif method == 'lockpick' then
        game, minT = Burglary.LockGame(src, 'D', seed)
        if not game then return { ok = false, msg = L('need_item', L('item_lockpick')) } end
    elseif method == 'shim' then
        if not Bridge.HasItem(src, Config.Items.shim) then return { ok = false, msg = L('need_item', Economy.ItemLabel(Config.Items.shim)) } end
        game, minT = { game = 'shim', seed = seed }, 1.0
    elseif method == 'cutters' then
        if not Bridge.HasItem(src, Config.Items.cutters) then return { ok = false, msg = L('need_item', Economy.ItemLabel(Config.Items.cutters)) } end
        local d = Config.Durations.cutters
        game, minT = { game = 'progress', label = L('act_cutters'), time = d, anim = 'cutters' }, d * 0.8
    else
        return { ok = false }
    end
    return { ok = true, token = SV.IssueToken(src, 'shed', { id = id, method = method, picks = game.picks }, minT, 300), game = game }
end, 400)

SV.Register('shed:finish', function(src, token, result)
    local data, err = SV.UseToken(src, token, 'shed')
    if not data then
        if err == 'too_quick' then SV.Suspicious(src, 'szopa za szybko') end
        return { ok = false, msg = L('session_invalid') }
    end
    local s = WLM.ShedById[data.id]
    if not s or not SV.Near(src, s.coords, 4.0) then return { ok = false, msg = L('too_far') } end
    result = type(result) == 'table' and result or {}
    local st = Houses.Shed(data.id)
    if data.method == 'lockpick' then
        local broken = math.floor(WLM.U.Clamp(tonumber(result.broken) or 0, 0, data.picks or 10))
        if broken > 0 then Burglary.ConsumePicks(src, broken) end
    end
    if data.method == 'search' then
        if st.searched then return { ok = false } end
        st.searched = true
        local found = {}
        local rng = function(a, b) return a and b and math.random(a, b) or math.random() end
        local f = Config.Furniture.toolchest
        for _ = 1, math.random(f.rolls[1], f.rolls[2]) do
            local key = WLM.U.PickWeighted(rng, f.table)
            if key and Config.Loot[key] then
                local item = Bag.Make(key, data.id, Bag.RollValue(key, 1))
                if Bag.Add(src, item) then found[#found + 1] = Config.Loot[key].label end
            end
        end
        shedFinger(src, data.id)
        Bag.Sync(src)
        Progress.AddXP(src, 15, 'szopa')
        Contracts.Hook(src, 'shed', { id = data.id })
        Houses.FinishShed(data.id)
        return { ok = true, found = found }
    end
    if not result.ok then return { ok = true, opened = false } end
    st.open = true
    shedFinger(src, data.id)
    TriggerClientEvent('dp-wlamywacz:client:sheds', -1, Houses.ShedList())
    return { ok = true, opened = true }
end, 200)
