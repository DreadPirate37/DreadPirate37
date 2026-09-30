-- ==========================================================================
--  Ekonomia: paserzy (PAS-01, PAS-09, PAS-12, PAS-13, PAS-21), lombard (PAS-02),
--  sklep czarnego rynku z dostawą do skrytki (NAR-37)
-- ==========================================================================
Economy = {}
local U = WLM.U

local function dayNumber() return math.floor(os.time() / 86400) end

-- dzisiejsza lokalizacja pasera (zmienia się codziennie)
function Economy.FenceSpot(f, idx)
    local n = #f.spots
    return f.spots[((dayNumber() + idx) % n) + 1]
end

function Economy.FenceByKey(key)
    for i, f in ipairs(Config.Fences) do
        if f.key == key then return f, i end
    end
end

SV.Register('econ:places', function(src)
    local fences = {}
    for i, f in ipairs(Config.Fences) do
        local c = Economy.FenceSpot(f, i)
        fences[#fences + 1] = { key = f.key, label = f.label, model = f.model, scenario = f.scenario, coords = { x = c.x, y = c.y, z = c.z, w = c.w } }
    end
    return { ok = true, fences = fences }
end, 2000)

local function repMult(rep)
    local m, label = 1.0, Config.FenceRep[1].label
    for _, r in ipairs(Config.FenceRep) do
        if rep >= r.rep then m, label = r.mult, r.label end
    end
    return m, label
end

local function trunkNear(src, netId)
    local veh = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return nil end
    local pc = SV.Coords(src)
    if not pc or #(pc - GetEntityCoords(veh)) > 12.0 then return nil end
    return Bag.CleanPlate(GetVehicleNumberPlateText(veh))
end

local function limitsLeft(src)
    local prof = Progress.Get(src)
    local today = Store.Today()
    if prof.sales.day ~= today then prof.sales = { day = today, value = 0 } end
    local econ = Store.Doc('econ', {})
    if econ.day ~= today then econ.day = today econ.value = 0 Store.TouchDoc('econ') end
    return math.max(0, Config.Limits.playerDaily - prof.sales.value), math.max(0, Config.Limits.serverDaily - econ.value)
end

local function priceFor(item, f, mult)
    local def = Config.Loot[item.key]
    if not def then return nil end
    local catMult = f.buys[def.cat]
    if not catMult then return nil end
    return math.floor(item.value * catMult * mult * (1 - Config.FenceCut))
end

-- lista tego, co paser kupi: z torby i z bagażnika pobliskiego auta
SV.Register('fence:offer', function(src, key, netId)
    local f, idx = Economy.FenceByKey(key)
    if not f then return { ok = false } end
    local spot = Economy.FenceSpot(f, idx)
    if not SV.Near(src, spot, 5.0) then return { ok = false, msg = L('too_far') } end
    local rep = Progress.Rep(src, 'fence_' .. f.key)
    local mult, repLabel = repMult(rep)
    local out = {}
    for _, it in ipairs(Bag.Items(src)) do
        local price = priceFor(it, f, mult)
        if price then out[#out + 1] = { uid = it.uid, label = Config.Loot[it.key].label, price = price, from = 'bag', kg = it.kg } end
    end
    local plate = netId and trunkNear(src, netId)
    if plate then
        for _, it in ipairs(Bag.Trunk(plate)) do
            local price = priceFor(it, f, mult)
            if price then out[#out + 1] = { uid = it.uid, label = Config.Loot[it.key].label, price = price, from = 'trunk', kg = it.kg } end
        end
    end
    local pl, sl = limitsLeft(src)
    return { ok = true, fence = f.label, items = out, rep = rep, repLabel = repLabel, limit = math.min(pl, sl), cut = Config.FenceCut }
end, 800)

SV.Register('fence:sell', function(src, key, uids, netId)
    local f, idx = Economy.FenceByKey(key)
    if not f or type(uids) ~= 'table' then return { ok = false } end
    if not SV.Near(src, Economy.FenceSpot(f, idx), 5.0) then return { ok = false, msg = L('too_far') } end
    local mult = repMult(Progress.Rep(src, 'fence_' .. f.key))
    local want = {}
    for _, u in ipairs(uids) do if type(u) == 'string' then want[u] = true end end

    local total, sellBag, sellTrunk = 0, {}, {}
    for _, it in ipairs(Bag.Items(src)) do
        if want[it.uid] then
            local p = priceFor(it, f, mult)
            if p then total = total + p sellBag[#sellBag + 1] = it.uid end
        end
    end
    local plate = netId and trunkNear(src, netId)
    local trunk = plate and Bag.Trunk(plate)
    if trunk then
        for _, it in ipairs(trunk) do
            if want[it.uid] then
                local p = priceFor(it, f, mult)
                if p then total = total + p sellTrunk[it.uid] = true end
            end
        end
    end
    if total <= 0 then return { ok = false, msg = L('nothing_to_sell') } end
    local pl, sl = limitsLeft(src)
    if total > math.min(pl, sl) then return { ok = false, msg = L('limit_reached', math.min(pl, sl)) } end

    Bag.RemoveUids(src, sellBag)
    if trunk and next(sellTrunk) then
        local keep = {}
        for _, it in ipairs(trunk) do if not sellTrunk[it.uid] then keep[#keep + 1] = it end end
        Store.Doc('trunks', {})[plate] = keep
        Bag.TrunkTouch()
    end
    Bridge.AddMoney(src, total, 'paser')
    local prof = Progress.Get(src)
    prof.sales.value = prof.sales.value + total
    local econ = Store.Doc('econ', {})
    econ.value = (econ.value or 0) + total
    Store.TouchDoc('econ')
    Progress.AddRep(src, 'fence_' .. f.key, total / 10)
    Progress.AddXP(src, total * Config.XP.perSale, 'sprzedaz')
    Bag.Sync(src)
    Contracts.Hook(src, 'sale', { value = total })
    SV.Log('paser', ('%s sprzedał za %d$ u %s'):format(GetPlayerName(src) or src, total, f.label))
    return { ok = true, msg = L('sold', total) }
end, 1500)

-- --------------------------------------------------------------------------
--  Lombard (PAS-02): legalna gotówka, tylko czysty towar; gorący odrzuca i czasem zgłasza
-- --------------------------------------------------------------------------
local function pawnPrice(it)
    local def = Config.Loot[it.key]
    if not def or not Config.Pawn.buys[def.cat] then return nil end
    return math.floor(it.value * Config.Pawn.mult)
end

SV.Register('pawn:offer', function(src)
    if not SV.Near(src, Config.Pawn.ped.coords, 5.0) then return { ok = false, msg = L('too_far') } end
    local out, now = {}, os.time()
    for _, it in ipairs(Bag.Items(src)) do
        local p = pawnPrice(it)
        if p then
            out[#out + 1] = { uid = it.uid, label = Config.Loot[it.key].label, price = p, from = 'bag', hot = now - (it.t or 0) < Config.Pawn.hotHours * 3600, kg = it.kg }
        end
    end
    return { ok = true, fence = Config.Pawn.label, items = out, pawn = true, limit = math.min(limitsLeft(src)) }
end, 800)

SV.Register('pawn:sell', function(src, uids)
    if type(uids) ~= 'table' or not SV.Near(src, Config.Pawn.ped.coords, 5.0) then return { ok = false } end
    local want, now = {}, os.time()
    for _, u in ipairs(uids) do want[u] = true end
    local total, sell, hot = 0, {}, false
    for _, it in ipairs(Bag.Items(src)) do
        if want[it.uid] then
            local p = pawnPrice(it)
            if p then
                if now - (it.t or 0) < Config.Pawn.hotHours * 3600 then hot = true
                else total = total + p sell[#sell + 1] = it.uid end
            end
        end
    end
    if hot then
        if math.random() < Config.Pawn.reportChance then
            local c = Config.Pawn.ped.coords
            Police.Alert('pawn', c, 'city', L('dispatch_pawn_desc', Bridge.GetName(src)), src)
            Progress.AddHeat(src, Config.Heat.add.witness)
        end
        return { ok = false, msg = L('pawn_hot') }
    end
    if total <= 0 then return { ok = false, msg = L('nothing_to_sell') } end
    local pl, sl = limitsLeft(src)
    if total > math.min(pl, sl) then return { ok = false, msg = L('limit_reached', math.min(pl, sl)) } end
    Bag.RemoveUids(src, sell)
    Bridge.AddMoney(src, total, 'lombard', false)
    local prof = Progress.Get(src)
    prof.sales.value = prof.sales.value + total
    Bag.Sync(src)
    return { ok = true, msg = L('sold', total) }
end, 1500)

-- --------------------------------------------------------------------------
--  Sklep czarnego rynku z dostawą do skrytki (NAR-37)
-- --------------------------------------------------------------------------
function Economy.ItemLabel(item)
    for _, lp in ipairs(Config.Items.lockpicks) do if lp.item == item then return lp.label end end
    for _, g in ipairs(Config.Items.gloves) do if g.item == item then return g.label end end
    for _, b in ipairs(Config.Items.bags) do if b.item == item then return b.label end end
    return L('item_' .. item)
end

function Economy.ShopView(src)
    local lvl = Progress.Level(src)
    local out = {}
    for i, s in ipairs(Config.Shop.items) do
        out[#out + 1] = { i = i, item = s.item, label = Economy.ItemLabel(s.item), price = s.price, minLevel = s.minLevel, locked = lvl < s.minLevel }
    end
    local prof = Progress.Get(src)
    local orders = {}
    for i, o in ipairs(prof.orders or {}) do
        local d = Config.Shop.drops[o.drop]
        orders[#orders + 1] = { i = i, ready = o.readyAt <= os.time(), left = math.max(0, o.readyAt - os.time()), coords = { x = d.x, y = d.y, z = d.z }, n = #o.items }
    end
    return { items = out, orders = orders }
end

SV.Register('shop:orders', function(src)
    return { ok = true, orders = Economy.ShopView(src).orders }
end, 1000)

SV.Register('shop:buy', function(src, index, qty)
    local s = Config.Shop.items[tonumber(index) or 0]
    qty = math.floor(U.Clamp(tonumber(qty) or 1, 1, 10))
    if not s then return { ok = false } end
    if Progress.Level(src) < s.minLevel then return { ok = false, msg = L('level_low') } end
    local prof = Progress.Get(src)
    if #prof.orders >= 3 then return { ok = false, msg = L('orders_full') } end
    local cost = s.price * qty
    if not Bridge.RemoveMoney(src, cost, 'czarny rynek') then return { ok = false, msg = L('no_money', cost) } end
    local drop = math.random(#Config.Shop.drops)
    prof.orders[#prof.orders + 1] = { items = { { item = s.item, count = qty } }, drop = drop, readyAt = os.time() + Config.Shop.deliveryMinutes * 60 }
    Store.Touch(prof.id)
    return { ok = true, msg = L('order_placed', Config.Shop.deliveryMinutes), shop = Economy.ShopView(src) }
end, 1000)

SV.Register('shop:collect', function(src)
    local prof = Progress.Get(src)
    local now, got, keep = os.time(), 0, {}
    for _, o in ipairs(prof.orders or {}) do
        local d = Config.Shop.drops[o.drop]
        if o.readyAt <= now and SV.Near(src, d, 3.0) then
            for _, it in ipairs(o.items) do
                if Bridge.AddItem(src, it.item, it.count) then got = got + it.count end
            end
        else
            keep[#keep + 1] = o
        end
    end
    prof.orders = keep
    Store.Touch(prof.id)
    if got == 0 then return { ok = false, msg = L('drop_empty') } end
    return { ok = true, msg = L('drop_collected', got) }
end, 1500)
