Config = {}

-- ==========================================================================
--  OGÓLNE
-- ==========================================================================
Config.Debug = false               -- /dpcar_debug: wypisuje handling i stan pojazdu
Config.Units = 'kmh'               -- 'kmh' | 'mph'
Config.Hud = true                  -- mały pasek statusu przy minimapie (tylko gdy prowadzisz)
Config.Sounds = true               -- tykanie kierunkowskazów, gong pasów, piknięcia przełączników

-- Klawisze domyślne. Każdy gracz może je zmienić w:
-- Ustawienia → Przypisanie klawiszy → FiveM. Pusty string = brak domyślnego klawisza.
Config.Keys = {
    panel     = 'F7',        -- panel sterowania (myszka)
    mode      = 'Z',         -- następny tryb jazdy
    drive     = 'NUMPAD9',   -- przełącz napęd
    diff      = 'NUMPAD8',   -- blokada dyferencjału (kolejny poziom)
    low       = 'NUMPAD7',   -- reduktor
    tc        = 'NUMPAD6',   -- kontrola trakcji
    launch    = 'NUMPAD5',   -- uzbrój launch control
    susp      = 'NUMPAD4',   -- zawieszenie pneumatyczne (kolejny poziom)
    cruise    = 'NUMPAD1',   -- tempomat
    limiter   = 'NUMPAD2',   -- ogranicznik prędkości
    speedUp   = 'PAGEUP',    -- +krok tempomatu/ogranicznika
    speedDown = 'PAGEDOWN',  -- -krok tempomatu/ogranicznika
    indLeft   = 'LEFT',
    indRight  = 'RIGHT',
    hazard    = 'UP',
    belt      = 'B',
    engine    = '',          -- silnik on/off (domyślnie bez klawisza)
}

-- klasy pojazdów, których skrypt w ogóle nie obsługuje
-- 8 motocykle, 13 rowery, 14 łodzie, 15 helikoptery, 16 samoloty, 21 pociągi
Config.DisabledClasses = { [8] = true, [13] = true, [14] = true, [15] = true, [16] = true, [21] = true }

-- ==========================================================================
--  TRYBY JAZDY
--  Mnożniki odnoszą się do oryginalnego handlingu danego auta:
--    power    fInitialDriveForce        (moc)
--    inertia  fDriveInertia             (jak szybko wkręca się silnik)
--    shift    fClutchChangeRateScale*   (szybkość zmiany biegów)
--    steer    fSteeringLock             (kąt skrętu)
--    grip     fTractionCurveMax/Min     (przyczepność)
--    lowLoss  fLowSpeedTractionLossMult (buksowanie przy ruszaniu; więcej = więcej buksowania)
--    susp     fSuspensionForce          (twardość sprężyn)
--    damp     fSuspensionComp/ReboundDamp
--    antiroll fAntiRollBarForce         (stabilizatory)
--    brake    fBrakeForce
--  tc – domyślny poziom kontroli trakcji po wejściu w tryb ('on' | 'sport' | 'off')
-- ==========================================================================
Config.DefaultMode = 'comfort'
Config.ModeOrder = { 'eco', 'comfort', 'sport', 'sportplus', 'drift' }

Config.Modes = {
    eco = {
        label = 'ECO', color = '#3ddc84', tc = 'on',
        h = { power = 0.80, inertia = 0.80, shift = 0.75, steer = 1.00, grip = 1.00, lowLoss = 0.85,
              susp = 0.95, damp = 0.92, antiroll = 0.95, brake = 1.00 },
    },
    comfort = {
        label = 'KOMFORT', color = '#4ecdc4', tc = 'on',
        h = {}, -- oryginalny handling
    },
    sport = {
        label = 'SPORT', color = '#ffb020', tc = 'sport',
        h = { power = 1.07, inertia = 1.15, shift = 1.35, steer = 1.00, grip = 1.03, lowLoss = 1.00,
              susp = 1.12, damp = 1.15, antiroll = 1.20, brake = 1.05 },
    },
    sportplus = {
        label = 'SPORT+', color = '#ff5c5c', tc = 'off',
        h = { power = 1.12, inertia = 1.30, shift = 1.70, steer = 1.02, grip = 1.05, lowLoss = 1.05,
              susp = 1.22, damp = 1.28, antiroll = 1.35, brake = 1.08 },
    },
    drift = {
        label = 'DRIFT', color = '#c77dff', tc = 'off', forceDrive = 'RWD',
        h = { power = 1.10, inertia = 1.25, shift = 1.40, steer = 1.35, grip = 0.86, lowLoss = 1.35,
              susp = 1.10, damp = 1.10, antiroll = 1.40, brake = 1.00 },
    },
}

