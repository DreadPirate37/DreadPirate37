-- ==========================================================================
--  dp-mechanic – warsztaty: konto, pracownicy, rangi, służba, wypłaty, ustawienia
--  Stan trzymany w pamięci (ładowany na starcie po gotowości bazy), zapisy
--  do bazy na bieżąco. Każda operacja pieniężna trafia do dpm_transactions.
-- ==========================================================================
Business = { ws = {}, ready = false }

local byIdentifier = {}    -- [identifier] = wsId – szybkie wyszukiwanie pracownika
local dirtyMinutes = {}    -- [wsId .. '|' .. identifier] = { ws, id } – minuty do zapisu
local payMinutes = {}      -- [src] = minuty służby od ostatniej wypłaty
local fundsWarned = {}     -- [wsId] = os.time() ostatniego ostrzeżenia o braku środków na wypłaty

local KNOWN_PERMS = {}
for _, p in ipairs(Config.Permissions) do KNOWN_PERMS[p.id] = true end

local MAX_RANKS = 20
local MAX_BANK_OP = 10000000
local WEEKDAYS = { 'Nd', 'Pn', 'Wt', 'Śr', 'Cz', 'Pt', 'So' }   -- os.date wday: 1 = niedziela

local catalogCount = 0
for _ in pairs(Catalog.items) do catalogCount = catalogCount + 1 end

-- --------------------------------------------------------------------------
--  Pomocnicze
-- --------------------------------------------------------------------------
local function fail(msg) return { ok = false, err = msg } end

local function sqlAwait(kind, query, params)
    local ok, res = pcall(MySQL[kind].await, query, params)
    if not ok then
        DPM.Error(('SQL: %s | %s'):format(tostring(res), (query:gsub('%s+', ' ')):sub(1, 140)))
        return nil, false
    end
    return res, true
end

-- zapis: w wątku czekamy na wynik (zachowana kolejność zapytań), poza wątkiem – asynchronicznie
local function sqlWrite(query, params, async)
    if not async and coroutine.isyieldable() then
        local _, ok = sqlAwait('update', query, params)
        return ok
    end
    MySQL.update(query, params)
    return true
end

local function jsonDecode(s, default)
    if type(s) ~= 'string' or s == '' then return default end
    local ok, v = pcall(json.decode, s)
    if ok and v ~= nil then return v end
    return default
end

local function toNum(v)
    v = tonumber(v)
    if not v or v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end

local function isInt(v) return v ~= nil and v == math.floor(v) end

local function hasStar(perms)
    if type(perms) ~= 'table' then return false end
    for i = 1, #perms do if perms[i] == '*' then return true end end
    return false
end

