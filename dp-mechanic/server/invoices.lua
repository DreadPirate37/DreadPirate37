-- ==========================================================================
--  dp-mechanic – serwer: faktury i terminal płatniczy
--  Faktura liczona wyłącznie na serwerze: części + robocizna + pozycje własne,
--  rabat, VAT. Numeracja FV/RRRR/MM/NNNN osobno dla warsztatu i miesiąca.
--  Płatność przez sesję terminala: mechanik wskazuje klienta, klient wybiera
--  metodę i płaci – środki pobiera i rozlicza serwer (konto warsztatu, prowizja).
-- ==========================================================================
Invoices = { sessions = {} }

local sessions = Invoices.sessions   -- [id] = sesja terminala
local byPlayer = {}                  -- [src] = id sesji (klient albo wystawiający)
local sessionSeq = 0
local calls = {}                     -- limity: [src] = { [nazwa] = GetGameTimer() }
local schema = { checked = false, km = false }
Invoices.schema = schema

local STATUSES = { unpaid = true, paid = true, cancelled = true }
local METHOD_LABELS = { card = 'karta', cash = 'gotówka' }
local ERR_CASH = 'Nie masz wystarczającej ilości gotówki'
local ERR_BANK = 'Brak wystarczających środków na koncie'

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

local function posId(v)
    v = tonumber(v)
    if not v or v ~= math.floor(v) or v < 1 or v > 2147483647 then return nil end
    return math.floor(v)
end

local function utf8Fix(s)
    if utf8.len(s) then return s end
    for _ = 1, 3 do
        s = s:sub(1, -2)
        if utf8.len(s) then return s end
    end
    return (s:gsub('[\128-\255]', ''))
end

local function str(s, max)
    local t = type(s)
    if t == 'number' then s = tostring(s) elseif t ~= 'string' then return nil end
    s = s:gsub('[%c<>]', ' '):gsub('%s+', ' ')
    s = utf8Fix(Utils.Trim(s))
    if s == '' then return nil end
    max = max or 64
    if utf8.len(s) > max then s = Utils.Trim(s:sub(1, utf8.offset(s, max + 1) - 1)) end
    return s ~= '' and s or nil
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

local function safe(fn, what)
    local ok, err = pcall(fn)
    if not ok then print(('^1[dp-mechanic] %s: %s^7'):format(what or 'faktury', tostring(err))) end
    return ok
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

local function online(src)
    return src ~= nil and GetPlayerName(src) ~= nil
end

-- gracz ma „portfel” we frameworku (bridge bez obiektu gracza zachowuje się jak standalone)
local function hasWallet(src)
    if not online(src) then return false end
    if Bridge.name ~= 'standalone' and Bridge.GetPlayer and not Bridge.GetPlayer(src) then return false end
    return true
end

local function wsLabel(id)
    local ws = Config.Workshops[id or '']
    return ws and ws.label or ''
end

local function laborRate(ws)
    local v = Business and Business.LaborRate and tonumber(Business.LaborRate(ws))
    return v or Config.Invoice.laborRate
end

local function vatRate(ws)
    local v = Business and Business.Vat and tonumber(Business.Vat(ws))
    if not v then v = tonumber(Config.Invoice.vat) or 0 end
    return Utils.Clamp(v, 0, 0.5)
end

local function need(src, perm)
    local m = DPM.GetMember(src)
    if not m then return nil, 'Nie jesteś pracownikiem warsztatu' end
    if perm and not DPM.Can(src, perm, false) then return nil, 'Brak uprawnień' end
    return m
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

local function hasId(v)
    return v ~= nil and v ~= false and v ~= 0 and v ~= ''
end

-- --------------------------------------------------------------------------
--  Liczenie faktury
-- --------------------------------------------------------------------------
-- „3,5” / „0,25” / „2”
local function hoursLabel(h)
    local s = ('%.2f'):format(h):gsub('0+$', ''):gsub('%.$', '')
    return (s:gsub('%.', ','))
end

local function laborLabel(h, rate)
    return ('Robocizna %s h × %s/h'):format(hoursLabel(h), Utils.Money(rate))
end

