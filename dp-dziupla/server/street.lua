-- ==========================================================================
--  dp-dziupla – serwer: ulica (zlecenia kradzieży, auta-cele, wytrych,
--  alarm, nadajniki GPS, zamówienia klientów, eksport, handlarz „czystych” aut)
-- ==========================================================================
local C = Config.Contracts
local Offers = {}     -- [src] = { at, lvl, list }        zlecenia kradzieży
local Active = {}     -- [src] = zlecenie w realizacji
local OOffers = {}    -- [src] = { at, list }             zamówienia
local OActive = {}    -- [src] = zamówienie w realizacji
local EOffers = {}    -- [src] = { at, list }             eksport
local EActive = {}    -- [src] = eksport w realizacji
local Sess = {}       -- [src] = { kind = 'lockpick'|'scan', token, net, started }

local function ucfirst(s) return (s:gsub('^%l', string.upper)) end

local function vehFromNet(netId)
    if type(netId) ~= 'number' then return nil end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) or GetEntityType(veh) ~= 2 then return nil end
    return veh
end

local function nearEnt(src, ent, r)
    local c = DZ.PedCoords(src)
    return c and #(c - GetEntityCoords(ent)) <= r
end

local function dispatch(src, kind, coords, data)
    TriggerClientEvent('dp-dziupla:client:dispatch', src, kind, coords, data or {})
end

