-- ==========================================================================
--  dp-mechanic – serwer: dane techniczne pojazdów (po tablicy rejestracyjnej)
--  Przebieg, zużycie części, opony, geometria, części osiągowe, swapy, nitro,
--  przeglądy. Serwer jest źródłem prawdy: zużycie liczy sam z raportów kierowcy
--  (anty-cheat: tylko kierowca, limit km zależny od czasu, limit obciążeń,
--  limit częstotliwości). Stan trafia do klientów przez statebagi encji.
-- ==========================================================================
Vehicles = {
    cache = {},   -- [plate] = { data, model, dirty, persisted, ents = { [netId] = true }, touched }
}

local cache = Vehicles.cache
local loading = {}       -- [plate] = promise – trwa odczyt z bazy
local lastSync = {}      -- [src] = GetGameTimer() ostatniego przyjętego raportu
local drivers = {}       -- [src] = { net, t } – ostatnio potwierdzony kierowca (raport przy wysiadaniu)
local nosActive = {}     -- [netId] = { src, ent } – auta z aktywnym dpm_nos
local hwActive = {}      -- [netId] = { src, ent } – auta z ukrytymi kołami
local buckets = {}       -- limity zdarzeń: [src] = { [nazwa] = { t, n } }

local STRESS = { 'eng', 'brk', 'tyr', 'clu', 'sus' }
local TOUCH_RADIUS = 30.0
local HIDE_RADIUS = 10.0
local DATA_RADIUS = 30.0
local SAVE_EVERY = 60000     -- ms – zapis zmienionych danych
local EVICT_AFTER = 1800     -- s – usuwanie z pamięci nieużywanych wpisów
local SAVE_SQL = 'INSERT INTO dpm_vehicles (plate, model, data, updated_at) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE model = ?, data = ?, updated_at = ?'

-- --------------------------------------------------------------------------
--  Narzędzia
-- --------------------------------------------------------------------------
local function now() return os.time() end

local function dbWait()
    if DB and DB.Await then DB.Await() end
end

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

-- poprawny UTF-8 (ucięty znak na końcu → usunięty)
local function utf8Fix(s)
    if utf8.len(s) then return s end
    for _ = 1, 3 do
        s = s:sub(1, -2)
        if utf8.len(s) then return s end
    end
    return (s:gsub('[\128-\255]', ''))
end

-- bezpieczny tekst od klienta: bez znaków sterujących i <>, przycięty do max znaków
local function str(s, max)
    local t = type(s)
    if t == 'number' then s = tostring(s) elseif t ~= 'string' then return nil end
    s = s:gsub('[%c<>]', ' '):gsub('%s+', ' ')
    s = utf8Fix(Utils.Trim(s))
    if s == '' then return nil end
    max = max or 64
    if utf8.len(s) > max then s = Utils.Trim(s:sub(1, utf8.offset(s, max + 1) - 1)) end
    return s
end

local function normPlate(p)
    if type(p) ~= 'string' and type(p) ~= 'number' then return nil end
    p = Utils.Plate(tostring(p))
    if p == '' or #p > 16 then return nil end
    return p
end
Vehicles.NormPlate = normPlate

local function entFromNet(netId)
    netId = tonumber(netId)
    if not netId or netId <= 0 or netId ~= math.floor(netId) then return nil end
    local ent = DPM.VehicleFromNet(netId)
    if not ent or ent == 0 or not DoesEntityExist(ent) or GetEntityType(ent) ~= 2 then return nil end
    return ent
end
Vehicles.Entity = entFromNet

local function plateOf(ent)
    return normPlate(GetVehicleNumberPlateText(ent))
end

-- limit zdarzeń: max wywołań w oknie (ms)
local function allow(src, name, max, window)
    local b = buckets[src]
    if not b then b = {} buckets[src] = b end
    local t = GetGameTimer()
    local e = b[name]
    if not e or t - e.t >= window then
        e = { t = t, n = 0 }
        b[name] = e
    end
    e.n = e.n + 1
    return e.n <= max
end

local function isDriver(src, ent)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and GetPedInVehicleSeat(ent, -1) == ped
end

local function markDriver(src, ent)
    drivers[src] = { net = NetworkGetNetworkIdFromEntity(ent), t = GetGameTimer() }
end

