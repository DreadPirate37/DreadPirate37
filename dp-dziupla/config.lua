Config = {}

-- ==========================================================================
--  OGÓLNE
-- ==========================================================================
Config.Debug = false               -- komenda /dziupla_pos, dodatkowe logi w konsoli
Config.Framework = 'auto'          -- 'auto' | 'esx' | 'qb' | 'qbx' | 'standalone'
Config.UseTarget = true            -- ox_target / qb-target dla NPC i punktów, jeśli są uruchomione
Config.PayAccount = 'cash'         -- na jakie konto idą pieniądze z dziupli ('cash' | 'bank' | 'black_money' dla ESX)
Config.ShopAccount = 'cash'        -- z jakiego konta płaci się za narzędzia

Config.Job = {
    required = false,              -- true = tylko gracze z pracą z listy (np. gang)
    names = { 'chopshop', 'dziupla', 'mechanic' },
    blocked = { 'police', 'sheriff', 'lspd', 'bcso' }, -- tym pracom dziupla się nie otworzy
}

Config.Police = {
    jobs = { 'police', 'sheriff', 'lspd', 'bcso' },
    minForContracts = 0,           -- ilu policjantów musi być na służbie, żeby brać zlecenia kradzieży
    minForChop = 0,                -- ...żeby w ogóle rozbierać auta
}

-- ==========================================================================
--  DZIUPLE (lokacje) – sprawdź koordynaty na swojej mapie!  /dziupla_pos (Debug)
--  Z w punktach jest dociągane do gruntu, ale X/Y muszą być sensowne.
-- ==========================================================================
Config.Shops = {
    {
        key = 'lapuerta',
        label = 'Dziupla – złomowisko La Puerta',
        blip = { sprite = 380, color = 1, scale = 0.7, show = false }, -- show=false: tajna lokacja
        center = vec3(-555.0, -1695.0, 19.1),
        radius = 60.0,
        laptop = vec4(-560.2, -1703.4, 19.2, 30.0),       -- biurko z laptopem (ChopNet)
        fence = vec4(-562.4, -1701.8, 19.1, 300.0),        -- paser (NPC)
        fencePed = 'g_m_m_armboss_01',
        shelf = vec3(-547.6, -1703.9, 19.2),               -- regał: tu odkłada się zdjęte części
        bench = vec4(-551.4, -1706.8, 19.2, 210.0),        -- stół warsztatowy (regeneracja)
        tyre = vec4(-545.1, -1700.2, 19.2, 120.0),         -- montażownica (koło -> felga + opona)
        crusher = vec3(-532.0, -1683.0, 19.1),             -- prasa / zgniatarka
        gate = vec3(-549.9, -1688.4, 19.4),                -- przełącznik bramy (hałas!)
        bays = {                                           -- stanowiska rozbiórki (z podnośnikiem)
            vec4(-557.8, -1689.8, 19.1, 210.0),
            vec4(-551.6, -1693.9, 19.1, 210.0),
        },
        vinBay = vec4(-542.9, -1695.6, 19.1, 210.0),       -- stanowisko przebitki VIN i lakierni
        tow = vec4(-538.4, -1706.2, 19.1, 300.0),          -- wypożyczenie lawety (spawn)
    },
    {
        key = 'sandy',
        label = 'Dziupla – złom Sandy Shores',
        blip = { sprite = 380, color = 1, scale = 0.7, show = false },
        center = vec3(2340.0, 3136.0, 48.2),
        radius = 60.0,
        laptop = vec4(2348.4, 3131.2, 48.2, 80.0),
        fence = vec4(2350.1, 3133.6, 48.2, 120.0),
        fencePed = 'a_m_m_hillbilly_01',
        shelf = vec3(2344.6, 3124.9, 48.2),
        bench = vec4(2338.9, 3122.8, 48.2, 170.0),
        tyre = vec4(2333.4, 3126.1, 48.2, 170.0),
        crusher = vec3(2360.2, 3120.6, 48.2),
        gate = vec3(2331.8, 3141.5, 48.4),
        bays = {
            vec4(2334.9, 3137.1, 48.2, 80.0),
            vec4(2341.5, 3141.9, 48.2, 80.0),
        },
        vinBay = nil,                                       -- ta dziupla nie ma lakierni
    },
}

