-- ==========================================================================
--  dp-mechanic – podnośniki (stan współdzielony)
--  Serwer trzyma docelową wysokość i przypisane auto. Klienci animują wysokość
--  lokalnie (deterministycznie, Config.Lifts.speed) i przestawiają auto;
--  serwer szacuje wysokość tą samą metodą (pole `h` w wysyłanym stanie).
--  Stan: Lifts.state[key] = { ws, idx, type, target, veh = netId|nil, by = src|nil, t }
-- ==========================================================================
Lifts = { state = {} }

local SPEED = (Config.Lifts and tonumber(Config.Lifts.speed)) or 0.22        -- m/s
local DRIVE_ON = (Config.Lifts and tonumber(Config.Lifts.driveOnRadius)) or 2.2
local PANEL_RADIUS = 6.0          -- maks. odległość operatora od panelu
local REPORT_RADIUS = 80.0        -- maks. odległość klienta zgłaszającego opuszczenie
local motion = {}                 -- [key] = { h = wysokość w chwili at, at = GetGameTimer(), seq, ent = encja auta }

for wsId, ws in pairs(Config.Workshops) do
    for idx, l in ipairs(ws.lifts or {}) do
        local key = wsId .. ':' .. idx
        Lifts.state[key] = { ws = wsId, idx = idx, type = l.type or 'ramp', target = 0.0, veh = nil, by = nil, t = os.time() }
        motion[key] = { h = 0.0, at = GetGameTimer(), seq = 0, ent = nil }
    end
end

-- --------------------------------------------------------------------------
--  Pomocnicze
-- --------------------------------------------------------------------------
local function cfgOf(key)
    local st = Lifts.state[key]
    if not st then return nil end
    local ws = Config.Workshops[st.ws]
    return ws and ws.lifts and ws.lifts[st.idx] or nil, st
end

-- szacowana aktualna wysokość (ruch jednostajny od h w stronę target)
local function heightNow(key)
    local st, mo = Lifts.state[key], motion[key]
    if not st or not mo then return 0.0 end
    local step = SPEED * (GetGameTimer() - mo.at) / 1000.0
    local d = st.target - mo.h
    if math.abs(d) <= step then return st.target end
    return mo.h + (d > 0 and step or -step)
end

-- kopia stanu do wysłania (z aktualną szacowaną wysokością)
local function view(key)
    local st = Lifts.state[key]
    if not st then return nil end
    return { ws = st.ws, idx = st.idx, type = st.type, target = st.target, veh = st.veh, by = st.by, t = st.t, h = Utils.Round(heightNow(key), 3) }
end

local function broadcast(key)
    TriggerClientEvent('dp-mechanic:lift:state', -1, key, view(key))
end

-- encja auta przypiętego do podnośnika (nil, gdy zniknęło lub netId przejęła inna encja)
local function boundVehicle(key)
    local st, mo = Lifts.state[key], motion[key]
    if not st or not st.veh then return nil end
    local ent = DPM.VehicleFromNet(st.veh)
    if not ent or (mo.ent and ent ~= mo.ent) then return nil end
    return ent
end

-- odpina auto od podnośnika (statebag dpm_lift = nil); true gdy coś zmieniono
local function release(key)
    local st, mo = Lifts.state[key], motion[key]
    if not st or not st.veh then return false end
    local ent = DPM.VehicleFromNet(st.veh)
    if ent and (not mo.ent or ent == mo.ent) and Entity(ent).state.dpm_lift == key then
        Entity(ent).state:set('dpm_lift', nil, true)
    end
    st.veh = nil
    mo.ent = nil
    st.t = os.time()
    return true
end

function Lifts.Get(key) return Lifts.state[key] end
function Lifts.Height(key) return heightNow(key) end
function Lifts.Release(key)
    if release(key) then broadcast(key) end
end

-- klucz podnośnika, na którym stoi auto (netId) lub nil
function Lifts.VehicleLift(netId)
    netId = tonumber(netId)
    if not netId then return nil end
    for key, st in pairs(Lifts.state) do
        if st.veh == netId and boundVehicle(key) then return key end
    end
    return nil
end

-- --------------------------------------------------------------------------
--  Callbacki
-- --------------------------------------------------------------------------
DPM.RegisterCallback('lift:all', function()
    local list = {}
    for key in pairs(Lifts.state) do list[key] = view(key) end
    return { ok = true, list = list }
end)

