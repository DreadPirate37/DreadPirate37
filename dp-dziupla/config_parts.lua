-- ==========================================================================
--  CZĘŚCI I ICH MOCOWANIA
--
--  Każda część ma kotwicę (kość pojazdu albo zapas liczony z wymiarów modelu)
--  i listę elementów złącznych (F). Pozycje są w metrach w układzie pojazdu,
--  względem kotwicy: x = w bok, y = do przodu, z = do góry.
--  Dla części bocznych (side = -1 lewa / +1 prawa) x oznacza „na zewnątrz”
--  i jest mnożone przez side, więc jeden opis obsługuje obie strony.
--
--  Typy elementów złącznych (F.t):
--    bolt / nut   – śruba / nakrętka, rozmiar nasadki size (mm lub 'T50'), rust = szansa na rdzę,
--                   cut = można ją przeciąć szlifierką zamiast odkręcać
--    terminal     – klema akumulatora (sign '-' / '+'), minus zawsze pierwszy!
--    drain        – korek spustowy (fluid), podstaw miskę zanim odkręcisz
--    screw        – wkręt (bit 'PH2' / 'T30' ...)
--    clip         – plastikowy klips tapicerki (łyżka), za szybko = pęka
--    hanger       – gumowy wieszak wydechu (łyżka, wolniej)
--    connector    – wtyczka elektryczna (ręka: zatrzask + wyciągnięcie),
--                   airbag = żółta wtyczka poduszki, sensitive = elektronika wrażliwa na zwarcie
--    hose         – wąż z opaską (szczypce), fluid = płyn, który się wyleje, jeśli go nie spuściłeś
--    cut          – linia cięcia (pts), tool 'grinder' albo 'wire'
--    stamp        – znak VIN do wybicia puncerem (przebitka)
--    hoist        – podniesienie żurawiem (ostatni krok silnika / skrzyni)
--  after = { indeksy } – element pojawia się dopiero po zdjęciu wskazanych (warstwy jak w CMS)
-- ==========================================================================
Parts = {}

local function V(x, y, z) return vec3(x, y, z) end

-- --------------------------------------------------------------------------
--  Typy części: nazwa, kategoria rynku, wartość bazowa ($ u pasera przy 100%),
--  masa, rekwizyt do noszenia, XP, rodzaj regeneracji na stole
-- --------------------------------------------------------------------------
Parts.Types = {
    wheel      = { label = 'Koło',                      cat = 'wheels',   base = 220,  kg = 18,  prop = 'prop_wheel_01',        carry = 'wheel', xp = 8,  bench = 'split' },
    brake      = { label = 'Zacisk z tarczą',           cat = 'wheels',   base = 160,  kg = 9,   prop = 'prop_rub_carpart_04',  carry = 'box',   xp = 8,  bench = 'clean' },
    shock      = { label = 'Amortyzator',               cat = 'wheels',   base = 120,  kg = 5,   prop = 'prop_rub_carpart_03',  carry = 'box',   xp = 8,  bench = 'clean' },
    door       = { label = 'Drzwi',                     cat = 'body',     base = 260,  kg = 22,  prop = 'prop_car_door_01',     carry = 'door',  xp = 12, bench = 'dents' },
    bonnet     = { label = 'Maska',                     cat = 'body',     base = 240,  kg = 16,  prop = 'prop_car_bonnet_01',   carry = 'panel', xp = 10, bench = 'dents' },
    boot       = { label = 'Klapa bagażnika',           cat = 'body',     base = 200,  kg = 14,  prop = 'prop_car_bonnet_02',   carry = 'panel', xp = 10, bench = 'dents' },
    bumper     = { label = 'Zderzak',                   cat = 'body',     base = 180,  kg = 8,   prop = 'prop_rub_carpart_02',  carry = 'panel', xp = 10, bench = 'dents' },
    spoiler    = { label = 'Spojler',                   cat = 'body',     base = 250,  kg = 6,   prop = 'prop_rub_carpart_05',  carry = 'panel', xp = 8,  bench = 'dents' },
    plate      = { label = 'Tablica rejestracyjna',     cat = 'body',     base = 25,   kg = 1,   prop = 'p_num_plate_01',       carry = 'small', xp = 2 },
    headlight  = { label = 'Reflektor',                 cat = 'lights',   base = 150,  kg = 3,   prop = 'prop_rub_carpart_05',  carry = 'box',   xp = 8,  bench = 'clean' },
    taillight  = { label = 'Lampa tylna',               cat = 'lights',   base = 90,   kg = 2,   prop = 'prop_rub_carpart_05',  carry = 'box',   xp = 6,  bench = 'clean' },
    battery    = { label = 'Akumulator',                cat = 'electro',  base = 110,  kg = 15,  prop = 'prop_car_battery_01',  carry = 'box',   xp = 6 },
    ecu        = { label = 'Sterownik silnika (ECU)',   cat = 'electro',  base = 380,  kg = 2,   prop = 'prop_cs_cardbox_01',   carry = 'small', xp = 10 },
    radio      = { label = 'Radio / multimedia',        cat = 'electro',  base = 260,  kg = 2,   prop = 'prop_cs_cardbox_01',   carry = 'small', xp = 10 },
    airbag     = { label = 'Poduszka powietrzna',       cat = 'electro',  base = 300,  kg = 2,   prop = 'prop_cs_cardbox_01',   carry = 'small', xp = 10 },
    radiator   = { label = 'Chłodnica',                 cat = 'engine',   base = 170,  kg = 7,   prop = 'prop_rub_carpart_02',  carry = 'panel', xp = 10, bench = 'clean' },
    engine     = { label = 'Silnik',                    cat = 'engine',   base = 1400, kg = 160, heavy = true,                              xp = 40, bench = 'clean' },
    turbo      = { label = 'Turbosprężarka',            cat = 'engine',   base = 900,  kg = 10,  prop = 'prop_rub_carpart_04',  carry = 'box',   xp = 15, bench = 'clean' },
    gearbox    = { label = 'Skrzynia biegów',           cat = 'engine',   base = 800,  kg = 60,  heavy = true,                              xp = 30, bench = 'clean' },
    fueltank   = { label = 'Zbiornik paliwa',           cat = 'engine',   base = 120,  kg = 12,  prop = 'prop_rub_carpart_02',  carry = 'box',   xp = 8 },
    catalyst   = { label = 'Katalizator',               cat = 'exhaust',  base = 650,  kg = 6,   prop = 'prop_car_exhaust_01',  carry = 'pipe',  xp = 14 },
    exhaust    = { label = 'Tłumik / wydech',           cat = 'exhaust',  base = 220,  kg = 14,  prop = 'prop_car_exhaust_01',  carry = 'pipe',  xp = 10, bench = 'clean' },
    seat       = { label = 'Fotel',                     cat = 'interior', base = 180,  kg = 18,  prop = 'prop_car_seat',        carry = 'seat',  xp = 8,  bench = 'clean' },
    rearseat   = { label = 'Kanapa tylna',              cat = 'interior', base = 140,  kg = 20,  prop = 'prop_car_seat',        carry = 'seat',  xp = 8,  bench = 'clean' },
    steering   = { label = 'Kierownica',                cat = 'interior', base = 90,   kg = 3,   prop = 'prop_cs_cardbox_01',   carry = 'small', xp = 5,  bench = 'clean' },
    windscreen = { label = 'Szyba czołowa',             cat = 'glass',    base = 200,  kg = 14,  prop = 'prop_rub_carpart_05',  carry = 'panel', xp = 12 },
    rearwindow = { label = 'Szyba tylna',               cat = 'glass',    base = 140,  kg = 10,  prop = 'prop_rub_carpart_05',  carry = 'panel', xp = 10 },
    -- powstają przy obróbce, nie zdejmuje się ich z auta
    rim        = { label = 'Felga',                     cat = 'wheels',   base = 165,  kg = 10 },
    tyre       = { label = 'Opona',                     cat = 'wheels',   base = 95,   kg = 8 },
    scrap      = { label = 'Złom stalowy',              cat = 'scrap',    base = 0,    kg = 1,   heavy = true },
}

