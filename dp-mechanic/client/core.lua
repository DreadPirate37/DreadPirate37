-- ==========================================================================
--  dp-mechanic – rdzeń klienta
--  Callbacki serwera, most NUI, członkostwo w warsztacie, narzędzia, właściwości aut.
--  Każdy moduł klienta dopina się do globalnej tabeli DPM (DPM.Camera, DPM.Tuning…).
-- ==========================================================================
DPM = {
    member = nil,     -- { identifier, name, workshop, rank = { id, level, label }, perms = {}, duty }
    busy = false,     -- nazwa aktywnej czynności ('tuning', 'assembly', 'tire', 'tablet', 'payment', 'dyno'…)
    nuiReady = false,
    usingTarget = false,
    WheelBones = { 'wheel_lf', 'wheel_rf', 'wheel_lr', 'wheel_rr' },
    WheelLabels = { 'Lewe przednie', 'Prawe przednie', 'Lewe tylne', 'Prawe tylne' },
}

-- --------------------------------------------------------------------------
--  Callbacki serwera
-- --------------------------------------------------------------------------
local cbId, cbPending = 0, {}

function DPM.Callback(name, ...)
    cbId = cbId + 1
    local id = cbId
    local p = promise.new()
    cbPending[id] = p
    TriggerServerEvent('dp-mechanic:cb', name, id, ...)
    SetTimeout(15000, function()
        if cbPending[id] then
            cbPending[id] = nil
            p:resolve({ ok = false, err = 'Brak odpowiedzi serwera' })
        end
    end)
    return Citizen.Await(p)
end

RegisterNetEvent('dp-mechanic:cbr', function(id, res)
    local p = cbPending[id]
    if p then
        cbPending[id] = nil
        p:resolve(res)
    end
end)

-- --------------------------------------------------------------------------
--  Powiadomienia / debug
-- --------------------------------------------------------------------------
function DPM.Notify(msg, kind, time)
    Hooks.Notify(msg, kind, time)
end
RegisterNetEvent('dp-mechanic:notify', function(msg, kind, time) DPM.Notify(msg, kind, time) end)

function DPM.Debug(...)
    if Config.Debug then print('[dp-mechanic]', ...) end
end

-- --------------------------------------------------------------------------
--  Członkostwo w warsztacie
-- --------------------------------------------------------------------------
RegisterNetEvent('dp-mechanic:member', function(member)
    DPM.member = member
    TriggerEvent('dp-mechanic:memberChanged', member)
end)

function DPM.IsMechanic() return DPM.member ~= nil end
function DPM.OnDuty() return DPM.member ~= nil and (DPM.member.duty or not Config.RequireDuty) end
function DPM.Can(perm)
    return DPM.member ~= nil and Utils.HasPerm(DPM.member.perms, perm)
end
function DPM.Workshop()
    return DPM.member and Config.Workshops[DPM.member.workshop] or nil
end

-- warsztat, w którego strefie jest punkt
function DPM.WorkshopAt(coords)
    for id, ws in pairs(Config.Workshops) do
        if #(coords - ws.zone.center) <= ws.zone.radius then return id, ws end
    end
    return nil
end

-- czy gracz może pracować przy autach w danym warsztacie (członek + służba + właściwy warsztat)
function DPM.CanWorkHere(coords)
    if not DPM.OnDuty() then return false end
    local id = DPM.WorkshopAt(coords or GetEntityCoords(PlayerPedId()))
    return id ~= nil and id == DPM.member.workshop
end

function DPM.SetBusy(tag)
    DPM.busy = tag or false
end

-- --------------------------------------------------------------------------
--  NUI
-- --------------------------------------------------------------------------
function DPM.Nui(action, data)
    data = data or {}
    data.action = action
    SendNUIMessage(data)
end

local focusState = { focus = false, cursor = false, keep = false }
function DPM.Focus(hasFocus, hasCursor, keepInput)
    focusState.focus, focusState.cursor, focusState.keep = hasFocus, hasCursor, keepInput == true
    SetNuiFocus(hasFocus, hasCursor)
    SetNuiFocusKeepInput(keepInput == true)
end
function DPM.FocusState() return focusState end

