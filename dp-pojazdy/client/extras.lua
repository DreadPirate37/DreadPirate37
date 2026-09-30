-- ==========================================================================
--  dp-pojazdy – kierunkowskazy, pasy, silnik, wizualna wysokość zawieszenia
--  Kierunkowskazy i wysokość zawieszenia idą przez state bagi, więc widzą je
--  wszyscy gracze, także ci, którzy podjadą później.
-- ==========================================================================
local lastInd, chiming = 0, false
local indHeading = nil

local function entityFromBag(bagName)
    local veh = GetEntityFromStateBagName(bagName)
    if veh ~= 0 then return veh end
    -- pojazd mógł jeszcze nie zdążyć się utworzyć u nas
    local timeout = GetGameTimer() + 1500
    while GetGameTimer() < timeout do
        Wait(50)
        veh = GetEntityFromStateBagName(bagName)
        if veh ~= 0 then return veh end
    end
    return 0
end

-- --------------------------------------------------------------------------
--  Kierunkowskazy: 0 wył., 1 lewy, 2 prawy, 3 awaryjne
-- --------------------------------------------------------------------------
local function setIndicatorLights(veh, v)
    SetVehicleIndicatorLights(veh, 1, v == 1 or v == 3)
    SetVehicleIndicatorLights(veh, 0, v == 2 or v == 3)
end

AddStateBagChangeHandler('dpcar_ind', nil, function(bagName, _, value)
    if not Config.Indicators.enabled then return end
    local veh = entityFromBag(bagName)
    if veh == 0 then return end
    setIndicatorLights(veh, tonumber(value) or 0)
end)

function Car.SetIndicator(v)
    if not Config.Indicators.enabled then return end
    local veh = Car.veh
    if veh == 0 or not Car.isDriver or not Car.profile then return end
    local cur = Entity(veh).state.dpcar_ind or 0
    if cur == v then v = 0 end
    Entity(veh).state:set('dpcar_ind', v, true)
    setIndicatorLights(veh, v) -- od razu lokalnie, bez czekania na replikację
    indHeading = (v == 1 or v == 2) and GetEntityHeading(veh) or nil
end

-- --------------------------------------------------------------------------
--  Zawieszenie pneumatyczne – część wizualna u wszystkich graczy
-- --------------------------------------------------------------------------
local baseHeight = {} -- [uchwyt] = { model, wysokość fabryczna/tuningowa }

local function applySuspVisual(veh, level)
    local lvl = Config.AirSuspension.levels[level] or Config.AirSuspension.levels.normal
    local model = GetEntityModel(veh)
    local base = baseHeight[veh]
    if not base or base.model ~= model then -- uchwyty bywają używane ponownie
        base = { model = model, h = GetVehicleSuspensionHeight(veh) }
        baseHeight[veh] = base
    end
    SetVehicleSuspensionHeight(veh, base.h + (lvl.height or 0.0))
end

-- sprzątanie po pojazdach, które zniknęły
CreateThread(function()
    while true do
        Wait(60000)
        for veh in pairs(baseHeight) do
            if not DoesEntityExist(veh) then baseHeight[veh] = nil end
        end
    end
end)

AddStateBagChangeHandler('dpcar', nil, function(bagName, _, value)
    if type(value) ~= 'table' then return end
    local veh = entityFromBag(bagName)
    if veh == 0 then return end
    local p = Car.GetProfile(veh)
    if not p or not p.airSusp then return end
    applySuspVisual(veh, value.susp)
end)

-- --------------------------------------------------------------------------
--  Pasy
-- --------------------------------------------------------------------------
function Car.ToggleBelt()
    if not Config.Seatbelt.enabled or Car.veh == 0 or not Car.profile then return end
    Car.belt = not Car.belt
    Car.Notify(L(Car.belt and 'belt_on' or 'belt_off'))
    Car.Sound(Car.belt and 'belt_on' or 'belt_off')
    Car.Dirty()
end

-- --------------------------------------------------------------------------
--  Silnik
-- --------------------------------------------------------------------------
function Car.ToggleEngine()
    if not Config.Engine.enabled then return end
    local veh = Car.veh
    if veh == 0 or not Car.isDriver then return Car.Notify(L('not_driver'), 'error') end
    local on = not GetIsVehicleEngineRunning(veh)
    SetVehicleEngineOn(veh, on, false, true)
    Car.Notify(L(on and 'engine_on' or 'engine_off'))
end

-- wysiadając gra gasi silnik – przez chwilę trzymamy go na chodzie
function Car.KeepEngineRunning(veh)
    CreateThread(function()
        local ped = PlayerPedId()
        local untilT = GetGameTimer() + 2500
        while GetGameTimer() < untilT and DoesEntityExist(veh) do
            local driver = GetPedInVehicleSeat(veh, -1)
            if driver == ped and not GetIsTaskActive(ped, 2) then break end -- rozmyślił się
            if driver ~= 0 and driver ~= ped then break end               -- ktoś inny wsiadł
            SetVehicleEngineOn(veh, true, true, false)
            Wait(0)
        end
    end)
end

-- --------------------------------------------------------------------------
--  Tick co 100 ms (każde miejsce w aucie)
-- --------------------------------------------------------------------------
function Car.ExtrasTick(veh, now, speed)
    -- dźwięk kierunkowskazu dla osób w środku
    local ind = GetVehicleIndicatorLights(veh)
    if ind ~= lastInd then
        lastInd = ind
        if Config.Sounds then SendNUIMessage({ action = 'blinker', on = ind ~= 0 }) end
        Car.Dirty()
    end

    -- automatyczne gaszenie kierunkowskazu po skręcie
    if indHeading and Car.isDriver then
        local st = Entity(veh).state.dpcar_ind
        if st ~= 1 and st ~= 2 then
            indHeading = nil
        elseif Config.Indicators.autoCancel then
            local d = math.abs((GetEntityHeading(veh) - indHeading + 180.0) % 360.0 - 180.0)
            if d >= Config.Indicators.autoCancelAngle and math.abs(GetVehicleSteeringAngle(veh)) < 6.0 then
                Car.SetIndicator(0)
            end
        end
    end

    -- gong niezapiętych pasów
    local cfg = Config.Seatbelt
    if cfg.enabled and cfg.chime > 0 and Config.Sounds then
        local want = not Car.belt and speed * 3.6 > cfg.chime
        if want ~= chiming then
            chiming = want
            SendNUIMessage({ action = 'chime', on = want })
        end
    end
end

function Car.ExtrasReset()
    Car.belt = false
    indHeading = nil
    if lastInd ~= 0 or chiming then
        SendNUIMessage({ action = 'blinker', on = false })
        SendNUIMessage({ action = 'chime', on = false })
    end
    lastInd, chiming = 0, false
end

-- dla HUD-ów i innych skryptów
function Car.IndicatorState()
    return Car.veh ~= 0 and GetVehicleIndicatorLights(Car.veh) or 0
end
