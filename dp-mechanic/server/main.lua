-- ==========================================================================
--  dp-mechanic – rdzeń serwera (DPM)
--  Callbacki (pcall + limit zapytań na gracza), członkostwo w warsztatach
--  (cache, push do klienta, auto-import z pracy frameworka), narzędzia
--  dystansu / encji, komendy administracyjne, przedmiot „tablet”.
--  Pozostałe moduły serwera (DB, Business, Vehicles, Orders, Invoices, Lifts)
--  korzystają z tej tabeli – ładowana jest jako pierwsza.
-- ==========================================================================
DPM = { Members = {} }   -- [src] = member

local RESOURCE = GetCurrentResourceName()
DPM.version = GetResourceMetadata(RESOURCE, 'version', 0) or '1.0.0'

-- --------------------------------------------------------------------------
--  Logi / czas
-- --------------------------------------------------------------------------
function DPM.Debug(...)
    if Config.Debug then print('^3[dp-mechanic]^7', ...) end
end

function DPM.Error(msg)
    print(('^1[dp-mechanic] %s^7'):format(tostring(msg)))
end

function DPM.Now() return os.time() end

-- --------------------------------------------------------------------------
--  Tekst od gracza – bez znaków sterujących, poprawny UTF-8, max N znaków
-- --------------------------------------------------------------------------
function DPM.Text(s, maxLen, multiline)
    if type(s) == 'number' then s = tostring(s) end
    if type(s) ~= 'string' then return '' end
    -- niepoprawne UTF-8 → zostawiamy tylko ASCII
    if not utf8.len(s) then s = s:gsub('[\128-\255]', '') end
    if multiline then
        s = s:gsub('\r\n?', '\n')
        s = s:gsub('%c', function(c) return c == '\n' and '\n' or ' ' end)
        s = s:gsub('[ \t]+', ' ')
        s = s:gsub('\n%s*\n[%s\n]*', '\n\n')
    else
        s = s:gsub('%c', ' ')
        s = s:gsub('%s+', ' ')
    end
    s = Utils.Trim(s)
    if maxLen then
        local len = utf8.len(s) or #s
        if len > maxLen then
            local cut = utf8.offset(s, maxLen + 1) or (maxLen + 1)
            s = Utils.Trim(s:sub(1, cut - 1))
        end
    end
    return s
end

-- długość tekstu w znakach (nie bajtach)
function DPM.TextLen(s)
    if type(s) ~= 'string' then return 0 end
    return utf8.len(s) or #s
end

-- etykiety uprawnień (do komunikatów)
local permLabels = {}
for _, p in ipairs(Config.Permissions or {}) do permLabels[p.id] = p.label end
function DPM.PermLabel(perm) return permLabels[perm] or tostring(perm) end

-- lista warsztatów (posortowana – do komunikatów i wartości domyślnych)
function DPM.WorkshopIds()
    local ids = {}
    for id in pairs(Config.Workshops) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

-- --------------------------------------------------------------------------
--  Callbacki  (klient: DPM.Callback(name, ...)  ↔  serwer: DPM.RegisterCallback)
-- --------------------------------------------------------------------------
local handlers = {}

function DPM.RegisterCallback(name, fn)
    if type(name) ~= 'string' or type(fn) ~= 'function' then
        error('DPM.RegisterCallback: wymagana nazwa (string) i funkcja', 2)
    end
    if handlers[name] then DPM.Debug(('callback %s został nadpisany'):format(name)) end
    handlers[name] = fn
end

function DPM.HasCallback(name) return handlers[name] ~= nil end

-- limit zapytań: kubełek żetonów per gracz (pozwala na krótkie serie, blokuje spam)
local RL = Config.RateLimit or {}
local RL_BURST = tonumber(RL.burst) or 30        -- maks. seria zapytań
local RL_RATE = tonumber(RL.perSecond) or 10     -- odnawianie żetonów na sekundę
local buckets, rlWarned = {}, {}