Config.Bay = {
    radius = 3.2,                  -- jak blisko środka stanowiska musi stać auto
    lift = { 0.0, 0.55, 1.75 },    -- wysokości podnośnika [m]: 0 = ziemia, 1 = do kół, 2 = pod podwozie
    liftTime = 3500,               -- ms na zmianę poziomu
    maxJobAge = 3 * 3600,          -- po tylu sekundach porzucona rozbiórka jest sprzątana
}

-- ==========================================================================
--  PROGRESJA
-- ==========================================================================
Config.Levels = {
    { xp = 0,     label = 'Złomiarz' },
    { xp = 300,   label = 'Pomocnik' },
    { xp = 800,   label = 'Rozbieracz' },
    { xp = 1600,  label = 'Mechanik z dziupli' },
    { xp = 2800,  label = 'Specjalista od części' },
    { xp = 4500,  label = 'Majster' },
    { xp = 7000,  label = 'Zawodowiec' },
    { xp = 10000, label = 'Szef warsztatu' },
    { xp = 14000, label = 'Król dziupli' },
    { xp = 20000, label = 'Legenda półświatka' },
}
Config.PerkPointsPerLevel = 1
Config.PerkResetPrice = 5000

-- Umiejętności (drzewko). Efekty są liczone w shared/logic.lua (Logic.Perk)
Config.Perks = {
    speed    = { label = 'Szybkie ręce',   ranks = 3, minLevel = 1, desc = '+12% szybkości odkręcania na rangę' },
    steady   = { label = 'Pewna ręka',     ranks = 2, minLevel = 2, desc = '-30% ryzyka zerwania gwintu, pęknięcia klipsa i ukręcenia śruby na rangę' },
    quiet    = { label = 'Cichociemny',    ranks = 2, minLevel = 2, desc = '-25% hałasu narzędzi na rangę' },
    trader   = { label = 'Negocjator',     ranks = 3, minLevel = 3, desc = '+5% do cen u pasera i w zamówieniach na rangę' },
    eye      = { label = 'Oko fachowca',   ranks = 1, minLevel = 3, desc = 'Widzisz stan i wycenę części oraz rozmiary śrub bez mierzenia; +4% stanu części' },
    restorer = { label = 'Złota rączka',   ranks = 2, minLevel = 4, desc = '+10 pkt maks. regeneracji części na rangę' },
    thief    = { label = 'Włamywacz',      ranks = 2, minLevel = 4, desc = 'Szersza linia ścinania w zamkach, -35% szansy na alarm na rangę' },
    tech     = { label = 'Elektronik',     ranks = 1, minLevel = 5, desc = 'Szybsze szukanie nadajników, o połowę mniejsze szkody od zwarć' },
    mule     = { label = 'Tragarz',        ranks = 1, minLevel = 5, desc = 'Noszenie części bez spowolnienia' },
    contacts = { label = 'Kontakty',       ranks = 2, minLevel = 6, desc = '+1 zlecenie w ofercie i +10% premii za zlecenia na rangę' },
}

