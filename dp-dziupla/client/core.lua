-- ==========================================================================
--  dp-dziupla – rdzeń klienta: callbacki, narzędzia, stan, zdjęcie pojazdu
-- ==========================================================================
Dz = {
    busy = false,         -- trwa minigra / laptop / animacja
    carrying = nil,       -- niesiona część
    usingTarget = false,
    shop = nil,           -- najbliższa dziupla (w promieniu)
}
local D = Dz

local cbId, cbPending = 0, {}

function D.Callback(name, ...)
    cbId = cbId + 1
    local id = cbId
    local p = promise.new()
    cbPending[id] = p
    TriggerServerEvent('dp-dziupla:server:cb', name, id, ...)
    SetTimeout(15000, function()
        if cbPending[id] then
            cbPending[id] = nil
            p:resolve(nil)
        end
    end)
    return Citizen.Await(p)
end

RegisterNetEvent('dp-dziupla:client:cb', function(id, res)
    local p = cbPending[id]
    if p then
        cbPending[id] = nil
        p:resolve(res)
    end
end)

function D.Notify(msg, kind, time)
    if msg then Hooks.Notify(msg, kind, time) end
end
RegisterNetEvent('dp-dziupla:client:notify', function(msg, kind) D.Notify(msg, kind) end)

RegisterNetEvent('dp-dziupla:client:dispatch', function(kind, coords, data)
    if kind == 'tracker' then D.Notify(L('tracker_ping'), 'warn', 3000) end
    Hooks.Dispatch(kind, coords, data)
end)

function D.Help(text)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, false, -1)
end

function D.LoadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) do
        if GetGameTimer() > timeout then return nil end
        Wait(10)
    end
    return hash
end

function D.LoadDict(dict)
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 5000
    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() > timeout then return false end
        Wait(10)
    end
    return true
end

function D.LoadPtfx(asset)
    RequestNamedPtfxAsset(asset)
    local timeout = GetGameTimer() + 3000
    while not HasNamedPtfxAssetLoaded(asset) do
        if GetGameTimer() > timeout then return false end
        Wait(10)
    end
    return true
end

function D.PlayAnim(a, flag)
    local ped = PlayerPedId()
    if a.scenario then
        TaskStartScenarioInPlace(ped, a.scenario, 0, true)
        return
    end
    if D.LoadDict(a.dict) then TaskPlayAnim(ped, a.dict, a.clip, 3.0, 3.0, -1, flag or 1, 0, false, false, false) end
end

-- dociąga Z do gruntu (config nie musi mieć idealnych wysokości)
function D.GroundZ(v)
    local found, z = GetGroundZFor_3dCoord(v.x, v.y, v.z + 3.0, false)
    if found and math.abs(z - v.z) < 6.0 then return z end
    return v.z
end

function D.Control(ent)
    if not DoesEntityExist(ent) then return false end
    if NetworkHasControlOfEntity(ent) then return true end
    NetworkRequestControlOfEntity(ent)
    local t = GetGameTimer() + 1500
    while not NetworkHasControlOfEntity(ent) and GetGameTimer() < t do
        Wait(20)
        NetworkRequestControlOfEntity(ent)
    end
    return NetworkHasControlOfEntity(ent)
end

function D.Text3D(pos, text, scale)
    local onScreen, x, y = GetScreenCoordFromWorldCoord(pos.x, pos.y, pos.z)
    if not onScreen then return end
    SetTextScale(scale or 0.32, scale or 0.32)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(255, 255, 255, 230)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

function D.Blip(coords, cfg, label, route)
    local b = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(b, cfg.sprite)
    SetBlipColour(b, cfg.color)
    SetBlipScale(b, cfg.scale or 0.8)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandSetBlipName(b)
    if route then
        SetBlipRoute(b, true)
        SetBlipRouteColour(b, cfg.color)
    end
    return b
end

function D.RemoveBlip(b)
    if b and DoesBlipExist(b) then RemoveBlip(b) end
    return nil
end

-- --------------------------------------------------------------------------
--  „Zdjęcie” pojazdu: stan, uszkodzenia, kości, tuning (serwer je waliduje)
-- --------------------------------------------------------------------------
local TYRE = { wheel_lf = 0, wheel_rf = 1, wheel_lr = 4, wheel_rr = 5 }
local DOOR_BONES = { [0] = 'door_dside_f', [1] = 'door_pside_f', [2] = 'door_dside_r', [3] = 'door_pside_r', [4] = 'bonnet', [5] = 'boot' }

local function deformAt(veh, bone)
    local bi = GetEntityBoneIndexByName(veh, bone)
    if bi == -1 then return 0.0 end
    local w = GetWorldPositionOfEntityBone(veh, bi)
    local o = GetOffsetFromEntityGivenWorldCoords(veh, w.x, w.y, w.z)
    return #GetVehicleDeformationAtPos(veh, o.x, o.y, o.z)
end

