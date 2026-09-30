-- ==========================================================================
--  dp-pojazdy – wykrywanie wejścia/wyjścia i pętla pojazdu
--  Poza autem: jedno sprawdzenie co 500 ms. W aucie: pętla co klatkę tylko
--  wtedy, gdy coś tego wymaga (kierowca, zapięty pas, duża prędkość),
--  w pozostałych przypadkach co 100 ms.
-- ==========================================================================
local H = Handling
local session = 0

local GetEntitySpeed = GetEntitySpeed
local GetGameTimer = GetGameTimer
local IsControlPressed = IsControlPressed
local DisableControlAction = DisableControlAction
local GetVehicleWheelSpeed = GetVehicleWheelSpeed
local SetVehicleCheatPowerIncrease = SetVehicleCheatPowerIncrease

-- --------------------------------------------------------------------------
--  Kontrola trakcji – poślizg najszybszego koła napędzanego względem auta
-- --------------------------------------------------------------------------
local function tractionTarget(veh, speed, lvl)
    if not lvl or not lvl.slip then return 1.0 end
    if GetVehicleThrottleOffset(veh) < 0.05 or GetVehicleCurrentGear(veh) == 0 or IsEntityInAir(veh) then return 1.0 end
    local powered = H.powered
    local maxW = 0.0
    for i = 1, #powered do
        local w = GetVehicleWheelSpeed(veh, powered[i])
        if w < 0 then w = -w end
        if w > maxW then maxW = w end
    end
    local ref = math.max(speed, Config.TractionControl.minSpeed)
    local slip = (maxW - speed) / ref
    if slip <= lvl.slip then return 1.0 end
    return math.max(lvl.floor or 0.3, 1.0 - (slip - lvl.slip) * (lvl.gain or 2.0))
end

local launchTC = { slip = Config.Launch.slip, gain = 3.0, floor = 0.35 }

-- --------------------------------------------------------------------------
--  Co klatkę (tylko kierowca obsługiwanego auta)
-- --------------------------------------------------------------------------
local function driverFrame(veh, now, speed)
    -- launch control
    local lc = Car.launch
    if lc == 'armed' then
        if speed < 0.5 and IsControlPressed(0, 71) and IsControlPressed(0, 72) then
            Car.launch = 'ready'
            Car.Notify(L('launch_ready'), 'warn')
            Car.Sound('launch')
            Car.Dirty()
        end
    elseif lc == 'ready' then
        DisableControlAction(0, 71, true)
        DisableControlAction(0, 72, true)
        SetVehicleHandbrake(veh, true)
        SetVehicleCurrentRpm(veh, Config.Launch.holdRpm)
        if not IsDisabledControlPressed(0, 71) then
            Car.launch = 'armed'
            SetVehicleHandbrake(veh, false)
            Car.Dirty()
        elseif not IsDisabledControlPressed(0, 72) then
            Car.launch = 'go'
            Car.launchUntil = now + Config.Launch.duration
            SetVehicleHandbrake(veh, false)
            Car.Notify(L('launch_go'), 'success')
            Car.Dirty()
        end
    elseif lc == 'go' then
        if now > Car.launchUntil or not IsControlPressed(0, 71) then
            Car.launch = nil
            Car.Dirty()
        end
    end

    -- tempomat: gaz regulowany proporcjonalnie, gracz może dogazować, hamulec wyłącza
    local cruise = Car.cruise
    if cruise then
        if IsControlPressed(0, 72) or IsControlPressed(0, 76) or GetVehicleCurrentGear(veh) == 0 then
            Car.cruise = nil
            Car.Notify(L('cruise_off'))
            Car.Sound('off')
            Car.Dirty()
        elseif not IsControlPressed(0, 71) then
            local diff = cruise - speed
            if diff > 0 then
                SetControlNormal(0, 71, math.min(1.0, 0.18 + diff * Config.Cruise.gain * 3.0))
            end
        end
    end

    -- moc: przełączanie napędu → 0, TC → <1, launch → >1
    local f
    if now < Car.switchUntil then
        f = 0.0
    else
        local lvl = Car.launch == 'go' and launchTC or Config.TractionControl.levels[Car.EffectiveTC()]
        local target = tractionTarget(veh, speed, lvl)
        local cur = Car.tcFactor
        -- szybkie cięcie, łagodny powrót
        cur = cur + (target - cur) * (target < cur and 0.5 or 0.12)
        if cur > 0.995 then cur = 1.0 end
        if (cur < 0.97) ~= (Car.tcFactor < 0.97) then Car.Dirty() end
        Car.tcFactor = cur
        f = cur
        if Car.launch == 'go' then f = f * Config.Launch.boost end
    end
    Car.powerFactor = f
    if f ~= 1.0 then SetVehicleCheatPowerIncrease(veh, f) end

    -- silnik pracuje po wyjściu
    if Config.Engine.enabled and Config.Engine.keepRunningOnExit and IsControlJustPressed(0, 75) and GetIsVehicleEngineRunning(veh) then
        Car.KeepEngineRunning(veh)
    end
end

-- --------------------------------------------------------------------------
--  Co 100 ms
-- --------------------------------------------------------------------------
local wasSwitching = false

