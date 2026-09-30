-- ==========================================================================
--  TYPY WEJŚĆ (WEJ-02, WEJ-03, WEJ-24) – jeden model dla wszystkich metod otwierania
--  lockpick = wytrych (minigra „punkt”), rake = grabie (tylko klasy A/B), key = ukryty klucz,
--  pry = łom (minigra), smash = zbicie szyby, glasscut = wycięcie szyby, wire = drut przez uchył,
--  climb = wejście przez otwarte okno / przejście przez płot, shim = shim do kłódki, cutters = nożyce
-- ==========================================================================
Config.EntryTypes = {
    door_wood  = { label = 'Drzwi drewniane',        methods = { 'lockpick', 'rake', 'key', 'pry' }, pryDiff = 1 },
    door_steel = { label = 'Drzwi antywłamaniowe',   methods = { 'lockpick', 'key' } },
    door_glass = { label = 'Drzwi tarasowe',         methods = { 'lockpick', 'rake', 'pry', 'smash' }, pryDiff = 2, glass = true },
    window     = { label = 'Okno',                   methods = { 'pry', 'smash', 'glasscut', 'wire', 'climb' }, pryDiff = 2, glass = true },
    gate       = { label = 'Furtka',                 methods = { 'shim', 'lockpick', 'cutters', 'climb' } },
}

-- stan okien losowany dla domu (WEJ-03): szanse, pogoda i pora dnia je zmieniają
Config.WindowState = { tilted = 0.22, open = 0.06, rainFactor = 0.3, nightFactor = 0.6 }

