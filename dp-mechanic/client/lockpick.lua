-- ==========================================================================
--  Wytrych – klient: otwieranie zamków aut (minigra zapadek bębenkowych)
--  DPM.Lockpick.Start(opts) -> bool   |   exports['dp-mechanic']:Lockpick(opts) -> bool
--  opts = { veh?, netId?, pins?, label?, consume? (false = nie zużywa wytrychów), noAlarm? }
-- ==========================================================================
DPM.Lockpick = {}
local LPM = DPM.Lockpick
local LP = Config.Lockpick
local active = nil

local ANIM_DICT, ANIM_CLIP = 'veh@break_in@0h@p_m_one@', 'low_force_entry_ds'

local function pinsFor(veh)
    if not veh then return LP.pins.default or 5 end
    local cls = GetVehicleClass(veh)
    return LP.pins[cls] or LP.pins.default or 5
end

local function finish(success)
    if not active then return end
    local p = active.p
    active.result = success == true
    if p then active.p = nil p:resolve(success == true) end
end

function LPM.Start(opts)
    if not LP or not LP.enabled then return false end
    opts = opts or {}
    if active or DPM.busy then
        DPM.Notify('Jesteś zajęty inną czynnością', 'error')
        return false
    end
    local veh = opts.veh
    local netId = opts.netId
    if veh and DoesEntityExist(veh) and not netId and NetworkGetEntityIsNetworked(veh) then netId = VehToNet(veh) end
    if netId and not veh then veh = NetToVeh(netId) end

    local res = DPM.Callback('lockpick:start', netId, { consume = opts.consume })
    if not res or not res.ok then
        DPM.Notify(res and res.err or 'Nie można rozpocząć', 'error')
        return false
    end

    local ped = PlayerPedId()
    active = { veh = veh, netId = netId, p = promise.new(), alarm = false, noAlarm = opts.noAlarm == true }
    DPM.SetBusy('lockpick')
    Hooks.ToggleHud(false)

    if veh and DoesEntityExist(veh) then
        local bone = GetEntityBoneIndexByName(veh, 'door_dside_f')
        local target = bone ~= -1 and GetWorldPositionOfEntityBone(veh, bone) or GetEntityCoords(veh)
        TaskTurnPedToFaceCoord(ped, target.x, target.y, target.z, 800)
        Wait(800)
    end
    DPM.PlayAnim(ped, ANIM_DICT, ANIM_CLIP, 1)

    local label = opts.label
    if not label and veh and DoesEntityExist(veh) then
        label = ('%s – %s'):format(DPM.VehLabel(veh), DPM.Plate(veh))
    end

    DPM.Focus(true, true, false)
    DPM.Nui('lockpick:start', {
        pins = opts.pins or pinsFor(veh),
        label = label or 'Zamek',
        picks = res.picks, xp = res.xp, level = res.level, levelXp = res.levelXp, nextXp = res.nextXp,
        money = res.money, currency = Config.Currency,
        cfg = {
            autoTension = LP.autoTension, resetOnBreak = LP.resetOnBreak, tolerance = LP.tolerance,
            toleranceStep = LP.toleranceStep, stressRate = LP.stressRate, maxSetSpeed = LP.maxSetSpeed,
            noise = LP.noise, timeLimit = LP.timeLimit,
        },
    })

    -- nadzór: śmierć, odejście, zniknięcie auta, podtrzymanie animacji
    CreateThread(function()
        local startPos = GetEntityCoords(ped)
        while active and active.p do
            Wait(400)
            ped = PlayerPedId()
            if IsEntityDead(ped) or #(GetEntityCoords(ped) - startPos) > 3.0 or (active.veh and not DoesEntityExist(active.veh)) then
                DPM.Nui('lockpick:stop', {})
                finish(false)
                break
            end
            if not IsEntityPlayingAnim(ped, ANIM_DICT, ANIM_CLIP, 3) then DPM.PlayAnim(ped, ANIM_DICT, ANIM_CLIP, 1) end
        end
    end)

    local ok = Citizen.Await(active.p)
    local st = active
    active = nil

    SetNightvision(false)
    DPM.Focus(false, false, false)
    ClearPedTasks(PlayerPedId())
    Hooks.ToggleHud(true)
    DPM.SetBusy(false)

    local done = DPM.Callback('lockpick:done', ok == true)
    if ok then
        if st.veh and DoesEntityExist(st.veh) and LP.unlockDoors then
            if DPM.RequestControl(st.veh, 1000) then SetVehicleDoorsLocked(st.veh, 1) end
            SetVehicleDoorsLockedForAllPlayers(st.veh, false)
        end
        DPM.Notify('Zamek otwarty', 'success')
    end
    return ok == true, done
