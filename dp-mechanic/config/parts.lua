-- ==========================================================================
--  CZĘŚCI: eksploatacja (zużycie), części osiągowe, opony
--
--  Statystyki (klucze w "fx"/"effects") mapowane na handling pojazdu:
--    power        – fInitialDriveForce        (moc/przyspieszenie, mnożnik)
--    topspeed     – fInitialDriveMaxFlatVel   (prędkość maks., mnożnik)
--    revs         – fDriveInertia             (szybkość wkręcania się na obroty, mnożnik)
--    shift        – fClutchChangeRateScale*   (szybkość zmiany biegów, mnożnik)
--    gears        – nInitialDriveGears        (liczba biegów, wartość)
--    bias         – fDriveBiasFront           (0.0 = RWD, 1.0 = FWD, pomiędzy = AWD, wartość)
--    brake        – fBrakeForce               (mnożnik)
--    brakeBias    – fBrakeBiasFront           (wartość)
--    handbrake    – fHandBrakeForce           (mnożnik)
--    grip         – fTractionCurveMax         (przyczepność maks., mnożnik)
--    gripMin      – fTractionCurveMin         (przyczepność w poślizgu, mnożnik)
--    lateral      – fTractionCurveLateral     (mnożnik)
--    tractionLoss – fTractionLossMult         (utrata przyczepności na złej nawierzchni, mnożnik)
--    lowSpeedLoss – fLowSpeedTractionLossMult (buksowanie przy ruszaniu, mnożnik)
--    susForce     – fSuspensionForce          (twardość sprężyn, mnożnik)
--    susDamp      – fSuspensionComp/ReboundDamp (tłumienie, mnożnik)
--    susRaise     – fSuspensionRaise          (wysokość, dodawane w metrach)
--    antiroll     – fAntiRollBarForce         (stabilizatory, mnożnik)
--    steer        – fSteeringLock             (kąt skrętu, mnożnik)
--    engineDmg    – fEngineDamageMult         (podatność silnika na uszkodzenia, mnożnik)
-- ==========================================================================

