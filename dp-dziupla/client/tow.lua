-- ==========================================================================
--  Laweta: wypożyczenie w dziupli, wciąganie aut z listy na platformę,
--  zsuwanie (np. prosto na stanowisko rozbiórki)
-- ==========================================================================
local D = Dz
local T = Config.Tow
D.TowNet = nil
local towCar          -- auto aktualnie na platformie

local function vehFromNet(net)
    if not net or not NetworkDoesNetworkIdExist(net) then return nil end
    local v = NetToVeh(net)
    return (v ~= 0 and DoesEntityExist(v)) and v or nil
end

function D.TowAction(has)
    if D.busy then return end
    D.busy = true
    local r = D.Callback(has and 'towReturn' or 'towRent')
    D.busy = false
    if not r then return end
    if r.ok and not has then
        D.TowNet = r.net
        local t = GetGameTimer() + 5000
        local v = vehFromNet(r.net)
        while not v and GetGameTimer() < t do Wait(100) v = vehFromNet(r.net) end
        if v then Hooks.GiveKeys(v, r.plate) end
    elseif r.ok then
        D.TowNet, towCar = nil, nil
    end
    if r.msg then D.Notify(r.msg, r.ok and 'good' or 'bad', 7000) end
end

local function rearOf(tow)
    return GetOffsetFromEntityInWorldCoords(tow, 0.0, -4.6, 0.0)
end

local function findCar(tow)
    local rear = rearOf(tow)
    local best, bd
    for _, v in ipairs(GetGamePool('CVehicle')) do
        if v ~= tow then
            local s = Entity(v).state
            if s.dpStolen and not s.dpChop and not s.dpTowed then
                local d = #(GetEntityCoords(v) - rear)
                if d < T.maxDist and (not bd or d < bd) then best, bd = v, d end
            end
        end
    end
    return best
end

local function load(tow, car)
    D.busy = true
    local ped = PlayerPedId()
    TaskTurnPedToFaceEntity(ped, car, 800)
    Wait(800)
    D.PlayAnim(Config.Anim.stand, 1)
    local r = D.Callback('towLoad', D.TowNet, NetworkGetNetworkIdFromEntity(car))
    if r and r.ok then
        if r.alarm and D.Control(car) then
            SetVehicleAlarm(car, true)
            SetVehicleAlarmTimeLeft(car, 30000)
            StartVehicleAlarm(car)
            D.Notify(L('alarm'), 'bad')
            Hooks.Dispatch('alarm', GetEntityCoords(car), { plate = r.plate })
        end
        -- wciąganie: auto płynnie jedzie na platformę
        if D.Control(car) and D.Control(tow) then
            local from = GetEntityCoords(car)
            local to = GetOffsetFromEntityInWorldCoords(tow, T.attach.x, T.attach.y, T.attach.z)
            local steps = math.floor(T.loadTime / 50)
            FreezeEntityPosition(car, true)
            SetEntityCollision(car, false, false)
            for i = 1, steps do
                local k = i / steps
                local p = from + (to - from) * k
                SetEntityCoordsNoOffset(car, p.x, p.y, p.z, false, false, false)
                SetEntityHeading(car, GetEntityHeading(tow))
                Wait(50)
            end
            FreezeEntityPosition(car, false)
            SetEntityCollision(car, true, true)
            local bone = GetEntityBoneIndexByName(tow, 'chassis')
            AttachEntityToEntity(car, tow, bone, T.attach.x, T.attach.y, T.attach.z, 0.0, 0.0, 0.0, false, false, true, false, 2, true)
            towCar = car
        end
        D.Notify(r.msg, 'good')
    elseif r and r.msg then
        D.Notify(r.msg, 'bad')
    end
    ClearPedTasks(ped)
    D.busy = false
end

local function unload(tow, car)
    D.busy = true
    if D.Control(car) then
        DetachEntity(car, true, true)
        local p = GetOffsetFromEntityInWorldCoords(tow, 0.0, -7.5, 0.5)
        SetEntityCoords(car, p.x, p.y, p.z, false, false, false, false)
        SetEntityHeading(car, GetEntityHeading(tow))
        SetVehicleOnGroundProperly(car)
    end
    D.Callback('towUnload', D.TowNet, NetworkGetNetworkIdFromEntity(car))
    towCar = nil
    D.busy = false
end

CreateThread(function()
    Wait(3000)
    local r = D.Callback('towState')
    if r and r.net then D.TowNet = r.net end
    while true do
        local sleep = 1000
        local tow = D.TowNet and vehFromNet(D.TowNet)
        if D.TowNet and not tow and not NetworkDoesNetworkIdExist(D.TowNet) then D.TowNet = nil end
        if tow and not D.busy then
            local ped = PlayerPedId()
            if not IsPedInAnyVehicle(ped, false) then
                local rear = rearOf(tow)
                if #(GetEntityCoords(ped) - rear) < 3.0 then
                    sleep = 0
                    if towCar and DoesEntityExist(towCar) and IsEntityAttachedToEntity(towCar, tow) then
                        D.Help(L('help_tow_unload'))
                        if IsControlJustReleased(0, 38) then CreateThread(function() unload(tow, towCar) end) end
                    else
                        local car = findCar(tow)
                        if car then
                            D.Help(L('help_tow_load'))
                            if IsControlJustReleased(0, 38) then CreateThread(function() load(tow, car) end) end
                        end
                    end
                else
                    sleep = 300
                end
            end
        end
        Wait(sleep)
    end
end)