-- raport od kierowcy – także tuż po wysiadaniu (fotel kierowcy wolny, gracz był ostatnim kierowcą)
local function canReport(src, ent)
    if isDriver(src, ent) then
        markDriver(src, ent)
        return true
    end
    local ped = GetPlayerPed(src)
    if ped == 0 then return false end
    local seat = GetPedInVehicleSeat(ent, -1)
    if seat ~= 0 and seat ~= ped then return false end
    if not DPM.IsNear(src, ent, 15.0) then return false end
    local d = drivers[src]
    if d and d.net == NetworkGetNetworkIdFromEntity(ent) and GetGameTimer() - d.t < 120000 then return true end
    return GetVehiclePedIsIn(ped, true) == ent
end

local function wsOf(src)
    local m = DPM.GetMember(src)
    return m and m.workshop or ''
end

-- --------------------------------------------------------------------------
--  Tworzenie danych dla auta bez historii (przebieg – SPEC 8)
-- --------------------------------------------------------------------------
local function freshData(plate)
    local m = Config.Mileage or {}
    local t = now()
    local days = tonumber(Config.Wear.inspectionDays) or 30
    if m.enabled == false then return Utils.NewVehicleData() end

    local owner
    if Bridge.GetVehicleOwner then
        local ok, res = pcall(Bridge.GetVehicleOwner, plate)
        if ok and res and res ~= '' then owner = res end
    end

    if owner then
        -- auto gracza: nowe z salonu, ważne badanie techniczne
        local d = Utils.NewVehicleData()
        d.km = math.max(0.0, tonumber(m.ownedStart) or 0.0)
        d.svc = { km = d.km, at = t, insp = t + days * 86400 }
        return d
    end

    -- auto bez właściciela: „używane” z losowym przebiegiem i zgodnym z nim zużyciem
    local r = m.randomStart or {}
    local lo = math.floor(tonumber(r.min) or 15000)
    local hi = math.floor(tonumber(r.max) or 240000)
    if hi < lo then lo, hi = hi, lo end
    local d = Utils.UsedVehicleData(math.random(lo, hi) + math.random())
    -- badanie: zwykle ważne (losowo 1..days dni), czasem przeterminowane
    if math.random() < 0.7 then
        d.svc.insp = t + math.random(1, math.max(1, days)) * 86400
    else
        d.svc.insp = t - math.random(1, 120) * 86400
    end
    d.svc.at = t - math.random(10, 400) * 86400
    return d
end

-- --------------------------------------------------------------------------
--  Cache / baza
-- --------------------------------------------------------------------------
local function load(plate, model)
    if loading[plate] then return Citizen.Await(loading[plate]) end
    local p = promise.new()
    loading[plate] = p
    local ok, entry = pcall(function()
        dbWait()
        local row = MySQL.single.await('SELECT model, data FROM dpm_vehicles WHERE plate = ?', { plate })
        local data
        if row and type(row.data) == 'string' then
            local okj, dec = pcall(json.decode, row.data)
            if okj and type(dec) == 'table' then data = dec end
        end
        local fresh = data == nil
        if fresh then data = freshData(plate) end
        data = Utils.FixVehicleData(data)
        data.plate = plate
        local mdl = row and row.model
        if (not mdl or mdl == '' or mdl == '0') and model then mdl = tostring(model) end
        return {
            data = data, model = mdl, persisted = row ~= nil,
            dirty = fresh,  -- nowe dane zapisujemy, żeby „historia” auta się nie zmieniała
            ents = {}, touched = now(),
        }
    end)
    if not ok then
        print(('^1[dp-mechanic] Vehicles: błąd odczytu %s: %s^7'):format(plate, tostring(entry)))
        entry = nil
    end
    if cache[plate] then
        entry = cache[plate]          -- ktoś ustawił dane w międzyczasie (np. eksport)
    elseif entry then
        cache[plate] = entry
    end
    loading[plate] = nil
    p:resolve(entry)
    return entry
end

-- dane auta (ładuje z bazy albo tworzy); UWAGA: może czekać na bazę
function Vehicles.Get(plate, model)
    plate = normPlate(plate)
    if not plate then return nil end
    local e = cache[plate] or load(plate, model)
    if not e then return nil end
    e.touched = now()
    if model and (not e.model or e.model == '' or e.model == '0') then
        e.model = tostring(model)
        if e.persisted then e.dirty = true end
    end
    return e.data
end

function Vehicles.Model(plate)
    plate = normPlate(plate)
    local e = plate and cache[plate]
    return e and e.model or nil
end

function Vehicles.Label(plate)
    plate = normPlate(plate)
    local e = plate and cache[plate]
    return e and e.data.vlabel or nil
end

