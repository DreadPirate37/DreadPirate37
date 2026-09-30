-- ==========================================================================
--  dp-pojazdy – logika skrzyni biegów zależna od trybu jazdy
--  Fabryczna skrzynia GTA wrzuca wyższe biegi bardzo wcześnie i redukuje późno.
--  W trybach sportowych nadpisujemy ją co klatkę:
--    • blokada wczesnej zmiany w górę – bieg trzymany do wysokich obrotów,
--    • wczesna redukcja – silnik nie schodzi z obrotów,
--    • trzymanie biegu po puszczeniu gazu (hamowanie silnikiem),
--    • kickdown po przełączeniu trybu – od razu kilka biegów w dół,
--    • międzygaz przy redukcji.
--  ECO robi odwrotnie: wcześnie wrzuca wyższe biegi.
-- ==========================================================================
Gearbox = {}

local GetVehicleCurrentGear = GetVehicleCurrentGear
local GetVehicleNextGear = GetVehicleNextGear
local GetVehicleCurrentRpm = GetVehicleCurrentRpm
local GetVehicleGearRatio = GetVehicleGearRatio
local SetVehicleNextGear = SetVehicleNextGear

local lastShift = 0
local kickTarget, kickUntil = nil, 0
local k = nil           -- obroty na (m/s × przełożenie), kalibrowane w trakcie jazdy
local calVeh = 0

function Gearbox.Reset()
    lastShift, kickTarget, kickUntil, k, calVeh = 0, nil, 0, nil, 0
end

-- zmiana handlingu (np. reduktor) zmienia przełożenia – kalibrujemy od nowa
function Gearbox.Recalibrate() k = nil end

-- po przełączeniu w tryb sportowy: redukuj, aż obroty dojdą do 'target'
function Gearbox.Kick(target)
    if not Config.Gearbox.enabled or not target then return end
    kickTarget = target
    kickUntil = GetGameTimer() + 2000
    lastShift = 0
end

-- szacowane obroty na biegu g przy obecnej prędkości
local function rpmAt(veh, g, speed, rpm, cur)
    local rg = GetVehicleGearRatio(veh, g)
    if not rg or rg <= 0 then return nil end
    if k then return speed * rg * k end
    local rc = GetVehicleGearRatio(veh, cur)
    if not rc or rc <= 0 then return nil end
    return rpm * rg / rc
end

local function shift(veh, gear, now, predicted, blip)
    SetVehicleNextGear(veh, gear)
    SetVehicleCurrentGear(veh, gear)
    if blip and predicted then SetVehicleCurrentRpm(veh, math.min(0.99, predicted)) end
    lastShift = now
end

function Gearbox.Frame(veh, now, speed, gb)
    if not gb then return end
    local cur = GetVehicleCurrentGear(veh)
    if cur < 1 then return end -- wsteczny / luz
    local nxt = GetVehicleNextGear(veh)
    local rpm = GetVehicleCurrentRpm(veh)

    if veh ~= calVeh then k, calVeh = nil, veh end

    -- kalibracja przy sprzęgniętej skrzyni i bez buksowania
    if cur == nxt and speed > 4.0 and rpm > 0.3 and rpm < 0.98 and Car.tcFactor > 0.99
        and GetVehicleClutch(veh) > 0.95 and not IsEntityInAir(veh) then
        local rc = GetVehicleGearRatio(veh, cur)
        if rc and rc > 0 then
            local sample = rpm / (speed * rc)
            k = k and (k + (sample - k) * 0.1) or sample
        end
    end

    if speed < Config.Gearbox.minSpeed or IsEntityInAir(veh) then return end
    local thr = GetVehicleThrottleOffset(veh)

    -- 1) blokada zbyt wczesnej zmiany w górę
    if gb.up and nxt > cur then
        local allow = rpm >= gb.up or (not gb.hold and thr < 0.1)
        if not allow then
            SetVehicleNextGear(veh, cur)
            nxt = cur
        end
    end

    if nxt ~= cur then return end

    -- 2) kickdown po zmianie trybu (szybkie redukcje jedna po drugiej)
    if kickTarget then
        if now > kickUntil or cur <= 1 then
            kickTarget = nil
        elseif now - lastShift >= 150 then
            local pr = rpmAt(veh, cur - 1, speed, rpm, cur)
            if pr and pr <= kickTarget then
                shift(veh, cur - 1, now, pr, true)
            else
                kickTarget = nil
            end
        end
        return
    end

    if now - lastShift < (gb.gap or 400) then return end

    -- 3) wczesna redukcja – trzymamy silnik w obrotach
    if gb.down and cur > 1 and rpm < gb.down then
        local pr = rpmAt(veh, cur - 1, speed, rpm, cur)
        if pr and pr <= (gb.downMax or 0.9) then
            shift(veh, cur - 1, now, pr, gb.blip)
            return
        end
    end

    -- 4) ECO – wcześnie w górę przy spokojnym gazie
    if gb.earlyUp and cur < GetVehicleHighGear(veh) and thr > 0.05 and thr < 0.8 and rpm > gb.earlyUp then
        local pr = rpmAt(veh, cur + 1, speed, rpm, cur)
        if pr and pr >= 0.3 then shift(veh, cur + 1, now, nil, false) end
    end
end
