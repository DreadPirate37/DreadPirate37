-- ==========================================================================
--  dp-wlamywacz – wspólne narzędzia (klient + serwer)
-- ==========================================================================
WLM = WLM or {}
local U = {}
WLM.U = U

Locales = Locales or {}

function L(key, ...)
    local t = Locales[Config.Locale] or Locales.pl or {}
    local s = t[key] or (Locales.pl and Locales.pl[key]) or key
    if select('#', ...) > 0 then
        local ok, out = pcall(string.format, s, ...)
        return ok and out or s
    end
    return s
end

-- deterministyczny generator liczb z seeda (splitmix64 – całkowite 64-bit Lua 5.4 zawijają się same)
-- rng() -> [0,1), rng(n) -> 1..n, rng(a, b) -> a..b
function U.Rng(seed)
    local s = math.floor(seed)
    return function(m, n)
        s = s + 0x9E3779B97F4A7C15
        local z = s
        z = (z ~ (z >> 30)) * 0xBF58476D1CE4E5B9
        z = (z ~ (z >> 27)) * 0x94D049BB133111EB
        z = z ~ (z >> 31)
        local r = (z >> 11) / 9007199254740992.0
        if m then
            if n then return m + math.floor(r * (n - m + 1)) end
            return 1 + math.floor(r * m)
        end
        return r
    end
end

-- FNV-1a 32-bit
function U.Hash(s)
    local h = 2166136261
    for i = 1, #s do h = ((h ~ s:byte(i)) * 16777619) & 0xffffffff end
    return h
end

function U.Clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
function U.Round(v, d) local m = 10 ^ (d or 0) return math.floor(v * m + 0.5) / m end
function U.Lerp(a, b, t) return a + (b - a) * t end
function U.RangeF(rng, r) return r[1] + rng() * (r[2] - r[1]) end
function U.RangeI(rng, r) return rng(r[1], r[2]) end

function U.SortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

-- list = { { klucz, waga }, ... }
function U.PickWeighted(rng, list)
    local total = 0
    for i = 1, #list do total = total + math.max(0, list[i][2]) end
    if total <= 0 then return nil end
    local r = rng() * total
    for i = 1, #list do
        r = r - math.max(0, list[i][2])
        if r < 0 then return list[i][1] end
    end
    return list[#list][1]
end

-- czy minuta m (0–1439) leży w przedziale [a, b) z przejściem przez północ
function U.InRange(m, a, b)
    if a <= b then return m >= a and m < b end
    return m >= a or m < b
end

function U.Minute(h, m) return ((h or 0) * 60 + (m or 0)) % 1440 end
function U.Clock(minute) return ('%02d:%02d'):format(math.floor(minute / 60) % 24, math.floor(minute % 60)) end

function U.Copy(t)
    if type(t) ~= 'table' then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = U.Copy(v) end
    return o
end

-- wartość zanikająca w czasie liczona leniwie: v·e^(−Δt/τ) (POL-08, heat bez timerów)
function U.Decay(v, since, tau, now)
    if not v or v <= 0 then return 0 end
    local dt = math.max(0, now - (since or now))
    return v * math.exp(-dt / tau)
end

-- przekształcenie punktu względnego szablonu wnętrza na świat (bez obrotu – wnętrza IPL są osiowe)
function U.Rel(origin, p)
    return vector3(origin.x + p.x, origin.y + p.y, origin.z + p.z)
end

-- początek układu współrzędnych wnętrza: IPL ma stały, shell stoi pod domem (offset od pierwszego wejścia)
function U.InteriorOrigin(house, tpl)
    if tpl.type == 'shell' then
        local c = house.entries[1].coords
        local o = tpl.offset or vector3(0.0, 0.0, -40.0)
        return vector3(c.x + o.x, c.y + o.y, c.z + o.z)
    end
    return vector3(tpl.origin.x, tpl.origin.y, tpl.origin.z)
end

function U.Grade(score)
    for _, g in ipairs(Config.Rating.grades) do
        if score >= g[1] then return g[2] end
    end
    return 'F'
end

function U.LevelFor(xp)
    local lvl = 1
    for i, l in ipairs(Config.Levels) do if xp >= l.xp then lvl = i end end
    return lvl
end

function U.FindEntry(house, entryId)
    for _, e in ipairs(house.entries or {}) do
        if e.id == entryId then return e end
    end
end

function U.FindPoint(tpl, pointId)
    for _, p in ipairs(tpl.points) do
        if p.id == pointId then return p end
    end
end

function U.HasValue(list, v)
    for i = 1, #list do if list[i] == v then return true end end
    return false
end

-- indeksy domów i szop po id (budowane raz)
WLM.HouseById, WLM.ShedById = {}, {}
for _, h in ipairs(Config.Houses) do WLM.HouseById[h.id] = h end
for _, s in ipairs(Config.Sheds) do WLM.ShedById[s.id] = s end