-- --------------------------------------------------------------------------
--  ZUŻYCIE / EKSPLOATACJA
--  lifeKm   – po ilu km część spada do 0% (przy normalnej jeździe)
--  stress   – grupa obciążenia: eng (wysokie obroty), brk (hamowanie), tyr (poślizg),
--             clu (ruszanie/zmiany), sus (wstrząsy), nil = tylko kilometry
--  fx       – { stat, próg%, mnożnik przy 0% } – poniżej progu efekt narasta liniowo
--  lift     – wymagany podnośnik do wymiany: 'ramp' | 'arms' | nil
--  anchor   – miejsce montażu (preset kamery/poświaty z config/assembly.lua)
-- --------------------------------------------------------------------------
Config.Wear = {
    enabled = true,
    syncInterval = 30,       -- s – co ile klient-kierowca raportuje przebieg
    kmMultiplier = 1.0,      -- globalny mnożnik zużycia (2.0 = wszystko zużywa się 2x szybciej)
    maxKmPerSync = 3.5,      -- anty-cheat: maks. km na jedną synchronizację
    stressMax = 3.0,         -- maks. mnożnik obciążenia (agresywna jazda)
    warnDashboard = true,    -- kontrolki na HUD kierowcy
    engineDamageAtZero = true,

    serviceInterval = 15000, -- km – przegląd okresowy (olej, filtry, kontrola)
    inspectionDays = 30,     -- dni ważności przeglądu technicznego

    parts = {
        oil = {
            label = 'Olej silnikowy', lifeKm = 10000, stress = 'eng', price = 180, labor = 0.5,
            lift = 'ramp', anchor = 'under_engine', cabinet = 'wear',
            fx = { { 'revs', 25, 0.93 }, { 'engineDmg', 25, 2.5 } },
            warn = 20, icon = 'oil', code = 'P0520',
        },
        oil_filter = {
            label = 'Filtr oleju', lifeKm = 10000, stress = 'eng', price = 60, labor = 0.2,
            lift = 'ramp', anchor = 'under_engine', cabinet = 'wear',
            fx = { { 'engineDmg', 20, 1.6 } },
            warn = 15, code = 'P0521',
        },
        air_filter = {
            label = 'Filtr powietrza', lifeKm = 20000, price = 70, labor = 0.2,
            anchor = 'engine', cabinet = 'wear',
            fx = { { 'power', 40, 0.90 } },
            warn = 15, code = 'P0101',
        },
        spark_plugs = {
            label = 'Świece zapłonowe', lifeKm = 30000, stress = 'eng', price = 160, labor = 0.6,
            anchor = 'engine', cabinet = 'wear',
            fx = { { 'power', 30, 0.88 } },
            misfire = 25,        -- poniżej % – wypadanie zapłonów (szarpanie)
            warn = 20, code = 'P0300',
        },
        timing_belt = {
            label = 'Rozrząd (pasek + rolki)', lifeKm = 90000, stress = 'eng', price = 900, labor = 3.0,
            anchor = 'engine', cabinet = 'engine',
            fx = { { 'power', 15, 0.95 } },
            failAtZero = true,   -- zerwany pasek = silnik nie odpali
            warn = 10, code = 'P0016',
        },
        coolant = {
            label = 'Płyn chłodniczy', lifeKm = 40000, price = 90, labor = 0.4,
            anchor = 'engine', cabinet = 'wear',
            fx = { { 'engineDmg', 30, 2.0 } },
            overheat = 20,       -- poniżej % – przegrzewanie przy obciążeniu
            warn = 20, code = 'P0217',
        },
        battery = {
            label = 'Akumulator', lifeKm = 60000, price = 350, labor = 0.3,
            anchor = 'engine', cabinet = 'wear',
            fx = {},
            noStart = 25,        -- poniżej % – szansa, że auto nie odpali
            warn = 20, code = 'P0562',
        },
        brake_pads = {
            label = 'Klocki hamulcowe', lifeKm = 30000, stress = 'brk', price = 240, labor = 0.8,
            lift = 'arms', anchor = 'wheel', cabinet = 'wear',
            fx = { { 'brake', 35, 0.45 } },
            squeal = 20,
            warn = 20, code = 'C1234',
        },
        brake_discs = {
            label = 'Tarcze hamulcowe', lifeKm = 70000, stress = 'brk', price = 520, labor = 1.2,
            lift = 'arms', anchor = 'wheel', cabinet = 'wear',
            fx = { { 'brake', 25, 0.75 } },
            judder = 30,         -- poniżej % – bicie tarcz przy hamowaniu
            warn = 15, code = 'C1235',
        },
        brake_fluid = {
            label = 'Płyn hamulcowy', lifeKm = 40000, price = 80, labor = 0.4,
            anchor = 'engine', cabinet = 'wear',
            fx = { { 'brake', 30, 0.80 } },
            warn = 20, code = 'C1150',
        },
        clutch = {
            label = 'Sprzęgło', lifeKm = 120000, stress = 'clu', price = 1200, labor = 4.0,
            lift = 'ramp', anchor = 'under_gearbox', cabinet = 'engine',
            fx = { { 'shift', 35, 0.55 }, { 'power', 20, 0.85 } },
            slip = 20,           -- poniżej % – buksowanie sprzęgła
            warn = 15, code = 'P0806',
        },
        gearbox_oil = {
            label = 'Olej skrzyni biegów', lifeKm = 60000, price = 150, labor = 0.6,
            lift = 'ramp', anchor = 'under_gearbox', cabinet = 'wear',
            fx = { { 'shift', 30, 0.75 } },
            warn = 15, code = 'P0711',
        },
        shocks = {
            label = 'Amortyzatory', lifeKm = 80000, stress = 'sus', price = 800, labor = 2.0,
            lift = 'arms', anchor = 'wheel', cabinet = 'perf',
            fx = { { 'susDamp', 45, 0.45 }, { 'antiroll', 30, 0.75 }, { 'grip', 25, 0.95 } },
            warn = 20, code = 'C1510',
        },
    },
}

-- --------------------------------------------------------------------------
--  GEOMETRIA (zbieżność) – psuje się od uderzeń; auto ściąga na bok
-- --------------------------------------------------------------------------
Config.Alignment = {
    enabled = true,
    impactThreshold = 22.0,  -- m/s² nagłego wyhamowania od uderzenia, żeby rozstroić geometrię
    maxBias = 0.12,          -- maks. ściąganie kierownicy
    perImpact = 0.025,
    price = 250, labor = 0.8, lift = 'arms',
    warn = 0.03,
}

