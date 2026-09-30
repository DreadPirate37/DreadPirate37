-- ==========================================================================
--  dp-mechanic – serwer: zlecenia, projekty klientów, magazyn i dostawy
--  Baza danych jest źródłem prawdy (zapis przy każdej zmianie); w pamięci są
--  tylko świeżo używane zlecenia. Każda zmiana zlecenia przechodzi przez
--  blokadę (Orders.Mutate), więc równoległe akcje kilku mechaników się nie gubią.
--  Ceny i robocizna liczone wyłącznie na serwerze (Catalog.Build × mnożnik cen).
-- ==========================================================================
Orders = { cache = {} }

local cache = Orders.cache
local touched = {}       -- [id] = os.time() ostatniego użycia
local locks = {}         -- [klucz] = true
local pending = {}       -- [ws] = { { id, ws, key, label, qty, eta, done } } – dostawy w drodze
local deliverySeq = 0
local calls = {}         -- limity: [src] = { [nazwa] = GetGameTimer() }
local schema = { checked = false, km = false }
Orders.schema = schema

local MAX_ITEMS = 120
local VEH_RADIUS = 15.0
local STATUSES = { open = true, progress = true, ready = true, invoiced = true, paid = true, cancelled = true }
local WORKABLE = { open = true, progress = true, ready = true }   -- można pobierać części i montować
local EDITABLE = { open = true, progress = true, ready = true }   -- można dodawać / usuwać pozycje
local KIND_ORDER = { service = 1, wear = 2, align = 3, swap = 4, perf = 5, nitro = 6, mod = 7, extra = 8, wheels = 9, tire = 10, paint = 11, custom = 12 }
local WHEEL_MAPS = { 'wheelsDone', 'takenWheels', 'fromStockW' }
local CATEGORY_LABELS = {
    body = 'Nadwozie', engine = 'Silnik', perf = 'Osiągi', wheels = 'Koła i opony',
    wear = 'Eksploatacja', nitro = 'Nitro', swap = 'Swapy', paint = 'Lakier',
}
local PROP_KEYS = {
    plateIndex = true, color1 = true, color2 = true, pearlescentColor = true, wheelColor = true, wheels = true,
    windowTint = true, xenonColor = true, neonEnabled = true, neonColor = true, tyreSmokeColor = true,
    interiorColor = true, dashboardColor = true, livery = true, paintType1 = true, paintType2 = true,
    extras = true, modVariation = true, customPrimaryColor = true, customSecondaryColor = true,
}

-- --------------------------------------------------------------------------
--  Narzędzia
-- --------------------------------------------------------------------------
local function now() return os.time() end

local function dbWait()
    if DB and DB.Await then DB.Await() end
end

local function deny(msg) return DPM.Deny(msg) end

local function num(v, lo, hi, def)
    v = tonumber(v)
    if not v or v ~= v or v == math.huge or v == -math.huge then return def end
    if lo and v < lo then v = lo end
    if hi and v > hi then v = hi end
    return v
end

local function int(v, lo, hi, def)
    v = num(v, nil, nil, nil)
    if not v then return def end
    v = math.floor(v)
    if lo and v < lo then v = lo end
    if hi and v > hi then v = hi end
    return v
end

-- ścisły indeks 1..n (bez przycinania)
local function index(v, n)
    v = tonumber(v)
    if not v or v ~= math.floor(v) or v < 1 or v > n then return nil end
    return math.floor(v)
end

-- identyfikator rekordu (liczba całkowita ≥ 1)
local function posId(v)
    return index(v, 2147483647)
end

local function utf8Fix(s)
    if utf8.len(s) then return s end
    for _ = 1, 3 do
        s = s:sub(1, -2)
        if utf8.len(s) then return s end
    end
    return (s:gsub('[\128-\255]', ''))
end

local function cut(s, max)
    if utf8.len(s) > max then s = s:sub(1, utf8.offset(s, max + 1) - 1) end
    return s
end

-- tekst jednoliniowy od klienta
local function str(s, max)
    local t = type(s)
    if t == 'number' then s = tostring(s) elseif t ~= 'string' then return nil end
    s = s:gsub('[%c<>]', ' '):gsub('%s+', ' ')
    s = utf8Fix(Utils.Trim(s))
    if s == '' then return nil end
    s = Utils.Trim(cut(s, max or 64))
    return s ~= '' and s or nil
end

-- tekst wieloliniowy (notatki)
local function text(s, max)
    if type(s) ~= 'string' then return '' end
    s = s:gsub('\r\n?', '\n'):gsub('[\0-\9\11-\31\127<>]', ''):gsub('\n\n\n+', '\n\n')
    s = utf8Fix(Utils.Trim(s))
    return Utils.Trim(cut(s, max or 500))
end

local function nz(v)
    if v == nil or v == '' then return nil end
    return v
end

local function decode(s, def)
    if type(s) ~= 'string' or s == '' then return def end
    local ok, v = pcall(json.decode, s)
    if ok and v ~= nil then return v end
    return def
end