-- rejestracja callbacku NUI; fn(data) wykonywana w wątku, zwraca wynik dla JS
function DPM.RegisterNui(name, fn)
    RegisterNUICallback(name, function(data, cb)
        CreateThread(function()
            local ok, res = pcall(fn, data or {})
            if not ok then
                print(('[dp-mechanic] błąd NUI %s: %s'):format(name, tostring(res)))
                cb({ ok = false, err = 'Błąd skryptu' })
                return
            end
            if res == nil then res = { ok = true } end
            cb(res)
        end)
    end)
end

DPM.RegisterNui('nui_ready', function()
    DPM.nuiReady = true
    return { ok = true, currency = Config.Currency }
end)

function DPM.KeyHint(list)
    DPM.Nui('keyhint', { list = list })
end

function DPM.Sound(name)
    DPM.Nui('sound', { name = name })
end

-- --------------------------------------------------------------------------
--  Ładowanie zasobów / encje
-- --------------------------------------------------------------------------
function DPM.LoadModel(model)
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

function DPM.LoadDict(dict)
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 5000
    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() > timeout then return false end
        Wait(10)
    end
    return true
end

function DPM.LoadPtfx(asset)
    if HasNamedPtfxAssetLoaded(asset) then return true end
    RequestNamedPtfxAsset(asset)
    local timeout = GetGameTimer() + 5000
    while not HasNamedPtfxAssetLoaded(asset) do
        if GetGameTimer() > timeout then return false end
        Wait(10)
    end
    return true
end

function DPM.RequestControl(entity, timeout)
    if not DoesEntityExist(entity) then return false end
    if NetworkHasControlOfEntity(entity) then return true end
    NetworkRequestControlOfEntity(entity)
    local t = GetGameTimer() + (timeout or 1500)
    while not NetworkHasControlOfEntity(entity) do
        if GetGameTimer() > t then return false end
        NetworkRequestControlOfEntity(entity)
        Wait(20)
    end
    return true
end

function DPM.DeleteEntity(ent)
    if ent and DoesEntityExist(ent) then
        SetEntityAsMissionEntity(ent, true, true)
        DeleteEntity(ent)
    end
end

function DPM.PlayAnim(ped, dict, clip, flag, duration)
    if not DPM.LoadDict(dict) then return false end
    TaskPlayAnim(ped, dict, clip, 3.0, 3.0, duration or -1, flag or 1, 0.0, false, false, false)
    return true
end

-- prop przyczepiony do kości (spawn lokalny, sieciowy – widoczny dla innych)
function DPM.AttachProp(ped, model, bone, pos, rot)
    local hash = DPM.LoadModel(model) or DPM.LoadModel('prop_cs_cardbox_01')
    if not hash then return nil end
    local c = GetEntityCoords(ped)
    local obj = CreateObject(hash, c.x, c.y, c.z + 0.2, true, true, false)
    SetEntityCollision(obj, false, false)
    AttachEntityToEntity(obj, ped, GetPedBoneIndex(ped, bone or 28422), pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(hash)
    return obj
end

-- --------------------------------------------------------------------------
--  Tekst / pomoc
-- --------------------------------------------------------------------------
function DPM.Help(text)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, false, -1)
end

function DPM.Text3D(coords, text, scale)
    local onScreen, x, y = GetScreenCoordFromWorldCoord(coords.x, coords.y, coords.z)
    if not onScreen then return end
    SetTextScale(0.0, scale or 0.32)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(255, 255, 255, 230)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

-- --------------------------------------------------------------------------
--  Pojazdy
-- --------------------------------------------------------------------------
function DPM.Plate(veh)
    return Utils.Plate(GetVehicleNumberPlateText(veh))
end

function DPM.VehLabel(veh)
    local model = GetEntityModel(veh)
    local name = GetLabelText(GetDisplayNameFromVehicleModel(model))
    if not name or name == 'NULL' then name = GetDisplayNameFromVehicleModel(model) end
    local make = GetMakeNameFromVehicleModel and GetLabelText(GetMakeNameFromVehicleModel(model)) or nil
    if make and make ~= 'NULL' and make ~= '' then return make .. ' ' .. name end
    return name
end

function DPM.GetClosestVehicle(coords, radius)
    coords = coords or GetEntityCoords(PlayerPedId())
    local best, bestD = nil, radius or 5.0
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        local d = #(coords - GetEntityCoords(veh))
        if d < bestD then best, bestD = veh, d end
    end
    return best, bestD
end

function DPM.FindVehicleByPlate(plate, coords, radius)
    plate = Utils.Plate(plate)
    coords = coords or GetEntityCoords(PlayerPedId())
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        if #(coords - GetEntityCoords(veh)) <= (radius or 25.0) and DPM.Plate(veh) == plate then return veh end
    end
    return nil