local function randomPlate()
    local L3 = 'ABCDEFGHJKLMNPRSTUVWXYZ'
    local function ch() local k = math.random(#L3) return L3:sub(k, k) end
    return ('%s%s%d%d%d%s%s'):format(ch(), ch(), math.random(0, 9), math.random(0, 9), math.random(0, 9), ch(), ch())
end

local function fmtLeft(sec)
    sec = math.max(0, math.floor(sec))
    return ('%d:%02d'):format(sec // 60, sec % 60)
end

-- ==========================================================================
--  ZLECENIA KRADZIEŻY
-- ==========================================================================
local function genContract(lvl, fx)
    local tiers = {}
    for i, t in ipairs(C.tiers) do
        if lvl >= t.minLevel then tiers[#tiers + 1] = i end
    end
    local ti = DZ.pick(tiers)
    local t = C.tiers[ti]
    local model = DZ.pick(t.models)
    local spot = DZ.pick(C.spots)
    local a = math.random() * math.pi * 2
    local r = C.areaRadius * 0.6 * math.random()
    local bonus = 1 + 0.10 * fx.contacts
    return {
        id = DZ.token():sub(1, 8), tier = ti, model = model, label = ucfirst(model),
        reward = math.floor(math.random(t.reward[1], t.reward[2]) * bonus), xp = t.xp,
        time = math.random(C.deadline[1], C.deadline[2]),
        alarm = t.alarm, tracker = t.tracker, pins = t.pins,
        spot = spot, area = vector3(spot.x + math.cos(a) * r, spot.y + math.sin(a) * r, spot.z),
    }
end

local function contractOffers(src, p)
    local lvl = DZ.Level(p)
    local o = Offers[src]
    if o and os.time() - o.at < C.refresh and o.lvl == lvl and #o.list > 0 then return o.list end
    local fx = DZ.Fx(p)
    local list = {}
    for _ = 1, C.count + fx.contacts do list[#list + 1] = genContract(lvl, fx) end
    Offers[src] = { at = os.time(), lvl = lvl, list = list }
    return list
end

local function contractView(c, active)
    local v = {
        id = c.id, tier = c.tier, label = c.label, model = c.model, reward = c.reward, xp = c.xp,
        time = c.time, risk = { alarm = c.alarm, tracker = c.tracker }, area = { x = c.area.x, y = c.area.y, z = c.area.z },
    }
    if active then
        v.left = fmtLeft(c.deadline - os.time())
        v.spawned = c.net ~= nil
        v.plate = c.plate
    end
    return v
end

local function clearContract(src, deleteVeh)
    local c = Active[src]
    if not c then return end
    Active[src] = nil
    if c.net then
        local veh = vehFromNet(c.net)
        if veh then
            Entity(veh).state:set('dpTarget', nil, true)
            local driver = GetPedInVehicleSeat(veh, -1)
            if deleteVeh and driver == 0 and not DZ.JobByNet(c.net) then DeleteEntity(veh) end
        end
    end
    TriggerClientEvent('dp-dziupla:client:contract', src, nil)
end

DZ.register('contractAccept', function(src, id)
    if not DZ.HasAccess(src) then return { ok = false, msg = L('no_access') } end
    if Active[src] then return { ok = false, msg = L('contract_taken') } end
    if Bridge.CountPolice() < Config.Police.minForContracts then return { ok = false, msg = L('police_low') } end
    local o = Offers[src]
    local offer
    for _, c in ipairs(o and o.list or {}) do
        if c.id == id then offer = c end
    end
    if not offer then return { ok = false, msg = L('contract_gone') } end
    local p = DZ.Profile(src)
    if DZ.Level(p) < C.tiers[offer.tier].minLevel then return { ok = false, msg = L('contract_level') } end
    offer.deadline = os.time() + offer.time
    Active[src] = offer
    Offers[src] = nil
    TriggerClientEvent('dp-dziupla:client:contract', src, { area = offer.area, spot = offer.spot, radius = C.areaRadius, label = offer.label, deadline = offer.time })
    return { ok = true, msg = L('contract_accepted', offer.label), data = DZ.Overview(src) }
end)

DZ.register('contractCancel', function(src)
    if not Active[src] then return { ok = false } end
    clearContract(src, true)
    return { ok = true, msg = L('contract_cancel'), data = DZ.Overview(src) }
end)

-- gracz dojechał w okolice – serwer tworzy auto-cel
DZ.register('contractSpawn', function(src, groundZ)
    local c = Active[src]
    if not c or c.net then return { ok = false } end
    local pc = DZ.PedCoords(src)
    if not pc or #(pc.xy - c.spot.xy) > C.spawnDistance + 30.0 then return { ok = false } end
    local z = tonumber(groundZ)
    if not z or math.abs(z - c.spot.z) > 6.0 then z = c.spot.z end
    local veh = CreateVehicleServerSetter(joaat(c.model), 'automobile', c.spot.x, c.spot.y, z + 0.3, c.spot.w)
    local t = GetGameTimer() + 5000
    while not DoesEntityExist(veh) and GetGameTimer() < t do Wait(10) end
    if not DoesEntityExist(veh) then return { ok = false } end
    pcall(SetEntityOrphanMode, veh, 2)
    c.plate = randomPlate()
    SetVehicleNumberPlateText(veh, c.plate)
    SetVehicleDoorsLocked(veh, 2)
    local col = math.random(0, 150)
    SetVehicleColours(veh, col, col)
    local p = DZ.Profile(src)
    local thief = DZ.Fx(p).thief
    c.net = NetworkGetNetworkIdFromEntity(veh)
    c.hasTracker = math.random() < c.tracker
    c.trackerSpot = math.random(#Config.Tracker.spots)
    c.alarmChance = c.alarm * (1 - 0.35 * thief)
    c.locked = true
    Entity(veh).state:set('dpTarget', { owner = src, locked = true, tracker = c.hasTracker }, true)
    return { ok = true, net = c.net, plate = c.plate, msg = L('contract_spawned', c.label, c.plate) }
end)

-- auto ze zlecenia trafiło na przebitkę – zlecenie znika, ale auta nie kasujemy
function DZ.DropContract(net)
    for src, c in pairs(Active) do
        if c.net == net then clearContract(src, false) end
    end
end

-- wynik przy wstawieniu auta na stanowisko (wołane z server/chop.lua)
function DZ.OnChopStart(src, veh, snap, job)
    local c = Active[src]
    if not c or not DZ.SameModel(GetEntityModel(veh), joaat(c.model)) then return end
    if os.time() > c.deadline then return end
    local p = DZ.Profile(src)
    DZ.Earn(src, p, c.reward, 'zlecenie')
    DZ.AddXP(src, p, c.xp)
    p.stats.contracts = p.stats.contracts + 1
    DZ.Save(p)
    Bridge.Notify(src, L('contract_bonus', c.reward), 'good')
    Active[src] = nil
    Entity(veh).state:set('dpTarget', nil, true)
    TriggerClientEvent('dp-dziupla:client:contract', src, nil)
end

-- --------------------------------------------------------------------------
--  Wytrych / wybicie szyby
-- --------------------------------------------------------------------------
local function targetOf(src, netId)
    local veh = vehFromNet(netId)
    if not veh then return nil end
    local st = Entity(veh).state.dpTarget
    if not st or st.owner ~= src then return nil end
    return veh, Active[src]
end

local function unlockTarget(veh, c)
    local st = Entity(veh).state.dpTarget or {}
    SetVehicleDoorsLocked(veh, 1)
    c.locked = false
    Entity(veh).state:set('dpTarget', { owner = st.owner, locked = false, tracker = c.hasTracker }, true)
end

DZ.register('lockpickBegin', function(src, netId)
    local veh, c = targetOf(src, netId)
    if not veh or not c or not c.locked then return { ok = false } end
    if not nearEnt(src, veh, 4.0) then return { ok = false, msg = L('too_far') } end
    local p = DZ.Profile(src)
    if (p.cons.lockpick or 0) <= 0 then return { ok = false, msg = L('lockpick_none') } end
    local fx = DZ.Fx(p)
    local token = DZ.token()
    Sess[src] = { kind = 'lockpick', token = token, net = netId, started = os.time() }
    return { ok = true, token = token, spec = { pins = c.pins, seed = math.random(1, 2147483646), picks = p.cons.lockpick, shear = 0.05 + 0.02 * fx.thief } }
end)

DZ.register('lockpickFinish', function(src, token, success, broke)
    local s = Sess[src]
    if not s or s.kind ~= 'lockpick' or s.token ~= token then return { ok = false } end
    Sess[src] = nil
    local veh, c = targetOf(src, s.net)
    if not veh or not c then return { ok = false } end
    local p = DZ.Profile(src)
    p.cons.lockpick = math.max(0, (p.cons.lockpick or 0) - math.floor(DZ.num(broke, 0, 20)))
    DZ.Save(p)
    if success ~= true then
        return { ok = true, success = false, msg = L('lockpick_fail'), alarm = math.random() < c.alarmChance * 0.5, plate = c.plate }
    end
    if os.time() - s.started < Config.Security.lockpickMin or not nearEnt(src, veh, 4.0) then
        DZ.warn(src, 'wytrych za szybko / za daleko')
        return { ok = false, msg = L('suspicious') }
    end
    unlockTarget(veh, c)
    local alarm = math.random() < c.alarmChance
    return { ok = true, success = true, alarm = alarm, plate = c.plate, msg = L('lockpick_ok') }
end)

DZ.register('smash', function(src, netId)
    local veh, c = targetOf(src, netId)
    if not veh or not c or not c.locked then return { ok = false } end
    if not nearEnt(src, veh, 4.0) then return { ok = false, msg = L('too_far') } end
    unlockTarget(veh, c)
    return { ok = true, alarm = Config.Contracts.smashAlarm or math.random() < c.alarmChance, plate = c.plate }
end)

-- --------------------------------------------------------------------------
--  Nadajnik GPS
-- --------------------------------------------------------------------------
DZ.register('scanBegin', function(src, netId)
    local veh = vehFromNet(netId)
    if not veh or not nearEnt(src, veh, 5.0) then return { ok = false, msg = L('too_far') } end
    local p = DZ.Profile(src)
    if not DZ.HasTool(p, 'scanner') then return { ok = false, msg = L('part_tool', Config.Tools.scanner.label) } end
    local st = Entity(veh).state.dpTarget
    local c = st and Active[st.owner]
    local has = c and c.net == netId and c.hasTracker or false
    local token = DZ.token()
    Sess[src] = { kind = 'scan', token = token, net = netId, started = os.time() }
    return { ok = true, token = token, spec = {
        seed = math.random(1, 2147483646), spots = Config.Tracker.spots,
        spot = has and c.trackerSpot or 0, tech = DZ.Fx(p).tech,
    } }
end)

DZ.register('scanFinish', function(src, token, found)
    local s = Sess[src]
    if not s or s.kind ~= 'scan' or s.token ~= token then return { ok = false } end
    Sess[src] = nil
    local veh = vehFromNet(s.net)
    if not veh then return { ok = false } end
    local st = Entity(veh).state.dpTarget
    local c = st and Active[st.owner]
    if not (c and c.net == s.net and c.hasTracker) then return { ok = true, msg = L('tracker_none') } end
    if found ~= true then return { ok = true } end
    if os.time() - s.started < Config.Security.scannerMin then return { ok = false, msg = L('suspicious') } end
    c.hasTracker = false
    Entity(veh).state:set('dpTarget', { owner = st.owner, locked = st.locked, tracker = false }, true)
    return { ok = true, removed = true, msg = L('tracker_removed') }
end)

local function playerFromPed(ped)
    for _, id in ipairs(GetPlayers()) do
        if GetPlayerPed(id) == ped then return tonumber(id) end
    end
end

-- namiary z nadajników i wygasanie zleceń
CreateThread(function()
    local T = Config.Tracker
    while true do
        Wait(5000)
        local now = os.time()
        for src, c in pairs(Active) do
            if now > c.deadline then
                Bridge.Notify(src, L('contract_expired'), 'bad')
                clearContract(src, true)
            elseif c.net and c.hasTracker and not c.locked then
                local veh = vehFromNet(c.net)
                if veh then
                    local driver = GetPedInVehicleSeat(veh, -1)
                    if driver ~= 0 then
                        c.trackStart = c.trackStart or now
                        c.lastPing = c.lastPing or (now - T.interval + T.firstDelay)
                        if now - c.lastPing >= T.interval then
                            c.lastPing = now
                            local who = playerFromPed(driver) or src
                            dispatch(who, 'tracker', GetEntityCoords(veh), { plate = c.plate, model = c.label })
                        end
                    end
                end
            end
        end
    end
end)

-- ==========================================================================
--  ZAMÓWIENIA KLIENTÓW
-- ==========================================================================
local O = Config.Orders
local orderTypes = {}
for k, t in pairs(Parts.Types) do
    if k ~= 'scrap' and t.base >= 60 then orderTypes[#orderTypes + 1] = k end
end
table.sort(orderTypes)

local function genOrder(p)
    local lines, pay = {}, 0
    local used = {}
    for _ = 1, math.random(1, 3) do
        local t = DZ.pick(orderTypes)
        if not used[t] then
            used[t] = true
            local n = (t == 'wheel' or t == 'rim' or t == 'tyre') and math.random(2, 4) or math.random(1, 2)
            local minC = DZ.pick({ 30, 45, 60, 75 })
            lines[#lines + 1] = { t = t, n = n, min = minC, label = Parts.Types[t].label }
            pay = pay + Logic.PartValue(t, math.min(100, minC + 15), 1.0) * n
        end
    end
    local mult = O.payMult[1] + (O.payMult[2] - O.payMult[1]) * math.random()
    return {
        id = DZ.token():sub(1, 8), lines = lines, pay = math.floor(pay * mult * DZ.Fx(p).trader),
        drop = DZ.pick(O.drops), time = O.deadline,
        client = DZ.pick({ 'Warsztat „U Zenka”', 'Tuner z Vespucci', 'Handlarz z Sandy', 'Komis Premium', 'Zbyszek od felg', 'Garaż na Grove', 'Klub driftowy', 'Rosjanin z portu' }),
    }
end

local function orderOffers(src, p)
    local o = OOffers[src]
    if o and os.time() - o.at < O.refresh and #o.list > 0 then return o.list end
    local list = {}
    for _ = 1, O.count do list[#list + 1] = genOrder(p) end
    OOffers[src] = { at = os.time(), list = list }
    return list
end

-- dobór części z magazynu do zamówienia (najsłabsze spełniające próg)
local function matchOrder(p, lines)
    local picked, taken = {}, {}
    for _, ln in ipairs(lines) do
        local cands = {}
        for _, it in ipairs(p.wh) do
            if it.t == ln.t and not it.res and not taken[it.u] and (it.c or 0) >= ln.min then cands[#cands + 1] = it end
        end
        table.sort(cands, function(a, b) return a.c < b.c end)
        if #cands < ln.n then return nil, ln end
        for i = 1, ln.n do
            taken[cands[i].u] = true
            picked[#picked + 1] = cands[i].u
        end
    end
    return picked
end

local function orderHave(p, lines)
    local out = {}
    for i, ln in ipairs(lines) do
        local n = 0
        for _, it in ipairs(p.wh) do
            if it.t == ln.t and not it.res and (it.c or 0) >= ln.min then n = n + 1 end
        end
        out[i] = n
    end
    return out
end

local function releaseOrder(src, p)
    local o = OActive[src]
    if not o then return end
    p = p or DZ.Profile(src)
    if p then
        for _, u in ipairs(o.uids) do
            local it = DZ.WhFind(p, u)
            if it then it.res = nil end
        end
        DZ.Save(p)
    end
    OActive[src] = nil
    TriggerClientEvent('dp-dziupla:client:order', src, nil)
end

DZ.register('orderAccept', function(src, id)
    if OActive[src] then return { ok = false, msg = L('order_taken') } end
    if not DZ.ShopAt(src) then return { ok = false, msg = L('not_at_shop') } end
    local p = DZ.Profile(src)
    local oo = OOffers[src]
    local offer
    for _, o in ipairs(oo and oo.list or {}) do
        if o.id == id then offer = o end
    end
    if not offer then return { ok = false, msg = L('contract_gone') } end
    local uids = matchOrder(p, offer.lines)
    if not uids then return { ok = false, msg = L('order_missing') } end
    for _, u in ipairs(uids) do DZ.WhFind(p, u).res = true end
    DZ.Save(p)
    offer.uids = uids
    offer.deadline = os.time() + offer.time
    OActive[src] = offer
    OOffers[src] = nil
    TriggerClientEvent('dp-dziupla:client:order', src, { drop = offer.drop, client = offer.client })
    return { ok = true, msg = L('order_accepted'), data = DZ.Overview(src) }
end)

DZ.register('orderCancel', function(src)
    if not OActive[src] then return { ok = false } end
    releaseOrder(src)
    return { ok = true, msg = L('order_cancel'), data = DZ.Overview(src) }
end)

DZ.register('orderDeliver', function(src)
    local o = OActive[src]
    if not o then return { ok = false } end
    if not DZ.Near(src, o.drop, 6.0) then return { ok = false, msg = L('too_far') } end
    local p = DZ.Profile(src)
    for _, u in ipairs(o.uids) do
        local it = DZ.WhFind(p, u)
        if it then
            local t = Parts.Types[it.t]
            if t then DZ.MarketSold(t.cat, Logic.PartValue(it.t, it.c, it.m) * 0.5) end
            DZ.WhTake(p, u)
        end
    end
    OActive[src] = nil
    DZ.Earn(src, p, o.pay, 'zamowienie')
    DZ.AddXP(src, p, 25 + #o.uids * 5)
    p.stats.orders = p.stats.orders + 1
    DZ.Save(p)
    if math.random() < O.ambushChance then dispatch(src, 'drop', vector3(o.drop.x, o.drop.y, o.drop.z), {}) end
    TriggerClientEvent('dp-dziupla:client:order', src, nil)
    return { ok = true, msg = L('order_done', o.pay) }
end)

-- ==========================================================================
--  EKSPORT
-- ==========================================================================
local E = Config.Export
local exportClasses = {}
for cls in pairs(E.base) do exportClasses[#exportClasses + 1] = cls end
table.sort(exportClasses)

local function exportOffers(src, p)
    if DZ.Level(p) < E.minLevel then return {} end
    local o = EOffers[src]
    if o and os.time() - o.at < E.refresh and #o.list > 0 then return o.list end
    local list = {}
    for _ = 1, E.count do
        local cls = DZ.pick(exportClasses)
        list[#list + 1] = {
            id = DZ.token():sub(1, 8), class = cls, label = Config.ClassLabels[cls] or ('Klasa ' .. cls),
            pay = math.floor(E.base[cls] * (0.9 + 0.3 * math.random()) * DZ.Fx(p).trader), time = E.deadline,
            point = DZ.pick(E.points), minHealth = E.minHealth,
        }
    end
    EOffers[src] = { at = os.time(), list = list }
    return list
end

DZ.register('exportAccept', function(src, id)
    if EActive[src] then return { ok = false, msg = L('export_taken') } end
    local oo = EOffers[src]
    local offer
    for _, o in ipairs(oo and oo.list or {}) do
        if o.id == id then offer = o end
    end
    if not offer then return { ok = false, msg = L('contract_gone') } end
    offer.deadline = os.time() + offer.time
    EActive[src] = offer
    EOffers[src] = nil
    TriggerClientEvent('dp-dziupla:client:export', src, { point = offer.point, label = offer.label })
    return { ok = true, msg = L('export_accepted', offer.label), data = DZ.Overview(src) }
end)

DZ.register('exportCancel', function(src)
    if not EActive[src] then return { ok = false } end
    EActive[src] = nil
    TriggerClientEvent('dp-dziupla:client:export', src, nil)
    return { ok = true, msg = L('contract_cancel'), data = DZ.Overview(src) }
end)

DZ.register('exportDeliver', function(src, netId, snap)
    local e = EActive[src]
    if not e then return { ok = false } end
    local veh = vehFromNet(netId)
    if not veh or type(snap) ~= 'table' then return { ok = false } end
    if #(GetEntityCoords(veh).xy - e.point.xy) > 10.0 or not nearEnt(src, veh, 6.0) then return { ok = false, msg = L('too_far') } end
    if not DZ.SameModel(snap.model, GetEntityModel(veh)) then return { ok = false, msg = L('suspicious') } end
    local cls = math.floor(DZ.num(snap.class, 0, 22))
    if cls ~= e.class then return { ok = false, msg = L('export_wrong', e.label) } end
    local plate = (GetVehicleNumberPlateText(veh) or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if not Entity(veh).state.dpTarget and ServerHooks.IsVehicleOwned(plate) then return { ok = false, msg = L('chop_owned') } end
    for seat = -1, 6 do
        local ped = GetPedInVehicleSeat(veh, seat)
        if ped ~= 0 and ped ~= GetPlayerPed(src) then return { ok = false, msg = L('chop_occupied') } end
    end
    local health = math.min(DZ.num(snap.body, 0, 1000), DZ.num(snap.engine, 0, 1000)) / 1000
    if health < e.minHealth then return { ok = false, msg = L('export_damaged') } end
    local p = DZ.Profile(src)
    local pay = math.floor(e.pay * (0.6 + 0.4 * health))
    EActive[src] = nil
    SetTimeout(3000, function()
        if DoesEntityExist(veh) then DeleteEntity(veh) end
    end)
    if Active[src] and Active[src].net == netId then clearContract(src, false) end
    DZ.Earn(src, p, pay, 'eksport')
    DZ.AddXP(src, p, 50)
    p.stats.exports = p.stats.exports + 1
    DZ.Save(p)
    if math.random() < E.dispatchChance then dispatch(src, 'export', GetEntityCoords(veh), { plate = plate }) end
    TriggerClientEvent('dp-dziupla:client:export', src, nil)
    return { ok = true, msg = L('export_done', pay) }
end)

-- ==========================================================================
--  HANDLARZ („czyste” auta po przebitce)
-- ==========================================================================
local function cleanCar(src, netId)
    local veh = vehFromNet(netId)
    if not veh then return nil end
    local st = Entity(veh).state.dpClean
    if not st or st.owner ~= Bridge.GetIdentifier(src) then return nil end
    return veh, st
end

DZ.register('revinSell', function(src, netId)
    local veh, st = cleanCar(src, netId)
    if not veh then return { ok = false, msg = L('not_revin_car') } end
    local R = Config.Revin
    if not DZ.Near(src, R.dealer, 10.0) or #(GetEntityCoords(veh).xy - R.dealer.xy) > 14.0 then return { ok = false, msg = L('too_far') } end
    for seat = -1, 6 do
        if GetPedInVehicleSeat(veh, seat) ~= 0 then return { ok = false, msg = L('chop_occupied') } end
    end
    local q = DZ.num(st.q, 0, 1)
    local risk = 0
    if q < R.detectBelow then risk = (R.detectBelow - q) * 2 end
    if not st.papers then risk = risk + 0.15 end
    if math.random() < risk then
        Entity(veh).state:set('dpClean', nil, true)
        dispatch(src, 'dealer', GetEntityCoords(veh), { plate = st.plate })
        return { ok = true, refused = true, msg = L('revin_refused') }
    end
    local p = DZ.Profile(src)
    local pay = math.floor((R.value[st.class] or 4000) * (0.5 + 0.5 * q) * (st.papers and R.papersMult or 1.0) * DZ.Fx(p).trader)
    DeleteEntity(veh)
    DZ.Earn(src, p, pay, 'handlarz')
    DZ.AddXP(src, p, 60)
    DZ.Save(p)
    return { ok = true, msg = L('revin_sold', pay) }
end)

DZ.register('revinKeep', function(src, netId, props)
    if not Config.Revin.allowKeep then return { ok = false, msg = L('revin_keep_off') } end
    local veh, st = cleanCar(src, netId)
    if not veh then return { ok = false, msg = L('not_revin_car') } end
    if type(props) == 'table' then props.plate = st.plate end
    if not ServerHooks.GiveVehicle(src, st.plate, type(props) == 'table' and props or nil, (st.name or ''):lower()) then
        return { ok = false, msg = L('error') }
    end
    Entity(veh).state:set('dpClean', nil, true)
    return { ok = true, plate = st.plate, msg = L('revin_kept', st.plate) }
end)

-- ==========================================================================
--  Widok do laptopa + przywracanie stanu po reconnect/restarcie klienta
-- ==========================================================================
function DZ.StreetView(src, p, data)
    local lvl = DZ.Level(p)
    local c = Active[src]
    data.contracts = { active = c and contractView(c, true) or nil, offers = {} }
    if not c then
        for i, o in ipairs(contractOffers(src, p)) do data.contracts.offers[i] = contractView(o) end
    end
    local o = OActive[src]
    data.orders = { offers = {} }
    if o then
        data.orders.active = { client = o.client, pay = o.pay, lines = o.lines, left = fmtLeft(o.deadline - os.time()) }
    else
        for i, of in ipairs(orderOffers(src, p)) do
            data.orders.offers[i] = { id = of.id, client = of.client, pay = of.pay, lines = of.lines, have = orderHave(p, of.lines), time = of.time }
        end
    end
    local e = EActive[src]
    data.exports = { minLevel = E.minLevel, locked = lvl < E.minLevel, offers = {} }
    if e then
        data.exports.active = { label = e.label, pay = e.pay, left = fmtLeft(e.deadline - os.time()), minHealth = e.minHealth }
    else
        for i, of in ipairs(exportOffers(src, p)) do
            data.exports.offers[i] = { id = of.id, label = of.label, pay = of.pay, time = of.time, minHealth = of.minHealth }
        end
    end
end

DZ.register('streetState', function(src)
    local c, o, e = Active[src], OActive[src], EActive[src]
    return {
        contract = c and { area = c.area, spot = c.spot, radius = C.areaRadius, label = c.label, net = c.net, plate = c.plate, deadline = c.deadline - os.time() } or nil,
        order = o and { drop = o.drop, client = o.client } or nil,
        export = e and { point = e.point, label = e.label } or nil,
    }
end)

-- wygasanie zamówień i eksportów
CreateThread(function()
    while true do
        Wait(10000)
        local now = os.time()
        for src, o in pairs(OActive) do
            if now > o.deadline then
                releaseOrder(src)
                Bridge.Notify(src, L('order_expired'), 'bad')
            end
        end
        for src, e in pairs(EActive) do
            if now > e.deadline then
                EActive[src] = nil
                Bridge.Notify(src, L('export_expired'), 'bad')
                TriggerClientEvent('dp-dziupla:client:export', src, nil)
            end
        end
    end
end)

DZ.OnDrop[#DZ.OnDrop + 1] = function(src)
    clearContract(src, true)
    releaseOrder(src)
    Offers[src], OOffers[src], EOffers[src], EActive[src], Sess[src] = nil, nil, nil, nil, nil
end
