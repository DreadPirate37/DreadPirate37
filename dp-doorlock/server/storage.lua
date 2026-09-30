-- ==========================================================================
--  Magazyn: definicje drzwi (data/doors.json), stany (KVP), dziennik (RAM)
-- ==========================================================================
Store = {
    doors = {},        -- [id] = definicja (pełna, z sekretami)
    order = {},        -- lista id (stała kolejność dla panelu)
    removedKeys = {},  -- klucze drzwi z configu usunięte w edytorze
    nextId = 1,
    logs = {},         -- [id] = { head, n, items = {} }  bufor cykliczny
    pos = {},          -- [id] = vector3 środka (szybkie sprawdzanie dystansu)
}
local S = Store
local RES = GetCurrentResourceName()
local FILE = 'data/doors.json'

local function vecOf(t) return vector3(t.x, t.y, t.z) end

local function rebuildOrder()
    local o = {}
    for id in pairs(S.doors) do o[#o + 1] = id end
    table.sort(o)
    S.order = o
end

-- --------------------------------------------------------------------------
--  Zapis z opóźnieniem – wiele edycji w krótkim czasie = jeden zapis
-- --------------------------------------------------------------------------
local savePending = false
function S.Save()
    if savePending then return end
    savePending = true
    SetTimeout(Config.Perf.saveDebounce, function()
        savePending = false
        local list = {}
        for _, id in ipairs(S.order) do list[#list + 1] = S.doors[id] end
        local removed = {}
        for k in pairs(S.removedKeys) do removed[#removed + 1] = k end
        local ok = SaveResourceFile(RES, FILE, json.encode({
            version = 1, nextId = S.nextId, doors = list, removedKeys = removed,
        }), -1)
        if not ok then print('^1[dp-doorlock] Nie udało się zapisać ' .. FILE .. ' (czy istnieje katalog data/?)^7') end
    end)
end

function S.Put(def)
    if not def.id then
        def.id = S.nextId
        S.nextId = S.nextId + 1
    end
    S.doors[def.id] = def
    S.pos[def.id] = vecOf(def.coords)
    rebuildOrder()
    S.Save()
    return def
end

function S.Remove(id)
    local d = S.doors[id]
    if not d then return false end
    if d.key then S.removedKeys[d.key] = true end
    S.doors[id] = nil
    S.logs[id] = nil
    S.pos[id] = nil
    DeleteResourceKvp('state:' .. id)
    rebuildOrder()
    S.Save()
    return true
end

-- --------------------------------------------------------------------------
--  Wczytanie + scalenie z Config.Doors
-- --------------------------------------------------------------------------
function S.Load()
    local raw = LoadResourceFile(RES, FILE)
    local data = raw and raw ~= '' and json.decode(raw) or nil
    local byKey, dirty = {}, false

    if type(data) == 'table' then
        S.nextId = tonumber(data.nextId) or 1
        for _, k in ipairs(data.removedKeys or {}) do S.removedKeys[k] = true end
        for _, d in ipairs(data.doors or {}) do
            local n = Door.Normalize(d)
            if n and n.id then
                S.doors[n.id] = n
                S.pos[n.id] = vecOf(n.coords)
                if n.id >= S.nextId then S.nextId = n.id + 1 end
                if n.key then byKey[n.key] = true end
            end
        end
    end

    for _, d in ipairs(Config.Doors) do
        if d.key and not byKey[d.key] and not S.removedKeys[d.key] then
            local copy = {}
            for k, v in pairs(d) do copy[k] = v end
            copy.id = nil
            local n, err = Door.Normalize(copy)
            if n then
                n.id = S.nextId
                S.nextId = S.nextId + 1
                S.doors[n.id] = n
                S.pos[n.id] = vecOf(n.coords)
                dirty = true
            else
                print(('^3[dp-doorlock] Pominięto drzwi z configu %s: %s^7'):format(d.key, err))
            end
        end
    end
    rebuildOrder()
    if dirty or not data then S.Save() end
    print(('^2[dp-doorlock]^7 wczytano %d drzwi'):format(#S.order))
end

-- --------------------------------------------------------------------------
--  Stan zamka (persystencja przez KVP – jeden klucz na drzwi, zapis tylko przy zmianie)
-- --------------------------------------------------------------------------
function S.SavedLock(id)
    if not Config.PersistState then return nil end
    local v = GetResourceKvpInt('state:' .. id)
    if v == 0 then return nil end
    return v == 2
end

function S.PersistLock(id, locked)
    if Config.PersistState then SetResourceKvpInt('state:' .. id, locked and 2 or 1) end
end

-- --------------------------------------------------------------------------
--  Dziennik zdarzeń – bufor cykliczny O(1)
-- --------------------------------------------------------------------------
function S.Log(id, src, action, extra)
    local size = Config.Perf.logSize
    local l = S.logs[id]
    if not l then
        l = { head = 0, n = 0, items = {} }
        S.logs[id] = l
    end
    l.head = l.head % size + 1
    l.items[l.head] = {
        t = os.time(), a = action, x = extra,
        who = src and src > 0 and Bridge.GetName(src) or 'System',
    }
    if l.n < size then l.n = l.n + 1 end
    if Hooks and Hooks.OnLog then Hooks.OnLog(id, src, action, extra) end
end

--- Najnowsze wpisy (od najnowszego)
function S.GetLogs(id, limit)
    local l, out = S.logs[id], {}
    if not l then return out end
    local size = Config.Perf.logSize
    local idx = l.head
    for _ = 1, math.min(l.n, limit or l.n) do
        out[#out + 1] = l.items[idx]
        idx = idx - 1
        if idx < 1 then idx = size end
    end
    return out
end
