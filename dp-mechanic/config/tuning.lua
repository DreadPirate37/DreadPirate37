-- ==========================================================================
--  MENU TUNINGU
--  cam     – preset kamery (config/assembly.lua → Config.CamPresets) na który kamera przelatuje
--  anchor  – miejsce montażu (poświata + śruby) – Config.Anchors
--  doors   – drzwi/maska/bagażnik otwierane automatycznie (0-3 drzwi, 4 maska, 5 bagażnik)
--  price   – cena poziomu 0, step – dopłata za każdy kolejny poziom
--  labor   – roboczogodziny (do faktury)
--  bolts   – liczba śrub w minigrze montażu, pattern – układ ('line','circle','grid','corners')
--  prop    – co mechanik niesie w rękach (Config.CarryProps)
--  effects – realny wpływ na jazdę NA POZIOM (mnożniki są potęgowane poziomem)
-- ==========================================================================

Config.TuningGroups = {
    { id = 'body',     label = 'Nadwozie',   icon = 'car' },
    { id = 'wheels',   label = 'Koła',       icon = 'wheel' },
    { id = 'perf',     label = 'Osiągi',     icon = 'bolt' },
    { id = 'paint',    label = 'Lakier',     icon = 'brush' },
    { id = 'lights',   label = 'Światła',    icon = 'light' },
    { id = 'interior', label = 'Wnętrze',    icon = 'seat' },
    { id = 'extras',   label = 'Dodatki',    icon = 'star' },
}