-- nazwa auta (serwer nie zna nazw modeli – podaje ją klient przy okazji)
function Vehicles.SetLabel(plate, label)
    plate = normPlate(plate)
    label = str(label, 64)
    local e = plate and cache[plate]
    if not e or not label or e.data.vlabel == label then return end
    e.data.vlabel = label
    e.dirty = true
end

-- --------------------------------------------------------------------------
--  Statebagi
-- --------------------------------------------------------------------------
local function soundOf(data)
    local eng = Config.Engines[(data.swap and data.swap.engine) or 'stock']
    return eng and eng.sound or nil
end

local function popsOf(data)
    for id, lvl in pairs(data.perf or {}) do
        local p = Config.PerfParts[id]
        local l = p and p.levels[tonumber(lvl) or 0]
        if l and l.pops then return true end
    end
    return false
end

local function applyState(ent, data)
    local st = Entity(ent).state
    st:set('dpm', data, true)
    local snd = soundOf(data)
    if st.dpm_snd ~= snd then st:set('dpm_snd', snd, true) end
    local pops = popsOf(data)
    if st.dpm_pops ~= pops then st:set('dpm_pops', pops, true) end
end

-- rozesłanie danych do wszystkich znanych encji z tą tablicą
function Vehicles.Push(plate)
    plate = normPlate(plate)
    local e = plate and cache[plate]
    if not e then return end
    for netId in pairs(e.ents) do
        local ent = NetworkGetEntityFromNetworkId(netId)
        if ent ~= 0 and DoesEntityExist(ent) and plateOf(ent) == plate then
            applyState(ent, e.data)
        else
            e.ents[netId] = nil
        end
    end
end

-- rejestruje encję przy tablicy (bez wysyłania) → plate, data, czy była znana
local function attach(ent)
    local plate = plateOf(ent)
    if not plate then return nil end
    local data = Vehicles.Get(plate, GetEntityModel(ent))
    if not data then return nil end
    if not DoesEntityExist(ent) then return plate, data, true end
    local e = cache[plate]
    local netId = NetworkGetNetworkIdFromEntity(ent)
    local known = e.ents[netId] == true
    e.ents[netId] = true
    return plate, data, known
end

-- powiązanie auta z danymi + statebagi dpm / dpm_snd / dpm_pops
function Vehicles.Bind(netId, ent)
    ent = ent or entFromNet(netId)
    if not ent then return nil end
    local plate, data = attach(ent)
    if not plate then return nil end
    if DoesEntityExist(ent) then applyState(ent, data) end
    return plate, data
end

-- zmiana danych: fn(data) NIE może czekać (Wait); zwrot false = brak zmian
function Vehicles.Update(plate, fn)
    plate = normPlate(plate)
    local data = plate and Vehicles.Get(plate)
    if not data then return nil end
    local ok, res = pcall(fn, data)
    if not ok then
        print(('^1[dp-mechanic] Vehicles.Update %s: %s^7'):format(plate, tostring(res)))
        return nil
    end
    if res == false then return data end
    Utils.FixVehicleData(data)
    data.plate = plate
    local e = cache[plate]
    if e then
        e.dirty = true
        e.touched = now()
    end
    Vehicles.Push(plate)
    return data
end

-- wpis w książce serwisowej (km = przebieg w chwili czynności)
function Vehicles.AddHistory(plate, ws, kind, label, km, mechanic)
    plate = normPlate(plate)
    if not plate then return end
    if km == nil then
        local e = cache[plate]
        km = e and e.data.km or 0
    end
    MySQL.insert('INSERT INTO dpm_history (plate, workshop, kind, label, km, mechanic, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)', {
        plate, tostring(ws or ''), str(kind, 16) or 'info', str(label, 160) or '-',
        math.floor(tonumber(km) or 0), str(mechanic, 64) or '', now(),
    })
end

