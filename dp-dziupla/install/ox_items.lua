-- ==========================================================================
--  Itemy dp-dziupla dla ox_inventory – wklej do ox_inventory/data/items.lua
--  (tylko gdy Config.Inventory.mode = 'auto' / 'ox'). 'lockpick' zwykle już istnieje.
-- ==========================================================================

['dz_part'] = {
    label = 'Część samochodowa',
    weight = 1000,          -- nadpisywane przez metadata.weight (prawdziwa masa części)
    stack = false,          -- każda część ma własny stan i pochodzenie w metadanych
    close = true,
    description = 'Część z dziupli. Stan i pochodzenie w opisie.',
},

['dz_penetrant'] = {
    label = 'Penetrant (odrdzewiacz)',
    weight = 400,
    stack = true,
    description = 'Ułatwia odkręcanie zapieczonych śrub.',
},

['dz_disc'] = {
    label = 'Tarcza do szlifierki',
    weight = 150,
    stack = true,
},

['dz_extractor'] = {
    label = 'Wykrętak do śrub',
    weight = 60,
    stack = true,
    description = 'Do ukręconych i zaokrąglonych śrub.',
},

-- jeśli nie masz jeszcze wytrycha:
-- ['lockpick'] = { label = 'Wytrych', weight = 100, stack = true },
