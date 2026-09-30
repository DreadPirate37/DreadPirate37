-- ==========================================================================
--  Magazyn części i materiały eksploatacyjne – dwa tryby:
--    'ox'       – części to itemy ox_inventory (dz_part + metadane) w stashu gracza,
--                 materiały (wytrychy, tarcze, penetrant, wykrętaki) to itemy w ekwipunku
--    'internal' – wszystko w profilu KVP skryptu (bez zależności)
--  Reszta kodu używa tylko funkcji DZ.Wh* / DZ.Cons* / DZ.Res* z tego pliku.
-- ==========================================================================
local I = Config.Inventory
local mode = I.mode
if mode == 'auto' then mode = GetResourceState('ox_inventory') ~= 'missing' and 'ox' or 'internal' end
DZ.InvMode = mode
local OX = mode == 'ox'
local ox = OX and exports.ox_inventory or nil

-- --------------------------------------------------------------------------
--  Rezerwacje (zamówienia w drodze, część na stole) – tylko w pamięci serwera
-- --------------------------------------------------------------------------
local Res = {}   -- [identyfikator] = { [uid] = true }

function DZ.IsRes(p, uid) return Res[p.id] ~= nil and Res[p.id][uid] == true end

function DZ.SetRes(p, uid, on)
    Res[p.id] = Res[p.id] or {}
    Res[p.id][uid] = on and true or nil
end

-- --------------------------------------------------------------------------
--  Wspólne
-- --------------------------------------------------------------------------
function DZ.WhCap(p)
    return Config.Warehouse.baseSlots + (p.upg.shelf or 0) * Config.Warehouse.perShelf
end

local function nextUid(p)
    p.seq = (p.seq or 0) + 1
    return p.seq
end

local function meta(it)
    local t = Parts.Types[it.t] or {}
    local label = DZ.ItemLabel(it)
    local desc = ('Stan: %d%%'):format(it.c or 0)
    if it.v then desc = desc .. ' · z auta: ' .. it.v end
    if it.r then desc = desc .. ' · regenerowana' end
    return {
        dzid = it.u, t = it.t, c = it.c, m = it.m, v = it.v, r = it.r, k = it.k,
        label = ('%s (%d%%)'):format(label, it.c or 0), description = desc,
        weight = math.floor(((it.t == 'scrap' and it.k) or t.kg or 1) * 1000),
        image = I.images and ('dz_' .. it.t) or nil,
    }
end

local function fromMeta(slot)
    local m = slot.metadata or {}
    if not m.t or not m.dzid then return nil end
    return { u = m.dzid, t = m.t, c = m.c, m = m.m, v = m.v, r = m.r, k = m.k, slot = slot.slot }
end

