Config = {}

-- ==========================================================================
--  OGÓLNE
-- ==========================================================================
Config.Debug = false               -- komendy /spawacz_pos, dodatkowe logi
Config.Framework = 'auto'          -- 'auto' | 'esx' | 'qb' | 'qbx' | 'standalone'
Config.UseTarget = true            -- ox_target / qb-target jeśli uruchomione, inaczej [E]
Config.Camera = true               -- kamera na stanowisko podczas minigry
Config.PayAccount = 'bank'         -- 'bank' | 'cash'

Config.Job = {
    required = false,              -- true = tylko gracze z pracą z listy poniżej
    names = { 'welder', 'spawacz', 'mechanic' },
}

-- ==========================================================================
--  BAZA / BRYGADZISTA
-- ==========================================================================
Config.Depot = {
    label = 'Spawalnia – baza',
    ped = { model = 's_m_y_construct_01', coords = vec4(1209.35, -3114.9, 5.54, 90.0) },
    blip = { sprite = 446, color = 47, scale = 0.8 },
    vehicleSpawn = vec4(1200.9, -3102.3, 5.8, 0.0),
    finishRadius = 25.0,           -- promień, w którym można rozliczyć zlecenie
}

Config.Vehicle = {
    enabled = true,
    model = 'burrito3',
    plate = 'SPAW',                -- prefiks tablicy (dopełniany cyframi)
    deposit = 500,                 -- kaucja, zwracana proporcjonalnie do stanu auta
    depositAccount = 'bank',
    returnRadius = 25.0,
}

-- ==========================================================================
--  PROGRESJA
-- ==========================================================================
Config.Levels = {
    { xp = 0,    label = 'Praktykant',              payMult = 1.00 },
    { xp = 400,  label = 'Spawacz',                 payMult = 1.08 },
    { xp = 1200, label = 'Spawacz certyfikowany',   payMult = 1.16 },
    { xp = 2600, label = 'Spawacz specjalista',     payMult = 1.25 },
    { xp = 5000, label = 'Mistrz spawalnictwa',     payMult = 1.35 },
}

Config.XP = {
    perTask = 60,                  -- bazowo, skalowane trudnością i jakością
    gradeBonus = { S = 25, A = 10 },
    failXp = 5,
}

-- grubości materiału dostępne na danym poziomie [mm]
Config.Thickness = {
    [1] = { 3, 6 }, [2] = { 3, 8 }, [3] = { 2, 10 }, [4] = { 2, 12 }, [5] = { 2, 14 },
}

Config.Processes = {
    MMA = { label = 'MMA',     minLevel = 1, pay = 1.00 },
    MAG = { label = 'MIG/MAG', minLevel = 2, pay = 1.05 },
    TIG = { label = 'TIG',     minLevel = 3, pay = 1.25 },
}

Config.Materials = {
    steel     = { label = 'Stal węglowa',    minLevel = 1, pay = 1.00, processes = { 'MMA', 'MAG', 'TIG' } },
    stainless = { label = 'Stal nierdzewna', minLevel = 3, pay = 1.30, processes = { 'TIG', 'MAG' } },
    aluminium = { label = 'Aluminium',       minLevel = 4, pay = 1.45, processes = { 'TIG', 'MAG' } },
}

Config.Positions = {
    flat     = { label = 'PA – podolna',  minLevel = 1, pay = 1.00, weight = 5 },
    vertical = { label = 'PF – pionowa',  minLevel = 2, pay = 1.20, weight = 3 },
    overhead = { label = 'PE – pułapowa', minLevel = 4, pay = 1.45, weight = 2 },
}

Config.Types = {
    crack  = { label = 'Pęknięcie rury',    minLevel = 1, pay = 1.00, props = { 'prop_pipes_02b', 'prop_pipes_03b', 'prop_pipes_01a' } },
    fillet = { label = 'Spoina pachwinowa', minLevel = 1, pay = 0.95, props = { 'prop_byard_sleeper01', 'prop_metal_plates01' } },
    butt   = { label = 'Złącze doczołowe',  minLevel = 2, pay = 1.10, props = { 'prop_metal_plates02', 'prop_metal_plates01' } },
    patch  = { label = 'Łata na zbiorniku', minLevel = 3, pay = 1.30, props = { 'prop_gas_tank_01a', 'prop_storagetank_01' } },
}

-- ==========================================================================
--  WYPŁATY I OCENA  (wagi / progi MUSZĄ zgadzać się z html/js/data.js)
-- ==========================================================================
Config.Payment = {
    basePerTask = 380,
    perExtraPass = 0.18,           -- +18% za każdy dodatkowy ścieg
    perDifficulty = 0.10,          -- +10% za każdy poziom trudności powyżej 1
    gradeBonus = { S = 0.25, A = 0.10 },
    contractBonus = 0.20,          -- premia za komplet zadań (od sumy wypłat), przy rozliczeniu w bazie
    maxAttempts = 2,               -- ile razy można podejść do zadania (ocena F = nieudane)
}

Config.Scoring = {
    weights = { setup = 0.10, prep = 0.15, prep2 = 0.10, weld = 0.55, finish = 0.10 },
    grades = { { 93, 'S' }, { 82, 'A' }, { 68, 'B' }, { 52, 'C' }, { 40, 'D' }, { 0, 'F' } },
}

Config.Offers = {
    count = 3,
    refresh = 300,                 -- sekundy do odświeżenia listy zleceń
}

