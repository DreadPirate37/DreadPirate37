-- ==========================================================================
--  ŁUP (LUP-01, LUP-02, LUP-03, LUP-07)
--  kg = waga, value = zakres ceny u pasera przed prowizją, cat = kategoria dla paserów,
--  large = noszone w rękach (nie mieści się w torbie, idzie do bagażnika), prop = model propa
-- ==========================================================================
Config.Loot = {
    -- duże: w rękach, do bagażnika
    telewizor    = { label = 'Telewizor',            cat = 'large',       kg = 18,  value = { 260, 520 }, large = true, prop = 'prop_tv_flat_01' },
    komputer     = { label = 'Komputer stacjonarny', cat = 'large',       kg = 12,  value = { 300, 700 }, large = true, prop = 'prop_pc_01a' },
    mikrofalowka = { label = 'Mikrofalówka',         cat = 'large',       kg = 11,  value = { 60, 120 },  large = true, prop = 'prop_micro_01' },
    -- elektronika
    laptop       = { label = 'Laptop',               cat = 'electronics', kg = 2.2, value = { 220, 480 }, prop = 'prop_laptop_01a' },
    tablet       = { label = 'Tablet',               cat = 'electronics', kg = 0.6, value = { 120, 260 }, prop = 'prop_cs_tablet' },
    telefon      = { label = 'Telefon',              cat = 'electronics', kg = 0.2, value = { 90, 240 },  prop = 'prop_npc_phone_02' },
    konsola      = { label = 'Konsola do gier',      cat = 'electronics', kg = 3.0, value = { 180, 320 } },
    glosnik      = { label = 'Głośnik bezprzewodowy',cat = 'electronics', kg = 1.8, value = { 60, 140 },  prop = 'prop_boombox_01' },
    aparat       = { label = 'Aparat fotograficzny', cat = 'electronics', kg = 0.9, value = { 150, 380 } },
    sluchawki    = { label = 'Słuchawki',            cat = 'electronics', kg = 0.3, value = { 40, 120 } },
    -- biżuteria
    zegarek      = { label = 'Zegarek',              cat = 'jewelry',     kg = 0.1, value = { 120, 900 } },
    pierscionek  = { label = 'Pierścionek',          cat = 'jewelry',     kg = 0.02, value = { 90, 600 } },
    naszyjnik    = { label = 'Naszyjnik',            cat = 'jewelry',     kg = 0.05, value = { 110, 700 } },
    bizuteria    = { label = 'Drobna biżuteria',     cat = 'jewelry',     kg = 0.1, value = { 30, 140 } },
    -- alkohol, sztuka, kolekcje
    whisky       = { label = 'Whisky single malt',   cat = 'alcohol',     kg = 1.3, value = { 40, 160 },  prop = 'prop_cs_whiskey_bottle' },
    wino         = { label = 'Wino kolekcjonerskie', cat = 'alcohol',     kg = 1.4, value = { 30, 220 } },
    obraz        = { label = 'Obraz',                cat = 'art',         kg = 4.0, value = { 180, 1200 }, prop = 'ch_prop_vault_painting_01a' },
    figurka      = { label = 'Figurka kolekcjonerska', cat = 'collectibles', kg = 0.4, value = { 60, 400 } },
    karty        = { label = 'Karty kolekcjonerskie',  cat = 'collectibles', kg = 0.2, value = { 40, 500 } },
    monety       = { label = 'Kolekcja monet',       cat = 'collectibles',kg = 0.8, value = { 120, 650 } },
    -- narzędzia z garażu / szopy
    wiertarka    = { label = 'Wiertarka',            cat = 'tools',       kg = 2.1, value = { 60, 160 } },
    szlifierka   = { label = 'Szlifierka',           cat = 'tools',       kg = 2.6, value = { 50, 140 } },
    -- dokumenty (do zleceń)
    dokumenty    = { label = 'Teczka z dokumentami', cat = 'documents',   kg = 0.5, value = { 20, 60 } },
}