-- chwyty do noszenia (animacja pudła, kość lewej dłoni)
Parts.Carry = {
    box   = { bone = 60309, pos = V(0.025, 0.08, 0.255), rot = V(-145.0, 290.0, 0.0) },
    small = { bone = 60309, pos = V(0.05, 0.12, 0.22),  rot = V(-145.0, 290.0, 0.0) },
    wheel = { bone = 60309, pos = V(0.10, 0.18, 0.28),  rot = V(-60.0, 100.0, 10.0) },
    door  = { bone = 60309, pos = V(-0.25, 0.25, 0.35), rot = V(-100.0, 250.0, 0.0) },
    panel = { bone = 60309, pos = V(-0.15, 0.25, 0.30), rot = V(-120.0, 270.0, 0.0) },
    seat  = { bone = 60309, pos = V(0.05, 0.25, 0.30),  rot = V(-150.0, 280.0, 0.0) },
    pipe  = { bone = 60309, pos = V(0.00, 0.15, 0.25),  rot = V(-90.0, 270.0, 0.0) },
}

Parts.Flags = {
    ['@oil']        = 'Spuść olej silnikowy',
    ['@gearOil']    = 'Spuść olej ze skrzyni',
    ['@fuel']       = 'Spuść paliwo',
    ['@coolant']    = 'Spuść płyn chłodniczy',
    ['@batteryOff'] = 'Odłącz akumulator',
}

Parts.Fluids = {
    oil = 'olej', gearOil = 'olej przekładniowy', fuel = 'paliwo', coolant = 'płyn chłodniczy', brake = 'płyn hamulcowy',
}

-- nasadki i bity dostępne w narzędziach
Parts.Sockets = { 8, 10, 13, 15, 17, 18, 19, 21, 'T50' }
Parts.Bits = { 'PH1', 'PH2', 'T20', 'T30' }