-- pozycje własne z kreatora: [{ label, amount }]
local function cleanCustom(custom)
    if custom == nil then return {} end
    if type(custom) ~= 'table' then return nil, 'Nieprawidłowe pozycje własne' end
    local maxLines = tonumber(Config.Invoice.maxCustomLines) or 10
    local maxAmount = tonumber(Config.Invoice.maxCustomAmount) or 250000
    local out = {}
    for i = 1, math.min(#custom, 100) do
        local c = custom[i]
        if type(c) == 'table' then
            local label = str(c.label or c.name, 60)
            local amount = num(c.amount or c.price, nil, nil, nil)
            if label and amount then
                if amount < 0 or amount > maxAmount then
                    return nil, ('Kwota pozycji „%s” musi być w zakresie 0 – %s'):format(label, Utils.Money(maxAmount))
                end
                out[#out + 1] = { label = label, amount = math.floor(amount + 0.5) }
            end
        end
    end
    if #out > maxLines then return nil, ('Maksymalnie %d własnych pozycji na fakturze'):format(maxLines) end
    return out
end

function Invoices.Compute(ws, order, custom, pct)
    local lines, customs = {}, {}
    local laborH = 0.0
    if order then
        for _, it in ipairs(order.items or {}) do
            local price = math.max(0, math.floor(tonumber(it.price) or 0))
            if it.custom then
                customs[#customs + 1] = { label = it.label, qty = 1, unit = price, amount = price, kind = 'custom' }
            else
                lines[#lines + 1] = { label = it.label, qty = 1, unit = price, amount = price, kind = 'part' }
                laborH = laborH + math.max(0.0, tonumber(it.labor) or 0)
            end
        end
    end
    laborH = Utils.Round(laborH, 2)
    if laborH > 0 then
        local rate = laborRate(ws)
        lines[#lines + 1] = { label = laborLabel(laborH, rate), qty = laborH, unit = rate, amount = Catalog.LaborCost(laborH, rate), kind = 'labor' }
    end
    for _, c in ipairs(customs) do lines[#lines + 1] = c end
    for _, c in ipairs(custom or {}) do
        lines[#lines + 1] = { label = c.label, qty = 1, unit = c.amount, amount = c.amount, kind = 'custom' }
    end
    local subtotal = 0
    for _, l in ipairs(lines) do subtotal = subtotal + l.amount end
    pct = Utils.Round(num(pct, 0, 50, 0), 1)
    local discount = math.floor(subtotal * pct / 100 + 0.5)
    local vat = vatRate(ws)
    local tax = math.floor((subtotal - discount) * vat + 0.5)
    return {
        lines = lines, subtotal = subtotal, discount = discount, tax = tax,
        total = subtotal - discount + tax, pct = pct, vat = vat, laborH = laborH,
    }
end

local function derive(inv)
    local base = (inv.subtotal or 0) - (inv.discount or 0)
    inv.netto = base
    inv.vatPct = base > 0 and Utils.Round((inv.tax or 0) / base * 100, 1) or 0
    inv.discountPct = (inv.subtotal or 0) > 0 and Utils.Round((inv.discount or 0) / inv.subtotal * 100, 1) or 0
    inv.methodLabel = inv.method and METHOD_LABELS[inv.method] or nil
    return inv
end

local function rowToInvoice(r)
    return derive({
        id = r.id, number = r.number, workshop = r.workshop, workshopLabel = wsLabel(r.workshop),
        orderId = tonumber(r.order_id), plate = nz(r.plate), vlabel = nz(r.vlabel),
        customer = nz(r.customer), customerName = nz(r.customer_name), issuer = nz(r.issuer), issuerName = nz(r.issuer_name),
        lines = decode(r.lines_json, {}), subtotal = tonumber(r.subtotal) or 0, discount = tonumber(r.discount) or 0,
        tax = tonumber(r.tax) or 0, total = tonumber(r.total) or 0, status = STATUSES[r.status] and r.status or 'unpaid',
        method = nz(r.method), createdAt = tonumber(r.created_at) or 0, paidAt = tonumber(r.paid_at), km = tonumber(r.km),
    })
end

function Invoices.Load(id)
    id = posId(id)
    if not id then return nil end
    local row = MySQL.single.await('SELECT * FROM dpm_invoices WHERE id = ?', { id })
    return row and rowToInvoice(row) or nil
end

-- szkic faktury (bez zapisu)
local function draft(m, o, custom, pct)
    local c = Invoices.Compute(m.workshop, o, custom, pct)
    local km
    if o and o.plate then
        local d = Vehicles.Get(o.plate)
        km = d and math.floor(tonumber(d.km) or 0) or o.km
    end
    local inv = derive({
        workshop = m.workshop, workshopLabel = wsLabel(m.workshop), orderId = o and o.id or nil,
        plate = o and o.plate or nil, vlabel = o and o.vlabel or nil,
        customer = o and o.customer or nil, customerName = o and o.customerName or nil,
        issuer = m.identifier, issuerName = m.name, lines = c.lines,
        subtotal = c.subtotal, discount = c.discount, tax = c.tax, total = c.total,
        status = 'draft', createdAt = now(), km = km,
    })
    inv.discountPct = c.pct
    inv.vatPct = Utils.Round(c.vat * 100, 1)
    inv.laborHours = c.laborH
    return inv
end

-- zapis z kolejnym numerem (blokada per warsztat – numery się nie powtarzają)
local function insertInvoice(inv)
    return Orders.WithLock('inv:' .. inv.workshop, function()
        local t = now()
        local prefix = ('FV/%s/%s/'):format(os.date('%Y', t), os.date('%m', t))
        local last = MySQL.scalar.await('SELECT number FROM dpm_invoices WHERE workshop = ? AND number LIKE ? ORDER BY id DESC LIMIT 1', { inv.workshop, prefix .. '%' })
        local n = type(last) == 'string' and tonumber(last:match('(%d+)$')) or 0
        inv.number = prefix .. ('%04d'):format(math.floor(n) + 1)
        inv.status = 'unpaid'
        inv.createdAt = t
        local cols = 'number, workshop, order_id, plate, vlabel, customer, customer_name, issuer, issuer_name, lines_json, subtotal, discount, tax, total, status, created_at'
        local vals = "?, ?, NULLIF(?, 0), ?, ?, NULLIF(?, ''), ?, ?, ?, ?, ?, ?, ?, ?, 'unpaid', ?"
        local params = {
            inv.number, inv.workshop, inv.orderId or 0, inv.plate or '', inv.vlabel or '', inv.customer or '', inv.customerName or '',
            inv.issuer or '', inv.issuerName or '', json.encode(inv.lines), inv.subtotal, inv.discount, inv.tax, inv.total, t,
        }
        if schema.km then
            cols = cols .. ', km'
            vals = vals .. ', ?'
            params[#params + 1] = math.floor(tonumber(inv.km) or 0)
        end
        local id = MySQL.insert.await(('INSERT INTO dpm_invoices (%s) VALUES (%s)'):format(cols, vals), params)
        if not id then return deny('Nie udało się zapisać faktury') end
        inv.id = id
        return { ok = true, invoice = inv }
    end)
end

local function orderInvoiceErr(o)
    if o.status == 'invoiced' or o.invoiceId then return 'Faktura dla tego zlecenia jest już wystawiona' end
    if o.status == 'paid' then return 'Zlecenie jest już opłacone' end
    if o.status == 'cancelled' then return 'Zlecenie zostało anulowane' end
    return nil
end

-- --------------------------------------------------------------------------
--  Callbacki: faktury
-- --------------------------------------------------------------------------
reg('invoices:preview', function(src, orderId, custom, pct)
    local m, err = need(src, 'invoice')
    if not m then return deny(err) end
    local list, e2 = cleanCustom(custom)
    if not list then return deny(e2) end
    local o
    if hasId(orderId) then
        o = Orders.Load(orderId)
        if not o or o.workshop ~= m.workshop then return deny('Zlecenie nie istnieje') end
        local e3 = orderInvoiceErr(o)
        if e3 then return deny(e3) end
    end
    return { ok = true, invoice = draft(m, o, list, pct) }
end)

reg('invoices:create', function(src, orderId, custom, pct)
    local m, err = need(src, 'invoice')
    if not m then return deny(err) end
    if not throttle(src, 'create', 1500) then return deny('Chwileczkę…') end
    local list, e2 = cleanCustom(custom)
    if not list then return deny(e2) end

    if hasId(orderId) then
        return Orders.Mutate(orderId, function(o)
            if o.workshop ~= m.workshop then return deny('Zlecenie nie istnieje') end
            local e3 = orderInvoiceErr(o)
            if e3 then return deny(e3) end
            if o.status ~= 'ready' then return deny('Zlecenie nie jest jeszcze gotowe – dokończ wszystkie pozycje') end
            local inv = draft(m, o, list, pct)
            if inv.total <= 0 then return deny('Kwota faktury musi być większa od zera') end
            local res = insertInvoice(inv)
            if not res.ok then return res end
            o.status = 'invoiced'
            o.invoiceId = res.invoice.id
            return res, true
        end)
    end

    if #list == 0 then return deny('Dodaj co najmniej jedną pozycję faktury') end
    local inv = draft(m, nil, list, pct)
    if inv.total <= 0 then return deny('Kwota faktury musi być większa od zera') end
    return insertInvoice(inv)
end)

reg('invoices:list', function(src, filter)
    local m, err = need(src, 'invoice')
    if not m then return deny(err) end
    filter = type(filter) == 'table' and filter or {}
    local where, params = { 'workshop = ?' }, { m.workshop }
    if filter.status ~= nil and filter.status ~= 'all' then
        if not STATUSES[filter.status] then return deny('Nieprawidłowy filtr statusu') end
        where[#where + 1] = 'status = ?'
        params[#params + 1] = filter.status
    end
    local oid = posId(filter.orderId)
    if oid then
        where[#where + 1] = 'order_id = ?'
        params[#params + 1] = oid
    end
    local q = str(filter.plate, 16)
    if q then
        where[#where + 1] = 'plate LIKE ?'
        params[#params + 1] = '%' .. (q:upper():gsub('[%%_\\]', '\\%0')) .. '%'
    end
    local rows = MySQL.query.await('SELECT * FROM dpm_invoices WHERE ' .. table.concat(where, ' AND ') .. ' ORDER BY id DESC LIMIT 100', params) or {}
    local list = {}
    for i, r in ipairs(rows) do list[i] = rowToInvoice(r) end
    return { ok = true, list = list }
end)

reg('invoices:get', function(src, id)
    local m, err = need(src, 'invoice')
    if not m then return deny(err) end
    local inv = Invoices.Load(id)
    if not inv or inv.workshop ~= m.workshop then return deny('Faktura nie istnieje') end
    return { ok = true, invoice = inv }
end)

-- --------------------------------------------------------------------------
--  Terminal płatniczy – sesje
-- --------------------------------------------------------------------------
local function sessionFor(invoiceId)
    for _, s in pairs(sessions) do
        if s.invoiceId == invoiceId then return s end
    end
    return nil
end

local function pushState(s, state, data)
    TriggerClientEvent('dp-mechanic:terminal:state', s.target, s.id, state, data or {})
    if s.issuer ~= s.target then TriggerClientEvent('dp-mechanic:terminal:state', s.issuer, s.id, state, data or {}) end
end

local function closeSession(s)
    sessions[s.id] = nil
    if byPlayer[s.issuer] == s.id then byPlayer[s.issuer] = nil end
    if byPlayer[s.target] == s.id then byPlayer[s.target] = nil end
end

local function sessionView(s)
    local inv = Utils.Copy(s.invoice)
    if not inv.customerName then inv.customerName = s.customerName end
    return {
        session = s.id, invoice = inv, pinRequired = s.pinRequired, expires = s.expires,
        timeout = math.max(0, s.expires - now()), issuerName = s.issuerName, customerName = s.customerName,
        workshopLabel = inv.workshopLabel, total = inv.total, currency = Config.Currency,
        method = s.method, state = s.state,
    }
end

local function activeSession(sid, src)
    local s = sessions[posId(sid) or -1]
    if not s then return nil end
    if src and s.target ~= src and s.issuer ~= src then return nil end
    return s
end

reg('invoices:issue', function(src, invoiceId, targetSrc)
    local m, err = need(src, 'invoice')
    if not m then return deny(err) end
    if not throttle(src, 'issue', 1500) then return deny('Chwileczkę…') end
    invoiceId = posId(invoiceId)
    if not invoiceId then return deny('Nieprawidłowa faktura') end
    local target = posId(targetSrc)
    if not target or not online(target) or GetPlayerPed(target) == 0 then return deny('Nie znaleziono klienta') end
    if target == src and not Config.Invoice.allowSelf then return deny('Nie możesz wystawić faktury samemu sobie') end
    if target ~= src and pdist(src, target) > (tonumber(Config.Invoice.targetRadius) or 8.0) + 2.0 then
        return deny('Klient jest za daleko')
    end
    if byPlayer[src] then return deny('Masz już otwartą transakcję na terminalu') end
    if byPlayer[target] then return deny('Klient ma już otwartą inną transakcję') end
    if sessionFor(invoiceId) then return deny('Ta faktura jest już na terminalu') end

    local inv = Invoices.Load(invoiceId)
    if not inv or inv.workshop ~= m.workshop then return deny('Faktura nie istnieje') end
    if inv.status == 'paid' then return deny('Faktura jest już opłacona') end
    if inv.status ~= 'unpaid' then return deny('Faktura została anulowana') end
    -- ponowne sprawdzenie po odczycie z bazy (równoległe wywołania)
    if byPlayer[src] or byPlayer[target] or sessionFor(invoiceId) then return deny('Transakcja jest już w toku') end

    sessionSeq = sessionSeq + 1
    local s = {
        id = sessionSeq, invoiceId = invoiceId, issuer = src, target = target, method = nil, state = 'waiting',
        expires = now() + math.max(15, tonumber(Config.Invoice.terminalTimeout) or 120),
        ws = m.workshop, issuerIdentifier = m.identifier, issuerName = m.name,
        customerIdentifier = Bridge.GetIdentifier(target), customerName = Bridge.GetName(target),
        invoice = inv, pinRequired = inv.total > (tonumber(Config.Invoice.pinAbove) or 500),
    }
    sessions[s.id] = s
    byPlayer[src] = s.id
    byPlayer[target] = s.id

    local view = sessionView(s)
    TriggerClientEvent('dp-mechanic:terminal:open', target, view)
    if target ~= src then TriggerClientEvent('dp-mechanic:terminal:mirror', src, view) end
    return { ok = true, session = s.id, view = view }
end)

reg('terminal:method', function(src, sid, method)
    local s = activeSession(sid)
    if not s or s.target ~= src then return deny('Transakcja nie istnieje lub wygasła') end
    if s.state == 'paying' then return deny('Trwa przetwarzanie płatności') end
    if method ~= 'card' and method ~= 'cash' then return deny('Wybierz kartę albo gotówkę') end
    local acc = method == 'cash' and 'cash' or 'bank'
    if not hasWallet(src) or (tonumber(Bridge.GetMoney(src, acc)) or 0) < s.invoice.total then
        return deny(method == 'cash' and ERR_CASH or ERR_BANK)
    end
    s.method = method
    s.state = 'method'
    pushState(s, 'method', { method = method })
    return { ok = true }
end)

-- rozliczenie płatności (pod blokadą faktury)
local function settle(s)
    local src = s.target
    local row = MySQL.single.await('SELECT * FROM dpm_invoices WHERE id = ?', { s.invoiceId })
    if not row or row.status ~= 'unpaid' then return deny('Ta faktura nie jest już do zapłaty') end
    local total = math.max(0, math.floor(tonumber(row.total) or 0))
    local acc = s.method == 'cash' and 'cash' or 'bank'
    local errMsg = s.method == 'cash' and ERR_CASH or ERR_BANK
    if not hasWallet(src) or (tonumber(Bridge.GetMoney(src, acc)) or 0) < total then return deny(errMsg) end

    local t = now()
    local custName = nz(row.customer_name) or s.customerName or ''
    -- najpierw atomowo zajmujemy fakturę, dopiero potem pobieramy pieniądze
    local n = MySQL.update.await("UPDATE dpm_invoices SET status = 'paid', method = ?, paid_at = ?, customer = COALESCE(customer, NULLIF(?, '')), customer_name = ? WHERE id = ? AND status = 'unpaid'", {
        s.method, t, s.customerIdentifier or '', custName, s.invoiceId,
    })
    if (tonumber(n) or 0) < 1 then return deny('Ta faktura nie jest już do zapłaty') end
    local okR, paid = false, false
    if hasWallet(src) then okR, paid = pcall(Bridge.RemoveMoney, src, acc, total, ('Faktura %s'):format(row.number)) end
    if not okR or not paid then
        MySQL.update.await("UPDATE dpm_invoices SET status = 'unpaid', method = NULL, paid_at = NULL WHERE id = ?", { s.invoiceId })
        return deny(errMsg)
    end

    -- netto na konto warsztatu, prowizja dla wystawiającego (VAT nie trafia do warsztatu)
    local netto = math.max(0, (tonumber(row.subtotal) or 0) - (tonumber(row.discount) or 0))
    local cutPct = Utils.Clamp(tonumber(Config.Invoice.mechanicCut) or 0, 0, 1)
    local issuerOnline = hasWallet(s.issuer)
    local cutAmount = issuerOnline and math.min(netto, math.floor(netto * cutPct + 0.5)) or 0
    safe(function()
        Business.AddBalance(row.workshop, netto - cutAmount, 'invoice', row.number, custName ~= '' and custName or '—')
    end, 'AddBalance')
    if cutAmount > 0 then
        safe(function()
            Bridge.AddMoney(s.issuer, 'bank', cutAmount, ('Prowizja – faktura %s'):format(row.number))
            if Business.AddEarned then Business.AddEarned(row.workshop, s.issuerIdentifier, cutAmount) end
        end, 'prowizja')
        Bridge.Notify(s.issuer, ('Faktura %s opłacona. Twoja prowizja: %s'):format(row.number, Utils.Money(cutAmount)), 'success')
    end

    local orderId = tonumber(row.order_id)
    if orderId then
        safe(function()
            Orders.Mutate(orderId, function(o)
                o.status = 'paid'
                o.invoiceId = s.invoiceId
                if not o.customer and s.customerIdentifier then
                    o.customer, o.customerName = s.customerIdentifier, s.customerName
                end
                if o.projectId and Orders.ProjectStatus then Orders.ProjectStatus(o.projectId, 'done') end
                return { ok = true }, true
            end)
        end, 'zlecenie → opłacone')
    end

    local plate = nz(row.plate)
    if plate then
        Vehicles.AddHistory(plate, row.workshop, 'invoice',
            ('Faktura %s – %s (%s)'):format(row.number, Utils.Money(total), METHOD_LABELS[s.method] or s.method),
            tonumber(row.km), s.issuerName)
    end
    if DPM.NotifyWorkshop then
        DPM.NotifyWorkshop(row.workshop, ('Wpłata %s – faktura %s (%s)'):format(Utils.Money(netto - cutAmount), row.number, custName ~= '' and custName or 'klient'), 'success', 'bank')
    end
    return { ok = true, total = total, number = row.number, cut = cutAmount }
end

reg('terminal:pay', function(src, sid, proof)
    local s = activeSession(sid)
    if not s or s.target ~= src then return deny('Transakcja nie istnieje lub wygasła') end
    if s.state == 'paying' then return deny('Trwa przetwarzanie płatności') end
    if not s.method or s.state ~= 'method' then return deny('Wybierz metodę płatności') end
    if now() >= s.expires then return deny('Czas na płatność minął') end
    proof = type(proof) == 'table' and proof or {}
    if s.method == 'card' and s.pinRequired then
        local pin = proof.pin
        if type(pin) == 'number' then
            pin = num(pin, 0, 9999, nil)
            pin = pin and ('%04d'):format(math.floor(pin)) or nil
        end
        if type(pin) ~= 'string' or not pin:match('^%d%d%d%d$') then return deny('Wprowadź 4-cyfrowy PIN') end
    end
    if s.issuer ~= src then
        if not online(s.issuer) then
            pushState(s, 'cancelled', { by = 'issuer', left = true })
            closeSession(s)
            return deny('Mechanik opuścił serwer – transakcja anulowana')
        end
        if pdist(src, s.issuer) > (tonumber(Config.Invoice.targetRadius) or 8.0) + 12.0 then
            return deny('Jesteś za daleko od terminala')
        end
    end

    s.state = 'paying'
    s.payingAt = now()
    if s.issuer ~= s.target then
        TriggerClientEvent('dp-mechanic:terminal:state', s.issuer, s.id, 'processing', { method = s.method })
    end
    local res = Orders.WithLock('i:' .. s.invoiceId, function() return settle(s) end)
    if not res or not res.ok then
        if s.dropped then
            pushState(s, 'cancelled', { by = 'customer', left = true })
            closeSession(s)
        elseif sessions[s.id] then
            s.state = 'method'
        end
        return res or deny('Płatność nie powiodła się')
    end
    pushState(s, 'paid', { total = res.total, method = s.method, number = res.number })
    closeSession(s)
    return { ok = true, total = res.total, number = res.number }
end)

reg('terminal:cancel', function(src, sid)
    local s = activeSession(sid, src)
    if not s then return deny('Transakcja nie istnieje lub wygasła') end
    if s.state == 'paying' then return deny('Trwa przetwarzanie płatności') end
    pushState(s, 'cancelled', { by = src == s.target and 'customer' or 'issuer' })
    closeSession(s)
    return { ok = true }
end)

reg('invoices:cancel', function(src, id)
    local m, err = need(src, 'orders_all')
    if not m then return deny(err) end
    id = posId(id)
    if not id then return deny('Nieprawidłowa faktura') end
    local res = Orders.WithLock('i:' .. id, function()
        local row = MySQL.single.await('SELECT id, workshop, status, order_id FROM dpm_invoices WHERE id = ?', { id })
        if not row or row.workshop ~= m.workshop then return deny('Faktura nie istnieje') end
        if row.status == 'paid' then return deny('Nie można anulować opłaconej faktury') end
        if row.status ~= 'unpaid' then return deny('Faktura jest już anulowana') end
        local s = sessionFor(id)
        if s and s.state == 'paying' then return deny('Trwa płatność tej faktury') end
        local n = MySQL.update.await("UPDATE dpm_invoices SET status = 'cancelled' WHERE id = ? AND status = 'unpaid'", { id })
        if (tonumber(n) or 0) < 1 then return deny('Nie udało się anulować faktury') end
        if s then
            pushState(s, 'cancelled', { by = 'issuer' })
            closeSession(s)
        end
        return { ok = true, orderId = tonumber(row.order_id) }
    end)
    if not res.ok then return res end
    if res.orderId then
        -- zlecenie wraca do „gotowe” (można wystawić nową fakturę)
        Orders.Mutate(res.orderId, function(o)
            if o.invoiceId ~= id and o.status ~= 'invoiced' then return { ok = true } end
            if o.invoiceId == id then o.invoiceId = nil end
            if o.status == 'invoiced' then o.status = 'ready' end
            return { ok = true }, true
        end)
    end
    return { ok = true }
end)

-- --------------------------------------------------------------------------
--  Wątki / sprzątanie
-- --------------------------------------------------------------------------
CreateThread(function()
    dbWait()
    local ok, res = pcall(Orders.EnsureColumn, 'dpm_invoices', 'km', 'INT DEFAULT 0')
    schema.km = ok and res == true
    schema.checked = true
    if not schema.km then print('^3[dp-mechanic] dpm_invoices: brak kolumny km – przebieg na fakturze nie będzie zapisywany^7') end
end)

-- wygasanie sesji terminala
CreateThread(function()
    while true do
        Wait(5000)
        if next(sessions) then
            local t = now()
            local expired = {}
            for _, s in pairs(sessions) do
                if (s.state ~= 'paying' and t >= s.expires) or (s.state == 'paying' and t - (s.payingAt or t) > 60) then
                    expired[#expired + 1] = s
                end
            end
            for _, s in ipairs(expired) do
                pushState(s, 'timeout', {})
                closeSession(s)
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    calls[src] = nil
    local sid = byPlayer[src]
    if not sid then return end
    byPlayer[src] = nil
    local s = sessions[sid]
    if not s then return end
    if s.state == 'paying' then
        s.dropped = true      -- płatność w toku – dokończy / cofnie ją terminal:pay
        return
    end
    local other = src == s.target and s.issuer or s.target
    if other ~= src and online(other) then
        TriggerClientEvent('dp-mechanic:terminal:state', other, s.id, 'cancelled', { by = src == s.target and 'customer' or 'issuer', left = true })
    end
    closeSession(s)
end)
