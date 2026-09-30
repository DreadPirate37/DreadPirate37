-- ==========================================================================
--  SZABLONY WNĘTRZ (DOM-01, DOM-07)
--  Wszystkie pozycje punktów i pokoi są WZGLĘDNE do `origin` szablonu.
--  type = 'ipl'   – wnętrze z gry stojące pod mapą (nic nie trzeba spawnować, działa w każdym buckecie)
--  type = 'shell' – model shella spawnowany lokalnie w `origin` (np. zasoby K4MB1), `model` = nazwa modelu
--
--  !!! Punkty poniżej to przykładowy układ. Po włączeniu Config.Debug wnętrze rysuje pokoje i punkty,
--  a komenda /wlm_punkt <typ> [parametr] wypisuje gotową linijkę z pozycją względną – tak poprawisz
--  każdy punkt w kilka minut. Szczegóły w README.
-- ==========================================================================
Config.Interiors = {}

Config.Interiors.studio = {
    label = 'Kawalerka (wnętrze GTA: low-end apartment)',
    type = 'ipl',
    origin = vec3(265.31, -1002.80, -100.01),
    -- gdzie pojawia się gracz po wejściu danym wejściem (w = heading)
    spawns = {
        front  = vec4(0.0, 0.0, 0.0, 0.0),
        back   = vec4(-3.2, 3.6, 0.0, 180.0),
        window = vec4(-7.8, 1.6, 0.0, 90.0),
    },
    rooms = {
        { id = 'hall',      label = 'Przedpokój', min = vec3(-1.6, -1.5, -0.5),  max = vec3(1.6, 2.2, 3.0),  floor = 'panel' },
        { id = 'salon',     label = 'Salon',      min = vec3(-6.0, -3.0, -0.5),  max = vec3(-1.6, 3.0, 3.0), floor = 'carpet', street = true },
        { id = 'kuchnia',   label = 'Kuchnia',    min = vec3(-4.5, 3.0, -0.5),   max = vec3(-1.0, 5.5, 3.0), floor = 'tile' },
        { id = 'sypialnia', label = 'Sypialnia',  min = vec3(-10.5, -3.0, -0.5), max = vec3(-6.0, 3.0, 3.0), floor = 'carpet', street = true },
        { id = 'lazienka',  label = 'Łazienka',   min = vec3(-1.0, 2.2, -0.5),   max = vec3(2.2, 5.5, 3.0),  floor = 'tile' },
    },
    -- przejścia: { pokój, pokój, drzwi? } – drzwi tłumią hałas mocniej niż otwarte przejście
    links = {
        { 'hall', 'salon', false }, { 'salon', 'kuchnia', false }, { 'salon', 'sypialnia', true }, { 'hall', 'lazienka', true },
    },
    points = {
        -- meble do przeszukania (LUP-04); locked = zamknięta szuflada (ZAM-16)
        { id = 'szafki',   type = 'search', furniture = 'kitchen',    room = 'kuchnia',   pos = vec3(-3.0, 5.0, 0.0) },
        { id = 'szafa',    type = 'search', furniture = 'wardrobe',   room = 'sypialnia', pos = vec3(-10.0, -2.2, 0.0) },
        { id = 'nocna',    type = 'search', furniture = 'nightstand', room = 'sypialnia', pos = vec3(-9.8, 1.8, 0.0) },
        { id = 'komoda',   type = 'search', furniture = 'dresser',    room = 'sypialnia', pos = vec3(-7.0, -2.6, 0.0) },
        { id = 'biurko',   type = 'search', furniture = 'desk',       room = 'salon',     pos = vec3(-5.4, -2.4, 0.0), locked = true },
        { id = 'regal',    type = 'search', furniture = 'shelf',      room = 'salon',     pos = vec3(-2.2, -2.6, 0.0) },
        { id = 'apteczka', type = 'search', furniture = 'bathroom',   room = 'lazienka',  pos = vec3(1.6, 4.8, 0.0) },
        -- widoczne łupy (LUP-05): prop pojawia się wg Config.LootSlots
        { id = 'tv',      type = 'loot', slot = 'tv',     room = 'salon',   pos = vec4(-4.2, -2.7, 0.55, 0.0) },
        { id = 'mikro',   type = 'loot', slot = 'micro',  room = 'kuchnia', pos = vec4(-2.0, 5.2, 0.95, 0.0) },
        { id = 'laptop',  type = 'loot', slot = 'laptop', room = 'salon',   pos = vec4(-5.4, -2.2, 0.78, 180.0) },
        { id = 'butelka', type = 'loot', slot = 'bottle', room = 'kuchnia', pos = vec4(-4.0, 5.2, 0.95, 0.0) },
        { id = 'glosnik', type = 'loot', slot = 'speaker',room = 'sypialnia', pos = vec4(-7.4, -2.6, 0.9, 0.0) },
        -- sejf: kind = 'dial' (tarcza, ZAM-10) albo 'furniture' (meblowy z kodem, ZAM-12)
        { id = 'sejf',    type = 'safe', kind = 'dial', room = 'sypialnia', pos = vec3(-10.2, 0.2, 0.3) },
        -- włączniki światła (SKR-07)
        { id = 'sw_hall',  type = 'light', room = 'hall',      pos = vec3(1.4, -0.4, 1.2) },
        { id = 'sw_salon', type = 'light', room = 'salon',     pos = vec3(-1.8, 0.8, 1.2) },
        { id = 'sw_kuch',  type = 'light', room = 'kuchnia',   pos = vec3(-1.2, 3.4, 1.2) },
        { id = 'sw_syp',   type = 'light', room = 'sypialnia', pos = vec3(-6.2, 1.0, 1.2) },
        { id = 'sw_laz',   type = 'light', room = 'lazienka',  pos = vec3(-0.8, 2.6, 1.2) },
        -- kryjówki (SKR-10)
        { id = 'kr_szafa', type = 'hide', label = 'Schowaj się w szafie', room = 'sypialnia', pos = vec4(-9.6, -2.4, 0.0, 180.0) },
        { id = 'kr_lozko', type = 'hide', label = 'Wejdź pod łóżko',      room = 'sypialnia', pos = vec4(-8.4, -0.6, 0.0, 90.0) },
        { id = 'kr_zaslona', type = 'hide', label = 'Stań za zasłoną',    room = 'salon',     pos = vec4(-5.6, 2.6, 0.0, 0.0) },
        -- domownicy: łóżka (sen), miejsca dzienne, cel nocnego wyjścia
        { id = 'lozko1', type = 'bed',   room = 'sypialnia', pos = vec4(-8.6, 0.3, 0.55, 90.0) },
        { id = 'lozko2', type = 'bed',   room = 'sypialnia', pos = vec4(-8.6, 1.3, 0.55, 90.0) },
        { id = 'kanapa', type = 'sit',   room = 'salon',     pos = vec4(-3.5, 1.5, 0.0, 180.0) },
        { id = 'kuch_st',type = 'sit',   room = 'kuchnia',   pos = vec4(-2.6, 4.2, 0.0, 0.0) },
        { id = 'wc',     type = 'visit', room = 'lazienka',  pos = vec3(1.2, 3.5, 0.0) },
        { id = 'pies',   type = 'dog',   room = 'salon',     pos = vec4(-3.0, 0.0, 0.0, 90.0) },
        -- zabezpieczenia (ZAB-01, ZAB-08, ZAB-11)
        { id = 'panel',   type = 'alarm',  room = 'hall',      pos = vec3(0.9, -1.2, 1.3) },
        { id = 'dvr',     type = 'dvr',    room = 'sypialnia', pos = vec3(-10.2, -0.8, 0.3) },
        { id = 'kamera1', type = 'camera', room = 'salon',     pos = vec4(-1.8, -2.8, 2.4, 225.0), sweep = true },
        { id = 'kamera2', type = 'camera', room = 'hall',      pos = vec4(1.4, 2.0, 2.4, 160.0) },
        { id = 'kamera3', type = 'camera', room = 'sypialnia', pos = vec4(-6.2, -2.8, 2.4, 135.0) },
        -- wyjścia: spawn = którym wejściem wychodzisz na zewnątrz
        { id = 'wy_front', type = 'exit', spawn = 'front',  room = 'hall',      pos = vec3(0.0, -1.0, 0.0) },
        { id = 'wy_back',  type = 'exit', spawn = 'back',   room = 'kuchnia',   pos = vec3(-3.2, 3.2, 0.0) },
        { id = 'wy_okno',  type = 'exit', spawn = 'window', room = 'sypialnia', pos = vec3(-8.2, 1.6, 0.0) },
    },
}
