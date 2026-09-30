-- ==========================================================================
--  Silnik obliczeń: części → handling pojazdu, oraz krzywe hamowni.
--  Jedno źródło prawdy: to samo liczy jazdę, hamownię i diagnostykę w tablecie.
-- ==========================================================================
Handling = {}

-- stat → { pole handlingu, sposób łączenia, [drugie pole] }
Handling.Stats = {
    power        = { 'fInitialDriveForce', 'mult' },
    topspeed     = { 'fInitialDriveMaxFlatVel', 'mult' },
    revs         = { 'fDriveInertia', 'mult' },
    shift        = { 'fClutchChangeRateScaleUpShift', 'mult', 'fClutchChangeRateScaleDownShift' },
    gears        = { 'nInitialDriveGears', 'set' },
    bias         = { 'fDriveBiasFront', 'set' },
    brake        = { 'fBrakeForce', 'mult' },
    brakeBias    = { 'fBrakeBiasFront', 'set' },
    handbrake    = { 'fHandBrakeForce', 'mult' },
    grip         = { 'fTractionCurveMax', 'mult' },
    gripMin      = { 'fTractionCurveMin', 'mult' },
    lateral      = { 'fTractionCurveLateral', 'mult' },
    tractionLoss = { 'fTractionLossMult', 'mult' },
    lowSpeedLoss = { 'fLowSpeedTractionLossMult', 'mult' },
    susForce     = { 'fSuspensionForce', 'mult' },
    susDamp      = { 'fSuspensionCompDamp', 'mult', 'fSuspensionReboundDamp' },
    susRaise     = { 'fSuspensionRaise', 'add' },
    antiroll     = { 'fAntiRollBarForce', 'mult' },
    steer        = { 'fSteeringLock', 'mult' },
    engineDmg    = { 'fEngineDamageMult', 'mult' },
}

-- pola czytane z auta jako baza (fMass tylko do obliczeń mocy)
Handling.Fields = {
    'fInitialDriveForce', 'fInitialDriveMaxFlatVel', 'fDriveInertia', 'fClutchChangeRateScaleUpShift',
    'fClutchChangeRateScaleDownShift', 'fDriveBiasFront', 'fBrakeForce', 'fBrakeBiasFront', 'fHandBrakeForce',
    'fTractionCurveMax', 'fTractionCurveMin', 'fTractionCurveLateral', 'fTractionLossMult', 'fLowSpeedTractionLossMult',
    'fSuspensionForce', 'fSuspensionCompDamp', 'fSuspensionReboundDamp', 'fSuspensionRaise', 'fAntiRollBarForce',
    'fSteeringLock', 'fEngineDamageMult', 'fMass',
}
Handling.IntFields = { nInitialDriveGears = true }

-- bezpieczne granice (nie da się „zepsuć” fizyki auta nawet absurdalnym configiem)
Handling.Limits = {
    fInitialDriveForce = { 0.02, 3.0 }, fInitialDriveMaxFlatVel = { 40.0, 500.0 }, fDriveInertia = { 0.3, 2.5 },
    fClutchChangeRateScaleUpShift = { 0.3, 12.0 }, fClutchChangeRateScaleDownShift = { 0.3, 12.0 },
    fDriveBiasFront = { 0.0, 1.0 }, fBrakeForce = { 0.05, 5.0 }, fBrakeBiasFront = { 0.2, 0.8 }, fHandBrakeForce = { 0.1, 5.0 },
    fTractionCurveMax = { 0.5, 5.0 }, fTractionCurveMin = { 0.4, 5.0 }, fTractionCurveLateral = { 5.0, 35.0 },
    fTractionLossMult = { 0.1, 3.0 }, fLowSpeedTractionLossMult = { 0.0, 3.0 }, fSuspensionForce = { 0.5, 6.0 },
    fSuspensionCompDamp = { 0.2, 6.0 }, fSuspensionReboundDamp = { 0.2, 6.0 }, fSuspensionRaise = { -0.25, 0.25 },
    fAntiRollBarForce = { 0.0, 5.0 }, fSteeringLock = { 20.0, 75.0 }, fEngineDamageMult = { 0.1, 6.0 },
    nInitialDriveGears = { 1, 7 },
}

local function newAcc()
    return { mult = {}, set = {}, add = {} }
end

local function push(acc, stat, value, power)
    local s = Handling.Stats[stat]
    if not s or type(value) ~= 'number' then return end
    local how = s[2]
    if how == 'mult' then
        acc.mult[stat] = (acc.mult[stat] or 1.0) * (value ^ (power or 1))
    elseif how == 'add' then
        acc.add[stat] = (acc.add[stat] or 0.0) + value * (power or 1)
    else
        acc.set[stat] = value
    end
