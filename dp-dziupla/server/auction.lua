-- ==========================================================================
--  Giełda części między graczami (aukcje). Stan w KVP, działa też offline:
--  pieniądze i części czekają, aż gracz otworzy ChopNet.
-- ==========================================================================
local A = Config.Auction
local Auctions = {}   -- [aid] = { id, seller, sellerName, item, start, bid, bidder, bidderName, ends, buyout }
local Pending = {}    -- [identyfikator] = { money = n, items = { item, ... } }
local seq = 0

local function save()
    SetResourceKvp('dz:auctions', json.encode({ list = Auctions, pending = Pending, seq = seq }))
end

local function load()
    local raw = GetResourceKvpString('dz:auctions')
    local d = raw and json.decode(raw) or {}
    for _, a in pairs(d.list or {}) do Auctions[a.id] = a end
    Pending = d.pending or {}
    seq = d.seq or 0
end

local function onlineSrc(id)
    for _, pid in ipairs(GetPlayers()) do
        local p = DZ.Profile(tonumber(pid))
        if p and p.id == id then return tonumber(pid) end
    end
end

local function pend(id) Pending[id] = Pending[id] or { money = 0, items = {} } return Pending[id] end

local function payTo(id, amount, why)
    if amount <= 0 then return end
    local src = onlineSrc(id)
    if src then
        Bridge.AddMoney(src, Config.PayAccount, amount, 'dp-dziupla-gielda')
        Bridge.Notify(src, why .. (' (+%d$)'):format(amount), 'good')
    else
        pend(id).money = pend(id).money + amount
    end
end