-- ==========================================================================
--  ZABEZPIECZENIA
-- ==========================================================================
Config.Security = {
    maxDistance = 8.0,             -- max odległość gracza od punktu przy starcie/końcu spawu
    minSecondsBase = 30,           -- minimalny czas całej minigry...
    minSecondsPerPass = 10,        -- ...+ tyle za każdy ścieg
    maxSeconds = 1200,
}

-- ==========================================================================
--  ANIMACJE I REKWIZYTY
-- ==========================================================================
Config.Anim = {
    weldScenario = 'WORLD_HUMAN_WELDING',
    kneel = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer' },
    tablet = { dict = 'amb@code_human_in_bus_passenger_idles@female@tablet@base', clip = 'base', prop = 'prop_cs_tablet' },
}

Config.Marker = { type = 21, size = vec3(0.45, 0.45, 0.45), color = { 255, 176, 32, 170 } }
Config.TaskBlip = { sprite = 566, color = 47, scale = 0.7 }

-- ==========================================================================
--  MIEJSCA PRACY
--  coords = miejsce, w którym stoi gracz (w = heading, gracz patrzy na detal)
--  Z jest automatycznie dociągane do gruntu. Własne punkty: /spawacz_pos (Debug)
-- ==========================================================================
Config.Sites = {
    {
        key = 'port', label = 'Port LS – rurociąg paliwowy', tier = 1, minLevel = 1,
        center = vec3(1165.0, -3185.0, 5.9), tasks = { 2, 3 },
        spots = {
            { coords = vec4(1142.6, -3174.8, 5.9, 180.0), types = { 'crack', 'fillet' } },
            { coords = vec4(1157.1, -3192.3, 5.9, 90.0),  types = { 'crack', 'butt' } },
            { coords = vec4(1176.4, -3180.2, 5.9, 270.0), types = { 'crack' } },
            { coords = vec4(1189.8, -3196.5, 5.9, 0.0),   types = { 'fillet', 'butt' } },
        },
    },
    {
        key = 'budowa', label = 'Budowa – konstrukcja stalowa', tier = 2, minLevel = 1,
        center = vec3(-110.0, -1010.0, 27.3), tasks = { 2, 4 },
        spots = {
            { coords = vec4(-97.1, -1013.5, 27.3, 160.0),  types = { 'fillet', 'butt' } },
            { coords = vec4(-120.4, -1005.9, 27.3, 250.0), types = { 'fillet' } },
            { coords = vec4(-139.2, -1017.8, 27.3, 70.0),  types = { 'butt', 'fillet' } },
            { coords = vec4(-108.6, -1036.1, 27.3, 340.0), types = { 'crack', 'fillet' } },
        },
    },
    {
        key = 'lotnisko', label = 'Sandy Shores – hangar serwisowy', tier = 2, minLevel = 2,
        center = vec3(1735.0, 3295.0, 41.1), tasks = { 2, 3 },
        spots = {
            { coords = vec4(1729.8, 3310.4, 41.2, 195.0), types = { 'butt', 'patch' } },
            { coords = vec4(1744.1, 3291.7, 41.1, 105.0), types = { 'fillet', 'butt' } },
            { coords = vec4(1718.6, 3288.9, 41.2, 285.0), types = { 'patch', 'crack' } },
        },
    },
    {
        key = 'rafineria', label = 'Pola naftowe – instalacja rurowa', tier = 3, minLevel = 2,
        center = vec3(1500.0, -2110.0, 76.8), tasks = { 3, 4 },
        spots = {
            { coords = vec4(1493.7, -2098.2, 76.8, 90.0),  types = { 'crack', 'patch' } },
            { coords = vec4(1510.5, -2114.9, 76.9, 0.0),   types = { 'crack', 'butt' } },
            { coords = vec4(1486.9, -2126.3, 76.7, 225.0), types = { 'patch', 'crack' } },
            { coords = vec4(1521.2, -2092.6, 77.0, 135.0), types = { 'butt', 'fillet' } },
        },
    },
    {
        key = 'elektrownia', label = 'Elektrownia Palmer-Taylor', tier = 3, minLevel = 3,
        center = vec3(2735.0, 1530.0, 24.5), tasks = { 3, 4 },
        spots = {
            { coords = vec4(2727.4, 1521.8, 24.5, 70.0),  types = { 'crack', 'butt', 'patch' } },
            { coords = vec4(2744.9, 1538.3, 24.5, 250.0), types = { 'patch', 'fillet' } },
            { coords = vec4(2752.1, 1519.7, 24.5, 160.0), types = { 'crack', 'butt' } },
            { coords = vec4(2719.3, 1542.6, 24.5, 340.0), types = { 'butt', 'patch' } },
        },
    },
    {
        key = 'kamieniolom', label = 'Kamieniołom Davis Quartz – zbiorniki', tier = 4, minLevel = 4,
        center = vec3(2950.0, 2790.0, 41.0), tasks = { 3, 4 },
        spots = {
            { coords = vec4(2941.6, 2779.2, 40.2, 30.0),  types = { 'patch', 'crack' } },
            { coords = vec4(2958.3, 2796.4, 41.1, 210.0), types = { 'patch', 'butt' } },
            { coords = vec4(2966.7, 2775.8, 40.8, 120.0), types = { 'crack', 'fillet', 'patch' } },
            { coords = vec4(2936.2, 2801.9, 41.4, 300.0), types = { 'butt', 'patch' } },
        },
    },
}