end

local function pushAll(acc, effects, power)
    if not effects then return end
    for stat, value in pairs(effects) do push(acc, stat, value, power) end
end

function Handling.StockHp(base)
    return (base.fInitialDriveForce or 0.25) * (base.fMass or 1400.0) * Config.HpFactor
end

-- stan zużycia → mnożniki (osobno, bo pokazujemy to też w diagnostyce)
function Handling.WearFx(acc, data)
    if not Config.Wear.enabled or not data.parts then return end
    for id, p in pairs(Config.Wear.parts) do
        local cond = data.parts[id] or 100.0
        for _, fx in ipairs(p.fx or {}) do
            local stat, from, atZero = fx[1], fx[2], fx[3]
            if cond < from then
                local t = cond / from
                push(acc, stat, Utils.Lerp(atZero, 1.0, t))
            end
        end
    end
end

function Handling.TireGrip(data)
    local sum, n = 0.0, 0
    for i = 1, 4 do
        local t = data.tires and data.tires[i]
        if t then sum = sum + (t.t or Config.TireNewTread) n = n + 1 end
    end
    local avg = n > 0 and sum / n or Config.TireNewTread
    local cfg = Config.TireTreadGrip
    if avg >= cfg.at then return 1.0, avg end
    return Utils.Lerp(cfg.min, 1.0, avg / cfg.at), avg
end

--  base    – wartości bazowe z auta (Handling.Fields)
--  data    – dane techniczne pojazdu (Utils.NewVehicleData)
--  gtaMods – { [modType] = poziom (-1 brak) }  (toggle: 1/-1)
--  zwraca: { pole = wartość }, meta (hp, info do diagnostyki)
function Handling.Compute(base, data, gtaMods)
    local acc = newAcc()
    local meta = { stockHp = Handling.StockHp(base) }

    -- 1) modyfikacje GTA z efektami
    for t, lvl in pairs(gtaMods or {}) do
        local m = Config.ModTypes[t]
        if m and m.effects and lvl and lvl >= 0 then
            pushAll(acc, m.effects, m.toggle and 1 or (lvl + 1))
        end
    end

    -- 2) części osiągowe
    local wearMult = 1.0
    for id, lvl in pairs(data.perf or {}) do
        local p = Config.PerfParts[id]
        local l = p and p.levels[lvl]
        if l then
            pushAll(acc, l.effects)
            if p.wearMult and p.wearMult[lvl] then wearMult = wearMult * p.wearMult[lvl] end
            if l.pops then meta.pops = true end
        end
    end
    meta.wearMult = wearMult

    -- 3) swapy
    local sw = data.swap or {}
    local eng = Config.Engines[sw.engine or 'stock']
    if eng and eng.hp then
        local ratio = eng.hp / math.max(meta.stockHp, 30.0)
        push(acc, 'power', ratio)
        push(acc, 'topspeed', Utils.Clamp(ratio ^ (1.0 / 3.0), 0.7, 1.55))
        if eng.revs then push(acc, 'revs', eng.revs) end
        if eng.gears then push(acc, 'gears', eng.gears) end
        meta.engine = sw.engine
    end
    local dt = Config.Drivetrains[sw.drivetrain or 'stock']
    if dt and dt.bias then
        push(acc, 'bias', dt.bias)
        pushAll(acc, dt.effects)
    end
    local bk = Config.BrakeKits[sw.brakes or 'stock']
    if bk then pushAll(acc, bk.effects) end
    local gb = Config.Gearboxes[sw.gearbox or 'stock']
    if gb then pushAll(acc, gb.effects) end

    -- 4) opony
    local comp = Config.TireCompounds[data.compound or 'street']
    if comp then pushAll(acc, comp.effects) end
    local treadGrip, avgTread = Handling.TireGrip(data)
    push(acc, 'grip', treadGrip)
    push(acc, 'gripMin', treadGrip)
    meta.tread = avgTread

    -- 5) zużycie
    Handling.WearFx(acc, data)

    -- wynik
    local out = {}
    for stat, m in pairs(acc.mult) do
        local s = Handling.Stats[stat]
        for i = 1, (s[3] and 2 or 1) do
            local field = i == 1 and s[1] or s[3]
            if base[field] then out[field] = base[field] * m end
        end
    end
    for stat, v in pairs(acc.add) do
        local s = Handling.Stats[stat]
        out[s[1]] = (out[s[1]] or base[s[1]] or 0.0) + v
    end
    for stat, v in pairs(acc.set) do
        local s = Handling.Stats[stat]
        out[s[1]] = v
    end
    for field, lim in pairs(Handling.Limits) do
        if out[field] then out[field] = Utils.Clamp(out[field], lim[1], lim[2]) end
    end
    if out.nInitialDriveGears then out.nInitialDriveGears = math.floor(out.nInitialDriveGears + 0.5) end
    out.fMass = nil

    meta.hp = (out.fInitialDriveForce or base.fInitialDriveForce or 0.25) * (base.fMass or 1400.0) * Config.HpFactor
    meta.mult = acc.mult
    return out, meta
