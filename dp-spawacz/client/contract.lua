-- ==========================================================================
--  Aktywne zlecenie: blipy, rekwizyty, punkty pracy, pojazd służbowy
--  Pętla działa tylko przy aktywnym zleceniu i usypia się zależnie od dystansu.
-- ==========================================================================
local S = Spawacz
local siteBlip

local function fwd(h)
    local r = math.rad(h)
    return vector3(-math.sin(r), math.cos(r), 0.0)
end

local function removeTaskStuff(t)
    if t.obj and DoesEntityExist(t.obj) then DeleteEntity(t.obj) end
    t.obj = nil
    if t.blip and DoesBlipExist(t.blip) then RemoveBlip(t.blip) end
    t.blip = nil
    if t.zone then
        if S.usingTarget == 'ox' then exports.ox_target:removeZone(t.zone)
        elseif S.usingTarget == 'qb' then exports['qb-target']:RemoveZone(t.zone) end
        t.zone = nil
    end
end

local function spawnProp(t)
    if not t.prop or t.obj then return end
    local hash = S.LoadModel(t.prop)
    if not hash then
        t.prop = nil -- model niedostępny – pracujemy bez rekwizytu
        return
    end
    local p = t.pos + fwd(t.heading) * 1.05
    t.obj = CreateObject(hash, p.x, p.y, p.z, false, false, false)
    SetEntityHeading(t.obj, t.heading)
    PlaceObjectOnGroundProperly(t.obj)
    FreezeEntityPosition(t.obj, true)
    SetEntityCollision(t.obj, true, true)
    SetModelAsNoLongerNeeded(hash)
end

local function addZone(t)
    if t.zone or not S.usingTarget then return end
    local label = L('target_task', t.typeLabel)
    if S.usingTarget == 'ox' then
        t.zone = exports.ox_target:addSphereZone({
            coords = t.pos + vector3(0.0, 0.0, 0.8), radius = 1.2,
            options = { { name = 'dp_spawacz_task', icon = 'fa-solid fa-fire-flame-curved', label = label, distance = 2.0,
                canInteract = function() return not S.busy end,
                onSelect = function() S.BeginTask(t) end } },
        })
    else
        local name = ('dp_spawacz_task_%d'):format(t.id)
        exports['qb-target']:AddCircleZone(name, t.pos + vector3(0.0, 0.0, 0.8), 1.2, { name = name, useZ = true, debugPoly = false }, {
            options = { { icon = 'fas fa-fire', label = label, action = function() S.BeginTask(t) end, canInteract = function() return not S.busy end } },
            distance = 2.0,
        })
        t.zone = name
    end
end

local function taskBlip(t)
    local b = AddBlipForCoord(t.pos.x, t.pos.y, t.pos.z)
    SetBlipSprite(b, Config.TaskBlip.sprite)
    SetBlipColour(b, Config.TaskBlip.color)
    SetBlipScale(b, Config.TaskBlip.scale)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Spawanie: ' .. t.typeLabel)
    EndTextCommandSetBlipName(b)
    t.blip = b
end

local function spawnVan()
    local hash = S.LoadModel(Config.Vehicle.model)
    if not hash then return end
    local c = Config.Depot.vehicleSpawn
    local veh = CreateVehicle(hash, c.x, c.y, c.z, c.w, true, false)
    local plate = (Config.Vehicle.plate .. tostring(math.random(1000, 9999))):sub(1, 8)
    SetVehicleNumberPlateText(veh, plate)
    SetVehicleOnGroundProperly(veh)
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleDirtLevel(veh, 0.0)
    SetModelAsNoLongerNeeded(hash)
    Hooks.GiveKeys(veh, plate)
    Hooks.SetFuel(veh, 100.0)
    local netId = NetworkGetNetworkIdFromEntity(veh)
    S.Callback('registerVan', netId)
end

local function taskLoop()
    CreateThread(function()
        while S.contract do
            local sleep = 1000
            local pc = GetEntityCoords(PlayerPedId())
            for _, t in ipairs(S.contract.tasks) do
                if not t.done and not t.failed then
                    local d = #(pc - t.pos)
                    if d < 120.0 then
                        if not t.snapped then
                            t.pos = vector3(t.pos.x, t.pos.y, S.GroundZ(t.pos))
                            t.snapped = true
                        end
                        spawnProp(t)
                        addZone(t)
                    elseif d > 160.0 and t.obj then
                        DeleteEntity(t.obj)
                        t.obj = nil
                    end
                    if d < 30.0 then
                        sleep = 0
                        local m = Config.Marker
                        DrawMarker(m.type, t.pos.x, t.pos.y, t.pos.z + 0.35, 0.0, 0.0, 0.0, 0.0, 180.0, 0.0,
                            m.size.x, m.size.y, m.size.z, m.color[1], m.color[2], m.color[3], m.color[4], true, true, 2, false, nil, nil, false)
                        if not S.usingTarget and d < 1.4 and not S.busy then
                            S.Help(L('help_task', t.typeLabel))
                            if IsControlJustReleased(0, 38) then S.BeginTask(t) end
                        end
                    elseif d < 90.0 and sleep > 400 then
                        sleep = 400
                    end
                end
            end
            Wait(sleep)
        end
    end)
end

function S.StartContract(c)
    S.EndContract()
    for _, t in ipairs(c.tasks) do
        t.pos = vector3(t.coords.x, t.coords.y, t.coords.z)
        t.heading = t.coords.w
    end
    S.contract = c
    siteBlip = AddBlipForCoord(c.center.x, c.center.y, c.center.z)
    SetBlipSprite(siteBlip, 1)
    SetBlipColour(siteBlip, 47)
    SetBlipRoute(siteBlip, true)
    SetBlipRouteColour(siteBlip, 47)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(c.siteLabel)
    EndTextCommandSetBlipName(siteBlip)
    for _, t in ipairs(c.tasks) do
        if not t.done and not t.failed then taskBlip(t) end
    end
    if c.vehicle then spawnVan() end
    taskLoop()
end

-- aktualizacja po zakończeniu zadania (serwer odsyła stan)
function S.UpdateContract(view)
    if not S.contract then return end
    for i, v in ipairs(view.tasks) do
        local t = S.contract.tasks[i]
        if t then
            t.done, t.failed, t.grade = v.done, v.failed, v.grade
            if t.done or t.failed then removeTaskStuff(t) end
        end
    end
    local left = 0
    for _, t in ipairs(S.contract.tasks) do
        if not t.done and not t.failed then left = left + 1 end
    end
    if left == 0 and siteBlip then
        RemoveBlip(siteBlip)
        siteBlip = nil
        SetNewWaypoint(Config.Depot.ped.coords.x, Config.Depot.ped.coords.y)
    end
    return left
end

function S.WaypointNext()
    if not S.contract then return end
    local pc = GetEntityCoords(PlayerPedId())
    local best, bd
    for _, t in ipairs(S.contract.tasks) do
        if not t.done and not t.failed then
            local d = #(pc - t.pos)
            if not bd or d < bd then best, bd = t, d end
        end
    end
    if best then SetNewWaypoint(best.pos.x, best.pos.y)
    else SetNewWaypoint(Config.Depot.ped.coords.x, Config.Depot.ped.coords.y) end
end

function S.EndContract()
    if S.contract then
        for _, t in ipairs(S.contract.tasks) do removeTaskStuff(t) end
    end
    if siteBlip and DoesBlipExist(siteBlip) then RemoveBlip(siteBlip) end
    siteBlip = nil
    S.contract = nil
end

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then S.EndContract() end
end)
