Config = {}

-- ==========================================================================
--  OGÓLNE
-- ==========================================================================
Config.Debug = false               -- komendy /wlm_punkt, /wlm_dom, rysowanie pokoi i punktów, logi
Config.Locale = 'pl'               -- 'pl' | 'en'
Config.Framework = 'auto'          -- 'auto' | 'esx' | 'qb' | 'qbx' | 'standalone'
Config.Inventory = 'auto'          -- 'auto' | 'ox' | 'qb' | 'qs' | 'esx' | 'none'
Config.UseTarget = true            -- ox_target / qb-target jeśli uruchomione, inaczej własne [E]
Config.Dispatch = 'auto'           -- 'auto' | 'ps' | 'cd' | 'core' | 'qs' | 'rcore' | 'builtin'
Config.RequireItems = true         -- false = narzędzia nie są wymagane (test / standalone bez ekwipunku)

-- skąd brać porę dnia gry: 'client' (zegar gracza, który wchodzi) albo własna funkcja w server/core.lua
Config.GameTime = 'client'

Config.Keys = {
    signals = 'Z',                 -- koło sygnałów ekipy (EKI-07)
    flashlight = 'H',              -- latarka
    slots = { '1', '2', '3', '4' },-- pasek narzędzi: lornetka, latarka, rękawiczki, laptop (NAR-33)
    laptop = '',                   -- /wlm_laptop – przypisz w ustawieniach FiveM
}

-- ==========================================================================
--  POLICJA I OGRANICZENIA (POL-02, POL-16, POL-18)
-- ==========================================================================
Config.Police = {
    jobs = { 'police', 'sheriff', 'lspd', 'bcso' },
    emsJobs = { 'ambulance', 'ems' },
    minOnline = 2,                 -- minimum policjantów na służbie, żeby zacząć włamanie
    dutyCooldown = 15,             -- [min] blokada po zejściu ze służby policji/EMS
    eta = {                        -- [s] czas dojazdu policji wg dzielnicy (skaluje się liczbą policjantów)
        default = 150, city = 110, hills = 90, rich = 80, sandy = 210, paleto = 240,
    },
    heatMax = 100,                 -- przy tym heacie gracz nie zacznie kolejnego włamania
}

Config.Cooldowns = {
    house = 3 * 3600,              -- [s] po włamaniu dom odpoczywa
    player = 8 * 60,               -- [s] między włamaniami jednego gracza
    maxActive = 6,                 -- ile włamań naraz na serwer
    sessionTimeout = 25 * 60,      -- [s] po tym czasie sesja jest zamykana
}

Config.Rotation = {
    active = 10,                   -- ile domów jest celami naraz (DOM-16)
    every = 3 * 3600,              -- [s] rotacja puli
}

-- ==========================================================================
--  HAŁAS I WIDOCZNOŚĆ (SKR, WYT-15)
-- ==========================================================================
Config.Noise = {
    actions = {                    -- wartości hałasu (0–100) poszczególnych czynności
        lockpick = 10, rake = 25, shim = 5, pickBreak = 20, pry = 45, pryFail = 70,
        smash = 90, glasscut = 8, search = 12, searchFast = 22, take = 8, takeLarge = 15,
        drop = 35, door = 10, light = 6, fuse = 12, dvrTake = 10, dvrSmash = 55, keypad = 4,
        doorbell = 30, gate = 30, climb = 25, hidden = 3,
    },
    footsteps = { crouch = 4, walk = 12, run = 30, sprint = 45 },
    floor = { carpet = 0.5, panel = 1.0, tile = 1.3, gravel = 1.8, wood = 1.15 },
    rain = 0.7,                    -- deszcz tłumi hałas o 30%
    link = { open = 0.8, door = 0.45 }, -- tłumienie między pokojami: otwarte przejście / drzwi
    outside = 0.35,                -- ile hałasu z pokoju z oknem na ulicę słychać na zewnątrz
}