local function allowCall(src)
    local now = GetGameTimer()
    local b = buckets[src]
    if not b then
        b = { tokens = RL_BURST, at = now }
        buckets[src] = b
    else
        b.tokens = math.min(RL_BURST, b.tokens + (now - b.at) * RL_RATE / 1000.0)
        b.at = now
    end
    if b.tokens < 1.0 then
        if not rlWarned[src] or now - rlWarned[src] > 10000 then
            rlWarned[src] = now
            print(('^3[dp-mechanic] gracz %s (%s) przekracza limit zapytań^7'):format(src, GetPlayerName(src) or '?'))
        end
        return false
    end
    b.tokens = b.tokens - 1.0
    return true
end

local function traceback(err)
    return debug.traceback(tostring(err), 2)
end

RegisterNetEvent('dp-mechanic:cb', function(name, id, ...)
    local src = source
    if type(name) ~= 'string' or type(id) ~= 'number' or #name > 64 then return end
    local res
    local h = handlers[name]
    if not h then
        res = { ok = false, err = 'Nieznana operacja: ' .. name }
    elseif not allowCall(src) then
        res = { ok = false, err = 'Zbyt wiele zapytań – spróbuj za chwilę' }
    else
        local ok, r = xpcall(h, traceback, src, ...)
        if not ok then
            DPM.Error(('błąd w callbacku %s (gracz %s): %s'):format(name, src, tostring(r)))
            res = { ok = false, err = 'Błąd serwera – spróbuj ponownie' }
        elseif r == nil then
            DPM.Debug(('callback %s nie zwrócił wyniku'):format(name))
            res = { ok = false, err = 'Brak wyniku operacji' }
        else
            res = r
        end
    end
    if GetPlayerName(src) then
        TriggerClientEvent('dp-mechanic:cbr', src, id, res)
    end
end)

-- --------------------------------------------------------------------------
--  Odmowa z powodem (DPM.Can zapamiętuje powód dla bieżącego wątku)
-- --------------------------------------------------------------------------
local denyReason = setmetatable({}, { __mode = 'k' })   -- [coroutine] = komunikat

local function setReason(msg)
    local co = coroutine.running()
    if co then denyReason[co] = msg end
end

function DPM.Deny(msg)
    local co = coroutine.running()
    if co then
        if not msg then msg = denyReason[co] end
        denyReason[co] = nil
    end
    return { ok = false, err = msg or 'Brak uprawnień' }
end

-- --------------------------------------------------------------------------
--  Gracze
-- --------------------------------------------------------------------------
-- identyfikator postaci – nil, dopóki framework nie wczyta gracza
function DPM.Identifier(src)
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return nil end
    if Bridge.name ~= 'standalone' then
        local ok, p = pcall(Bridge.GetPlayer, src)
        if not ok or not p then return nil end
    end
    local ok, id = pcall(Bridge.GetIdentifier, src)
    if not ok or type(id) ~= 'string' or id == '' then return nil end
    return id
end

function DPM.Name(src)
    local ok, n = pcall(Bridge.GetName, src)
    n = ok and DPM.Text(n, 64) or ''
    if n == '' then n = DPM.Text(GetPlayerName(src), 64) end
    if n == '' then n = 'Gracz ' .. tostring(src) end
    return n
end

function DPM.Notify(src, msg, kind, time)
    if src and GetPlayerName(src) then Bridge.Notify(src, msg, kind, time) end
end

function DPM.Coords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    return GetEntityCoords(ped)
end

-- dystans gracza od punktu (vec3 / vec4 / tabela x,y,z); brak gracza → math.huge
function DPM.Dist(src, coords)
    local c = DPM.Coords(src)
    if not c or not coords then return math.huge end
    return #(c - vec3(coords.x, coords.y, coords.z))
end