end

-- --------------------------------------------------------------------------
--  HAMOWNIA
-- --------------------------------------------------------------------------
local Curves = {
    na = function(x) return 0.62 + 0.62 * x - 0.42 * x * x end,
    super = function(x) return 0.88 + 0.22 * x - 0.28 * x * x end,
    turbo = function(x)
        if x < 0.18 then return 0.42 + x end
        if x < 0.42 then return 0.6 + (x - 0.18) / 0.24 * 0.4 end
        if x < 0.78 then return 1.0 end
        return 1.0 - (x - 0.78) * 0.9
    end,
    diesel = function(x)
        if x < 0.32 then return 0.55 + x * 1.4 end
        return 1.0 - (x - 0.32) * 0.75
    end,
    rotary = function(x) return 0.5 + 0.55 * x - 0.12 * x * x end,
    electric = function(x)
        if x < 0.35 then return 1.0 end
        return 0.35 / x
    end,
}
Handling.Curves = Curves

-- zwraca listę punktów { rpm, hp, tq } + wartości szczytowe
function Handling.Dyno(base, data, gtaMods, opts)
    opts = opts or {}
    local _, meta = Handling.Compute(base, data, gtaMods)
    local eng = Config.Engines[(data.swap or {}).engine or 'stock'] or {}
    local shape = eng.curve or ((gtaMods and gtaMods[18] and gtaMods[18] >= 0) and 'turbo' or 'na')
    local redline = eng.redline or 7000
    local fn = Curves[shape] or Curves.na

    local dtId = (data.swap or {}).drivetrain
    local bias = (Config.Drivetrains[dtId or 'stock'] or {}).bias or base.fDriveBiasFront or 0.0
    local loss = bias >= 0.95 and Config.DrivetrainLoss.fwd or (bias <= 0.05 and Config.DrivetrainLoss.rwd or Config.DrivetrainLoss.awd)

    -- znajdź max (t(x)*x), żeby szczyt mocy = meta.hp
    local peakShape = 0.0
    for i = 1, 60 do
        local x = i / 60
        local p = fn(x) * x
        if p > peakShape then peakShape = p end
    end

    local nitroMult = 1.0
    if opts.nitro and data.nitro and data.nitro.kit then
        local shot = Config.Nitro.shots[opts.nitro] or Config.Nitro.shots[1]
        nitroMult = shot.power
    end

    local misfire = 0.0
    local sp = data.parts and data.parts.spark_plugs or 100
    local mf = Config.Wear.parts.spark_plugs and Config.Wear.parts.spark_plugs.misfire or 0
    if sp < mf then misfire = (1.0 - sp / mf) * 0.08 end

    local pts, maxHp, maxTq, hpRpm, tqRpm = {}, 0.0, 0.0, 0, 0
    local steps = opts.steps or 48
    local seed = opts.seed or 1
    for i = 0, steps do
        local x = 0.12 + (i / steps) * 0.88
        local rpm = math.floor(redline * x)
        local shapeP = fn(x) * x / peakShape
        local hpCrank = meta.hp * shapeP * nitroMult
        if opts.noise then
            local n = math.sin((i + seed) * 12.9898) * 43758.5453
            n = n - math.floor(n)
            hpCrank = hpCrank * (1.0 + (n - 0.5) * 2.0 * opts.noise - (misfire > 0 and n * misfire or 0))
        end
        local whp = hpCrank * (1.0 - loss)
        local tq = (hpCrank * 7127.0) / math.max(rpm, 1)   -- Nm z KM
        pts[#pts + 1] = { rpm = rpm, hp = Utils.Round(hpCrank, 1), whp = Utils.Round(whp, 1), tq = Utils.Round(tq, 1) }
        if hpCrank > maxHp then maxHp, hpRpm = hpCrank, rpm end
        if tq > maxTq then maxTq, tqRpm = tq, rpm end
    end
    return {
        points = pts, redline = redline, shape = shape, loss = loss,
        maxHp = Utils.Round(maxHp, 1), maxWhp = Utils.Round(maxHp * (1.0 - loss), 1), maxTq = Utils.Round(maxTq, 1),
        hpRpm = hpRpm, tqRpm = tqRpm, stockHp = Utils.Round(meta.stockHp, 1),
    }
end