-- ==========================================================================
--  NARZĘDZIA, MATERIAŁY EKSPLOATACYJNE, ULEPSZENIA (sklep w ChopNecie)
-- ==========================================================================
Config.Tools = {
    ratchet  = { label = 'Grzechotka z nasadkami',      price = 0,    minLevel = 1, starter = true, icon = 'ratchet' },
    screw    = { label = 'Wkrętaki PH / Torx',          price = 0,    minLevel = 1, starter = true, icon = 'screw' },
    trim     = { label = 'Łyżki do tapicerki',          price = 0,    minLevel = 1, starter = true, icon = 'trim' },
    basin    = { label = 'Miska na płyny',              price = 0,    minLevel = 1, starter = true, icon = 'basin' },
    pliers   = { label = 'Szczypce do opasek',          price = 180,  minLevel = 1, icon = 'pliers' },
    drill    = { label = 'Wiertarka (do wykrętaków)',   price = 650,  minLevel = 1, icon = 'drill' },
    grinder  = { label = 'Szlifierka kątowa',           price = 900,  minLevel = 2, icon = 'grinder' },
    wire     = { label = 'Struna do wycinania szyb',    price = 450,  minLevel = 2, icon = 'wire' },
    jack     = { label = 'Lewarek (kradzież kół na ulicy)', price = 350, minLevel = 1, icon = 'jack' },
    impact   = { label = 'Klucz udarowy',               price = 2600, minLevel = 3, icon = 'impact' },
    hoist    = { label = 'Żuraw warsztatowy',           price = 4200, minLevel = 3, icon = 'hoist' },
    scanner  = { label = 'Skaner nadajników GPS',       price = 3200, minLevel = 4, icon = 'scanner' },
    tyretool = { label = 'Montażownica do opon',        price = 2400, minLevel = 3, icon = 'tyre' },
    stamps   = { label = 'Zestaw puncerów (przebitka)', price = 6500, minLevel = 6, icon = 'stamps' },
}

Config.Consumables = {
    penetrant = { label = 'Penetrant (odrdzewiacz)', price = 35,  max = 20, start = 3 },
    disc      = { label = 'Tarcza do szlifierki',    price = 25,  max = 30, start = 0 },
    extractor = { label = 'Wykrętak do śrub',        price = 45,  max = 20, start = 2 },
    lockpick  = { label = 'Wytrych',                 price = 120, max = 10, start = 2 },
}

Config.Upgrades = {
    shelf = { label = 'Dodatkowy regał (+10 miejsc w magazynie)', price = 2500, max = 5 },
}

-- Ekwipunek: 'auto' (ox_inventory, jeśli jest uruchomiony) | 'ox' | 'internal'
-- W trybie ox części to itemy z metadanymi (stan, auto, regeneracja) w prywatnym stashu gracza
-- przy regale, a materiały eksploatacyjne to zwykłe itemy w ekwipunku. Itemy: install/ox_items.lua
Config.Inventory = {
    mode = 'auto',
    partItem = 'dz_part',
    stashLabel = 'Magazyn dziupli',
    stashWeight = 5000000,         -- gramy (5 t – silniki i złom też się zmieszczą)
    images = false,                -- true = metadata.image = 'dz_<typ>' (wrzuć własne ikony do ox_inventory/web/images)
    items = {                      -- nazwy itemów materiałów (lockpick zwykle już istnieje na serwerze)
        lockpick = 'lockpick',
        penetrant = 'dz_penetrant',
        disc = 'dz_disc',
        extractor = 'dz_extractor',
    },
}

Config.Warehouse = {
    baseSlots = 25,
    perShelf = 10,
}

-- ==========================================================================
--  EKONOMIA
-- ==========================================================================
Config.Economy = {
    priceMult = 1.0,               -- globalny mnożnik wszystkich cen części
    scrapPerKg = 0.6,              -- skup złomu ($/kg) – dla zniszczonych części i karoserii
    condCurve = 1.3,               -- wartość = 0.15 + 0.85 * (stan/100)^condCurve
}