function D.Snapshot(veh)
    local model = GetEntityModel(veh)
    local name = GetDisplayNameFromVehicleModel(model)
    local label = GetLabelText(name)
    if not label or label == 'NULL' then label = name end
    local s = {
        model = model, name = name, label = label, class = GetVehicleClass(veh),
        body = GetVehicleBodyHealth(veh), engine = GetVehicleEngineHealth(veh), tank = GetVehiclePetrolTankHealth(veh),
        wheels = GetVehicleNumberOfWheels(veh),
        doors = {}, doorDmg = {}, tyres = {}, hl = {}, bumperOff = {}, windows = {}, bones = {}, mods = {},
    }
    for i = 0, 5 do
        s.doors[i + 1] = GetIsDoorValid(veh, i) and not IsVehicleDoorDamaged(veh, i)
        s.doorDmg[i + 1] = deformAt(veh, DOOR_BONES[i]) > 0.08
    end
    for _, b in ipairs(Parts.Bones) do s.bones[b] = GetEntityBoneIndexByName(veh, b) ~= -1 end
    for b, idx in pairs(TYRE) do s.tyres[b] = IsVehicleTyreBurst(veh, idx, false) end
    s.hl.l = GetIsLeftVehicleHeadlightDamaged(veh)
    s.hl.r = GetIsRightVehicleHeadlightDamaged(veh)
    s.bumperOff.f = IsVehicleBumperBrokenOff(veh, true)
    s.bumperOff.r = IsVehicleBumperBrokenOff(veh, false)
    s.windows.front = IsVehicleWindowIntact(veh, 6)
    s.windows.rear = IsVehicleWindowIntact(veh, 7)
    SetVehicleModKit(veh, 0)
    s.mods = {
        spoiler = GetVehicleMod(veh, 0), bumperF = GetVehicleMod(veh, 1), bumperR = GetVehicleMod(veh, 2),
        exhaust = GetVehicleMod(veh, 4), hood = GetVehicleMod(veh, 7), engine = GetVehicleMod(veh, 11),
        brakes = GetVehicleMod(veh, 12), trans = GetVehicleMod(veh, 13), susp = GetVehicleMod(veh, 15),
        wheels = GetVehicleMod(veh, 23), turbo = IsToggleModOn(veh, 18), xenon = IsToggleModOn(veh, 22),
    }
    return s
end

-- --------------------------------------------------------------------------
--  Kotwice części w układzie pojazdu
-- --------------------------------------------------------------------------
local anchorCache = {}   -- [veh] = { model, [partId] = vector3 }

function D.AnchorLocal(veh, def)
    local cache = anchorCache[veh]
    local model = GetEntityModel(veh)
    if not cache or cache.model ~= model then
        cache = { model = model }
        anchorCache[veh] = cache
    end
    if cache[def.id] then return cache[def.id] end
    local a = def.anchor
    local sx = (def.side and def.side ~= 0) and def.side or 1
    local loc
    if a.bone then
        local bi = GetEntityBoneIndexByName(veh, a.bone)
        if bi ~= -1 then
            local w = GetWorldPositionOfEntityBone(veh, bi)
            loc = GetOffsetFromEntityGivenWorldCoords(veh, w.x, w.y, w.z)
            if a.off then loc = loc + a.off end
        end
    end
    if not loc then
        local mn, mx = GetModelDimensions(model)
        local c = (mn + mx) / 2
        local h = (mx - mn) / 2
        loc = vector3(c.x + a.fb.x * sx * h.x, c.y + a.fb.y * h.y, c.z + a.fb.z * h.z)
    end
    if a.absX then loc = vector3(a.absX, loc.y, loc.z) end
    cache[def.id] = loc
    return loc
end

-- punkt w układzie części (x = „na zewnątrz” dla części bocznych) -> świat
function D.PartWorld(veh, def, loc, o)
    local sx = (def.side and def.side ~= 0) and def.side or 1
    return GetOffsetFromEntityInWorldCoords(veh, loc.x + o.x * sx, loc.y + o.y, loc.z + o.z)
end

function D.ClearAnchorCache(veh)
    if veh then anchorCache[veh] = nil else anchorCache = {} end
end

-- --------------------------------------------------------------------------
--  Interakcje / target
-- --------------------------------------------------------------------------
CreateThread(function()
    Wait(1000)
    if Config.UseTarget then
        if GetResourceState('ox_target') == 'started' then D.usingTarget = 'ox'
        elseif GetResourceState('qb-target') == 'started' then D.usingTarget = 'qb' end
    end
end)

function D.TargetPed(ped, name, icon, label, fn)
    if D.usingTarget == 'ox' then
        exports.ox_target:addLocalEntity(ped, { {
            name = name, icon = icon, label = label, distance = 2.5,
            canInteract = function() return not D.busy end, onSelect = fn,
        } })
    elseif D.usingTarget == 'qb' then
        exports['qb-target']:AddTargetEntity(ped, {
            options = { { icon = icon, label = label, action = fn, canInteract = function() return not D.busy end } },
            distance = 2.5,
        })
    end
end

function D.SpawnPed(model, c, scenario)
    local hash = D.LoadModel(model)
    if not hash then return nil end
    local z = D.GroundZ(c.xyz)
    local ped = CreatePed(4, hash, c.x, c.y, z, c.w, false, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)
    if scenario then TaskStartScenarioInPlace(ped, scenario, 0, true) end
    SetModelAsNoLongerNeeded(hash)
    return ped
end

if Config.Debug then
    RegisterCommand('dziupla_pos', function()
        local ped = PlayerPedId()
        local c = GetEntityCoords(ped)
        local out = ('vec4(%.2f, %.2f, %.2f, %.1f)'):format(c.x, c.y, c.z, GetEntityHeading(ped))
        print(out)
        D.Notify(out, 'info', 10000)
    end, false)
end
