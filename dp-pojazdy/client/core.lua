-- ==========================================================================
--  dp-pojazdy – rdzeń klienta: stan, profile pojazdów, HUD, powiadomienia
-- ==========================================================================
Car = {
    veh = 0,             -- pojazd, w którym siedzimy
    isDriver = false,
    profile = nil,       -- co jest dostępne w tym aucie (nil = auto nieobsługiwane)
    state = nil,         -- stan synchronizowany (state bag 'dpcar')

    -- stan lokalny kierowcy (niesynchronizowany)
    cruise = nil,        -- [m/s] cel tempomatu
    limiter = nil,       -- [m/s] ogranicznik
    launch = nil,        -- nil | 'armed' | 'ready' | 'go'
    launchUntil = 0,
    switchUntil = 0,     -- odcięcie mocy przy przełączaniu napędu
    tcFactor = 1.0,      -- aktualna ingerencja TC (1 = brak)
    powerFactor = 1.0,   -- wynikowy mnożnik momentu stosowany co klatkę
    belt = false,
    panelOpen = false,

    Actions = {},
}

local KMH = 3.6
local MPH = 2.236936
local unitMul = Config.Units == 'mph' and MPH or KMH
Car.unit = Config.Units == 'mph' and 'mph' or 'km/h'

function Car.ToDisplay(ms) return math.floor(ms * unitMul + 0.5) end
function Car.FromDisplay(v) return v / unitMul end
function Car.Kmh(ms) return ms * KMH end
-- progi w configu są w km/h – do komunikatów przeliczamy na jednostkę gracza
function Car.KmhLabel(kmh) return math.floor(kmh / KMH * unitMul + 0.5) end

local function contains(list, value)
    if not list then return false end
    for i = 1, #list do
        if list[i] == value then return true end
    end
    return false
end
Car.Contains = contains

function Car.Dbg(...)
    if Config.Debug then print('^3[dp-pojazdy]^7', ...) end
end

-- --------------------------------------------------------------------------
--  Profile pojazdów (liczone raz na model)
-- --------------------------------------------------------------------------
local byModel = {}
for name, p in pairs(Config.Vehicles) do byModel[joaat(name)] = p end

local profileCache = {}

local function merge(dst, src)
    if not src then return end
    for k, v in pairs(src) do dst[k] = v end
end