-- ==========================================================================
--  Tryb ox_inventory
-- ==========================================================================
if OX then
    local registered = {}

    local function stashId(p)
        return 'dz_wh_' .. tostring(p.id):gsub('[^%w]', '_')
    end
    DZ.StashId = stashId

    -- stash tworzony leniwie; pojemność rośnie z regałami
    local function stash(p)
        local id = stashId(p)
        local cap = DZ.WhCap(p)
        if not registered[id] then
            ox:RegisterStash(id, I.stashLabel, cap, I.stashWeight, false)
            registered[id] = cap
            -- migracja: części z magazynu wewnętrznego trafiają do stasha
            if p.wh and #p.wh > 0 then
                for _, it in ipairs(p.wh) do ox:AddItem(id, I.partItem, 1, meta(it)) end
                p.wh = {}
                DZ.Save(p)
            end
        elseif registered[id] ~= cap then
            pcall(function() ox:SetSlotCount(id, cap) end)
            registered[id] = cap
        end
        return id
    end
    DZ.Stash = stash

    function DZ.WhList(p)
        local id = stash(p)
        local out = {}
        for _, slot in pairs(ox:GetInventoryItems(id) or {}) do
            if slot.name == I.partItem then
                local it = fromMeta(slot)
                if it then out[#out + 1] = it end
            end
        end
        table.sort(out, function(a, b) return a.u < b.u end)
        return out
    end

    function DZ.WhCount(p) return #DZ.WhList(p) end

    function DZ.WhFree(p) return DZ.WhCap(p) - DZ.WhCount(p) end

    function DZ.WhAdd(p, item)
        local id = stash(p)
        item.u = nextUid(p)
        local ok = ox:AddItem(id, I.partItem, 1, meta(item))
        if not ok then
            DZ.dbg('ox: nie zmieściło się ' .. tostring(item.t))
            return nil
        end
        return item
    end

    function DZ.WhFind(p, uid)
        for _, it in ipairs(DZ.WhList(p)) do
            if it.u == uid then return it end
        end
    end

    function DZ.WhTake(p, uid)
        local it = DZ.WhFind(p, uid)
        if not it then return nil end
        if not ox:RemoveItem(stash(p), I.partItem, 1, nil, it.slot) then return nil end
        DZ.SetRes(p, uid, false)
        return it
    end

    function DZ.WhUpdate(p, it)
        local cur = DZ.WhFind(p, it.u)
        if cur then ox:SetMetadata(stash(p), cur.slot, meta(it)) end
    end

    -- materiały eksploatacyjne = itemy w ekwipunku gracza
    function DZ.ConsCount(src, p, key)
        local name = I.items[key]
        if not name then return 0 end
        return ox:Search(src, 'count', name) or 0
    end

    function DZ.ConsUse(src, p, key, n)
        n = math.min(n, DZ.ConsCount(src, p, key))
        if n > 0 then ox:RemoveItem(src, I.items[key], n) end
    end

    function DZ.ConsAdd(src, p, key, n)
        local name = I.items[key]
        if not name or not ox:CanCarryItem(src, name, n) then return false end
        return ox:AddItem(src, name, n) and true or false
    end

    -- otwarcie stasha przy regale (serwer sprawdza odległość, klient nie otworzy go sam)
    DZ.register('openStash', function(src)
        local ok = false
        for _, shop in ipairs(Config.Shops) do
            if DZ.Near(src, shop.shelf, 3.5) then ok = true end
        end
        if not ok then return { ok = false, msg = L('too_far') } end
        local p = DZ.Profile(src)
        ox:forceOpenInventory(src, 'stash', stash(p))
        return { ok = true }
    end)

-- ==========================================================================
--  Tryb wewnętrzny (KVP)
-- ==========================================================================
else
    function DZ.WhList(p) return p.wh end

    function DZ.WhCount(p) return #p.wh end

    function DZ.WhFree(p) return DZ.WhCap(p) - #p.wh end

    function DZ.WhAdd(p, item)
        if DZ.WhFree(p) <= 0 then return nil end
        item.u = nextUid(p)
        p.wh[#p.wh + 1] = item
        return item
    end

    function DZ.WhFind(p, uid)
        for i, it in ipairs(p.wh) do
            if it.u == uid then return it, i end
        end
    end

    function DZ.WhTake(p, uid)
        for i, it in ipairs(p.wh) do
            if it.u == uid then
                table.remove(p.wh, i)
                DZ.SetRes(p, uid, false)
                return it
            end
        end
    end

    function DZ.WhUpdate(p, it) end   -- tabela w profilu jest już zmieniona

    function DZ.ConsCount(src, p, key) return p.cons[key] or 0 end

    function DZ.ConsUse(src, p, key, n)
        p.cons[key] = math.max(0, (p.cons[key] or 0) - n)
    end

    function DZ.ConsAdd(src, p, key, n)
        p.cons[key] = (p.cons[key] or 0) + n
        return true
    end

    DZ.register('openStash', function() return { ok = false } end)
end

-- wszystkie materiały naraz (dla NUI demontażu)
function DZ.ConsTable(src, p)
    local out = {}
    for k in pairs(Config.Consumables) do out[k] = DZ.ConsCount(src, p, k) end
    return out
end

CreateThread(function()
    Wait(700)
    print(('^2[dp-dziupla]^7 magazyn: %s'):format(OX and 'ox_inventory (item ' .. I.partItem .. ')' or 'wewnętrzny (KVP)'))
end)
