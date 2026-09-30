-- ==========================================================================
--  SWAPY: silniki, napędy, hamulce, skrzynie biegów + NITRO
--  Montowane na stanowisku swapów (swapStation) – jak każda część: szafka → montaż.
-- ==========================================================================

-- Moc w swapach jest ABSOLUTNA (hp), a nie „mnożnik”: W16 w małym hatchbacku daje ogromny
-- przyrost, a R4 w hiperaucie – spadek. Moc fabryczna auta liczona jest z handlingu:
--   hp ≈ fInitialDriveForce * fMass * Config.HpFactor
-- Prędkość maks. rośnie z pierwiastkiem 3. stopnia ze stosunku mocy (jak w fizyce oporu powietrza).
Config.HpFactor = 1.0
Config.DrivetrainLoss = { fwd = 0.12, rwd = 0.15, awd = 0.20 }  -- straty napędu na hamowni (WHP)

--  curve: kształt krzywej momentu na hamowni i charakter jazdy
--    'na'       – wolnossący: moc rośnie do wysokich obrotów
--    'turbo'    – płaski moment w średnich obrotach + turbodziura (lag)
--    'super'    – kompresor: moment od dołu, liniowo
--    'diesel'   – ogromny moment nisko, szybko gaśnie
--    'rotary'   – wankel: bardzo wysokie obroty, mały moment
--    'electric' – pełny moment od 0, spada przy wysokich obrotach
--  sound: nazwa dźwięku silnika GTA (nazwa modelu) lub dźwięku addon (np. z paczki dźwięków)
Config.Engines = {
    stock = { label = 'Fabryczny', price = 0, labor = 0 },
    i4_na = {
        label = 'R4 2.0 wolnossący', hp = 190, redline = 7800, curve = 'na', cylinders = 4,
        sound = 'blista', price = 9000, labor = 8, revs = 1.05,
    },
    i4_turbo = {
        label = 'R4 2.0 Turbo', hp = 330, redline = 7200, curve = 'turbo', cylinders = 4, turbo = true,
        sound = 'sultan', price = 16000, labor = 9, revs = 1.0, lag = 0.6,
    },
    i6_turbo = {
        label = 'R6 3.0 Twin-Turbo', hp = 480, redline = 7000, curve = 'turbo', cylinders = 6, turbo = true,
        sound = 'jester', price = 28000, labor = 10, revs = 1.0, lag = 0.5,
    },
    v6_twin = {
        label = 'V6 3.8 Twin-Turbo', hp = 560, redline = 7100, curve = 'turbo', cylinders = 6, turbo = true,
        sound = 'carbonizzare', price = 34000, labor = 10, revs = 1.02, lag = 0.4,
    },
    rotary = {
        label = 'Wankel 13B Twin-Rotor', hp = 280, redline = 9000, curve = 'rotary', cylinders = 2,
        sound = 'zr350', fallback = 'futo', price = 21000, labor = 9, revs = 1.18,
    },
    v8_muscle = {
        label = 'V8 6.2 OHV (muscle)', hp = 460, redline = 6300, curve = 'super', cylinders = 8,
        sound = 'dominator', price = 26000, labor = 11, revs = 0.94,
    },
    v8_super = {
        label = 'V8 6.2 z kompresorem', hp = 720, redline = 6600, curve = 'super', cylinders = 8,
        sound = 'gauntlet', price = 48000, labor = 12, revs = 0.96,
    },
    v8_twin = {
        label = 'V8 4.0 Twin-Turbo (hyper)', hp = 800, redline = 8200, curve = 'turbo', cylinders = 8, turbo = true,
        sound = 'zentorno', price = 72000, labor = 12, revs = 1.06, lag = 0.35,
    },
    v10 = {
        label = 'V10 5.2 wolnossący', hp = 640, redline = 8700, curve = 'na', cylinders = 10,
        sound = 'infernus', price = 68000, labor = 12, revs = 1.12,
    },
    v12 = {
        label = 'V12 6.5 wolnossący', hp = 780, redline = 9000, curve = 'na', cylinders = 12,
        sound = 'nero', price = 95000, labor = 14, revs = 1.10,
    },
    w16 = {
        label = 'W16 8.0 Quad-Turbo', hp = 1500, redline = 6800, curve = 'turbo', cylinders = 16, turbo = true,
        sound = 'adder', price = 240000, labor = 16, revs = 0.98, lag = 0.45,
    },
    diesel = {
        label = 'R6 3.0 Diesel Biturbo', hp = 340, redline = 4800, curve = 'diesel', cylinders = 6, turbo = true,
        sound = 'sandking', price = 18000, labor = 10, revs = 0.85, lag = 0.7,
    },
    electric = {
        label = 'Silnik elektryczny 2x (AWD)', hp = 650, redline = 16000, curve = 'electric', cylinders = 0,
        sound = 'voltic', price = 85000, labor = 10, revs = 1.3, gears = 1,
    },
}