end

-- --------------------------------------------------------------------------
--  Callbacki NUI
-- --------------------------------------------------------------------------
DPM.RegisterNui('lockpick_break', function()
    if not active then return { ok = false } end
    local r = DPM.Callback('lockpick:break')
    return { ok = true, picks = r and r.picks or 0 }
end)

DPM.RegisterNui('lockpick_pin', function()
    if not active then return { ok = false } end
    return DPM.Callback('lockpick:pin') or { ok = false }
end)

DPM.RegisterNui('lockpick_alarm', function()
    if not active or active.alarm or active.noAlarm or not LP.alarm then return { ok = true } end
    active.alarm = true
    local veh = active.veh
    if veh and DoesEntityExist(veh) then
        CreateThread(function()
            if DPM.RequestControl(veh, 1000) then
                SetVehicleAlarm(veh, true)
                SetVehicleAlarmTimeLeft(veh, LP.alarmTime or 30000)
                StartVehicleAlarm(veh)
            end
        end)
    end
    TriggerServerEvent('dp-mechanic:lockpick:alarm', active.netId)
    return { ok = true }
end)

DPM.RegisterNui('lockpick_nv', function(data)
    SetNightvision(data.on == true)
    return { ok = true }
end)

DPM.RegisterNui('lockpick_end', function(data)
    finish(data.success == true)
    return { ok = true }
end)

-- --------------------------------------------------------------------------
--  Komenda / klawisz przy zamkniętym aucie
-- --------------------------------------------------------------------------
local function tryVehicle()
    if not LP or not LP.enabled or active then return end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) or not Hooks.CanInteract() then return end
    if LP.mechanicOnly and not DPM.OnDuty() then
        DPM.Notify('Tylko mechanik na służbie może otwierać zamki', 'error')
        return
    end
    local veh = DPM.GetClosestVehicle(GetEntityCoords(ped), 3.0)
    if not veh then return DPM.Notify('Brak auta w pobliżu', 'error') end
    if GetVehicleDoorLockStatus(veh) < 2 then return DPM.Notify('To auto nie jest zamknięte', 'info') end
    if not NetworkGetEntityIsNetworked(veh) then return end
    LPM.Start({ veh = veh })
end

if LP and LP.enabled then
    RegisterCommand(LP.command or 'wytrych', function() CreateThread(tryVehicle) end, false)
    if LP.key then
        RegisterCommand('+dpm_lockpick', function() CreateThread(tryVehicle) end, false)
        RegisterCommand('-dpm_lockpick', function() end, false)
        RegisterKeyMapping('+dpm_lockpick', 'Wytrych – otwórz zamek auta', 'keyboard', LP.key)
    end

    if Config.UseTarget then
        CreateThread(function()
            Wait(1500)
            local option = {
                name = 'dpm_lockpick', label = 'Otwórz zamek wytrychem', icon = 'fas fa-key', distance = 2.2,
                canInteract = function(entity)
                    return not active and GetVehicleDoorLockStatus(entity) >= 2 and (not LP.mechanicOnly or DPM.OnDuty())
                end,
                onSelect = function(data) CreateThread(function() LPM.Start({ veh = data.entity }) end) end,
            }
            if DPM.usingTarget == 'ox' then
                exports.ox_target:addGlobalVehicle({ option })
            elseif DPM.usingTarget == 'qb' then
                exports['qb-target']:AddGlobalVehicle({
                    options = { {
                        icon = option.icon, label = option.label,
                        canInteract = option.canInteract,
                        action = function(entity) CreateThread(function() LPM.Start({ veh = entity }) end) end,
                    } },
                    distance = option.distance,
                })
            end
        end)
    end
end

exports('Lockpick', function(opts) return LPM.Start(opts or {}) end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() or not active then return end
    SetNightvision(false)
    ClearPedTasks(PlayerPedId())
end)
