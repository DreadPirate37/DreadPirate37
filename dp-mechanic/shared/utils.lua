-- ==========================================================================
--  Narzędzia współdzielone (klient + serwer)
-- ==========================================================================
Utils = {}

function Utils.Clamp(v, a, b)
    if v < a then return a end
    if v > b then return b end
    return v
end

function Utils.Lerp(a, b, t) return a + (b - a) * t end

function Utils.Round(v, d)
    local m = 10 ^ (d or 0)
    return math.floor(v * m + 0.5) / m
end

function Utils.Copy(t)
    if type(t) ~= 'table' then return t end
    local r = {}
    for k, v in pairs(t) do r[k] = Utils.Copy(v) end
    return r
end

function Utils.Trim(s)
    return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

function Utils.Plate(p)
    return Utils.Trim(p):upper()
end

function Utils.Money(v)
    local s = tostring(math.floor(v + 0.5))
    local r = s:reverse():gsub('(%d%d%d)', '%1 '):reverse()
    return (r:gsub('^%s', '')) .. ' ' .. Config.Currency
end

-- pozycja w „połówkach wymiaru” auta → offset lokalny w metrach
function Utils.BoxOffset(min, max, rel)
    local cx, cy, cz = (min.x + max.x) * 0.5, (min.y + max.y) * 0.5, (min.z + max.z) * 0.5
    local hx, hy, hz = (max.x - min.x) * 0.5, (max.y - min.y) * 0.5, (max.z - min.z) * 0.5
    return vec3(cx + rel.x * hx, cy + rel.y * hy, cz + rel.z * hz)
end

function Utils.HasPerm(perms, perm)
    if not perms then return false end
    for i = 1, #perms do
        if perms[i] == '*' or perms[i] == perm then return true end
    end
    return false
end

-- nowe dane pojazdu (pełny stan techniczny)
function Utils.NewVehicleData()
    local parts = {}
    for id in pairs(Config.Wear.parts) do parts[id] = 100.0 end
    local tires = {}
    for i = 1, 4 do tires[i] = { t = Config.TireNewTread, b = 0 } end
    return {
        km = 0.0,
        parts = parts,
        tires = tires,
        compound = 'street',
        align = 0.0,
        perf = {},
        swap = { engine = 'stock', drivetrain = 'stock', brakes = 'stock', gearbox = 'stock' },
        nitro = nil,
        svc = { km = 0.0, at = 0, insp = 0 },
    }
end

-- dane „używanego” auta: przebieg + zużycie części wynikające z tego przebiegu
-- (zakładamy, że poprzedni właściciel wymieniał części, gdy się zużyły – stan to reszta z cyklu)
function Utils.UsedVehicleData(km)
    local d = Utils.NewVehicleData()
    km = math.max(0.0, tonumber(km) or 0.0)
    d.km = km
    local m = Config.Mileage or {}
    if m.usedWear ~= false and km > 0 then
        local serviced = math.random() < (m.serviceRandom or 0.6)
        for id, p in pairs(Config.Wear.parts) do
            local life = math.max(1000, p.lifeKm or 10000)
            local used = (km % life) / life
            -- serwisowane auto: płyny i filtry świeże (zużycie max 35%)
            if serviced and (id == 'oil' or id == 'oil_filter' or id == 'air_filter' or id == 'coolant' or id == 'brake_fluid') then
                used = used * 0.35
            end
            d.parts[id] = Utils.Round(Utils.Clamp(100.0 - used * 100.0 + (math.random() - 0.5) * 6.0, 3.0, 100.0), 1)
        end
        local life = (Config.TireCompounds.street and Config.TireCompounds.street.life) or 40000
        for i = 1, 4 do
            local used = ((km + i * 1500) % life) / life
            d.tires[i] = { t = Utils.Round(Utils.Clamp(Config.TireNewTread * (1.0 - used), 1.0, Config.TireNewTread), 2), b = math.random(0, 3) * 5 }
        end
        d.align = (math.random() < 0.3) and Utils.Round((math.random() - 0.5) * 0.06, 3) or 0.0
        local interval = Config.Wear.serviceInterval or 15000
        d.svc.km = serviced and (km - (km % interval) + math.random(0, math.floor(interval * 0.3))) or math.max(0.0, km - interval * (1 + math.random()))
        if d.svc.km > km then d.svc.km = km end
    end
    d.svc.km = d.svc.km or 0.0
    return d
end

-- formatowanie przebiegu wg jednostki z configu
function Utils.FormatKm(km)
    local unit = (Config.Mileage and Config.Mileage.unit) or 'km'
    local v = tonumber(km) or 0
    if unit == 'mi' then v = v * 0.621371 end
    local s = tostring(math.floor(v))
    local r = s:reverse():gsub('(%d%d%d)', '%1 '):reverse()
    return (r:gsub('^%s', '')) .. ' ' .. unit
end

-- uzupełnia brakujące pola (np. po dodaniu nowej części do configu)
function Utils.FixVehicleData(d)
    local def = Utils.NewVehicleData()
    if type(d) ~= 'table' then return def end
    for k, v in pairs(def) do
        if d[k] == nil then d[k] = v end
    end
    for id in pairs(Config.Wear.parts) do
        if type(d.parts[id]) ~= 'number' then d.parts[id] = 100.0 end
    end
    for k, v in pairs(def.swap) do
        if not d.swap[k] then d.swap[k] = v end
    end
    for i = 1, 4 do
        if type(d.tires[i]) ~= 'table' then d.tires[i] = { t = Config.TireNewTread, b = 0 } end
    end
    if not Config.TireCompounds[d.compound] then d.compound = 'street' end
    return d
end
