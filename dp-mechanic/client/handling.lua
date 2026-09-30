-- ==========================================================================
--  DPM.Drive – realny wpływ części na jazdę (handling), dźwięki silników,
--  strzały z wydechu, turbodziura oraz wspólna pętla kierowcy:
--    - modyfikatory mocy (turbo / misfire / sprzęgło / nitro) łączone w JEDNO
--      wywołanie SetVehicleCheatPowerIncrease na klatkę,
--    - wstrząsy kamery z wielu źródeł (bierzemy najsilniejszy),
--    - „ticki” modułów (wear, nitro) wykonywane co klatkę tylko gdy potrzebne.
-- ==========================================================================
DPM.Drive = {
    veh = nil,    -- auto, którym kieruje lokalny gracz
    data = nil,   -- ostatnie znane dane techniczne (state.dpm) tego auta
}
local Drive = DPM.Drive

local RAD = math.pi / 180.0
local ENGINE_AUDIO_RANGE = 80.0

local baseCache = {}   -- [model] = { vals (jednostki handling.meta), raw (wartości wewnętrzne), conv }
local applied = {}     -- [veh] = { targets = {pole = wartość meta}, gears }
local topBoost = {}    -- [veh] = mnożnik prędkości maks. (nitro)

-- --------------------------------------------------------------------------
--  Jednostki: gra po wczytaniu handling.meta przelicza część pól na jednostki
--  wewnętrzne (m/s, radiany, x2). Natywki Get/SetVehicleHandlingFloat działają
--  na wartościach wewnętrznych – przeliczamy w obie strony, żeby Handling.Compute
--  i Handling.Limits pracowały na wartościach „jak w pliku meta”.
--  Wykrywanie: fSteeringLock w meta to stopnie (≥ 15), wewnętrznie radiany (< 1.5).
-- --------------------------------------------------------------------------
local Conv = {
    fInitialDriveMaxFlatVel = {
        toMeta = function(v) return v * 3.6 end,
        toRaw = function(v) return v / 3.6 end,
    },
    fBrakeBiasFront = {
        toMeta = function(v) return v * 0.5 end,
        toRaw = function(v) return v * 2.0 end,
    },
    fSteeringLock = {
        toMeta = function(v) return v / RAD end,
        toRaw = function(v) return v * RAD end,
    },
    fTractionCurveLateral = {
        toMeta = function(v) return v / RAD end,
        toRaw = function(v) return v * RAD end,
    },
    -- napęd: 1.0 = przód, 0.0 = tył, pomiędzy = AWD zapisane wewnętrznie jako 2×bias
    fDriveBiasFront = {
        toMeta = function(v)
            if v >= 0.999 and v <= 1.001 then return 1.0 end
            if v <= 0.001 then return 0.0 end
            return Utils.Clamp(v * 0.5, 0.0, 1.0)
        end,
        toRaw = function(v)
            if v >= 0.95 then return 1.0 end
            if v <= 0.05 then return 0.0 end
            return v * 2.0
        end,
    },
}

-- pole → stat (do mnożników z meta.mult)
local FieldStat = {}
for stat, s in pairs(Handling.Stats) do
    FieldStat[s[1]] = stat
    if s[3] then FieldStat[s[3]] = stat end
end

local function toRaw(c, field, v)
    local cv = Conv[field]
    if c.conv and cv then return cv.toRaw(v) end
    return v
end

local function readBase(veh)
    local raw, vals = {}, {}
    for _, f in ipairs(Handling.Fields) do
        raw[f] = GetVehicleHandlingFloat(veh, 'CHandlingData', f)
    end
    raw.nInitialDriveGears = GetVehicleHandlingInt(veh, 'CHandlingData', 'nInitialDriveGears')
    local conv = (raw.fSteeringLock or 0.0) < 3.0
    for f, v in pairs(raw) do
        local cv = Conv[f]
        vals[f] = (conv and cv) and cv.toMeta(v) or v
    end
    if not vals.nInitialDriveGears or vals.nInitialDriveGears < 1 then vals.nInitialDriveGears = 5 end
    return { vals = vals, raw = raw, conv = conv }
end

