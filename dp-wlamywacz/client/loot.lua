-- ==========================================================================
--  Noszenie dużych łupów (LUP-03) i ładowanie do bagażnika (LOG-01).
--  Pętla klatkowa działa tylko, gdy niesiesz przedmiot (blokada sprintu i skoku).
-- ==========================================================================
local carryObj
local CARRY_DICT, CARRY_CLIP = 'anim@heists@box_carry@', 'idle'

local function nearestVehicle(pc)
    local best, bd
    for _, v in ipairs(GetGamePool('CVehicle')) do
        local d = #(GetEntityCoords(v) - pc)
        if d < 7.0 and (not bd or d < bd) then best, bd = v, d end
    end
    if not best then return nil end
    -- stań przy bagażniku: tył pojazdu
    local min, max = GetModelDimensions(GetEntityModel(best))
    local rear = GetOffsetFromEntityInWorldCoords(best, 0.0, min.y - 0.4, 0.0)
    if #(rear - pc) < 2.2 then return best end
    return nil
end

local function stopCarry()
    local ped = PlayerPedId()
    if carryObj and DoesEntityExist(carryObj) then
        DetachEntity(carryObj, true, true)
        DeleteEntity(carryObj)
    end
    carryObj = nil
    StopAnimTask(ped, CARRY_DICT, CARRY_CLIP, 2.0)
    W.carry = nil
    W.Hud({ carry = false })
end

local function startCarry(data)
    local ped = PlayerPedId()
    W.carry = data
    W.Hud({ carry = Config.Loot[data.key] and Config.Loot[data.key].label or data.key })
    if W.LoadDict(CARRY_DICT) then TaskPlayAnim(ped, CARRY_DICT, CARRY_CLIP, 3.0, 3.0, -1, 49, 0, false, false, false) end
    local hash = data.prop and W.LoadModel(data.prop)
    if hash then
        local c = GetEntityCoords(ped)
        carryObj = CreateObject(hash, c.x, c.y, c.z + 0.5, true, true, false)
        SetModelAsNoLongerNeeded(hash)
        AttachEntityToEntity(carryObj, ped, GetPedBoneIndex(ped, 60309), 0.025, 0.08, 0.255, -145.0, 290.0, 0.0, true, true, false, true, 1, true)
        W.Callback('carry:net', NetworkGetNetworkIdFromEntity(carryObj))
    end
    CreateThread(function()
        local veh, nextScan = nil, 0
        while W.carry do
            DisableControlAction(0, 21, true) -- sprint
            DisableControlAction(0, 22, true) -- skok
            DisableControlAction(0, 23, true) -- wsiadanie
            DisableControlAction(0, 24, true) DisableControlAction(0, 25, true)
            if not IsEntityPlayingAnim(ped, CARRY_DICT, CARRY_CLIP, 3) then
                TaskPlayAnim(ped, CARRY_DICT, CARRY_CLIP, 3.0, 3.0, -1, 49, 0, false, false, false)
            end
            local now = GetGameTimer()
            if now > nextScan then
                nextScan = now + 250
                veh = not W.session and nearestVehicle(GetEntityCoords(ped)) or nil
            end
            if veh then
                W.Help(L('trunk_help'))
                if IsControlJustReleased(0, 38) and not W.busy then
                    SetVehicleDoorOpen(veh, 5, false, false)
                    Wait(600)
                    local r = W.Call('loot:trunk', NetworkGetNetworkIdFromEntity(veh), Hooks.VehicleClass(veh))
                    Wait(400)
                    SetVehicleDoorShut(veh, 5, false)
                    if r and r.ok then break end
                end
            else
                W.Help(L('carry_help'))
            end
            if IsControlJustReleased(0, 47) and not W.busy then
                W.EmitNoise(W.session and Config.Noise.actions.take or Config.Noise.actions.drop)
                W.Call('loot:drop')
                break
            end
            Wait(0)
        end
    end)
end

RegisterNetEvent('dp-wlamywacz:client:carry', function(data)
    if data then
        if W.carry then stopCarry() end
        startCarry(data)
    else
        stopCarry()
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and carryObj and DoesEntityExist(carryObj) then DeleteEntity(carryObj) end
end)