-- ==========================================================================
--  NAPĘD
-- ==========================================================================
Config.Drivetrain = {
    maxSwitchSpeed = 15,    -- [km/h] powyżej nie da się przełączyć napędu
    switchTime = 1200,      -- [ms] odcięcie mocy w trakcie przełączania
    awdBias = 0.40,         -- fDriveBiasFront w trybie AWD, jeśli auto fabrycznie nie jest AWD
}

-- ==========================================================================
--  BLOKADA DYFERENCJAŁU
--  Poziomy: 1 = tylny, 2 = tylny + centralny (wymusza AWD 50/50), 3 = wszystkie
-- ==========================================================================
Config.DiffLock = {
    maxSpeed = 40,          -- [km/h] powyżej blokady same się rozłączają
    engageSpeed = 25,       -- [km/h] powyżej nie da się ich włączyć
    disablesTC = true,      -- jak w prawdziwych terenówkach: blokada = TC/ESP off
    perLevel = {            -- efekt na każdy poziom blokady
        lowLoss = -0.22,    -- mniej buksowania
        offroadLoss = -0.18,-- fTractionLossMult – mniej utraty przyczepności w terenie
        steer = -0.05,      -- zablokowany most „pcha” auto prosto
        grip = 0.03,
    },
}

-- ==========================================================================
--  REDUKTOR (4L)
-- ==========================================================================
Config.LowRange = {
    engageSpeed = 5,        -- [km/h] reduktor włączysz tylko prawie stojąc
    maxSpeed = 55,          -- [km/h] twardy limit prędkości na reduktorze
    power = 1.35,           -- mnożnik fInitialDriveForce
    topSpeed = 0.42,        -- mnożnik fInitialDriveMaxFlatVel (krótsze przełożenia)
    forceAWD = true,        -- jeśli auto może mieć AWD, reduktor je wymusza
}

-- ==========================================================================
--  KONTROLA TRAKCJI
--  slip  – dopuszczalny poślizg kół napędowych (0.15 = 15% szybciej niż auto)
--  gain  – jak mocno odcinać moc ponad progiem
--  floor – minimalna moc przy interwencji
-- ==========================================================================
Config.TractionControl = {
    enabled = true,
    order = { 'on', 'sport', 'off' },
    levels = {
        on    = { label = 'TC',       slip = 0.12, gain = 3.0, floor = 0.25 },
        sport = { label = 'TC SPORT', slip = 0.35, gain = 1.8, floor = 0.45 },
        off   = { label = 'TC OFF' },
    },
    minSpeed = 1.0,         -- [m/s] poniżej liczymy poślizg względem 1 m/s
}

-- ==========================================================================
--  LAUNCH CONTROL
--  Uzbrój (klawisz lub panel) → stój, trzymaj hamulec + gaz → puść hamulec.
-- ==========================================================================
Config.Launch = {
    enabled = true,
    holdRpm = 0.72,         -- obroty trzymane na starcie
    boost = 1.22,           -- mnożnik momentu w fazie startu
    duration = 2600,        -- [ms] długość fazy startu
    slip = 0.10,            -- agresywna kontrola trakcji podczas startu
}

-- ==========================================================================
--  TEMPOMAT / OGRANICZNIK
-- ==========================================================================
Config.Cruise = {
    enabled = true,
    minSpeed = 30,          -- [km/h]
    step = 5,               -- [km/h] krok PAGEUP/PAGEDOWN
    gain = 0.12,            -- czułość regulatora gazu
}

Config.Limiter = {
    enabled = true,
    minSpeed = 20,          -- [km/h]
    step = 5,
}