function Car.GetProfile(veh)
    local model = GetEntityModel(veh)
    local cached = profileCache[model]
    if cached ~= nil then return cached or nil end

    local class = GetVehicleClass(veh)
    if Config.DisabledClasses[class] then
        profileCache[model] = false
        return nil
    end

    local p = {}
    merge(p, Config.DefaultProfile)
    merge(p, Config.ClassProfiles[class])
    merge(p, byModel[model])

    local modes = {}
    for _, id in ipairs(p.modes or {}) do
        if Config.Modes[id] then modes[#modes + 1] = id end
    end
    if #modes == 0 then modes = { Config.DefaultMode } end
    p.modes = modes

    if p.drive then
        local drives = {}
        for _, d in ipairs(p.drive) do
            if d == 'FWD' or d == 'RWD' or d == 'AWD' then drives[#drives + 1] = d end
        end
        p.drive = #drives > 0 and drives or nil
    end
    p.hasAWD = contains(p.drive, 'AWD')
    p.diff = math.max(0, math.min(3, tonumber(p.diff) or 0))
    p.launch = p.launch and Config.Launch.enabled or false

    profileCache[model] = p
    return p
end

-- --------------------------------------------------------------------------
--  Stan synchronizowany
-- --------------------------------------------------------------------------
function Car.DefaultState(p)
    local mode = contains(p.modes, Config.DefaultMode) and Config.DefaultMode or p.modes[1]
    return {
        mode = mode,
        drive = p.drive and p.drive[1] or nil,
        diff = 0,
        low = false,
        tc = Config.Modes[mode].tc or 'on',
        susp = 'normal',
    }
end

-- stan z state bagu może być stary (inny profil) albo zmieniony przez kogoś – czyścimy go
function Car.Sanitize(s, p)
    local d = Car.DefaultState(p)
    if type(s) ~= 'table' then return d end
    return {
        mode = contains(p.modes, s.mode) and s.mode or d.mode,
        drive = contains(p.drive, s.drive) and s.drive or d.drive,
        diff = (type(s.diff) == 'number' and s.diff >= 0 and s.diff <= p.diff) and math.floor(s.diff) or 0,
        low = (p.lowRange and s.low == true) or false,
        tc = Config.TractionControl.levels[s.tc] and s.tc or d.tc,
        susp = (p.airSusp and Config.AirSuspension.levels[s.susp]) and s.susp or 'normal',
    }
end

-- napęd faktycznie użyty (tryb drift, reduktor i blokada centralna mogą go wymusić)
function Car.EffectiveDrive()
    local s, p = Car.state, Car.profile
    if not s or not p then return nil end
    local force = Config.Modes[s.mode].forceDrive
    if force and contains(p.drive, force) then return force, 'mode' end
    if p.hasAWD and ((s.low and Config.LowRange.forceAWD) or s.diff >= 2) then return 'AWD', s.low and 'low' or 'diff' end
    return s.drive
end

function Car.EffectiveTC()
    local s = Car.state
    if not s or not Config.TractionControl.enabled then return 'off' end
    if Config.DiffLock.disablesTC and s.diff > 0 then return 'off' end
    return s.tc
end

function Car.SetState(patch)
    local veh = Car.veh
    if not Car.isDriver or not Car.state or not DoesEntityExist(veh) then return end
    for k, v in pairs(patch) do Car.state[k] = v end
    Entity(veh).state:set('dpcar', Car.state, true)
    Handling.Apply(veh, Car.state, Car.profile)
    Car.UpdateMaxSpeed()
    Car.Dirty()
end

-- ogranicznik i reduktor korzystają z tego samego limitu prędkości
function Car.UpdateMaxSpeed()
    local veh = Car.veh
    if not Car.isDriver or not DoesEntityExist(veh) then return end
    local limit = Car.limiter
    if Car.state and Car.state.low then
        local low = Config.LowRange.maxSpeed / KMH
        limit = limit and math.min(limit, low) or low
    end
    SetVehicleMaxSpeed(veh, limit or 0.0)
end

-- --------------------------------------------------------------------------
--  Powiadomienia / dźwięki – podmień Car.Notify na ox_lib itp., jeśli chcesz
-- --------------------------------------------------------------------------
function Car.Notify(msg, kind)
    SendNUIMessage({ action = 'toast', text = msg, kind = kind or 'info' })
end

function Car.Sound(name)
    if Config.Sounds then SendNUIMessage({ action = 'sound', name = name }) end
end

-- --------------------------------------------------------------------------
--  HUD – wysyłany tylko wtedy, gdy coś się zmieniło
-- --------------------------------------------------------------------------
local dirty, lastHud = true, nil

function Car.Dirty() dirty = true end

function Car.HudData()
    if Car.veh == 0 then return { show = false } end
    local data = { show = true, driver = Car.isDriver, belt = Car.belt, beltEnabled = Config.Seatbelt.enabled, unit = Car.unit }
    local s, p = Car.state, Car.profile
    if Car.isDriver and s and p then
        local m = Config.Modes[s.mode]
        local tc = Car.EffectiveTC()
        data.mode = { label = m.label, color = m.color }
        data.drive = Car.EffectiveDrive()
        data.diff = s.diff > 0 and L('diff_' .. s.diff) or nil
        data.low = s.low
        data.tc = { label = Config.TractionControl.levels[tc] and Config.TractionControl.levels[tc].label or 'TC OFF', off = tc == 'off', active = Car.tcFactor < 0.97 }
        data.launch = Car.launch
        data.cruise = Car.cruise and Car.ToDisplay(Car.cruise) or nil
        data.limiter = Car.limiter and Car.ToDisplay(Car.limiter) or nil
        data.susp = (p.airSusp and s.susp ~= 'normal') and Config.AirSuspension.levels[s.susp].label or nil
        data.switching = GetGameTimer() < Car.switchUntil
    end
    return data
end

function Car.FlushHud(force)
    if not Config.Hud then return end
    if not dirty and not force then return end
    dirty = false
    local data = Car.HudData()
    local enc = json.encode(data)
    if enc == lastHud and not force then return end
    lastHud = enc
    SendNUIMessage({ action = 'hud', data = data })
    if Car.panelOpen then Car.PushPanel() end
end
