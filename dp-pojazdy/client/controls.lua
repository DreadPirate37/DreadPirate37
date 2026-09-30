-- ==========================================================================
--  dp-pojazdy – akcje (klawisze, panel, eksporty)
-- ==========================================================================
local A = Car.Actions
local contains = Car.Contains

local function driverOnly()
    if Car.veh == 0 or not Car.isDriver or not Car.state then
        Car.Notify(L('not_driver'), 'error')
        return false
    end
    return true
end

local function kmh() return GetEntitySpeed(Car.veh) * 3.6 end

local function nextIn(list, cur)
    for i = 1, #list do
        if list[i] == cur then return list[i % #list + 1] end
    end
    return list[1]
end

-- zmiana stanu; jeśli przy okazji zmienia się faktyczny napęd, na chwilę odcinamy moc
local function commit(patch)
    local before = Car.EffectiveDrive()
    Car.SetState(patch)
    if Car.EffectiveDrive() ~= before then
        Car.switchUntil = GetGameTimer() + Config.Drivetrain.switchTime
        Car.Dirty()
    end
end

local lockReason = { mode = 'tryb DRIFT', low = 'reduktor', diff = 'blokadę centralną' }

-- --------------------------------------------------------------------------
function A.mode(id)
    if not driverOnly() then return end
    local p, s = Car.profile, Car.state
    id = id or nextIn(p.modes, s.mode)
    if not contains(p.modes, id) or id == s.mode then return end
    local m = Config.Modes[id]
    local patch = { mode = id }
    if m.tc then patch.tc = m.tc end
    commit(patch)
    -- tryb sportowy łapie obroty od razu: kilka szybkich redukcji z międzygazem
    if m.gearbox and m.gearbox.kick then Gearbox.Kick(m.gearbox.kick) end
    Car.Notify(L('mode_set', m.label))
    Car.Sound('mode')
end

function A.drive(id)
    if not driverOnly() then return end
    local p, s = Car.profile, Car.state
    if not p.drive or #p.drive < 2 then return Car.Notify(L('not_supported'), 'error') end
    local eff, why = Car.EffectiveDrive()
    if why then return Car.Notify(L('drive_locked', lockReason[why] or why), 'warn') end
    if kmh() > Config.Drivetrain.maxSwitchSpeed then
        return Car.Notify(L('drive_too_fast', Car.KmhLabel(Config.Drivetrain.maxSwitchSpeed), Car.unit), 'warn')
    end
    id = id or nextIn(p.drive, s.drive)
    if not contains(p.drive, id) or id == eff then return end
    commit({ drive = id })
    Car.Notify(L('drive_set', id))
    Car.Sound('drive')
end

function A.diff(level)
    if not driverOnly() then return end
    local p, s = Car.profile, Car.state
    if p.diff == 0 then return Car.Notify(L('not_supported'), 'error') end
    level = level or ((s.diff + 1) % (p.diff + 1))
    level = math.max(0, math.min(p.diff, math.floor(level)))
    if level == s.diff then return end
    if level > s.diff and kmh() > Config.DiffLock.engageSpeed then
        return Car.Notify(L('diff_too_fast', Car.KmhLabel(Config.DiffLock.engageSpeed), Car.unit), 'warn')
    end
    commit({ diff = level })
    if level > 0 then
        Car.Notify(L('diff_set', L('diff_' .. level)))
        Car.Sound('lock')
    else
        Car.Notify(L('diff_off'))
        Car.Sound('off')
    end
end

function A.low(on)
    if not driverOnly() then return end
    local p, s = Car.profile, Car.state
    if not p.lowRange then return Car.Notify(L('not_supported'), 'error') end
    if on == nil then on = not s.low end
    if on == s.low then return end
    if kmh() > Config.LowRange.engageSpeed then return Car.Notify(L('low_too_fast'), 'warn') end
    commit({ low = on })
    if on then
        Car.Notify(L('low_on', Car.KmhLabel(Config.LowRange.maxSpeed), Car.unit))
        Car.Sound('lock')
    else
        Car.Notify(L('low_off'))
        Car.Sound('off')
    end
end

function A.tc(level)
    if not driverOnly() then return end
    if not Config.TractionControl.enabled then return Car.Notify(L('not_supported'), 'error') end
    local s = Car.state
    if Config.DiffLock.disablesTC and s.diff > 0 then return Car.Notify(L('tc_locked'), 'warn') end
    level = level or nextIn(Config.TractionControl.order, s.tc)
    if not Config.TractionControl.levels[level] or level == s.tc then return end
    Car.state.tc = level -- TC nie zmienia handlingu, wystarczy zsynchronizować stan
    Entity(Car.veh).state:set('dpcar', Car.state, true)
    Car.Dirty()
    Car.Notify(L('tc_set', Config.TractionControl.levels[level].label))
    Car.Sound(level == 'off' and 'off' or 'on')
end

function A.launch()
    if not driverOnly() then return end
    if not Car.profile.launch then return Car.Notify(L('not_supported'), 'error') end
    if Car.launch then
        if Car.launch == 'ready' then SetVehicleHandbrake(Car.veh, false) end
        Car.launch = nil
        Car.Notify(L('launch_off'))
        Car.Sound('off')
    else
        Car.launch = 'armed'
        Car.Notify(L('launch_armed'))
        Car.Sound('on')
    end
    Car.Dirty()
end

function A.susp(level)
    if not driverOnly() then return end
    local p, s = Car.profile, Car.state
    if not p.airSusp then return Car.Notify(L('not_supported'), 'error') end
    level = level or nextIn(Config.AirSuspension.order, s.susp)
    if not Config.AirSuspension.levels[level] or level == s.susp then return end
    if kmh() > Config.AirSuspension.changeSpeed then return Car.Notify(L('susp_too_fast'), 'warn') end
    local limit = Config.AirSuspension.maxSpeed[level]
    if limit and kmh() > limit then return Car.Notify(L('susp_too_fast'), 'warn') end
    commit({ susp = level })
    Car.Notify(L('susp_set', Config.AirSuspension.levels[level].label))
    Car.Sound('air')
end

-- --------------------------------------------------------------------------
--  Tempomat / ogranicznik (stan lokalny kierowcy, nie synchronizowany)
-- --------------------------------------------------------------------------
function A.cruise()
    if not driverOnly() or not Config.Cruise.enabled then return end
    if Car.cruise then
        Car.cruise = nil
        Car.Notify(L('cruise_off'))
        Car.Sound('off')
    else
        if kmh() < Config.Cruise.minSpeed then
            return Car.Notify(L('cruise_too_slow', Car.KmhLabel(Config.Cruise.minSpeed), Car.unit), 'warn')
        end
        Car.cruise = GetEntitySpeed(Car.veh)
        Car.limiter = nil
        Car.UpdateMaxSpeed()
        Car.Notify(L('cruise_on', Car.ToDisplay(Car.cruise), Car.unit))
        Car.Sound('on')
    end
    Car.Dirty()
end

function A.limiter()
    if not driverOnly() or not Config.Limiter.enabled then return end
    if Car.limiter then
        Car.limiter = nil
        Car.Notify(L('limiter_off'))
        Car.Sound('off')
    else
        if kmh() < Config.Limiter.minSpeed then
            return Car.Notify(L('limiter_too_slow', Car.KmhLabel(Config.Limiter.minSpeed), Car.unit), 'warn')
        end
        Car.limiter = GetEntitySpeed(Car.veh)
        Car.cruise = nil
        Car.Notify(L('limiter_on', Car.ToDisplay(Car.limiter), Car.unit))
        Car.Sound('on')
    end
    Car.UpdateMaxSpeed()
    Car.Dirty()
end

function A.speed(dir)
    if not driverOnly() then return end
    dir = dir == -1 and -1 or 1
    if Car.cruise then
        -- zaokrąglamy do pełnego kroku w jednostce gracza
        local disp = Car.ToDisplay(Car.cruise)
        disp = (math.floor(disp / Config.Cruise.step + 0.5) + dir) * Config.Cruise.step
        Car.cruise = math.max(Config.Cruise.minSpeed / 3.6, Car.FromDisplay(disp))
        Car.Notify(L('cruise_on', Car.ToDisplay(Car.cruise), Car.unit))
    elseif Car.limiter then
        local disp = Car.ToDisplay(Car.limiter)
        disp = (math.floor(disp / Config.Limiter.step + 0.5) + dir) * Config.Limiter.step
        Car.limiter = math.max(Config.Limiter.minSpeed / 3.6, Car.FromDisplay(disp))
        Car.UpdateMaxSpeed()
        Car.Notify(L('limiter_on', Car.ToDisplay(Car.limiter), Car.unit))
    else
        return
    end
    Car.Sound('tick')
    Car.Dirty()
end

function A.ind(v) Car.SetIndicator(v) end
function A.belt() Car.ToggleBelt() end
function A.engine() Car.ToggleEngine() end

-- --------------------------------------------------------------------------
--  Klawisze
-- --------------------------------------------------------------------------
local binds = {
    { 'panel',     function() Car.OpenPanel() end },
    { 'mode',      function() A.mode() end },
    { 'drive',     function() A.drive() end },
    { 'diff',      function() A.diff() end },
    { 'low',       function() A.low() end },
    { 'tc',        function() A.tc() end },
    { 'launch',    function() A.launch() end },
    { 'susp',      function() A.susp() end },
    { 'cruise',    function() A.cruise() end },
    { 'limiter',   function() A.limiter() end },
    { 'speedUp',   function() A.speed(1) end },
    { 'speedDown', function() A.speed(-1) end },
    { 'indLeft',   function() A.ind(1) end },
    { 'indRight',  function() A.ind(2) end },
    { 'hazard',    function() A.ind(3) end },
    { 'belt',      function() A.belt() end },
    { 'engine',    function() A.engine() end },
}

local function enabled(name)
    if name == 'belt' then return Config.Seatbelt.enabled end
    if name == 'engine' then return Config.Engine.enabled end
    if name == 'indLeft' or name == 'indRight' or name == 'hazard' then return Config.Indicators.enabled end
    if name == 'cruise' then return Config.Cruise.enabled end
    if name == 'limiter' then return Config.Limiter.enabled end
    if name == 'launch' then return Config.Launch.enabled end
    if name == 'tc' then return Config.TractionControl.enabled end
    return true
end

for _, b in ipairs(binds) do
    local name, fn = b[1], b[2]
    if enabled(name) then
        local cmd = 'dpcar_' .. name
        RegisterCommand(cmd, function()
            -- w menu pauzy / z otwartym czatem klawisze nie powinny działać
            if IsPauseMenuActive() then return end
            fn()
        end, false)
        RegisterKeyMapping(cmd, L('key_' .. name), 'keyboard', Config.Keys[name] or '')
        TriggerEvent('chat:removeSuggestion', '/' .. cmd)
    end
end

-- --------------------------------------------------------------------------
--  Eksporty dla innych skryptów (HUD, tuning itp.)
-- --------------------------------------------------------------------------
exports('GetState', function() return Car.state end)
exports('GetProfile', function() return Car.profile end)
exports('IsBelted', function() return Car.belt end)
exports('GetCruise', function() return Car.cruise and Car.ToDisplay(Car.cruise) or nil end)
exports('GetLimiter', function() return Car.limiter and Car.ToDisplay(Car.limiter) or nil end)
exports('SetMode', function(id) A.mode(id) end)
exports('SetDrive', function(id) A.drive(id) end)
exports('ToggleBelt', function() A.belt() end)

if Config.Debug then
    RegisterCommand('dpcar_debug', function()
        print('^3[dp-pojazdy] stan^7', json.encode({ state = Car.state, profile = Car.profile, drive = Car.EffectiveDrive(),
            tc = Car.EffectiveTC(), cruise = Car.cruise, limiter = Car.limiter, launch = Car.launch }))
        Handling.Debug(Car.veh)
    end, false)
end