-- --------------------------------------------------------------------------
--  Pomocnicze generatory
-- --------------------------------------------------------------------------
local function ring(t, n, r, out, extra)
    local list = {}
    for i = 0, n - 1 do
        local a = (i / n) * math.pi * 2 + 0.3
        local f = { t = t, o = V(out, math.cos(a) * r, math.sin(a) * r) }
        for k, v in pairs(extra or {}) do f[k] = v end
        list[#list + 1] = f
    end
    return list
end

local function cat(...)
    local out = {}
    for _, l in ipairs({ ... }) do
        for _, v in ipairs(l) do out[#out + 1] = v end
    end
    return out
end

local WHEELS = {
    { id = 'lf', bone = 'wheel_lf', side = -1, y = 0.62, wheel = 0, lbl = 'LP' },
    { id = 'rf', bone = 'wheel_rf', side = 1,  y = 0.62, wheel = 1, lbl = 'PP' },
    { id = 'lr', bone = 'wheel_lr', side = -1, y = -0.62, wheel = 2, lbl = 'LT' },
    { id = 'rr', bone = 'wheel_rr', side = 1,  y = -0.62, wheel = 3, lbl = 'PT' },
}

local DOORS = {
    { id = 'lf', bone = 'door_dside_f', side = -1, y = 0.22,  door = 0, lbl = 'LP' },
    { id = 'rf', bone = 'door_pside_f', side = 1,  y = 0.22,  door = 1, lbl = 'PP' },
    { id = 'lr', bone = 'door_dside_r', side = -1, y = -0.22, door = 2, lbl = 'LT' },
    { id = 'rr', bone = 'door_pside_r', side = 1,  y = -0.22, door = 3, lbl = 'PT' },
}

-- --------------------------------------------------------------------------
--  Lista części (kolejność = kolejność w oględzinach)
-- --------------------------------------------------------------------------
Parts.List = {}
local function add(p) Parts.List[#Parts.List + 1] = p end

-- tablica
add({
    id = 'plate', type = 'plate', label = 'Tablica rejestracyjna', side = 0,
    anchor = { bone = 'platelight', fb = V(0.0, -1.0, -0.2) },
    lift = { 0, 1 }, pose = 'kneel', stand = { mode = 'rear' },
    cam = { o = V(0.25, -0.75, 0.2), look = V(0, 0, 0), fov = 40 },
    vis = { plate = true }, cond = 'body',
    F = {
        { t = 'screw', bit = 'PH2', o = V(-0.17, 0.0, 0.0) },
        { t = 'screw', bit = 'PH2', o = V(0.17, 0.0, 0.0) },
    },
})

-- koła, hamulce, amortyzatory
for _, w in ipairs(WHEELS) do
    add({
        id = 'wheel_' .. w.id, type = 'wheel', label = 'Koło ' .. w.lbl, side = w.side,
        anchor = { bone = w.bone, fb = V(1.0, w.y, -0.55) },
        avail = function(s) return (s.wheels or 4) > w.wheel end,
        lift = { 1, 2 }, pose = { [1] = 'kneel', [2] = 'stand' }, stand = { mode = 'side' },
        cam = { o = V(1.05, 0.0, 0.12), look = V(0.08, 0, 0), fov = 40 },
        vis = { wheel = w.wheel }, cond = 'tyre:' .. w.bone, mod = { key = 'wheels', mult = 1.45 },
        F = ring('nut', 5, 0.068, 0.11, { size = 19, rust = 0.25 }),
    })
    if w.y > 0 then
        add({
            id = 'brake_' .. w.id, type = 'brake', label = 'Hamulec ' .. w.lbl, side = w.side,
            anchor = { bone = w.bone, fb = V(0.95, w.y, -0.55) },
            requires = { 'wheel_' .. w.id },
            lift = { 1, 2 }, pose = { [1] = 'kneel', [2] = 'stand' }, stand = { mode = 'side' },
            cam = { o = V(0.8, -0.25, 0.15), look = V(0.02, -0.08, 0), fov = 40 },
            cond = 'mech', mod = { key = 'brakes', per = 0.12 },
            F = {
                { t = 'bolt', size = 17, rust = 0.35, o = V(0.03, -0.13, 0.08) },
                { t = 'bolt', size = 17, rust = 0.35, o = V(0.03, -0.13, -0.08) },
                { t = 'hose', fluid = 'brake', o = V(0.0, -0.17, 0.15) },
            },
        })
        add({
            id = 'shock_' .. w.id, type = 'shock', label = 'Amortyzator ' .. w.lbl, side = w.side,
            anchor = { bone = w.bone, fb = V(0.95, w.y, -0.55) },
            requires = { 'brake_' .. w.id },
            lift = { 1, 2 }, pose = { [1] = 'kneel', [2] = 'stand' }, stand = { mode = 'side' },
            cam = { o = V(0.85, 0.1, 0.32), look = V(-0.02, 0, 0.15), fov = 40 },
            cond = 'mech', mod = { key = 'susp', per = 0.10 },
            F = {
                { t = 'clip', o = V(0.0, 0.08, 0.12) },
                { t = 'bolt', size = 18, rust = 0.5, o = V(-0.02, 0.0, 0.20) },
                { t = 'bolt', size = 18, rust = 0.5, o = V(-0.02, 0.05, 0.27) },
            },
        })
    end
end

-- drzwi
for _, d in ipairs(DOORS) do
    add({
        id = 'door_' .. d.id, type = 'door', label = 'Drzwi ' .. d.lbl, side = d.side,
        anchor = { bone = d.bone, fb = V(1.0, d.y, 0.05) },
        avail = function(s) return s.doors and s.doors[d.door + 1] end,
        open = { d.door }, lift = { 0, 1 }, pose = 'stand', stand = { mode = 'side', dy = -0.55 },
        cam = { o = V(0.95, -0.95, 0.15), look = V(-0.03, 0, 0.0), fov = 42 },
        vis = { door = d.door }, cond = 'door:' .. d.door,
        F = {
            { t = 'connector', o = V(-0.06, -0.05, -0.05) },
            { t = 'clip', o = V(-0.03, -0.03, 0.04) },
            { t = 'bolt', size = 13, o = V(-0.02, 0.02, 0.27) },
            { t = 'bolt', size = 13, o = V(-0.02, 0.02, 0.19) },
            { t = 'bolt', size = 13, o = V(-0.02, 0.02, -0.17) },
            { t = 'bolt', size = 13, o = V(-0.02, 0.02, -0.25) },
        },
    })
end

-- maska, klapa, spojler
add({
    id = 'bonnet', type = 'bonnet', label = 'Maska', side = 0,
    anchor = { bone = 'bonnet', fb = V(0.0, 0.55, 0.35) },
    avail = function(s) return s.doors and s.doors[5] end,
    open = { 4 }, lift = { 0, 1 }, pose = 'stand', stand = { mode = 'side', s = -1, dy = 0.4 },
    cam = { o = V(1.3, 0.7, 0.75), look = V(0.0, 0.05, 0.0), fov = 45 },
    vis = { door = 4 }, cond = 'door:4', mod = { key = 'hood', mult = 1.3 },
    F = {
        { t = 'hose', o = V(0.2, 0.15, -0.02) },
        { t = 'bolt', size = 10, o = V(-0.55, 0.0, 0.0) },
        { t = 'bolt', size = 10, o = V(-0.55, 0.08, -0.01) },
        { t = 'bolt', size = 10, o = V(0.55, 0.0, 0.0) },
        { t = 'bolt', size = 10, o = V(0.55, 0.08, -0.01) },
    },
})

add({
    id = 'boot', type = 'boot', label = 'Klapa bagażnika', side = 0,
    anchor = { bone = 'boot', fb = V(0.0, -0.6, 0.35) },
    avail = function(s) return s.doors and s.doors[6] end,
    open = { 5 }, lift = { 0, 1 }, pose = 'stand', stand = { mode = 'side', s = -1, dy = -0.4 },
    cam = { o = V(1.2, -0.75, 0.65), look = V(0, -0.05, 0), fov = 45 },
    vis = { door = 5 }, cond = 'door:5',
    F = {
        { t = 'connector', o = V(0.25, -0.1, -0.02) },
        { t = 'bolt', size = 10, o = V(-0.45, 0.0, 0.0) },
        { t = 'bolt', size = 10, o = V(-0.45, -0.07, 0.0) },
        { t = 'bolt', size = 10, o = V(0.45, 0.0, 0.0) },
        { t = 'bolt', size = 10, o = V(0.45, -0.07, 0.0) },
    },
})

add({
    id = 'spoiler', type = 'spoiler', label = 'Spojler', side = 0,
    anchor = { fb = V(0.0, -0.95, 0.5) },
    avail = function(s) return s.mods and (s.mods.spoiler or -1) >= 0 end,
    lift = { 0, 1 }, pose = 'stand', stand = { mode = 'rear' },
    cam = { o = V(0.9, -1.0, 0.75), look = V(0, 0, 0), fov = 45 },
    vis = { mod = 0 }, cond = 'body',
    F = {
        { t = 'nut', size = 10, o = V(-0.42, 0.0, -0.03) },
        { t = 'nut', size = 10, o = V(-0.32, 0.0, -0.03) },
        { t = 'nut', size = 10, o = V(0.32, 0.0, -0.03) },
        { t = 'nut', size = 10, o = V(0.42, 0.0, -0.03) },
    },
})

-- zderzaki i lampy
add({
    id = 'bumper_f', type = 'bumper', label = 'Zderzak przedni', side = 0,
    anchor = { bone = 'bumper_f', fb = V(0.0, 1.0, -0.35) },
    avail = function(s) return not (s.bumperOff and s.bumperOff.f) end,
    lift = { 0, 1 }, pose = 'kneel', stand = { mode = 'front' },
    cam = { o = V(0.45, 1.55, 0.4), look = V(0, 0, 0), fov = 55 },
    vis = { mod = 1, onlyMod = true }, cond = 'body', mod = { key = 'bumperF', mult = 1.35 },
    F = {
        { t = 'clip', o = V(-0.35, 0.0, 0.14) },
        { t = 'clip', o = V(-0.12, 0.0, 0.15) },
        { t = 'clip', o = V(0.12, 0.0, 0.15) },
        { t = 'clip', o = V(0.35, 0.0, 0.14) },
        { t = 'bolt', size = 10, o = V(-0.75, -0.12, 0.02) },
        { t = 'bolt', size = 10, o = V(0.75, -0.12, 0.02) },
        { t = 'connector', o = V(0.3, -0.05, -0.08) },
    },
})

add({
    id = 'bumper_r', type = 'bumper', label = 'Zderzak tylny', side = 0,
    anchor = { bone = 'bumper_r', fb = V(0.0, -1.0, -0.35) },
    avail = function(s) return not (s.bumperOff and s.bumperOff.r) end,
    lift = { 0, 1 }, pose = 'kneel', stand = { mode = 'rear' },
    cam = { o = V(-0.45, -1.55, 0.4), look = V(0, 0, 0), fov = 55 },
    vis = { mod = 2, onlyMod = true }, cond = 'body', mod = { key = 'bumperR', mult = 1.35 },
    F = {
        { t = 'clip', o = V(-0.35, 0.0, 0.14) },
        { t = 'clip', o = V(-0.12, 0.0, 0.15) },
        { t = 'clip', o = V(0.12, 0.0, 0.15) },
        { t = 'clip', o = V(0.35, 0.0, 0.14) },
        { t = 'bolt', size = 10, o = V(-0.75, 0.12, 0.02) },
        { t = 'bolt', size = 10, o = V(0.75, 0.12, 0.02) },
        { t = 'connector', o = V(-0.3, 0.05, -0.08) },
    },
})

for _, h in ipairs({ { id = 'l', side = -1, lbl = 'lewy' }, { id = 'r', side = 1, lbl = 'prawy' } }) do
    add({
        id = 'headlight_' .. h.id, type = 'headlight', label = 'Reflektor ' .. h.lbl, side = h.side,
        anchor = { bone = 'headlight_' .. h.id, fb = V(0.75, 0.95, 0.05) },
        requires = { 'bumper_f' },
        lift = { 0, 1 }, pose = 'kneel', stand = { mode = 'front' },
        cam = { o = V(0.45, 0.85, 0.35), look = V(-0.05, -0.05, 0), fov = 42 },
        cond = 'hl:' .. h.id, mod = { key = 'xenon', mult = 1.3 },
        F = {
            { t = 'bolt', size = 10, o = V(0.0, -0.05, 0.07) },
            { t = 'bolt', size = 10, o = V(-0.18, -0.05, 0.07) },
            { t = 'bolt', size = 10, o = V(-0.08, -0.06, -0.06) },
            { t = 'connector', o = V(-0.08, -0.15, 0.0) },
        },
    })
    add({
        id = 'taillight_' .. h.id, type = 'taillight', label = 'Lampa tylna ' .. (h.id == 'l' and 'lewa' or 'prawa'), side = h.side,
        anchor = { bone = 'taillight_' .. h.id, fb = V(0.8, -0.97, 0.15) },
        open = { 5 }, lift = { 0, 1 }, pose = 'stand', stand = { mode = 'rear' },
        cam = { o = V(0.35, -0.9, 0.45), look = V(-0.08, 0.05, 0), fov = 42 },
        cond = 'body',
        F = {
            { t = 'nut', size = 8, o = V(-0.08, 0.1, 0.05) },
            { t = 'nut', size = 8, o = V(-0.08, 0.1, -0.05) },
            { t = 'connector', o = V(-0.12, 0.12, 0.0) },
        },
    })
end

-- komora silnika
add({
    id = 'battery', type = 'battery', label = 'Akumulator', side = 0,
    anchor = { bone = 'engine', off = V(-0.38, 0.15, 0.18), fb = V(-0.4, 0.7, 0.1) },
    open = { 4 }, lift = { 0, 1 }, pose = 'stand', stand = { mode = 'side', s = -1 },
    cam = { o = V(-0.7, 0.35, 0.8), look = V(0, 0, 0.05), fov = 42 },
    cond = 'mech',
    F = {
        { t = 'terminal', sign = '+', size = 10, o = V(-0.06, 0.04, 0.1) },
        { t = 'terminal', sign = '-', size = 10, o = V(0.06, 0.04, 0.1), sets = '@batteryOff' },
        { t = 'bolt', size = 13, o = V(0.0, -0.1, 0.02) },
    },
})

add({
    id = 'ecu', type = 'ecu', label = 'Sterownik silnika', side = 0,
    anchor = { bone = 'engine', off = V(0.42, -0.35, 0.12), fb = V(0.4, 0.45, 0.1) },
    open = { 4 }, lift = { 0, 1 }, pose = 'stand', stand = { mode = 'side', s = 1 },
    cam = { o = V(0.75, 0.3, 0.75), look = V(0, 0, 0), fov = 42 },
    cond = 'engine',
    F = {
        { t = 'connector', sensitive = true, o = V(0.0, 0.05, 0.05) },
        { t = 'connector', sensitive = true, o = V(0.07, 0.05, 0.05) },
        { t = 'bolt', size = 10, o = V(-0.08, -0.06, 0.0) },
        { t = 'bolt', size = 10, o = V(0.12, -0.06, 0.0) },
    },
})

add({
    id = 'radiator', type = 'radiator', label = 'Chłodnica', side = 0,
    anchor = { bone = 'engine', off = V(0.0, 0.72, 0.0), fb = V(0.0, 0.85, 0.0) },
    requires = { 'bumper_f' },
    open = { 4 }, lift = { 0, 1 }, pose = 'stand', stand = { mode = 'front' },
    cam = { o = V(0.35, 0.95, 0.55), look = V(0, 0, 0), fov = 50 },
    cond = 'engine',
    F = {
        { t = 'drain', fluid = 'coolant', size = 13, o = V(0.3, 0.05, -0.28), sets = '@coolant' },
        { t = 'hose', fluid = 'coolant', o = V(-0.3, -0.08, 0.18) },
        { t = 'hose', fluid = 'coolant', o = V(0.32, -0.08, -0.18) },
        { t = 'bolt', size = 10, o = V(-0.4, 0.0, 0.25) },
        { t = 'bolt', size = 10, o = V(0.4, 0.0, 0.25) },
    },
})

add({
    id = 'turbo', type = 'turbo', label = 'Turbosprężarka', side = 0,
    anchor = { bone = 'engine', off = V(0.3, 0.05, 0.12), fb = V(0.3, 0.6, 0.1) },
    avail = function(s) return s.mods and s.mods.turbo end,
    open = { 4 }, lift = { 0, 1 }, pose = 'stand', stand = { mode = 'side', s = 1 },
    cam = { o = V(0.7, 0.45, 0.75), look = V(0, 0, 0), fov = 42 },
    vis = { toggle = 18 }, cond = 'engine',
    F = {
        { t = 'hose', fluid = 'oil', o = V(-0.1, 0.08, 0.05) },
        { t = 'nut', size = 13, rust = 0.3, o = V(-0.06, 0.05, 0.08) },
        { t = 'nut', size = 13, rust = 0.3, o = V(0.06, 0.05, 0.08) },
        { t = 'nut', size = 13, rust = 0.3, o = V(-0.06, -0.05, 0.08) },
        { t = 'nut', size = 13, rust = 0.3, o = V(0.06, -0.05, 0.08) },
    },
})

add({
    id = 'engine', type = 'engine', label = 'Silnik', side = 0,
    anchor = { bone = 'engine', fb = V(0.0, 0.62, 0.0) },
    requires = { 'bonnet', 'battery', 'radiator', 'turbo', '@oil' },
    tool = 'hoist', lift = { 0, 0 }, pose = 'stand', stand = { mode = 'side', s = 1 },
    cam = { o = V(0.95, 0.55, 1.1), look = V(0, 0, 0), fov = 50 },
    vis = { undriveable = true }, cond = 'engine', mod = { key = 'engine', per = 0.15 },
    F = {
        { t = 'connector', o = V(-0.2, 0.1, 0.2) },
        { t = 'connector', o = V(0.22, -0.15, 0.18) },
        { t = 'hose', fluid = 'fuel', o = V(0.3, -0.25, 0.1) },
        { t = 'hose', o = V(0.0, 0.2, 0.25) },
        { t = 'bolt', size = 18, rust = 0.4, o = V(-0.35, 0.2, -0.2) },
        { t = 'bolt', size = 18, rust = 0.4, o = V(0.35, 0.2, -0.2) },
        { t = 'bolt', size = 18, rust = 0.4, o = V(-0.35, -0.25, -0.2) },
        { t = 'bolt', size = 18, rust = 0.4, o = V(0.35, -0.25, -0.2) },
        { t = 'hoist', o = V(0.0, 0.0, 0.45), after = { 1, 2, 3, 4, 5, 6, 7, 8 } },
    },
})

-- podwozie (podnośnik na poziomie 2)
add({
    id = 'oil_drain', type = nil, op = true, label = 'Spuszczenie oleju', side = 0,
    anchor = { bone = 'engine', off = V(0.0, 0.05, -0.42), fb = V(0.0, 0.6, -0.65) },
    lift = { 2, 2 }, pose = 'under', stand = { mode = 'under' },
    cam = { o = V(0.65, -0.55, -0.85), look = V(0, -0.2, 0), fov = 55 },
    xp = 5,
    F = {
        { t = 'drain', fluid = 'oil', size = 17, o = V(0.0, 0.0, 0.0), sets = '@oil' },
        { t = 'drain', fluid = 'gearOil', size = 13, o = V(0.05, -0.5, 0.02), sets = '@gearOil' },
    },
})

add({
    id = 'fuel_drain', type = nil, op = true, label = 'Spuszczenie paliwa', side = 0,
    anchor = { fb = V(0.0, -0.45, -0.8) },
    lift = { 2, 2 }, pose = 'under', stand = { mode = 'under' },
    cam = { o = V(0.6, 0.5, -0.85), look = V(0, 0, 0), fov = 50 },
    xp = 4,
    F = {
        { t = 'drain', fluid = 'fuel', size = 13, o = V(0.15, 0.0, 0.0), sets = '@fuel' },
    },
})

add({
    id = 'catalyst', type = 'catalyst', label = 'Katalizator', side = 0,
    anchor = { fb = V(0.0, 0.2, -0.9) },
    lift = { 2, 2 }, pose = 'under', stand = { mode = 'under' },
    cam = { o = V(0.7, 0.0, -0.85), look = V(0, 0, 0), fov = 50 },
    -- na ulicy auto stoi na ziemi: kamera nisko z boku, gracz leży obok
    streetCam = { o = V(1.5, 0.3, 0.05), look = V(0, 0, 0), fov = 55 }, streetPose = 'creeper',
    cond = 'mech',
    F = {
        { t = 'connector', o = V(0.08, 0.28, 0.05) },
        { t = 'bolt', size = 15, rust = 0.7, cut = true, fire = true, o = V(-0.05, 0.3, 0.0) },
        { t = 'bolt', size = 15, rust = 0.7, cut = true, fire = true, o = V(0.05, 0.3, 0.0) },
        { t = 'bolt', size = 15, rust = 0.7, cut = true, fire = true, o = V(-0.05, -0.3, 0.0) },
        { t = 'bolt', size = 15, rust = 0.7, cut = true, fire = true, o = V(0.05, -0.3, 0.0) },
    },
})

add({
    id = 'exhaust', type = 'exhaust', label = 'Tłumik / wydech', side = 0,
    anchor = { bone = 'exhaust', fb = V(0.3, -1.0, -0.6) },
    requires = { 'catalyst' },
    lift = { 2, 2 }, pose = 'under', stand = { mode = 'under' },
    cam = { o = V(0.85, 0.45, -0.75), look = V(0, 0.45, 0), fov = 50 },
    vis = { mod = 4, onlyMod = true }, cond = 'mech', mod = { key = 'exhaust', mult = 1.4 },
    F = {
        { t = 'hanger', o = V(0.0, 0.15, 0.08) },
        { t = 'hanger', o = V(0.0, 0.55, 0.08) },
        { t = 'bolt', size = 13, rust = 0.6, cut = true, fire = true, o = V(0.03, 0.85, 0.02) },
        { t = 'bolt', size = 13, rust = 0.6, cut = true, fire = true, o = V(-0.03, 0.85, 0.02) },
    },
})

add({
    id = 'gearbox', type = 'gearbox', label = 'Skrzynia biegów', side = 0,
    anchor = { bone = 'engine', off = V(0.0, -0.55, -0.25), fb = V(0.0, 0.3, -0.6) },
    requires = { 'engine', '@gearOil' },
    tool = 'hoist', lift = { 2, 2 }, pose = 'under', stand = { mode = 'under' },
    cam = { o = V(0.7, -0.3, -0.9), look = V(0, 0, 0), fov = 50 },
    cond = 'engine', mod = { key = 'trans', per = 0.12 },
    F = {
        { t = 'connector', o = V(0.12, 0.1, -0.05) },
        { t = 'bolt', size = 17, rust = 0.3, o = V(-0.15, 0.15, 0.05) },
        { t = 'bolt', size = 17, rust = 0.3, o = V(0.15, 0.15, 0.05) },
        { t = 'bolt', size = 17, rust = 0.3, o = V(-0.15, 0.15, -0.05) },
        { t = 'bolt', size = 17, rust = 0.3, o = V(0.15, 0.15, -0.05) },
        { t = 'hoist', o = V(0.0, 0.0, -0.2), after = { 1, 2, 3, 4, 5 } },
    },
})

add({
    id = 'fueltank', type = 'fueltank', label = 'Zbiornik paliwa', side = 0,
    anchor = { fb = V(0.0, -0.45, -0.8) },
    requires = { '@fuel' },
    lift = { 2, 2 }, pose = 'under', stand = { mode = 'under' },
    cam = { o = V(0.6, 0.6, -0.85), look = V(0, 0, 0), fov = 50 },
    cond = 'tank',
    F = {
        { t = 'connector', o = V(-0.1, 0.25, 0.05) },
        { t = 'hose', fluid = 'fuel', o = V(0.2, 0.25, 0.05) },
        { t = 'bolt', size = 13, rust = 0.4, cut = true, fire = true, o = V(-0.3, 0.2, 0.0) },
        { t = 'bolt', size = 13, rust = 0.4, cut = true, fire = true, o = V(0.3, 0.2, 0.0) },
    },
})

-- wnętrze
for _, st in ipairs({ { id = 'lf', bone = 'seat_dside_f', side = -1, door = 0, lbl = 'kierowcy' }, { id = 'rf', bone = 'seat_pside_f', side = 1, door = 1, lbl = 'pasażera' } }) do
    add({
        id = 'seat_' .. st.id, type = 'seat', label = 'Fotel ' .. st.lbl, side = st.side,
        anchor = { bone = st.bone, fb = V(0.35, 0.0, -0.1) },
        open = { st.door }, lift = { 0, 0 }, pose = 'inside', stand = { mode = 'side', dy = 0.1 },
        cam = { o = V(0.95, 0.15, 0.35), look = V(0, 0, -0.2), fov = 50 },
        cond = 'interior',
        F = {
            { t = 'connector', airbag = true, o = V(0.2, -0.05, -0.22) },
            { t = 'bolt', size = 'T50', o = V(0.18, 0.22, -0.28) },
            { t = 'bolt', size = 'T50', o = V(-0.18, 0.22, -0.28) },
            { t = 'bolt', size = 'T50', o = V(0.18, -0.25, -0.28) },
            { t = 'bolt', size = 'T50', o = V(-0.18, -0.25, -0.28) },
        },
    })
end

add({
    id = 'rearseat', type = 'rearseat', label = 'Kanapa tylna', side = 0,
    anchor = { bone = 'seat_dside_r', off = V(0.38, 0.0, 0.0), fb = V(0.0, -0.2, -0.1) },
    avail = function(s) return s.bones and s.bones.seat_dside_r end,
    requires = function(s) return (s.doors and s.doors[3]) and {} or { 'seat_lf' } end,
    open = { 2, 0 }, lift = { 0, 0 }, pose = 'inside', stand = { mode = 'side', s = -1, dy = -0.3 },
    cam = { o = V(-1.2, 0.0, 0.4), look = V(0, 0, -0.1), fov = 50 },
    cond = 'interior',
    F = {
        { t = 'clip', o = V(-0.3, -0.1, 0.0) },
        { t = 'clip', o = V(0.3, -0.1, 0.0) },
        { t = 'bolt', size = 13, o = V(-0.35, 0.2, -0.25) },
        { t = 'bolt', size = 13, o = V(0.35, 0.2, -0.25) },
    },
})

add({
    id = 'radio', type = 'radio', label = 'Radio / multimedia', side = 0,
    anchor = { bone = 'steeringwheel', absX = 0.0, off = V(0.0, 0.12, -0.12), fb = V(0.0, 0.25, 0.15) },
    open = { 0 }, lift = { 0, 0 }, pose = 'inside', stand = { mode = 'side', s = -1, dy = -0.2 },
    cam = { o = V(-0.35, -0.55, 0.12), look = V(0, 0, 0), fov = 50 },
    cond = 'interior',
    F = {
        { t = 'clip', o = V(-0.12, 0.0, 0.07) },
        { t = 'clip', o = V(0.12, 0.0, 0.07) },
        { t = 'clip', o = V(-0.12, 0.0, -0.07) },
        { t = 'clip', o = V(0.12, 0.0, -0.07) },
        { t = 'screw', bit = 'PH2', o = V(-0.09, 0.02, 0.05), after = { 1, 2, 3, 4 } },
        { t = 'screw', bit = 'PH2', o = V(0.09, 0.02, 0.05), after = { 1, 2, 3, 4 } },
        { t = 'screw', bit = 'PH2', o = V(-0.09, 0.02, -0.05), after = { 1, 2, 3, 4 } },
        { t = 'screw', bit = 'PH2', o = V(0.09, 0.02, -0.05), after = { 1, 2, 3, 4 } },
        { t = 'connector', o = V(-0.035, 0.08, 0.0), after = { 5, 6, 7, 8 } },
        { t = 'connector', o = V(0.04, 0.08, 0.0), after = { 5, 6, 7, 8 } },
    },
})

add({
    id = 'airbag', type = 'airbag', label = 'Poduszka kierowcy', side = 0,
    anchor = { bone = 'steeringwheel', fb = V(-0.35, 0.2, 0.2) },
    open = { 0 }, lift = { 0, 0 }, pose = 'inside', stand = { mode = 'side', s = -1 },
    cam = { o = V(0.15, -0.5, 0.15), look = V(0, 0, 0), fov = 45 },
    cond = 'interior',
    F = {
        { t = 'screw', bit = 'T30', o = V(-0.13, 0.06, 0.0) },
        { t = 'screw', bit = 'T30', o = V(0.13, 0.06, 0.0) },
        { t = 'connector', airbag = true, o = V(0.0, 0.05, -0.04), after = { 1, 2 } },
    },
})

add({
    id = 'steering', type = 'steering', label = 'Kierownica', side = 0,
    anchor = { bone = 'steeringwheel', fb = V(-0.35, 0.2, 0.2) },
    requires = { 'airbag' },
    open = { 0 }, lift = { 0, 0 }, pose = 'inside', stand = { mode = 'side', s = -1 },
    cam = { o = V(0.15, -0.5, 0.15), look = V(0, 0, 0), fov = 45 },
    cond = 'interior',
    F = {
        { t = 'nut', size = 21, o = V(0.0, 0.0, 0.0) },
        { t = 'connector', o = V(0.0, 0.06, -0.06), after = { 1 } },
    },
})

-- szyby (struna)
add({
    id = 'windscreen', type = 'windscreen', label = 'Szyba czołowa', side = 0,
    anchor = { bone = 'windscreen', fb = V(0.0, 0.28, 0.45) },
    avail = function(s) return s.windows and s.windows.front end,
    lift = { 0, 0 }, pose = 'stand', stand = { mode = 'front' },
    cam = { o = V(0.9, 1.35, 0.95), look = V(0, 0, 0), fov = 50 },
    vis = { window = 6 }, cond = 'body',
    F = {
        { t = 'cut', tool = 'wire', closed = true, pts = { V(-0.62, 0.16, -0.2), V(0.62, 0.16, -0.2), V(0.55, -0.16, 0.2), V(-0.55, -0.16, 0.2) } },
    },
})

add({
    id = 'rearwindow', type = 'rearwindow', label = 'Szyba tylna', side = 0,
    anchor = { bone = 'windscreen_r', fb = V(0.0, -0.45, 0.45) },
    avail = function(s) return s.windows and s.windows.rear end,
    lift = { 0, 0 }, pose = 'stand', stand = { mode = 'rear' },
    cam = { o = V(0.8, -1.3, 0.85), look = V(0, 0, 0), fov = 50 },
    vis = { window = 7 }, cond = 'body',
    F = {
        { t = 'cut', tool = 'wire', closed = true, pts = { V(-0.55, -0.14, -0.18), V(0.55, -0.14, -0.18), V(0.5, 0.14, 0.18), V(-0.5, 0.14, 0.18) } },
    },
})

-- karoseria: pocięcie „skorupy” po zdjęciu najważniejszych części
add({
    id = 'shell', type = 'scrap', label = 'Pocięcie karoserii', side = 0, shell = true,
    anchor = { fb = V(0.0, 0.0, 0.0) },
    requires = { 'door_lf', 'door_rf', 'door_lr', 'door_rr', 'bonnet', 'boot', 'wheel_lf', 'wheel_rf', 'wheel_lr', 'wheel_rr', 'engine', 'gearbox', 'fueltank' },
    lift = { 0, 0 }, pose = 'stand', stand = { mode = 'side', s = -1 },
    cam = { o = V(0.0, -0.4, 4.6), look = V(0, 0.05, 0), fov = 55 },
    xp = 20,
    F = {
        { t = 'cut', tool = 'grinder', fire = true, pts = { V(-0.62, 0.35, 0.55), V(-0.75, 0.85, 0.15) } },
        { t = 'cut', tool = 'grinder', fire = true, pts = { V(0.62, 0.35, 0.55), V(0.75, 0.85, 0.15) } },
        { t = 'cut', tool = 'grinder', fire = true, pts = { V(-0.62, -0.55, 0.55), V(-0.75, -1.05, 0.2) } },
        { t = 'cut', tool = 'grinder', fire = true, pts = { V(0.62, -0.55, 0.55), V(0.75, -1.05, 0.2) } },
    },
})

-- --------------------------------------------------------------------------
--  Przebitka VIN (tryb 'revin')
-- --------------------------------------------------------------------------
local stamps = {}
for i = 0, 7 do stamps[#stamps + 1] = { t = 'stamp', o = V(-0.105 + i * 0.03, 0.0, 0.0) } end

add({
    id = 'vin_grind', type = nil, op = true, revin = true, label = 'Zeszlifowanie starego VIN', side = 0,
    anchor = { bone = 'engine', off = V(0.0, -0.5, 0.25), fb = V(0.0, 0.3, 0.2) },
    open = { 4 }, lift = { 0, 0 }, pose = 'stand', stand = { mode = 'side', s = -1 },
    cam = { o = V(-0.5, 0.45, 0.7), look = V(0, 0, 0), fov = 38 },
    xp = 10,
    F = { { t = 'cut', tool = 'grinder', pts = { V(-0.13, 0.0, 0.0), V(0.13, 0.0, 0.0) } } },
})

add({
    id = 'vin_stamp', type = nil, op = true, revin = true, label = 'Wybicie nowego VIN', side = 0,
    anchor = { bone = 'engine', off = V(0.0, -0.5, 0.25), fb = V(0.0, 0.3, 0.2) },
    requires = { 'vin_grind' },
    open = { 4 }, lift = { 0, 0 }, pose = 'stand', stand = { mode = 'side', s = -1 },
    cam = { o = V(-0.28, 0.3, 0.42), look = V(0, 0, 0), fov = 36 },
    xp = 20,
    F = stamps,
})

add({
    id = 'plate_swap', type = nil, op = true, revin = true, label = 'Wymiana tablic', side = 0,
    anchor = { bone = 'platelight', fb = V(0.0, -1.0, -0.2) },
    lift = { 0, 0 }, pose = 'kneel', stand = { mode = 'rear' },
    cam = { o = V(0.25, -0.75, 0.2), look = V(0, 0, 0), fov = 40 },
    xp = 5,
    F = {
        { t = 'screw', bit = 'PH2', o = V(-0.17, 0.0, 0.0) },
        { t = 'screw', bit = 'PH2', o = V(0.17, 0.0, 0.0) },
    },
})

-- --------------------------------------------------------------------------
--  Indeksy
-- --------------------------------------------------------------------------
Parts.ById = {}
for i, p in ipairs(Parts.List) do
    p.order = i
    Parts.ById[p.id] = p
end

Parts.Modes = { chop = {}, revin = {} }
for _, p in ipairs(Parts.List) do
    local m = p.revin and Parts.Modes.revin or Parts.Modes.chop
    m[#m + 1] = p.id
end
-- szybka kradzież na ulicy (auto stoi na ziemi, bez podnośnika)
Parts.Modes.street = { 'plate', 'wheel_lf', 'wheel_rf', 'wheel_lr', 'wheel_rr', 'catalyst' }

-- kości, które klient sprawdza przy robieniu „zdjęcia” auta
Parts.Bones = {}
do
    local seen = {}
    for _, p in ipairs(Parts.List) do
        local b = p.anchor.bone
        if b and not seen[b] then
            seen[b] = true
            Parts.Bones[#Parts.Bones + 1] = b
        end
    end
end
