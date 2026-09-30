-- ==========================================================================
--  DPM.Wear – przebieg, obciążenia i efekty zużycia części (tylko kierowca)
--  - licznik km (płynny, bez skoków przy synchronizacji) + trip per tablica (KVP)
--  - obciążenia grup (eng/brk/tyr/clu/sus), uderzenia, poślizg kół → 'dp-mechanic:veh:sync'
--  - efekty: wypadanie zapłonów, brak rozruchu, zerwany rozrząd, przegrzewanie,
--    zatarcie bez oleju, pisk klocków, bicie tarcz, buksowanie sprzęgła,
--    niewyważenie kół, ściąganie (geometria), pękanie łysych opon
--  - kontrolki na desce (NUI 'dash') i odometr (NUI 'odo')
--  Próbkowanie co 200 ms tylko podczas jazdy; co klatkę tylko geometria/sprzęgło.
-- ==========================================================================
DPM.Wear = {}
local Wear = DPM.Wear
local Drive = DPM.Drive

local CW = Config.Wear or {}
local CP = CW.parts or {}
local CM = Config.Mileage or {}
local CI = Config.Imbalance or {}
local CA = Config.Alignment or {}

local WEAR_ON = CW.enabled ~= false
local MILEAGE_ON = CM.enabled ~= false
local STRESS_MAX = math.max(1.0, CW.stressMax or 3.0)
local SYNC_MS = math.max(5, CW.syncInterval or 30) * 1000
local MAX_KM = CW.maxKmPerSync or 3.5
local SERVICE_KM = CW.serviceInterval or 15000
local BALD_MM = 0.3
local TYRE_IDX = { 0, 1, 4, 5 }                 -- indeksy opon GTA dla kół 1..4
local GAIN = { eng = 2.5, brk = 5.0, tyr = 4.0, clu = 6.0, sus = 5.0 }  -- jak szybko styl jazdy nasyca obciążenie
local STEAM_ASSET, STEAM_FX = 'core', 'ent_sht_steam'

-- ikony kontrolek (nazwy rozumie drive.js)
local ICONS = {
    oil = 'oil', oil_filter = 'filter', air_filter = 'filter', spark_plugs = 'plug', timing_belt = 'belt',
    coolant = 'coolant', battery = 'battery', brake_pads = 'brake', brake_discs = 'brake', brake_fluid = 'brake',
    clutch = 'clutch', gearbox_oil = 'gearbox', shocks = 'shock',
}

local S = nil          -- stan bieżącej jazdy
local nosUsed = 0.0    -- zużyte jednostki N2O od ostatniej synchronizacji
local temps = {}       -- [tablica] = { t = temperatura 0..1, at = GetGameTimer() }
local sessionId = 0

-- --------------------------------------------------------------------------
--  Pomocnicze
-- --------------------------------------------------------------------------
local function round(v, d)
    local m = 10 ^ (d or 0)
    return math.floor(v * m + 0.5) / m
end

local function cond(data, id)
    local v = data and data.parts and data.parts[id]
    if type(v) ~= 'number' then return 100.0 end
    return v
end

-- 0..1 – jak bardzo część jest poniżej progu efektu (nil = brak efektu)
local function severity(c, thr)
    if type(thr) ~= 'number' or thr <= 0 or c >= thr then return nil end
    return Utils.Clamp(1.0 - c / thr, 0.05, 1.0)
end

local function maxSev(a, b)
    if not a then return b end
    if not b then return a end
    return a > b and a or b
end

local function nowUnix()
    local t = GetCloudTimeAsInt and GetCloudTimeAsInt() or 0
    if (not t or t <= 0) and os and os.time then t = os.time() end
    return t or 0
end

local function tripKey(plate) return 'trip:' .. plate end

