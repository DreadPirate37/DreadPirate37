Config = {}

-- ==========================================================================
--  OGÓLNE
-- ==========================================================================
Config.Debug = false               -- dodatkowe logi i /doorlock_pos
Config.Framework = 'auto'          -- 'auto' | 'esx' | 'qb' | 'qbx' | 'standalone'
Config.Inventory = 'auto'          -- 'auto' | 'ox' | 'qb' | 'esx' | 'standalone'
Config.RequireDuty = false         -- dostęp służbowy tylko na służbie (QB/QBox)
Config.PersistState = true         -- pamiętaj stan zamków po restarcie serwera (KVP)
Config.AdminAce = 'dp-doorlock.admin'  -- ACE do edytora; dodatkowo admini frameworka
Config.AdminAccess = true          -- admini otwierają wszystkie drzwi

Config.Keys = {
    use  = 'E',                    -- otwórz / zamknij / klawiatura / czytnik
    menu = 'G',                    -- menu akcji drzwi (radial)
}

-- ==========================================================================
--  WYDAJNOŚĆ  (domyślne wartości są dobrane pod ~1000 drzwi na serwerze)
-- ==========================================================================
Config.Perf = {
    gridSize = 64.0,               -- rozmiar komórki siatki przestrzennej [m]
    scanInterval = 500,            -- co ile ms szukać drzwi w pobliżu (pętla wolna)
    scanRadius = 30.0,             -- promień, w którym drzwi są „aktywne”
    idleSleep = 750,               -- sen pętli szybkiej, gdy żadne drzwi nie są w zasięgu UI
    chipEpsilon = 0.0015,          -- min. przesunięcie znacznika na ekranie, aby wysłać go do NUI
    saveDebounce = 3000,           -- zapis pliku drzwi najwyżej raz na X ms
    logSize = 60,                  -- ile wpisów dziennika trzymać na drzwi (bufor cykliczny)
}

-- ==========================================================================
--  WYGLĄD ZNACZNIKA W ŚWIECIE
-- ==========================================================================
Config.UI = {
    drawDistance = 7.0,            -- od tej odległości widać kompaktową ikonę kłódki
    showNames = true,
    theme = 'aurora',              -- 'aurora' | 'noir' | 'ember' | 'ice'  (html/css/style.css)
    scaleByDistance = true,
    maxChips = 6,                  -- ile znaczników naraz (najbliższe drzwi)
    sounds = true,
    volume = 0.55,
}

-- ==========================================================================
--  PRZEDMIOTY
-- ==========================================================================
Config.Items = {
    diy        = { 'bobbypin' },                       -- spinka (ze śrubokrętem) – proste zamki
    lockpick   = { 'lockpick', 'advancedlockpick' },   -- wytrych – zamki z zapadkami (działa też na proste)
    advanced   = 'advancedlockpick',                   -- zaawansowany: zapadki dłużej „stoją”
    round      = { 'round_lockpick' },                 -- wytrych okrągły – zamki okrągłe
    hackDevice = { 'hacking_device', 'electronickit' },
    thermite   = 'thermite',
    ram        = 'police_ram',                         -- nil = taran nie wymaga przedmiotu
}

-- karty dostępu: przedmiot = poziom uprawnień
Config.Keycards = {
    keycard_green  = 1,
    keycard_blue   = 2,
    keycard_red    = 3,
    keycard_black  = 4,
}