DPM.RegisterCallback('lift:set', function(src, key, target, netId)
    if type(key) ~= 'string' then return DPM.Deny('Nieznany podnośnik') end
    local cfg, st = cfgOf(key)
    if not cfg or not st then return DPM.Deny('Nieznany podnośnik') end

    local m = DPM.Can(src, nil, true)
    if not m then return DPM.Deny() end
    if m.workshop ~= st.ws then return DPM.Deny('To nie jest podnośnik Twojego warsztatu') end
    if DPM.Dist(src, cfg.panel or cfg.coords) > PANEL_RADIUS then return DPM.Deny('Jesteś za daleko od panelu podnośnika') end

    target = tonumber(target)
    if not target or target ~= target or target == math.huge or target == -math.huge then
        return DPM.Deny('Nieprawidłowa wysokość')
    end
    local maxH = tonumber(cfg.maxHeight) or 1.8
    target = Utils.Round(Utils.Clamp(target, 0.0, maxH), 2)

    -- przypięte auto zniknęło → zwalniamy miejsce
    if st.veh and not boundVehicle(key) then release(key) end

    local cur = heightNow(key)
    local mo = motion[key]

    -- przypisanie auta przy podnoszeniu z poziomu 0 (auto nie może wjechać na podniesiony podnośnik)
    if target > 0.0 and netId ~= nil and not st.veh and cur <= 0.15 then
        local veh = DPM.VehicleFromNet(netId)
        if not veh then return DPM.Deny('Nie znaleziono auta') end
        local vc = GetEntityCoords(veh)
        local dx, dy = vc.x - cfg.coords.x, vc.y - cfg.coords.y
        if math.sqrt(dx * dx + dy * dy) > DRIVE_ON + 1.0 or math.abs(vc.z - cfg.coords.z) > 3.0 then
            return DPM.Deny('Auto nie stoi na podnośniku')
        end
        if GetPedInVehicleSeat(veh, -1) ~= 0 then return DPM.Deny('Kierowca musi wysiąść z auta') end
        local nid = math.floor(tonumber(netId))
        local other = Entity(veh).state.dpm_lift
        if other and other ~= key then
            local ost = Lifts.state[other]
            if ost and ost.veh == nid and boundVehicle(other) then
                return DPM.Deny('To auto stoi na innym podnośniku')
            end
        end
        st.veh = nid
        mo.ent = veh
        Entity(veh).state:set('dpm_lift', key, true)
    end

    -- nowy ruch od bieżącej (szacowanej) wysokości
    mo.h, mo.at, mo.seq = cur, GetGameTimer(), mo.seq + 1
    st.target, st.by, st.t = target, src, os.time()

    -- zabezpieczenie: gdy nikt nie zgłosi opuszczenia, odpinamy auto po czasie zjazdu
    if target <= 0.0 and st.veh then
        local seq = mo.seq
        local ms = math.floor(cur / SPEED * 1000.0) + 4000
        SetTimeout(ms, function()
            local s = Lifts.state[key]
            if motion[key].seq == seq and s.target <= 0.0 and s.veh then
                if release(key) then broadcast(key) end
            end
        end)
    end

    broadcast(key)
    return { ok = true, state = view(key) }
end)

-- klient: podnośnik zjechał do 0 → auto odpięte
RegisterNetEvent('dp-mechanic:lift:lowered', function(key)
    local src = source
    if type(key) ~= 'string' then return end
    local cfg, st = cfgOf(key)
    if not cfg or not st or st.target > 0.0 or not st.veh then return end
    if DPM.Dist(src, cfg.coords) > REPORT_RADIUS then return end
    -- klient widzi podnośnik na dole – wyrównujemy szacunek serwera
    local mo = motion[key]
    mo.h, mo.at = 0.0, GetGameTimer()
    if release(key) then broadcast(key) end
end)

-- --------------------------------------------------------------------------
--  Nadzór: auta usunięte ze świata, wyjście operatora, restart zasobu
-- --------------------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(5000)
        for key, st in pairs(Lifts.state) do
            if st.veh and not boundVehicle(key) then
                st.veh = nil
                motion[key].ent = nil
                st.t = os.time()
                broadcast(key)
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    for _, st in pairs(Lifts.state) do
        if st.by == src then st.by = nil end
    end
end)

-- po restarcie zasobu auta mogły zostać z nieaktualnym statebagiem
CreateThread(function()
    Wait(1000)
    local n = 0
    for _, veh in ipairs(GetAllVehicles()) do
        if DoesEntityExist(veh) and Entity(veh).state.dpm_lift ~= nil then
            Entity(veh).state:set('dpm_lift', nil, true)
            n = n + 1
        end
    end
    if n > 0 then DPM.Debug(('wyczyszczono dpm_lift na %d autach'):format(n)) end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for key in pairs(Lifts.state) do release(key) end
end)