-- mnożniki wartości według klasy pojazdu (GetVehicleClass); false = klasa zablokowana
Config.ClassMult = {
    [0] = 0.80,  -- Compacts
    [1] = 0.90,  -- Sedans
    [2] = 1.05,  -- SUVs
    [3] = 1.10,  -- Coupes
    [4] = 1.10,  -- Muscle
    [5] = 1.40,  -- Sports Classics
    [6] = 1.35,  -- Sports
    [7] = 1.90,  -- Super
    [8] = false, -- Motorcycles
    [9] = 1.00,  -- Off-road
    [10] = false, [11] = 0.80, [12] = 0.85, [13] = false, [14] = false, [15] = false,
    [16] = false, [17] = false, [18] = false, [19] = false, [20] = 0.90, [21] = false,
    [22] = 1.60, -- Open wheel
}
Config.ClassLabels = {
    [0] = 'Kompakt', [1] = 'Sedan', [2] = 'SUV', [3] = 'Coupe', [4] = 'Muscle', [5] = 'Sport klasyk',
    [6] = 'Sportowe', [7] = 'Super', [9] = 'Terenowe', [11] = 'Użytkowe', [12] = 'Van', [20] = 'Ciężarowe', [22] = 'Open wheel',
}
-- wybrane modele mogą mieć własny mnożnik (nadpisuje klasę)
Config.ModelMult = {
    -- adder = 2.2, t20 = 2.1,
}
-- modele, których nie da się rozebrać (np. auta służbowe)
Config.BlacklistModels = { 'police', 'police2', 'police3', 'police4', 'policet', 'sheriff', 'sheriff2', 'ambulance', 'firetruk', 'fbi', 'fbi2', 'riot' }

-- Rynek części: popyt kategorii rośnie i spada w zależności od sprzedaży na serwerze
Config.Market = {
    min = 0.55, max = 1.5,
    saturation = 12000,            -- ile $ sprzedaży w kategorii zbija popyt o 1.0
    recoverPerMin = 0.012,         -- powrót do bazowego popytu na minutę
    historyEvery = 10,             -- co ile minut zapisywać punkt historii (wykres w ChopNecie)
    eventChance = 0.25,            -- szansa na wydarzenie rynkowe co godzinę
    events = {
        { cat = 'exhaust',  mult = 1.45, label = 'Boom na katalizatory – skupy płacą jak za zboże' },
        { cat = 'wheels',   mult = 1.35, label = 'Sezon na felgi – wszyscy tuningują' },
        { cat = 'electro',  mult = 1.40, label = 'Braki w elektronice – sterowniki i radia rozchwytywane' },
        { cat = 'engine',   mult = 1.30, label = 'Zlecenie hurtowe na silniki od zagranicznego kontrahenta' },
        { cat = 'body',     mult = 1.30, label = 'Blacharze z Vespucci wykupują karoserię' },
        { cat = 'interior', mult = 1.35, label = 'Import foteli kubełkowych się zatrzymał' },
    },
}

Config.Categories = {
    body     = 'Karoseria',
    lights   = 'Oświetlenie',
    wheels   = 'Koła i zawieszenie',
    engine   = 'Silnik i napęd',
    electro  = 'Elektronika',
    interior = 'Wnętrze',
    exhaust  = 'Układ wydechowy',
    glass    = 'Szyby',
    scrap    = 'Złom',
}

Config.Fence = {
    mult = 1.0,                    -- paser płaci wartość części × to
}

-- ==========================================================================
--  HAŁAS (jak w Thief Simulator) – szlifierka i klucz udarowy przy otwartej bramie
--  mogą ściągnąć zgłoszenie od sąsiadów
-- ==========================================================================
Config.Noise = {
    gateClosedMult = 0.3,          -- zamknięta brama tłumi hałas
    decayPerSec = 0.012,           -- tyle „hałasu” ubywa na sekundę
    threshold = 1.5,               -- powyżej tego progu każde kolejne hałasowanie może wezwać policję (≈6 s szlifierki przy otwartej bramie)
    alertChance = 0.35,
    alertCooldown = 300,           -- sekundy między zgłoszeniami z jednej dziupli
}