-- gotówka nie trafia do torby: od razu jako brudne pieniądze (LUP-14, PAS-12)
Config.CashLabel = 'Gotówka'

-- ==========================================================================
--  MEBLE DO PRZESZUKANIA (LUP-04). time = [s], rolls = ile losowań, table = { klucz, waga }
--  'gotowka' = pieniądze, 'nic' = pusto. Mnożniki z profilu domu zmieniają wagi kategorii.
-- ==========================================================================
Config.Furniture = {
    kitchen    = { label = 'Szafki kuchenne', time = 4.0, rolls = { 1, 2 }, anim = 'search',
                   table = { { 'whisky', 3 }, { 'wino', 3 }, { 'gotowka', 2 }, { 'nic', 6 } } },
    wardrobe   = { label = 'Szafa',           time = 5.0, rolls = { 1, 2 }, anim = 'search',
                   table = { { 'zegarek', 2 }, { 'bizuteria', 3 }, { 'naszyjnik', 1 }, { 'gotowka', 2 }, { 'nic', 4 } } },
    nightstand = { label = 'Szafka nocna',    time = 3.0, rolls = { 1, 1 }, anim = 'low',
                   table = { { 'pierscionek', 2 }, { 'telefon', 2 }, { 'zegarek', 1 }, { 'gotowka', 3 }, { 'nic', 3 } } },
    desk       = { label = 'Biurko',          time = 4.0, rolls = { 1, 2 }, anim = 'search',
                   table = { { 'tablet', 2 }, { 'sluchawki', 3 }, { 'dokumenty', 2 }, { 'aparat', 1 }, { 'gotowka', 1 }, { 'nic', 3 } } },
    dresser    = { label = 'Komoda',          time = 4.0, rolls = { 1, 2 }, anim = 'low',
                   table = { { 'bizuteria', 3 }, { 'naszyjnik', 1 }, { 'gotowka', 2 }, { 'nic', 4 } } },
    shelf      = { label = 'Regał',           time = 3.5, rolls = { 1, 1 }, anim = 'search',
                   table = { { 'figurka', 2 }, { 'karty', 2 }, { 'monety', 1 }, { 'konsola', 2 }, { 'nic', 3 } } },
    toolchest  = { label = 'Skrzynka z narzędziami', time = 4.0, rolls = { 1, 2 }, anim = 'low',
                   table = { { 'wiertarka', 3 }, { 'szlifierka', 2 }, { 'nic', 2 } } },
    bathroom   = { label = 'Szafka łazienkowa', time = 2.5, rolls = { 1, 1 }, anim = 'search',
                   table = { { 'zegarek', 1 }, { 'gotowka', 1 }, { 'nic', 6 } } },
}

-- mnożniki kategorii wg archetypu (LUP-07)
Config.LootProfile = {
    singiel = { electronics = 1.4, collectibles = 1.2 },
    para    = { jewelry = 1.3, alcohol = 1.2 },
    emeryt  = { jewelry = 1.5, cash = 1.8, electronics = 0.6, collectibles = 1.3 },
    nocny   = { electronics = 1.3, alcohol = 1.3 },
}

-- widoczne łupy w slotach wnętrza (LUP-05): slot -> możliwe przedmioty i szansa na pojawienie się
Config.LootSlots = {
    tv       = { chance = 0.9,  items = { 'telewizor' } },
    pc       = { chance = 0.55, items = { 'komputer' } },
    micro    = { chance = 0.7,  items = { 'mikrofalowka' } },
    laptop   = { chance = 0.6,  items = { 'laptop', 'tablet' } },
    speaker  = { chance = 0.5,  items = { 'glosnik' } },
    bottle   = { chance = 0.5,  items = { 'whisky' } },
    painting = { chance = 0.35, items = { 'obraz' } },
}