-- ==========================================================================
--  WYTRYCH (minigra z zapadkami)
-- ==========================================================================
Config.Lockpick = {
    -- Narzędzie zależy od zamka (jak w symulatorach włamywacza):
    --   trudność 1–diyMaxDifficulty  → prosty zamek: SPINKA + ŚRUBOKRĘT (albo zwykły wytrych)
    --   wyższa trudność              → zamek z zapadkami: WYTRYCH (przekrój, 5 zapadek)
    --   lockModel = 'round'          → zamek okrągły: WYTRYCH OKRĄGŁY
    diyMaxDifficulty = 2,
    diy = {
        maxFails = { 5, 4 },                 -- nietrafione próby, po których spinka pęka (wg trudności)
    },
    pins = {                                 -- wg trudności 1–5 (dla wytrycha i wytrycha okrągłego)
        count    = { 5, 5, 5, 5, 6 },        -- zapadki w zwykłym zamku (okrągły ma zawsze 7)
        knockMax = { 1, 2, 2, 3, 3 },        -- ile razy maks. trzeba stuknąć, zanim sprężyna puści
        stall    = { 1.0, 0.9, 0.75, 0.6, 0.5 }, -- ile sekund zapadka stoi na dnie
        spring   = { 0.25, 0.3, 0.35, 0.42, 0.5 }, -- jak szybko sprężyna wypycha zapadkę
        maxFails = 4,                        -- kliknięcia „zablokuj” w złym momencie, po których wytrych pęka
    },
    advancedBonus = 0.25,                    -- zaawansowany wytrych: dłuższe „stanie” zapadki
    -- umiejętność „Włamywanie” (XP i poziomy jak w grze; zapis w KVP)
    skill = {
        enabled = true,
        levels = { 0, 82, 200, 380, 650, 1000 },   -- XP potrzebne na poziom 1, 2, 3…
        xpPerDifficulty = 12,                      -- XP za otwarty zamek = trudność × ta wartość
        required = { 1, 1, 2, 3, 4 },              -- minimalny poziom dla zamka o trudności 1–5
        stallPerLevel = 0.05,                      -- każdy poziom wydłuża „stanie” zapadki
    },
    camera = true,                           -- kamera najeżdża na zamek podczas minigry
    cameraDistance = 0.55,
    cameraFov = 42.0,
    minSeconds = 2,                          -- serwer odrzuci szybsze „sukcesy”
    alarmOnBreak = 0.35,                     -- szansa na cichy alarm, gdy narzędzie pęknie
}

-- ==========================================================================
--  HAKOWANIE (synchronizacja sygnału)
-- ==========================================================================
Config.Hack = {
    stagesByDifficulty = { 1, 2, 2, 3, 3 },
    minSeconds = 4,
    timeLimit = 45,
    alarmOnFail = true,
    lockoutSeconds = 90,           -- po porażce czytnik blokuje się dla tego gracza
}

-- ==========================================================================
--  WYWAŻANIE: termit i taran
-- ==========================================================================
Config.Breach = {
    thermiteSeconds = 12,          -- czas palenia
    brokenSeconds = 900,           -- jak długo drzwi są wyłamane (0 = do naprawy)
    ramSeconds = 5,
    ramJobs = { police = 0, sheriff = 0, fbi = 0 },
    ramAnyDoor = true,             -- taran działa na wszystkie drzwi (nie tylko z breach = true)
    repairJobs = { police = 0, mechanic = 0 },  -- oprócz osób z dostępem do drzwi
    repairSeconds = 8,
}

-- ==========================================================================
--  BLOKADA BUDYNKU (lockdown całej grupy drzwi)
-- ==========================================================================
Config.Lockdown = {
    jobs = { police = 2, sheriff = 2 },
    command = 'lockdown',          -- /lockdown <grupa> | /lockdown <grupa> off
}

-- ==========================================================================
--  KLAWIATURY PIN
-- ==========================================================================
Config.Keypad = {
    maxAttempts = 3,               -- po tylu błędach klawiatura blokuje się
    lockoutSeconds = 60,
    alarmOnLockout = true,
    minLength = 4, maxLength = 8,
}

-- ==========================================================================
--  ALARM / DYSPOZYTORNIA
-- ==========================================================================
Config.Alarm = {
    jobs = { 'police', 'sheriff' },
    blipSeconds = 90,
    cooldown = 60,                 -- min. odstęp między alarmami z tych samych drzwi [s]
}

-- ==========================================================================
--  DZWONEK I PUKANIE
-- ==========================================================================
Config.Social = {
    knockRadius = 14.0,
    bellRadius = 45.0,             -- kto usłyszy dzwonek (i dostanie powiadomienie, jeśli ma dostęp)
    cooldown = 4,
}