-- ==========================================================================
--  ZLECENIA KRADZIEŻY („lista życzeń”)
-- ==========================================================================
Config.Contracts = {
    count = 3,
    refresh = 900,                 -- sekundy do odświeżenia oferty
    deadline = { 1800, 2700 },     -- czas na realizację [s]
    spawnDistance = 220.0,         -- auto pojawia się, gdy gracz podjedzie tak blisko
    areaRadius = 140.0,            -- promień obszaru poszukiwań na mapie
    tiers = {
        { minLevel = 1, reward = { 600, 900 },    xp = 60,  alarm = 0.30, tracker = 0.00, pins = 4,
          models = { 'asea', 'premier', 'ingot', 'emperor', 'stanier', 'primo', 'blista', 'issi2', 'prairie' } },
        { minLevel = 3, reward = { 1200, 1800 },  xp = 110, alarm = 0.50, tracker = 0.25, pins = 5,
          models = { 'sultan', 'buffalo', 'fugitive', 'schafter2', 'tailgater', 'oracle', 'felon', 'jackal', 'dominator', 'baller' } },
        { minLevel = 5, reward = { 2400, 3400 },  xp = 180, alarm = 0.70, tracker = 0.50, pins = 6,
          models = { 'comet2', 'carbonizzare', 'feltzer2', 'banshee', 'jester', 'massacro', 'ninef', 'elegy2', 'coquette' } },
        { minLevel = 7, reward = { 4500, 6500 },  xp = 300, alarm = 0.90, tracker = 0.80, pins = 7,
          models = { 'zentorno', 'adder', 't20', 'osiris', 'entityxf', 'turismor', 'cheetah', 'infernus' } },
    },
    -- miejsca parkowania aut na zlecenie (heading = kierunek auta)
    spots = {
        vec4(-340.5, -757.3, 33.97, 270.0),
        vec4(229.5, -800.5, 30.6, 160.0),
        vec4(-1183.3, -1495.4, 4.38, 125.0),
        vec4(1143.1, -787.2, 57.6, 90.0),
        vec4(-1622.4, 16.6, 62.1, 330.0),
        vec4(-805.0, -1310.0, 5.0, 170.0),
        vec4(372.4, 285.0, 103.1, 250.0),
        vec4(-2044.9, -468.4, 11.4, 320.0),
        vec4(-1316.4, -928.3, 11.3, 110.0),
        vec4(-712.0, -150.0, 37.3, 120.0),
        vec4(282.0, -335.0, 44.9, 250.0),
        vec4(1195.0, -1286.0, 34.9, 175.0),
        vec4(-1488.3, -378.9, 40.2, 135.0),
        vec4(-47.6, -1116.4, 26.4, 0.0),
    },
    smashAlarm = true,             -- wybicie szyby zawsze włącza alarm
}

-- Tylko auta zespawnowane przez skrypt (zlecenia + auta „na mieście”) można rozebrać,
-- zgnieść, wyeksportować i przebić. false = każde auto NPC (auta graczy i tak są blokowane).
Config.OnlyScriptVehicles = true

-- Auta „na mieście”: skrypt trzyma kilka zamkniętych aut do kradzieży bez zlecenia.
-- Gracze szukają ich sami albo kupują cynk (przybliżone miejsce) w ChopNecie.
Config.StreetTargets = {
    enabled = true,
    count = 6,                     -- ile aut stoi naraz na mapie
    checkEvery = 60,               -- co ile sekund uzupełniać pulę
    lifetime = 2700,               -- po tylu sekundach nieruszone auto jest przestawiane
    clearRadius = 90.0,            -- nie spawnuj/usuwaj, gdy gracz jest bliżej niż tyle
    tierWeights = { 50, 30, 15, 5 }, -- szansa na poziom auta (jak w Config.Contracts.tiers)
    tipPrice = { 150, 300, 600, 1200 }, -- cena cynku według poziomu auta
    spots = {
        vec4(-1044.3, -1476.2, 5.0, 305.0),
        vec4(-592.6, -1122.4, 22.2, 180.0),
        vec4(152.9, -1036.9, 29.3, 340.0),
        vec4(441.3, -1021.6, 28.6, 90.0),
        vec4(1164.8, -1648.6, 36.9, 30.0),
        vec4(-1464.1, -916.2, 10.1, 50.0),
        vec4(-247.3, 6211.6, 31.5, 45.0),
        vec4(1696.4, 3595.2, 35.4, 210.0),
        vec4(-1609.1, -1027.9, 13.0, 50.0),
        vec4(809.4, -812.3, 26.2, 90.0),
        vec4(-1236.4, -331.3, 37.4, 25.0),
        vec4(-73.3, -592.3, 36.3, 70.0),
        vec4(930.3, -1553.8, 30.7, 90.0),
        vec4(-330.8, -1426.2, 30.3, 270.0),
    },
}