-- ==========================================================================
--  POZIOMY DOMÓW (DOM-04)
-- ==========================================================================
Config.Tiers = {
    [1] = { label = 'Przyczepa / mieszkanie', minLevel = 1, lootMult = 0.8, cash = { 40, 220 },    alarm = 0.05, cameras = { 0, 0 }, dog = 0.15 },
    [2] = { label = 'Szeregowiec',            minLevel = 1, lootMult = 1.0, cash = { 80, 420 },    alarm = 0.30, cameras = { 0, 1 }, dog = 0.25 },
    [3] = { label = 'Dom jednorodzinny',      minLevel = 3, lootMult = 1.35, cash = { 150, 800 },  alarm = 0.65, cameras = { 1, 2 }, dog = 0.30 },
    [4] = { label = 'Willa',                  minLevel = 5, lootMult = 1.9, cash = { 400, 2200 },  alarm = 0.95, cameras = { 2, 3 }, dog = 0.40 },
}

-- ==========================================================================
--  DOMOWNICY (NPC-01, NPC-02) – archetypy planu dnia, czasy w minutach doby
-- ==========================================================================
Config.Archetypes = {
    singiel = {
        label = 'Singiel', weight = { 4, 3, 2, 1 }, residents = 1,
        wake = { 390, 450 }, leave = { 440, 510 }, back = { 990, 1110 }, sleep = { 1350, 1440 },
        sleepDeep = { 0.45, 0.7 }, homeDay = 0.1,
    },
    para = {
        label = 'Para', weight = { 2, 4, 4, 3 }, residents = 2,
        wake = { 360, 420 }, leave = { 420, 480 }, back = { 960, 1080 }, sleep = { 1320, 1410 },
        sleepDeep = { 0.5, 0.8 }, homeDay = 0.35,
    },
    emeryt = {
        label = 'Emeryci', weight = { 3, 3, 2, 1 }, residents = 2,
        wake = { 300, 360 }, leave = { 600, 630 }, back = { 690, 750 }, sleep = { 1260, 1320 },
        sleepDeep = { 0.65, 0.9 }, homeDay = 0.8, nightTrip = 180,   -- wstaje ok. 3:00 do toalety
    },
    nocny = {
        label = 'Pracuje na nocki', weight = { 2, 2, 1, 1 }, residents = 1,
        wake = { 870, 930 }, leave = { 1290, 1320 }, back = { 390, 420 }, sleep = { 450, 480 },
        sleepDeep = { 0.55, 0.8 }, homeDay = 0.0,
    },
}

Config.ResidentModels = {
    male = { 'a_m_m_bevhills_01', 'a_m_y_hipster_01', 'a_m_m_business_01', 'a_m_o_genstreet_01', 'a_m_y_vinewood_01' },
    female = { 'a_f_m_bevhills_01', 'a_f_y_hipster_02', 'a_f_m_business_02', 'a_f_o_genstreet_01', 'a_f_y_vinewood_02' },
    names = {
        male = { 'Adam', 'Tomasz', 'Marek', 'Paweł', 'Krzysztof', 'Jan', 'Piotr', 'Michał' },
        female = { 'Anna', 'Katarzyna', 'Magdalena', 'Ewa', 'Joanna', 'Agnieszka', 'Maria', 'Zofia' },
        last = { 'Nowak', 'Kowalski', 'Wiśniewski', 'Mazur', 'Zając', 'Król', 'Wróbel', 'Sikora' },
    },
}

Config.Dogs = {
    { model = 'a_c_retriever', big = true,  label = 'retriever' },
    { model = 'a_c_shepherd',  big = true,  label = 'owczarek' },
    { model = 'a_c_pug',       big = false, label = 'mops' },
    { model = 'a_c_westy',     big = false, label = 'terier' },
}

Config.AI = {
    tick = 250,                    -- [ms] tick koordynatora AI domu (NPC-26)
    hearing = { awake = 8, light = 22, deep = 45 }, -- próg słuchu: ile hałasu (po tłumieniu) budzi / niepokoi
    sight = { fov = 110, dark = 4.0, lit = 15.0, flashlight = 3.0 },
    suspicion = { rise = 55, fall = 8, suspicious = 30, alarmed = 100 },
    investigate = 25,              -- [s] ile domownik szuka źródła hałasu
    phoneTime = 7,                 -- [s] ile trwa telefon na policję (NPC-09)
    dog = { smell = 8.0, attack = true },
}

