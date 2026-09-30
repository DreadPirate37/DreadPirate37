-- ==========================================================================
--  DPM.Nitro – własny system N2O
--  - uzbrojenie, podanie (trzymaj), purge (przedmuch), zmiana dyszy (shot)
--  - symulacja ciśnienia butli: zimna butla = słabszy strzał, podgrzewacz (kit PRO),
--    spadek ciśnienia przy podaniu, końcówka butli; „zimna” linia po postoju
--  - progresja (kit PRO), ryzyko uszkodzenia silnika w złych warunkach
--  - efekty dla wszystkich: płomienie z wydechów (dpm_nos = 1), chmura purge (2)
--  Pętla lokalna: co 100 ms gdy uzbrojone/bezczynne, co klatkę tylko przy podaniu/purge.
-- ==========================================================================
DPM.Nitro = {}
local Nitro = DPM.Nitro
local Drive = DPM.Drive

local NC = Config.Nitro or {}
local P = NC.pressure or {}
local KITS = NC.kits or {}
local SHOTS = (NC.shots and #NC.shots > 0) and NC.shots or { { label = '50 shot', power = 1.3, use = 5.5 } }
local ENABLED = NC.enabled ~= false and Config.Nitro ~= nil

local P_IDEAL = P.ideal or 950
local P_MIN = P.min or 500
local P_MAX = P.max or 1150
local P_AMBIENT = P_IDEAL * 0.82
local COLD_AFTER = (NC.lineColdAfter or 45) * 1000
local COLD_TIME = (NC.lineColdTime or 1.4) * 1000
local FLAME_ASSET, FLAME_FX = 'veh_xs_vehicle_mods', 'veh_nitrous'
local PURGE_ASSET, PURGE_FX = 'core', 'ent_sht_steam'
local FX_RANGE = 150.0

local N = nil             -- stan instalacji w aucie, którym kierujemy
local sid = 0
local holdFire, holdPurge = false, false
local psiMem = {}         -- [tablica] = { psi, at } – butla nie zmienia temperatury skokowo
local lastHint = 0

local function round(v, d)
    local m = 10 ^ (d or 0)
    return math.floor(v * m + 0.5) / m
end

local function kitOf(data)
    local n = type(data) == 'table' and data.nitro or nil
    if type(n) ~= 'table' or not n.kit or not KITS[n.kit] then return nil end
    return KITS[n.kit], n
end

local function maxShotOf(kit)
    return math.max(1, math.min(kit.maxShot or #SHOTS, #SHOTS))
end

local function hint(msg, kind)
    local now = GetGameTimer()
    if now - lastHint < 2500 then return end
    lastHint = now
    DPM.Notify(msg, kind or 'info', 2500)
end

-- --------------------------------------------------------------------------
--  Efekty wizualne dla wszystkich graczy w pobliżu
-- --------------------------------------------------------------------------
local fxList = {}         -- [ent] = { mode, next, check, far, driver, own, offs, purge }
local fxLoop = false

local EXHAUST_BONES = { 'exhaust' }
for i = 2, 16 do EXHAUST_BONES[#EXHAUST_BONES + 1] = 'exhaust_' .. i end

local function assetReady(asset)
    if HasNamedPtfxAssetLoaded(asset) then return true end
    RequestNamedPtfxAsset(asset)
    return false
end

local function exhaustOffsets(ent)
    local list = {}
    for _, name in ipairs(EXHAUST_BONES) do
        local b = GetEntityBoneIndexByName(ent, name)
        if b ~= -1 then
            local wp = GetWorldPositionOfEntityBone(ent, b)
            list[#list + 1] = GetOffsetFromEntityGivenWorldCoords(ent, wp.x, wp.y, wp.z)
        end
    end
    if #list == 0 then
        local min, max = GetModelDimensions(GetEntityModel(ent))
        list[1] = vector3(max.x * 0.35, min.y + 0.1, min.z + 0.3)
    end
    return list
end

local function stopPurgeFx(f)
    if f.purge then
        for i = 1, #f.purge do StopParticleFxLooped(f.purge[i], false) end
        f.purge = nil
    end
end

local function startPurgeFx(ent, f)
    local min, max = GetModelDimensions(GetEntityModel(ent))
    local y = max.y - 0.55
    local z = min.z + (max.z - min.z) * 0.6
    local x = math.min(0.32, max.x * 0.4)
    f.purge = {}
    for _, sx in ipairs({ -x, x }) do
        UseParticleFxAssetNextCall(PURGE_ASSET)
        local h = StartParticleFxLoopedOnEntity(PURGE_FX, ent, sx, y, z, 40.0, 0.0, 0.0, 0.5, false, false, false)
        if h and h ~= 0 then f.purge[#f.purge + 1] = h end
    end
end

local function removeFx(ent)
    local f = fxList[ent]
    if f then
        stopPurgeFx(f)
        fxList[ent] = nil
    end
end

-- przetwarza jedno auto; false = usuń z listy
local function fxEntity(ent, f, now, pos)
    if not DoesEntityExist(ent) then
        stopPurgeFx(f)
        return false, false
    end
    if now >= f.check then
        f.check = now + 500
        if not f.own then
            local st = tonumber(Entity(ent).state.dpm_nos) or 0
            if st <= 0 then
                stopPurgeFx(f)
                return false, false
            end
            if st ~= f.mode then
                if f.mode == 2 then stopPurgeFx(f) end
                f.mode = st
            end
        end
        f.far = #(pos - GetEntityCoords(ent)) > FX_RANGE
        -- bez kierowcy (np. rozłączony gracz) nie pokazujemy efektów
        f.driver = GetPedInVehicleSeat(ent, -1) ~= 0
    end
    local visible = not f.far and f.driver
    local flames = false
    if f.mode == 1 and visible and NC.exhaustFlames ~= false then
        flames = true
        if now >= f.next and assetReady(FLAME_ASSET) then
            f.next = now + 100
            if not f.offs then f.offs = exhaustOffsets(ent) end
            for i = 1, #f.offs do
                local o = f.offs[i]
                UseParticleFxAssetNextCall(FLAME_ASSET)
                StartParticleFxNonLoopedOnEntity(FLAME_FX, ent, o.x, o.y, o.z, 0.0, 0.0, 0.0, 1.0, false, false, false)
            end
        end
    end
    if f.mode == 2 and visible then
        if not f.purge and assetReady(PURGE_ASSET) then startPurgeFx(ent, f) end
    elseif f.purge then
        stopPurgeFx(f)
    end
    return true, flames
end

local function ensureFxLoop()
    if fxLoop then return end
    fxLoop = true
    CreateThread(function()
        while next(fxList) do
            local now = GetGameTimer()
            local pos = GetEntityCoords(PlayerPedId())
            local anyFlames = false
            for ent, f in pairs(fxList) do
                local keep, flames = fxEntity(ent, f, now, pos)
                if not keep then
                    fxList[ent] = nil
                elseif flames then
                    anyFlames = true
                end
            end
            -- co klatkę tylko gdy w pobliżu lecą płomienie (purge to efekt zapętlony)
            Wait(anyFlames and 0 or 200)
        end
        fxLoop = false
    end)
end

local function setFx(ent, mode, own)
    if mode and mode > 0 then
        local f = fxList[ent]
        if not f then
            f = { next = 0, check = 0, far = false, driver = true }
            fxList[ent] = f
        end
        if f.mode == 2 and mode ~= 2 then stopPurgeFx(f) end
        f.mode = mode
        f.own = own == true
        if own then f.check = GetGameTimer() + 500 f.driver = true f.far = false end
        ensureFxLoop()
    else
        removeFx(ent)
    end
end

AddStateBagChangeHandler('dpm_nos', nil, function(bagName, _, value)
    local ent = GetEntityFromStateBagName(bagName)
    if ent == 0 then return end
    if N and ent == N.veh then return end   -- własne auto obsługujemy lokalnie (bez opóźnienia)
    setFx(ent, tonumber(value) or 0, false)
end)

-- --------------------------------------------------------------------------
--  Logika instalacji (kierowca)
-- --------------------------------------------------------------------------
local function pressureFactor(psi)
    local cp = P.coldPower or 0.65
    if psi >= P_IDEAL then return 1.0 end
    if psi <= P_MIN then return cp * Utils.Clamp(psi / P_MIN, 0.0, 1.0) end
    return Utils.Lerp(cp, 1.0, (psi - P_MIN) / (P_IDEAL - P_MIN))
end

local function sendState(st)
    if not N or st == N.sent then return end
    N.sent = st
    if N.netId then TriggerServerEvent('dp-mechanic:veh:nos', N.netId, st) end
    setFx(N.veh, st, true)
end

local function startFeed(now)
    local veh = N.veh
    N.active = true
    N.activeSince = now
    -- linia bez przedmuchu: pierwsze chwile to gaz zamiast ciekłego N2O
    if now - N.lastFlow > COLD_AFTER then N.coldUntil = now + COLD_TIME end
    SetVehicleBoostActive(veh, true)
    if NC.screenEffect ~= false then AnimpostfxPlay('RaceTurbo', 0, true) end
    Drive.SetTopBoost(veh, NC.topSpeedBoost or 1.0)
    Drive.SetShake('nitro', 0.07)
    DPM.Nui('drive:sound', { name = 'nitro' })
end

local function stopFeed()
    if not N or not N.active then return end
    local veh = N.veh
    N.active = false
    Drive.SetPowerMod('nitro', nil)
    Drive.SetShake('nitro', nil)
    if DoesEntityExist(veh) then
        SetVehicleBoostActive(veh, false)
        Drive.SetTopBoost(veh, 1.0)
    end
    if NC.screenEffect ~= false then AnimpostfxStop('RaceTurbo') end
end

local function engineDamage(reasons)
    local veh = N.veh
    local eh = GetVehicleEngineHealth(veh)
    SetVehicleEngineHealth(veh, math.max(0.0, eh - (NC.damageAmount or 120.0)) + 0.0)
    stopFeed()
    N.fireLock = true
    Drive.SetShake('nosdmg', 0.55)
    SetTimeout(350, function() Drive.SetShake('nosdmg', nil) end)
    DPM.Nui('drive:sound', { name = 'backfire' })
    DPM.Notify('Strzał N2O w dolot – silnik uszkodzony! (' .. table.concat(reasons, ', ') .. ')', 'error', 6000)
end

local function sendHud(level, psiEff, now, force)
    local kit = N.kit
    local shot = SHOTS[N.shot] or SHOTS[1]
    local cold = (now - N.lastFlow > COLD_AFTER) or now < N.coldUntil
    local visible = Drive.HudAllowed()
    local lvl = round(level, 1)
    local psi = math.floor(psiEff / 5 + 0.5) * 5
    local sig = table.concat({
        tostring(visible), lvl, psi, N.shot, tostring(N.armed), tostring(N.active), tostring(N.purging), tostring(cold), tostring(N.heater),
    }, '|')
    if not force and sig == N.hudSig then return end
    if not force and now - N.hudAt < 100 then return end
    N.hudSig, N.hudAt = sig, now
    DPM.Nui('nitro', {
        visible = visible, level = lvl, capacity = N.cap, psi = psi,
        shot = N.shot, shotLabel = shot.label, maxShot = maxShotOf(kit),
        armed = N.armed, active = N.active, purge = N.purging, cold = cold, heater = N.heater,
        kit = kit.label, hasPurge = kit.purge == true, hasHeater = kit.heater == true, progressive = kit.progressive == true,
        pmin = P_MIN, pmax = P_MAX, pideal = P_IDEAL,
    })
end

local function update(dt, now)
    local veh = N.veh
    local kit = N.kit
    local level = math.max(0.0, N.stateLevel - N.used)

    -- ciśnienie butli
    N.heater = kit.heater == true and N.armed
    local target, rate
    if N.heater then target, rate = P_IDEAL + 12.0, P.heaterRate or 12.0
    else target, rate = P_AMBIENT, P.coolRate or 1.2 end
    if N.psi < target then N.psi = math.min(target, N.psi + rate * dt)
    else N.psi = math.max(target, N.psi - (P.coolRate or 1.2) * dt) end
    if N.active then N.psi = N.psi - (P.usageDrop or 18.0) * dt end
    if N.purging then N.psi = N.psi - (P.usageDrop or 18.0) * 0.5 * dt end
    N.psi = Utils.Clamp(N.psi, 0.0, P_MAX)
    local psiEff = N.psi
    local lowAt = N.cap * 0.08
    if level < lowAt and lowAt > 0 then psiEff = psiEff * (level / lowAt) end

    -- podanie
    local kmh = GetEntitySpeed(veh) * 3.6
    local thr = GetControlNormal(0, 71)
    local running = GetIsVehicleEngineRunning(veh)
    local canFire = holdFire and not N.fireLock and N.armed and level > 0.0 and kmh >= (NC.minSpeed or 15.0)
        and thr > 0.5 and running and not IsEntityInWater(veh)
    if canFire then
        if not N.active then startFeed(now) end
        local shot = SHOTS[N.shot] or SHOTS[1]
        local prog = 1.0
        if kit.progressive then prog = Utils.Clamp(0.6 + 0.4 * (now - N.activeSince) / 1000.0, 0.6, 1.0) end
        local line = now < N.coldUntil and (NC.lineColdPower or 0.6) or 1.0
        local gain = ((shot.power or 1.3) - 1.0) * pressureFactor(psiEff) * line * prog
        Drive.SetPowerMod('nitro', 1.0 + gain)
        N.lastFlow = now
        local use = math.min(level, (shot.use or 5.0) * dt)
        N.used = N.used + use
        DPM.Wear.AddNitroUsed(use)
        level = level - use
        -- ryzyko uszkodzenia
        local reasons = {}
        if GetVehicleCurrentRpm(veh) < (NC.minRpm or 0.45) then reasons[#reasons + 1] = 'za niskie obroty' end
        if N.plugs < 30.0 then reasons[#reasons + 1] = 'zużyte świece' end
        if N.shot >= 3 and not N.ecu then reasons[#reasons + 1] = 'duża dysza bez mapy ECU' end
        if #reasons > 0 and math.random() < (NC.damageChance or 0.06) * #reasons * dt then
            engineDamage(reasons)
        elseif level <= 0.001 then
            stopFeed()
            DPM.Notify('Butla N2O jest pusta', 'error', 3500)
        end
    elseif N.active then
        stopFeed()
    end

    -- purge (przedmuch linii)
    local wantPurge = holdPurge and kit.purge == true and N.armed and level > 0.0 and not N.active
    if wantPurge then
        if not N.purging then
            N.purging = true
            N.purgeSince = now
            DPM.Nui('drive:sound', { name = 'purge', on = true })
        end
        if now - N.purgeSince >= 400 then
            N.lastFlow = now
            N.coldUntil = 0
        end
        local use = math.min(level, (SHOTS[1].use or 5.0) * 0.3 * dt)
        N.used = N.used + use
        DPM.Wear.AddNitroUsed(use)
        level = level - use
    elseif N.purging then
        N.purging = false
        DPM.Nui('drive:sound', { name = 'purge', on = false })
    end

    sendState(N.active and 1 or (N.purging and 2 or 0))
    sendHud(level, psiEff, now, false)
end

local function endSession()
    if not N then return end
    local veh = N.veh
    stopFeed()
    if N.purging then DPM.Nui('drive:sound', { name = 'purge', on = false }) end
    N.purging = false
    sendState(0)
    removeFx(veh)
    if N.plate then psiMem[N.plate] = { psi = N.psi, at = GetGameTimer() } end
    DPM.Nui('nitro', { visible = false })
    N = nil
end

local function startSession(veh, data)
    local kit, n = kitOf(data)
    if not kit then return end
    sid = sid + 1
    local now = GetGameTimer()
    local plate = DPM.Plate(veh)
    local mem = psiMem[plate]
    local psi = P_AMBIENT
    if mem then
        local k = Utils.Clamp((now - mem.at) / 300000.0, 0.0, 1.0)
        psi = Utils.Lerp(mem.psi, P_AMBIENT, k)
    end
    N = {
        token = sid, veh = veh, plate = plate,
        netId = NetworkGetEntityIsNetworked(veh) and VehToNet(veh) or nil,
        kitId = n.kit, kit = kit, cap = kit.capacity or 100,
        stateLevel = tonumber(n.level) or 0.0, used = 0.0,
        armed = false, active = false, purging = false, heater = false, fireLock = false,
        shot = 1, psi = psi,
        lastFlow = now - COLD_AFTER - 1, coldUntil = 0, activeSince = 0, purgeSince = 0,
        sent = 0, hudSig = nil, hudAt = 0,
        plugs = (data.parts and tonumber(data.parts.spark_plugs)) or 100.0,
        ecu = data.perf and data.perf.ecu ~= nil,
    }
    local token = sid
    sendHud(math.max(0.0, N.stateLevel), psi, now, true)
    CreateThread(function()
        local last = GetGameTimer()
        while N and N.token == token do
            local t = GetGameTimer()
            local dt = (t - last) / 1000.0
            last = t
            if dt > 0.5 then dt = 0.5 end
            if not DoesEntityExist(N.veh) then break end
            local ok, err = pcall(update, dt, t)
            if not ok then print('[dp-mechanic] nitro: ' .. tostring(err)) end
            local fast = N and (N.active or N.purging or ((holdFire or holdPurge) and N.armed))
            Wait(fast and 0 or 100)
        end
    end)
end

-- --------------------------------------------------------------------------
--  API
-- --------------------------------------------------------------------------
function Nitro.IsActive() return N ~= nil and N.active end

function Nitro.GetState()
    if not N then return nil end
    return {
        kit = N.kitId, level = math.max(0.0, N.stateLevel - N.used), capacity = N.cap, psi = N.psi,
        shot = N.shot, armed = N.armed, active = N.active, purge = N.purging, heater = N.heater,
    }
end

if not ENABLED then return end

Drive.OnEnter(function(veh, data)
    if N then endSession() end
    startSession(veh, data)
end)

Drive.OnLeave(function()
    endSession()
end)

Drive.OnData(function(veh, data)
    local kit, n = kitOf(data)
    if not N then
        if kit and Drive.veh == veh then startSession(veh, data) end
        return
    end
    if N.veh ~= veh then return end
    if not kit or n.kit ~= N.kitId then
        -- zmiana / demontaż zestawu
        endSession()
        if kit then startSession(veh, data) end
        return
    end
    local newLevel = tonumber(n.level) or 0.0
    if newLevel > N.stateLevel + 0.01 then
        N.used = 0.0                                          -- napełnienie butli
    elseif newLevel < N.stateLevel then
        N.used = math.max(0.0, N.used - (N.stateLevel - newLevel)) -- serwer uwzględnił zużycie
    end
    N.stateLevel = newLevel
    N.plugs = (data.parts and tonumber(data.parts.spark_plugs)) or 100.0
    N.ecu = data.perf and data.perf.ecu ~= nil
    N.hudSig = nil
end)

-- --------------------------------------------------------------------------
--  Klawisze
-- --------------------------------------------------------------------------
RegisterCommand('dpm_nos_arm', function()
    if not N then
        if Drive.veh then hint('To auto nie ma instalacji N2O', 'error') end
        return
    end
    N.armed = not N.armed
    if not N.armed then
        stopFeed()
        if N.purging then DPM.Nui('drive:sound', { name = 'purge', on = false }) end
        N.purging = false
    end
    DPM.Nui('drive:sound', { name = 'arm', on = N.armed })
    N.hudSig = nil
end, false)

RegisterCommand('+dpm_nos', function()
    holdFire = true
    if not N then return end
    N.fireLock = false
    local level = N.stateLevel - N.used
    if not N.armed then
        hint('System N2O nie jest uzbrojony')
    elseif level <= 0.0 then
        hint('Butla N2O jest pusta', 'error')
    end
end, false)
RegisterCommand('-dpm_nos', function() holdFire = false end, false)

RegisterCommand('+dpm_purge', function()
    holdPurge = true
    if N and not N.kit.purge then hint('Ten zestaw nie ma zaworu purge', 'error') end
end, false)
RegisterCommand('-dpm_purge', function() holdPurge = false end, false)

RegisterCommand('dpm_nos_shot', function()
    if not N then return end
    if N.active then
        hint('Nie zmieniaj dyszy podczas podania', 'error')
        return
    end
    N.shot = N.shot % maxShotOf(N.kit) + 1
    DPM.Nui('drive:sound', { name = 'shot' })
    N.hudSig = nil
end, false)

local K = Config.Keys or {}
RegisterKeyMapping('dpm_nos_arm', 'Nitro – uzbrojenie systemu', 'keyboard', K.nitroArm or 'N')
RegisterKeyMapping('+dpm_nos', 'Nitro – podanie (trzymaj)', 'keyboard', K.nitroFire or 'LSHIFT')
RegisterKeyMapping('+dpm_purge', 'Nitro – przedmuch (purge)', 'keyboard', K.nitroPurge or 'B')
RegisterKeyMapping('dpm_nos_shot', 'Nitro – zmiana dyszy', 'keyboard', K.nitroShot or 'PAGEUP')

-- --------------------------------------------------------------------------
--  Sprzątanie
-- --------------------------------------------------------------------------
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if N then
        local veh = N.veh
        if DoesEntityExist(veh) then SetVehicleBoostActive(veh, false) end
        if N.sent ~= 0 and N.netId then TriggerServerEvent('dp-mechanic:veh:nos', N.netId, 0) end
    end
    AnimpostfxStop('RaceTurbo')
    for _, f in pairs(fxList) do stopPurgeFx(f) end
    fxList = {}
end)