-- --------------------------------------------------------------------------
--  Efekty wyliczane z danych auta (odświeżane przy każdej zmianie statebaga)
-- --------------------------------------------------------------------------
local function buildFx(data, wheels)
    local fx = { align = 0.0, imbB = 0.0, bald = {}, minTread = Config.TireNewTread or 8.0 }
    if not data then return fx end
    if WEAR_ON then
        -- sterowane configiem: każda część z polem misfire/noStart/… daje efekt
        for id, p in pairs(CP) do
            local c = cond(data, id)
            fx.misfire = maxSev(fx.misfire, severity(c, p.misfire))
            fx.noStart = maxSev(fx.noStart, severity(c, p.noStart))
            fx.coolSev = maxSev(fx.coolSev, severity(c, p.overheat))
            fx.squeal = maxSev(fx.squeal, severity(c, p.squeal))
            fx.judder = maxSev(fx.judder, severity(c, p.judder))
            fx.slip = maxSev(fx.slip, severity(c, p.slip))
            if p.failAtZero and c <= 0.0 then fx.beltBroken = true end
        end
        local oil = CP.oil
        if oil then
            local oc = cond(data, 'oil')
            fx.oilSev = severity(oc, oil.warn or 20)
            fx.oilZero = CW.engineDamageAtZero and oc <= 0.0 or false
        end
    end
    local n = math.max(1, wheels or 4)
    for i = 1, math.min(4, n) do
        local t = data.tires and data.tires[i]
        if type(t) == 'table' then
            local tread = tonumber(t.t) or (Config.TireNewTread or 8.0)
            if tread < fx.minTread then fx.minTread = tread end
            if tread < BALD_MM then fx.bald[#fx.bald + 1] = i end
            local b = tonumber(t.b) or 0
            if b > fx.imbB then fx.imbB = b end
        end
    end
    if CA.enabled ~= false then fx.align = tonumber(data.align) or 0.0 end
    return fx
end

-- stałe kontrolki (z danych) – scalane po ikonie
local function buildStaticWarnings(data, fx)
    local list, byIcon = {}, {}
    local function add(id, icon, label, level)
        local w = byIcon[icon]
        if w then
            if level == 'err' then w.level = 'err' end
            if not w.label:find(label, 1, true) then w.label = w.label .. ' · ' .. label end
            return
        end
        w = { id = id, icon = icon, label = label, level = level }
        byIcon[icon] = w
        list[#list + 1] = w
    end
    if WEAR_ON and data then
        local ids = {}
        for id in pairs(CP) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local p = CP[id]
            local c = cond(data, id)
            local w = p.warn or 15
            if c < w then
                local level = (c <= 0.0 or c < w * 0.5) and 'err' or 'warn'
                local icon = ICONS[id] or p.icon or 'engine'
                add(id, icon, ('%s %d%%'):format(p.label or id, math.floor(c + 0.5)), level)
            end
        end
    end
    local legal = Config.TireLegalTread or 1.6
    if fx.minTread < legal then
        add('tires', 'tire', ('Bieżnik opon %.1f mm'):format(fx.minTread), fx.minTread < 0.8 and 'err' or 'warn')
    end
    local aw = CA.warn or 0.03
    if CA.enabled ~= false and math.abs(fx.align) > aw then
        add('align', 'align', 'Geometria kół – auto ściąga', math.abs(fx.align) > (CA.maxBias or 0.12) * 0.7 and 'err' or 'warn')
    end
    if CI.enabled ~= false and fx.imbB >= (CI.gramsForMax or 60) * 0.35 then
        add('balance', 'balance', ('Niewyważone koła (%d g)'):format(math.floor(fx.imbB + 0.5)), 'warn')
    end
    return list
end

-- --------------------------------------------------------------------------
--  Przebieg
-- --------------------------------------------------------------------------
local function odoKm()
    if not S then return 0.0 end
    local base = (S.data and tonumber(S.data.km)) or 0.0
    local v = base + S.unconf + S.pend
    if v < S.disp then v = S.disp end
    S.disp = v
    return v
end

function Wear.GetMileage(veh)
    veh = veh or GetVehiclePedIsIn(PlayerPedId(), false)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return nil end
    if S and S.veh == veh then return odoKm() end
    local d = Drive.GetData(veh)
    return d and tonumber(d.km) or nil
end

function Wear.GetTrip()
    return S and S.trip or nil
end

function Wear.GetTemp()
    return S and S.temp or nil
end

-- zużyte N2O (z nitro.lua) – wysyłane w najbliższej synchronizacji
function Wear.AddNitroUsed(units)
    units = tonumber(units) or 0
    if units > 0 then nosUsed = nosUsed + units end
end

exports('GetMileage', function(veh) return Wear.GetMileage(veh) end)

local function saveTrip(force)
    if not S or not S.plate or S.plate == '' then return end
    if force or math.abs(S.trip - S.tripSaved) >= 0.05 then
        SetResourceKvpFloat(tripKey(S.plate), S.trip + 0.0)
        S.tripSaved = S.trip
    end
end

local function resetTrip()
    if not MILEAGE_ON then return end
    if not S then
        DPM.Notify('Musisz prowadzić auto, żeby wyzerować licznik dzienny', 'error')
        return
    end
    S.trip, S.tripSaved = 0.0, -1.0
    saveTrip(true)
    S.odoSig = nil
    DPM.Nui('drive:sound', { name = 'tick' })
    DPM.Notify('Licznik dzienny (TRIP) wyzerowany', 'success', 2500)
end

if MILEAGE_ON then
    RegisterCommand('trip', resetTrip, false)
    RegisterCommand('dpm_trip_reset', resetTrip, false)
    RegisterKeyMapping('dpm_trip_reset', 'Licznik dzienny (trip) – zerowanie', 'keyboard', CM.tripKey or 'HOME')
end

-- --------------------------------------------------------------------------
--  Synchronizacja z serwerem
-- --------------------------------------------------------------------------
local function resetAccumulators()
    S.acc = { eng = 0.0, brk = 0.0, tyr = 0.0, clu = 0.0, sus = 0.0 }
    S.accT = 0.0
    S.wslip = { 0.0, 0.0, 0.0, 0.0 }
    S.imp = 0
end

local function computeStress()
    local st = {}
    for g, sum in pairs(S.acc) do
        local mean = S.accT > 0 and (sum / S.accT) or 0.0
        st[g] = round(1.0 + (STRESS_MAX - 1.0) * Utils.Clamp(mean * (GAIN[g] or 3.0), 0.0, 1.0), 2)
    end
    return st
end

local function computeWheels()
    local out = {}
    for i = 1, S.wheels do
        local mean = S.accT > 0 and (S.wslip[i] / S.accT) or 0.0
        out[i] = round(1.0 + 2.0 * Utils.Clamp(mean * GAIN.tyr, 0.0, 1.0), 2)
    end
    return out
end

local function sendSync()
    if not S then return end
    local now = GetGameTimer()
    S.nextSync = now + SYNC_MS
    if not S.netId then S.pend = 0.0 resetAccumulators() return end
    local km = S.pend
    if km < 0.0005 and S.imp == 0 and nosUsed < 0.01 then return end
    local payload = { km = round(km, 4), imp = S.imp, nos = round(nosUsed, 3) }
    if WEAR_ON then
        payload.st = computeStress()
        payload.wheels = computeWheels()
    end
    TriggerServerEvent('dp-mechanic:veh:sync', S.netId, payload)
    S.unconf = S.unconf + km
    S.unconfAt = now
    S.pend = 0.0
    nosUsed = 0.0
    resetAccumulators()
end

-- --------------------------------------------------------------------------
--  Efekty lokalne
-- --------------------------------------------------------------------------
local lastNotify = {}
local function notifyOnce(key, msg, kind, cooldown)
    local now = GetGameTimer()
    if lastNotify[key] and now - lastNotify[key] < (cooldown or 8000) then return end
    lastNotify[key] = now
    DPM.Notify(msg, kind or 'error', 4000)
end

local function stopSteam()
    if S and S.steam then
        StopParticleFxLooped(S.steam, false)
        S.steam = nil
    end
end

local function startSteam(veh)
    if S.steam or not HasNamedPtfxAssetLoaded(STEAM_ASSET) then
        if not HasNamedPtfxAssetLoaded(STEAM_ASSET) then RequestNamedPtfxAsset(STEAM_ASSET) end
        return
    end
    local min, max = GetModelDimensions(GetEntityModel(veh))
    UseParticleFxAssetNextCall(STEAM_ASSET)
    S.steam = StartParticleFxLoopedOnEntity(STEAM_FX, veh, 0.0, max.y - 0.6, min.z + (max.z - min.z) * 0.62, 70.0, 0.0, 0.0, 0.55, false, false, false)
end

-- rozruch: kręcenie rozrusznikiem, które nie kończy się zapłonem
local function crankFail(veh, msg, dur, weak, permanent)
    if S.cranking then return end
    S.cranking = true
    local token = S.token
    SetVehicleEngineOn(veh, false, true, true)
    DPM.Nui('drive:sound', { name = 'crank', dur = dur, weak = weak, fail = true })
    Drive.SetShake('crank', 0.16)
    CreateThread(function()
        local endAt = GetGameTimer() + math.floor(dur * 1000)
        while GetGameTimer() < endAt and S and S.token == token do
            SetVehicleEngineOn(veh, false, true, true)
            Wait(100)
        end
        Drive.SetShake('crank', nil)
        if not S or S.token ~= token then return end
        notifyOnce(msg, msg, 'error', 5000)
        Wait(900)
        if S and S.token == token then
            -- pozwól na kolejną próbę (gaz = nowa próba rozruchu)
            if not permanent and DoesEntityExist(veh) then SetVehicleEngineOn(veh, false, true, false) end
            S.cranking = false
            S.crankCd = GetGameTimer() + 1200
        end
    end)
end

local function onStartAttempt(veh)
    local fx = S.fx
    if fx.beltBroken then
        crankFail(veh, 'Silnik kręci, ale nie zapala – zerwany pasek rozrządu', 1.8, 0.1, true)
        return
    end
    if fx.noStart then
        local chance = 0.25 + 0.65 * fx.noStart
        if math.random() < chance then
            crankFail(veh, 'Silnik nie chce zapalić… (słaby akumulator)', 1.1 + fx.noStart * 0.9, fx.noStart, false)
            return
        end
        -- udany rozruch słabym akumulatorem – ciężkie, krótkie kręcenie
        DPM.Nui('drive:sound', { name = 'crank', dur = 0.45 + fx.noStart * 0.5, weak = fx.noStart, fail = false })
    end
end

local function misfire(veh)
    local dur = math.random(120, 250)
    Drive.SetPowerMod('misfire', 0.1)
    Drive.SetShake('misfire', 0.32)
    DPM.Nui('drive:sound', { name = 'misfire' })
    SetTimeout(dur, function()
        Drive.SetPowerMod('misfire', nil)
        Drive.SetShake('misfire', nil)
    end)
end

-- co klatkę: ściąganie kierownicy i buksowanie sprzęgła
local function wearTick(veh, dt)
    if not S or S.veh ~= veh then return end
    if S.alignOn then SetVehicleSteerBias(veh, S.fx.align + 0.0) end
    local sev = S.fx.slip
    if sev then
        local thr = GetControlNormal(0, 71)
        local rpm = GetVehicleCurrentRpm(veh)
        if thr > 0.8 and rpm > 0.55 and GetVehicleCurrentGear(veh) > 0 and GetIsVehicleEngineRunning(veh) then
            Drive.SetPowerMod('clutch', 1.0 - 0.55 * sev * (0.6 + 0.4 * rpm))
            if rpm < 0.98 then SetVehicleCurrentRpm(veh, math.min(1.0, rpm + dt * 0.9 * sev)) end
        elseif Drive.GetPowerMod('clutch') then
            Drive.SetPowerMod('clutch', nil)
        end
    end
end

-- --------------------------------------------------------------------------
--  Kontrolki / odometr (NUI)
-- --------------------------------------------------------------------------
local function sendDash(force)
    if CW.warnDashboard == false then return end
    local visible = Drive.HudAllowed()
    if not visible then
        if S.dashVisible ~= false then
            S.dashVisible = false
            S.dashSig = nil
            DPM.Nui('dash', { visible = false })
        end
        return
    end
    local list = {}
    for i = 1, #S.warnStatic do list[i] = S.warnStatic[i] end
    local veh = S.veh
    if S.temp >= 0.8 then
        list[#list + 1] = { id = 'overheat', icon = 'temp', label = 'Przegrzanie silnika!', level = 'err' }
    end
    local eh = GetVehicleEngineHealth(veh)
    if eh < 400.0 then
        list[#list + 1] = { id = 'engine', icon = 'engine', label = 'Awaria silnika', level = 'err' }
    elseif eh < 750.0 then
        list[#list + 1] = { id = 'engine', icon = 'engine', label = 'Kontrola silnika', level = 'warn' }
    end
    local km = odoKm()
    local svc = S.data and S.data.svc or {}
    local service = WEAR_ON and (km - (tonumber(svc.km) or 0.0)) > SERVICE_KM or false
    local insp = tonumber(svc.insp) or 0
    local inspection = insp < nowUnix() and not (insp == 0 and km < 1000.0)

    local parts = {}
    for i = 1, #list do parts[i] = list[i].id .. ':' .. list[i].level end
    local temp = round(S.temp, 2)
    local sig = table.concat(parts, ',') .. '|' .. tostring(service) .. tostring(inspection)
    if not force and sig == S.dashSig and temp == S.dashTemp and S.dashVisible then return end
    S.dashSig, S.dashTemp, S.dashVisible = sig, temp, true
    DPM.Nui('dash', { visible = true, warnings = list, temp = temp, service = service, inspection = inspection })
end

local function sendOdo(force)
    if not MILEAGE_ON or CM.hud == false then return end
    local visible = Drive.HudAllowed()
    if not visible then
        if S.odoVisible ~= false then
            S.odoVisible = false
            S.odoSig = nil
            DPM.Nui('odo', { visible = false })
        end
        return
    end
    local km = odoKm()
    if not force and S.odoVisible and S.odoKm and math.abs(km - S.odoKm) < 0.01 and S.odoSig == 'ok' then return end
    S.odoKm, S.odoSig, S.odoVisible = km, 'ok', true
    DPM.Nui('odo', { visible = true, km = round(km, 3), trip = round(S.trip, 3), unit = CM.unit or 'km' })
end

-- --------------------------------------------------------------------------
--  Próbkowanie jazdy (co 200 ms)
-- --------------------------------------------------------------------------
local function sample()
    local veh = S.veh
    if not DoesEntityExist(veh) then return end
    local now = GetGameTimer()
    local dt = (now - S.last) / 1000.0
    S.last = now
    if dt <= 0.0 or dt > 2.0 then dt = 0.2 end

    local ped = PlayerPedId()
    local speed = GetEntitySpeed(veh)
    local kmh = speed * 3.6
    local rpm = GetVehicleCurrentRpm(veh)
    local thr = GetControlNormal(0, 71)
    local brkIn = GetControlNormal(0, 72)
    local forward = GetEntitySpeedVector(veh, true).y
    local braking = brkIn > 0.15 and forward > 0.5
    local running = GetIsVehicleEngineRunning(veh)
    local fx = S.fx

    -- przebieg + trip (bez zamrożonych aut / teleportów)
    if not IsEntityPositionFrozen(veh) and speed > 0.3 and speed < 120.0 then
        local dkm = speed * dt / 1000.0
        S.pend = S.pend + dkm
        S.trip = S.trip + dkm
    end

    -- obciążenia (styl jazdy)
    if WEAR_ON and (speed > 0.5 or (running and thr > 0.1)) then
        S.accT = S.accT + dt
        local acc = S.acc
        if running and rpm > 0.85 then acc.eng = acc.eng + (0.6 + 0.4 * thr) * dt end
        if braking and kmh > 60.0 then acc.brk = acc.brk + brkIn * Utils.Clamp(kmh / 120.0, 0.5, 1.5) * dt end
        if kmh < 20.0 and thr > 0.6 and rpm > 0.7 then acc.clu = acc.clu + dt end
        local vz = GetEntityVelocity(veh).z
        local dvz = math.abs(vz - S.vz)
        S.vz = vz
        if dvz > 1.5 then acc.sus = acc.sus + Utils.Clamp((dvz - 1.5) / 4.0, 0.0, 1.0) * dt end
        -- poślizg kół: prędkość obwodowa koła vs prędkość auta
        local burnout = IsVehicleInBurnout(veh)
        local tyrSum = 0.0
        for i = 1, S.wheels do
            local ws = math.abs(GetVehicleWheelSpeed(veh, i - 1))
            local slip = math.abs(ws - speed) / math.max(speed, 2.0)
            if slip < 0.15 then slip = 0.0 end
            if burnout and slip < 1.0 then slip = 1.0 end
            if slip > 2.0 then slip = 2.0 end
            S.wslip[i] = S.wslip[i] + slip * dt
            tyrSum = tyrSum + slip
        end
        acc.tyr = acc.tyr + (tyrSum / S.wheels) * dt
    end

    -- uderzenia (nagłe wytracenie prędkości + kolizja)
    local decel = (S.prevSpeed - speed) / dt
    local body = GetVehicleBodyHealth(veh)
    if decel > (CA.impactThreshold or 22.0) and now > S.impCd
        and (HasEntityCollidedWithAnything(veh) or (S.prevBody - body) > 2.0) then
        S.imp = S.imp + 1
        S.impCd = now + 1000
    end
    S.prevSpeed, S.prevBody = speed, body

    -- rozruch (akumulator / rozrząd)
    if WEAR_ON and not S.cranking then
        local starting = IsVehicleEngineStarting(veh)
        if (starting or (running and not S.wasRunning)) and not S.attemptHandled then
            S.attemptHandled = true
            onStartAttempt(veh)
        elseif not starting and not running then
            S.attemptHandled = false
        end
        if fx.beltBroken then
            if running then SetVehicleEngineOn(veh, false, true, true) end
            if thr > 0.5 and not running and now > (S.crankCd or 0) then
                S.crankCd = now + 2500
                crankFail(veh, 'Silnik kręci, ale nie zapala – zerwany pasek rozrządu', 1.6, 0.1, true)
            end
        end
    end
    S.wasRunning = GetIsVehicleEngineRunning(veh)
    running = S.wasRunning

    if WEAR_ON then
        -- temperatura silnika
        local sev = math.max(fx.coolSev or 0.0, (fx.oilSev or 0.0) * 0.6)
        local target, rate
        if running then
            local load = Utils.Clamp(rpm, 0.0, 1.0) * (0.45 + 0.55 * thr)
            target = 0.45
            if load > 0.5 then target = target + (load - 0.5) / 0.5 * (0.05 + sev * 0.75) end
            target = target - math.min(kmh / 450.0, 0.07) * (1.0 - sev * 0.6)
            if sev > 0 and kmh < 8.0 and rpm < 0.35 then target = target + sev * 0.12 end
            if GetVehicleEngineHealth(veh) < 300.0 then target = target + 0.12 end
            if target < 0.42 then target = 0.42 end
            rate = target > S.temp and (0.012 + sev * 0.03) or 0.02
        else
            target, rate = 0.08, 0.004
        end
        if S.temp < target then S.temp = math.min(target, S.temp + rate * dt)
        else S.temp = math.max(target, S.temp - rate * dt) end
        if S.temp > 1.05 then S.temp = 1.05 end

        local eh = GetVehicleEngineHealth(veh)
        local newEh = eh
        if S.temp > 0.85 and running then
            newEh = newEh - (2.0 + (S.temp - 0.85) / 0.15 * 9.0) * dt
            notifyOnce('overheat', 'Silnik się przegrzewa! Zwolnij lub zatrzymaj auto.', 'error', 30000)
        end
        -- brak oleju – stopniowe zacieranie
        if fx.oilZero and running then
            newEh = newEh - (1.5 + rpm * 6.0) * dt
            notifyOnce('oil0', 'Brak oleju – silnik się zaciera!', 'error', 20000)
        end
        if newEh < eh then
            if newEh <= 0.0 then
                newEh = 0.0
                SetVehicleEngineOn(veh, false, true, false)
                notifyOnce('seized', 'Silnik zgasł – poważna awaria', 'error', 15000)
            end
            SetVehicleEngineHealth(veh, newEh + 0.0)
        end
        if S.temp > 0.92 and running then startSteam(veh) elseif S.steam and S.temp < 0.85 then stopSteam() end

        -- wypadanie zapłonów
        if fx.misfire and running and thr > 0.2 and rpm > 0.25 and now >= S.nextMisfire then
            misfire(veh)
            S.nextMisfire = now + math.floor(math.random(600, 4500) * (1.25 - fx.misfire))
        end

        -- pisk klocków
        if fx.squeal and braking and kmh > 4.0 and kmh < 80.0 and now >= S.squealCd then
            DPM.Nui('drive:sound', { name = 'squeal', v = round(0.35 + fx.squeal * 0.65, 2) })
            S.squealCd = now + 1300 + math.random(0, 900)
        end

        -- bicie tarcz przy hamowaniu
        if fx.judder and braking and kmh > 30.0 then
            Drive.SetShake('judder', (0.12 + 0.45 * fx.judder) * Utils.Clamp(kmh / 100.0, 0.4, 1.2))
            if now >= S.judderCd then
                DPM.Nui('drive:sound', { name = 'judder', v = round(fx.judder, 2) })
                S.judderCd = now + 700
            end
        else
            Drive.SetShake('judder', nil)
        end
    end

    -- niewyważenie kół – rezonans w zakresie prędkości
    if CI.enabled ~= false and fx.imbB > 2.0 then
        local from, to = CI.speedFrom or 70, CI.speedTo or 140
        if kmh >= from and kmh <= to and to > from then
            local t = (kmh - from) / (to - from)
            local amp = Utils.Clamp(fx.imbB / (CI.gramsForMax or 60), 0.0, 1.0) * math.sin(t * math.pi) * 0.5
            Drive.SetShake('imbalance', amp > 0.02 and amp or nil)
        else
            Drive.SetShake('imbalance', nil)
        end
    else
        Drive.SetShake('imbalance', nil)
    end

    -- łyse opony pękają (raz na sekundę losowanie)
    if Config.TireBurstAtZero and #fx.bald > 0 and kmh > 40.0 and now >= S.burstCd then
        S.burstCd = now + 1000
        if GetVehicleTyresCanBurst(veh) then
            for _, w in ipairs(fx.bald) do
                local idx = TYRE_IDX[w]
                if idx and w <= S.wheels and not IsVehicleTyreBurst(veh, idx, false) and math.random() < 0.0025 * (kmh / 80.0) then
                    SetVehicleTyreBurst(veh, idx, false, 1000.0)
                    DPM.Notify('Pękła łysa opona (' .. (DPM.WheelLabels[w] or w) .. ')!', 'error', 5000)
                end
            end
        end
    end

    -- ticki co klatkę tylko gdy potrzebne
    local needAlign = math.abs(fx.align) > 0.005 and kmh > 20.0
    if needAlign ~= S.alignOn then
        S.alignOn = needAlign
        if not needAlign then SetVehicleSteerBias(veh, 0.0) end
    end
    local needSlip = fx.slip ~= nil and running and thr > 0.5
    local want = needAlign or needSlip
    if want and not Drive.HasTick('wear') then
        Drive.SetTick('wear', wearTick)
    elseif not want and Drive.HasTick('wear') then
        Drive.SetTick('wear', nil)
        Drive.SetPowerMod('clutch', nil)
    end

    -- niepotwierdzony przebieg (serwer odrzucił) – po 2 min zapominamy
    if S.unconf > 0 and now - S.unconfAt > 120000 then S.unconf = 0.0 end

    -- wyjście z auta – synchronizacja zanim przestaniemy być kierowcą
    if GetIsTaskActive(ped, 2) and not S.exitFlushed then
        S.exitFlushed = true
        sendSync()
    end
    if now >= S.nextSync or S.pend >= MAX_KM * 0.9 then sendSync() end

    if now >= S.nextDash then
        S.nextDash = now + 500
        sendDash(false)
    end
    if now >= S.nextOdo then
        S.nextOdo = now + 250
        sendOdo(false)
    end
    if now >= S.nextTripSave then
        S.nextTripSave = now + 15000
        saveTrip(false)
    end
end

-- --------------------------------------------------------------------------
--  Sesja jazdy
-- --------------------------------------------------------------------------
local function refreshData(data)
    local old = S.fx
    S.data = data
    S.fx = buildFx(data, S.wheels)
    S.warnStatic = buildStaticWarnings(data, S.fx)
    S.dashSig = nil
    local veh = S.veh
    -- zerwany pasek w trakcie jazdy – silnik gaśnie, zawory dostają
    if S.fx.beltBroken and old and not old.beltBroken and GetIsVehicleEngineRunning(veh) then
        SetVehicleEngineOn(veh, false, true, true)
        SetVehicleEngineHealth(veh, math.max(0.0, GetVehicleEngineHealth(veh) - 250.0))
        DPM.Nui('drive:sound', { name = 'misfire' })
        DPM.Notify('Zerwał się pasek rozrządu! Silnik zgasł.', 'error', 7000)
    end
    if S.fx.beltBroken and not S.undriveable then
        SetVehicleUndriveable(veh, true)
        S.undriveable = true
    elseif not S.fx.beltBroken and S.undriveable then
        SetVehicleUndriveable(veh, false)
        SetVehicleEngineOn(veh, false, true, false)
        S.undriveable = false
    end
end

local function startSession(veh, data)
    sessionId = sessionId + 1
    local now = GetGameTimer()
    local plate = DPM.Plate(veh)
    local wheels = math.max(1, DPM.WheelCount(veh))
    S = {
        token = sessionId, veh = veh, plate = plate, wheels = wheels,
        netId = NetworkGetEntityIsNetworked(veh) and VehToNet(veh) or nil,
        data = nil, fx = nil, warnStatic = {},
        pend = 0.0, unconf = 0.0, unconfAt = now, disp = 0.0, stateKm = tonumber(data.km) or 0.0,
        trip = GetResourceKvpFloat(tripKey(plate)) or 0.0, tripSaved = 0.0,
        last = now, nextSync = now + SYNC_MS, nextDash = now, nextOdo = now, nextTripSave = now + 15000,
        prevSpeed = GetEntitySpeed(veh), prevBody = GetVehicleBodyHealth(veh), vz = 0.0, impCd = 0,
        wasRunning = GetIsVehicleEngineRunning(veh), attemptHandled = GetIsVehicleEngineRunning(veh),
        nextMisfire = now + 2000, squealCd = 0, judderCd = 0, burstCd = now + 1000, crankCd = 0,
        alignOn = false, temp = 0.12, cranking = false, exitFlushed = false,
    }
    S.tripSaved = S.trip
    nosUsed = 0.0
    resetAccumulators()

    -- temperatura: auto pamięta, jak było ciepłe (stygnie z czasem)
    local stored = temps[plate]
    if stored then
        S.temp = math.max(0.08, stored.t - (now - stored.at) / 1000.0 * 0.004)
    elseif S.wasRunning then
        S.temp = 0.45
    end

    refreshData(data)
    -- rozrząd zerwany – silnik nie pracuje
    if S.fx.beltBroken and S.wasRunning then SetVehicleEngineOn(veh, false, true, true) end

    sendDash(true)
    sendOdo(true)
    local token = S.token
    CreateThread(function()
        while S and S.token == token do
            local ok, err = pcall(sample)
            if not ok then print('[dp-mechanic] wear: ' .. tostring(err)) end
            Wait(200)
        end
    end)
end

local function endSession(veh)
    if not S then return end
    sendSync()
    saveTrip(true)
    local now = GetGameTimer()
    for plate, t in pairs(temps) do
        if now - t.at > 1800000 then temps[plate] = nil end
    end
    temps[S.plate] = { t = S.temp, at = now }
    stopSteam()
    Drive.SetTick('wear', nil)
    Drive.SetPowerMod('clutch', nil)
    Drive.SetPowerMod('misfire', nil)
    if DoesEntityExist(veh) then
        if S.alignOn then SetVehicleSteerBias(veh, 0.0) end
        if S.undriveable then SetVehicleUndriveable(veh, false) end
    end
    if CW.warnDashboard ~= false then DPM.Nui('dash', { visible = false }) end
    if MILEAGE_ON and CM.hud ~= false then DPM.Nui('odo', { visible = false }) end
    S = nil
end

local function trackingEnabled()
    return WEAR_ON or MILEAGE_ON or (Config.Nitro and Config.Nitro.enabled)
end

Drive.OnEnter(function(veh, data)
    if not trackingEnabled() or type(data) ~= 'table' then return end
    startSession(veh, data)
end)

Drive.OnLeave(function(veh)
    endSession(veh)
end)

Drive.OnData(function(veh, data)
    if not trackingEnabled() then return end
    if not S then
        -- dane dotarły dopiero po wejściu
        if Drive.veh == veh then startSession(veh, data) end
        return
    end
    if S.veh ~= veh then return end
    local newKm = tonumber(data.km) or 0.0
    if newKm > S.stateKm then
        S.unconf = math.max(0.0, S.unconf - (newKm - S.stateKm))
    elseif newKm < S.stateKm - 0.5 then
        -- korekta licznika przez administratora
        S.unconf, S.disp = 0.0, 0.0
    end
    S.stateKm = newKm
    refreshData(data)
    sendDash(true)
    sendOdo(true)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() or not S then return end
    local veh = S.veh
    sendSync()
    saveTrip(true)
    stopSteam()
    if DoesEntityExist(veh) then
        SetVehicleSteerBias(veh, 0.0)
        if S.undriveable then SetVehicleUndriveable(veh, false) end
    end
end)
