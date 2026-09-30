-- ==========================================================================
--  dp-dziupla – serwer: rdzeń (callbacki, profile, magazyn, rynek, sklep,
--  umiejętności, hałas, laptop ChopNet). Serwer jest jedynym źródłem prawdy.
-- ==========================================================================
DZ = {}

function DZ.dbg(...)
    if Config.Debug then print('^3[dp-dziupla]^7', ...) end
end

function DZ.warn(src, what)
    print(('^1[dp-dziupla] podejrzane (%s / %d): %s^7'):format(GetPlayerName(src) or '?', src, what))
end

function DZ.token()
    return ('%08x%08x'):format(math.random(0, 0x7fffffff), math.random(0, 0x7fffffff))
end

function DZ.num(v, lo, hi)
    v = tonumber(v) or 0
    if v ~= v then v = 0 end
    return math.max(lo, math.min(hi, v))
end

function DZ.pick(t) return t[math.random(#t)] end

function DZ.shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

-- --------------------------------------------------------------------------
--  Callbacki (lekki system bez zależności, z limitem częstotliwości)
-- --------------------------------------------------------------------------
local handlers, lastCall = {}, {}

function DZ.register(name, fn) handlers[name] = fn end

RegisterNetEvent('dp-dziupla:server:cb', function(name, id, ...)
    local src = source
    if type(id) ~= 'number' or type(name) ~= 'string' then return end
    local h = handlers[name]
    if not h then return TriggerClientEvent('dp-dziupla:client:cb', src, id, nil) end
    lastCall[src] = lastCall[src] or {}
    local now = GetGameTimer()
    if lastCall[src][name] and now - lastCall[src][name] < 200 then
        return TriggerClientEvent('dp-dziupla:client:cb', src, id, nil)
    end
    lastCall[src][name] = now
    local ok, res = pcall(h, src, ...)
    if not ok then
        print(('^1[dp-dziupla] błąd w %s: %s^7'):format(name, res))
        res = { ok = false, msg = L('error') }
    end
    TriggerClientEvent('dp-dziupla:client:cb', src, id, res)
end)

-- --------------------------------------------------------------------------
--  Profil gracza (KVP – bez bazy danych)
-- --------------------------------------------------------------------------
local Profiles = {}
local SrcIds = {}     -- [src] = identyfikator (działa też w playerDropped, gdy framework już wyrzucił gracza)

local function newProfile(id)
    local p = {
        id = id, xp = 0, perks = {}, tools = {}, cons = {}, upg = {},
        stats = { cars = 0, parts = 0, earned = 0, contracts = 0, regen = 0, exports = 0, orders = 0 },
        wh = {}, seq = 0,
    }
    for k, c in pairs(Config.Consumables) do p.cons[k] = c.start or 0 end
    return p
end

function DZ.Profile(src)
    local id = Bridge.GetIdentifier(src, true) or SrcIds[src] or Bridge.GetIdentifier(src)
    if not id then return nil end
    SrcIds[src] = id
    if Profiles[id] then return Profiles[id] end
    local raw = GetResourceKvpString('dz:' .. id)
    local p = newProfile(id)
    if raw then
        local d = json.decode(raw) or {}
        for k, v in pairs(d) do p[k] = v end
        p.id = id
    end
    for k in pairs(newProfile(id).stats) do p.stats[k] = p.stats[k] or 0 end
    Profiles[id] = p
    return p
end

function DZ.Save(p)
    local copy = {}
    for k, v in pairs(p) do
        if k ~= 'id' then copy[k] = v end
    end
    SetResourceKvp('dz:' .. p.id, json.encode(copy))
end

function DZ.Level(p) return Logic.LevelFor(p.xp) end

function DZ.Fx(p) return Logic.PerkFx(p.perks) end

function DZ.PerkPoints(p)
    local spent = 0
    for _, r in pairs(p.perks) do spent = spent + r end
    return (DZ.Level(p) - 1) * Config.PerkPointsPerLevel - spent
end

function DZ.AddXP(src, p, amount)
    amount = math.floor(amount)
    if amount == 0 then return nil end
    local before = DZ.Level(p)
    p.xp = math.max(0, p.xp + amount)
    local after = DZ.Level(p)
    if after > before then
        Bridge.Notify(src, L('level_up', Config.Levels[after].label, (after - before) * Config.PerkPointsPerLevel), 'good')
        return Config.Levels[after].label
    end
end

function DZ.HasTool(p, key)
    local t = Config.Tools[key]
    if not t then return false end
    return t.starter or p.tools[key] == true
end

function DZ.OwnedTools(p)
    local out = {}
    for k in pairs(Config.Tools) do
        if DZ.HasTool(p, k) then out[k] = true end
    end
    return out
end

function DZ.Earn(src, p, amount, reason)
    amount = math.floor(amount)
    if amount <= 0 then return 0 end
    Bridge.AddMoney(src, Config.PayAccount, amount, 'dp-dziupla-' .. reason)
    p.stats.earned = p.stats.earned + amount
    ServerHooks.OnEarn(src, amount, reason)
    TriggerEvent('dp-dziupla:earned', src, amount, reason)
    return amount
end

-- --------------------------------------------------------------------------
--  Dostęp i lokalizacja
-- --------------------------------------------------------------------------
function DZ.HasAccess(src)
    local job = Bridge.GetJob(src)
    for _, b in ipairs(Config.Job.blocked) do
        if b == job then return false end
    end
    if not Config.Job.required then return true end
    for _, n in ipairs(Config.Job.names) do
        if n == job then return true end
    end
    return false
end

function DZ.PedCoords(src)
    local ped = GetPlayerPed(src)
    if ped == 0 then return nil end
    return GetEntityCoords(ped)
end

function DZ.ShopByKey(key)
    for _, s in ipairs(Config.Shops) do
        if s.key == key then return s end
    end
end

function DZ.ShopAt(src)
    local c = DZ.PedCoords(src)
    if not c then return nil end
    for _, s in ipairs(Config.Shops) do
        if #(c - s.center) <= s.radius then return s end
    end
end

function DZ.Near(src, v, r)
    local c = DZ.PedCoords(src)
    return c and #(c.xy - vector2(v.x, v.y)) <= r
end

-- --------------------------------------------------------------------------
--  Magazyn części
-- --------------------------------------------------------------------------
-- DZ.WhCap / WhFree / WhAdd / WhFind / WhTake / WhList / WhUpdate – patrz server/storage.lua

function DZ.ItemLabel(it)
    local t = Parts.Types[it.t]
    local l = it.l or (t and t.label) or it.t
    if it.t == 'scrap' then return ('%s (%d kg)'):format(l, it.k or 0) end
    return l
end

-- --------------------------------------------------------------------------
--  Rynek (popyt per kategoria, historia, wydarzenia)
-- --------------------------------------------------------------------------
local Market = { d = {}, hist = {}, event = nil, tick = 0 }

local function loadMarket()
    local raw = GetResourceKvpString('dz:market')
    local m = raw and json.decode(raw) or {}
    for cat in pairs(Config.Categories) do
        Market.d[cat] = tonumber(m.d and m.d[cat]) or 1.0
        Market.hist[cat] = (m.hist and m.hist[cat]) or {}
    end
    if m.event and m.event['until'] and m.event['until'] > os.time() then Market.event = m.event end
end

local function saveMarket()
    SetResourceKvp('dz:market', json.encode({ d = Market.d, hist = Market.hist, event = Market.event }))
end

local function target(cat)
    if Market.event and Market.event.cat == cat then return Market.event.mult end
    return 1.0
end

function DZ.Demand(cat) return Market.d[cat] or 1.0 end

function DZ.MarketSold(cat, amount)
    if cat == 'scrap' then return end
    local M = Config.Market
    Market.d[cat] = math.max(M.min, (Market.d[cat] or 1) - amount / M.saturation)
end

-- cena u pasera za przedmiot z magazynu
function DZ.Price(p, it)
    local t = Parts.Types[it.t]
    if not t then return 0 end
    local v = Logic.PartValue(it.t, it.c, it.m, it.k)
    if it.t == 'scrap' then return v end
    return math.floor(v * DZ.Demand(t.cat) * DZ.Fx(p).trader * Config.Fence.mult)
end

CreateThread(function()
    loadMarket()
    local M = Config.Market
    while true do
        Wait(60000)
        Market.tick = Market.tick + 1
        for cat in pairs(Config.Categories) do
            local d, t = Market.d[cat], target(cat)
            if d < t then d = math.min(t, d + M.recoverPerMin) else d = math.max(t, d - M.recoverPerMin) end
            Market.d[cat] = math.max(M.min, math.min(M.max, d))
        end
        if Market.event and Market.event['until'] <= os.time() then Market.event = nil end
        if Market.tick % 60 == 0 and not Market.event and math.random() < M.eventChance then
            local e = DZ.pick(M.events)
            Market.event = { cat = e.cat, mult = e.mult, label = e.label, ['until'] = os.time() + 3600 }
            DZ.dbg('wydarzenie rynkowe: ' .. e.label)
        end
        if Market.tick % M.historyEvery == 0 then
            for cat in pairs(Config.Categories) do
                local h = Market.hist[cat]
                h[#h + 1] = math.floor(Market.d[cat] * 100 + 0.5) / 100
                while #h > 24 do table.remove(h, 1) end
            end
        end
        saveMarket()
    end
end)

-- --------------------------------------------------------------------------
--  Hałas i brama
-- --------------------------------------------------------------------------
local Noise = {}   -- [shopKey] = { v, last, alertAt }

function DZ.GateClosed(key)
    return GlobalState['dpGate_' .. key] == true
end

function DZ.AddNoise(src, shopKey, amount, p)
    if not shopKey or amount <= 0 then return end
    local N = Config.Noise
    local n = Noise[shopKey] or { v = 0, last = os.time(), alertAt = 0 }
    Noise[shopKey] = n
    local now = os.time()
    n.v = math.max(0, n.v - (now - n.last) * N.decayPerSec)
    n.last = now
    local mult = (DZ.GateClosed(shopKey) and N.gateClosedMult or 1.0) * (p and DZ.Fx(p).quiet or 1.0)
    n.v = n.v + amount * mult
    if n.v >= N.threshold and now - n.alertAt >= N.alertCooldown and math.random() < N.alertChance then
        n.alertAt = now
        n.v = n.v * 0.5
        local shop = DZ.ShopByKey(shopKey)
        Bridge.Notify(src, L('noise_alert'), 'bad')
        TriggerClientEvent('dp-dziupla:client:dispatch', src, 'noise', shop and shop.center or DZ.PedCoords(src), {})
    end
end

function DZ.NoiseLevel(shopKey)
    local n = Noise[shopKey]
    if not n then return 0 end
    return math.max(0, n.v - (os.time() - n.last) * Config.Noise.decayPerSec)
end

DZ.register('gate', function(src, key)
    local shop = DZ.ShopByKey(key)
    if not shop or not DZ.HasAccess(src) then return { ok = false } end
    if not DZ.Near(src, shop.gate, 4.0) then return { ok = false, msg = L('too_far') } end
    local closed = not DZ.GateClosed(key)
    GlobalState['dpGate_' .. key] = closed
    return { ok = true, closed = closed, msg = closed and L('gate_closed') or L('gate_open') }
end)

DZ.register('noise', function(src, key)
    return { v = DZ.NoiseLevel(key) / Config.Noise.threshold, closed = DZ.GateClosed(key) }
end)

-- --------------------------------------------------------------------------
--  Laptop ChopNet – widok danych
-- --------------------------------------------------------------------------
function DZ.ItemView(p, it)
    local t = Parts.Types[it.t] or {}
    return {
        u = it.u, t = it.t, label = DZ.ItemLabel(it), cat = t.cat, catLabel = Config.Categories[t.cat or 'scrap'],
        cond = it.c or 0, value = DZ.Price(p, it), vehicle = it.v, regen = it.r == true,
        bench = t.bench, reserved = DZ.IsRes(p, it.u),
    }
end

function DZ.ProfileView(p)
    local lvl = DZ.Level(p)
    local nextL = Config.Levels[lvl + 1]
    return {
        level = lvl, label = Config.Levels[lvl].label, xp = p.xp,
        curXp = Config.Levels[lvl].xp, nextXp = nextL and nextL.xp or nil, nextLabel = nextL and nextL.label or nil,
        points = DZ.PerkPoints(p), stats = p.stats,
    }
end

local function shopView(src, p)
    local lvl = DZ.Level(p)
    local tools, cons, upg = {}, {}, {}
    for k, t in pairs(Config.Tools) do
        if not t.starter then
            tools[#tools + 1] = { key = k, label = t.label, price = t.price, minLevel = t.minLevel, owned = DZ.HasTool(p, k), locked = lvl < t.minLevel, icon = t.icon }
        end
    end
    table.sort(tools, function(a, b) return a.price < b.price end)
    for k, c in pairs(Config.Consumables) do
        cons[#cons + 1] = { key = k, label = c.label, price = c.price, have = DZ.ConsCount(src, p, k), max = c.max }
    end
    table.sort(cons, function(a, b) return a.price < b.price end)
    for k, u in pairs(Config.Upgrades) do
        upg[#upg + 1] = { key = k, label = u.label, price = u.price, have = p.upg[k] or 0, max = u.max }
    end
    return { tools = tools, cons = cons, upg = upg }
end

local function perkView(p)
    local lvl = DZ.Level(p)
    local out = {}
    for k, d in pairs(Config.Perks) do
        out[#out + 1] = { key = k, label = d.label, desc = d.desc, ranks = d.ranks, rank = p.perks[k] or 0, minLevel = d.minLevel, locked = lvl < d.minLevel }
    end
    table.sort(out, function(a, b)
        if a.minLevel ~= b.minLevel then return a.minLevel < b.minLevel end
        return a.key < b.key
    end)
    return out
end

local function marketView()
    local cats = {}
    for cat, label in pairs(Config.Categories) do
        if cat ~= 'scrap' then
            cats[#cats + 1] = { key = cat, label = label, d = Market.d[cat], hist = Market.hist[cat] }
        end
    end
    table.sort(cats, function(a, b) return a.label < b.label end)
    return { cats = cats, event = Market.event and { label = Market.event.label, cat = Market.event.cat, left = Market.event['until'] - os.time() } or nil }
end

function DZ.Overview(src)
    local p = DZ.Profile(src)
    local items = {}
    for i, it in ipairs(DZ.WhList(p)) do items[i] = DZ.ItemView(p, it) end
    local shop = DZ.ShopAt(src)
    local data = {
        profile = DZ.ProfileView(p),
        warehouse = { items = items, cap = DZ.WhCap(p) },
        market = marketView(),
        shop = shopView(src, p),
        perks = perkView(p),
        atShop = shop ~= nil,
        cash = nil,
    }
    if DZ.StreetView then DZ.StreetView(src, p, data) end
    return data
end

DZ.register('overview', function(src)
    if not DZ.HasAccess(src) then return { ok = false, msg = L('no_access') } end
    return { ok = true, data = DZ.Overview(src) }
end)

-- --------------------------------------------------------------------------
--  Sklep, umiejętności, sprzedaż
-- --------------------------------------------------------------------------
DZ.register('buy', function(src, key, qty)
    if not DZ.HasAccess(src) or not DZ.ShopAt(src) then return { ok = false, msg = L('not_at_shop') } end
    local p = DZ.Profile(src)
    local lvl = DZ.Level(p)
    qty = math.floor(DZ.num(qty, 1, 50))
    local price, apply
    if Config.Tools[key] then
        local t = Config.Tools[key]
        if DZ.HasTool(p, key) then return { ok = false, msg = 'Masz już to narzędzie.' } end
        if lvl < t.minLevel then return { ok = false, msg = ('Wymaga poziomu %d.'):format(t.minLevel) } end
        price, apply = t.price, function() p.tools[key] = true end
    elseif Config.Consumables[key] then
        local c = Config.Consumables[key]
        qty = math.min(qty, c.max - DZ.ConsCount(src, p, key))
        if qty <= 0 then return { ok = false, msg = 'Nie zmieścisz więcej.' } end
        if DZ.InvMode == 'ox' and not exports.ox_inventory:CanCarryItem(src, Config.Inventory.items[key], qty) then
            return { ok = false, msg = 'Nie uniesiesz tego – zrób miejsce w ekwipunku.' }
        end
        price, apply = c.price * qty, function() DZ.ConsAdd(src, p, key, qty) end
    elseif Config.Upgrades[key] then
        local u = Config.Upgrades[key]
        if (p.upg[key] or 0) >= u.max then return { ok = false, msg = 'Maksymalny poziom ulepszenia.' } end
        price, apply = u.price, function() p.upg[key] = (p.upg[key] or 0) + 1 end
    else
        return { ok = false }
    end
    if not Bridge.RemoveMoney(src, Config.ShopAccount, price, 'dp-dziupla-sklep') then
        return { ok = false, msg = L('no_money', price) }
    end
    apply()
    DZ.Save(p)
    return { ok = true, msg = ('Kupiono za %d$.'):format(price), data = DZ.Overview(src) }
end)

DZ.register('perk', function(src, key)
    local p = DZ.Profile(src)
    local d = Config.Perks[key]
    if not d then return { ok = false } end
    if DZ.Level(p) < d.minLevel then return { ok = false, msg = ('Wymaga poziomu %d.'):format(d.minLevel) } end
    if (p.perks[key] or 0) >= d.ranks then return { ok = false, msg = 'Maksymalna ranga.' } end
    if DZ.PerkPoints(p) <= 0 then return { ok = false, msg = 'Brak punktów umiejętności.' } end
    p.perks[key] = (p.perks[key] or 0) + 1
    DZ.Save(p)
    return { ok = true, msg = d.label .. ': ranga ' .. p.perks[key], data = DZ.Overview(src) }
end)

DZ.register('perkReset', function(src)
    if not DZ.ShopAt(src) then return { ok = false, msg = L('not_at_shop') } end
    local p = DZ.Profile(src)
    if not Bridge.RemoveMoney(src, Config.ShopAccount, Config.PerkResetPrice, 'dp-dziupla-reset') then
        return { ok = false, msg = L('no_money', Config.PerkResetPrice) }
    end
    p.perks = {}
    DZ.Save(p)
    return { ok = true, msg = 'Umiejętności zresetowane.', data = DZ.Overview(src) }
end)

local function sellCommon(src, uids, scrapOnly)
    if not DZ.HasAccess(src) or not DZ.ShopAt(src) then return { ok = false, msg = L('not_at_shop') } end
    if type(uids) ~= 'table' or #uids == 0 or #uids > 200 then return { ok = false } end
    local p = DZ.Profile(src)
    local total, n = 0, 0
    for _, u in ipairs(uids) do
        local it = DZ.WhFind(p, tonumber(u))
        if it and not DZ.IsRes(p, it.u) then
            local t = Parts.Types[it.t]
            local price
            if scrapOnly then
                price = math.floor((it.k or (t and t.kg) or 1) * Config.Economy.scrapPerKg)
            else
                price = DZ.Price(p, it)
                if t then DZ.MarketSold(t.cat, price) end
            end
            if DZ.WhTake(p, it.u) then
                total = total + price
                n = n + 1
            end
        end
    end
    if n == 0 then return { ok = false, msg = 'Nic nie sprzedano.' } end
    DZ.Earn(src, p, total, scrapOnly and 'zlom' or 'paser')
    DZ.Save(p)
    return { ok = true, msg = ('Sprzedano %d szt. za %d$.'):format(n, total), data = DZ.Overview(src) }
end

DZ.register('sell', function(src, uids) return sellCommon(src, uids, false) end)
DZ.register('scrap', function(src, uids) return sellCommon(src, uids, true) end)

-- --------------------------------------------------------------------------
--  Sprzątanie
-- --------------------------------------------------------------------------
AddEventHandler('playerDropped', function()
    local src = source
    lastCall[src] = nil
    if DZ.OnDrop then
        for _, fn in ipairs(DZ.OnDrop) do pcall(fn, src) end
    end
    SrcIds[src] = nil
end)

DZ.OnDrop = {}

-- --------------------------------------------------------------------------
--  Eksporty
-- --------------------------------------------------------------------------
exports('GetLevel', function(src)
    local p = DZ.Profile(src)
    return p and DZ.Level(p) or 1
end)

exports('AddXP', function(src, amount)
    local p = DZ.Profile(src)
    if not p then return false end
    DZ.AddXP(src, p, tonumber(amount) or 0)
    DZ.Save(p)
    return true
end)

-- dodanie części do magazynu z innego skryptu: typ z Parts.Types, stan 0-100
exports('AddPart', function(src, partType, cond, mult)
    local p = DZ.Profile(src)
    if not p or not Parts.Types[partType] or DZ.WhFree(p) <= 0 then return false end
    local ok = DZ.WhAdd(p, { t = partType, c = math.floor(DZ.num(cond, 0, 100)), m = tonumber(mult) or 1.0 }) ~= nil
    DZ.Save(p)
    return ok
end)

exports('GetWarehouse', function(src)
    local p = DZ.Profile(src)
    return p and DZ.WhList(p) or {}
end)

math.randomseed(os.time())
CreateThread(function()
    Wait(500)
    print(('^2[dp-dziupla]^7 uruchomiono (framework: %s, części: %d)'):format(Bridge.name, #Parts.List))
end)
