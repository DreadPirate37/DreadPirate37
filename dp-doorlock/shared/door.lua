-- ==========================================================================
--  Wspólne: model drzwi, normalizacja i serializacja (klient + serwer)
-- ==========================================================================
Door = {}

Door.Types = { single = true, double = true, sliding = true, garage = true }
Door.Security = { standard = true, keypad = true, card = true, bio = true }
Door.Electronic = { keypad = true, card = true, bio = true }
Door.LockModels = { euro = true, rim = true, padlock = true, round = true }

local function num(v, def, lo, hi)
    v = tonumber(v) or def
    if lo and v < lo then v = lo end
    if hi and v > hi then v = hi end
    return v
end

local function str(v, def, max)
    if type(v) ~= 'string' then return def end
    v = v:gsub('[%c<>]', ''):sub(1, max or 64)
    return v
end

local function vec(v)
    if type(v) == 'vector3' or type(v) == 'vector4' then return { x = v.x + 0.0, y = v.y + 0.0, z = v.z + 0.0 } end
    if type(v) == 'table' and tonumber(v.x) and tonumber(v.y) and tonumber(v.z) then
        return { x = v.x + 0.0, y = v.y + 0.0, z = v.z + 0.0 }
    end
    return nil
end

local function model(m)
    if type(m) == 'string' then return tonumber(m) or joaat(m) end
    return tonumber(m)
end

-- mapa { nazwa = grade } z zabezpieczeniem typów
local function gradeMap(t)
    local out = {}
    if type(t) ~= 'table' then return out end
    for k, v in pairs(t) do
        if type(k) == 'string' and #k > 0 and #k < 40 then out[k] = math.floor(num(v, 0, 0, 99)) end
    end
    return out
end

local function list(t, max)
    local out = {}
    if type(t) ~= 'table' then return out end
    for _, v in ipairs(t) do
        if type(v) == 'string' and #v > 0 and #v < 60 then out[#out + 1] = v end
        if #out >= (max or 32) then break end
    end
    return out
end

local function hhmm(s)
    if type(s) ~= 'string' then return nil end
    local h, m = s:match('^(%d%d?):(%d%d)$')
    h, m = tonumber(h), tonumber(m)
    if not h or h > 23 or m > 59 then return nil end
    return ('%02d:%02d'):format(h, m)
end

--- Zwraca znormalizowaną, bezpieczną kopię definicji drzwi (albo nil, err).
function Door.Normalize(d)
    if type(d) ~= 'table' then return nil, 'bad' end
    local out = {
        id = tonumber(d.id),
        key = type(d.key) == 'string' and d.key or nil,
        name = str(d.name, 'Drzwi', 48),
        group = str(d.group, '', 32),
        type = Door.Types[d.type] and d.type or 'single',
        security = Door.Security[d.security] and d.security or Config.Defaults.security,
        locked = d.locked ~= false,
        doors = {},
    }

    for i, leaf in ipairs(type(d.doors) == 'table' and d.doors or {}) do
        local c, m = vec(leaf.coords), model(leaf.model)
        if c and m then out.doors[#out.doors + 1] = { model = m, coords = c } end
        if i >= 2 then break end
    end
    if #out.doors == 0 then return nil, 'no_leaves' end
    if out.type == 'double' and #out.doors < 2 then out.type = 'single' end
    if out.type == 'single' and #out.doors > 1 then out.type = 'double' end

    local cx, cy, cz = 0.0, 0.0, 0.0
    for _, leaf in ipairs(out.doors) do cx, cy, cz = cx + leaf.coords.x, cy + leaf.coords.y, cz + leaf.coords.z end
    local n = #out.doors
    out.coords = { x = cx / n, y = cy / n, z = cz / n }

    local gate = out.type == 'sliding' or out.type == 'garage'
    out.distance = num(d.distance, gate and Config.Defaults.gateDistance or Config.Defaults.distance, 0.5, 25.0)
    out.autoLock = math.floor(num(d.autoLock, Config.Defaults.autoLock, 0, 3600))
    out.lockpick = math.floor(num(d.lockpick, 0, 0, 5))
    out.lockModel = Door.LockModels[d.lockModel] and d.lockModel or 'euro'
    out.hack = math.floor(num(d.hack, 0, 0, 5))
    out.breach = d.breach == true
    out.alarm = d.alarm == true
    out.doorbell = d.doorbell == true
    out.hideUi = d.hideUi == true
    out.owner = type(d.owner) == 'string' and d.owner or nil

    if out.security == 'keypad' then
        local pin = tostring(d.pin or ''):gsub('%D', '')
        if #pin < Config.Keypad.minLength or #pin > Config.Keypad.maxLength then pin = '0000' end
        out.pin = pin
    end
    if out.security == 'card' then out.cardLevel = math.floor(num(d.cardLevel, 1, 1, 9)) end

    local a = type(d.access) == 'table' and d.access or {}
    out.access = {
        jobs = gradeMap(a.jobs),
        gangs = gradeMap(a.gangs),
        items = list(a.items, 8),
        public = a.public == true,
        identifiers = {},
    }
    if type(a.identifiers) == 'table' then
        local c = 0
        for id, label in pairs(a.identifiers) do
            if type(id) == 'string' and #id < 80 then
                out.access.identifiers[id] = str(label, 'Gość', 32)
                c = c + 1
                if c >= 64 then break end
            end
        end
    end

    if type(d.schedule) == 'table' then
        local o, c = hhmm(d.schedule.open), hhmm(d.schedule.close)
        if o and c and o ~= c then out.schedule = { open = o, close = c } end
    end
    return out
end

--- Widok dla klienta: bez PIN-u i listy identyfikatorów (nie wysyłamy sekretów).
function Door.Public(d)
    return {
        id = d.id, name = d.name, group = d.group, type = d.type, security = d.security,
        doors = d.doors, coords = d.coords, distance = d.distance, autoLock = d.autoLock,
        lockpick = d.lockpick, hack = d.hack, breach = d.breach, doorbell = d.doorbell,
        hideUi = d.hideUi, cardLevel = d.cardLevel, schedule = d.schedule,
        hasOwner = d.owner ~= nil,
    }
end

--- 'HH:MM' → minuty od północy
function Door.Minutes(s)
    local h, m = s:match('^(%d+):(%d+)$')
    return tonumber(h) * 60 + tonumber(m)
end

--- Czy w danej minucie doby harmonogram trzyma drzwi otwarte (obsługuje przejście przez północ).
function Door.ScheduleOpen(schedule, minute)
    local o, c = Door.Minutes(schedule.open), Door.Minutes(schedule.close)
    if o < c then return minute >= o and minute < c end
    return minute >= o or minute < c
end