-- gracze w promieniu (bez src, ten sam routing bucket) – posortowani po dystansie
function DPM.NearPlayers(src, radius)
    local out = {}
    src = tonumber(src)
    local c = src and DPM.Coords(src)
    if not c then return out end
    radius = tonumber(radius) or 5.0
    local bucket = GetPlayerRoutingBucket(src)
    for _, s in ipairs(GetPlayers()) do
        local t = tonumber(s)
        if t and t ~= src and GetPlayerRoutingBucket(t) == bucket then
            local tc = DPM.Coords(t)
            if tc then
                local d = #(tc - c)
                if d <= radius then
                    out[#out + 1] = { src = t, name = DPM.Name(t), dist = Utils.Round(d, 1) }
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.dist < b.dist end)
    return out
end

-- encja pojazdu z netId (nil gdy nie istnieje / to nie pojazd)
function DPM.VehicleFromNet(netId)
    netId = tonumber(netId)
    if not netId or netId <= 0 then return nil end
    local ent = NetworkGetEntityFromNetworkId(math.floor(netId))
    if not ent or ent == 0 or not DoesEntityExist(ent) then return nil end
    if GetEntityType(ent) ~= 2 then return nil end
    return ent
end

function DPM.IsNear(src, entity, radius)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    if GetEntityRoutingBucket(entity) ~= GetPlayerRoutingBucket(src) then return false end
    return DPM.Dist(src, GetEntityCoords(entity)) <= (tonumber(radius) or 5.0)
end

function DPM.IsAdmin(src)
    src = tonumber(src)
    if src == 0 then return true end
    if not src then return false end
    return IsPlayerAceAllowed(tostring(src), Config.AdminAce or 'dpmechanic.admin') == true
end

-- --------------------------------------------------------------------------
--  Członkostwo w warsztacie
--  member = { src, identifier, name, workshop, rankId, rank = {id,level,label,salary,perms}, perms, duty }
-- --------------------------------------------------------------------------
local nonMember = {}      -- [src] = GetGameTimer(), do kiedy ważny wynik „nie jest członkiem”
local NON_MEMBER_TTL = 30000

local function copyList(t)
    local r = {}
    if type(t) == 'table' then for i = 1, #t do r[i] = t[i] end end
    return r
end

function DPM.GetMember(src, refresh)
    src = tonumber(src)
    if not src or src <= 0 then return nil end
    local prev = DPM.Members[src]
    if prev and not refresh then return prev end
    if not refresh and nonMember[src] and GetGameTimer() < nonMember[src] then return nil end
    if not Business or not Business.ready or not GetPlayerName(src) then return prev end

    local identifier = DPM.Identifier(src)
    if not identifier then
        -- postać się (prze)ładowuje – nie zapamiętujemy wyniku negatywnego
        if prev and Business.OnMemberLeave then pcall(Business.OnMemberLeave, src, prev) end
        DPM.Members[src] = nil
        return nil
    end

    local wsId, emp = Business.FindEmployee(identifier)
    if not wsId then wsId, emp = Business.TryImport(src, identifier) end

    local m
    if wsId and emp then
        local rank = Business.RankOf(wsId, emp.rankId) or Business.LowestRank(wsId)
        if rank then
            local name = DPM.Name(src)
            if name ~= emp.name then Business.SetEmployeeName(wsId, identifier, name) end
            local perms = copyList(rank.perms)
            local same = prev ~= nil and prev.identifier == identifier and prev.workshop == wsId
            m = {
                src = src,
                identifier = identifier,
                name = emp.name,
                workshop = wsId,
                rankId = rank.id,
                rank = { id = rank.id, level = rank.level, label = rank.label, salary = rank.salary, perms = perms },
                perms = perms,
                duty = same and prev.duty == true or false,
                dutyAt = same and prev.dutyAt or nil,
            }
        end
    end

    -- zmiana tożsamości / warsztatu / zwolnienie → rozliczenie poprzedniego stanu
    if prev and (not m or prev.identifier ~= m.identifier or prev.workshop ~= m.workshop) and Business.OnMemberLeave then
        local ok, err = pcall(Business.OnMemberLeave, src, prev)
        if not ok then DPM.Error(err) end
    end

    DPM.Members[src] = m
    if m then
        nonMember[src] = nil
        local fresh = not prev or prev.identifier ~= m.identifier or prev.workshop ~= m.workshop
        if Business.OnMemberResolved then Business.OnMemberResolved(src, m, fresh) end
    else
        nonMember[src] = GetGameTimer() + NON_MEMBER_TTL
    end
    return m
