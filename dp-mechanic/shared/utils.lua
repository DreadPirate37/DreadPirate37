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