end

function DPM.GetVehData(veh)
    if not veh or not DoesEntityExist(veh) then return nil end
    return Entity(veh).state.dpm
end

-- prosi serwer o powiązanie auta z danymi technicznymi (statebag 'dpm') i czeka na nie
function DPM.EnsureVehData(veh)
    if not veh or not DoesEntityExist(veh) then return nil end
    local d = Entity(veh).state.dpm
    if d then return d end
    if not NetworkGetEntityIsNetworked(veh) then return nil end
    TriggerServerEvent('dp-mechanic:veh:touch', VehToNet(veh))
    local t = GetGameTimer() + 2500
    while GetGameTimer() < t do
        Wait(50)
        d = Entity(veh).state.dpm
        if d then return d end
    end
    return nil
end

function DPM.WheelCount(veh)
    return math.min(GetVehicleNumberOfWheels(veh), 4)
end

-- pozycja koła w świecie (1..4)
function DPM.WheelPos(veh, wheel)
    local bone = GetEntityBoneIndexByName(veh, DPM.WheelBones[wheel])
    if bone == -1 then
        local min, max = GetModelDimensions(GetEntityModel(veh))
        local rel = ({ vec3(-0.9, 0.62, -0.55), vec3(0.9, 0.62, -0.55), vec3(-0.9, -0.62, -0.55), vec3(0.9, -0.62, -0.55) })[wheel]
        local off = Utils.BoxOffset(min, max, rel)
        return GetOffsetFromEntityInWorldCoords(veh, off.x, off.y, off.z)
    end
    return GetWorldPositionOfEntityBone(veh, bone)
end

-- poziomy modów GTA potrzebne do obliczeń handlingu
function DPM.GetGtaModLevels(veh)
    local out = {}
    for t, m in pairs(Config.ModTypes) do
        if m.effects then
            if m.toggle then
                out[t] = IsToggleModOn(veh, t) and 1 or -1
            else
                out[t] = GetVehicleMod(veh, t)
            end
        end
    end
    return out
end

-- --------------------------------------------------------------------------
--  Właściwości wyglądu auta (mody, kolory, neony…) – format zgodny z ox_lib/qb
-- --------------------------------------------------------------------------
function DPM.GetProps(veh)
    if not DoesEntityExist(veh) then return nil end
    local c1, c2 = GetVehicleColours(veh)
    local pearl, wheelColor = GetVehicleExtraColours(veh)
    local props = {
        model = GetEntityModel(veh),
        plate = GetVehicleNumberPlateText(veh),
        plateIndex = GetVehicleNumberPlateTextIndex(veh),
        color1 = c1, color2 = c2,
        pearlescentColor = pearl, wheelColor = wheelColor,
        wheels = GetVehicleWheelType(veh),
        windowTint = GetVehicleWindowTint(veh),
        xenonColor = GetVehicleXenonLightsColor(veh),
        neonEnabled = { IsVehicleNeonLightEnabled(veh, 0), IsVehicleNeonLightEnabled(veh, 1), IsVehicleNeonLightEnabled(veh, 2), IsVehicleNeonLightEnabled(veh, 3) },
        neonColor = table.pack(GetVehicleNeonLightsColour(veh)),
        tyreSmokeColor = table.pack(GetVehicleTyreSmokeColor(veh)),
        interiorColor = GetVehicleInteriorColor(veh),
        dashboardColor = GetVehicleDashboardColor(veh),
        livery = GetVehicleLivery(veh),
        paintType1 = (GetVehicleModColor_1(veh)),
        paintType2 = (GetVehicleModColor_2(veh)),
        extras = {},
        modVariation = GetVehicleModVariation(veh, 23),
    }
    props.neonColor.n = nil
    props.tyreSmokeColor.n = nil
    if GetIsVehiclePrimaryColourCustom(veh) then props.customPrimaryColor = table.pack(GetVehicleCustomPrimaryColour(veh)) props.customPrimaryColor.n = nil end
    if GetIsVehicleSecondaryColourCustom(veh) then props.customSecondaryColor = table.pack(GetVehicleCustomSecondaryColour(veh)) props.customSecondaryColor.n = nil end
    for i = 0, 20 do
        if DoesExtraExist(veh, i) then props.extras[tostring(i)] = IsVehicleExtraTurnedOn(veh, i) end
    end
    for t = 0, 48 do
        if t == 18 or t == 20 or t == 22 then
            props['mod' .. t] = IsToggleModOn(veh, t)
        elseif t ~= 17 and t ~= 19 and t ~= 21 and t ~= 47 then
            props['mod' .. t] = GetVehicleMod(veh, t)
        end
    end
    -- zgodność z nazewnictwem ox_lib / qb
    props.modSpoilers, props.modFrontBumper, props.modRearBumper = props.mod0, props.mod1, props.mod2
    props.modSideSkirt, props.modExhaust, props.modFrame, props.modGrille = props.mod3, props.mod4, props.mod5, props.mod6
    props.modHood, props.modFender, props.modRightFender, props.modRoof = props.mod7, props.mod8, props.mod9, props.mod10
    props.modEngine, props.modBrakes, props.modTransmission, props.modHorns = props.mod11, props.mod12, props.mod13, props.mod14
    props.modSuspension, props.modArmor, props.modTurbo, props.modSmokeEnabled = props.mod15, props.mod16, props.mod18, props.mod20
    props.modXenon, props.modFrontWheels, props.modBackWheels = props.mod22, props.mod23, props.mod24
    props.modPlateHolder, props.modVanityPlate, props.modTrimA, props.modOrnaments = props.mod25, props.mod26, props.mod27, props.mod28
    props.modDashboard, props.modDial, props.modDoorSpeaker, props.modSeats = props.mod29, props.mod30, props.mod31, props.mod32
    props.modSteeringWheel, props.modShifterLeavers, props.modAPlate, props.modSpeakers = props.mod33, props.mod34, props.mod35, props.mod36
    props.modTrunk, props.modHydrolic, props.modEngineBlock, props.modAirFilter = props.mod37, props.mod38, props.mod39, props.mod40
    props.modStruts, props.modArchCover, props.modAerials, props.modTrimB = props.mod41, props.mod42, props.mod43, props.mod44
    props.modTank, props.modWindows, props.modLivery = props.mod45, props.mod46, props.mod48
    return props