end

function DPM.PublicMember(m)
    if not m then return nil end
    local ws = Config.Workshops[m.workshop]
    return {
        identifier = m.identifier,
        name = m.name,
        workshop = m.workshop,
        workshopLabel = ws and ws.label or m.workshop,
        rank = { id = m.rank.id, level = m.rank.level, label = m.rank.label },
        perms = m.perms,
        duty = m.duty == true,
    }
end

function DPM.PushMember(src)
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return end
    TriggerClientEvent('dp-mechanic:member', src, DPM.PublicMember(DPM.Members[src]))
end

-- członek z uprawnieniem (perm nil = dowolny członek); needDuty → wymaga służby (gdy Config.RequireDuty)
function DPM.Can(src, perm, needDuty)
    local m = DPM.GetMember(src)
    if not m then
        if Business and not Business.ready then
            setReason('Warsztaty jeszcze się wczytują – spróbuj za chwilę')
        else
            setReason('Nie jesteś pracownikiem warsztatu')
        end
        return nil
    end
    if perm and not Utils.HasPerm(m.perms, perm) then
        setReason('Brak uprawnień: ' .. DPM.PermLabel(perm))
        return nil
    end
    if needDuty and Config.RequireDuty and not m.duty then
        setReason('Musisz być na służbie')
        return nil
    end
    setReason(nil)
    return m
end

-- członkowie online danego warsztatu
function DPM.MembersOf(wsId)
    local out = {}
    for src, m in pairs(DPM.Members) do
        if m.workshop == wsId then out[src] = m end
    end
    return out
end

-- powiadomienie do członków online (opcjonalnie tylko z uprawnieniem)
function DPM.NotifyWorkshop(wsId, msg, kind, perm)
    for src, m in pairs(DPM.Members) do
        if m.workshop == wsId and (not perm or Utils.HasPerm(m.perms, perm)) then
            Bridge.Notify(src, msg, kind or 'info')
        end
    end
end

-- src gracza online o danym identyfikatorze
function DPM.OnlineSource(identifier)
    if not identifier then return nil end
    for src, m in pairs(DPM.Members) do
        if m.identifier == identifier and GetPlayerName(src) then return src end
    end
    for _, s in ipairs(GetPlayers()) do
        local src = tonumber(s)
        if src and DPM.Identifier(src) == identifier then return src end
    end
    return nil
end

-- odświeżenie członkostwa z opóźnieniem (łączy serie zdarzeń frameworka)
local refreshPending = {}
function DPM.ScheduleRefresh(src, delay)
    src = tonumber(src)
    if not src or src <= 0 or refreshPending[src] then return end
    refreshPending[src] = true
    SetTimeout(delay or 250, function()
        refreshPending[src] = nil
        if not GetPlayerName(src) then return end
        DPM.GetMember(src, true)
        DPM.PushMember(src)
    end)
end

DPM.RegisterCallback('member:get', function(src)
    local m = DPM.GetMember(src, true)
    DPM.PushMember(src)
    return { ok = true, member = DPM.PublicMember(m) }
end)

-- --------------------------------------------------------------------------
--  Zdarzenia frameworków (wczytanie postaci, zmiana pracy, wylogowanie)
-- --------------------------------------------------------------------------
local function memberLeft(src)
    src = tonumber(src)
    if not src then return end
    local m = DPM.Members[src]
    if m and Business and Business.OnMemberLeave then
        local ok, err = pcall(Business.OnMemberLeave, src, m)
        if not ok then DPM.Error(err) end
    end
    DPM.Members[src] = nil
    nonMember[src] = nil
    if m then TriggerEvent('dp-mechanic:memberLeft', src, m) end