-- --------------------------------------------------------------------------
--  OPONY – mieszanki
--  life – km do zdarcia bieżnika (8 mm → 0 mm), prawna granica 1.6 mm
-- --------------------------------------------------------------------------
Config.TireCompounds = {
    street = {
        label = 'Uliczne (standard)', price = 180, life = 45000,
        effects = {},
        color = '#9aa3ad',
    },
    sport = {
        label = 'Sportowe', price = 320, life = 30000,
        effects = { grip = 1.06, lateral = 0.96, lowSpeedLoss = 0.92 },
        color = '#f5b942',
    },
    semi = {
        label = 'Półslick (R-compound)', price = 520, life = 16000,
        effects = { grip = 1.12, gripMin = 1.06, lateral = 0.93, lowSpeedLoss = 0.85, tractionLoss = 1.25 },
        color = '#ff7a1a',
    },
    slick = {
        label = 'Slick torowy', price = 880, life = 7000,
        effects = { grip = 1.20, gripMin = 1.10, lateral = 0.90, lowSpeedLoss = 0.78, tractionLoss = 1.8 },
        color = '#e5484d',
    },
    drift = {
        label = 'Driftowe (twarda mieszanka)', price = 260, life = 20000,
        effects = { grip = 0.86, gripMin = 0.80, lateral = 1.18, lowSpeedLoss = 1.25 },
        color = '#a78bfa',
    },
    offroad = {
        label = 'Terenowe A/T', price = 400, life = 50000,
        effects = { grip = 0.94, tractionLoss = 0.55, lowSpeedLoss = 0.9 },
        color = '#65a30d',
    },
    winter = {
        label = 'Zimowe', price = 300, life = 35000,
        effects = { grip = 0.95, tractionLoss = 0.7, lowSpeedLoss = 0.85 },
        color = '#60a5fa',
    },
}
Config.TireNewTread = 8.0      -- mm
Config.TireLegalTread = 1.6    -- mm – poniżej: ostrzeżenie i słaba przyczepność
Config.TireTreadGrip = { at = 3.0, min = 0.72 }  -- poniżej 3 mm przyczepność spada do 72% przy 0 mm
Config.TireBurstAtZero = true  -- łysa opona może pęknąć
Config.RimPrice = 450          -- cena felgi (za sztukę) przy zmianie felg

-- niewyważenie kół – wibracje na kierownicy w zakresie prędkości
Config.Imbalance = {
    enabled = true,
    speedFrom = 70, speedTo = 140,   -- km/h – rezonans
    gramsForMax = 60,                -- przy takim niewyważeniu wibracje są maksymalne
    tireWearMult = 0.5,              -- +50% zużycia opony przy maks. niewyważeniu
}