Config.ModTypes = {
    [0]  = { label = 'Spojler',           group = 'body', cam = 'rear_high', anchor = 'spoiler',  price = 1400, step = 300, labor = 1.0, bolts = 4, pattern = 'line',    prop = 'spoiler', cabinet = 'body', doors = { 5 },
             effects = { grip = 1.012, tractionLoss = 0.99 } },
    [1]  = { label = 'Zderzak przedni',   group = 'body', cam = 'front',     anchor = 'bumper_f', price = 1600, step = 250, labor = 1.2, bolts = 6, pattern = 'line',    prop = 'bumper',  cabinet = 'body' },
    [2]  = { label = 'Zderzak tylny',     group = 'body', cam = 'rear',      anchor = 'bumper_r', price = 1500, step = 250, labor = 1.2, bolts = 6, pattern = 'line',    prop = 'bumper',  cabinet = 'body' },
    [3]  = { label = 'Progi',             group = 'body', cam = 'side_l',    anchor = 'skirt',    price = 1100, step = 200, labor = 1.0, bolts = 6, pattern = 'line',    prop = 'panel',   cabinet = 'body' },
    [4]  = { label = 'Końcówki wydechu',  group = 'body', cam = 'exhaust',   anchor = 'exhaust',  price = 900,  step = 200, labor = 0.8, bolts = 3, pattern = 'circle',  prop = 'exhaust', cabinet = 'body', lift = 'ramp' },
    [5]  = { label = 'Klatka / rama',     group = 'body', cam = 'interior',  anchor = 'interior', price = 2800, step = 500, labor = 3.0, bolts = 8, pattern = 'grid',    prop = 'frame',   cabinet = 'body', doors = { 0, 1 },
             effects = { antiroll = 1.02, engineDmg = 0.99 } },
    [6]  = { label = 'Grill',             group = 'body', cam = 'front',     anchor = 'grille',   price = 700,  step = 150, labor = 0.5, bolts = 4, pattern = 'corners', prop = 'panel',   cabinet = 'body' },
    [7]  = { label = 'Maska',             group = 'body', cam = 'hood',      anchor = 'hood',     price = 1800, step = 300, labor = 1.0, bolts = 4, pattern = 'corners', prop = 'hood',    cabinet = 'body' },
    [8]  = { label = 'Błotnik lewy',      group = 'body', cam = 'side_l',    anchor = 'fender_l', price = 900,  step = 200, labor = 1.0, bolts = 5, pattern = 'line',    prop = 'panel',   cabinet = 'body' },
    [9]  = { label = 'Błotnik prawy',     group = 'body', cam = 'side_r',    anchor = 'fender_r', price = 900,  step = 200, labor = 1.0, bolts = 5, pattern = 'line',    prop = 'panel',   cabinet = 'body' },
    [10] = { label = 'Dach',              group = 'body', cam = 'roof',      anchor = 'roof',     price = 1500, step = 300, labor = 1.5, bolts = 6, pattern = 'corners', prop = 'panel',   cabinet = 'body' },
    [11] = { label = 'Silnik (EMS)',      group = 'perf', cam = 'engine',    anchor = 'engine',   price = 4500, step = 3500,labor = 3.0, bolts = 6, pattern = 'grid',    prop = 'engine_part', cabinet = 'engine', doors = { 4 },
             effects = { power = 1.03, revs = 1.01 } },
    [12] = { label = 'Hamulce',           group = 'perf', cam = 'wheel_fl',  anchor = 'wheel',    price = 2400, step = 1600,labor = 1.5, bolts = 4, pattern = 'circle',  prop = 'brake',   cabinet = 'perf', lift = 'arms',
             effects = { brake = 1.06 } },
    [13] = { label = 'Skrzynia biegów',   group = 'perf', cam = 'under',     anchor = 'under_gearbox', price = 3800, step = 2200, labor = 4.0, bolts = 8, pattern = 'grid', prop = 'engine_part', cabinet = 'engine', lift = 'ramp',
             effects = { shift = 1.12 } },
    [15] = { label = 'Zawieszenie',       group = 'perf', cam = 'wheel_fl',  anchor = 'wheel',    price = 2200, step = 1300,labor = 2.0, bolts = 4, pattern = 'circle',  prop = 'spring',  cabinet = 'perf', lift = 'arms',
             effects = { susForce = 1.05, antiroll = 1.05, grip = 1.008 } },
    [16] = { label = 'Opancerzenie',      group = 'perf', cam = 'side_l',    anchor = 'door_l',   price = 5000, step = 4000,labor = 3.0, bolts = 8, pattern = 'grid',    prop = 'panel',   cabinet = 'body', doors = { 0 },
             effects = { power = 0.99, brake = 0.99 } },
    [18] = { label = 'Turbo',             group = 'perf', cam = 'engine',    anchor = 'engine',   price = 12000, step = 0,  labor = 4.0, bolts = 6, pattern = 'circle',  prop = 'turbo',   cabinet = 'engine', doors = { 4 }, toggle = true,
             effects = { power = 1.04 } },
    [14] = { label = 'Klakson',           group = 'extras', cam = 'front',   anchor = 'bumper_f', price = 350,  step = 50,  labor = 0.3, bolts = 2, pattern = 'line',    prop = 'small',   cabinet = 'body' },
    [22] = { label = 'Ksenony',           group = 'lights', cam = 'front',   anchor = 'bumper_f', price = 1200, step = 0,   labor = 0.8, bolts = 2, pattern = 'line',    prop = 'small',   cabinet = 'body', doors = { 4 }, toggle = true },
    [20] = { label = 'Kolorowy dym opon', group = 'wheels', cam = 'wheel_fl', anchor = 'wheel',   price = 900,  step = 0,   labor = 0.2, bolts = 0, pattern = 'none',    prop = 'small',   cabinet = 'wheels', toggle = true },
    [25] = { label = 'Ramka tablicy',     group = 'extras', cam = 'rear',    anchor = 'plate_r',  price = 250,  step = 50,  labor = 0.2, bolts = 2, pattern = 'line',    prop = 'small',   cabinet = 'body' },
    [26] = { label = 'Tablice ozdobne',   group = 'extras', cam = 'front',   anchor = 'bumper_f', price = 250,  step = 50,  labor = 0.2, bolts = 2, pattern = 'line',    prop = 'small',   cabinet = 'body' },
    [27] = { label = 'Wykończenie A',     group = 'interior', cam = 'interior', anchor = 'interior', price = 600, step = 120, labor = 0.6, bolts = 4, pattern = 'corners', prop = 'small', cabinet = 'body', doors = { 0 } },
    [28] = { label = 'Ozdoby',            group = 'interior', cam = 'interior', anchor = 'interior', price = 300, step = 60,  labor = 0.3, bolts = 2, pattern = 'line', prop = 'small', cabinet = 'body', doors = { 0 } },
    [29] = { label = 'Deska rozdzielcza', group = 'interior', cam = 'interior', anchor = 'interior', price = 900, step = 150, labor = 1.2, bolts = 6, pattern = 'line', prop = 'panel', cabinet = 'body', doors = { 0 } },
    [30] = { label = 'Zegary',            group = 'interior', cam = 'interior', anchor = 'interior', price = 700, step = 120, labor = 0.8, bolts = 4, pattern = 'corners', prop = 'small', cabinet = 'body', doors = { 0 } },
    [31] = { label = 'Głośniki w drzwiach', group = 'interior', cam = 'side_l', anchor = 'door_l', price = 500, step = 100, labor = 0.8, bolts = 4, pattern = 'circle', prop = 'small', cabinet = 'body', doors = { 0 } },
    [32] = { label = 'Fotele',            group = 'interior', cam = 'interior', anchor = 'interior', price = 1300, step = 250, labor = 1.5, bolts = 4, pattern = 'corners', prop = 'seat', cabinet = 'body', doors = { 0, 1 } },
    [33] = { label = 'Kierownica',        group = 'interior', cam = 'interior', anchor = 'steering', price = 800, step = 150, labor = 0.6, bolts = 3, pattern = 'circle', prop = 'steering', cabinet = 'body', doors = { 0 } },
    [34] = { label = 'Gałka zmiany biegów', group = 'interior', cam = 'interior', anchor = 'interior', price = 250, step = 50, labor = 0.2, bolts = 1, pattern = 'circle', prop = 'small', cabinet = 'body', doors = { 0 } },
    [35] = { label = 'Plakietki',         group = 'interior', cam = 'interior', anchor = 'interior', price = 200, step = 40,  labor = 0.2, bolts = 2, pattern = 'line', prop = 'small', cabinet = 'body', doors = { 0 } },
    [36] = { label = 'Nagłośnienie',      group = 'interior', cam = 'trunk',  anchor = 'trunk',    price = 1400, step = 250, labor = 1.5, bolts = 6, pattern = 'grid',    prop = 'box',     cabinet = 'body', doors = { 5 } },
    [37] = { label = 'Bagażnik',          group = 'interior', cam = 'trunk',  anchor = 'trunk',    price = 900,  step = 150, labor = 1.0, bolts = 4, pattern = 'corners', prop = 'box',     cabinet = 'body', doors = { 5 } },
    [38] = { label = 'Hydraulika',        group = 'extras', cam = 'under',    anchor = 'under_front', price = 3500, step = 600, labor = 3.0, bolts = 6, pattern = 'grid', prop = 'engine_part', cabinet = 'perf', lift = 'ramp' },
    [39] = { label = 'Blok silnika',      group = 'perf', cam = 'engine',     anchor = 'engine',   price = 1500, step = 300, labor = 1.5, bolts = 6, pattern = 'grid',    prop = 'engine_part', cabinet = 'engine', doors = { 4 } },
    [40] = { label = 'Obudowa filtra',    group = 'perf', cam = 'engine',     anchor = 'engine',   price = 700,  step = 150, labor = 0.5, bolts = 4, pattern = 'corners', prop = 'small',   cabinet = 'engine', doors = { 4 } },
    [41] = { label = 'Rozpórki',          group = 'perf', cam = 'engine',     anchor = 'engine',   price = 900,  step = 200, labor = 0.8, bolts = 4, pattern = 'line',    prop = 'small',   cabinet = 'perf', doors = { 4 },
             effects = { antiroll = 1.02 } },
    [42] = { label = 'Nadkola',           group = 'body', cam = 'side_l',     anchor = 'fender_l', price = 800,  step = 150, labor = 0.8, bolts = 4, pattern = 'line',    prop = 'panel',   cabinet = 'body' },
    [43] = { label = 'Anteny',            group = 'extras', cam = 'roof',     anchor = 'roof',     price = 200,  step = 40,  labor = 0.2, bolts = 1, pattern = 'circle',  prop = 'small',   cabinet = 'body' },
    [44] = { label = 'Wykończenie B',     group = 'body', cam = 'side_l',     anchor = 'door_l',   price = 500,  step = 100, labor = 0.5, bolts = 4, pattern = 'line',    prop = 'panel',   cabinet = 'body' },
    [45] = { label = 'Zbiornik paliwa',   group = 'extras', cam = 'rear',     anchor = 'bumper_r', price = 600,  step = 120, labor = 0.8, bolts = 4, pattern = 'corners', prop = 'box',     cabinet = 'body' },
    [46] = { label = 'Szyby',             group = 'body', cam = 'side_l',     anchor = 'door_l',   price = 600,  step = 120, labor = 0.8, bolts = 4, pattern = 'corners', prop = 'panel',   cabinet = 'body' },
    [48] = { label = 'Oklejenie (livery)',group = 'paint', cam = 'side_l',    anchor = 'door_l',   price = 1800, step = 200, labor = 1.5, bolts = 0, pattern = 'none',    prop = 'roll',    cabinet = 'paint' },
}