-- Kradzież części z aut na ulicy (tylko auta ze skryptu): koła, katalizator, tablica
Config.StreetStrip = {
    enabled = true,
    wheelTool = 'jack',            -- koła wymagają lewarka
    alarmOnStart = true,           -- zamknięte auto może zawyć, gdy zaczniesz przy nim grzebać
    noiseAlert = 0.5,              -- szansa na zgłoszenie = hałas × to (szlifierka na ulicy!)
    idleEnd = 600,                 -- po tylu sekundach bez pracy auto wraca do normalnego stanu
}

-- Laweta: wciąganie aut ze skryptu bez odpalania (zamknięte też – ale może zawyć alarm)
Config.Tow = {
    enabled = true,
    model = 'flatbed',
    deposit = 750,
    attach = vec3(0.0, -2.2, 1.1),  -- pozycja auta na platformie względem lawety
    loadTime = 7000,
    maxDist = 9.0,                  -- jak daleko za lawetą może stać auto
}

-- Nadajnik GPS w droższych autach: dopóki go nie znajdziesz i nie wyrwiesz, policja dostaje namiar
Config.Tracker = {
    interval = 45,                 -- co ile sekund leci namiar do dispatchu
    firstDelay = 20,
    spots = {                      -- możliwe kryjówki nadajnika (nazwy dla skanera)
        'Zderzak przedni', 'Nadkole LP', 'Nadkole PT', 'Pod fotelem kierowcy', 'Gniazdo OBD',
        'Podsufitka', 'Bagażnik – koło zapasowe', 'Zderzak tylny', 'Komora silnika', 'Pod kanapą',
    },
}

-- ==========================================================================
--  ZAMÓWIENIA KLIENTÓW (części z magazynu dowożone do punktu odbioru)
-- ==========================================================================
Config.Orders = {
    count = 3,
    refresh = 600,
    deadline = 2400,
    payMult = { 1.5, 1.9 },        -- zamówienia płacą więcej niż paser
    ambushChance = 0.12,           -- szansa, że przy odbiorze kręci się policja (dispatch)
    drops = {
        vec4(-1147.0, -1564.0, 4.4, 35.0),
        vec4(389.6, -908.2, 29.4, 270.0),
        vec4(1213.0, -1389.0, 35.4, 180.0),
        vec4(153.1, -3084.6, 5.9, 90.0),
        vec4(861.3, -2182.0, 30.4, 175.0),
        vec4(-71.5, -1826.3, 26.9, 230.0),
        vec4(706.6, -967.4, 30.4, 90.0),
        vec4(-1488.3, -378.9, 40.2, 135.0),
    },
}

-- ==========================================================================
--  EKSPORT (całe auto do kontenera w porcie)
-- ==========================================================================
Config.Export = {
    count = 2,
    refresh = 1200,
    deadline = 1800,
    minHealth = 0.7,               -- minimalny stan auta (karoseria i silnik)
    dispatchChance = 0.35,
    minLevel = 2,
    points = {
        vec4(1234.6, -3239.7, 5.9, 0.0),
        vec4(-297.4, -2658.3, 6.0, 45.0),
    },
    -- bazowa kwota według klasy, mnożona przez stan auta
    base = { [0] = 2200, [1] = 2600, [2] = 3200, [3] = 3400, [4] = 3500, [5] = 5200, [6] = 5600, [7] = 9500, [9] = 3000, [12] = 2400, [22] = 8000 },
}