Config.Drivetrains = {
    stock = { label = 'Fabryczny', price = 0, labor = 0 },
    fwd   = { label = 'Przedni (FWD)', bias = 1.0, price = 6000, labor = 6, effects = { lowSpeedLoss = 1.05 } },
    rwd   = { label = 'Tylny (RWD)', bias = 0.0, price = 6000, labor = 6, effects = {} },
    awd_rear = { label = 'AWD 30/70 (tylnonapędowy charakter)', bias = 0.3, price = 14000, labor = 8, effects = { lowSpeedLoss = 0.85 } },
    awd   = { label = 'AWD 50/50', bias = 0.5, price = 14000, labor = 8, effects = { lowSpeedLoss = 0.75, tractionLoss = 0.9 } },
    awd_front = { label = 'AWD 60/40 (Haldex)', bias = 0.6, price = 12000, labor = 8, effects = { lowSpeedLoss = 0.82 } },
}

Config.BrakeKits = {
    stock   = { label = 'Fabryczne', price = 0, labor = 0 },
    sport   = { label = 'Sportowe (nawiercane + klocki sport)', price = 3200, labor = 2.5, effects = { brake = 1.18 } },
    bbk     = { label = 'Big Brake Kit 6-tłoczkowy', price = 7800, labor = 3.5, effects = { brake = 1.42, brakeBias = 0.62 } },
    ceramic = { label = 'Karbonowo-ceramiczne', price = 16000, labor = 3.5, effects = { brake = 1.7, brakeBias = 0.6 } },
    rally   = { label = 'Hydrauliczny ręczny (rally/drift)', price = 2400, labor = 2.0, effects = { handbrake = 1.7 } },
}

Config.Gearboxes = {
    stock = { label = 'Fabryczna', price = 0, labor = 0 },
    m5    = { label = '5-biegowa krótka (close ratio)', price = 4500, labor = 5, effects = { gears = 5, shift = 1.1, power = 1.03, topspeed = 0.97 } },
    m6    = { label = '6-biegowa manualna', price = 6500, labor = 5, effects = { gears = 6, shift = 1.1 } },
    dct7  = { label = '7-biegowa dwusprzęgłowa (DCT)', price = 14000, labor = 6, effects = { gears = 7, shift = 2.0 } },
    seq6  = { label = 'Sekwencyjna 6-biegowa (dog-box)', price = 22000, labor = 6, effects = { gears = 6, shift = 2.8, power = 1.02 } },
}

-- ==========================================================================
--  NITRO (N2O) – własny system
--  - uzbrojenie (N), podanie (LSHIFT – trzymaj), purge (B), zmiana dyszy (PAGEUP)
--  - ciśnienie butli: zimna butla = słabszy strzał; podgrzewacz (kit pro) utrzymuje ciśnienie
--  - linia „zapowietrzona” po dłuższym postoju: pierwszy strzał słabszy, dopóki nie zrobisz purge
--  - za niskie obroty / zużyte świece / brak mapy ECU przy dużej dyszy = ryzyko uszkodzenia silnika
-- ==========================================================================
Config.Nitro = {
    enabled = true,
    kits = {
        nos_single = { label = 'N2O – pojedyncza butla 5 lb', capacity = 100, purge = false, heater = false, maxShot = 2, price = 6500, labor = 3 },
        nos_dual   = { label = 'N2O – podwójna butla 2×5 lb + purge', capacity = 200, purge = true, heater = false, maxShot = 3, price = 12500, labor = 4 },
        nos_pro    = { label = 'N2O PRO – 2×10 lb, podgrzewacz, progresja', capacity = 320, purge = true, heater = true, maxShot = 3, progressive = true, price = 24000, labor = 5 },
    },
    shots = {
        { label = '50 shot',  power = 1.30, use = 5.5 },   -- use: jednostek butli na sekundę
        { label = '100 shot', power = 1.55, use = 9.0 },
        { label = '150 shot', power = 1.85, use = 13.0 },
    },
    refillPrice = 600,        -- cena napełnienia pełnej butli (proporcjonalnie)
    pressure = { ideal = 950, min = 500, max = 1150, coldPower = 0.65, heaterRate = 12, coolRate = 1.2, usageDrop = 18 },
    lineColdAfter = 45,       -- s bez podania = linia wymaga purge
    lineColdPower = 0.6,      -- moc pierwszych sekund bez purge
    lineColdTime = 1.4,
    minRpm = 0.45,            -- poniżej (0-1) – strzał w dolot / ryzyko
    minSpeed = 15.0,          -- km/h
    damageChance = 0.06,      -- szansa/s na uszkodzenie silnika w złych warunkach
    damageAmount = 120.0,     -- ile „zdrowia” silnika zabiera
    topSpeedBoost = 1.12,     -- mnożnik prędkości maks. podczas podania
    screenEffect = true,
    exhaustFlames = true,
}