-- ==========================================================================
--  ZABEZPIECZENIA (ZAB-22, ZAB-32)
-- ==========================================================================
Config.Security = {
    entryDelay = { [1] = 45, [2] = 40, [3] = 30, [4] = 20 },   -- [s] opóźnienie wejścia (ZAB-11)
    ups = { [1] = 0, [2] = 0, [3] = 120, [4] = 300 },          -- [s] akumulator alarmu po odcięciu prądu
    subscription = {               -- abonament firmy ochroniarskiej wg poziomu domu: szanse
        [1] = { none = 1.0 },
        [2] = { none = 0.6, monitor = 0.4 },
        [3] = { none = 0.2, monitor = 0.5, reaction = 0.3 },
        [4] = { monitor = 0.3, reaction = 0.7 },
    },
    monitorDelay = 60,             -- [s] monitoring dzwoni do właściciela, potem zgłasza
    stickerBluff = 0.2,            -- szansa, że naklejka jest blefem (REK-06)
    contactChance = { door = 0.9, window = 0.55 },  -- szansa na kontaktron przy alarmie
    camera = { fov = 70, range = 14.0, sweep = 90, period = 9.0, spotTime = 1.2 },
    siren = { radius = 120.0, time = 90 },
}

-- ==========================================================================
--  ZAMKI (ZAM-01, ZAM-16, WYT-01) – parametry minigry „punkt” wg klasy
--  stages = ile punktów, tol = szerokość punktu [°], fall = zanik chwytu [°], dmg = zużycie wytrycha [HP/s]
--  D = zamek meblowy (szuflady, tanie kłódki)
-- ==========================================================================
Config.Locks = {
    A = { stages = 1, tol = 14, fall = 55, dmg = 20, rake = 0.55 },
    B = { stages = 2, tol = 9,  fall = 45, dmg = 27, rake = 0.25 },
    C = { stages = 3, tol = 5,  fall = 36, dmg = 34, rake = 0.0 },
    D = { stages = 1, tol = 18, fall = 60, dmg = 14, rake = 0.8 },
}
-- czas trwania akcji bez minigry [s]
Config.Durations = { smash = 1.5, wire = 7.0, climb = 2.5, key = 2.0, cutters = 3.5, keySearch = 3.0, take = 1.5, takeLarge = 2.5, dvr = 5.0, dvrSmash = 2.0, force = 2.0 }

-- ==========================================================================
--  NARZĘDZIA (NAR) – nazwy przedmiotów w ekwipunku
-- ==========================================================================
Config.Items = {
    lockpicks = {                  -- od najsłabszego; minigra bierze najlepszy posiadany (WYT-05)
        { item = 'wlm_wytrych_drut',  label = 'Wytrych z drutu',     hp = 55,  bonus = 0 },
        { item = 'wlm_wytrych_stal',  label = 'Wytrych stalowy',     hp = 100, bonus = 1 },
        { item = 'wlm_wytrych_tytan', label = 'Wytrych tytanowy',    hp = 160, bonus = 2 },
        { item = 'wlm_wytrych_pro',   label = 'Zestaw profesjonalny',hp = 220, bonus = 3 },
    },
    rake = 'wlm_grabie',
    shim = 'wlm_shim',
    crowbar = 'wlm_lom',
    glasscutter = 'wlm_noz_szklo',
    cutters = 'wlm_nozyce',
    screwdriver = 'wlm_srubokret',
    wire = 'wlm_drut',
    flashlight = 'wlm_latarka',
    binoculars = 'wlm_lornetka',
    laptop = 'wlm_laptop',
    gloves = {
        { item = 'wlm_rekawiczki_lateks', label = 'Rękawiczki lateksowe', uses = 6, precision = 0 },
        { item = 'wlm_rekawiczki_skora',  label = 'Rękawiczki skórzane',  uses = 0, precision = -0.1 },
        { item = 'wlm_rekawiczki_takt',   label = 'Rękawiczki taktyczne', uses = 0, precision = 0 },
    },
    mask = 'wlm_maska',
    bags = {                       -- worek / plecak / torba = pojemność na łup (NAR-17)
        { item = 'wlm_worek',  label = 'Worek na śmieci', kg = 12, tear = 0.08 },
        { item = 'wlm_plecak', label = 'Plecak',          kg = 25 },
        { item = 'wlm_torba',  label = 'Torba sportowa',  kg = 35, slow = true },
    },
}
Config.BagFree = 6                 -- [kg] tyle mieścisz w kieszeniach bez torby

