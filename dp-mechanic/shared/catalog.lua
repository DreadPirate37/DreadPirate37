-- ==========================================================================
--  Katalog części (pozycje magazynowe) i budowanie pozycji zleceń.
--  Ceny i robocizna ZAWSZE liczone po stronie serwera z configu – klient
--  przysyła tylko „co” chce zamontować.
-- ==========================================================================
Catalog = { items = {} }
local items = Catalog.items

local function add(key, label, price, cabinet, prop)
    items[key] = { key = key, label = label, price = math.floor(price), cabinet = cabinet, prop = prop or 'default' }
end

for t, m in pairs(Config.ModTypes) do
    add('mod_' .. t, m.label .. ' (zestaw)', m.price, m.cabinet or 'body', m.prop)
end
for id, p in pairs(Config.PerfParts) do
    for lvl, l in ipairs(p.levels) do
        add(('perf_%s_%d'):format(id, lvl), p.label .. ' – ' .. l.label, l.price, p.cabinet or 'perf', 'default')
    end
end
for id, p in pairs(Config.Wear.parts) do
    local prop = 'default'
    if id == 'battery' then prop = 'battery'
    elseif id == 'oil' or id == 'coolant' or id == 'brake_fluid' or id == 'gearbox_oil' then prop = 'fluid'
    elseif id == 'brake_discs' or id == 'brake_pads' then prop = 'brake'
    elseif id == 'shocks' then prop = 'spring' end
    add('wear_' .. id, p.label, p.price, p.cabinet or 'wear', prop)
end
for id, c in pairs(Config.TireCompounds) do
    add('tire_' .. id, 'Opona – ' .. c.label, c.price, 'wheels', 'tire')
end
add('rim', 'Felga', Config.RimPrice, 'wheels', 'wheel')
add('weights', 'Ciężarki do wyważania (taśma)', 15, 'wheels', 'small')
add('paint_can', 'Lakier (puszka 1 L)', 250, 'paint', 'fluid')
add('neon_kit', 'Zestaw neonów LED', Config.PaintPrices.neonKit, 'body', 'small')
add('align_kit', 'Zestaw do geometrii (drążki, końcówki)', 120, 'perf', 'small')
add('inspection_kit', 'Zestaw przeglądowy (filtry, uszczelki)', 90, 'wear', 'small')
for id, e in pairs(Config.Engines) do
    if id ~= 'stock' then add('swap_engine_' .. id, 'Silnik – ' .. e.label, e.price, 'swap', 'engine_part') end
end
for id, e in pairs(Config.Drivetrains) do
    if id ~= 'stock' then add('swap_drivetrain_' .. id, 'Napęd – ' .. e.label, e.price, 'swap', 'engine_part') end
end
for id, e in pairs(Config.BrakeKits) do
    if id ~= 'stock' then add('swap_brakes_' .. id, 'Hamulce – ' .. e.label, e.price, 'swap', 'brake') end
end
for id, e in pairs(Config.Gearboxes) do
    if id ~= 'stock' then add('swap_gearbox_' .. id, 'Skrzynia – ' .. e.label, e.price, 'swap', 'engine_part') end
end
for id, k in pairs(Config.Nitro.kits) do
    add('nitro_' .. id, k.label, k.price, 'nitro', 'nitro')
end
add('nitro_bottle', 'Butla N2O (napełniona)', Config.Nitro.refillPrice, 'nitro', 'nitro')

Catalog.SwapTables = {
    engine = Config.Engines, drivetrain = Config.Drivetrains, brakes = Config.BrakeKits, gearbox = Config.Gearboxes,
}
Catalog.SwapLabels = { engine = 'Silnik', drivetrain = 'Napęd', brakes = 'Hamulce', gearbox = 'Skrzynia biegów' }

Catalog.PaintKeys = {
    primary = { label = 'Lakier główny', stock = 'paint_can' },
    secondary = { label = 'Lakier dodatkowy', stock = 'paint_can' },
    pearl = { label = 'Perła' , stock = 'paint_can' },
    wheels = { label = 'Kolor felg', stock = 'paint_can' },
    interior = { label = 'Kolor wnętrza', stock = 'paint_can' },
    dashboard = { label = 'Kolor deski', stock = 'paint_can' },
    neon = { label = 'Neony', stock = 'neon_kit', laborKey = 'neon', priceKey = 'neonKit' },
    neonColor = { label = 'Kolor neonów', laborKey = 'neon' },
    xenonColor = { label = 'Kolor ksenonów', laborKey = 'plate' },
    tint = { label = 'Przyciemnienie szyb' },
    plate = { label = 'Typ tablicy' },
    smoke = { label = 'Kolor dymu opon' },
}

