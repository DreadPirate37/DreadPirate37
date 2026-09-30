-- ==========================================================================
--  Torba na łup (LUP-02, NAR-17, LUP-25). Łup nie trafia do ekwipunku frameworka:
--  trzyma go serwer, każdy przedmiot ma unikalne uid, dom pochodzenia i czas kradzieży.
--  Dzięki temu skrypt działa z każdym ekwipunkiem, a dupowanie jest niemożliwe z założenia.
--  Duże łupy (TV, PC) nosi się w rękach i ładuje do bagażnika (LUP-03, LOG-01).
-- ==========================================================================
Bag = {}
Trunks = {}                        -- [tablica] = { przedmioty }
Carry = {}                         -- [src] = przedmiot w rękach
local seq = 0

local function uid()
    seq = seq + 1
    return ('%x%04x'):format(os.time(), seq % 0xffff)
end
Bag.Uid = uid

function Bag.Items(src)
    local p = Progress.Get(src)
    return p and p.bag or {}
end

function Bag.BestBag(src)
    local best
    for _, b in ipairs(Config.Items.bags) do
        if Bridge.ItemCount(src, b.item) > 0 and (not best or b.kg > best.kg) then best = b end
    end
    return best
end

function Bag.Capacity(src)
    if not Config.RequireItems then return Config.BagFree + 25 end
    local b = Bag.BestBag(src)
    return Config.BagFree + (b and b.kg or 0)
end

function Bag.Weight(src)
    local w = 0
    for _, it in ipairs(Bag.Items(src)) do w = w + (it.kg or 0) end
    return math.floor(w * 10 + 0.5) / 10
end

-- wartość przedmiotu ustala serwer w chwili kradzieży
function Bag.RollValue(key, mult)
    local def = Config.Loot[key]
    if not def then return 0 end
    local v = math.random(def.value[1], def.value[2])
    return math.floor(v * (mult or 1))
end

function Bag.Make(key, house, value)
    local def = Config.Loot[key]
    return { uid = uid(), key = key, value = value, kg = def and def.kg or 1, house = house, t = os.time() }
end

-- dodaje przedmiot do torby; zwraca true albo false + komunikat
function Bag.Add(src, item)
    local p = Progress.Get(src)
    if not p then return false, L('error') end
    local cap, w = Bag.Capacity(src), Bag.Weight(src)
    if w + item.kg > cap + 0.001 then return false, L('bag_full', cap) end
    -- tani worek może się rozedrzeć przy ciężkim ładunku (NAR-17)
    local b = Bag.BestBag(src)
    if b and b.tear and (w + item.kg) / cap > 0.7 and math.random() < b.tear then
        Bridge.RemoveItem(src, b.item, 1)
        SV.Notify(src, L('bag_torn'), 'bad')
        if w + item.kg > Bag.Capacity(src) + 0.001 then return false, L('bag_full', Bag.Capacity(src)) end
    end
    p.bag[#p.bag + 1] = item
    Store.Touch(p.id)
    return true
end

function Bag.RemoveUids(src, uids)
    local p = Progress.Get(src)
    if not p then return {} end
    local set, removed, keep = {}, {}, {}
    for _, u in ipairs(uids) do set[u] = true end
    for _, it in ipairs(p.bag) do
        if set[it.uid] then removed[#removed + 1] = it else keep[#keep + 1] = it end
    end
    p.bag = keep
    Store.Touch(p.id)
    return removed
end

function Bag.View(src)
    local out = {}
    for _, it in ipairs(Bag.Items(src)) do
        local def = Config.Loot[it.key] or {}
        local h = WLM.HouseById[it.house] or WLM.ShedById[it.house]
        out[#out + 1] = { uid = it.uid, key = it.key, label = def.label or it.key, kg = it.kg, cat = def.cat, house = h and h.label or '', hot = os.time() - (it.t or 0) < Config.Pawn.hotHours * 3600 }
    end
    return { items = out, kg = Bag.Weight(src), cap = Bag.Capacity(src) }
end

function Bag.Sync(src)
    SV.Client(src, 'bag', Bag.View(src))
end

-- --------------------------------------------------------------------------
--  Bagażniki (duże łupy)
-- --------------------------------------------------------------------------
local function trunkDoc() return Store.Doc('trunks', {}) end

function Bag.Trunk(plate)
    local doc = trunkDoc()
    doc[plate] = doc[plate] or {}
    return doc[plate]
end

function Bag.TrunkTouch() Store.TouchDoc('trunks') end

local function cleanPlate(p) return (p or ''):gsub('^%s+', ''):gsub('%s+$', '') end
Bag.CleanPlate = cleanPlate

-- --------------------------------------------------------------------------
--  Noszenie dużych przedmiotów
-- --------------------------------------------------------------------------
function Bag.StartCarry(src, item)
    Carry[src] = item
    SV.Client(src, 'carry', { key = item.key, prop = Config.Loot[item.key].prop })
end

function Burglary_DropCarryInternal(src)
    local c = Carry[src]
    Carry[src] = nil
    if c then SV.Client(src, 'carry', nil) end
    return c
end

SV.Register('loot:trunk', function(src, netId, vclass)
    local c = Carry[src]
    if not c then return { ok = false, msg = L('not_carrying') } end
    local veh = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return { ok = false, msg = L('no_vehicle') } end
    local pc = SV.Coords(src)
    if not pc or #(pc - GetEntityCoords(veh)) > 6.0 then return { ok = false, msg = L('too_far') } end
    local plate = cleanPlate(GetVehicleNumberPlateText(veh))
    if plate == '' then return { ok = false, msg = L('no_vehicle') } end
    local slots = Config.TrunkSlots[math.floor(tonumber(vclass) or -1)] or Config.TrunkSlots.default
    local trunk = Bag.Trunk(plate)
    if #trunk >= slots then return { ok = false, msg = L('trunk_full', slots) } end
    trunk[#trunk + 1] = c
    Bag.TrunkTouch()
    Burglary_DropCarryInternal(src)
    return { ok = true, msg = L('trunk_loaded', Config.Loot[c.key].label, #trunk, slots) }
end, 500)

SV.Register('loot:drop', function(src)
    local c = Burglary_DropCarryInternal(src)
    if not c then return { ok = false } end
    -- w domu przedmiot wraca na miejsce, poza domem przepada (rozbity przy upuszczeniu)
    local back = Burglary.ReturnCarry(src, c)
    return { ok = true, msg = back and L('put_back') or L('dropped_item') }
end, 500)

SV.Register('bag:view', function(src)
    return { ok = true, bag = Bag.View(src) }
end, 500)

-- klient zgłasza sieciowy prop noszonego przedmiotu (potrzebne przy zmianie bucketu)
SV.Register('carry:net', function(src, net)
    if Carry[src] then Carry[src].net = tonumber(net) end
    return { ok = true }
end, 300)
