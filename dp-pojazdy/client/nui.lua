-- ==========================================================================
--  dp-pojazdy – panel sterowania (NUI)
--  Panel działa z SetNuiFocusKeepInput, więc da się jechać z otwartym panelem;
--  blokujemy tylko rozglądanie się myszką, strzelanie i menu pauzy.
-- ==========================================================================
local A = Car.Actions
local lastTelemetry = 0

local function stockDrive()
    local b = Handling.OriginalBias()
    if not b then return nil end
    if b < 0.01 then return 'RWD' end
    if b > 0.99 then return 'FWD' end
    return 'AWD'
end

local function vehicleName(veh)
    local display = GetDisplayNameFromVehicleModel(GetEntityModel(veh))
    local label = GetLabelText(display)
    if not label or label == 'NULL' then label = display end
    return label
end

local function panelData()
    local veh, p, s = Car.veh, Car.profile, Car.state
    local modes = {}
    for _, id in ipairs(p.modes) do
        local m = Config.Modes[id]
        modes[#modes + 1] = { id = id, label = m.label, color = m.color }
    end
    local susp
    if p.airSusp then
        susp = {}
        for _, id in ipairs(Config.AirSuspension.order) do
            susp[#susp + 1] = { id = id, label = Config.AirSuspension.levels[id].label }
        end
    end
    local tc
    if Config.TractionControl.enabled then
        tc = {}
        for _, id in ipairs(Config.TractionControl.order) do
            tc[#tc + 1] = { id = id, label = Config.TractionControl.levels[id].label }
        end
    end
    local eff, why = Car.EffectiveDrive()
    return {
        name = vehicleName(veh),
        plate = GetVehicleNumberPlateText(veh),
        unit = Car.unit,
        modes = modes,
        drives = p.drive or {},
        drive = eff or stockDrive(),
        driveLocked = why ~= nil,
        diffMax = p.diff,
        diffLabels = { L('diff_1'), L('diff_2'), L('diff_3') },
        lowRange = p.lowRange,
        susp = susp,
        tcLevels = tc,
        launch = p.launch,
        features = {
            cruise = Config.Cruise.enabled, limiter = Config.Limiter.enabled, belt = Config.Seatbelt.enabled,
            indicators = Config.Indicators.enabled, engine = Config.Engine.enabled,
        },
        state = s,
        tcEff = Car.EffectiveTC(),
        tcLocked = Config.DiffLock.disablesTC and s.diff > 0,
        launchState = Car.launch,
        cruise = Car.cruise and Car.ToDisplay(Car.cruise) or nil,
        limiter = Car.limiter and Car.ToDisplay(Car.limiter) or nil,
        belt = Car.belt,
        engine = GetIsVehicleEngineRunning(veh),
        ind = Entity(veh).state.dpcar_ind or 0,
    }
end

function Car.PushPanel()
    if not Car.panelOpen or not Car.state then return end
    SendNUIMessage({ action = 'panel', open = true, data = panelData() })
end

function Car.OpenPanel()
    if Car.panelOpen then return Car.ClosePanel() end
    if Car.veh == 0 or not Car.isDriver or not Car.state then return Car.Notify(L('not_driver'), 'error') end
    Car.panelOpen = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(true)
    Car.PushPanel()
end

function Car.ClosePanel()
    if not Car.panelOpen then return end
    Car.panelOpen = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'panel', open = false })
end

-- wywoływane co klatkę z pętli pojazdu, gdy panel jest otwarty
local blocked = { 1, 2, 14, 15, 16, 17, 24, 25, 37, 68, 69, 70, 91, 92, 106, 114, 199, 200, 257, 322 }
function Car.PanelFrame()
    for i = 1, #blocked do DisableControlAction(0, blocked[i], true) end
end

-- telemetria na żywo, 10 Hz, tylko z otwartym panelem
function Car.PanelTick(veh, now)
    if not Car.panelOpen then return end
    if now - lastTelemetry < 100 then return end
    lastTelemetry = now
    local speed = GetEntitySpeed(veh)
    local ref = math.max(speed, 1.0)
    local wheels = {}
    for w = 0, GetVehicleNumberOfWheels(veh) - 1 do
        local ws = GetVehicleWheelSpeed(veh, w)
        if ws < 0 then ws = -ws end
        wheels[#wheels + 1] = { p = GetVehicleWheelIsPowered(veh, w), s = math.floor((ws - speed) / ref * 100 + 0.5) }
    end
    SendNUIMessage({
        action = 'telemetry',
        speed = Car.ToDisplay(speed),
        rpm = GetVehicleCurrentRpm(veh),
        gear = GetVehicleCurrentGear(veh),
        throttle = GetVehicleThrottleOffset(veh),
        power = Car.powerFactor,
        tc = Car.tcFactor < 0.97,
        wheels = wheels,
    })
end

-- --------------------------------------------------------------------------
--  Callbacki NUI
-- --------------------------------------------------------------------------
RegisterNUICallback('close', function(_, cb)
    Car.ClosePanel()
    cb('ok')
end)

local allowed = {
    mode = 'string', drive = 'string', diff = 'number', low = 'boolean', tc = 'string', launch = 'nil',
    susp = 'string', cruise = 'nil', limiter = 'nil', speed = 'number', ind = 'number', belt = 'nil', engine = 'nil',
}

RegisterNUICallback('action', function(d, cb)
    cb('ok')
    if type(d) ~= 'table' or not Car.panelOpen then return end
    local expected = allowed[d.type]
    if not expected then return end
    local value = d.value
    if expected == 'nil' then value = nil elseif type(value) ~= expected then return end
    A[d.type](value)
    Car.PushPanel()
end)