-- --------------------------------------------------------------------------
--  KOŁA
-- --------------------------------------------------------------------------
Config.WheelTypes = {
    { id = 0,  label = 'Sportowe' },
    { id = 1,  label = 'Muscle' },
    { id = 2,  label = 'Lowrider' },
    { id = 3,  label = 'SUV' },
    { id = 4,  label = 'Terenowe' },
    { id = 5,  label = 'Tuner' },
    { id = 7,  label = 'High-end' },
    { id = 8,  label = 'Benny\'s Original' },
    { id = 9,  label = 'Benny\'s Bespoke' },
    { id = 10, label = 'Open Wheel' },
    { id = 11, label = 'Street' },
    { id = 12, label = 'Track' },
}
Config.WheelLabor = 0.4  -- h za koło (demontaż + montaż + wyważenie liczone osobno w procedurze)

-- --------------------------------------------------------------------------
--  LAKIER
--  finish – „tekstura” lakieru GTA: 0 normalny, 1 metalik, 2 perła, 3 mat, 4 metal, 5 chrom
-- --------------------------------------------------------------------------
Config.PaintFinishes = {
    { id = 0, label = 'Klasyczny' },
    { id = 1, label = 'Metalik' },
    { id = 2, label = 'Perłowy' },
    { id = 3, label = 'Matowy' },
    { id = 4, label = 'Metal szczotkowany' },
    { id = 5, label = 'Chrom' },
}