-- ile dużych łupów (TV, komputer) mieści bagażnik wg klasy pojazdu GTA (LOG-01)
Config.TrunkSlots = {
    default = 2,
    [0] = 1, [1] = 2, [2] = 3, [3] = 1, [4] = 2, [5] = 1, [6] = 1, [7] = 1,
    [9] = 3, [10] = 6, [11] = 4, [12] = 6, [17] = 6, [20] = 8,
}

-- rękawiczki z ubrania: numery drawable komponentu 3 (ręce), które liczą się jako rękawiczki
Config.GloveDrawables = {
    male = { 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50 },
    female = { 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51 },
}

-- ==========================================================================
--  PROGRESJA (PRO-01, PRO-05, PRO-06, PRO-11)
-- ==========================================================================
Config.Levels = {
    { xp = 0,     label = 'Amator' },
    { xp = 300,   label = 'Kieszonkowiec' },
    { xp = 900,   label = 'Włamywacz' },
    { xp = 2000,  label = 'Fachowiec' },
    { xp = 4000,  label = 'Mistrz cienia' },
    { xp = 7500,  label = 'Legenda' },
}

Config.XP = {
    perHouse = { [1] = 40, [2] = 70, [3] = 120, [4] = 200 },
    perRecon = 6, perSale = 0.02,  -- XP za każdy dolar sprzedaży
    grade = { S = 1.5, A = 1.25, B = 1.0, C = 0.85, D = 0.7, F = 0.4 },
    arrestLoss = 0.1,              -- ile XP (ułamek bieżącego progu) traci zatrzymany
}

-- ocena włamania S–F (SKR-23)
Config.Rating = {
    grades = { { 90, 'S' }, { 75, 'A' }, { 60, 'B' }, { 45, 'C' }, { 30, 'D' }, { 0, 'F' } },
    penalty = { noise = 0.05, detected = 18, alarm = 20, fingerprint = 4, footage = 12, minute = 1.5, police = 15, empty = 25 },
}

-- ==========================================================================
--  EKONOMIA: PASERZY, LOMBARD, LIMITY (PAS)
-- ==========================================================================
Config.Payout = {
    dirty = true,                  -- true = brudna gotówka (black_money / markedbills), false = gotówka
    account = 'cash',              -- konto przy dirty = false
    qbDirtyItem = 'markedbills',   -- QBCore/QBox: przedmiot z metadanymi { worth = kwota }
}

Config.Fences = {
    {
        key = 'szczur', label = 'Szczur', model = 's_m_y_dealer_01', scenario = 'WORLD_HUMAN_SMOKING',
        spots = { vec4(-1152.6, -1564.3, 4.4, 35.0), vec4(488.1, -1331.9, 29.3, 297.0), vec4(-104.6, -8.2, 70.5, 158.0) },
        buys = { electronics = 1.0, large = 1.0, tools = 0.8, alcohol = 0.7 },
    },
    {
        key = 'jubiler', label = 'Pan Henio', model = 'a_m_o_soucent_02', scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
        spots = { vec4(-622.4, -229.9, 38.1, 305.0), vec4(1143.7, -983.4, 46.4, 97.0), vec4(-1377.3, -357.2, 36.6, 210.0) },
        buys = { jewelry = 1.1, art = 1.0, collectibles = 1.0, cash = 1.0 },
    },
}
Config.FenceCut = 0.22             -- prowizja pasera (PAS-21)
Config.FenceRep = {                -- mnożnik ceny wg reputacji u pasera (PAS-09)
    { rep = 0,    mult = 1.00, label = 'Obcy' },
    { rep = 500,  mult = 1.06, label = 'Znajomy' },
    { rep = 2000, mult = 1.12, label = 'Zaufany' },
    { rep = 6000, mult = 1.20, label = 'Wspólnik' },
}
Config.Pawn = {                    -- legalny lombard (PAS-02)
    label = 'Lombard Vinewood', ped = { model = 'a_m_m_hasjew_01', coords = vec4(182.8, -1319.4, 29.3, 240.0) },
    mult = 0.45, hotHours = 6, reportChance = 0.35,
    buys = { electronics = true, jewelry = true, tools = true, collectibles = true },
}
Config.Limits = {
    playerDaily = 25000,           -- maks. sprzedaży dziennie na postać (PAS-13)
    serverDaily = 400000,
}