end

function DPM.SetProps(veh, p)
    if not p or not DoesEntityExist(veh) then return end
    SetVehicleModKit(veh, 0)
    if p.wheels then SetVehicleWheelType(veh, p.wheels) end
    if p.color1 or p.color2 then
        local c1, c2 = GetVehicleColours(veh)
        SetVehicleColours(veh, p.color1 or c1, p.color2 or c2)
    end
    if p.paintType1 then
        local _, col, pr = GetVehicleModColor_1(veh)
        SetVehicleModColor_1(veh, p.paintType1, col or 0, pr or 0)
    end
    if p.paintType2 then
        local _, col = GetVehicleModColor_2(veh)
        SetVehicleModColor_2(veh, p.paintType2, col or 0)
    end
    if p.customPrimaryColor then SetVehicleCustomPrimaryColour(veh, p.customPrimaryColor[1], p.customPrimaryColor[2], p.customPrimaryColor[3])
    elseif p.color1 then ClearVehicleCustomPrimaryColour(veh) SetVehicleColours(veh, p.color1, p.color2 or select(2, GetVehicleColours(veh))) end
    if p.customSecondaryColor then SetVehicleCustomSecondaryColour(veh, p.customSecondaryColor[1], p.customSecondaryColor[2], p.customSecondaryColor[3])
    elseif p.color2 then ClearVehicleCustomSecondaryColour(veh) SetVehicleColours(veh, select(1, GetVehicleColours(veh)), p.color2) end
    if p.pearlescentColor or p.wheelColor then
        local pe, wc = GetVehicleExtraColours(veh)
        SetVehicleExtraColours(veh, p.pearlescentColor or pe, p.wheelColor or wc)
    end
    if p.plateIndex then SetVehicleNumberPlateTextIndex(veh, p.plateIndex) end
    if p.windowTint then SetVehicleWindowTint(veh, p.windowTint) end
    if p.interiorColor then SetVehicleInteriorColor(veh, p.interiorColor) end
    if p.dashboardColor then SetVehicleDashboardColor(veh, p.dashboardColor) end
    if p.neonEnabled then for i = 1, 4 do SetVehicleNeonLightEnabled(veh, i - 1, p.neonEnabled[i] == true) end end
    if p.neonColor then SetVehicleNeonLightsColour(veh, p.neonColor[1], p.neonColor[2], p.neonColor[3]) end
    if p.tyreSmokeColor then SetVehicleTyreSmokeColor(veh, p.tyreSmokeColor[1], p.tyreSmokeColor[2], p.tyreSmokeColor[3]) end
    if p.extras then
        for id, on in pairs(p.extras) do
            local i = tonumber(id)
            if i and DoesExtraExist(veh, i) then SetVehicleExtra(veh, i, not on) end
        end
    end
    for t = 0, 48 do
        local v = p['mod' .. t]
        if v ~= nil then
            if t == 18 or t == 20 or t == 22 then
                ToggleVehicleMod(veh, t, v == true)
            elseif t ~= 17 and t ~= 19 and t ~= 21 and t ~= 47 then
                SetVehicleMod(veh, t, v, t == 23 and (p.modVariation == true) or false)
            end
        end
    end
    if p.xenonColor then SetVehicleXenonLightsColor(veh, p.xenonColor) end
    if p.livery and p.livery >= 0 then SetVehicleLivery(veh, p.livery) end