end

AddEventHandler('esx:playerLoaded', function(playerId) DPM.ScheduleRefresh(playerId, 500) end)
AddEventHandler('esx:setJob', function(playerId) DPM.ScheduleRefresh(playerId) end)
AddEventHandler('esx:playerDropped', function(playerId)
    memberLeft(playerId)
    DPM.PushMember(playerId)   -- wylogowanie (multichar) – gracz nadal na serwerze
end)

AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    local src = type(player) == 'table' and player.PlayerData and player.PlayerData.source or tonumber(player)
    if src then DPM.ScheduleRefresh(src, 500) end
end)
AddEventHandler('QBCore:Server:OnJobUpdate', function(src) DPM.ScheduleRefresh(src) end)
AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
    memberLeft(src)
    DPM.PushMember(src)
end)

AddEventHandler('playerDropped', function()
    local src = source
    memberLeft(src)
    buckets[src], rlWarned[src], refreshPending[src] = nil, nil, nil
end)

-- --------------------------------------------------------------------------
--  Przedmiot „tablet” (opcjonalny)
-- --------------------------------------------------------------------------
CreateThread(function()
    local item = Config.Tablet and Config.Tablet.item
    if not item then return end
    local ok, err = pcall(Bridge.RegisterUsable, item, function(src)
        TriggerClientEvent('dp-mechanic:tablet:use', src)
    end)
    if not ok then DPM.Error('nie udało się zarejestrować przedmiotu tabletu: ' .. tostring(err)) end
end)

-- --------------------------------------------------------------------------
--  Komendy administracyjne (ace Config.AdminAce lub konsola)
-- --------------------------------------------------------------------------
local function reply(src, msg, kind)
    if src == 0 then
        print('[dp-mechanic] ' .. msg)
    else
        Bridge.Notify(src, msg, kind or 'info', 7000)
    end
end

-- /dpm_setboss [id gracza] [warsztat] – zatrudnia jako najwyższą rangę
RegisterCommand('dpm_setboss', function(src, args)
    if not DPM.IsAdmin(src) then return reply(src, 'Brak uprawnień do tej komendy', 'error') end
    CreateThread(function()
        if not Business or not Business.ready then return reply(src, 'Warsztaty jeszcze się wczytują – spróbuj za chwilę', 'error') end
        local target = tonumber(args[1]) or (src ~= 0 and src or nil)
        if not target or not GetPlayerName(target) then
            return reply(src, 'Użycie: /dpm_setboss [id gracza] [warsztat]', 'error')
        end
        local ids = DPM.WorkshopIds()
        local wsId = args[2] or ids[1]
        local ws = wsId and Business.Get(wsId)
        if not ws then
            return reply(src, ('Nieznany warsztat „%s”. Dostępne: %s'):format(tostring(wsId), table.concat(ids, ', ')), 'error')
        end
        local identifier = DPM.Identifier(target)
        if not identifier then return reply(src, 'Postać gracza nie jest jeszcze wczytana', 'error') end
        local rank = Business.TopRank(wsId)
        if not rank then return reply(src, 'Warsztat nie ma żadnych rang', 'error') end
        local name = DPM.Name(target)
        local emp = Business.SetEmployee(wsId, identifier, name, rank.id)
        if not emp then return reply(src, 'Nie udało się zapisać pracownika', 'error') end
        if ws.cfg.syncJob and ws.cfg.job then pcall(Bridge.SetJob, target, ws.cfg.job, rank.level) end
        DPM.GetMember(target, true)
        DPM.PushMember(target)
        Bridge.Notify(target, ('Zostałeś właścicielem warsztatu %s (%s)'):format(ws.cfg.label or wsId, rank.label), 'success', 7000)
        if src ~= target then reply(src, ('%s [%d] → %s w %s'):format(name, target, rank.label, ws.cfg.label or wsId), 'success') end
        print(('[dp-mechanic] /dpm_setboss: %s (%s) → %s / %s (wykonał: %s)'):format(name, identifier, wsId, rank.label, src == 0 and 'konsola' or GetPlayerName(src)))
    end)
end, false)