local function driverSlow(veh, now, speed)
    local s = Car.state
    local kmh = speed * 3.6

    if s.diff > 0 and kmh > Config.DiffLock.maxSpeed then
        Car.SetState({ diff = 0 })
        Car.Notify(L('diff_auto_off'), 'warn')
        Car.Sound('off')
    end

    local suspLimit = Car.profile.airSusp and Config.AirSuspension.maxSpeed[s.susp]
    if suspLimit and kmh > suspLimit then
        Car.SetState({ susp = 'normal' })
        Car.Notify(L('susp_auto'))
        Car.Sound('air')
    end

    if Car.launch == 'armed' and kmh > 30 then
        Car.launch = nil
        Car.Dirty()
    end

    local switching = now < Car.switchUntil
    if switching ~= wasSwitching then
        wasSwitching = switching
        Car.Dirty()
    end
end

-- --------------------------------------------------------------------------
--  Pasy: wypadnięcie przez szybę przy gwałtownym wytraceniu prędkości
-- --------------------------------------------------------------------------
local function eject(veh, vel)
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local fw = GetEntityForwardVector(veh)
    SetEntityCoords(ped, c.x + fw.x, c.y + fw.y, c.z - 0.47, true, true, true, false)
    SetEntityVelocity(ped, vel.x, vel.y, vel.z)
    Wait(1)
    SetPedToRagdoll(ped, 2500, 2500, 0, false, false, false)
    if Config.Seatbelt.ejectDamage > 0 then ApplyDamageToPed(ped, Config.Seatbelt.ejectDamage, false) end
end

local function crashCheck(veh, now, speed, hist)
    hist[#hist + 1] = { t = now, s = speed, v = GetEntityVelocity(veh) }
    while #hist > 1 and now - hist[1].t > 150 do table.remove(hist, 1) end
    if Car.belt then return end
    local ref = hist[1]
    if ref.s * 3.6 >= Config.Seatbelt.ejectSpeed and (ref.s - speed) / ref.s >= Config.Seatbelt.ejectDrop
        and HasEntityCollidedWithAnything(veh) then
        for i = #hist, 1, -1 do hist[i] = nil end
        eject(veh, ref.v)
    end
end

-- --------------------------------------------------------------------------
--  Pętla pobytu w aucie
-- --------------------------------------------------------------------------
local function vehicleLoop(veh, token)
    local slowAt, hist = 0, {}
    local beltCfg = Config.Seatbelt
    local ejectFrameSpeed = beltCfg.ejectSpeed / 3.6 * 0.7

    while session == token and Car.veh == veh do
        if not DoesEntityExist(veh) then break end
        local now = GetGameTimer()
        local speed = GetEntitySpeed(veh)
        local frame = false

        local driving = Car.isDriver and Car.state ~= nil
        if driving then
            frame = true
            driverFrame(veh, now, speed)
        end

        if beltCfg.enabled then
            if Car.belt and beltCfg.blockExit then
                frame = true
                DisableControlAction(0, 75, true)
                if IsDisabledControlJustPressed(0, 75) then Car.Notify(L('belt_block'), 'warn') end
            end
            if speed > ejectFrameSpeed then frame = true end
            crashCheck(veh, now, speed, hist)
        end

        if Car.panelOpen then
            frame = true
            Car.PanelFrame()
        end

        if now >= slowAt then
            slowAt = now + 100
            if driving then driverSlow(veh, now, speed) end
            Car.ExtrasTick(veh, now, speed)
            Car.PanelTick(veh, now)
        end

        Car.FlushHud()
        Wait(frame and 0 or 100)
    end
end

-- --------------------------------------------------------------------------
--  Wejście / wyjście
-- --------------------------------------------------------------------------
local function onLeave()
    local veh = Car.veh
    if Car.isDriver and Car.state and DoesEntityExist(veh) then
        SetVehicleMaxSpeed(veh, 0.0)
        if Car.launch == 'ready' then SetVehicleHandbrake(veh, false) end
    end
    if Car.isDriver then H.Restore() end
    if Car.panelOpen then Car.ClosePanel() end

    session = session + 1
    Car.veh, Car.isDriver, Car.profile, Car.state = 0, false, nil, nil
    Car.cruise, Car.limiter, Car.launch = nil, nil, nil
    Car.tcFactor, Car.powerFactor, Car.switchUntil = 1.0, 1.0, 0
    Car.ExtrasReset()
    Car.Dirty()
    Car.FlushHud(true)
end

local function onEnter(veh, driver, keepBelt)
    session = session + 1
    Car.veh, Car.isDriver = veh, driver
    Car.profile = Car.GetProfile(veh)
    if not Car.profile then return end -- klasa wyłączona: nic nie robimy

    Car.belt = keepBelt or false
    if driver then
        Car.state = Car.Sanitize(Entity(veh).state.dpcar, Car.profile)
        Entity(veh).state:set('dpcar', Car.state, true)
        H.Apply(veh, Car.state, Car.profile)
        Car.UpdateMaxSpeed()
    end
    Car.Dirty()
    Car.FlushHud(true)
    local token = session
    CreateThread(function() vehicleLoop(veh, token) end)
end

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 and not IsEntityDead(ped) then
            local driver = GetPedInVehicleSeat(veh, -1) == ped
            if veh ~= Car.veh or driver ~= Car.isDriver then
                local sameCar = veh == Car.veh
                local belt = sameCar and Car.belt
                if Car.veh ~= 0 then onLeave() end
                onEnter(veh, driver, belt)
            end
        elseif Car.veh ~= 0 then
            onLeave()
        end
        Wait(Car.veh ~= 0 and 250 or 500)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() or Car.veh == 0 then return end
    if Car.isDriver and Car.state and DoesEntityExist(Car.veh) then
        SetVehicleMaxSpeed(Car.veh, 0.0)
        SetVehicleHandbrake(Car.veh, false)
        H.Restore()
    end
end)