-- ==========================================================================
--  ZLECENIODAWCA I SKLEP CZARNEGO RYNKU (ZLE-01, NAR-37)
-- ==========================================================================
Config.Contact = {
    name = 'Wiktor', model = 'a_m_m_og_boss_01', scenario = 'WORLD_HUMAN_AA_COFFEE',
    coords = vec4(-1172.7, -1572.3, 4.7, 215.0),
    blip = { sprite = 40, color = 5, scale = 0.75, label = 'Wiktor' },
}

Config.Shop = {
    deliveryMinutes = 3,           -- [min] po tylu minutach towar czeka w skrytce
    drops = {                      -- skrytki (dead drop)
        vec3(-1188.5, -1561.8, 4.4), vec3(354.6, -1812.7, 28.9), vec3(1161.2, -1640.2, 36.9),
        vec3(-318.4, -1377.0, 31.3), vec3(1966.6, 3818.9, 32.3),
    },
    items = {
        { item = 'wlm_wytrych_drut',  price = 60,   minLevel = 1 },
        { item = 'wlm_wytrych_stal',  price = 180,  minLevel = 1 },
        { item = 'wlm_wytrych_tytan', price = 520,  minLevel = 3 },
        { item = 'wlm_wytrych_pro',   price = 1400, minLevel = 5 },
        { item = 'wlm_grabie',        price = 240,  minLevel = 2 },
        { item = 'wlm_shim',          price = 90,   minLevel = 1 },
        { item = 'wlm_lom',           price = 150,  minLevel = 1 },
        { item = 'wlm_noz_szklo',     price = 320,  minLevel = 2 },
        { item = 'wlm_nozyce',        price = 210,  minLevel = 1 },
        { item = 'wlm_srubokret',     price = 40,   minLevel = 1 },
        { item = 'wlm_drut',          price = 20,   minLevel = 1 },
        { item = 'wlm_latarka',       price = 80,   minLevel = 1 },
        { item = 'wlm_lornetka',      price = 260,  minLevel = 1 },
        { item = 'wlm_rekawiczki_lateks', price = 30, minLevel = 1 },
        { item = 'wlm_rekawiczki_skora',  price = 220, minLevel = 2 },
        { item = 'wlm_rekawiczki_takt',   price = 650, minLevel = 4 },
        { item = 'wlm_maska',         price = 120,  minLevel = 1 },
        { item = 'wlm_worek',         price = 10,   minLevel = 1 },
        { item = 'wlm_plecak',        price = 350,  minLevel = 2 },
        { item = 'wlm_torba',         price = 800,  minLevel = 4 },
    },
}

-- ==========================================================================
--  DOWODY (POL-03, POL-10)
-- ==========================================================================
Config.Evidence = {
    ttl = 6 * 3600,                -- [s] jak długo ślady są dostępne dla policji
    fingerprintChance = 0.8,       -- szansa na odcisk przy interakcji bez rękawiczek
    inspectDistance = 3.0,
}

Config.Heat = {
    tau = 2 * 3600,                -- [s] stała zaniku heatu (spada ~63% w tym czasie)
    add = { quiet = 5, noticed = 15, alarm = 25, police = 35, witness = 10 },
}

-- ==========================================================================
--  ZDARZENIA LOSOWE W TRAKCIE WŁAMANIA (ZLE-08, LUP-22)
-- ==========================================================================
Config.Events = {
    checkEvery = 30,               -- [s]
    base = 0.04,                   -- szansa bazowa na sprawdzenie
    perMinute = 0.012,             -- rośnie z każdą minutą w środku
    list = {
        { key = 'phone',  weight = 3 },  -- dzwoni telefon domowy (hałas, może obudzić)
        { key = 'toilet', weight = 3 },  -- domownik wstaje do toalety
        { key = 'return', weight = 2 },  -- domownik wraca wcześniej (dom pusty)
        { key = 'power',  weight = 1 },  -- awaria prądu w dzielnicy (kamery gasną na 60 s)
    },
}