-- ==========================================================================
--  ANIMACJE
-- ==========================================================================
Config.Anims = {
    key      = { dict = 'anim@heists@keycard@', clip = 'exit', time = 900, flag = 48,
                 prop = { model = 'prop_cuff_keys_01', bone = 57005, pos = vec3(0.11, 0.03, -0.03), rot = vec3(-90.0, 0.0, 0.0), time = 900 } },
    knock    = { dict = 'timetable@jimmy@doorknock@', clip = 'knockdoor_idle', time = 2200, flag = 48 },
    lockpick = { dict = 'mp_common_heist', clip = 'pick_door', flag = 1 },
    hack     = { scenario = 'WORLD_HUMAN_STAND_MOBILE' },
    thermite = { dict = 'anim@heists@ornate_bank@thermal_charge', clip = 'thermal_charge', flag = 1 },
    ram      = { dict = 'missprologuemcs_1', clip = 'kick_down_player_zero', flag = 0 },
    repair   = { scenario = 'PROP_HUMAN_BUM_BIN' },
}

-- ==========================================================================
--  DOMYŚLNE WARTOŚCI NOWYCH DRZWI (edytor w grze)
-- ==========================================================================
Config.Defaults = {
    distance = 2.0,
    gateDistance = 7.0,
    autoLock = 0,
    security = 'standard',
    locked = true,
}

-- ==========================================================================
--  DRZWI Z KONFIGURACJI
--  Wczytywane przy starcie do data/doors.json (po polu `key`). Później można
--  je edytować w grze (/doorlock). Usunięte w edytorze nie wracają.
--  Współrzędne to vanilla GTA – przy MLO sprawdź je komendą /doorlock (wybór celownikiem).
--
--  type      : 'single' | 'double' | 'sliding' | 'garage'
--  security  : 'standard' (klucz/uprawnienia) | 'keypad' (PIN) | 'card' (karta) | 'bio' (odcisk palca)
--  access    : jobs = { praca = minimalny_grade }, gangs = {...}, items = { 'klucz' }, public = true
--  lockpick / hack : trudność 1–5 (0 = wyłączone)
--  lockModel : 'euro' (wkładka w szyldzie) | 'rim' (rozeta) | 'padlock' (kłódka) | 'round' (zamek okrągły)
--  schedule  : { open = '08:00', close = '22:00' } – w tych godzinach drzwi są otwarte (czas serwera)
-- ==========================================================================
Config.Doors = {
    {
        key = 'mrpd_front', name = 'Wejście główne', group = 'MRPD', type = 'double',
        doors = {
            { model = `v_ilev_ph_door01`,  coords = vec3(434.7, -980.6, 30.8) },
            { model = `v_ilev_ph_door002`, coords = vec3(434.7, -983.2, 30.8) },
        },
        locked = false, access = { jobs = { police = 0 } }, breach = false,
        schedule = { open = '06:00', close = '23:00' },
    },
    {
        key = 'mrpd_lockers', name = 'Szatnia i dach', group = 'MRPD', type = 'single',
        doors = { { model = `v_ilev_ph_gendoor004`, coords = vec3(449.6, -986.4, 30.6) } },
        security = 'card', cardLevel = 2, access = { jobs = { police = 0 } }, hack = 3,
    },
    {
        key = 'mrpd_captain', name = 'Gabinet kapitana', group = 'MRPD', type = 'single',
        doors = { { model = `v_ilev_ph_gendoor002`, coords = vec3(447.2, -980.6, 30.6) } },
        security = 'bio', access = { jobs = { police = 3 } }, autoLock = 10, hack = 4,
    },
    {
        key = 'mrpd_cells', name = 'Cele – krata', group = 'MRPD', type = 'single',
        doors = { { model = `v_ilev_ph_cellgate`, coords = vec3(463.8, -992.6, 24.9) } },
        access = { jobs = { police = 0 } }, lockpick = 5, alarm = true, autoLock = 6,
    },
    {
        key = 'sandy_pd', name = 'Posterunek Sandy Shores', group = 'BCSO', type = 'single',
        doors = { { model = `v_ilev_shrfdoor`, coords = vec3(1855.1, 3683.5, 34.2) } },
        locked = false, access = { jobs = { sheriff = 0, police = 0 } }, breach = true, alarm = true,
    },
    {
        key = 'paleto_pd', name = 'Posterunek Paleto Bay', group = 'BCSO', type = 'double',
        doors = {
            { model = `v_ilev_shrf2door`, coords = vec3(-443.1, 6015.6, 31.7) },
            { model = `v_ilev_shrf2door`, coords = vec3(-443.9, 6016.6, 31.7) },
        },
        security = 'keypad', pin = '1337', access = { jobs = { sheriff = 0, police = 0 } },
        hack = 2, breach = true, alarm = true, doorbell = true,
    },
}