-- ==========================================================================
--  DOMY. Koordynaty to PRZYKŁADY – sprawdź je na swojej mapie (Config.Debug + /wlm_dom).
--  district = klucz z Config.Police.eta, tier = Config.Tiers, interior = Config.Interiors
--  entries: coords = punkt interakcji na zewnątrz (w = heading, gracz patrzy na wejście)
--           lock = klasa zamka (A/B/C), street = jak bardzo wejście widać z ulicy (0–1)
--           spawn = który spawn wnętrza, front = drzwi z dzwonkiem i kluczem pod wycieraczką
--           requires = 'gate' – wejście za furtką (WEJ-19)
--  fuse = skrzynka z bezpiecznikami (ZAB-18), keySpots = gdzie może leżeć ukryty klucz (WEJ-08)
-- ==========================================================================
Config.Houses = {
    {
        id = 'grove_3', label = 'Grove Street 3', district = 'city', tier = 2, interior = 'studio',
        entries = {
            { id = 'front', type = 'door_wood',  coords = vec4(126.60, -1929.95, 21.38, 25.0),  lock = 'B', street = 1.0, spawn = 'front', front = true },
            { id = 'back',  type = 'door_glass', coords = vec4(118.80, -1921.00, 21.30, 205.0), lock = 'A', street = 0.2, spawn = 'back', requires = 'gate' },
            { id = 'okno',  type = 'window',     coords = vec4(122.90, -1935.40, 21.40, 115.0), street = 0.6, spawn = 'window' },
            { id = 'gate',  type = 'gate',       coords = vec4(121.20, -1927.60, 21.30, 115.0), lock = 'A', street = 0.7 },
        },
        keySpots = { vec3(126.9, -1929.2, 20.4), vec3(125.6, -1930.6, 20.4), vec3(127.8, -1931.0, 20.4) },
        fuse = vec3(120.4, -1924.8, 21.3),
    },
    {
        id = 'forum_7', label = 'Forum Drive 7', district = 'city', tier = 1, interior = 'studio',
        entries = {
            { id = 'front', type = 'door_wood', coords = vec4(-14.30, -1441.50, 31.10, 180.0), lock = 'A', street = 1.0, spawn = 'front', front = true },
            { id = 'okno',  type = 'window',    coords = vec4(-8.90, -1436.60, 31.10, 270.0),  street = 0.4, spawn = 'window' },
        },
        keySpots = { vec3(-14.6, -1440.7, 30.1), vec3(-13.2, -1440.9, 30.1) },
        fuse = vec3(-9.6, -1440.2, 31.1),
    },
    {
        id = 'elburro_1', label = 'Amarillo Vista 1', district = 'city', tier = 2, interior = 'studio',
        entries = {
            { id = 'front', type = 'door_wood',  coords = vec4(1273.90, -1719.70, 54.77, 200.0), lock = 'B', street = 0.9, spawn = 'front', front = true },
            { id = 'back',  type = 'door_glass', coords = vec4(1260.90, -1715.30, 54.70, 20.0),  lock = 'B', street = 0.1, spawn = 'back' },
            { id = 'okno',  type = 'window',     coords = vec4(1268.60, -1726.00, 54.70, 290.0), street = 0.5, spawn = 'window' },
        },
        keySpots = { vec3(1274.3, -1720.6, 53.8), vec3(1272.8, -1720.9, 53.8) },
        fuse = vec3(1265.6, -1712.9, 54.7),
    },
    {
        id = 'mirror_12', label = 'Mirror Park, Nikola Ave 12', district = 'city', tier = 3, interior = 'studio',
        entries = {
            { id = 'front', type = 'door_steel', coords = vec4(1229.40, -725.40, 60.80, 90.0),  lock = 'C', street = 1.0, spawn = 'front', front = true },
            { id = 'back',  type = 'door_glass', coords = vec4(1218.20, -729.80, 60.70, 270.0), lock = 'B', street = 0.1, spawn = 'back', requires = 'gate' },
            { id = 'okno',  type = 'window',     coords = vec4(1226.60, -719.00, 60.80, 0.0),   street = 0.5, spawn = 'window' },
            { id = 'gate',  type = 'gate',       coords = vec4(1224.40, -731.20, 60.70, 180.0), lock = 'A', street = 0.6 },
        },
        keySpots = { vec3(1230.1, -724.6, 59.8), vec3(1230.0, -726.4, 59.8) },
        fuse = vec3(1221.4, -733.0, 60.7),
    },
    {
        id = 'vespucci_4', label = 'Vespucci Canals, Magellan 4', district = 'city', tier = 2, interior = 'studio',
        entries = {
            { id = 'front', type = 'door_wood', coords = vec4(-1150.70, -1521.70, 10.63, 215.0), lock = 'B', street = 0.9, spawn = 'front', front = true },
            { id = 'okno',  type = 'window',    coords = vec4(-1146.40, -1518.90, 10.63, 305.0), street = 0.7, spawn = 'window' },
        },
        keySpots = { vec3(-1151.2, -1522.4, 9.6), vec3(-1149.9, -1522.6, 9.6) },
        fuse = vec3(-1153.7, -1518.4, 10.6),
    },
    {
        id = 'wildoats_3655', label = 'Wild Oats Drive 3655', district = 'hills', tier = 4, interior = 'studio',
        entries = {
            { id = 'front', type = 'door_steel', coords = vec4(-174.35, 502.30, 137.42, 190.0), lock = 'C', street = 0.8, spawn = 'front', front = true },
            { id = 'back',  type = 'door_glass', coords = vec4(-167.40, 486.60, 137.26, 10.0),  lock = 'C', street = 0.0, spawn = 'back' },
            { id = 'okno',  type = 'window',     coords = vec4(-181.60, 494.10, 137.40, 100.0), street = 0.3, spawn = 'window' },
        },
        keySpots = { vec3(-174.8, 501.4, 136.4) },
        fuse = vec3(-165.6, 497.8, 137.6),
    },
    {
        id = 'rockford_1', label = 'Richman, Portola Dr 1', district = 'rich', tier = 4, interior = 'studio',
        entries = {
            { id = 'front', type = 'door_steel', coords = vec4(-817.10, 177.90, 72.23, 110.0), lock = 'C', street = 0.8, spawn = 'front', front = true },
            { id = 'back',  type = 'door_glass', coords = vec4(-795.40, 177.60, 72.84, 290.0), lock = 'B', street = 0.0, spawn = 'back', requires = 'gate' },
            { id = 'gate',  type = 'gate',       coords = vec4(-804.20, 170.90, 72.20, 290.0), lock = 'B', street = 0.5 },
        },
        keySpots = { vec3(-816.3, 178.6, 71.2) },
        fuse = vec3(-799.5, 170.3, 72.8),
    },
    {
        id = 'sandy_trailer', label = 'Sandy Shores, przyczepa przy Zancudo Ave', district = 'sandy', tier = 1, interior = 'studio',
        entries = {
            { id = 'front', type = 'door_wood', coords = vec4(1973.00, 3815.30, 33.43, 30.0), lock = 'A', street = 0.8, spawn = 'front', front = true },
            { id = 'okno',  type = 'window',    coords = vec4(1977.20, 3819.80, 33.40, 120.0), street = 0.5, spawn = 'window' },
        },
        keySpots = { vec3(1973.3, 3814.5, 32.4), vec3(1971.9, 3814.7, 32.4) },
        fuse = vec3(1969.6, 3820.1, 32.3),
    },
}

-- ==========================================================================
--  SZOPY I GARAŻE (DOM-11): mikro-włamania bez wnętrza. Skrzynię spawnuje skrypt, więc działają
--  od razu. Idealne na samouczek (PRO-16).
-- ==========================================================================
Config.Sheds = {
    { id = 'szopa_sandy',  label = 'Szopa za przyczepą',     district = 'sandy', coords = vec4(1979.4, 3824.6, 32.4, 30.0),   prop = 'prop_toolchest_01', lock = 'A' },
    { id = 'szopa_grove',  label = 'Garaż przy Grove Street', district = 'city',  coords = vec4(114.6, -1933.5, 20.8, 45.0),   prop = 'prop_toolchest_01', lock = 'A' },
    { id = 'szopa_mirror', label = 'Szopa w Mirror Park',     district = 'city',  coords = vec4(1214.8, -735.2, 60.2, 180.0),  prop = 'prop_toolchest_01', lock = 'A' },
}