local function modTypeCfg(t) return Config.ModTypes[tonumber(t)] end

-- sprawdza wartość z klienta i buduje pełną pozycję zlecenia
-- zwraca nil, jeśli pozycja jest niepoprawna
function Catalog.Build(kind, key, v, name)
    local it = { k = kind, key = key, v = v, done = false }
    if kind == 'mod' then
        local m = modTypeCfg(key)
        if not m then return nil end
        it.key = tonumber(key)
        if m.toggle then
            it.v = v == true
            it.price = it.v and m.price or 0
            it.label = m.label .. (it.v and ' – montaż' or ' – demontaż')
        else
            local lvl = tonumber(v)
            if not lvl or lvl < -1 or lvl > 80 then return nil end
            it.v = math.floor(lvl)
            it.price = it.v >= 0 and (m.price + m.step * it.v) or 0
            local nm = type(name) == 'string' and name:sub(1, 48) or (it.v >= 0 and ('#' .. (it.v + 1)) or 'Fabryczny')
            it.label = m.label .. ' – ' .. nm
        end
        it.labor = (it.price > 0) and m.labor or m.labor * 0.5
        it.stock = it.price > 0 and ('mod_' .. it.key) or nil
        it.anchor, it.cam, it.lift, it.bolts, it.pattern, it.prop, it.doors = m.anchor, m.cam, m.lift, m.bolts, m.pattern, m.prop, m.doors
        return it
    elseif kind == 'wheels' then
        if type(v) ~= 'table' or not tonumber(v.type) or not tonumber(v.index) then return nil end
        it.v = { type = math.floor(tonumber(v.type)), index = math.floor(tonumber(v.index)), custom = v.custom == true }
        it.price = Config.RimPrice * 4
        it.labor = Config.WheelLabor * 4
        it.label = 'Felgi – ' .. (type(name) == 'string' and name:sub(1, 40) or ('#' .. it.v.index))
        it.stock, it.stockQty = 'rim', 4
        it.wheelsDone = {}
        it.tireJob = true
        it.anchor, it.cam, it.lift = 'wheel', 'wheel_fl', Config.Tires.requireLift
        return it
    elseif kind == 'tire' then
        local c = Config.TireCompounds[key]
        if not c then return nil end
        it.price = c.price * 4
        it.labor = Config.WheelLabor * 4
        it.label = 'Opony – ' .. c.label .. ' (komplet)'
        it.stock, it.stockQty = 'tire_' .. key, 4
        it.wheelsDone = {}
        it.tireJob = true
        it.anchor, it.cam, it.lift = 'wheel', 'wheel_fl', Config.Tires.requireLift
        return it
    elseif kind == 'paint' then
        local p = Catalog.PaintKeys[key]
        if not p or v == nil then return nil end
        local pk = p.priceKey or key
        it.price = Config.PaintPrices[pk] or Config.PaintPrices[key] or 300
        it.labor = Config.PaintPrices.labor[p.laborKey or key] or 0.5
        it.label = p.label
        it.stock = p.stock
        it.paint = true
        it.anchor, it.cam = 'door_l', 'overview'
        if key == 'wheels' then it.anchor, it.cam = 'wheel', 'wheel_fl' end
        if key == 'interior' or key == 'dashboard' then it.anchor, it.cam = 'interior', 'interior' end
        return it
    elseif kind == 'extra' then
        local id = tonumber(key)
        if not id or id < 0 or id > 20 then return nil end
        it.key, it.v = id, v == true
        it.price = Config.PaintPrices.extra
        it.labor = Config.PaintPrices.labor.extra
        it.label = ('Dodatek #%d – %s'):format(id, it.v and 'włączony' or 'wyłączony')
        it.anchor, it.cam, it.bolts, it.pattern, it.prop = 'roof', 'overview', 2, 'line', 'small'
        return it
    elseif kind == 'perf' then
        local p = Config.PerfParts[key]
        local lvl = tonumber(v)
        if not p or not lvl or lvl < 0 or lvl > #p.levels then return nil end
        it.v = math.floor(lvl)
        local l = p.levels[it.v]
        it.price = l and l.price or 0
        it.labor = l and l.labor or 0.8
        it.label = p.label .. ' – ' .. (l and l.label or 'demontaż (fabryczne)')
        it.stock = l and ('perf_%s_%d'):format(key, it.v) or nil
        it.anchor, it.lift, it.bolts, it.pattern, it.prop = p.anchor, p.lift, 4, 'grid', 'default'
        it.cam = (Config.Anchors[p.anchor] and Config.Anchors[p.anchor].under) and 'under' or (p.anchor == 'wheel' and 'wheel_fl' or (p.anchor == 'interior' and 'interior' or 'engine'))
        it.doors = p.anchor == 'engine' and { 4 } or (p.anchor == 'interior' and { 0 } or nil)
        return it
    elseif kind == 'swap' then
        local tbl = Catalog.SwapTables[key]
        local e = tbl and tbl[v]
        if not e then return nil end
        it.price, it.labor = e.price, math.max(e.labor, 0.5)
        it.label = Catalog.SwapLabels[key] .. ' – ' .. e.label
        it.stock = v ~= 'stock' and ('swap_%s_%s'):format(key, v) or nil
        it.bolts, it.pattern, it.prop = 8, 'grid', key == 'brakes' and 'brake' or 'engine_part'
        if key == 'engine' then it.anchor, it.cam, it.doors = 'engine', 'engine', { 4 }
        elseif key == 'brakes' then it.anchor, it.cam, it.lift, it.pattern = 'wheel', 'wheel_fl', 'arms', 'circle'
        else it.anchor, it.cam, it.lift = 'under_gearbox', 'under', 'ramp' end
        return it
    elseif kind == 'nitro' then
        if key == 'kit' then
            local k = Config.Nitro.kits[v]
            if not k then return nil end
            it.price, it.labor, it.label = k.price, k.labor, k.label
            it.stock = 'nitro_' .. v
            it.anchor, it.cam, it.doors, it.bolts, it.pattern, it.prop = 'trunk', 'trunk', { 5 }, 4, 'corners', 'nitro'
            return it
        elseif key == 'refill' then
            it.price, it.labor, it.label = Config.Nitro.refillPrice, 0.3, 'Napełnienie butli N2O'
            it.stock = 'nitro_bottle'
            it.anchor, it.cam, it.doors, it.bolts, it.pattern, it.prop = 'trunk', 'trunk', { 5 }, 2, 'line', 'nitro'
            return it
        end
        return nil
    elseif kind == 'wear' then
        local p = Config.Wear.parts[key]
        if not p then return nil end
        it.price, it.labor, it.label = p.price, p.labor, 'Wymiana: ' .. p.label
        it.stock = 'wear_' .. key
        it.anchor, it.lift, it.bolts, it.pattern = p.anchor, p.lift, 3, 'circle'
        it.prop = Catalog.items[it.stock].prop
        local a = Config.Anchors[p.anchor]
        it.cam = (a and a.under) and 'under' or (p.anchor == 'wheel' and 'wheel_fl' or 'engine')
        it.doors = p.anchor == 'engine' and { 4 } or nil
        return it
    elseif kind == 'align' then
        it.price, it.labor, it.label = Config.Alignment.price, Config.Alignment.labor, 'Ustawienie geometrii kół'
        it.stock = 'align_kit'
        it.anchor, it.cam, it.lift, it.bolts, it.pattern, it.prop = 'wheel', 'wheel_fl', Config.Alignment.lift, 2, 'line', 'small'
        return it
    elseif kind == 'service' then
        it.key = 'inspection'
        it.price, it.labor, it.label = 350, 1.0, 'Przegląd okresowy + badanie techniczne'
        it.stock = 'inspection_kit'
        it.inspection = true
        it.anchor, it.cam = 'engine', 'overview'
        return it
    elseif kind == 'custom' then
        local price = tonumber(v)
        if type(name) ~= 'string' or not price or price < 0 or price > Config.Invoice.maxCustomAmount then return nil end
        it.label = name:sub(1, 60)
        it.price, it.labor, it.done = math.floor(price), 0, true
        it.custom = true
        return it
    end
    return nil
end

-- robocizna liczona w pieniądzach
function Catalog.LaborCost(hours, rate)
    return math.floor((hours or 0) * (rate or Config.Invoice.laborRate) + 0.5)
end