-- ==========================================================================
--  ZAWIESZENIE PNEUMATYCZNE
--  height – wartość dla SetVehicleSuspensionHeight dodawana do fabrycznej
--           (dodatnia obniża, ujemna podnosi; widoczne dla wszystkich graczy)
-- ==========================================================================
Config.AirSuspension = {
    order = { 'low', 'normal', 'high', 'offroad' },
    levels = {
        low     = { label = 'NISKO',  height = 0.045, h = { susp = 1.18, damp = 1.15, antiroll = 1.20 } },
        normal  = { label = 'NORMAL', height = 0.0,   h = {} },
        high    = { label = 'WYSOKO', height = -0.045, h = { susp = 0.92, damp = 0.92, antiroll = 0.90 } },
        offroad = { label = 'TEREN',  height = -0.085, h = { susp = 0.85, damp = 0.85, antiroll = 0.80 } },
    },
    maxSpeed = { high = 90, offroad = 50 }, -- [km/h] powyżej auto samo zjeżdża do 'normal'
    changeSpeed = 60,       -- [km/h] powyżej nie da się zmienić poziomu ręcznie
}

-- ==========================================================================
--  KIERUNKOWSKAZY, PASY, SILNIK
-- ==========================================================================
Config.Indicators = {
    enabled = true,
    autoCancel = true,      -- gasną same po skręcie
    autoCancelAngle = 55,   -- [°] ile trzeba skręcić
}

Config.Seatbelt = {
    enabled = true,         -- wyłącz, jeśli masz pasy w innym skrypcie (HUD itp.)
    blockExit = true,       -- zapięty pas blokuje wysiadanie
    ejectSpeed = 90,        -- [km/h] minimalna prędkość przed zderzeniem
    ejectDrop = 0.45,       -- ułamek prędkości utraconej w ~100 ms, który uznajemy za wypadek
    ejectDamage = 25,       -- obrażenia przy wypadnięciu przez szybę
    chime = 20,             -- [km/h] gong niezapiętych pasów (0 = wył.)
}

Config.Engine = {
    enabled = true,
    keepRunningOnExit = true, -- wysiadając nie gasisz silnika
}

-- ==========================================================================
--  PROFILE POJAZDÓW
--  Co jest dostępne w danym aucie. Kolejność: DefaultProfile → ClassProfiles[klasa] → Vehicles[model]
--    modes    – dostępne tryby jazdy
--    drive    – dostępne napędy do przełączania (nil = napęd fabryczny, bez przełączania)
--    awdBias  – własny rozkład dla AWD (opcjonalnie)
--    diff     – maks. poziom blokady (0–3)
--    lowRange – reduktor
--    airSusp  – zawieszenie pneumatyczne
--    launch   – launch control
--
--  WAŻNE (ograniczenie silnika gry): koło dostanie moment tylko wtedy, gdy handling
--  auta w ogóle przewiduje napęd na tę oś. Aby auto mogło przełączać się między FWD, RWD
--  i AWD, ustaw mu w handling.meta fDriveBiasFront pomiędzy 0.1 a 0.9 (np. 0.5).
--  Fabrycznie AWD auta z GTA (sultan, kuruma, elegy, terenówki) działają od ręki.
-- ==========================================================================
Config.DefaultProfile = {
    modes = { 'eco', 'comfort', 'sport' },
    drive = nil,
    diff = 0,
    lowRange = false,
    airSusp = false,
    launch = false,
}

Config.ClassProfiles = {
    [2]  = { diff = 1 },                                                            -- SUV
    [4]  = { modes = { 'eco', 'comfort', 'sport', 'sportplus' }, launch = true },   -- muscle
    [5]  = { modes = { 'comfort', 'sport', 'sportplus' } },                         -- sport classic
    [6]  = { modes = { 'eco', 'comfort', 'sport', 'sportplus' }, launch = true },   -- sport
    [7]  = { modes = { 'eco', 'comfort', 'sport', 'sportplus' }, launch = true },   -- super
    [9]  = { diff = 2 },                                                            -- off-road
    [10] = { modes = { 'eco', 'comfort' } },                                        -- przemysłowe
    [11] = { modes = { 'eco', 'comfort' } },                                        -- użytkowe
    [17] = { modes = { 'eco', 'comfort' } },                                        -- usługi
    [18] = { modes = { 'comfort', 'sport' } },                                      -- służby
    [20] = { modes = { 'eco', 'comfort' } },                                        -- dostawcze
}