local function tableCount(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- lista uprawnień: tylko znane id lub '*'; akceptuje tablicę lub mapę { perm = true }
-- zwraca: lista, pierwsze nieznane uprawnienie (lub nil)
local function parsePerms(input)
    local out, seen, unknown = {}, {}, nil
    if type(input) ~= 'table' then return out end
    local list = input
    if #input == 0 then
        list = {}
        for k, v in pairs(input) do
            if v == true then list[#list + 1] = k end
        end
        table.sort(list, function(a, b) return tostring(a) < tostring(b) end)
    end
    for _, p in ipairs(list) do
        if type(p) == 'string' and not seen[p] then
            if p == '*' or KNOWN_PERMS[p] then
                seen[p] = true
                out[#out + 1] = p
            elseif not unknown then
                unknown = p
            end
        end
    end
    if seen['*'] then out = { '*' } end   -- '*' obejmuje wszystko
    return out, unknown
end

local function firedKey(wsId, identifier)
    return ('fired:%s:%s'):format(wsId, identifier)
end

-- początek doby (lokalny czas serwera) sprzed `back` dni (ujemne = w przód)
local function dayStart(ts, back)
    local t = os.date('*t', ts)
    return os.time({ year = t.year, month = t.month, day = t.day - (back or 0), hour = 0, min = 0, sec = 0 })
end

local function defaultSettings()
    return {
        priceMult = 1.0,
        laborRate = math.floor(tonumber(Config.Invoice.laborRate) or 150),
        vat = tonumber(Config.Invoice.vat) or 0.0,
        motd = '',
    }
end

-- ustawienia z bazy → pełny, poprawny zestaw (wartości spoza zakresu przycinane)
local function normalizeSettings(s)
    local d = defaultSettings()
    if type(s) ~= 'table' then return d end
    local pm, lr, vat = toNum(s.priceMult), toNum(s.laborRate), toNum(s.vat)
    if pm then d.priceMult = Utils.Round(Utils.Clamp(pm, 0.5, 3.0), 2) end
    if lr then d.laborRate = math.floor(Utils.Clamp(lr, 0, 10000)) end
    if vat then d.vat = Utils.Round(Utils.Clamp(vat, 0.0, 0.5), 4) end
    if type(s.motd) == 'string' then d.motd = DPM.Text(s.motd, 200, true) end
    return d
end

-- --------------------------------------------------------------------------
--  API: warsztat / rangi / ustawienia
-- --------------------------------------------------------------------------
function Business.Get(wsId) return Business.ws[wsId] end

function Business.RankOf(wsId, rankId)
    local ws = Business.ws[wsId]
    return ws and rankId and ws.ranks[tonumber(rankId)] or nil
end

-- rangi posortowane: poziom malejąco, potem id
function Business.SortedRanks(wsId)
    local ws = Business.ws[wsId]
    local list = {}
    if not ws then return list end
    for _, r in pairs(ws.ranks) do list[#list + 1] = r end
    table.sort(list, function(a, b)
        if a.level ~= b.level then return a.level > b.level end
        return a.id < b.id
    end)
    return list
end

-- najwyższa ranga (przy równym poziomie – ta z '*')
function Business.TopRank(wsId)
    local best
    for _, r in ipairs(Business.SortedRanks(wsId)) do
        if not best then
            best = r
        elseif r.level == best.level and hasStar(r.perms) and not hasStar(best.perms) then
            best = r
        end
    end
    return best
end

function Business.LowestRank(wsId)
    local list = Business.SortedRanks(wsId)
    return list[#list]
end

-- ranga dla stopnia pracy frameworka: level == grade, inaczej najwyższa ≤ grade, inaczej najniższa
function Business.RankForGrade(wsId, grade)
    grade = tonumber(grade) or 0
    local exact, below
    for _, r in ipairs(Business.SortedRanks(wsId)) do
        if r.level == grade and (not exact or r.id < exact.id) then exact = r end
        if r.level <= grade and not below then below = r end
    end
    return exact or below or Business.LowestRank(wsId)
end

function Business.Settings(wsId)
    local ws = Business.ws[wsId]
    return ws and ws.settings or defaultSettings()
end

function Business.LaborRate(wsId) return Business.Settings(wsId).laborRate end
function Business.PriceMult(wsId) return Business.Settings(wsId).priceMult end
function Business.Vat(wsId) return Business.Settings(wsId).vat end

function Business.IsOwner(m) return m ~= nil and hasStar(m.perms) end

-- --------------------------------------------------------------------------
--  API: konto warsztatu
-- --------------------------------------------------------------------------
-- amount > 0 wpływ, < 0 wydatek (brak środków → false). Zwraca ok, saldo.
function Business.AddBalance(wsId, amount, kind, label, actor)
    local ws = Business.ws[wsId]
    amount = toNum(amount)
    if not ws or not amount then return false, ws and ws.balance or 0 end
    amount = amount >= 0 and math.floor(amount + 0.5) or -math.floor(-amount + 0.5)
    if amount == 0 then return true, ws.balance end
    if amount < 0 and ws.balance + amount < 0 then return false, ws.balance end
    ws.balance = ws.balance + amount
    local bal = ws.balance
    -- zapis przyrostowy – kolejność wykonania zapytań nie ma znaczenia
    MySQL.update('UPDATE dpm_workshops SET balance = balance + ? WHERE id = ?', { amount, wsId })
    MySQL.insert('INSERT INTO dpm_transactions (workshop, amount, balance, type, label, actor, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)', {
        wsId, amount, bal,
        tostring(kind or 'other'):sub(1, 24),
        DPM.Text(label or '', 128),
        DPM.Text(actor or 'system', 64),
        os.time(),
    })
    TriggerEvent('dp-mechanic:balanceChanged', wsId, bal, amount, kind)
    return true, bal
end

-- --------------------------------------------------------------------------
--  API: pracownicy
-- --------------------------------------------------------------------------
function Business.FindEmployee(identifier)
    if not identifier then return nil end
    local wsId = byIdentifier[identifier]
    local ws = wsId and Business.ws[wsId]
    local emp = ws and ws.employees[identifier]
    if emp then return wsId, emp end
    -- awaryjnie (np. indeks nieaktualny)
    for id, w in pairs(Business.ws) do
        if w.employees[identifier] then
            byIdentifier[identifier] = id
            return id, w.employees[identifier]
        end
    end
    return nil
end

-- zatrudnienie / zmiana rangi / przeniesienie z innego warsztatu
function Business.SetEmployee(wsId, identifier, name, rankId, async)
    local ws = Business.ws[wsId]
    rankId = tonumber(rankId)
    if not ws or not identifier or not rankId or not ws.ranks[rankId] then return nil end
    local prevWs = Business.FindEmployee(identifier)
    if prevWs and prevWs ~= wsId then Business.RemoveEmployee(prevWs, identifier, async) end
    name = DPM.Text(name, 64)
    local emp = ws.employees[identifier]
    if emp then
        emp.rankId = rankId
        if name ~= '' then emp.name = name end
        sqlWrite('UPDATE dpm_employees SET rank_id = ?, name = ? WHERE workshop = ? AND identifier = ?',
            { rankId, emp.name, wsId, identifier }, async)
    else
        local now = os.time()
        emp = { identifier = identifier, name = name ~= '' and name or identifier, rankId = rankId, hiredAt = now, minutes = 0, earned = 0 }
        ws.employees[identifier] = emp
        byIdentifier[identifier] = wsId
        sqlWrite('INSERT INTO dpm_employees (workshop, identifier, name, rank_id, hired_at, minutes, earned) VALUES (?, ?, ?, ?, ?, 0, 0) ' ..
            'ON DUPLICATE KEY UPDATE name = ?, rank_id = ?, hired_at = ?, minutes = 0, earned = 0',
            { wsId, identifier, emp.name, rankId, now, emp.name, rankId, now }, async)
    end
    DeleteResourceKvp(firedKey(wsId, identifier))
    return emp
end

function Business.RemoveEmployee(wsId, identifier, async)
    local ws = Business.ws[wsId]
    if not ws or not ws.employees[identifier] then return false end
    ws.employees[identifier] = nil
    if byIdentifier[identifier] == wsId then byIdentifier[identifier] = nil end
    dirtyMinutes[wsId .. '|' .. identifier] = nil
    sqlWrite('DELETE FROM dpm_employees WHERE workshop = ? AND identifier = ?', { wsId, identifier }, async)
    return true
end

function Business.SetEmployeeName(wsId, identifier, name)
    local ws = Business.ws[wsId]
    local emp = ws and ws.employees[identifier]
    name = DPM.Text(name, 64)
    if not emp or name == '' or emp.name == name then return end
    emp.name = name
    MySQL.update('UPDATE dpm_employees SET name = ? WHERE workshop = ? AND identifier = ?', { name, wsId, identifier })
end

function Business.AddEarned(wsId, identifier, amount)
    local ws = Business.ws[wsId]
    local emp = ws and ws.employees[identifier]
    amount = toNum(amount)
    if not emp or not amount or amount == 0 then return false end
    amount = math.floor(amount + 0.5)
    emp.earned = emp.earned + amount
    MySQL.update('UPDATE dpm_employees SET earned = earned + ? WHERE workshop = ? AND identifier = ?', { amount, wsId, identifier })
    return true
end

-- odświeża członkostwo graczy online warsztatu (opcjonalnie tylko z daną rangą)
function Business.RefreshOnline(wsId, rankId)
    local list = {}
    for src, m in pairs(DPM.Members) do
        if m.workshop == wsId and (not rankId or m.rankId == rankId) then list[#list + 1] = src end
    end
    for _, src in ipairs(list) do
        DPM.GetMember(src, true)
        DPM.PushMember(src)
    end
    return list
end

-- auto-import: gracz ma pracę frameworka == ws.job i nie ma go w bazie
-- Osoba zwolniona w tablecie ma znacznik (KVP) blokujący ponowny import – usuwa go
-- dopiero ponowne zatrudnienie przez tablet lub /dpm_setboss (Business.SetEmployee).
function Business.TryImport(src, identifier)
    if not Business.ready or not identifier then return nil end
    local ok, job, grade = pcall(Bridge.GetJob, src)
    if not ok or not job then return nil end
    for _, wsId in ipairs(DPM.WorkshopIds()) do
        local ws = Business.ws[wsId]
        if ws and ws.cfg.job and ws.cfg.job == job then
            if GetResourceKvpInt(firedKey(wsId, identifier)) > 0 then
                -- zwolniony: przy synchronizacji pracy odbieramy też pracę frameworka
                if ws.cfg.syncJob then
                    SetTimeout(0, function()
                        if not GetPlayerName(src) then return end
                        local okJ, cur = pcall(Bridge.GetJob, src)
                        if okJ and cur == ws.cfg.job then
                            pcall(Bridge.SetJob, src, 'unemployed', 0)
                            Bridge.Notify(src, ('Nie jesteś już pracownikiem warsztatu %s'):format(ws.label), 'error', 8000)
                        end
                    end)
                end
                return nil
            end
            local rank = Business.RankForGrade(wsId, grade)
            if rank then
                local emp = Business.SetEmployee(wsId, identifier, DPM.Name(src), rank.id, true)
                if emp then
                    print(('[dp-mechanic] auto-import: %s (%s) → %s / %s'):format(emp.name, identifier, wsId, rank.label))
                    return wsId, emp
                end
            end
        end
    end
    return nil
end

-- wywoływane przez DPM.GetMember; fresh = nowa sesja członka (wejście / zmiana postaci)
function Business.OnMemberResolved(src, m, fresh)
    if not fresh then return end
    local ws = Business.ws[m.workshop]
    if not ws or not ws.cfg.syncJob or not ws.cfg.job then return end
    -- ranga w warsztacie jest nadrzędna: wyrównanie stopnia pracy frameworka
    SetTimeout(0, function()
        local cur = DPM.Members[src]
        if not cur or cur.identifier ~= m.identifier then return end
        local ok, job, grade = pcall(Bridge.GetJob, src)
        if ok and job == ws.cfg.job and tonumber(grade) ~= cur.rank.level then
            pcall(Bridge.SetJob, src, ws.cfg.job, cur.rank.level)
        end
    end)
end

-- --------------------------------------------------------------------------
--  Służba, minuty i wypłaty
-- --------------------------------------------------------------------------
local function flushEmployee(wsId, identifier)
    local key = wsId .. '|' .. identifier
    if not dirtyMinutes[key] then return end
    dirtyMinutes[key] = nil
    local ws = Business.ws[wsId]
    local emp = ws and ws.employees[identifier]
    if emp then
        MySQL.update('UPDATE dpm_employees SET minutes = ? WHERE workshop = ? AND identifier = ?', { emp.minutes, wsId, identifier })
    end
end

local function flushAllMinutes()
    local keys = {}
    for key, v in pairs(dirtyMinutes) do keys[#keys + 1] = v end
    for _, v in ipairs(keys) do flushEmployee(v.ws, v.id) end
end

function Business.OnMemberLeave(src, m)
    payMinutes[src] = nil
    if m and m.workshop and m.identifier then flushEmployee(m.workshop, m.identifier) end
end

-- synchronizacja służby z QBCore/QBox (job.onduty), gdy warsztat synchronizuje pracę
local function syncFrameworkDuty(src, ws, duty)
    if Config.SyncFrameworkDuty == false or not ws.cfg.syncJob or not ws.cfg.job then return end
    if Bridge.name ~= 'qb' and Bridge.name ~= 'qbx' then return end
    local ok, p = pcall(Bridge.GetPlayer, src)
    if not ok or not p or not p.PlayerData or not p.PlayerData.job then return end
    if p.PlayerData.job.name ~= ws.cfg.job then return end
    if p.Functions and p.Functions.SetJobDuty then pcall(p.Functions.SetJobDuty, duty == true) end
end

function Business.PaySalary(src, m)
    local ws = Business.ws[m.workshop]
    local rank = ws and ws.ranks[m.rankId]
    local amount = rank and math.floor(tonumber(rank.salary) or 0) or 0
    if amount <= 0 then return false end
    local account = Config.Salary.account or 'bank'
    local fromBusiness = Config.Salary.fromBusiness ~= false
    if fromBusiness then
        local ok = Business.AddBalance(ws.id, -amount, 'salary', 'Wypłata – ' .. m.name, m.name)
        if not ok then
            Bridge.Notify(src, 'Warsztat nie ma środków na Twoją wypłatę', 'warning', 7000)
            local now = os.time()
            if not fundsWarned[ws.id] or now - fundsWarned[ws.id] > 600 then
                fundsWarned[ws.id] = now
                DPM.NotifyWorkshop(ws.id, 'Brak środków na koncie warsztatu – wypłaty pracowników wstrzymane', 'warning', 'bank_manage')
            end
            return false
        end
    end
    local okCall, paid = pcall(Bridge.AddMoney, src, account, amount, 'Wypłata – ' .. (ws.cfg.label or ws.id))
    if not okCall or not paid then
        if fromBusiness then Business.AddBalance(ws.id, amount, 'refund', 'Zwrot nieudanej wypłaty – ' .. m.name, 'system') end
        return false
    end
    Business.AddEarned(ws.id, m.identifier, amount)
    Bridge.Notify(src, ('Wypłata za służbę: %s'):format(Utils.Money(amount)), 'success', 6000)
    return true
end

-- co minutę: minuty służby (+ zapis co 5 min) i wypłaty co Config.Salary.interval min służby
function Business.Tick(tick)
    local list = {}
    for src, m in pairs(DPM.Members) do
        if m.duty then list[#list + 1] = src end
    end
    local interval = math.max(1, math.floor(tonumber(Config.Salary.interval) or 15))
    for _, src in ipairs(list) do
        local m = DPM.Members[src]
        local ws = m and Business.ws[m.workshop]
        local emp = ws and ws.employees[m.identifier]
        if emp and GetPlayerName(src) then
            emp.minutes = emp.minutes + 1
            dirtyMinutes[m.workshop .. '|' .. m.identifier] = { ws = m.workshop, id = m.identifier }
            if Config.Salary.enabled then
                payMinutes[src] = (payMinutes[src] or 0) + 1
                if payMinutes[src] >= interval then
                    payMinutes[src] = 0
                    local ok, err = pcall(Business.PaySalary, src, m)
                    if not ok then DPM.Error('wypłata: ' .. tostring(err)) end
                end
            end
        end
    end
    if tick % 5 == 0 then flushAllMinutes() end
end

CreateThread(function()
    local tick = 0
    while true do
        Wait(60000)
        if Business.ready then
            tick = tick + 1
            local ok, err = pcall(Business.Tick, tick)
            if not ok then DPM.Error('pętla służby: ' .. tostring(err)) end
        end
    end
end)

-- --------------------------------------------------------------------------
--  Wczytywanie warsztatów
-- --------------------------------------------------------------------------
local function insertStartStock(wsId)
    local qty = math.max(0, math.floor(tonumber(Config.Supplier and Config.Supplier.startStock) or 0))
    if qty <= 0 then return end
    local keys = {}
    for k in pairs(Catalog.items) do keys[#keys + 1] = k end
    table.sort(keys)
    for i = 1, #keys, 100 do
        local rows, params = {}, {}
        for j = i, math.min(#keys, i + 99) do
            rows[#rows + 1] = '(?, ?, ?)'
            params[#params + 1] = wsId
            params[#params + 1] = keys[j]
            params[#params + 1] = qty
        end
        sqlAwait('query', 'INSERT IGNORE INTO dpm_stock (workshop, item, qty) VALUES ' .. table.concat(rows, ', '), params)
    end
end

local function loadWorkshop(wsId, cfg)
    if #wsId > 32 then
        DPM.Error(('identyfikator warsztatu „%s” jest dłuższy niż 32 znaki – pominięto'):format(wsId))
        return false
    end
    local row, ok = sqlAwait('single', 'SELECT balance, settings FROM dpm_workshops WHERE id = ?', { wsId })
    if not ok then return false end

    local isNew = row == nil
    local settings
    if isNew then
        local start = math.max(0, math.floor(tonumber(cfg.startBalance) or 0))
        settings = defaultSettings()
        local _, okIns = sqlAwait('insert', 'INSERT IGNORE INTO dpm_workshops (id, balance, settings) VALUES (?, ?, ?)', { wsId, start, json.encode(settings) })
        if not okIns then return false end
        row = { balance = start }
    else
        settings = normalizeSettings(jsonDecode(row.settings, nil))
    end

    local ws = {
        id = wsId,
        cfg = cfg,
        label = cfg.label or wsId,
        balance = math.floor(tonumber(row.balance) or 0),
        settings = settings,
        ranks = {},
        employees = {},
    }

    -- rangi
    local rows = sqlAwait('query', 'SELECT id, level, label, salary, perms FROM dpm_ranks WHERE workshop = ?', { wsId })
    if not rows then return false end
    for _, r in ipairs(rows) do
        local id = tonumber(r.id)
        ws.ranks[id] = {
            id = id,
            level = math.floor(tonumber(r.level) or 0),
            label = r.label or ('Ranga #' .. id),
            salary = math.floor(tonumber(r.salary) or 0),
            perms = (parsePerms(jsonDecode(r.perms, {}))),
        }
    end
    if next(ws.ranks) == nil then
        for _, d in ipairs(Config.DefaultRanks or {}) do
            local perms = parsePerms(d.perms or {})
            local id = sqlAwait('insert', 'INSERT INTO dpm_ranks (workshop, level, label, salary, perms) VALUES (?, ?, ?, ?, ?)',
                { wsId, math.floor(d.level or 0), d.label or 'Ranga', math.floor(d.salary or 0), json.encode(perms) })
            id = tonumber(id)
            if id then
                ws.ranks[id] = { id = id, level = math.floor(d.level or 0), label = d.label or 'Ranga', salary = math.floor(d.salary or 0), perms = perms }
            end
        end
        if next(ws.ranks) == nil then
            DPM.Error(('warsztat %s nie ma żadnych rang (Config.DefaultRanks pusty?)'):format(wsId))
            return false
        end
    end
    Business.ws[wsId] = ws
    local lowest = Business.LowestRank(wsId)

    -- pracownicy
    local emps = sqlAwait('query', 'SELECT identifier, name, rank_id, hired_at, minutes, earned FROM dpm_employees WHERE workshop = ?', { wsId }) or {}
    for _, e in ipairs(emps) do
        local rankId = tonumber(e.rank_id)
        if not ws.ranks[rankId or -1] then
            -- ranga usunięta ręcznie z bazy → najniższa
            rankId = lowest.id
            MySQL.update('UPDATE dpm_employees SET rank_id = ? WHERE workshop = ? AND identifier = ?', { rankId, wsId, e.identifier })
        end
        ws.employees[e.identifier] = {
            identifier = e.identifier,
            name = e.name ~= '' and e.name or e.identifier,
            rankId = rankId,
            hiredAt = tonumber(e.hired_at) or 0,
            minutes = tonumber(e.minutes) or 0,
            earned = tonumber(e.earned) or 0,
        }
        if byIdentifier[e.identifier] and byIdentifier[e.identifier] ~= wsId then
            print(('^3[dp-mechanic] %s jest zapisany w kilku warsztatach (%s, %s) – używany pierwszy^7'):format(e.identifier, byIdentifier[e.identifier], wsId))
        else
            byIdentifier[e.identifier] = wsId
        end
    end

    if isNew then insertStartStock(wsId) end
    DPM.Debug(('warsztat %s: saldo %d, rang %d, pracowników %d%s'):format(wsId, ws.balance, tableCount(ws.ranks), tableCount(ws.employees), isNew and ' (nowy)' or ''))
    return true
end

CreateThread(function()
    if not DB.Await() then
        DPM.Error('warsztaty nie zostały wczytane – baza danych niedostępna')
        return
    end
    local ids = DPM.WorkshopIds()
    for _, wsId in ipairs(ids) do
        local ok, res = pcall(loadWorkshop, wsId, Config.Workshops[wsId])
        if not ok then DPM.Error(('błąd wczytywania warsztatu %s: %s'):format(wsId, tostring(res)))
        elseif not res then DPM.Error(('warsztat %s nie został wczytany'):format(wsId)) end
    end
    Business.ready = true
    print(('^2[dp-mechanic]^7 wczytano warsztaty: %d'):format(tableCount(Business.ws)))
    -- członkostwo graczy już obecnych na serwerze (restart zasobu)
    for _, s in ipairs(GetPlayers()) do
        local src = tonumber(s)
        if src then
            DPM.GetMember(src, true)
            DPM.PushMember(src)
        end
    end
    TriggerEvent('dp-mechanic:businessReady')
end)

-- czeka (w wątku) aż warsztaty zostaną wczytane
function Business.Await(timeout)
    local limit = timeout and (GetGameTimer() + timeout) or nil
    while not Business.ready do
        if limit and GetGameTimer() > limit then return false end
        if DB.failed then return false end
        Wait(100)
    end
    return true
end

-- --------------------------------------------------------------------------
--  Callbacki (wymagany członek warsztatu; perm = wymagane uprawnienie)
-- --------------------------------------------------------------------------
local function reg(name, perm, fn)
    DPM.RegisterCallback(name, function(src, ...)
        if not Business.ready then return fail('Warsztaty jeszcze się wczytują – spróbuj za chwilę') end
        local m = DPM.GetMember(src)
        if not m then return fail('Nie jesteś pracownikiem warsztatu') end
        local ws = Business.ws[m.workshop]
        if not ws then return fail('Twój warsztat nie istnieje') end
        if perm and not Utils.HasPerm(m.perms, perm) then return fail('Brak uprawnień: ' .. DPM.PermLabel(perm)) end
        return fn(src, m, ws, ...)
    end)
end

-- ---------------------------------------------------------------- tablet --
reg('tablet:init', nil, function(src, m, ws)
    local now = os.time()
    local today = dayStart(now, 0)
    local stats = {
        ordersOpen = 0, ordersProgress = 0, ordersReady = 0, ordersToday = 0,
        revenueToday = 0, revenueWeek = 0,
        employeesOnDuty = 0, employeesTotal = 0,
        lowStock = 0,
        balance = Utils.HasPerm(m.perms, 'bank') and ws.balance or nil,
    }

    -- zlecenia: liczniki statusów + dzisiejsze
    local o = sqlAwait('single', [[
        SELECT COALESCE(SUM(status = 'open'), 0) AS o_open,
               COALESCE(SUM(status = 'progress'), 0) AS o_progress,
               COALESCE(SUM(status = 'ready'), 0) AS o_ready,
               COALESCE(SUM(created_at >= ?), 0) AS o_today
        FROM dpm_orders
        WHERE workshop = ? AND (status IN ('open', 'progress', 'ready') OR created_at >= ?)
    ]], { today, ws.id, today })
    if o then
        stats.ordersOpen = math.floor(tonumber(o.o_open) or 0)
        stats.ordersProgress = math.floor(tonumber(o.o_progress) or 0)
        stats.ordersReady = math.floor(tonumber(o.o_ready) or 0)
        stats.ordersToday = math.floor(tonumber(o.o_today) or 0)
    end

    -- przychód netto (subtotal − rabat) z opłaconych faktur: 7 dni, każdy dzień osobno
    local days = {}
    for i = 6, 0, -1 do
        days[#days + 1] = { from = dayStart(now, i), to = dayStart(now, i - 1) }
    end
    local cols, params = {}, {}
    for i, d in ipairs(days) do
        cols[i] = ('COALESCE(SUM(CASE WHEN paid_at >= ? AND paid_at < ? THEN subtotal - discount ELSE 0 END), 0) AS d%d'):format(i)
        params[#params + 1] = d.from
        params[#params + 1] = d.to
    end
    params[#params + 1] = ws.id
    params[#params + 1] = days[1].from
    local rev = sqlAwait('single', 'SELECT ' .. table.concat(cols, ', ') ..
        " FROM dpm_invoices WHERE workshop = ? AND status = 'paid' AND paid_at >= ?", params)
    local chart = {}
    for i, d in ipairs(days) do
        local v = math.floor((rev and tonumber(rev['d' .. i]) or 0) + 0.5)
        chart[i] = { label = WEEKDAYS[os.date('*t', d.from).wday], value = v, ts = d.from, today = i == #days }
        stats.revenueWeek = stats.revenueWeek + v
    end
    stats.revenueToday = chart[#chart].value

    -- braki magazynowe: pozycje katalogu ze stanem ≤ 1 (brak wiersza = 0 szt.)
    local okRows = sqlAwait('query', 'SELECT item FROM dpm_stock WHERE workshop = ? AND qty > 1', { ws.id })
    if okRows then
        local okCount = 0
        for _, r in ipairs(okRows) do
            if Catalog.items[r.item] then okCount = okCount + 1 end
        end
        stats.lowStock = math.max(0, catalogCount - okCount)
    end

    -- pracownicy
    local total = sqlAwait('scalar', 'SELECT COUNT(*) FROM dpm_employees WHERE workshop = ?', { ws.id })
    stats.employeesTotal = math.floor(tonumber(total) or tableCount(ws.employees))
    for _, mm in pairs(DPM.Members) do
        if mm.workshop == ws.id and mm.duty then stats.employeesOnDuty = stats.employeesOnDuty + 1 end
    end

    -- ostatnie zlecenia
    local recent = {}
    local rows = sqlAwait('query', 'SELECT id, plate, vlabel, status, items, created_at FROM dpm_orders WHERE workshop = ? ORDER BY id DESC LIMIT 6', { ws.id })
    for _, r in ipairs(rows or {}) do
        local sum = 0
        local items = jsonDecode(r.items, {})
        if type(items) == 'table' then
            for _, it in ipairs(items) do
                if type(it) == 'table' then sum = sum + (tonumber(it.price) or 0) end
            end
        end
        recent[#recent + 1] = {
            id = tonumber(r.id), plate = r.plate, vlabel = r.vlabel or r.plate, status = r.status,
            total = math.floor(sum + 0.5), createdAt = tonumber(r.created_at) or 0,
        }
    end

    return {
        ok = true,
        me = {
            identifier = m.identifier, name = m.name,
            rank = { id = m.rank.id, label = m.rank.label, level = m.rank.level },
            perms = m.perms, duty = m.duty == true, owner = Business.IsOwner(m),
        },
        workshop = { id = ws.id, label = ws.label, motd = ws.settings.motd },
        stats = stats,
        recent = recent,
        chart = chart,
        config = {
            currency = Config.Currency,
            vat = ws.settings.vat,
            laborRate = ws.settings.laborRate,
            priceMult = ws.settings.priceMult,
            permissions = Config.Permissions,
            assembly = Config.Assembly.enabled == true,
            requireDuty = Config.RequireDuty == true,
            maxCustomLines = Config.Invoice.maxCustomLines,
            maxCustomAmount = Config.Invoice.maxCustomAmount,
            salaryInterval = Config.Salary.interval,
            version = DPM.version,
        },
    }
end)

-- ---------------------------------------------------------------- służba --
reg('duty:toggle', nil, function(src, m, ws)
    m.duty = not m.duty
    m.dutyAt = os.time()
    if not m.duty then flushEmployee(ws.id, m.identifier) end
    syncFrameworkDuty(src, ws, m.duty)
    DPM.PushMember(src)
    TriggerEvent('dp-mechanic:dutyChanged', src, ws.id, m.duty)
    return { ok = true, duty = m.duty }
end)

-- ------------------------------------------------------------ pracownicy --
reg('employees:list', nil, function(src, m, ws)
    local online = {}
    for _, mm in pairs(DPM.Members) do
        if mm.workshop == ws.id then online[mm.identifier] = mm end
    end
    local canManage = Utils.HasPerm(m.perms, 'employees')
    local owner = Business.IsOwner(m)
    local list = {}
    for id, e in pairs(ws.employees) do
        local r = ws.ranks[e.rankId]
        local om = online[id]
        local level = r and r.level or 0
        list[#list + 1] = {
            identifier = id,
            name = e.name,
            rankId = e.rankId,
            rankLabel = r and r.label or '—',
            level = level,
            online = om ~= nil,
            duty = om ~= nil and om.duty == true,
            minutes = e.minutes,
            earned = e.earned,
            hiredAt = e.hiredAt,
            me = id == m.identifier,
            manageable = canManage and id ~= m.identifier and level < m.rank.level and (owner or not (r and hasStar(r.perms))),
        }
    end
    table.sort(list, function(a, b)
        if a.level ~= b.level then return a.level > b.level end
        if a.online ~= b.online then return a.online end
        return tostring(a.name) < tostring(b.name)
    end)
    return { ok = true, list = list }
end)

reg('employees:nearby', 'employees', function(src, m, ws)
    local list = {}
    for _, p in ipairs(DPM.NearPlayers(src, 5.0)) do
        local identifier = DPM.Identifier(p.src)
        if identifier and not ws.employees[identifier] then
            local otherWs = Business.FindEmployee(identifier)
            list[#list + 1] = {
                src = p.src, name = p.name, dist = p.dist,
                other = otherWs and (Business.ws[otherWs].label or otherWs) or nil,
            }
        end
    end
    return { ok = true, list = list }
end)

reg('employees:hire', 'employees', function(src, m, ws, targetSrc, rankId)
    local target = tonumber(targetSrc)
    if not target or not GetPlayerName(target) then return fail('Ta osoba jest niedostępna') end
    if target == src then return fail('Nie możesz zatrudnić samego siebie') end
    local sc, tc = DPM.Coords(src), DPM.Coords(target)
    if not sc or not tc or #(sc - tc) > 6.0 then return fail('Osoba musi stać obok Ciebie') end
    local identifier = DPM.Identifier(target)
    if not identifier then return fail('Postać tej osoby nie jest jeszcze wczytana') end
    local curWs = Business.FindEmployee(identifier)
    if curWs == ws.id then return fail('Ta osoba już pracuje w Twoim warsztacie') end
    if curWs then return fail(('Ta osoba pracuje już w warsztacie %s'):format(Business.ws[curWs].label or curWs)) end

    local rank
    if rankId ~= nil then
        rank = ws.ranks[tonumber(rankId) or -1]
        if not rank then return fail('Wybrana ranga nie istnieje') end
    else
        rank = Business.LowestRank(ws.id)
    end
    if not Business.IsOwner(m) and (rank.level >= m.rank.level or hasStar(rank.perms)) then
        return fail('Możesz zatrudniać tylko na rangi niższe od swojej')
    end

    local name = DPM.Name(target)
    local emp = Business.SetEmployee(ws.id, identifier, name, rank.id)
    if not emp then return fail('Nie udało się zatrudnić tej osoby') end
    if ws.cfg.syncJob and ws.cfg.job then pcall(Bridge.SetJob, target, ws.cfg.job, rank.level) end
    DPM.GetMember(target, true)
    DPM.PushMember(target)
    Bridge.Notify(target, ('Zostałeś zatrudniony w %s jako %s'):format(ws.label, rank.label), 'success', 7000)
    Bridge.Notify(src, ('Zatrudniono: %s (%s)'):format(name, rank.label), 'success')
    -- informacja dla pozostałych osób zarządzających personelem
    for s, mm in pairs(DPM.Members) do
        if s ~= src and s ~= target and mm.workshop == ws.id and Utils.HasPerm(mm.perms, 'employees') then
            Bridge.Notify(s, ('Nowy pracownik: %s (%s)'):format(name, rank.label), 'info')
        end
    end
    return { ok = true }
end)

reg('employees:fire', 'employees', function(src, m, ws, identifier)
    local emp = type(identifier) == 'string' and ws.employees[identifier] or nil
    if not emp then return fail('Ta osoba nie jest pracownikiem warsztatu') end
    if identifier == m.identifier then return fail('Nie możesz zwolnić samego siebie') end
    local r = ws.ranks[emp.rankId]
    if (r and r.level or 0) >= m.rank.level or (r and hasStar(r.perms) and not Business.IsOwner(m)) then
        return fail('Nie możesz zwolnić osoby o randze równej lub wyższej od swojej')
    end

    local tsrc = DPM.OnlineSource(identifier)
    Business.RemoveEmployee(ws.id, identifier)
    -- znacznik: nie importuj ponownie z pracy frameworka (usuwany przy ponownym zatrudnieniu)
    if ws.cfg.job then SetResourceKvpInt(firedKey(ws.id, identifier), os.time()) end
    if tsrc then
        if ws.cfg.syncJob and ws.cfg.job then
            local ok, job = pcall(Bridge.GetJob, tsrc)
            if ok and job == ws.cfg.job then pcall(Bridge.SetJob, tsrc, 'unemployed', 0) end
        end
        DPM.GetMember(tsrc, true)
        DPM.PushMember(tsrc)
        Bridge.Notify(tsrc, ('Zostałeś zwolniony z warsztatu %s'):format(ws.label), 'error', 8000)
    end
    Bridge.Notify(src, ('Zwolniono: %s'):format(emp.name), 'success')
    return { ok = true }
end)

reg('employees:setRank', 'employees', function(src, m, ws, identifier, rankId)
    local emp = type(identifier) == 'string' and ws.employees[identifier] or nil
    if not emp then return fail('Ta osoba nie jest pracownikiem warsztatu') end
    if identifier == m.identifier then return fail('Nie możesz zmienić własnej rangi') end
    local rank = ws.ranks[tonumber(rankId) or -1]
    if not rank then return fail('Wybrana ranga nie istnieje') end
    local cur = ws.ranks[emp.rankId]
    if (cur and cur.level or 0) >= m.rank.level or (cur and hasStar(cur.perms) and not Business.IsOwner(m)) then
        return fail('Nie możesz zmieniać rangi osoby równej lub wyższej rangą')
    end
    if not Business.IsOwner(m) and (rank.level >= m.rank.level or hasStar(rank.perms)) then
        return fail('Możesz nadawać tylko rangi niższe od swojej')
    end
    if emp.rankId == rank.id then return { ok = true } end

    local promoted = not cur or rank.level > cur.level
    Business.SetEmployee(ws.id, identifier, nil, rank.id)
    local tsrc = DPM.OnlineSource(identifier)
    if tsrc then
        if ws.cfg.syncJob and ws.cfg.job then
            local ok, job = pcall(Bridge.GetJob, tsrc)
            if ok and job == ws.cfg.job then pcall(Bridge.SetJob, tsrc, ws.cfg.job, rank.level) end
        end
        DPM.GetMember(tsrc, true)
        DPM.PushMember(tsrc)
        Bridge.Notify(tsrc, ('%s: Twoja nowa ranga – %s'):format(promoted and 'Awans' or 'Zmiana rangi', rank.label), promoted and 'success' or 'info', 7000)
    end
    return { ok = true }
end)

-- ----------------------------------------------------------------- rangi --
reg('ranks:list', nil, function(src, m, ws)
    local counts = {}
    for _, e in pairs(ws.employees) do counts[e.rankId] = (counts[e.rankId] or 0) + 1 end
    local owner = Business.IsOwner(m)
    local list = {}
    for _, r in ipairs(Business.SortedRanks(ws.id)) do
        list[#list + 1] = {
            id = r.id, level = r.level, label = r.label, salary = r.salary, perms = r.perms,
            members = counts[r.id] or 0,
            editable = owner or r.level < m.rank.level,
        }
    end
    return { ok = true, list = list, permissions = Config.Permissions, maxLevel = 20 }
end)

reg('ranks:save', 'ranks', function(src, m, ws, data)
    if type(data) ~= 'table' then return fail('Nieprawidłowe dane rangi') end
    local owner = Business.IsOwner(m)

    local label = DPM.Text(data.label, 48)
    if label == '' then return fail('Podaj nazwę rangi (1–48 znaków)') end
    if DPM.TextLen(Utils.Trim(tostring(data.label or ''))) > 48 then return fail('Nazwa rangi może mieć maksymalnie 48 znaków') end
    local level = toNum(data.level)
    if not level or not isInt(level) or level < 0 or level > 20 then return fail('Poziom rangi musi być liczbą całkowitą 0–20') end
    local salary = toNum(data.salary)
    if not salary or salary < 0 or salary > 100000 then return fail('Pensja musi mieścić się w zakresie 0–100 000') end
    salary = math.floor(salary)
    local perms, unknown = parsePerms(data.perms)
    if unknown then return fail('Nieznane uprawnienie: ' .. tostring(unknown)) end
    local star = hasStar(perms)
    if star and not owner then return fail('Tylko właściciel może nadać pełne uprawnienia (*)') end
    if not owner then
        if level >= m.rank.level then return fail('Możesz tworzyć i edytować tylko rangi niższe od swojej') end
        for _, p in ipairs(perms) do
            if not Utils.HasPerm(m.perms, p) then
                return fail('Nie możesz nadać uprawnienia, którego sam nie masz: ' .. DPM.PermLabel(p))
            end
        end
    end

    local id = toNum(data.id)
    if id and id > 0 then
        local r = ws.ranks[id]
        if not r then return fail('Ranga nie istnieje') end
        if not owner and r.level >= m.rank.level then return fail('Nie możesz edytować rangi równej lub wyższej od swojej') end
        if r.id == m.rankId and hasStar(r.perms) and not star then
            return fail('Nie możesz odebrać pełnych uprawnień własnej randze')
        end
        local _, ok = sqlAwait('update', 'UPDATE dpm_ranks SET level = ?, label = ?, salary = ?, perms = ? WHERE id = ? AND workshop = ?',
            { level, label, salary, json.encode(perms), id, ws.id })
        if not ok then return fail('Nie udało się zapisać rangi') end
        r = ws.ranks[id]
        if not r then return fail('Ranga została usunięta') end
        local levelChanged = r.level ~= level
        r.level, r.label, r.salary, r.perms = level, label, salary, perms
        -- odświeżenie członków z tą rangą (uprawnienia / nazwa / stopień pracy)
        local srcs = Business.RefreshOnline(ws.id, id)
        if levelChanged and ws.cfg.syncJob and ws.cfg.job then
            for _, s in ipairs(srcs) do
                local okJ, job = pcall(Bridge.GetJob, s)
                if okJ and job == ws.cfg.job then pcall(Bridge.SetJob, s, ws.cfg.job, level) end
            end
        end
        return { ok = true, id = id }
    end

    if tableCount(ws.ranks) >= MAX_RANKS then return fail(('Osiągnięto limit rang (%d)'):format(MAX_RANKS)) end
    local newId = tonumber((sqlAwait('insert', 'INSERT INTO dpm_ranks (workshop, level, label, salary, perms) VALUES (?, ?, ?, ?, ?)',
        { ws.id, level, label, salary, json.encode(perms) })))
    if not newId then return fail('Nie udało się utworzyć rangi') end
    ws.ranks[newId] = { id = newId, level = level, label = label, salary = salary, perms = perms }
    return { ok = true, id = newId }
end)

reg('ranks:delete', 'ranks', function(src, m, ws, id)
    id = toNum(id)
    local r = id and ws.ranks[id]
    if not r then return fail('Ranga nie istnieje') end
    local owner = Business.IsOwner(m)
    if r.id == m.rankId then return fail('Nie możesz usunąć własnej rangi') end
    if not owner and r.level >= m.rank.level then return fail('Nie możesz usunąć rangi równej lub wyższej od swojej') end
    local holders = 0
    for _, e in pairs(ws.employees) do
        if e.rankId == id then holders = holders + 1 end
    end
    if holders > 0 then
        return fail(('Tej rangi nie można usunąć – ma ją %d %s'):format(holders, holders == 1 and 'pracownik' or 'pracowników'))
    end
    if tableCount(ws.ranks) <= 1 then return fail('Warsztat musi mieć co najmniej jedną rangę') end
    if hasStar(r.perms) then
        local stars = 0
        for _, rr in pairs(ws.ranks) do if hasStar(rr.perms) then stars = stars + 1 end end
        if stars <= 1 then return fail('Nie można usunąć jedynej rangi z pełnymi uprawnieniami') end
    end
    local _, ok = sqlAwait('update', 'DELETE FROM dpm_ranks WHERE id = ? AND workshop = ?', { id, ws.id })
    if not ok then return fail('Nie udało się usunąć rangi') end
    ws.ranks[id] = nil
    return { ok = true }
end)

-- ------------------------------------------------------------------ bank --
local function parseAmount(v)
    v = toNum(v)
    if not v then return nil end
    v = math.floor(v)
    if v < 1 or v > MAX_BANK_OP then return nil end
    return v
end

reg('bank:get', 'bank', function(src, m, ws)
    local rows = sqlAwait('query', 'SELECT id, amount, balance, type, label, actor, created_at FROM dpm_transactions WHERE workshop = ? ORDER BY id DESC LIMIT 60', { ws.id })
    local list = {}
    for i, r in ipairs(rows or {}) do
        list[i] = {
            id = tonumber(r.id),
            amount = tonumber(r.amount) or 0,
            balance = tonumber(r.balance) or 0,
            type = r.type,
            label = r.label,
            actor = r.actor,
            createdAt = tonumber(r.created_at) or 0,
        }
    end
    return { ok = true, balance = ws.balance, list = list, canManage = Utils.HasPerm(m.perms, 'bank_manage') }
end)

reg('bank:deposit', 'bank_manage', function(src, m, ws, amount)
    amount = parseAmount(amount)
    if not amount then return fail(('Podaj kwotę od 1 do %s'):format(Utils.Money(MAX_BANK_OP))) end
    local okM, have = pcall(Bridge.GetMoney, src, 'bank')
    if not okM or (tonumber(have) or 0) < amount then return fail('Brak wystarczających środków na koncie') end
    local okR, removed = pcall(Bridge.RemoveMoney, src, 'bank', amount, 'Wpłata na konto warsztatu ' .. ws.label)
    if not okR or not removed then return fail('Brak wystarczających środków na koncie') end
    local _, bal = Business.AddBalance(ws.id, amount, 'deposit', 'Wpłata – ' .. m.name, m.name)
    return { ok = true, balance = bal }
end)

reg('bank:withdraw', 'bank_manage', function(src, m, ws, amount)
    amount = parseAmount(amount)
    if not amount then return fail(('Podaj kwotę od 1 do %s'):format(Utils.Money(MAX_BANK_OP))) end
    local ok, bal = Business.AddBalance(ws.id, -amount, 'withdraw', 'Wypłata – ' .. m.name, m.name)
    if not ok then return fail('Brak wystarczających środków na koncie warsztatu') end
    local okA, added = pcall(Bridge.AddMoney, src, 'bank', amount, 'Wypłata z konta warsztatu ' .. ws.label)
    if not okA or not added then
        Business.AddBalance(ws.id, amount, 'refund', 'Zwrot – nieudana wypłata', m.name)
        return fail('Nie udało się przelać środków – operację cofnięto')
    end
    return { ok = true, balance = bal }
end)

-- ------------------------------------------------------------- ustawienia --
reg('settings:get', nil, function(src, m, ws)
    return { ok = true, settings = Utils.Copy(ws.settings), canEdit = Utils.HasPerm(m.perms, 'settings') }
end)

reg('settings:save', 'settings', function(src, m, ws, data)
    if type(data) ~= 'table' then return fail('Nieprawidłowe dane ustawień') end
    local s = Utils.Copy(ws.settings)
    local EPS = 1e-6
    if data.priceMult ~= nil then
        local v = toNum(data.priceMult)
        if not v or v < 0.5 - EPS or v > 3.0 + EPS then return fail('Mnożnik cen musi mieścić się w zakresie 0,5–3,0') end
        s.priceMult = Utils.Round(Utils.Clamp(v, 0.5, 3.0), 2)
    end
    if data.laborRate ~= nil then
        local v = toNum(data.laborRate)
        if not v or v < 0 or v > 10000 then return fail('Stawka roboczogodziny musi mieścić się w zakresie 0–10 000') end
        s.laborRate = math.floor(v + 0.5)
    end
    if data.vat ~= nil then
        local v = toNum(data.vat)
        if not v or v < -EPS or v > 0.5 + EPS then return fail('VAT musi mieścić się w zakresie 0–50%') end
        s.vat = Utils.Round(Utils.Clamp(v, 0.0, 0.5), 4)
    end
    if data.motd ~= nil then
        if type(data.motd) ~= 'string' then return fail('Nieprawidłowa wiadomość dnia') end
        local motd = DPM.Text(data.motd, nil, true)
        if DPM.TextLen(motd) > 200 then return fail('Wiadomość dnia może mieć maksymalnie 200 znaków') end
        s.motd = motd
    end
    local _, ok = sqlAwait('update', 'UPDATE dpm_workshops SET settings = ? WHERE id = ?', { json.encode(s), ws.id })
    if not ok then return fail('Nie udało się zapisać ustawień') end
    ws.settings = s
    TriggerEvent('dp-mechanic:settingsChanged', ws.id, Utils.Copy(s))
    return { ok = true, settings = Utils.Copy(s) }
end)

-- --------------------------------------------------------------------------
--  Sprzątanie
-- --------------------------------------------------------------------------
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    flushAllMinutes()
end)

-- --------------------------------------------------------------------------
--  Eksporty
-- --------------------------------------------------------------------------
exports('GetWorkshopBalance', function(wsId)
    local ws = Business.ws[wsId]
    return ws and ws.balance or nil
end)

-- amount > 0 wpłata, < 0 obciążenie (false przy braku środków); zwraca ok, saldo
exports('AddWorkshopMoney', function(wsId, amount, label)
    local res = GetInvokingResource() or GetCurrentResourceName()
    if not Business.ws[wsId] then return false, 0 end
    return Business.AddBalance(wsId, amount, 'external', label or ('Operacja: ' .. res), res)
end)