-- ==========================================================================
--  PRZEBITKA VIN + LAKIERNIA
-- ==========================================================================
Config.Revin = {
    minLevel = 6,
    papersPrice = 1500,            -- fałszywe papiery (podnoszą cenę i obniżają ryzyko)
    paintPrice = 400,
    dealer = vec4(-40.8, -1671.3, 29.5, 140.0), -- handlarz używanymi autami
    dealerPed = 's_m_m_autoshop_01',
    value = { [0] = 3500, [1] = 4200, [2] = 5200, [3] = 5500, [4] = 5600, [5] = 8200, [6] = 8800, [7] = 15000, [9] = 5000, [12] = 3800, [22] = 12000 },
    papersMult = 1.35,
    allowKeep = false,             -- true = gracz może zatrzymać auto (server/hooks.lua -> Hooks.GiveVehicle)
    detectBelow = 0.6,             -- poniżej tej jakości przebitki handlarz może zadzwonić po policję
    plateFormat = '%d%d%s%s%s%d%d%d', -- 2 cyfry, 3 litery, 3 cyfry
    colors = {                     -- indeksy kolorów GTA do wyboru w lakierni
        { 0, 'Czarny' }, { 111, 'Biały' }, { 4, 'Srebrny' }, { 27, 'Czerwony' }, { 64, 'Niebieski' },
        { 53, 'Zielony' }, { 88, 'Żółty' }, { 38, 'Pomarańczowy' }, { 71, 'Fioletowy' }, { 96, 'Brązowy' },
        { 12, 'Czarny mat' }, { 131, 'Biały mat' }, { 158, 'Złoty' }, { 117, 'Szczotkowana stal' },
    },
}

-- ==========================================================================
--  ZGNIATARKA
-- ==========================================================================
Config.Crusher = {
    kgBase = { [0] = 900, [1] = 1200, [2] = 1800, [3] = 1200, [4] = 1400, [5] = 1100, [6] = 1150, [7] = 1250, [9] = 1700, [11] = 2000, [12] = 1900, [20] = 3500, [22] = 700 },
    time = 9000,
    xp = 15,
}

-- ==========================================================================
--  EKIPA (crew)
-- ==========================================================================
Config.Crew = {
    enabled = true,
    createPrice = 25000,
    minLevel = 3,
    maxMembers = 8,
    cut = 0.10,                    -- 10% każdego zarobku członka trafia do kasy ekipy
    sharedWarehouse = true,        -- członkowie mają wspólny magazyn (i wspólne regały)
    levels = { 0, 500, 1500, 3500, 7000 }, -- XP ekipy (1 XP za każde 100$ zarobku członków)
    pricePerLevel = 0.03,          -- +3% do cen za każdy poziom ekipy powyżej 1
}

-- ==========================================================================
--  NALOTY POLICJI (heat dziupli)
-- ==========================================================================
Config.Raid = {
    enabled = true,
    perCar = 8,                    -- heat za każde auto wstawione na stanowisko
    perPart = 0.4,                 -- heat za każdą zdjętą część
    perAlert = 15,                 -- heat za zgłoszenie (hałas, alarm w okolicy)
    decayPerHour = 12,
    threshold = 100,               -- od tego poziomu możliwa obława
    chance = 0.35,                 -- szansa na obławę przy każdym sprawdzeniu (co 5 min) powyżej progu
    minPolice = 2,                 -- obława tylko, gdy jest tylu policjantów
    warning = 90,                  -- sekundy od ostrzeżenia do wejścia policji
    lockdown = 900,                -- ile sekund dziupla jest zamknięta (nie da się sprzedawać ani rozbierać)
    hotTime = 1800,                -- część jest „gorąca” (dowód) przez tyle sekund od zdjęcia
    searchRadius = 5.0,            -- policjant przeszukuje regał z tej odległości
    rewardPerPart = 150,           -- nagroda dla policjanta za zabezpieczoną część
    maxSeize = 12,                 -- maks. części zabezpieczonych u jednej osoby
    bribe = { price = 6000, amount = 40, cooldown = 3600 }, -- łapówka: -40 heat raz na godzinę
}