local function baseInfo(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return nil end
    local model = GetEntityModel(veh)
    local c = baseCache[model]
    if not c then
        c = readBase(veh)
        baseCache[model] = c
    end
    return c
end

local function canControl(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return false end
    return GetPedInVehicleSeat(veh, -1) == PlayerPedId() or NetworkHasControlOfEntity(veh)
end

-- --------------------------------------------------------------------------
--  API: baza / obliczenia / zastosowanie
-- --------------------------------------------------------------------------

-- wartości bazowe modelu (jednostki handling.meta) – czytane raz na model, przed modyfikacją
function Drive.GetBase(veh)
    local c = baseInfo(veh)
    return c and c.vals or nil
end

-- dane techniczne auta (dla auta, którym kierujemy – z cache, bez dekodowania statebaga)
function Drive.GetData(veh)
    if not veh or not DoesEntityExist(veh) then return nil end
    if veh == Drive.veh and Drive.data then return Drive.data end
    return Entity(veh).state.dpm
end

function Drive.Compute(veh, dataOverride, modsOverride)
    local base = Drive.GetBase(veh)
    if not base then return {}, { hp = 0.0, stockHp = 0.0, mult = {} } end
    local data = dataOverride or Drive.GetData(veh) or Utils.NewVehicleData()
    return Handling.Compute(base, data, modsOverride or DPM.GetGtaModLevels(veh))
end

-- docelowe wartości wszystkich pól (jednostki meta) – odporne na pola o nieznanej skali:
-- gdy baza leży poza Handling.Limits (inna skala wewnętrzna), stosujemy sam mnożnik
local function buildTargets(c, out, meta)
    local targets = {}
    for _, f in ipairs(Handling.Fields) do
        if f ~= 'fMass' then
            local b = c.vals[f]
            local v = out[f]
            if v == nil then
                v = b
            else
                local st = FieldStat[f]
                local lim = Handling.Limits[f]
                if st and Handling.Stats[st][2] == 'mult' and lim and b and (b < lim[1] or b > lim[2]) then
                    v = b * Utils.Clamp((meta.mult and meta.mult[st]) or 1.0, 0.2, 5.0)
                end
            end
            targets[f] = v
        end
    end
    targets.nInitialDriveGears = out.nInitialDriveGears or c.vals.nInitialDriveGears
    return targets
end

-- zapis do auta; prev = poprzednio zastosowane cele (zapisujemy tylko zmienione pola)
local function writeTargets(veh, c, targets, prev)
    local boost = topBoost[veh] or 1.0
    local speedChanged = prev == nil
    for f, v in pairs(targets) do
        if f ~= 'nInitialDriveGears' and type(v) == 'number' then
            local old = prev and prev.targets[f]
            if not old or math.abs(old - v) > 0.00001 then
                local raw
                if f == 'fDriveBiasFront' then
                    raw = toRaw(c, f, v)
                    -- bezpieczeństwo: tylnego udziału napędu nie da się ustawić natywką – auto z bazą
                    -- „przód” (tył = 0) nie może stracić napędu przedniego, bo stanęłoby w miejscu
                    local baseRaw = c.raw.fDriveBiasFront or 0.0
                    if c.conv and baseRaw >= 0.999 and raw < 1.0 then raw = 1.0 end
                elseif f == 'fInitialDriveMaxFlatVel' then
                    raw = toRaw(c, f, v * boost)
                    speedChanged = true
                else
                    raw = toRaw(c, f, v)
                end
                SetVehicleHandlingFloat(veh, 'CHandlingData', f, raw + 0.0)
            end
        end
    end
    local gears = math.floor((targets.nInitialDriveGears or c.vals.nInitialDriveGears or 5) + 0.5)
    local prevGears = prev and prev.gears or c.raw.nInitialDriveGears
    if gears ~= prevGears or not prev then
        SetVehicleHandlingInt(veh, 'CHandlingData', 'nInitialDriveGears', gears)
        if SetVehicleHighGear and gears ~= prevGears then SetVehicleHighGear(veh, gears) end
    end
    if speedChanged then ModifyVehicleTopSpeed(veh, 1.0) end
    return gears
end

-- stosuje handling wg części (tylko kierowca lub właściciel sieciowy)
function Drive.Apply(veh, dataOverride)
    if not canControl(veh) then return false end
    local data = dataOverride or Drive.GetData(veh)
    if type(data) ~= 'table' then return false end
    local c = baseInfo(veh)
    if not c then return false end
    local out, meta = Handling.Compute(c.vals, data, DPM.GetGtaModLevels(veh))
    local targets = buildTargets(c, out, meta)
    local gears = writeTargets(veh, c, targets, applied[veh])
    applied[veh] = { targets = targets, gears = gears }
    DPM.Debug(('Drive.Apply %s hp=%.0f (stock %.0f)'):format(DPM.Plate(veh), meta.hp or 0, meta.stockHp or 0))
    return true, meta
end

-- przywraca fabryczny handling modelu
function Drive.Reset(veh)
    if not veh or not DoesEntityExist(veh) then return false end
    local c = baseCache[GetEntityModel(veh)]
    if not c then return false end
    for _, f in ipairs(Handling.Fields) do
        if f ~= 'fMass' and c.raw[f] then
            SetVehicleHandlingFloat(veh, 'CHandlingData', f, c.raw[f] + 0.0)
        end
    end
    if c.raw.nInitialDriveGears and c.raw.nInitialDriveGears > 0 then
        SetVehicleHandlingInt(veh, 'CHandlingData', 'nInitialDriveGears', c.raw.nInitialDriveGears)
        if SetVehicleHighGear then SetVehicleHighGear(veh, c.raw.nInitialDriveGears) end
    end
    ModifyVehicleTopSpeed(veh, 1.0)
    applied[veh] = nil
    topBoost[veh] = nil
    return true
end

-- chwilowy mnożnik prędkości maks. (nitro) – bez SetEntityMaxSpeed, przez handling
function Drive.SetTopBoost(veh, mult)
    if not veh or not DoesEntityExist(veh) then return end
    mult = mult or 1.0
    if math.abs((topBoost[veh] or 1.0) - mult) < 0.001 then return end
    local c = baseInfo(veh)
    if not c then return end
    topBoost[veh] = (mult ~= 1.0) and mult or nil
    local a = applied[veh]
    local v = (a and a.targets.fInitialDriveMaxFlatVel) or c.vals.fInitialDriveMaxFlatVel
    if not v then return end
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDriveMaxFlatVel', toRaw(c, 'fInitialDriveMaxFlatVel', v * mult) + 0.0)
    ModifyVehicleTopSpeed(veh, 1.0)
end

-- --------------------------------------------------------------------------
--  Statystyki 0..100 (paski w menu tuningu / tablecie)
-- --------------------------------------------------------------------------
local function score(v, lo, hi)
    return Utils.Clamp((v - lo) / (hi - lo) * 100.0, 0.0, 100.0)
end

function Drive.Stats(veh, data, mods)
    local zero = { power = 0, topspeed = 0, accel = 0, braking = 0, grip = 0, handling = 0, hp = 0 }
    local base = Drive.GetBase(veh)
    if not base then return zero end
    data = data or Drive.GetData(veh) or Utils.NewVehicleData()
    local out, meta = Handling.Compute(base, data, mods or DPM.GetGtaModLevels(veh))
    local function g(f)
        local v = out[f]
        if v == nil then v = base[f] end
        return v or 0.0
    end
    local function rel(f)
        local b = base[f]
        if not b or b == 0 then return 1.0 end
        return g(f) / b
    end

    local hp = meta.hp or 0.0
    local mass = math.max(base.fMass or 1400.0, 300.0)
    local gripMax, gripMin = g('fTractionCurveMax'), g('fTractionCurveMin')

    local power = 100.0 * (1.0 - math.exp(-hp / 420.0))
    local topspeed = score(g('fInitialDriveMaxFlatVel'), 60.0, 230.0)

    -- przyspieszenie: moc/masa, trakcja, szybkość zmiany biegów
    local pw = hp / (mass / 1000.0)
    local traction = Utils.Clamp(0.72 + 0.28 * (gripMax / 2.6), 0.6, 1.08)
    local shift = Utils.Clamp(0.94 + 0.06 * rel('fClutchChangeRateScaleUpShift'), 0.9, 1.08)
    local accel = Utils.Clamp(100.0 * (1.0 - math.exp(-pw / 300.0)) * traction * shift, 0.0, 100.0)

    local braking = score(g('fBrakeForce') * (gripMax / 2.3), 0.2, 1.9)
    local grip = score(gripMax * 0.7 + gripMin * 0.3, 1.2, 3.2)

    -- prowadzenie: przyczepność, stabilizatory, sprężyny, kąt skrętu, reakcja boczna
    local antiroll = Utils.Clamp(50.0 * rel('fAntiRollBarForce'), 0.0, 100.0)
    local springs = Utils.Clamp(50.0 * rel('fSuspensionForce'), 0.0, 100.0)
    local steer = score(g('fSteeringLock'), 25.0, 65.0)
    local lateral = score(30.0 - g('fTractionCurveLateral'), 5.0, 17.0)
    local handling = grip * 0.5 + antiroll * 0.18 + springs * 0.1 + steer * 0.1 + lateral * 0.12

    return {
        power = math.floor(power + 0.5), topspeed = math.floor(topspeed + 0.5), accel = math.floor(accel + 0.5),
        braking = math.floor(braking + 0.5), grip = math.floor(grip + 0.5), handling = math.floor(Utils.Clamp(handling, 0, 100) + 0.5),
        hp = math.floor(hp + 0.5),
    }
end

-- --------------------------------------------------------------------------
--  Wspólna pętla kierowcy: moc, wstrząsy, ticki
-- --------------------------------------------------------------------------
local ticks = {}        -- [nazwa] = fn(veh, dt, now)
local powerMods = {}    -- [nazwa] = mnożnik mocy
local loopRunning = false
local cheatSet = false

local function needLoop()
    return Drive.veh ~= nil and (next(ticks) ~= nil or next(powerMods) ~= nil)
end

local function ensureLoop()
    if loopRunning or not needLoop() then return end
    loopRunning = true
    CreateThread(function()
        local last = GetGameTimer()
        local veh = Drive.veh
        while needLoop() and Drive.veh == veh do
            local now = GetGameTimer()
            local dt = (now - last) / 1000.0
            last = now
            if dt > 0.25 then dt = 0.25 end
            if not DoesEntityExist(veh) then break end
            for name, fn in pairs(ticks) do
                local ok, err = pcall(fn, veh, dt, now)
                if not ok then
                    ticks[name] = nil
                    print(('[dp-mechanic] błąd ticku %s: %s'):format(name, tostring(err)))
                end
            end
            local p = 1.0
            for _, m in pairs(powerMods) do p = p * m end
            if p < 0.999 or p > 1.001 then
                SetVehicleCheatPowerIncrease(veh, p)
                cheatSet = true
            elseif cheatSet then
                SetVehicleCheatPowerIncrease(veh, 1.0)
                cheatSet = false
            end
            Wait(0)
        end
        if cheatSet and DoesEntityExist(veh) then SetVehicleCheatPowerIncrease(veh, 1.0) end
        cheatSet = false
        loopRunning = false
        -- auto zmienione w trakcie – uruchom ponownie dla nowego
        if needLoop() then ensureLoop() end
    end)
end

-- mnożnik mocy z danego źródła (nil / 1.0 = usuń)
function Drive.SetPowerMod(key, mult)
    if mult == nil or (mult > 0.999 and mult < 1.001) then
        powerMods[key] = nil
        return
    end
    powerMods[key] = mult
    ensureLoop()
end

function Drive.GetPowerMod(key) return powerMods[key] end

-- funkcja wykonywana co klatkę, gdy kierujemy (nil = usuń)
function Drive.SetTick(key, fn)
    ticks[key] = fn
    if fn then ensureLoop() end
end

function Drive.HasTick(key) return ticks[key] ~= nil end

-- wstrząsy kamery: wiele źródeł, stosujemy najsilniejszy
local shakes, shaking = {}, false
local function updateShake()
    local m = 0.0
    for _, a in pairs(shakes) do if a > m then m = a end end
    if m > 0.005 then
        if not shaking or not IsGameplayCamShaking() then
            ShakeGameplayCam('ROAD_VIBRATION_SHAKE', m)
            shaking = true
        else
            SetGameplayCamShakeAmplitude(m)
        end
    elseif shaking then
        StopGameplayCamShaking(false)
        shaking = false
    end
end

function Drive.SetShake(key, amp)
    local new = (amp and amp > 0.005) and amp or nil
    if shakes[key] == new then return end
    shakes[key] = new
    updateShake()
end

function Drive.ClearShakes()
    shakes = {}
    updateShake()
end

-- HUD kierowcy może być widoczny (nie w menu pauzy)
function Drive.HudAllowed()
    return not IsPauseMenuActive()
end

function Drive.IsDriving() return Drive.veh ~= nil end

-- --------------------------------------------------------------------------
--  Zdarzenia kierowcy (wear / nitro się podpinają)
-- --------------------------------------------------------------------------
local enterCbs, leaveCbs, dataCbs = {}, {}, {}
function Drive.OnEnter(fn) enterCbs[#enterCbs + 1] = fn end   -- fn(veh, data|nil)
function Drive.OnLeave(fn) leaveCbs[#leaveCbs + 1] = fn end   -- fn(veh, data|nil)
function Drive.OnData(fn) dataCbs[#dataCbs + 1] = fn end      -- fn(veh, data) – nowe dane auta, którym kierujemy

local function fire(list, ...)
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then print('[dp-mechanic] błąd zdarzenia jazdy: ' .. tostring(err)) end
    end
end

-- --------------------------------------------------------------------------
--  Turbodziura (silniki z turbo = true po swapie)
-- --------------------------------------------------------------------------
local turbo = { spool = 0.0, lag = 0.5, prevThr = 0.0, lastBov = 0 }

local function turboTick(veh, dt, now)
    local thr = GetControlNormal(0, 71)
    local rpm = GetVehicleCurrentRpm(veh)
    if thr > 0.15 and GetIsVehicleEngineRunning(veh) then
        -- turbina rozkręca się szybciej na wyższych obrotach
        local rate = (0.55 + rpm * 0.9) / turbo.lag
        turbo.spool = math.min(1.0, turbo.spool + dt * rate * (0.4 + 0.6 * thr))
    else
        -- zawór upustowy (blow-off) po zdjęciu nogi z gazu przy wysokim doładowaniu
        if turbo.prevThr > 0.5 and turbo.spool > 0.7 and now - turbo.lastBov > 700 then
            turbo.lastBov = now
            DPM.Nui('drive:sound', { name = 'bov', v = turbo.spool })
        end
        turbo.spool = math.max(0.0, turbo.spool - dt / 0.6)
    end
    turbo.prevThr = thr
    -- na niskich obrotach turbina nie utrzyma ciśnienia
    if rpm < 0.3 then turbo.spool = math.min(turbo.spool, 0.25 + rpm) end
    local mult = 0.55 + 0.45 * turbo.spool
    Drive.SetPowerMod('turbo', mult < 0.995 and mult or nil)
end

local function setupTurbo(veh, data)
    local eng = data and data.swap and Config.Engines[data.swap.engine or 'stock']
    if eng and eng.turbo and (eng.lag or 0) > 0 then
        turbo.lag = math.max(0.1, eng.lag)
        if not Drive.HasTick('turbo') then
            turbo.spool = GetIsVehicleEngineRunning(veh) and 0.3 or 0.0
            turbo.prevThr = 0.0
            Drive.SetTick('turbo', turboTick)
        end
    else
        Drive.SetTick('turbo', nil)
        Drive.SetPowerMod('turbo', nil)
    end
end

-- --------------------------------------------------------------------------
--  Wejście / wyjście z auta (kierowca)
-- --------------------------------------------------------------------------
local function onEnter(veh)
    Drive.veh = veh
    Drive.data = nil
    local data = DPM.EnsureVehData(veh)
    if Drive.veh ~= veh then return end
    if type(data) == 'table' then
        Drive.data = data
        applied[veh] = nil   -- pełny zapis przy wejściu (uchwyty encji mogą być ponownie użyte)
        Drive.Apply(veh, data)
        setupTurbo(veh, data)
    end
    fire(enterCbs, veh, Drive.data)
end

local function onLeave(veh)
    fire(leaveCbs, veh, Drive.data)
    Drive.SetTick('turbo', nil)
    powerMods = {}
    ticks = {}
    Drive.ClearShakes()
    if cheatSet and DoesEntityExist(veh) then SetVehicleCheatPowerIncrease(veh, 1.0) cheatSet = false end
    if topBoost[veh] and DoesEntityExist(veh) then Drive.SetTopBoost(veh, 1.0) end
    Drive.veh = nil
    Drive.data = nil
end

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        local isDriver = veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped
        if isDriver then
            if veh ~= Drive.veh then
                if Drive.veh then onLeave(Drive.veh) end
                onEnter(veh)
            end
        elseif Drive.veh then
            onLeave(Drive.veh)
        end
        Wait(Drive.veh and 250 or 500)
    end
end)

-- nowe dane auta, którym kierujemy (montaż, zużycie, napełnienie butli…) – debounce 250 ms
local pendingData, dataDebounce = nil, false
AddStateBagChangeHandler('dpm', nil, function(bagName, _, value)
    local ent = GetEntityFromStateBagName(bagName)
    if ent == 0 or ent ~= Drive.veh then return end
    pendingData = value
    if dataDebounce then return end
    dataDebounce = true
    SetTimeout(250, function()
        dataDebounce = false
        local veh = Drive.veh
        local d = pendingData
        pendingData = nil
        if veh ~= ent or not DoesEntityExist(veh) or type(d) ~= 'table' then return end
        Drive.data = d
        Drive.Apply(veh, d)
        setupTurbo(veh, d)
        fire(dataCbs, veh, d)
    end)
end)

-- --------------------------------------------------------------------------
--  Dźwięki silników (swap) i strzały z wydechu – dla wszystkich aut w pobliżu
-- --------------------------------------------------------------------------
local sndApplied = {}   -- [veh] = nazwa dźwięku
local popsApplied = {}  -- [veh] = true

local function stockAudioName(veh)
    return string.lower(GetDisplayNameFromVehicleModel(GetEntityModel(veh)) or '')
end

local function syncVehicleAudio(veh)
    if not NetworkGetEntityIsNetworked(veh) then return end
    local st = Entity(veh).state
    local snd = st.dpm_snd
    local cur = sndApplied[veh]
    if type(snd) == 'string' and snd ~= '' then
        if cur ~= snd then
            ForceVehicleEngineAudio(veh, snd)
            sndApplied[veh] = snd
        end
    elseif cur then
        -- swap usunięty – wracamy do fabrycznego brzmienia
        local stock = stockAudioName(veh)
        if stock ~= '' and stock ~= 'carnotfound' then ForceVehicleEngineAudio(veh, stock) end
        sndApplied[veh] = nil
    end
    if EnableVehicleExhaustPops then
        local pops = st.dpm_pops == true
        if pops and not popsApplied[veh] then
            EnableVehicleExhaustPops(veh, true)
            popsApplied[veh] = true
        elseif not pops and popsApplied[veh] then
            EnableVehicleExhaustPops(veh, false)
            popsApplied[veh] = nil
        end
    end
end

-- wymusza ponowne nałożenie dźwięku (np. po odsłuchu silnika w menu tuningu)
function Drive.RefreshSound(veh)
    if not veh or not DoesEntityExist(veh) then return end
    sndApplied[veh] = nil
    syncVehicleAudio(veh)
end

CreateThread(function()
    while true do
        Wait(1500)
        local pos = GetEntityCoords(PlayerPedId())
        for _, veh in ipairs(GetGamePool('CVehicle')) do
            if #(pos - GetEntityCoords(veh)) <= ENGINE_AUDIO_RANGE then
                syncVehicleAudio(veh)
            end
        end
        for veh in pairs(sndApplied) do if not DoesEntityExist(veh) then sndApplied[veh] = nil end end
        for veh in pairs(popsApplied) do if not DoesEntityExist(veh) then popsApplied[veh] = nil end end
        for veh in pairs(applied) do if not DoesEntityExist(veh) then applied[veh] = nil topBoost[veh] = nil end end
    end
end)

local function onAudioBag(bagName)
    local ent = GetEntityFromStateBagName(bagName)
    if ent == 0 then return end
    -- handler wywoływany przed zapisem wartości – nakładamy chwilę później
    SetTimeout(60, function()
        if DoesEntityExist(ent) and #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(ent)) <= ENGINE_AUDIO_RANGE then
            syncVehicleAudio(ent)
        end
    end)
end
AddStateBagChangeHandler('dpm_snd', nil, function(bagName) onAudioBag(bagName) end)
AddStateBagChangeHandler('dpm_pops', nil, function(bagName) onAudioBag(bagName) end)

-- --------------------------------------------------------------------------
--  Sprzątanie przy zatrzymaniu zasobu
-- --------------------------------------------------------------------------
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if Drive.veh and DoesEntityExist(Drive.veh) then SetVehicleCheatPowerIncrease(Drive.veh, 1.0) end
    if shaking then StopGameplayCamShaking(true) end
    for veh in pairs(applied) do
        if DoesEntityExist(veh) then
            topBoost[veh] = nil
            Drive.Reset(veh)
        end
    end
    for veh in pairs(sndApplied) do
        if DoesEntityExist(veh) then
            local stock = stockAudioName(veh)
            if stock ~= '' and stock ~= 'carnotfound' then ForceVehicleEngineAudio(veh, stock) end
        end
    end
    if EnableVehicleExhaustPops then
        for veh in pairs(popsApplied) do
            if DoesEntityExist(veh) then EnableVehicleExhaustPops(veh, false) end
        end
    end
end)