-- --------------------------------------------------------------------------
--  CZĘŚCI OSIĄGOWE (poza GTA-modami) – montowane w menu tuningu (zakładka Osiągi)
--  levels[n] = { label, price, labor, effects }
-- --------------------------------------------------------------------------
Config.PerfParts = {
    ecu = {
        label = 'Chip / mapa ECU', group = 'Silnik', anchor = 'engine', cabinet = 'perf', icon = 'chip',
        levels = {
            { label = 'Stage 1', price = 1800, labor = 1.0, effects = { power = 1.05, revs = 1.02 } },
            { label = 'Stage 2', price = 3600, labor = 1.5, effects = { power = 1.09, revs = 1.04, engineDmg = 1.10 } },
            { label = 'Stage 3', price = 6500, labor = 2.0, effects = { power = 1.14, revs = 1.06, engineDmg = 1.25 } },
        },
        wearMult = { 1.05, 1.15, 1.3 },   -- szybsze zużycie części z grupy 'eng'
    },
    intake = {
        label = 'Dolot (cold air intake)', group = 'Silnik', anchor = 'engine', cabinet = 'perf', icon = 'air',
        levels = {
            { label = 'Sportowy filtr stożkowy', price = 900, labor = 0.6, effects = { power = 1.02 } },
            { label = 'Zimny dolot CAI', price = 1900, labor = 1.0, effects = { power = 1.04, revs = 1.01 } },
        },
    },
    exhaust_sys = {
        label = 'Układ wydechowy', group = 'Silnik', anchor = 'under_exhaust', lift = 'ramp', cabinet = 'perf', icon = 'exhaust',
        levels = {
            { label = 'Cat-back', price = 1400, labor = 1.2, effects = { power = 1.02 } },
            { label = 'Downpipe + cat-back', price = 2800, labor = 2.0, effects = { power = 1.04, revs = 1.02 } },
            { label = 'Pełny wydech wyczynowy (strzały)', price = 5200, labor = 2.5, effects = { power = 1.06, revs = 1.03 }, pops = true },
        },
    },
    intercooler = {
        label = 'Intercooler', group = 'Silnik', anchor = 'front', cabinet = 'perf', icon = 'cool',
        levels = {
            { label = 'Powiększony', price = 1600, labor = 1.5, effects = { power = 1.03 } },
            { label = 'Front-mount wyczynowy', price = 3100, labor = 2.0, effects = { power = 1.05, engineDmg = 0.9 } },
        },
    },
    camshaft = {
        label = 'Wałki rozrządu', group = 'Silnik', anchor = 'engine', cabinet = 'engine', icon = 'cam',
        levels = {
            { label = 'Sportowe', price = 2400, labor = 3.0, effects = { power = 1.04, revs = 1.04 } },
            { label = 'Wyczynowe (ostre)', price = 4800, labor = 3.5, effects = { power = 1.08, revs = 1.08, lowSpeedLoss = 0.95 } },
        },
    },
    flywheel = {
        label = 'Koło zamachowe', group = 'Napęd', anchor = 'under_gearbox', lift = 'ramp', cabinet = 'engine', icon = 'gear',
        levels = {
            { label = 'Odciążone', price = 1300, labor = 3.0, effects = { revs = 1.08 } },
            { label = 'Jednomasowe aluminiowe', price = 2600, labor = 3.0, effects = { revs = 1.16 } },
        },
    },
    clutch_kit = {
        label = 'Sprzęgło sportowe', group = 'Napęd', anchor = 'under_gearbox', lift = 'ramp', cabinet = 'engine', icon = 'gear',
        levels = {
            { label = 'Wzmocnione', price = 1800, labor = 4.0, effects = { shift = 1.25 } },
            { label = 'Wyczynowe ceramiczne', price = 3800, labor = 4.0, effects = { shift = 1.65, lowSpeedLoss = 1.05 } },
        },
    },
    lsd = {
        label = 'Szpera (LSD)', group = 'Napęd', anchor = 'under_rear', lift = 'ramp', cabinet = 'perf', icon = 'diff',
        levels = {
            { label = 'Szpera 1-way', price = 2200, labor = 2.5, effects = { tractionLoss = 0.92, lowSpeedLoss = 0.88, grip = 1.02 } },
            { label = 'Szpera 2-way (drift)', price = 3400, labor = 2.5, effects = { tractionLoss = 0.85, lowSpeedLoss = 1.10, lateral = 1.05 } },
        },
    },
    coilovers = {
        label = 'Gwint (coilovery)', group = 'Zawieszenie', anchor = 'wheel', lift = 'arms', cabinet = 'perf', icon = 'spring',
        levels = {
            { label = 'Uliczny', price = 2600, labor = 3.0, effects = { susForce = 1.12, susDamp = 1.15, antiroll = 1.1, susRaise = -0.02, grip = 1.02 } },
            { label = 'Torowy (regulowany)', price = 5200, labor = 3.5, effects = { susForce = 1.28, susDamp = 1.35, antiroll = 1.2, susRaise = -0.04, grip = 1.04 } },
        },
    },
    swaybars = {
        label = 'Stabilizatory', group = 'Zawieszenie', anchor = 'under_front', lift = 'ramp', cabinet = 'perf', icon = 'bar',
        levels = {
            { label = 'Wzmocnione', price = 900, labor = 1.5, effects = { antiroll = 1.25 } },
            { label = 'Regulowane wyczynowe', price = 1800, labor = 1.5, effects = { antiroll = 1.5, tractionLoss = 1.05 } },
        },
    },
    steering = {
        label = 'Kąt skrętu (angle kit)', group = 'Zawieszenie', anchor = 'wheel', lift = 'arms', cabinet = 'perf', icon = 'wheel',
        levels = {
            { label = 'Zwiększony kąt', price = 1600, labor = 2.0, effects = { steer = 1.2 } },
            { label = 'Angle kit driftowy', price = 3600, labor = 2.5, effects = { steer = 1.45, lateral = 1.04 } },
        },
    },
    weight = {
        label = 'Odchudzanie', group = 'Nadwozie', anchor = 'interior', cabinet = 'body', icon = 'weight',
        levels = {
            { label = 'Usunięcie wygłuszeń', price = 800, labor = 2.0, effects = { power = 1.02, brake = 1.02 } },
            { label = 'Fotele kubełkowe + lekkie szyby', price = 2600, labor = 3.0, effects = { power = 1.04, brake = 1.04, grip = 1.01 } },
            { label = 'Karbon + pełny strip', price = 6200, labor = 5.0, effects = { power = 1.07, brake = 1.07, grip = 1.02 } },
        },
    },
}