end

-- --------------------------------------------------------------------------
--  Pasek postępu (NUI) z animacją – blokujący, zwraca true/false
-- --------------------------------------------------------------------------
local progressActive = false
function DPM.Progress(label, ms, opts)
    if progressActive then return false end
    opts = opts or {}
    progressActive = true
    local ped = PlayerPedId()
    local prop
    if opts.anim then
        if opts.anim.scenario then
            TaskStartScenarioInPlace(ped, opts.anim.scenario, 0, true)
        else
            DPM.PlayAnim(ped, opts.anim.dict, opts.anim.clip, opts.anim.flag or 1)
        end
    end
    if opts.prop then prop = DPM.AttachProp(ped, opts.prop.model, opts.prop.bone, opts.prop.pos, opts.prop.rot) end
    DPM.Nui('progress', { label = label, time = ms })
    local finish = GetGameTimer() + ms
    local cancelled = false
    while GetGameTimer() < finish do
        Wait(0)
        DisableControlAction(0, 21, true) DisableControlAction(0, 24, true) DisableControlAction(0, 25, true)
        DisableControlAction(0, 30, true) DisableControlAction(0, 31, true) DisableControlAction(0, 22, true)
        if opts.canCancel ~= false and (IsControlJustPressed(0, 73) or IsControlJustPressed(0, 177)) then
            cancelled = true
            break
        end
        if IsEntityDead(ped) then cancelled = true break end
    end
    DPM.Nui('progressStop', { cancelled = cancelled })
    if opts.anim then ClearPedTasks(ped) end
    if prop then DPM.DeleteEntity(prop) end
    progressActive = false
    return not cancelled
end

-- --------------------------------------------------------------------------
--  Start
-- --------------------------------------------------------------------------
CreateThread(function()
    Wait(1000)
    if Config.UseTarget then
        if GetResourceState('ox_target') == 'started' then DPM.usingTarget = 'ox'
        elseif GetResourceState('qb-target') == 'started' then DPM.usingTarget = 'qb' end
    end
    local res = DPM.Callback('member:get')
    if res and res.ok then DPM.member = res.member end
    TriggerEvent('dp-mechanic:memberChanged', DPM.member)
end)

-- ponowne pobranie członkostwa po zmianie postaci / pracy
RegisterNetEvent('esx:setJob', function() CreateThread(function() local r = DPM.Callback('member:get') if r and r.ok then DPM.member = r.member TriggerEvent('dp-mechanic:memberChanged', DPM.member) end end) end)
RegisterNetEvent('QBCore:Client:OnJobUpdate', function() CreateThread(function() local r = DPM.Callback('member:get') if r and r.ok then DPM.member = r.member TriggerEvent('dp-mechanic:memberChanged', DPM.member) end end) end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
end)

if Config.Debug then
    RegisterCommand('dpm_pos', function()
        local ped = PlayerPedId()
        local c = GetEntityCoords(ped)
        local out = ('vec4(%.2f, %.2f, %.2f, %.1f)'):format(c.x, c.y, c.z, GetEntityHeading(ped))
        print(out)
        DPM.Notify(out, 'info', 10000)
    end, false)
    RegisterCommand('dpm_veh', function()
        local veh = DPM.GetClosestVehicle(nil, 6.0)
        if not veh then return end
        print(json.encode(DPM.EnsureVehData(veh) or {}, { indent = true }))
    end, false)
end