-- /dpm_givestock [warsztat] [przedmiot|all] [ilość] – dodaje (lub odejmuje) części w magazynie
RegisterCommand('dpm_givestock', function(src, args)
    if not DPM.IsAdmin(src) then return reply(src, 'Brak uprawnień do tej komendy', 'error') end
    CreateThread(function()
        local ids = DPM.WorkshopIds()
        local wsId, item, qty = args[1], args[2], tonumber(args[3] or '1')
        if not wsId or not Config.Workshops[wsId] then
            return reply(src, ('Użycie: /dpm_givestock [warsztat] [przedmiot|all] [ilość]. Warsztaty: %s'):format(table.concat(ids, ', ')), 'error')
        end
        if not item or (item ~= 'all' and not Catalog.items[item]) then
            return reply(src, ('Nieznany przedmiot „%s” (klucze jak w magazynie, np. wear_oil, tire_sport, rim; „all” = wszystkie)'):format(tostring(item)), 'error')
        end
        if not qty or qty ~= qty or qty == 0 then return reply(src, 'Podaj ilość różną od zera', 'error') end
        qty = math.floor(Utils.Clamp(qty, -100000, 100000))
        if not DB or not DB.Await(15000) then return reply(src, 'Baza danych niedostępna', 'error') end

        local keys = {}
        if item == 'all' then
            for k in pairs(Catalog.items) do keys[#keys + 1] = k end
            table.sort(keys)
        else
            keys[1] = item
        end

        if Orders and type(Orders.AddStock) == 'function' then
            for _, k in ipairs(keys) do Orders.AddStock(wsId, k, qty) end
        else
            -- zapis wsadowy po 100 pozycji
            for i = 1, #keys, 100 do
                local rows, params = {}, {}
                for j = i, math.min(#keys, i + 99) do
                    rows[#rows + 1] = '(?, ?, ?)'
                    params[#params + 1] = wsId
                    params[#params + 1] = keys[j]
                    params[#params + 1] = math.max(0, qty)
                end
                params[#params + 1] = qty
                local ok, err = pcall(MySQL.query.await,
                    'INSERT INTO dpm_stock (workshop, item, qty) VALUES ' .. table.concat(rows, ', ') ..
                    ' ON DUPLICATE KEY UPDATE qty = GREATEST(0, qty + ?)', params)
                if not ok then return reply(src, 'Błąd zapisu magazynu: ' .. tostring(err), 'error') end
            end
        end
        TriggerEvent('dp-mechanic:stockChanged', wsId, item ~= 'all' and item or nil, qty)
        local label = item == 'all' and ('wszystkie pozycje (%d)'):format(#keys) or Catalog.items[item].label
        reply(src, ('Magazyn %s: %s %+d szt.'):format(Config.Workshops[wsId].label or wsId, label, qty), 'success')
    end)
end, false)

-- --------------------------------------------------------------------------
--  Eksporty
-- --------------------------------------------------------------------------
-- czy gracz jest mechanikiem (opcjonalnie: konkretnego warsztatu / na służbie)
exports('IsMechanic', function(src, wsId, onDuty)
    local m = DPM.GetMember(src)
    if not m then return false end
    if wsId and m.workshop ~= wsId then return false end
    if onDuty and not m.duty then return false end
    return true
end)

exports('GetMechanic', function(src)
    return DPM.PublicMember(DPM.GetMember(src))
end)

math.randomseed(os.time())
print(('^2[dp-mechanic]^7 v%s uruchomiono (framework: %s)'):format(DPM.version, Bridge.name))