-- ==========================================================================
--  LOGI NA DISCORD (webhook – najlepiej przez convar: set dziupla_webhook "https://...")
-- ==========================================================================
Config.Logs = {
    webhook = '',
    name = 'Dziupla',
    events = {
        earn = true,        -- każda wypłata (paser, zamówienie, eksport, handlarz, zgniatarka, zlecenie)
        chop = true,        -- auto wstawione na stanowisko / przebitkę
        part = false,       -- każda zdjęta część (dużo wiadomości)
        suspicious = true,  -- odrzucone wyniki, podejrzane akcje
        police = true,      -- zgłoszenia do policji (hałas, alarm, nadajnik, handlarz)
        shop = false,       -- zakupy w sklepie
    },
}

-- ==========================================================================
--  ZABEZPIECZENIA
-- ==========================================================================
Config.Security = {
    maxDistance = 9.0,             -- max odległość gracza od auta przy starcie/końcu demontażu
    perFastener = 0.35,            -- min. sekund na element złączny
    partBase = 1.5,                -- + tyle sekund na część
    maxPartSeconds = 900,
    lockpickMin = 3,
    scannerMin = 4,
    benchMin = 5,
}

-- ==========================================================================
--  ANIMACJE, REKWIZYTY, MARKERY
-- ==========================================================================
Config.Anim = {
    stand  = { dict = 'mini@repair', clip = 'fixing_a_ped' },
    kneel  = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer' },
    under  = { dict = 'amb@prop_human_movie_bulb@base', clip = 'base' },
    creeper = { dict = 'amb@world_human_vehicle_mechanic@male@base', clip = 'base' },
    inside = { dict = 'mini@repair', clip = 'fixing_a_player' },
    carry  = { dict = 'anim@heists@box_carry@', clip = 'idle' },
    laptop = { scenario = 'PROP_HUMAN_SEAT_COMPUTER' },
    lockpick = { dict = 'missheistfbisetup1', clip = 'hassle_intro_loop_f' },
    smash  = { dict = 'melee@unarmed@streamed_variations', clip = 'plyr_takedown_front_elbow' },
    bench  = { dict = 'mini@repair', clip = 'fixing_a_ped' },
    scan   = { dict = 'amb@world_human_stand_mobile@male@text@base', clip = 'base' },
    drop   = { dict = 'anim@heists@narcotics@trash', clip = 'drop_front' },
}

-- Rekwizyty w dziupli (lokalne obiekty; nieistniejące modele są pomijane)
Config.Props = {
    enabled = true,
    bench = 'prop_tool_bench02',
    tyre = 'prop_compressor_03',
    table = 'prop_table_03',
    tableHeight = 0.78,
    laptop = 'prop_laptop_01a',
    shelf = 'prop_ff_shelves_01',
    shelfParts = true,             -- ostatnie części z magazynu leżą na regale
    shelfLevels = { 0.45, 1.05, 1.6 },
    hoist = 'prop_engine_hoist',
    basin = 'prop_oilcan_01a',
    bay = {                        -- przy każdym stanowisku (off = w prawo / do przodu względem stanowiska)
        { model = 'prop_toolchest_05', off = vec2(2.6, 0.8), h = 270.0 },
        { model = 'prop_worklight_03b', off = vec2(-2.6, 2.2), h = 120.0 },
        { model = 'prop_carjack', off = vec2(2.4, -1.6), h = 0.0 },
    },
    crusher = { 'prop_rub_carwreck_3', 'prop_rub_carwreck_2' },
}

Config.Marker = {
    available = { 255, 176, 32, 190 },
    blocked   = { 120, 120, 120, 120 },
    busy      = { 255, 70, 70, 190 },
    done      = { 60, 220, 130, 120 },
    size = 0.045,
}

Config.Blips = {
    contractArea = { sprite = 9, color = 1, alpha = 90 },
    contractCar  = { sprite = 225, color = 1, scale = 0.8 },
    drop         = { sprite = 478, color = 5, scale = 0.8 },
    export       = { sprite = 410, color = 3, scale = 0.8 },
    dealer       = { sprite = 225, color = 2, scale = 0.8 },
}