Config.PaintPrices = {
    primary = 1800, secondary = 900, pearl = 700, wheels = 450, interior = 500, dashboard = 400,
    neonKit = 2200, neonColor = 300, xenonColor = 300, tint = 450, plate = 150, smoke = 250, extra = 200,
    labor = { primary = 2.5, secondary = 1.5, pearl = 1.0, wheels = 0.8, interior = 1.0, dashboard = 0.6, neon = 1.5, tint = 0.8, plate = 0.1, smoke = 0.1, extra = 0.3 },
}

Config.PaintPresets = {
    { label = 'Rosso Corsa',          rgb = { 204, 0, 0 },     finish = 1 },
    { label = 'Guards Red',           rgb = { 190, 16, 22 },   finish = 0 },
    { label = 'Candy Apple',          rgb = { 150, 6, 18 },    finish = 2, pearl = 27 },
    { label = 'Sunset Orange',        rgb = { 255, 105, 20 },  finish = 1 },
    { label = 'Lava Orange',          rgb = { 232, 72, 12 },   finish = 2, pearl = 38 },
    { label = 'Giallo Modena',        rgb = { 255, 205, 0 },   finish = 1 },
    { label = 'Lime Green',           rgb = { 130, 220, 20 },  finish = 2, pearl = 92 },
    { label = 'British Racing Green', rgb = { 0, 66, 37 },     finish = 1 },
    { label = 'Miami Blue',           rgb = { 0, 180, 220 },   finish = 0 },
    { label = 'Bayside Blue',         rgb = { 20, 60, 190 },   finish = 2, pearl = 70 },
    { label = 'Midnight Purple',      rgb = { 45, 15, 80 },    finish = 2, pearl = 145 },
    { label = 'Frozen Blue',          rgb = { 70, 110, 150 },  finish = 3 },
    { label = 'Nardo Grey',           rgb = { 120, 122, 120 }, finish = 0 },
    { label = 'Liquid Silver',        rgb = { 190, 195, 200 }, finish = 1 },
    { label = 'Pearl White',          rgb = { 240, 240, 236 }, finish = 2, pearl = 111 },
    { label = 'Matte Black',          rgb = { 18, 18, 18 },    finish = 3 },
    { label = 'Obsidian',             rgb = { 8, 8, 12 },      finish = 1 },
    { label = 'Satin Graphite',       rgb = { 55, 58, 62 },    finish = 3 },
    { label = 'Chrome',               rgb = { 200, 200, 200 }, finish = 5 },
    { label = 'Brushed Titanium',     rgb = { 150, 150, 155 }, finish = 4 },
    { label = 'Rose Gold',            rgb = { 200, 140, 120 }, finish = 2, pearl = 107 },
    { label = 'Military Olive',       rgb = { 80, 85, 50 },    finish = 3 },
    { label = 'Hot Pink',             rgb = { 255, 50, 150 },  finish = 1 },
    { label = 'Plum Crazy',           rgb = { 110, 30, 130 },  finish = 1 },
}