-- zapis zmienionych danych; stopping = bez czekania (onResourceStop)
function Vehicles.Flush(stopping)
    local list = {}
    for plate, e in pairs(cache) do
        if e.dirty then list[#list + 1] = plate end
    end
    local saved = 0
    for _, plate in ipairs(list) do
        local e = cache[plate]
        if e and e.dirty then
            local okj, js = pcall(json.encode, e.data)
            if okj and type(js) == 'string' then
                local t, model = now(), tostring(e.model or '')
                local params = { plate, model, js, t, model, js, t }
                e.dirty = false
                if stopping then
                    MySQL.update(SAVE_SQL, params)
                    saved = saved + 1
                else
                    local ok = pcall(MySQL.update.await, SAVE_SQL, params)
                    if ok then
                        e.persisted = true
                        saved = saved + 1
                    else
                        e.dirty = true
                    end
                end
            end
        end
    end
    return saved
end

local function evict()
    local t = now()
    for plate, e in pairs(cache) do
        if not e.dirty and not loading[plate] and t - (e.touched or 0) > EVICT_AFTER then
            local alive = false
            for netId in pairs(e.ents) do
                local ent = NetworkGetEntityFromNetworkId(netId)
                if ent ~= 0 and DoesEntityExist(ent) and plateOf(ent) == plate then
                    alive = true
                else
                    e.ents[netId] = nil
                end
            end
            if not alive then cache[plate] = nil end
        end
    end
end

-- --------------------------------------------------------------------------
--  Zużycie (autorytatywnie po stronie serwera)
-- --------------------------------------------------------------------------
local function engineWearMult(d)
    local m = 1.0
    for id, lvl in pairs(d.perf or {}) do
        local p = Config.PerfParts[id]
        local w = p and p.wearMult and p.wearMult[tonumber(lvl) or 0]
        if w then m = m * w end
    end
    return m
end

local function applyWear(d, km, stress, imp, nos, slip)
    d.km = Utils.Round((tonumber(d.km) or 0.0) + km, 4)
    local W = Config.Wear

    if km > 0 and W.enabled ~= false then
        -- części: ubytek% = km / lifeKm * 100 * kmMultiplier * stres grupy (* wearMult dla 'eng')
        local mult = tonumber(W.kmMultiplier) or 1.0
        local engMult = engineWearMult(d)
        for id, p in pairs(W.parts) do
            local life = tonumber(p.lifeKm) or 0
            if life > 0 then
                local s = p.stress and stress[p.stress] or 1.0
                if p.stress == 'eng' then s = s * engMult end
                local cur = tonumber(d.parts[id]) or 100.0
                d.parts[id] = Utils.Round(math.max(0.0, cur - km / life * 100.0 * mult * s), 5)
            end
        end

        -- opony: ubytek mm = km / life * bieżnik * stres tyr * (1 + niewyważenie) * poślizg koła
        local comp = Config.TireCompounds[d.compound] or Config.TireCompounds.street
        local life = math.max(100.0, tonumber(comp and comp.life) or 40000)
        local imb = Config.Imbalance or {}
        for i = 1, 4 do
            local tt = d.tires[i]
            local f = 1.0
            if imb.enabled ~= false then
                f = 1.0 + math.min(1.0, (tonumber(tt.b) or 0) / math.max(1.0, tonumber(imb.gramsForMax) or 60)) * (tonumber(imb.tireWearMult) or 0.5)
            end
            local loss = km / life * Config.TireNewTread * stress.tyr * f * (slip[i] or 1.0)
            tt.t = Utils.Round(math.max(0.0, (tonumber(tt.t) or Config.TireNewTread) - loss), 5)
        end
    end

    -- geometria: znak losowy przy pierwszym rozstrojeniu, potem zachowany
    local A = Config.Alignment
    if imp > 0 and A and A.enabled ~= false then
        local cur = tonumber(d.align) or 0.0
        local sign = cur > 0 and 1 or (cur < 0 and -1 or (math.random() < 0.5 and -1 or 1))
        local maxB = tonumber(A.maxBias) or 0.12
        d.align = Utils.Round(Utils.Clamp(cur + imp * (tonumber(A.perImpact) or 0.025) * sign, -maxB, maxB), 4)
    end

    -- nitro: zużyte jednostki
    if nos > 0 and type(d.nitro) == 'table' then
        d.nitro.level = Utils.Round(math.max(0.0, (tonumber(d.nitro.level) or 0) - nos), 2)
    end
end

-- --------------------------------------------------------------------------
--  Zdarzenia klientów
-- --------------------------------------------------------------------------
-- gracz w pobliżu prosi o dane auta (statebag 'dpm'); opcjonalnie podaje nazwę auta
RegisterNetEvent('dp-mechanic:veh:touch', function(netId, vlabel)
    local src = source
    if not allow(src, 'touch', 12, 5000) then return end
    local ent = entFromNet(netId)
    if not ent or not DPM.IsNear(src, ent, TOUCH_RADIUS) then return end
    local plate = Vehicles.Bind(netId, ent)
    if plate and vlabel then Vehicles.SetLabel(plate, vlabel) end
    if isDriver(src, ent) then markDriver(src, ent) end
end)

-- raport kierowcy: przebieg, obciążenia, uderzenia, zużyte N2O, poślizg kół
RegisterNetEvent('dp-mechanic:veh:sync', function(netId, payload)
    local src = source
    if type(payload) ~= 'table' or not allow(src, 'sync', 6, 10000) then return end
    local ent = entFromNet(netId)
    if not ent or not canReport(src, ent) then return end

    local t = GetGameTimer()
    local interval = math.max(5.0, tonumber(Config.Wear.syncInterval) or 30.0)
    local last = lastSync[src]
    if last and t - last < 1500 then return end
    local elapsed = last and (t - last) / 1000.0 or interval
    lastSync[src] = t

    -- limit km proporcjonalny do czasu od poprzedniego raportu (z zapasem 20%)
    local maxKm = (tonumber(Config.Wear.maxKmPerSync) or 3.5) * math.min(1.0, elapsed * 1.2 / interval)
    local km = num(payload.km, 0.0, maxKm, 0.0)
    local sMax = math.max(1.0, tonumber(Config.Wear.stressMax) or 3.0)
    local stIn = type(payload.st) == 'table' and payload.st or {}
    local stress = {}
    for _, g in ipairs(STRESS) do stress[g] = num(stIn[g], 1.0, sMax, 1.0) end
    local imp = int(payload.imp, 0, 20, 0)
    local nos = num(payload.nos, 0.0, 2000.0, 0.0)
    local slip = {}
    if type(payload.wheels) == 'table' then
        for i = 1, 4 do slip[i] = num(payload.wheels[i], 1.0, 3.0, 1.0) end
    end

    local plate, _, known = attach(ent)
    if not plate then return end
    if km <= 0 and imp == 0 and nos <= 0 then
        if not known and DoesEntityExist(ent) then applyState(ent, cache[plate].data) end
        return
    end
    Vehicles.Update(plate, function(d) applyWear(d, km, stress, imp, nos, slip) end)
end)

-- stan N2O dla efektów u innych graczy (0 brak, 1 podawanie, 2 purge)
RegisterNetEvent('dp-mechanic:veh:nos', function(netId, state)
    local src = source
    if not allow(src, 'nos', 20, 2000) then return end
    local ent = entFromNet(netId)
    if not ent then return end
    state = int(state, 0, 2, 0)
    local nid = NetworkGetNetworkIdFromEntity(ent)
    local driver = isDriver(src, ent)
    if state > 0 and not driver then return end
    if state == 0 and not driver and not (nosActive[nid] and nosActive[nid].src == src) then return end

    if state > 0 then
        local plate = plateOf(ent)
        local e = plate and cache[plate]
        local nitro = e and e.data.nitro
        if Config.Nitro.enabled == false or type(nitro) ~= 'table' then
            state = 0
        elseif state == 1 and (tonumber(nitro.level) or 0) <= 0 then
            state = 0
        elseif state == 2 then
            local kit = Config.Nitro.kits[nitro.kit]
            if not (kit and kit.purge) then state = 0 end
        end
    end

    local st = Entity(ent).state
    if st.dpm_nos ~= state then st:set('dpm_nos', state, true) end
    if state > 0 then
        nosActive[nid] = { src = src, ent = ent }
    else
        nosActive[nid] = nil
    end
end)

-- ukrycie kół zdjętych do wymiany (maska bitowa 0..15)
RegisterNetEvent('dp-mechanic:veh:hideWheel', function(netId, mask)
    local src = source
    if not allow(src, 'hw', 20, 5000) then return end
    if not DPM.GetMember(src) then return end
    local ent = entFromNet(netId)
    if not ent or not DPM.IsNear(src, ent, HIDE_RADIUS) then return end
    mask = int(mask, 0, 15, 0)
    local st = Entity(ent).state
    if (st.dpm_hw or 0) ~= mask then st:set('dpm_hw', mask, true) end
    local nid = NetworkGetNetworkIdFromEntity(ent)
    if mask ~= 0 then
        hwActive[nid] = { src = src, ent = ent }
    else
        hwActive[nid] = nil
    end
end)

-- --------------------------------------------------------------------------
--  Callbacki
-- --------------------------------------------------------------------------
local function reg(name, fn)
    DPM.RegisterCallback(name, function(src, ...)
        dbWait()
        return fn(src, ...)
    end)
end

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

local function wsLabel(id)
    local ws = Config.Workshops[id or '']
    return ws and ws.label or nil
end

local function historyRow(r)
    return {
        kind = r.kind, label = r.label, km = tonumber(r.km) or 0, mechanic = r.mechanic,
        workshop = r.workshop, workshopLabel = wsLabel(r.workshop), createdAt = tonumber(r.created_at) or 0,
    }
end

local function dynoResult(r)
    local res
    if type(r.result) == 'string' then
        local ok, dec = pcall(json.decode, r.result)
        if ok and type(dec) == 'table' then res = dec end
    end
    return res or {}
end

reg('veh:data', function(src, netId)
    local m, err = need(src)
    if not m then return DPM.Deny(err) end
    local ent = entFromNet(netId)
    if not ent then return DPM.Deny('Nie znaleziono pojazdu') end
    if not DPM.IsNear(src, ent, DATA_RADIUS) then return DPM.Deny('Pojazd jest za daleko') end
    local plate, data = Vehicles.Bind(netId, ent)
    if not plate then return DPM.Deny('Nie udało się odczytać danych pojazdu') end

    local hist = MySQL.query.await('SELECT kind, label, km, mechanic, workshop, created_at FROM dpm_history WHERE plate = ? ORDER BY id DESC LIMIT 20', { plate }) or {}
    local history = {}
    for i, r in ipairs(hist) do history[i] = historyRow(r) end

    local dy = MySQL.query.await('SELECT id, created_at, result FROM dpm_dyno WHERE plate = ? ORDER BY id DESC LIMIT 5', { plate }) or {}
    local dyno = {}
    for i, r in ipairs(dy) do
        local res = dynoResult(r)
        dyno[i] = {
            id = r.id, createdAt = tonumber(r.created_at) or 0, maxHp = tonumber(res.maxHp) or 0,
            maxWhp = tonumber(res.maxWhp) or 0, maxTq = tonumber(res.maxTq) or 0, km = tonumber(res.km),
        }
    end

    return { ok = true, plate = plate, vlabel = data.vlabel, data = data, history = history, dyno = dyno }
end)

reg('history:get', function(src, plate)
    local m, err = need(src)
    if not m then return DPM.Deny(err) end
    plate = normPlate(plate)
    if not plate then return DPM.Deny('Podaj poprawną tablicę rejestracyjną') end
    local rows = MySQL.query.await('SELECT kind, label, km, mechanic, workshop, created_at FROM dpm_history WHERE plate = ? ORDER BY id DESC LIMIT 100', { plate }) or {}
    local list = {}
    for i, r in ipairs(rows) do list[i] = historyRow(r) end
    local e = cache[plate]
    return { ok = true, plate = plate, list = list, km = e and e.data.km or nil, vlabel = e and e.data.vlabel or nil }
end)

-- oczyszczenie wyniku hamowni przysłanego przez klienta
local function cleanDyno(r)
    if type(r) ~= 'table' or type(r.points) ~= 'table' then return nil end
    local out = {
        maxHp = Utils.Round(num(r.maxHp, 0, 20000, 0), 1),
        maxWhp = Utils.Round(num(r.maxWhp, 0, 20000, 0), 1),
        maxTq = Utils.Round(num(r.maxTq, 0, 50000, 0), 1),
        hpRpm = int(r.hpRpm, 0, 30000, 0),
        tqRpm = int(r.tqRpm, 0, 30000, 0),
        redline = int(r.redline, 0, 30000, nil),
        stockHp = r.stockHp and Utils.Round(num(r.stockHp, 0, 20000, 0), 1) or nil,
        nitro = r.nitro == true or (tonumber(r.nitro) or 0) > 0,
        shot = (tonumber(r.nitro) or 0) > 0 and int(r.nitro, 1, 9, 1) or nil,
        vlabel = str(r.vlabel, 64),
        points = {},
    }
    for i = 1, math.min(#r.points, 80) do
        local p = r.points[i]
        if type(p) == 'table' then
            out.points[#out.points + 1] = {
                rpm = int(p.rpm, 0, 30000, 0),
                hp = Utils.Round(num(p.hp, 0, 20000, 0), 1),
                whp = Utils.Round(num(p.whp, 0, 20000, 0), 1),
                tq = Utils.Round(num(p.tq, 0, 50000, 0), 1),
            }
        end
    end
    if #out.points < 2 or out.maxHp <= 0 then return nil end
    return out
end

reg('dyno:save', function(src, netId, result)
    local m, err = need(src, 'dyno', true)
    if not m then return DPM.Deny(err) end
    if not allow(src, 'dyno', 3, 10000) then return DPM.Deny('Zbyt wiele pomiarów – odczekaj chwilę') end
    local ent = entFromNet(netId)
    if not ent then return DPM.Deny('Nie znaleziono pojazdu') end
    if not DPM.IsNear(src, ent, 15.0) then return DPM.Deny('Pojazd jest za daleko') end
    local ws = Config.Workshops[m.workshop]
    if ws and ws.dyno and ws.dyno.coords then
        local c = ws.dyno.coords
        if #(GetEntityCoords(ent) - vec3(c.x, c.y, c.z)) > (ws.dyno.radius or 3.0) + 3.0 then
            return DPM.Deny('Auto nie stoi na hamowni')
        end
    end
    local res = cleanDyno(result)
    if not res then return DPM.Deny('Nieprawidłowy wynik pomiaru') end

    local plate, data = Vehicles.Bind(netId, ent)
    if not plate then return DPM.Deny('Nie udało się odczytać danych pojazdu') end
    if res.vlabel then Vehicles.SetLabel(plate, res.vlabel) end
    res.km = math.floor(tonumber(data.km) or 0)
    local vlabel = res.vlabel or data.vlabel or ''

    local id = MySQL.insert.await('INSERT INTO dpm_dyno (plate, workshop, model, vlabel, result, mechanic, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)', {
        plate, m.workshop, Vehicles.Model(plate) or tostring(GetEntityModel(ent)), vlabel, json.encode(res), m.name or '', now(),
    })
    if not id then return DPM.Deny('Nie udało się zapisać pomiaru') end

    Vehicles.AddHistory(plate, m.workshop, 'dyno',
        ('Pomiar hamowni: %d KM (%d WHP), %d Nm%s'):format(math.floor(res.maxHp + 0.5), math.floor(res.maxWhp + 0.5), math.floor(res.maxTq + 0.5), res.nitro and ' – z N2O' or ''),
        res.km, m.name)
    return { ok = true, id = id }
end)

reg('dyno:list', function(src, plate)
    local m, err = need(src)
    if not m then return DPM.Deny(err) end
    plate = normPlate(plate)
    if not plate then return DPM.Deny('Podaj poprawną tablicę rejestracyjną') end
    local rows = MySQL.query.await('SELECT id, vlabel, result, mechanic, created_at FROM dpm_dyno WHERE plate = ? ORDER BY id DESC LIMIT 20', { plate }) or {}
    local list = {}
    for i, r in ipairs(rows) do
        local res = dynoResult(r)
        list[i] = {
            id = r.id, createdAt = tonumber(r.created_at) or 0,
            maxHp = tonumber(res.maxHp) or 0, maxWhp = tonumber(res.maxWhp) or 0, maxTq = tonumber(res.maxTq) or 0,
            hpRpm = tonumber(res.hpRpm) or 0, tqRpm = tonumber(res.tqRpm) or 0, points = res.points or {},
            vlabel = (r.vlabel ~= '' and r.vlabel) or res.vlabel, mechanic = r.mechanic, nitro = res.nitro == true,
            km = tonumber(res.km), redline = tonumber(res.redline), stockHp = tonumber(res.stockHp),
        }
    end
    return { ok = true, list = list }
end)

-- --------------------------------------------------------------------------
--  Eksporty dla innych zasobów
-- --------------------------------------------------------------------------
exports('GetVehicleData', function(plate)
    local d = Vehicles.Get(plate)
    return d and Utils.Copy(d) or nil
end)

exports('SetVehicleData', function(plate, data)
    plate = normPlate(plate)
    if not plate or type(data) ~= 'table' then return false end
    local d = Utils.FixVehicleData(Utils.Copy(data))
    d.plate = plate
    local e = cache[plate]
    if not e then
        Vehicles.Get(plate)
        e = cache[plate]
    end
    if not e then return false end
    if d.vlabel == nil then d.vlabel = e.data.vlabel end
    e.data = d
    e.dirty = true
    e.touched = now()
    Vehicles.Push(plate)
    return true
end)

exports('GetVehicleMileage', function(plate)
    local d = Vehicles.Get(plate)
    return d and (tonumber(d.km) or 0.0) or nil
end)

-- --------------------------------------------------------------------------
--  Komenda administracyjna: korekta licznika
-- --------------------------------------------------------------------------
RegisterCommand('dpm_setkm', function(source, args)
    local src = source
    local ace = (Config.Mileage and Config.Mileage.adminAce) or Config.AdminAce or 'dpmechanic.admin'
    local function reply(msg, kind)
        if src == 0 then print('[dp-mechanic] ' .. msg) else Bridge.Notify(src, msg, kind or 'info') end
    end
    if src ~= 0 and not IsPlayerAceAllowed(src, ace) then
        reply('Brak uprawnień do tej komendy', 'error')
        return
    end
    if #args < 2 then
        reply('Użycie: /dpm_setkm [tablica] [km]', 'error')
        return
    end
    local km = tonumber(args[#args])
    local plate = normPlate(table.concat(args, ' ', 1, #args - 1))
    if not plate or not km or km ~= km or km < 0 or km > 9999999 then
        reply('Nieprawidłowa tablica lub przebieg', 'error')
        return
    end
    CreateThread(function()
        dbWait()
        local old
        local d = Vehicles.Update(plate, function(data)
            old = tonumber(data.km) or 0
            data.km = km + 0.0
            if (tonumber(data.svc.km) or 0) > data.km then data.svc.km = data.km end
        end)
        if not d then
            reply('Nie udało się zmienić przebiegu', 'error')
            return
        end
        Vehicles.AddHistory(plate, '', 'admin', ('Korekta licznika: %s → %s'):format(Utils.FormatKm(old or 0), Utils.FormatKm(km)), km, src == 0 and 'Konsola' or Bridge.GetName(src))
        reply(('Przebieg %s ustawiony na %s'):format(plate, Utils.FormatKm(km)), 'success')
    end)
end, false)

-- --------------------------------------------------------------------------
--  Wątki: zapis, czyszczenie pamięci, pilnowanie N2O
-- --------------------------------------------------------------------------
CreateThread(function()
    dbWait()
    -- opcjonalne czyszczenie bardzo starych rekordów (Config.Mileage.purgeDays, domyślnie wyłączone)
    local purge = tonumber(Config.Mileage and Config.Mileage.purgeDays)
    if purge and purge > 0 then
        pcall(MySQL.update.await, 'DELETE FROM dpm_vehicles WHERE updated_at < ?', { now() - math.floor(purge * 86400) })
    end
    -- po restarcie zasobu: podpięcie aut, które mają już statebag, i reset efektów tymczasowych
    Wait(2000)
    for _, veh in ipairs(GetAllVehicles()) do
        if DoesEntityExist(veh) then
            local st = Entity(veh).state
            if (st.dpm_nos or 0) ~= 0 then st:set('dpm_nos', 0, true) end
            if (st.dpm_hw or 0) ~= 0 then st:set('dpm_hw', 0, true) end
            if st.dpm ~= nil then
                pcall(Vehicles.Bind, NetworkGetNetworkIdFromEntity(veh), veh)
                Wait(20)
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(SAVE_EVERY)
        local ok, err = pcall(Vehicles.Flush, false)
        if not ok then print(('^1[dp-mechanic] Vehicles.Flush: %s^7'):format(tostring(err))) end
        evict()
    end
end)

-- dpm_nos wyłączane, gdy kierowca wysiadł / zniknął (efekty nie „wiszą”)
CreateThread(function()
    while true do
        Wait(next(nosActive) and 1000 or 2000)
        for nid, a in pairs(nosActive) do
            local ent = NetworkGetEntityFromNetworkId(nid)
            if ent == 0 or ent ~= a.ent or not DoesEntityExist(ent) then
                nosActive[nid] = nil
            elseif not isDriver(a.src, ent) then
                Entity(ent).state:set('dpm_nos', 0, true)
                nosActive[nid] = nil
            end
        end
    end
end)

local function resetTemp(list, key, src)
    for nid, a in pairs(list) do
        if src == nil or a.src == src then
            local ent = NetworkGetEntityFromNetworkId(nid)
            if ent ~= 0 and ent == a.ent and DoesEntityExist(ent) then Entity(ent).state:set(key, 0, true) end
            list[nid] = nil
        end
    end
end

AddEventHandler('playerDropped', function()
    local src = source
    resetTemp(nosActive, 'dpm_nos', src)
    resetTemp(hwActive, 'dpm_hw', src)   -- mechanik wyszedł w trakcie wymiany – koła wracają
    lastSync[src] = nil
    drivers[src] = nil
    buckets[src] = nil
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    resetTemp(nosActive, 'dpm_nos')
    resetTemp(hwActive, 'dpm_hw')
    Vehicles.Flush(true)
end)
