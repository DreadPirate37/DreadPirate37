-- ==========================================================================
--  dp-pojazdy – handling: zapis oryginału, przeliczenie, nałożenie, przywrócenie
--  SetVehicleHandlingFloat działa per-pojazd, ale zmiany robimy tylko u kierowcy
--  (to on liczy fizykę) i cofamy je, gdy przestaje prowadzić.
-- ==========================================================================
Handling = {
    powered = {},     -- indeksy kół napędzanych (dla kontroli trakcji)
}
local H = Handling

local CLASS = 'CHandlingData'

-- pole handlingu → klucz mnożnika z configu
local FIELDS = {
    { 'fInitialDriveForce',              'power' },
    { 'fDriveInertia',                   'inertia' },
    { 'fClutchChangeRateScaleUpShift',   'shift' },
    { 'fClutchChangeRateScaleDownShift', 'shift' },
    { 'fInitialDriveMaxFlatVel',         'topSpeed' },
    { 'fSteeringLock',                   'steer' },
    { 'fTractionCurveMax',               'grip' },
    { 'fTractionCurveMin',               'grip' },
    { 'fLowSpeedTractionLossMult',       'lowLoss' },
    { 'fTractionLossMult',               'offroadLoss' },
    { 'fSuspensionForce',                'susp' },
    { 'fSuspensionCompDamp',             'damp' },
    { 'fSuspensionReboundDamp',          'damp' },
    { 'fAntiRollBarForce',               'antiroll' },
    { 'fBrakeForce',                     'brake' },
}

local orig, origVeh, origPowered, origBias = nil, 0, nil, nil

local function capture(veh)
    orig = {}
    for i = 1, #FIELDS do
        local f = FIELDS[i][1]
        orig[f] = GetVehicleHandlingFloat(veh, CLASS, f)
    end
    origBias = GetVehicleHandlingFloat(veh, CLASS, 'fDriveBiasFront')
    origPowered = {}
    for w = 0, GetVehicleNumberOfWheels(veh) - 1 do
        origPowered[w] = GetVehicleWheelIsPowered(veh, w)
    end
    origVeh = veh
    Car.Dbg(('handling zapisany: moc %.3f, bias %.2f, koła %d'):format(orig.fInitialDriveForce, origBias, #origPowered + 1))
end

local function newMult()
    return { power = 1.0, inertia = 1.0, shift = 1.0, topSpeed = 1.0, steer = 1.0, grip = 1.0, lowLoss = 1.0,
             offroadLoss = 1.0, susp = 1.0, damp = 1.0, antiroll = 1.0, brake = 1.0 }
end

local function mulInto(m, src)
    if not src then return end
    for k, v in pairs(src) do
        if m[k] then m[k] = m[k] * v end
    end
end

function H.Compute(state, profile)
    local m = newMult()
    mulInto(m, Config.Modes[state.mode].h)

    if profile.airSusp then
        local lvl = Config.AirSuspension.levels[state.susp]
        if lvl then mulInto(m, lvl.h) end
    end

    if state.diff > 0 then
        local pl, d = Config.DiffLock.perLevel, state.diff
        m.lowLoss     = m.lowLoss     * math.max(0.1, 1.0 + pl.lowLoss * d)
        m.offroadLoss = m.offroadLoss * math.max(0.1, 1.0 + pl.offroadLoss * d)
        m.steer       = m.steer       * math.max(0.5, 1.0 + pl.steer * d)
        m.grip        = m.grip        * (1.0 + pl.grip * d)
    end

    if state.low then
        m.power    = m.power * Config.LowRange.power
        m.topSpeed = m.topSpeed * Config.LowRange.topSpeed
        m.shift    = m.shift * 0.8
    end
    return m
end

local function isFront(w) return w < 2 end  -- 0 = LP, 1 = PP; reszta to tył (także środkowe osie)

local function applyDrive(veh, drive, state, profile)
    local wheels = GetVehicleNumberOfWheels(veh)
    local powered = {}

    if not drive then
        -- napęd fabryczny
        local bias = origBias
        if state.diff >= 2 and bias > 0.01 and bias < 0.99 then bias = math.max(bias, 0.5) end
        SetVehicleHandlingFloat(veh, CLASS, 'fDriveBiasFront', bias)
        return bias, nil
    end

    -- oś, która fabrycznie nie ma napędu, dostaje moment dopiero po podniesieniu biasu
    local bias = origBias
    if drive == 'FWD' then
        if bias < 0.1 then bias = 1.0 end
    elseif drive == 'AWD' then
        if profile.awdBias then
            bias = profile.awdBias
        elseif bias < 0.1 then
            bias = Config.Drivetrain.awdBias
        end
        if state.diff >= 2 then bias = math.max(bias, 0.5) end
    end
    SetVehicleHandlingFloat(veh, CLASS, 'fDriveBiasFront', bias)

    for w = 0, wheels - 1 do
        local on = drive == 'AWD' or (drive == 'FWD' and isFront(w)) or (drive == 'RWD' and not isFront(w))
        powered[w] = on
    end
    return bias, powered
end

function H.Apply(veh, state, profile)
    if not DoesEntityExist(veh) or not state or not profile then return end
    if origVeh ~= veh then capture(veh) end

    local m = H.Compute(state, profile)
    for i = 1, #FIELDS do
        local f, key = FIELDS[i][1], FIELDS[i][2]
        SetVehicleHandlingFloat(veh, CLASS, f, orig[f] * m[key])
    end

    local drive = Car.EffectiveDrive()
    local _, powered = applyDrive(veh, drive, state, profile)

    -- przeładowanie skrzyni: bez tego zmiany mocy/przełożeń/napędu nie wchodzą w życie
    ModifyVehicleTopSpeed(veh, 0.0)

    -- flagi kół ustawiamy PO przeładowaniu, bo ono potrafi je nadpisać
    local list = {}
    for w = 0, GetVehicleNumberOfWheels(veh) - 1 do
        local on
        if powered then on = powered[w] else on = origPowered[w] end
        SetVehicleWheelIsPowered(veh, w, on and true or false)
        if on then list[#list + 1] = w end
    end
    H.powered = list
end

function H.Restore()
    local veh = origVeh
    if veh ~= 0 and orig and DoesEntityExist(veh) then
        for i = 1, #FIELDS do
            local f = FIELDS[i][1]
            SetVehicleHandlingFloat(veh, CLASS, f, orig[f])
        end
        SetVehicleHandlingFloat(veh, CLASS, 'fDriveBiasFront', origBias)
        ModifyVehicleTopSpeed(veh, 0.0)
        for w, on in pairs(origPowered) do
            SetVehicleWheelIsPowered(veh, w, on)
        end
        Car.Dbg('handling przywrócony')
    end
    orig, origVeh, origPowered, origBias = nil, 0, nil, nil
    H.powered = {}
end

function H.OriginalBias() return origBias end

function H.Debug(veh)
    if not DoesEntityExist(veh) then return end
    print('^3[dp-pojazdy] handling pojazdu^7')
    for i = 1, #FIELDS do
        local f = FIELDS[i][1]
        print(('  %-34s %8.4f  (oryg. %s)'):format(f, GetVehicleHandlingFloat(veh, CLASS, f), orig and ('%.4f'):format(orig[f]) or '-'))
    end
    print(('  %-34s %8.4f'):format('fDriveBiasFront', GetVehicleHandlingFloat(veh, CLASS, 'fDriveBiasFront')))
    for w = 0, GetVehicleNumberOfWheels(veh) - 1 do
        print(('  koło %d napędzane: %s'):format(w, tostring(GetVehicleWheelIsPowered(veh, w))))
    end
end