local function giveItem(id, item)
    local p = DZ.ProfileById(id)
    item.u = nil
    if p and DZ.WhAdd(p, item) then
        DZ.Save(p)
        return
    end
    local q = pend(id)
    q.items[#q.items + 1] = item
end

-- wypłata zaległości przy otwarciu laptopa
local function settlePending(src, p)
    local q = Pending[p.id]
    if not q then return end
    if q.money > 0 then
        Bridge.AddMoney(src, Config.PayAccount, q.money, 'dp-dziupla-gielda')
        Bridge.Notify(src, ('Giełda: zaległe %d$ wypłacone.'):format(q.money), 'good')
        q.money = 0
    end
    local left = {}
    for _, it in ipairs(q.items) do
        if not DZ.WhAdd(p, it) then left[#left + 1] = it end
    end
    q.items = left
    if #left == 0 and q.money == 0 then Pending[p.id] = nil end
    DZ.Save(p)
    save()
end

local function finish(a)
    Auctions[a.id] = nil
    if a.bidder then
        giveItem(a.bidder, a.item)
        payTo(a.seller, math.floor(a.bid * (1 - A.fee)), 'Giełda: sprzedano ' .. DZ.ItemLabel(a.item))
        local w = onlineSrc(a.bidder)
        if w then Bridge.Notify(w, 'Giełda: wygrałeś ' .. DZ.ItemLabel(a.item) .. ' – część w magazynie.', 'good') end
        DZ.Log('earn', nil, 'Giełda', ('%s → %s za %d$'):format(DZ.ItemLabel(a.item), a.bidderName or '?', a.bid), 'earn')
    else
        giveItem(a.seller, a.item)
    end
    save()
end

CreateThread(function()
    load()
    while true do
        Wait(30000)
        local now = os.time()
        for _, a in pairs(Auctions) do
            if now >= a.ends then finish(a) end
        end
    end
end)

-- --------------------------------------------------------------------------
--  Akcje
-- --------------------------------------------------------------------------
DZ.register('auctionList', function(src, uid, price, dur)
    if not A.enabled or not DZ.HasAccess(src) then return { ok = false } end
    if A.requireShop and not DZ.ShopAt(src) then return { ok = false, msg = L('not_at_shop') } end
    local p = DZ.Profile(src)
    local mine = 0
    for _, a in pairs(Auctions) do if a.seller == p.id then mine = mine + 1 end end
    if mine >= A.maxPerPlayer then return { ok = false, msg = ('Maks. %d aukcji naraz.'):format(A.maxPerPlayer) } end
    price = math.floor(tonumber(price) or 0)
    if price < A.minPrice then return { ok = false, msg = ('Cena wywoławcza min. %d$.'):format(A.minPrice) } end
    local it = DZ.WhFind(p, tonumber(uid))
    if not it or DZ.IsRes(p, it.u) then return { ok = false, msg = L('error') } end
    it = DZ.WhTake(p, it.u)
    if not it then return { ok = false, msg = L('error') } end
    it.slot = nil
    seq = seq + 1
    local d = A.durations[tonumber(dur) or 1] or A.durations[1]
    local aid = tostring(seq)
    Auctions[aid] = { id = aid, seller = p.id, sellerName = GetPlayerName(src), item = it, start = price, ends = os.time() + d }
    DZ.Save(p)
    save()
    return { ok = true, msg = 'Wystawiono na giełdę.', data = DZ.Overview(src) }
end)

DZ.register('auctionBid', function(src, aid, amount)
    local a = Auctions[tostring(aid)]
    if not a or os.time() >= a.ends then return { ok = false, msg = 'Aukcja się skończyła.' } end
    local p = DZ.Profile(src)
    if a.seller == p.id then return { ok = false, msg = 'Nie licytujesz własnej części.' } end
    if a.bidder == p.id then return { ok = false, msg = 'Już prowadzisz.' } end
    amount = math.floor(tonumber(amount) or 0)
    local min = a.bid and math.max(a.bid + A.minStepAbs, math.floor(a.bid * (1 + A.minStep))) or a.start
    if amount < min then return { ok = false, msg = ('Minimalna oferta: %d$.'):format(min) } end
    if not Bridge.RemoveMoney(src, Config.PayAccount, amount, 'dp-dziupla-gielda') then return { ok = false, msg = L('no_money', amount) } end
    if a.bidder then payTo(a.bidder, a.bid, 'Giełda: ktoś cię przebił – zwrot') end
    a.bid, a.bidder, a.bidderName = amount, p.id, GetPlayerName(src)
    if a.ends - os.time() < 60 then a.ends = os.time() + 60 end   -- bez snajpienia w ostatniej sekundzie
    save()
    return { ok = true, msg = ('Prowadzisz: %d$.'):format(amount), data = DZ.Overview(src) }
end)

DZ.register('auctionCancel', function(src, aid)
    local a = Auctions[tostring(aid)]
    local p = DZ.Profile(src)
    if not a or a.seller ~= p.id then return { ok = false } end
    if a.bidder then return { ok = false, msg = 'Ktoś już licytuje – nie można wycofać.' } end
    Auctions[a.id] = nil
    giveItem(p.id, a.item)
    save()
    return { ok = true, msg = 'Część wróciła do magazynu.', data = DZ.Overview(src) }
end)

function DZ.AuctionView(src, p, data)
    if not A.enabled then return end
    settlePending(src, p)
    local list, now = {}, os.time()
    for _, a in pairs(Auctions) do
        local v = DZ.ItemView(p, a.item)
        list[#list + 1] = {
            id = a.id, label = v.label, cat = v.catLabel, cond = v.cond, vehicle = v.vehicle, fence = v.value, tuning = v.tuning,
            start = a.start, bid = a.bid, lead = a.bidder == p.id, mine = a.seller == p.id, seller = a.sellerName,
            left = math.max(0, a.ends - now),
            min = a.bid and math.max(a.bid + A.minStepAbs, math.floor(a.bid * (1 + A.minStep))) or a.start,
        }
    end
    table.sort(list, function(x, y) return x.left < y.left end)
    local q = Pending[p.id]
    data.auction = { list = list, fee = A.fee, durations = A.durations, minPrice = A.minPrice, waiting = q and #q.items or 0 }
end