Config.Vehicles = {
    -- sportowe AWD z przełączaniem (drift w RWD)
    sultan    = { drive = { 'AWD', 'RWD' }, modes = { 'eco', 'comfort', 'sport', 'sportplus', 'drift' } },
    sultanrs  = { drive = { 'AWD', 'RWD', 'FWD' }, modes = { 'eco', 'comfort', 'sport', 'sportplus', 'drift' } },
    sultan2   = { drive = { 'AWD', 'RWD' }, modes = { 'eco', 'comfort', 'sport', 'sportplus', 'drift' }, launch = true },
    kuruma    = { drive = { 'AWD', 'RWD' }, modes = { 'eco', 'comfort', 'sport', 'sportplus', 'drift' } },
    elegy     = { drive = { 'AWD', 'RWD' }, modes = { 'eco', 'comfort', 'sport', 'sportplus', 'drift' } },
    elegy2    = { drive = { 'AWD', 'RWD' }, modes = { 'eco', 'comfort', 'sport', 'sportplus', 'drift' } },
    jester4   = { drive = { 'AWD', 'RWD' }, modes = { 'eco', 'comfort', 'sport', 'sportplus', 'drift' } },
    comet6    = { drive = { 'AWD', 'RWD' }, modes = { 'eco', 'comfort', 'sport', 'sportplus', 'drift' } },

    -- RWD do driftu
    futo      = { modes = { 'comfort', 'sport', 'drift' } },
    futo2     = { modes = { 'comfort', 'sport', 'drift' } },
    zr350     = { modes = { 'comfort', 'sport', 'sportplus', 'drift' }, launch = true },
    remus     = { modes = { 'comfort', 'sport', 'sportplus', 'drift' } },
    euros     = { modes = { 'comfort', 'sport', 'sportplus', 'drift' } },

    -- terenówki: pełne blokady + reduktor
    sandking  = { drive = { 'RWD', 'AWD' }, diff = 3, lowRange = true, airSusp = true },
    sandking2 = { drive = { 'RWD', 'AWD' }, diff = 3, lowRange = true, airSusp = true },
    dubsta3   = { drive = { 'RWD', 'AWD' }, diff = 3, lowRange = true },
    mesa3     = { drive = { 'RWD', 'AWD' }, diff = 3, lowRange = true },
    kamacho   = { drive = { 'RWD', 'AWD' }, diff = 3, lowRange = true, airSusp = true },
    rebel2    = { drive = { 'RWD', 'AWD' }, diff = 2, lowRange = true },
    everon    = { drive = { 'RWD', 'AWD' }, diff = 3, lowRange = true, airSusp = true },
    caracara2 = { drive = { 'RWD', 'AWD' }, diff = 3, lowRange = true, airSusp = true },
    yosemite3 = { drive = { 'RWD', 'AWD' }, diff = 2, lowRange = true, airSusp = true },
    winky     = { drive = { 'RWD', 'AWD' }, diff = 3, lowRange = true },
    vetir     = { drive = { 'RWD', 'AWD' }, diff = 3, lowRange = true },

    -- luksusowe SUV-y z pneumatyką
    baller7   = { drive = { 'AWD', 'RWD' }, diff = 1, airSusp = true, modes = { 'eco', 'comfort', 'sport' } },
    rebla     = { drive = { 'AWD', 'RWD' }, diff = 1, airSusp = true, modes = { 'eco', 'comfort', 'sport', 'sportplus' } },
    toros     = { drive = { 'AWD', 'RWD' }, diff = 1, airSusp = true, modes = { 'eco', 'comfort', 'sport', 'sportplus' }, launch = true },
    granger2  = { drive = { 'AWD', 'RWD' }, diff = 2, lowRange = true, airSusp = true },
}