-- perła / kolory kół / wnętrza – indeksy palety GTA
Config.PalettePresets = {
    { id = 0,   label = 'Czarny',       hex = '#0d1116' },
    { id = 1,   label = 'Grafit',       hex = '#1c1d21' },
    { id = 4,   label = 'Srebrny',      hex = '#bcbcbf' },
    { id = 5,   label = 'Srebrno-niebieski', hex = '#8a9cad' },
    { id = 111, label = 'Biały',        hex = '#f0f0f0' },
    { id = 27,  label = 'Czerwony',     hex = '#c00e1a' },
    { id = 35,  label = 'Karmin',       hex = '#8f1d1d' },
    { id = 38,  label = 'Pomarańczowy', hex = '#f78616' },
    { id = 89,  label = 'Żółty',        hex = '#fbe212' },
    { id = 92,  label = 'Limonka',      hex = '#98d223' },
    { id = 53,  label = 'Zielony',      hex = '#155c2d' },
    { id = 70,  label = 'Niebieski',    hex = '#0b9cf1' },
    { id = 64,  label = 'Granat',       hex = '#1e3264' },
    { id = 145, label = 'Fiolet',       hex = '#621276' },
    { id = 135, label = 'Róż',          hex = '#f21f99' },
    { id = 107, label = 'Beż',          hex = '#c9a27a' },
    { id = 90,  label = 'Brąz',         hex = '#4d2d1a' },
    { id = 158, label = 'Złoto',        hex = '#c2944f' },
    { id = 117, label = 'Stal szczotkowana', hex = '#6a7172' },
    { id = 120, label = 'Chrom',        hex = '#d8d8d8' },
}

Config.NeonPresets = {
    { label = 'Biały',      rgb = { 222, 222, 255 } },
    { label = 'Niebieski',  rgb = { 2, 21, 255 } },
    { label = 'Elektryk',   rgb = { 3, 83, 255 } },
    { label = 'Miętowy',    rgb = { 0, 255, 140 } },
    { label = 'Limonka',    rgb = { 94, 255, 1 } },
    { label = 'Żółty',      rgb = { 255, 255, 0 } },
    { label = 'Złoty',      rgb = { 255, 150, 0 } },
    { label = 'Pomarańcz',  rgb = { 255, 62, 0 } },
    { label = 'Czerwony',   rgb = { 255, 1, 1 } },
    { label = 'Różowy',     rgb = { 255, 50, 100 } },
    { label = 'Fuksja',     rgb = { 255, 5, 190 } },
    { label = 'Fiolet',     rgb = { 35, 1, 255 } },
}

Config.XenonColors = {
    { id = -1, label = 'Fabryczny',  hex = '#e8f0ff' },
    { id = 0,  label = 'Biały',      hex = '#ffffff' },
    { id = 1,  label = 'Niebieski',  hex = '#2d6bff' },
    { id = 2,  label = 'Elektryk',   hex = '#58a8ff' },
    { id = 3,  label = 'Miętowy',    hex = '#6affc0' },
    { id = 4,  label = 'Limonka',    hex = '#aaff3b' },
    { id = 5,  label = 'Żółty',      hex = '#fff23b' },
    { id = 6,  label = 'Złoty',      hex = '#ffc83b' },
    { id = 7,  label = 'Pomarańcz',  hex = '#ff8a2d' },
    { id = 8,  label = 'Czerwony',   hex = '#ff2d2d' },
    { id = 9,  label = 'Różowy',     hex = '#ff6ec7' },
    { id = 10, label = 'Fuksja',     hex = '#ff2dd2' },
    { id = 11, label = 'Fiolet',     hex = '#a42dff' },
    { id = 12, label = 'Blacklight', hex = '#5b2dff' },
}

Config.WindowTints = {
    { id = 0, label = 'Brak' },
    { id = 4, label = 'Lekko przyciemniane' },
    { id = 5, label = 'Ciemny dym' },
    { id = 3, label = 'Lekki dym' },
    { id = 1, label = 'Czarne (limo)' },
    { id = 6, label = 'Zielone' },
}

Config.PlateTypes = {
    { id = 0, label = 'Niebieska na białym 1' },
    { id = 3, label = 'Niebieska na białym 2' },
    { id = 4, label = 'Niebieska na białym 3' },
    { id = 1, label = 'Żółta na czarnym' },
    { id = 2, label = 'Żółta na niebieskim' },
    { id = 5, label = 'Yankton' },
}