local function normPlate(p)
    if Vehicles and Vehicles.NormPlate then return Vehicles.NormPlate(p) end
    if type(p) ~= 'string' then return nil end
    p = Utils.Plate(p)
    return (p ~= '' and #p <= 16) and p or nil
end

local function entFromNet(netId)
    return Vehicles.Entity(netId)
end

local function throttle(src, name, ms)
    local c = calls[src]
    if not c then c = {} calls[src] = c end
    local t = GetGameTimer()
    if c[name] and t - c[name] < ms then return false end
    c[name] = t
    return true
end

local function pdist(a, b)
    local pa, pb = GetPlayerPed(a), GetPlayerPed(b)
    if pa == 0 or pb == 0 then return math.huge end
    return #(GetEntityCoords(pa) - GetEntityCoords(pb))
end

local function wsLabel(id)
    local ws = Config.Workshops[id or '']
    return ws and ws.label or ''
end

local function priceMult(ws)
    local v = Business and Business.PriceMult and tonumber(Business.PriceMult(ws))
    return (v and v > 0) and v or 1.0
end

local function laborRate(ws)
    local v = Business and Business.LaborRate and tonumber(Business.LaborRate(ws))
    return v or Config.Invoice.laborRate
end

local function notifyWs(ws, msg, kind, perm)
    if DPM.NotifyWorkshop then DPM.NotifyWorkshop(ws, msg, kind, perm) end
end

local function notifyIdentifier(identifier, msg, kind)
    if not identifier or not Bridge.GetSourceByIdentifier then return end
    local s = Bridge.GetSourceByIdentifier(identifier)
    if s then Bridge.Notify(s, msg, kind or 'info') end
end
Orders.NotifyIdentifier = notifyIdentifier

local function need(src, perm, duty)
    local m = DPM.GetMember(src)
    if not m then return nil, 'Nie jesteś pracownikiem warsztatu' end
    if perm then
        if DPM.Can(src, perm, duty) then return m end
        if not Utils.HasPerm(m.perms, perm) then return nil, 'Brak uprawnień' end
        return nil, 'Musisz być na służbie'
    end
    if duty and Config.RequireDuty and not m.duty then return nil, 'Musisz być na służbie' end
    return m
end

local function can(src, perm)
    return DPM.Can(src, perm, false) and true or false
end

local function waitReady()
    dbWait()
    local t = GetGameTimer() + 15000
    while not schema.checked and GetGameTimer() < t do Wait(50) end
end

local function reg(name, fn)
    DPM.RegisterCallback(name, function(src, ...)
        waitReady()
        return fn(src, ...)
    end)
end

local function statusErr(status)
    if status == 'invoiced' then return 'Zlecenie ma już wystawioną fakturę' end
    if status == 'paid' then return 'Zlecenie jest opłacone i zamknięte' end
    if status == 'cancelled' then return 'Zlecenie zostało anulowane' end
    return 'Nie można zmienić zlecenia w tym stanie'
end

-- blokada per klucz (kolejkowanie równoległych zmian); fn zwraca wynik callbacku
function Orders.WithLock(key, fn)
    local deadline = GetGameTimer() + 10000
    while locks[key] do
        if GetGameTimer() > deadline then return deny('Operacja w toku – spróbuj ponownie za chwilę') end
        Wait(20)
    end
    locks[key] = true
    local ok, res = pcall(fn)
    locks[key] = nil
    if not ok then
        print(('^1[dp-mechanic] błąd (%s): %s^7'):format(key, tostring(res)))
        return deny('Błąd serwera – spróbuj ponownie')
    end
    return res
end

-- bezpieczne dodanie kolumny (MariaDB: IF NOT EXISTS; MySQL: zwykłe ADD) → czy kolumna jest
local function hasColumn(tbl, col)
    local ok, n = pcall(MySQL.scalar.await, 'SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?', { tbl, col })
    if not ok or n == nil then return nil end
    return (tonumber(n) or 0) > 0
end

function Orders.EnsureColumn(tbl, col, def)
    if hasColumn(tbl, col) then return true end
    local ok = pcall(MySQL.query.await, ('ALTER TABLE %s ADD COLUMN IF NOT EXISTS %s %s'):format(tbl, col, def))
    local has = hasColumn(tbl, col)
    if has then return true end
    if has == false or not ok then
        pcall(MySQL.query.await, ('ALTER TABLE %s ADD COLUMN %s %s'):format(tbl, col, def))
        has = hasColumn(tbl, col)
    end
    if has == nil then return ok end
    return has
end

-- --------------------------------------------------------------------------
--  Pozycje zleceń
-- --------------------------------------------------------------------------
-- wartość od klienta: tylko proste typy, mała głębokość i liczba pól
local function cleanValue(v, depth, maxN)
    local t = type(v)
    if t == 'boolean' then return v end
    if t == 'number' then
        if v ~= v or v == math.huge or v == -math.huge then return nil end
        return Utils.Clamp(v, -1e7, 1e7)
    end
    if t == 'string' then return str(v, 64) end
    if t == 'table' and depth < 2 then
        local out, n = {}, 0
        for k, x in pairs(v) do
            n = n + 1
            if n > (maxN or 12) then break end
            local kt = type(k)
            if (kt == 'string' and #k <= 24) or (kt == 'number' and k >= 0 and k <= 64 and k == math.floor(k)) then
                local cv = cleanValue(x, depth + 1, maxN)
                if cv ~= nil then out[k] = cv end
            end
        end
        return out
    end
    return nil
end

-- lista wejściowa: tablica { k, key, v, name } albo koszyk tuningu { ['k:key'] = {...} }
local function collectInput(items)
    local list = {}
    if type(items) ~= 'table' then return list end
    local n, count = #items, 0
    for _ in pairs(items) do
        count = count + 1
        if count > 400 then break end
    end
    if n > 0 and count == n then
        for i = 1, math.min(n, MAX_ITEMS) do
            if type(items[i]) == 'table' then list[#list + 1] = items[i] end
        end
        return list
    end
    local keyed = {}
    for k, v in pairs(items) do
        if type(v) == 'table' then keyed[#keyed + 1] = { k = tostring(k), v = v } end
        if #keyed >= MAX_ITEMS then break end
    end
    table.sort(keyed, function(a, b)
        local ka, kb = KIND_ORDER[a.v.k] or 99, KIND_ORDER[b.v.k] or 99
        if ka ~= kb then return ka < kb end
        return a.k < b.k
    end)
    for _, e in ipairs(keyed) do list[#list + 1] = e.v end
    return list
end

-- pozycja z danych klienta → pełna pozycja (cena z configu × mnożnik warsztatu)
local function buildItem(ws, raw, allowCustom)
    local k = raw.k
    if type(k) ~= 'string' or not KIND_ORDER[k] then return nil end
    if k == 'custom' and not allowCustom then return nil end
    if k == 'nitro' and Config.Nitro.enabled == false then return nil end
    local key = raw.key
    if type(key) == 'number' then
        key = (key == key and key == math.floor(key)) and key or nil
    elseif type(key) == 'string' then
        key = str(key, 32)
    else
        key = nil
    end
    local v = cleanValue(raw.v, 0)
    local name
    if k == 'custom' then
        name = str(raw.name or raw.label, 60)
        if v == nil then v = tonumber(raw.amount or raw.price) end
    else
        name = str(raw.name, 40)
    end
    local ok, it = pcall(Catalog.Build, k, key, v, name)
    if not ok or type(it) ~= 'table' then return nil end
    it.label = str(it.label, 120) or 'Pozycja'
    it.name = name
    it.price = math.max(0, math.floor(tonumber(it.price) or 0))
    if not it.custom then it.price = math.floor(it.price * priceMult(ws) + 0.5) end
    it.labor = Utils.Round(math.max(0.0, tonumber(it.labor) or 0), 2)
    it.done = it.custom == true
    it.taken = false
    if it.tireJob then
        it.wheelsDone, it.takenWheels, it.fromStockW = {}, {}, {}
    end
    return it
end

local function hasKit(list)
    for _, it in ipairs(list or {}) do
        if it.k == 'nitro' and it.key == 'kit' then return true end
    end
    return false
end

-- buduje listę pozycji (nieprawidłowe pomijane); room = ile jeszcze się zmieści
local function buildList(ws, input, allowCustom, vdata, existing, room)
    local out = {}
    for _, raw in ipairs(collectInput(input)) do
        if #out >= (room or MAX_ITEMS) then break end
        local it = buildItem(ws, raw, allowCustom)
        if it then out[#out + 1] = it end
    end
    -- napełnienie N2O ma sens tylko z instalacją (w aucie albo w tym zleceniu)
    if not (vdata and type(vdata.nitro) == 'table') and not hasKit(out) and not hasKit(existing) then
        for i = #out, 1, -1 do
            if out[i].k == 'nitro' and out[i].key == 'refill' then table.remove(out, i) end
        end
    end
    return out
end

local function assignUids(o, list)
    local maxUid = 0
    for _, it in ipairs(o.items or {}) do
        if (tonumber(it.uid) or 0) > maxUid then maxUid = tonumber(it.uid) end
    end
    for _, it in ipairs(list) do
        maxUid = maxUid + 1
        it.uid = maxUid
    end
end

-- mapy kół { [w] = true } zapisujemy jako listy numerów (JSON bez dziurawych tablic)
local function toWheelMap(v)
    local m = {}
    if type(v) ~= 'table' then return m end
    for k, x in pairs(v) do
        local w
        if type(x) == 'number' then w = x elseif x == true then w = tonumber(k) end
        if w and w >= 1 and w <= 4 then m[math.floor(w)] = true end
    end
    return m
end

local function encodeItems(items)
    local out = {}
    for i, it in ipairs(items) do
        local c = {}
        for k, v in pairs(it) do c[k] = v end
        for _, f in ipairs(WHEEL_MAPS) do
            if type(it[f]) == 'table' then
                local arr = {}
                for w = 1, 4 do
                    if it[f][w] then arr[#arr + 1] = w end
                end
                c[f] = arr
            end
        end
        out[i] = c
    end
    return json.encode(out)
end

local function decodeItems(s)
    local list = decode(s, {})
    local out = {}
    if type(list) ~= 'table' then return out end
    for i = 1, #list do
        local it = list[i]
        if type(it) == 'table' and type(it.k) == 'string' then
            for _, f in ipairs(WHEEL_MAPS) do
                if it[f] ~= nil or it.tireJob then it[f] = toWheelMap(it[f]) end
            end
            out[#out + 1] = it
        end
    end
    return out
end
Orders.DecodeItems = decodeItems

local function allDone(o)
    local n = 0
    for _, it in ipairs(o.items) do
        if not it.custom then
            n = n + 1
            if not it.done then return false end
        end
    end
    return n > 0
end
Orders.AllDone = allDone

local function needsStock(item)
    return Config.Assembly.requireStock and item.stock ~= nil and Catalog.items[item.stock] ~= nil
end

local function recalc(o)
    local total, labor, done, n = 0, 0.0, 0, 0
    for _, it in ipairs(o.items) do
        total = total + (tonumber(it.price) or 0)
        labor = labor + (tonumber(it.labor) or 0)
        if not it.custom then
            n = n + 1
            if it.done then done = done + 1 end
        end
    end
    o.total = math.floor(total)
    o.labor = Utils.Round(labor, 2)
    o.laborCost = Catalog.LaborCost(o.labor, laborRate(o.workshop))
    o.progress = { done = done, total = n }
    o.workshopLabel = wsLabel(o.workshop)
end

-- --------------------------------------------------------------------------
--  Zlecenia – baza / pamięć
-- --------------------------------------------------------------------------
local function rowToOrder(r)
    local o = {
        id = r.id, workshop = r.workshop, plate = r.plate, model = r.model, vlabel = nz(r.vlabel) or 'Pojazd',
        customer = nz(r.customer), customerName = nz(r.customer_name),
        status = STATUSES[r.status] and r.status or 'open', source = r.source or 'mechanic',
        items = decodeItems(r.items), notes = r.notes or '',
        assigned = nz(r.assigned), assignedName = nz(r.assigned_name), createdBy = nz(r.created_by),
        createdAt = tonumber(r.created_at) or 0, updatedAt = tonumber(r.updated_at) or 0,
        projectId = tonumber(r.project_id), invoiceId = tonumber(r.invoice_id), km = tonumber(r.km) or 0,
    }
    recalc(o)
    return o
end

function Orders.Load(id)
    id = tonumber(id)
    if not id or id < 1 then return nil end
    id = math.floor(id)
    local o = cache[id]
    if o then
        touched[id] = now()
        return o
    end
    local row = MySQL.single.await('SELECT * FROM dpm_orders WHERE id = ?', { id })
    if cache[id] then          -- ktoś wczytał/zmienił w międzyczasie – jego wersja jest aktualna
        touched[id] = now()
        return cache[id]
    end
    if not row then return nil end
    o = rowToOrder(row)
    cache[id] = o
    touched[id] = now()
    return o
end

function Orders.Save(o)
    recalc(o)
    o.updatedAt = now()
    cache[o.id] = o
    touched[o.id] = o.updatedAt
    MySQL.update.await("UPDATE dpm_orders SET status = ?, items = ?, notes = ?, assigned = NULLIF(?, ''), assigned_name = ?, customer = NULLIF(?, ''), customer_name = ?, vlabel = ?, updated_at = ?, invoice_id = NULLIF(?, 0) WHERE id = ?", {
        o.status, encodeItems(o.items), o.notes or '', o.assigned or '', o.assignedName or '',
        o.customer or '', o.customerName or '', o.vlabel or '', o.updatedAt, o.invoiceId or 0, o.id,
    })
end

-- zmiana zlecenia pod blokadą: fn(kopia) -> wynik, zapisać?
-- (błąd lub brak zapisu = zlecenie w pamięci bez zmian)
function Orders.Mutate(id, fn)
    id = tonumber(id)
    if not id or id < 1 then return deny('Nieprawidłowe zlecenie') end
    id = math.floor(id)
    return Orders.WithLock('o:' .. id, function()
        local cur = Orders.Load(id)
        if not cur then return deny('Zlecenie nie istnieje') end
        local o = Utils.Copy(cur)
        local res, save = fn(o)
        if save then Orders.Save(o) end
        return res
    end)
end

-- nowe zlecenie: p = { workshop, plate, model, vlabel, customer, customerName, status, source, items, notes,
--                      assigned, assignedName, createdBy, projectId, km }
function Orders.Create(p)
    local t = now()
    local o = {
        workshop = p.workshop, plate = p.plate, model = p.model or '', vlabel = p.vlabel or 'Pojazd',
        customer = p.customer, customerName = p.customerName, status = p.status or 'open', source = p.source or 'mechanic',
        items = {}, notes = p.notes or '', assigned = p.assigned, assignedName = p.assignedName,
        createdBy = p.createdBy, createdAt = t, updatedAt = t, projectId = p.projectId, invoiceId = nil,
        km = math.floor(tonumber(p.km) or 0),
    }
    assignUids(o, p.items or {})
    o.items = p.items or {}
    recalc(o)
    local cols = 'workshop, plate, model, vlabel, customer, customer_name, status, source, items, notes, assigned, assigned_name, created_by, created_at, updated_at, project_id'
    local vals = "?, ?, ?, ?, NULLIF(?, ''), ?, ?, ?, ?, ?, NULLIF(?, ''), ?, ?, ?, ?, NULLIF(?, 0)"
    local params = {
        o.workshop, o.plate, tostring(o.model), o.vlabel, o.customer or '', o.customerName or '', o.status, o.source,
        encodeItems(o.items), o.notes, o.assigned or '', o.assignedName or '', o.createdBy or '', t, t, o.projectId or 0,
    }
    if schema.km then
        cols = cols .. ', km'
        vals = vals .. ', ?'
        params[#params + 1] = o.km
    end
    local id = MySQL.insert.await(('INSERT INTO dpm_orders (%s) VALUES (%s)'):format(cols, vals), params)
    if not id then return nil end
    o.id = id
    cache[id] = o
    touched[id] = t
    return o
end

-- --------------------------------------------------------------------------
--  Magazyn
-- --------------------------------------------------------------------------
local function takeStock(ws, key, qty)
    local n = MySQL.update.await('UPDATE dpm_stock SET qty = qty - ? WHERE workshop = ? AND item = ? AND qty >= ?', { qty, ws, key, qty })
    return (tonumber(n) or 0) > 0
end

local STOCK_ADD = 'INSERT INTO dpm_stock (workshop, item, qty) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE qty = qty + ?'
local function addStock(ws, key, qty, async)
    if async then
        MySQL.update(STOCK_ADD, { ws, key, qty, qty })
    else
        MySQL.update.await(STOCK_ADD, { ws, key, qty, qty })
    end
end
Orders.AddStock = addStock

function Orders.StockMap(ws)
    local rows = MySQL.query.await('SELECT item, qty FROM dpm_stock WHERE workshop = ?', { ws }) or {}
    local map = {}
    for _, r in ipairs(rows) do map[r.item] = tonumber(r.qty) or 0 end
    return map
end

-- zwrot pobranych, niezamontowanych części (anulowanie zlecenia)
local function returnAllStock(o)
    for _, it in ipairs(o.items) do
        if not it.custom and not it.done then
            local key = it.stock and Catalog.items[it.stock] and it.stock or nil
            if it.tireJob then
                it.wheelsDone = it.wheelsDone or {}
                for w = 1, 4 do
                    if key and it.fromStockW and it.fromStockW[w] and not it.wheelsDone[w] then addStock(o.workshop, key, 1) end
                end
                local keep = {}
                for w in pairs(it.wheelsDone) do keep[w] = true end
                it.takenWheels = Utils.Copy(keep)
                it.fromStockW = Utils.Copy(keep)
            else
                if key and it.taken and it.fromStock then addStock(o.workshop, key, 1) end
                it.taken, it.fromStock = false, nil
            end
        end
    end
end

local function inWorkshop(src, wsId)
    local ws = Config.Workshops[wsId]
    if not ws or not ws.zone then return true end
    local d = DPM.Dist(src, ws.zone.center)
    return d ~= nil and d <= (ws.zone.radius or 45.0) + 25.0
end

-- --------------------------------------------------------------------------
--  Efekty wykonanych pozycji na danych auta
-- --------------------------------------------------------------------------
local function itemEffect(item, d, t)
    local k = item.k
    if k == 'perf' then
        local lvl = math.floor(tonumber(item.v) or 0)
        if Config.PerfParts[item.key] then d.perf[item.key] = lvl > 0 and lvl or nil end
    elseif k == 'swap' then
        if Catalog.SwapTables[item.key] then d.swap[item.key] = item.v end
    elseif k == 'wear' then
        if Config.Wear.parts[item.key] then d.parts[item.key] = 100.0 end
        if item.key == 'oil' then d.svc.km = d.km end
    elseif k == 'nitro' then
        if item.key == 'kit' then
            local kit = Config.Nitro.kits[item.v]
            d.nitro = { kit = item.v, level = kit and kit.capacity or 0 }
        elseif item.key == 'refill' and type(d.nitro) == 'table' then
            local kit = Config.Nitro.kits[d.nitro.kit]
            if kit then d.nitro.level = kit.capacity end
        end
    elseif k == 'align' then
        d.align = 0.0
    elseif k == 'service' then
        -- przegląd: części zostają jak są (wymiana to osobne pozycje), nowy termin badania
        d.svc = { km = d.km, at = t, insp = t + (tonumber(Config.Wear.inspectionDays) or 30) * 86400 }
    else
        return false    -- wizualia (mod, paint, extra, wheels) nakłada klient
    end
end

-- --------------------------------------------------------------------------
--  Wspólne walidacje zleceń
-- --------------------------------------------------------------------------
-- auto przy graczu → ent, plate (albo nil, komunikat)
local function orderVehicle(src, netId, radius)
    local ent = entFromNet(netId)
    if not ent then return nil, 'Nie znaleziono pojazdu' end
    if not DPM.IsNear(src, ent, radius or VEH_RADIUS) then return nil, 'Podejdź bliżej do auta' end
    local plate = Vehicles.Bind(netId, ent)
    if not plate then return nil, 'Nie udało się odczytać tablicy rejestracyjnej' end
    return ent, plate
end

local function ownOrder(o, m)
    return o and m and o.workshop == m.workshop
end

-- pozycja do pracy → item (albo nil, komunikat)
local function workItem(o, m, idx, plate)
    if not ownOrder(o, m) then return nil, 'To zlecenie należy do innego warsztatu' end
    if plate and o.plate ~= plate then return nil, 'To nie jest auto z tego zlecenia' end
    if not WORKABLE[o.status] then return nil, statusErr(o.status) end
    local i = index(idx, #o.items)
    local item = i and o.items[i]
    if not item then return nil, 'Nie ma takiej pozycji w zleceniu' end
    if item.custom then return nil, 'To pozycja własna – nie wymaga montażu' end
    if item.done then return nil, 'Ta pozycja jest już wykonana' end
    return item
end

local function startWork(o, m)
    if o.status == 'open' then o.status = 'progress' end
    if not o.assigned then o.assigned, o.assignedName = m.identifier, m.name end
end

-- wszystkie pozycje zrobione → gotowe + powiadomienia
local function finishCheck(o)
    if (o.status == 'open' or o.status == 'progress') and allDone(o) then
        o.status = 'ready'
        notifyWs(o.workshop, ('Zlecenie #%d – %s (%s) gotowe. Można wystawić fakturę.'):format(o.id, o.vlabel, o.plate), 'success', 'invoice')
        notifyIdentifier(o.customer, ('Twoje auto %s (%s) jest gotowe – zapraszamy do warsztatu %s.'):format(o.vlabel, o.plate, wsLabel(o.workshop)), 'success')
    end
end

local function projectStatus(id, status, from)
    if not id then return end
    if from then
        MySQL.update('UPDATE dpm_projects SET status = ? WHERE id = ? AND status = ?', { status, id, from })
    else
        MySQL.update('UPDATE dpm_projects SET status = ? WHERE id = ?', { status, id })
    end
end
Orders.ProjectStatus = projectStatus

-- klient zlecenia: wskazany gracz obok albo właściciel auta z frameworka
local function resolveCustomer(src, target, plate)
    target = tonumber(target)
    if target and GetPlayerName(target) and (target ~= src or Config.Invoice.allowSelf) and pdist(src, target) <= 20.0 then
        return Bridge.GetIdentifier(target), Bridge.GetName(target), target
    end
    local ok, owner = pcall(Bridge.GetVehicleOwner, plate)
    if ok and owner and owner ~= '' then
        local osrc = Bridge.GetSourceByIdentifier and Bridge.GetSourceByIdentifier(owner)
        return owner, osrc and Bridge.GetName(osrc) or nil, osrc
    end
    return nil, nil, nil
end

-- --------------------------------------------------------------------------
--  Callbacki: zlecenia
-- --------------------------------------------------------------------------
reg('orders:list', function(src, filter)
    local m, err = need(src, 'orders')
    if not m then return deny(err) end
    filter = type(filter) == 'table' and filter or {}
    local where, params = { 'workshop = ?' }, { m.workshop }
    local st = filter.status
    if st == nil or st == 'active' then
        where[#where + 1] = "status IN ('open','progress','ready','invoiced')"
    elseif st ~= 'all' then
        if not STATUSES[st] then return deny('Nieprawidłowy filtr statusu') end
        where[#where + 1] = 'status = ?'
        params[#params + 1] = st
    end
    local q = str(filter.plate, 16)
    if q then
        where[#where + 1] = 'plate LIKE ?'
        params[#params + 1] = '%' .. (q:upper():gsub('[%%_\\]', '\\%0')) .. '%'
    end
    local rows = MySQL.query.await('SELECT * FROM dpm_orders WHERE ' .. table.concat(where, ' AND ') .. ' ORDER BY id DESC LIMIT 100', params) or {}
    local list = {}
    for i, r in ipairs(rows) do list[i] = cache[r.id] or rowToOrder(r) end
    return { ok = true, list = list }
end)

reg('orders:get', function(src, id)
    local m, err = need(src, 'orders')
    if not m then return deny(err) end
    local o = Orders.Load(id)
    if not ownOrder(o, m) then return deny('Zlecenie nie istnieje') end
    return { ok = true, order = o }
end)

reg('orders:create', function(src, netId, items, opts)
    local m, err = need(src, 'orders', true)
    if not m then return deny(err) end
    if not throttle(src, 'create', 1500) then return deny('Chwileczkę…') end
    opts = type(opts) == 'table' and opts or {}
    local ent, plate = orderVehicle(src, netId)
    if not ent then return deny(plate) end
    local data = Vehicles.Get(plate)
    local list = buildList(m.workshop, items, true, data, nil, MAX_ITEMS)
    if #list == 0 then return deny('Brak prawidłowych pozycji zlecenia') end

    if opts.vlabel then Vehicles.SetLabel(plate, opts.vlabel) end
    local customer, customerName, customerSrc = resolveCustomer(src, opts.customerSrc, plate)
    local o = Orders.Create({
        workshop = m.workshop, plate = plate, model = Vehicles.Model(plate) or tostring(GetEntityModel(ent)),
        vlabel = str(opts.vlabel, 64) or Vehicles.Label(plate) or 'Pojazd',
        customer = customer, customerName = customerName, status = 'open',
        source = opts.source == 'service' and 'service' or 'mechanic',
        items = list, notes = text(opts.notes, 500), createdBy = m.name, km = data and data.km or 0,
    })
    if not o then return deny('Nie udało się zapisać zlecenia') end
    if customerSrc and customerSrc ~= src then
        Bridge.Notify(customerSrc, ('Warsztat %s przyjął Twoje auto %s (%s) – zlecenie #%d.'):format(wsLabel(m.workshop), o.vlabel, plate, o.id), 'info')
    end
    return { ok = true, id = o.id, order = o }
end)

reg('orders:addItems', function(src, id, items)
    local m, err = need(src, 'orders')
    if not m then return deny(err) end
    return Orders.Mutate(id, function(o)
        if not ownOrder(o, m) then return deny('Zlecenie nie istnieje') end
        if not EDITABLE[o.status] then return deny(statusErr(o.status)) end
        local room = MAX_ITEMS - #o.items
        if room <= 0 then return deny('Zlecenie ma już maksymalną liczbę pozycji') end
        local list = buildList(o.workshop, items, true, Vehicles.Get(o.plate), o.items, room)
        if #list == 0 then return deny('Brak prawidłowych pozycji do dodania') end
        assignUids(o, list)
        local work = false
        for _, it in ipairs(list) do
            o.items[#o.items + 1] = it
            if not it.custom then work = true end
        end
        if work and o.status == 'ready' then o.status = 'progress' end
        return { ok = true, order = o }, true
    end)
end)

reg('orders:removeItem', function(src, id, idx)
    local m, err = need(src, 'orders')
    if not m then return deny(err) end
    return Orders.Mutate(id, function(o)
        if not ownOrder(o, m) then return deny('Zlecenie nie istnieje') end
        if not EDITABLE[o.status] then return deny(statusErr(o.status)) end
        local i = index(idx, #o.items)
        local item = i and o.items[i]
        if not item then return deny('Nie ma takiej pozycji w zleceniu') end
        if not item.custom then
            if item.done then return deny('Nie można usunąć wykonanej pozycji') end
            if item.taken or next(item.takenWheels or {}) or next(item.wheelsDone or {}) then
                return deny('Część jest już pobrana z magazynu – najpierw ją zwróć')
            end
        end
        -- przesunięcie indeksów: nie usuwamy, gdy ktoś pracuje nad dalszą pozycją
        for j = i + 1, #o.items do
            local it = o.items[j]
            if not it.done and (it.taken or next(it.takenWheels or {}) or next(it.wheelsDone or {})) then
                return deny('Mechanik pracuje właśnie nad kolejną pozycją – spróbuj później')
            end
        end
        table.remove(o.items, i)
        finishCheck(o)
        return { ok = true, order = o }, true
    end)
end)

reg('orders:setStatus', function(src, id, status)
    local m, err = need(src, 'orders')
    if not m then return deny(err) end
    if status ~= 'open' and status ~= 'progress' and status ~= 'ready' and status ~= 'cancelled' then
        return deny('Nieprawidłowy status')
    end
    local manager = can(src, 'orders_all')
    if status == 'cancelled' and not manager then return deny('Anulowanie zlecenia wymaga uprawnień kierownika') end
    return Orders.Mutate(id, function(o)
        if not ownOrder(o, m) then return deny('Zlecenie nie istnieje') end
        if o.status == status then return { ok = true } end
        if o.status == 'paid' then return deny('Zlecenie jest opłacone i zamknięte') end
        if o.status == 'invoiced' then return deny('Zlecenie ma wystawioną fakturę – najpierw ją anuluj') end
        if o.status == 'cancelled' and not manager then return deny('Przywrócenie anulowanego zlecenia wymaga uprawnień kierownika') end
        if status == 'cancelled' then
            returnAllStock(o)
            if o.projectId then projectStatus(o.projectId, 'active', 'loaded') end
        elseif o.status == 'cancelled' and o.projectId then
            projectStatus(o.projectId, 'loaded', 'active')
        end
        o.status = status
        return { ok = true }, true
    end)
end)

reg('orders:assign', function(src, id, target)
    local m, err = need(src, 'orders')
    if not m then return deny(err) end
    local manager = can(src, 'orders_all')
    return Orders.Mutate(id, function(o)
        if not ownOrder(o, m) then return deny('Zlecenie nie istnieje') end
        if o.status == 'paid' or o.status == 'cancelled' then return deny(statusErr(o.status)) end
        if target == 'me' or target == m.identifier then
            if o.assigned and o.assigned ~= m.identifier and not manager then
                return deny('Zlecenie jest przypisane do innego mechanika')
            end
            o.assigned, o.assignedName = m.identifier, m.name
        elseif target == nil or target == false or target == '' then
            if o.assigned ~= m.identifier and not manager then return deny('Brak uprawnień') end
            o.assigned, o.assignedName = nil, nil
        else
            if not manager then return deny('Przypisywanie innym wymaga uprawnień kierownika') end
            if type(target) ~= 'string' or #target > 64 then return deny('Nieprawidłowy pracownik') end
            local ws = Business.Get(m.workshop)
            local emp = ws and ws.employees and ws.employees[target]
            if not emp then return deny('Nie ma takiego pracownika w warsztacie') end
            o.assigned, o.assignedName = target, emp.name
            notifyIdentifier(target, ('Przypisano Ci zlecenie #%d – %s (%s)'):format(o.id, o.vlabel, o.plate), 'info')
        end
        return { ok = true }, true
    end)
end)

reg('orders:notes', function(src, id, value)
    local m, err = need(src, 'orders')
    if not m then return deny(err) end
    if value ~= nil and type(value) ~= 'string' then return deny('Nieprawidłowa notatka') end
    local clean = text(value, 500)
    return Orders.Mutate(id, function(o)
        if not ownOrder(o, m) then return deny('Zlecenie nie istnieje') end
        o.notes = clean
        return { ok = true }, true
    end)
end)

reg('orders:start', function(src, id, netId)
    local m, err = need(src, 'orders', true)
    if not m then return deny(err) end
    local ent, plate = orderVehicle(src, netId)
    if not ent then return deny(plate) end
    return Orders.Mutate(id, function(o)
        if not ownOrder(o, m) then return deny('Zlecenie nie istnieje') end
        if o.plate ~= plate then return deny('To nie jest auto z tego zlecenia') end
        if not WORKABLE[o.status] then return deny(statusErr(o.status)) end
        startWork(o, m)
        return { ok = true, order = o }, true
    end)
end)

reg('orders:itemDone', function(src, orderId, idx, netId)
    local m, err = need(src, 'orders', true)
    if not m then return deny(err) end
    local ent, plate = orderVehicle(src, netId)
    if not ent then return deny(plate) end
    return Orders.Mutate(orderId, function(o)
        local item, e2 = workItem(o, m, idx, plate)
        if not item then return deny(e2) end
        if item.tireJob then return deny('Opony i felgi wymienia się koło po kole (montażownica i wyważarka)') end
        if needsStock(item) and not item.taken then return deny('Najpierw pobierz część z magazynu') end
        if item.k == 'nitro' and item.key == 'refill' then
            local vd = Vehicles.Get(plate)
            if not (vd and type(vd.nitro) == 'table') then return deny('Najpierw zamontuj instalację N2O') end
        end
        local t = now()
        Vehicles.Update(plate, function(d) return itemEffect(item, d, t) end)
        item.done, item.by, item.doneAt, item.taken = true, m.name, t, true
        startWork(o, m)
        local vd = Vehicles.Get(plate)
        Vehicles.AddHistory(plate, o.workshop, item.k == 'service' and 'inspection' or item.k, item.label, vd and vd.km, m.name)
        finishCheck(o)
        return { ok = true, order = o }, true
    end)
end)

reg('orders:wheelDone', function(src, orderId, idx, wheel, netId, res)
    local m, err = need(src, 'orders', true)
    if not m then return deny(err) end
    res = type(res) == 'table' and res or {}
    local imbalance = math.floor(num(res.imbalance, 0, 200, 0) + 0.5)
    local count = int(res.wheels, 1, 4, 4)
    local ent, plate = orderVehicle(src, netId)
    if not ent then return deny(plate) end
    return Orders.Mutate(orderId, function(o)
        local item, e2 = workItem(o, m, idx, plate)
        if not item then return deny(e2) end
        if not item.tireJob then return deny('Ta pozycja nie dotyczy kół') end
        item.wheelsDone = item.wheelsDone or {}
        item.takenWheels = item.takenWheels or {}
        item.wheelCount = int(item.wheelCount, 1, 4, nil) or count
        local w = index(wheel, item.wheelCount)
        if not w then return deny('Nieprawidłowe koło') end
        if item.wheelsDone[w] then return { ok = true, order = o, itemDone = item.done == true } end
        if needsStock(item) and not item.takenWheels[w] then
            return deny(item.k == 'tire' and 'Najpierw pobierz nową oponę z magazynu' or 'Najpierw pobierz felgę z magazynu')
        end
        Vehicles.Update(plate, function(d)
            if item.k == 'tire' then
                d.tires[w] = { t = Config.TireNewTread, b = imbalance }
            else
                d.tires[w].b = imbalance      -- nowa felga: bieżnik bez zmian, nowe wyważenie
            end
        end)
        item.wheelsDone[w] = true
        item.takenWheels[w] = true
        startWork(o, m)
        local all = true
        for i = 1, item.wheelCount do
            if not item.wheelsDone[i] then all = false break end
        end
        if all then
            item.done, item.by, item.doneAt, item.taken = true, m.name, now(), true
            if item.k == 'tire' then Vehicles.Update(plate, function(d) d.compound = item.key end) end
            local vd = Vehicles.Get(plate)
            Vehicles.AddHistory(plate, o.workshop, item.k, item.label, vd and vd.km, m.name)
            finishCheck(o)
        end
        return { ok = true, order = o, itemDone = all }, true
    end)
end)

-- właściwości wyglądu od klienta: tylko znane klucze (bez modelu i tablicy)
local function cleanProps(p)
    if type(p) ~= 'table' then return nil end
    local out, n = {}, 0
    for k, v in pairs(p) do
        if type(k) == 'string' and (PROP_KEYS[k] or k:match('^mod%d+$') or k:match('^mod%u%a+$')) then
            local cv = cleanValue(v, 0, 24)
            if cv ~= nil then
                out[k] = cv
                n = n + 1
                if n >= 160 then break end
            end
        end
    end
    return n > 0 and out or nil
end

reg('orders:finish', function(src, orderId, netId, props)
    local m, err = need(src, 'orders')
    if not m then return deny(err) end
    if not throttle(src, 'finish', 3000) then return deny('Chwileczkę…') end
    local ent, plate = orderVehicle(src, netId)
    if not ent then return deny(plate) end
    local o = Orders.Load(orderId)
    if not ownOrder(o, m) then return deny('Zlecenie nie istnieje') end
    if o.plate ~= plate then return deny('To nie jest auto z tego zlecenia') end
    if o.status == 'cancelled' then return deny(statusErr(o.status)) end
    if not allDone(o) and o.status ~= 'ready' and o.status ~= 'invoiced' and o.status ~= 'paid' then
        return deny('Nie wszystkie pozycje są wykonane')
    end
    local clean = cleanProps(props)
    if clean then
        local ok, e = pcall(Bridge.SaveVehicleProps, plate, clean)
        if not ok then print(('^1[dp-mechanic] SaveVehicleProps %s: %s^7'):format(plate, tostring(e))) end
    end
    Vehicles.AddHistory(plate, o.workshop, 'order',
        ('Zakończono zlecenie #%d (%d poz., %s)'):format(o.id, o.progress.total, Utils.Money(o.total)), nil, m.name)
    return { ok = true }
end)

-- --------------------------------------------------------------------------
--  Callbacki: magazyn przy zleceniu
-- --------------------------------------------------------------------------
reg('stock:take', function(src, orderId, idx, wheel)
    local m, err = need(src, 'stock', true)
    if not m then return deny(err) end
    if not inWorkshop(src, m.workshop) then return deny('Części możesz pobrać tylko w warsztacie') end
    return Orders.Mutate(orderId, function(o)
        local item, e2 = workItem(o, m, idx)
        if not item then return deny(e2) end
        local key = needsStock(item) and item.stock or nil
        local label = key and Catalog.items[key].label or item.label
        if item.tireJob then
            item.wheelsDone = item.wheelsDone or {}
            item.takenWheels = item.takenWheels or {}
            item.fromStockW = item.fromStockW or {}
            local w = index(wheel, 4)
            if not w then return deny('Wybierz koło') end
            if item.wheelsDone[w] then return deny('To koło jest już wymienione') end
            if item.takenWheels[w] then return { ok = true, item = item } end
            if key then
                if not takeStock(o.workshop, key, 1) then return deny(('Brak na stanie: %s'):format(label)) end
                item.fromStockW[w] = true
            end
            item.takenWheels[w] = true
        else
            if item.taken then return { ok = true, item = item } end
            if key then
                if not takeStock(o.workshop, key, 1) then return deny(('Brak na stanie: %s'):format(label)) end
                item.fromStock = true
            end
            item.taken = true
        end
        item.takenBy = m.name
        startWork(o, m)
        return { ok = true, item = item }, true
    end)
end)

reg('stock:return', function(src, orderId, idx, wheel)
    local m, err = need(src, 'stock')
    if not m then return deny(err) end
    return Orders.Mutate(orderId, function(o)
        if not ownOrder(o, m) then return deny('Zlecenie nie istnieje') end
        local i = index(idx, #o.items)
        local item = i and o.items[i]
        if not item then return deny('Nie ma takiej pozycji w zleceniu') end
        if item.custom then return { ok = true } end
        if item.done then return deny('Część jest już zamontowana') end
        local key = item.stock and Catalog.items[item.stock] and item.stock or nil
        if item.tireJob then
            local w = index(wheel, 4)
            if not w then return deny('Wybierz koło') end
            item.takenWheels = item.takenWheels or {}
            item.fromStockW = item.fromStockW or {}
            if not item.takenWheels[w] then return { ok = true } end
            if item.wheelsDone and item.wheelsDone[w] then return deny('To koło jest już zamontowane') end
            if key and item.fromStockW[w] then addStock(o.workshop, key, 1) end
            item.fromStockW[w] = nil
            item.takenWheels[w] = nil
        else
            if not item.taken then return { ok = true } end
            if key and item.fromStock then addStock(o.workshop, key, 1) end
            item.taken, item.fromStock = false, nil
        end
        return { ok = true }, true
    end)
end)

-- --------------------------------------------------------------------------
--  Callbacki: projekty klientów
-- --------------------------------------------------------------------------
local function stationWorkshop(src)
    local best, bestD
    for id, ws in pairs(Config.Workshops) do
        local st = ws.projectStation
        if st and st.coords then
            local d = DPM.Dist(src, vec3(st.coords.x, st.coords.y, st.coords.z))
            if d and d <= (st.radius or 3.5) + 6.0 and (not bestD or d < bestD) then best, bestD = id, d end
        end
    end
    return best
end

local function projectView(r, withOwner)
    local p = {
        id = r.id, workshop = r.workshop, workshopLabel = wsLabel(r.workshop), plate = r.plate, model = r.model,
        vlabel = nz(r.vlabel) or 'Pojazd', label = r.label, items = decodeItems(r.items), total = tonumber(r.total) or 0,
        status = r.status, createdAt = tonumber(r.created_at) or 0,
    }
    local labor = 0.0
    for _, it in ipairs(p.items) do labor = labor + (tonumber(it.labor) or 0) end
    p.labor = Utils.Round(labor, 2)
    p.count = #p.items
    if withOwner then
        p.owner = r.owner
        p.ownerName = r.owner_name
    end
    return p
end

reg('projects:save', function(src, netId, items, label, extra)
    if not throttle(src, 'project', 4000) then return deny('Chwileczkę…') end
    if not Config.ProjectForEveryone and DPM.GetMember(src) then
        return deny('Stanowisko projektowe jest przeznaczone dla klientów')
    end
    local wsId = stationWorkshop(src)
    if not wsId then return deny('Musisz być przy stanowisku projektowym') end
    local ent, plate = orderVehicle(src, netId, 10.0)
    if not ent then return deny(plate) end
    local identifier = Bridge.GetIdentifier(src)
    if not identifier then return deny('Nie udało się rozpoznać gracza') end

    local maxActive = (Config.Projects and tonumber(Config.Projects.maxActive)) or 5
    local active = tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM dpm_projects WHERE owner = ? AND status = 'active'", { identifier })) or 0
    if active >= maxActive then
        return deny(('Masz już %d aktywnych projektów – usuń któryś, aby zapisać nowy'):format(maxActive))
    end

    local data = Vehicles.Get(plate)
    local list = buildList(wsId, items, false, data, nil, MAX_ITEMS)
    if #list == 0 then return deny('Projekt nie zawiera żadnych zmian') end
    assignUids({ items = {} }, list)

    local vl = type(extra) == 'table' and extra.vlabel or extra
    if vl then Vehicles.SetLabel(plate, vl) end
    local vlabel = str(vl, 64) or Vehicles.Label(plate) or 'Pojazd'
    local total, labor = 0, 0.0
    for _, it in ipairs(list) do
        total = total + it.price
        labor = labor + (it.labor or 0)
    end
    label = str(label, 64) or ('Projekt – ' .. vlabel)

    local id = MySQL.insert.await("INSERT INTO dpm_projects (workshop, owner, owner_name, plate, model, vlabel, label, items, total, status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'active', ?)", {
        wsId, identifier, Bridge.GetName(src) or '', plate, Vehicles.Model(plate) or tostring(GetEntityModel(ent)),
        vlabel, label, encodeItems(list), total, now(),
    })
    if not id then return deny('Nie udało się zapisać projektu') end
    notifyWs(wsId, ('Nowy projekt klienta: %s – %s (%s), %s'):format(Bridge.GetName(src) or '?', vlabel, plate, Utils.Money(total)), 'info', 'projects')
    labor = Utils.Round(labor, 2)
    return { ok = true, id = id, total = total, labor = labor, laborCost = Catalog.LaborCost(labor, laborRate(wsId)), workshop = wsId }
end)

reg('projects:mine', function(src)
    local identifier = Bridge.GetIdentifier(src)
    if not identifier then return deny('Nie udało się rozpoznać gracza') end
    local rows = MySQL.query.await('SELECT * FROM dpm_projects WHERE owner = ? ORDER BY id DESC LIMIT 30', { identifier }) or {}
    local list = {}
    for i, r in ipairs(rows) do list[i] = projectView(r, false) end
    return { ok = true, list = list }
end)

reg('projects:list', function(src)
    local m, err = need(src, 'projects')
    if not m then return deny(err) end
    local rows = MySQL.query.await("SELECT * FROM dpm_projects WHERE workshop = ? AND status IN ('active','loaded') ORDER BY id DESC LIMIT 100", { m.workshop }) or {}
    local list = {}
    for i, r in ipairs(rows) do list[i] = projectView(r, true) end
    return { ok = true, list = list }
end)

reg('projects:load', function(src, id, netId)
    local m, err = need(src, 'projects', true)
    if not m then return deny(err) end
    id = posId(id)
    if not id then return deny('Nieprawidłowy projekt') end
    local ent, plate = orderVehicle(src, netId, 30.0)
    if not ent then return deny(plate) end
    return Orders.WithLock('p:' .. id, function()
        local row = MySQL.single.await('SELECT * FROM dpm_projects WHERE id = ?', { id })
        if not row or row.workshop ~= m.workshop then return deny('Projekt nie istnieje') end
        if row.status ~= 'active' then return deny('Ten projekt został już wczytany do zlecenia') end
        if row.plate ~= plate then return deny('To nie jest auto z tego projektu') end
        local data = Vehicles.Get(plate)
        local list = {}
        for _, it in ipairs(decodeItems(row.items)) do
            local b = buildItem(m.workshop, { k = it.k, key = it.key, v = it.v, name = it.name }, false)
            if b then
                -- cena z projektu (wycena pokazana klientowi) i jego etykieta
                local price = tonumber(it.price)
                if price and price >= 0 and price <= 100000000 then b.price = math.floor(price) end
                b.label = str(it.label, 120) or b.label
                list[#list + 1] = b
            end
        end
        if not (data and type(data.nitro) == 'table') and not hasKit(list) then
            for i = #list, 1, -1 do
                if list[i].k == 'nitro' and list[i].key == 'refill' then table.remove(list, i) end
            end
        end
        if #list == 0 then return deny('Pozycje projektu są już nieaktualne') end
        local o = Orders.Create({
            workshop = m.workshop, plate = plate, model = row.model, vlabel = nz(row.vlabel) or Vehicles.Label(plate) or 'Pojazd',
            customer = row.owner, customerName = nz(row.owner_name), status = 'open', source = 'project',
            items = list, notes = ('Projekt klienta: %s'):format(row.label or ''), createdBy = m.name,
            projectId = id, km = data and data.km or 0,
        })
        if not o then return deny('Nie udało się utworzyć zlecenia') end
        MySQL.update.await("UPDATE dpm_projects SET status = 'loaded' WHERE id = ?", { id })
        notifyIdentifier(row.owner, ('Warsztat %s rozpoczął realizację Twojego projektu „%s”.'):format(wsLabel(m.workshop), row.label or ''), 'info')
        return { ok = true, orderId = o.id, order = o }
    end)
end)

reg('projects:delete', function(src, id)
    id = posId(id)
    if not id then return deny('Nieprawidłowy projekt') end
    local row = MySQL.single.await('SELECT id, workshop, owner FROM dpm_projects WHERE id = ?', { id })
    if not row then return deny('Projekt nie istnieje') end
    local identifier = Bridge.GetIdentifier(src)
    local owner = identifier ~= nil and row.owner == identifier
    if not owner then
        local m = DPM.Can(src, 'projects', false)
        if not m or m.workshop ~= row.workshop then return deny('Brak uprawnień') end
    end
    MySQL.update.await('DELETE FROM dpm_projects WHERE id = ?', { id })
    return { ok = true }
end)

-- --------------------------------------------------------------------------
--  Callbacki: magazyn i hurtownia
-- --------------------------------------------------------------------------
local function pendingView(ws)
    local out = {}
    for _, e in ipairs(pending[ws] or {}) do
        if not e.done then out[#out + 1] = { id = e.id, key = e.key, label = e.label, qty = e.qty, eta = e.eta } end
    end
    return out
end

local function deliver(entry, stopping)
    if entry.done then return end
    entry.done = true
    local list = pending[entry.ws]
    if list then
        for i = #list, 1, -1 do
            if list[i] == entry then table.remove(list, i) end
        end
    end
    if stopping then
        addStock(entry.ws, entry.key, entry.qty, true)
        return
    end
    CreateThread(function()
        local ok, e = pcall(addStock, entry.ws, entry.key, entry.qty, false)
        if not ok then
            print(('^1[dp-mechanic] dostawa %s × %d: %s^7'):format(entry.key, entry.qty, tostring(e)))
            return
        end
        notifyWs(entry.ws, ('Dostawa z hurtowni: %s × %d – już w szafkach'):format(entry.label, entry.qty), 'success', 'stock')
    end)
end

reg('stock:list', function(src)
    local m, err = need(src, 'stock')
    if not m then return deny(err) end
    local qty = Orders.StockMap(m.workshop)
    local mult = priceMult(m.workshop)
    local wh = tonumber(Config.Supplier.wholesale) or 0.55
    local list = {}
    for key, it in pairs(Catalog.items) do
        list[#list + 1] = {
            key = key, label = it.label, cabinet = it.cabinet, category = CATEGORY_LABELS[it.cabinet] or it.cabinet,
            price = math.floor(it.price * mult + 0.5), wholesale = math.floor(it.price * wh + 0.5), qty = qty[key] or 0,
        }
    end
    table.sort(list, function(a, b)
        if a.cabinet ~= b.cabinet then return a.cabinet < b.cabinet end
        return a.label < b.label
    end)
    return { ok = true, list = list, pending = pendingView(m.workshop), deliveryTime = tonumber(Config.Supplier.deliveryTime) or 60 }
end)

reg('stock:buy', function(src, key, qty)
    local m, err = need(src, 'stock_buy')
    if not m then return deny(err) end
    if not throttle(src, 'buy', 700) then return deny('Chwileczkę…') end
    local item = type(key) == 'string' and Catalog.items[key] or nil
    if not item then return deny('Nieznana pozycja magazynowa') end
    qty = tonumber(qty)
    if not qty or qty ~= math.floor(qty) or qty < 1 or qty > 50 then return deny('Ilość musi być od 1 do 50') end
    local list = pending[m.workshop] or {}
    pending[m.workshop] = list
    if #list >= 30 then return deny('Zbyt wiele oczekujących dostaw – poczekaj na realizację') end

    local cost = math.floor(item.price * (tonumber(Config.Supplier.wholesale) or 0.55) * qty + 0.5)
    local ok, balance = Business.AddBalance(m.workshop, -cost, 'supplier', ('Hurtownia: %s × %d'):format(item.label, qty), m.name)
    if not ok then return deny('Za mało środków na koncie warsztatu') end

    local delay = math.max(0, math.floor(tonumber(Config.Supplier.deliveryTime) or 60))
    deliverySeq = deliverySeq + 1
    local entry = { id = deliverySeq, ws = m.workshop, key = key, label = item.label, qty = qty, eta = now() + delay }
    list[#list + 1] = entry
    SetTimeout(delay * 1000, function() deliver(entry, false) end)
    return { ok = true, balance = balance, cost = cost, eta = entry.eta, pending = pendingView(m.workshop) }
end)

reg('cabinet:list', function(src, wsId, cabIdx)
    local m, err = need(src, 'stock')
    if not m then return deny(err) end
    wsId = wsId or m.workshop
    if wsId ~= m.workshop then return deny('To nie jest Twój warsztat') end
    local ws = Config.Workshops[wsId]
    local i = index(cabIdx, ws and ws.cabinets and #ws.cabinets or 0)
    local cab = i and ws.cabinets[i]
    if not cab then return deny('Nie ma takiej szafki') end
    local d = DPM.Dist(src, vec3(cab.coords.x, cab.coords.y, cab.coords.z))
    if not d or d > 5.0 then return deny('Podejdź bliżej do szafki') end
    local cats, all = {}, false
    for _, c in ipairs(cab.categories or {}) do
        if c == 'all' then all = true end
        cats[c] = true
    end
    local qty = Orders.StockMap(wsId)
    local mult = priceMult(wsId)
    local list = {}
    for key, it in pairs(Catalog.items) do
        if all or cats[it.cabinet] then
            list[#list + 1] = { key = key, label = it.label, qty = qty[key] or 0, price = math.floor(it.price * mult + 0.5), cabinet = it.cabinet, prop = it.prop }
        end
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return { ok = true, label = cab.label, list = list }
end)

-- --------------------------------------------------------------------------
--  Start / sprzątanie
-- --------------------------------------------------------------------------
CreateThread(function()
    dbWait()
    local ok, res = pcall(Orders.EnsureColumn, 'dpm_orders', 'km', 'INT DEFAULT 0')
    schema.km = ok and res == true
    schema.checked = true
    if not schema.km then print('^3[dp-mechanic] dpm_orders: brak kolumny km – przebieg przy przyjęciu nie będzie zapisywany^7') end
end)

-- pamięć zleceń: usuwanie nieużywanych (dane są w bazie)
CreateThread(function()
    while true do
        Wait(300000)
        local t = now()
        for id, at in pairs(touched) do
            if t - at > 900 and not locks['o:' .. id] then
                cache[id] = nil
                touched[id] = nil
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    calls[source] = nil
end)

-- zatrzymanie zasobu: dostawy w drodze trafiają od razu do magazynu
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, list in pairs(pending) do
        for i = #list, 1, -1 do deliver(list[i], true) end
    end
end)
