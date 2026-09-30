-- ==========================================================================
--  Ulica: zlecenia kradzieży (auto-cel, wytrych, wybicie szyby, alarm,
--  nadajnik GPS + skaner), dostawy zamówień, eksport w porcie, handlarz
-- ==========================================================================
local D = Dz
local contract, cBlips = nil, {}
local order, oBlip = nil, nil
local exportJob, eBlip = nil, nil
local clean, dealerBlip, dealerPed = {}, nil, nil
local lp, scan = nil, nil

local function clearContractBlips()
    for _, b in pairs(cBlips) do D.RemoveBlip(b) end
    cBlips = {}
end

local function vehFromNet(net)
    if not net or not NetworkDoesNetworkIdExist(net) then return nil end
    local veh = NetToVeh(net)
    if veh == 0 or not DoesEntityExist(veh) then return nil end
    return veh
end

-- --------------------------------------------------------------------------
--  Alarm
-- --------------------------------------------------------------------------
local function alarm(veh, plate)
    if D.Control(veh) then
        SetVehicleAlarm(veh, true)
        SetVehicleAlarmTimeLeft(veh, 30000)
        StartVehicleAlarm(veh)
    end
    D.Notify(L('alarm'), 'bad')
    Hooks.Dispatch('alarm', GetEntityCoords(veh), { plate = plate, model = contract and contract.label })
end

-- --------------------------------------------------------------------------
--  Wytrych (minigra NUI)
-- --------------------------------------------------------------------------
local function doLockpick(veh, net)
    D.busy = true
    local r = D.Callback('lockpickBegin', net)
    if not r or not r.ok then
        D.busy = false
        return D.Notify(r and r.msg or L('error'), 'bad')
    end
    local ped = PlayerPedId()
    TaskTurnPedToFaceEntity(ped, veh, 800)
    Wait(800)
    D.PlayAnim(Config.Anim.lockpick, 1)
    lp = { token = r.token, net = net, veh = veh }
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'lockpickOpen', spec = r.spec })
end

RegisterNUICallback('lockpick', function(data, cb)
    if not lp then return cb({ ok = false }) end
    local cur = lp
    lp = nil
    CreateThread(function()
        local r = D.Callback('lockpickFinish', cur.token, data.success == true, tonumber(data.broke) or 0)
        SetNuiFocus(false, false)
        ClearPedTasks(PlayerPedId())
        D.busy = false
        if r and r.ok then
            if r.success then
                if D.Control(cur.veh) then SetVehicleDoorsLocked(cur.veh, 1) end
                D.Notify(r.msg, 'good')
            elseif r.msg then
                D.Notify(r.msg, 'bad')
            end
            if r.alarm then alarm(cur.veh, r.plate) end
        elseif r and r.msg then
            D.Notify(r.msg, 'bad')
        end
        cb({ ok = true })
    end)
end)

local function doSmash(veh, net)
    D.busy = true
    local ped = PlayerPedId()
    TaskTurnPedToFaceEntity(ped, veh, 700)
    Wait(700)
    D.PlayAnim(Config.Anim.smash, 0)
    Wait(700)
    local r = D.Callback('smash', net)
    if r and r.ok then
        if D.Control(veh) then
            SmashVehicleWindow(veh, 0)
            SetVehicleDoorsLocked(veh, 1)
        end
        if r.alarm then alarm(veh, r.plate) end
    end
    ClearPedTasks(ped)
    D.busy = false
end

-- --------------------------------------------------------------------------
--  Skaner nadajnika GPS (minigra NUI)
-- --------------------------------------------------------------------------
local function doScan(veh)
    if D.busy then return end
    local net = NetworkGetNetworkIdFromEntity(veh)
    D.busy = true
    local r = D.Callback('scanBegin', net)
    if not r or not r.ok then
        D.busy = false
        return D.Notify(r and r.msg or L('error'), 'bad')
    end
    D.PlayAnim(Config.Anim.scan, 49)
    scan = { token = r.token, net = net }
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'scannerOpen', spec = r.spec })
end

RegisterNUICallback('scanner', function(data, cb)
    if not scan then return cb({ ok = false }) end
    local cur = scan
    scan = nil
    CreateThread(function()
        local r = D.Callback('scanFinish', cur.token, data.found == true)
        SetNuiFocus(false, false)
        ClearPedTasks(PlayerPedId())
        D.busy = false
        if r and r.msg then D.Notify(r.msg, r.removed and 'good' or 'info') end
        if data.alert then
            local veh = vehFromNet(cur.net)
            if veh then Hooks.Dispatch('tracker', GetEntityCoords(veh), {}) end
        end
        cb({ ok = true })
    end)
end)

RegisterCommand('skaner', function()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return end
    local pc = GetEntityCoords(ped)
    local best, bd
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        local d = #(GetEntityCoords(veh) - pc)
        if d < 4.0 and (not bd or d < bd) then best, bd = veh, d end
    end
    if best then doScan(best) end
end, false)

-- --------------------------------------------------------------------------
--  Zlecenie kradzieży
-- --------------------------------------------------------------------------
local function setContract(data)
    clearContractBlips()
    contract = data
    if not data then return end
    local a = data.area
    local r = AddBlipForRadius(a.x, a.y, a.z, data.radius + 0.0)
    SetBlipColour(r, Config.Blips.contractArea.color)
    SetBlipAlpha(r, Config.Blips.contractArea.alpha)
    cBlips.area = r
    cBlips.route = D.Blip(a, { sprite = Config.Blips.contractArea.sprite, color = 1, scale = 0.7 }, 'Zlecenie: ' .. (data.label or 'auto'), true)
    contract.keys = false
    contract.warned = false
end

RegisterNetEvent('dp-dziupla:client:contract', setContract)

-- zlecenie: spawn auta, gdy gracz podjedzie, i blip na samym aucie
CreateThread(function()
    while true do
        local sleep = 1500
        if contract and not D.busy then
            local pc = GetEntityCoords(PlayerPedId())
            if not contract.net then
                local sp = contract.spot
                if #(pc.xy - vector2(sp.x, sp.y)) < Config.Contracts.spawnDistance then
                    local r = D.Callback('contractSpawn', D.GroundZ(vector3(sp.x, sp.y, sp.z)))
                    if r and r.ok then
                        contract.net, contract.plate = r.net, r.plate
                        D.Notify(r.msg, 'info', 8000)
                    end
                    sleep = 3000
                end
            else
                local veh = vehFromNet(contract.net)
                if veh and not cBlips.car then
                    local b = AddBlipForEntity(veh)
                    SetBlipSprite(b, Config.Blips.contractCar.sprite)
                    SetBlipColour(b, Config.Blips.contractCar.color)
                    SetBlipScale(b, Config.Blips.contractCar.scale)
                    cBlips.car = b
                    cBlips.route = D.RemoveBlip(cBlips.route)
                end
            end
        end
        Wait(sleep)
    end
end)

-- auta-cele w pobliżu (zlecenia i auta „na mieście” – wszystkie mają statebag dpTarget)
local nearTargets = {}
local keysGiven, trackerWarned = {}, {}

CreateThread(function()
    while true do
        local list = {}
        local pc = GetEntityCoords(PlayerPedId())
        for _, veh in ipairs(GetGamePool('CVehicle')) do
            if #(GetEntityCoords(veh) - pc) < 25.0 and Entity(veh).state.dpTarget then list[#list + 1] = veh end
        end
        nearTargets = list
        Wait(1000)
    end
end)

CreateThread(function()
    while true do
        local sleep = 800
        if #nearTargets > 0 and not D.busy then
            local ped = PlayerPedId()
            local pc = GetEntityCoords(ped)
            local cur = GetVehiclePedIsIn(ped, false)
            for _, veh in ipairs(nearTargets) do
                if DoesEntityExist(veh) then
                    local st = Entity(veh).state.dpTarget
                    if st then
                        local net = NetworkGetNetworkIdFromEntity(veh)
                        if cur == veh then
                            if GetPedInVehicleSeat(veh, -1) == ped and not keysGiven[net] and not st.locked then
                                keysGiven[net] = true
                                Hooks.GiveKeys(veh, GetVehicleNumberPlateText(veh))
                            end
                            if st.tracker and not trackerWarned[net] then
                                trackerWarned[net] = true
                                D.Notify(L('tracker_active'), 'bad', 9000)
                            end
                        elseif cur == 0 then
                            local dist = #(pc - GetEntityCoords(veh))
                            -- kradzież części na miejscu (H), gdy auto nie jest jeszcze „rozgrzebane”
                            if Config.StreetStrip.enabled and dist < 3.2 and not Entity(veh).state.dpChop and not Entity(veh).state.dpTowed then
                                sleep = 0
                                if not st.locked then D.Help(L('help_strip')) end
                                if IsControlJustReleased(0, 74) then CreateThread(function() D.StartStrip(veh, net) end) end
                            end
                            if st.locked then
                                local bi = GetEntityBoneIndexByName(veh, 'door_dside_f')
                                local door = bi ~= -1 and GetWorldPositionOfEntityBone(veh, bi) or GetEntityCoords(veh)
                                if #(pc - door) < 1.8 then
                                    sleep = 0
                                    D.Help(L('help_lockpick') .. '~n~' .. L('help_strip'))
                                    if IsControlJustReleased(0, 38) then CreateThread(function() doLockpick(veh, net) end) end
                                    if IsControlJustReleased(0, 47) then CreateThread(function() doSmash(veh, net) end) end
                                end
                            elseif st.tracker ~= false and dist < 3.0 then
                                sleep = 0
                                D.Help(L('help_scan'))
                                if IsControlJustReleased(0, 38) then CreateThread(function() doScan(veh) end) end
                            end
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

-- kradzież części na ulicy: tworzy lekkie „stanowisko” w miejscu auta
function D.StartStrip(veh, net)
    if D.busy or D.carrying then return end
    D.busy = true
    local r = D.Callback('streetStrip', net, D.Snapshot(veh))
    D.busy = false
    if not r or not r.ok then return D.Notify(r and r.msg or L('error'), 'bad') end
    D.Notify(r.msg, 'warn', 8000)
    if r.alarm then alarm(veh, r.plate) end
end

-- cynk kupiony w ChopNecie: obszar na mapie na 10 minut
local tipBlips = {}
RegisterNetEvent('dp-dziupla:client:tip', function(t)
    local r = AddBlipForRadius(t.x, t.y, t.z, 110.0)
    SetBlipColour(r, 5)
    SetBlipAlpha(r, 90)
    local b = D.Blip(vector3(t.x, t.y, t.z), { sprite = 225, color = 5, scale = 0.7 }, 'Cynk: ' .. t.label, false)
    SetNewWaypoint(t.x, t.y)
    tipBlips[#tipBlips + 1] = r
    tipBlips[#tipBlips + 1] = b
    SetTimeout(600000, function()
        D.RemoveBlip(r)
        D.RemoveBlip(b)
    end)
end)

-- --------------------------------------------------------------------------
--  Zamówienie – dostawa paczki
-- --------------------------------------------------------------------------
RegisterNetEvent('dp-dziupla:client:order', function(data)
    oBlip = D.RemoveBlip(oBlip)
    order = data
    if data then oBlip = D.Blip(data.drop, Config.Blips.drop, 'Odbiór: ' .. data.client, true) end
end)

local function deliverOrder()
    D.busy = true
    local ped = PlayerPedId()
    local hash = D.LoadModel('prop_cs_cardbox_01')
    local box
    if hash then
        box = CreateObject(hash, 0.0, 0.0, 0.0, true, true, false)
        AttachEntityToEntity(box, ped, GetPedBoneIndex(ped, 60309), 0.025, 0.08, 0.255, -145.0, 290.0, 0.0, true, true, false, true, 1, true)
    end
    D.PlayAnim(Config.Anim.drop, 0)
    Wait(1200)
    if box then
        DetachEntity(box, true, true)
        PlaceObjectOnGroundProperly(box)
        SetTimeout(20000, function() if DoesEntityExist(box) then DeleteEntity(box) end end)
    end
    local r = D.Callback('orderDeliver')
    ClearPedTasks(ped)
    D.busy = false
    if r and r.msg then D.Notify(r.msg, r.ok and 'good' or 'bad') end
end

-- --------------------------------------------------------------------------
--  Eksport
-- --------------------------------------------------------------------------
RegisterNetEvent('dp-dziupla:client:export', function(data)
    eBlip = D.RemoveBlip(eBlip)
    exportJob = data
    if data then eBlip = D.Blip(data.point, Config.Blips.export, 'Eksport: ' .. data.label, true) end
end)

local function deliverExport(veh)
    D.busy = true
    local snap = D.Snapshot(veh)
    local r = D.Callback('exportDeliver', NetworkGetNetworkIdFromEntity(veh), snap)
    if r and r.ok then
        local ped = PlayerPedId()
        TaskLeaveVehicle(ped, veh, 0)
        D.Notify(r.msg, 'good', 7000)
    elseif r and r.msg then
        D.Notify(r.msg, 'bad')
    end
    D.busy = false
end

-- --------------------------------------------------------------------------
--  Handlarz „czystych” aut
-- --------------------------------------------------------------------------
function D.SetCleanCar(net)
    clean[net] = true
    dealerBlip = D.RemoveBlip(dealerBlip)
    dealerBlip = D.Blip(Config.Revin.dealer, Config.Blips.dealer, 'Handlarz autami', true)
end

local function dealerCar()
    local d = Config.Revin.dealer
    for net in pairs(clean) do
        local veh = vehFromNet(net)
        if veh and #(GetEntityCoords(veh).xy - d.xy) < 14.0 then return veh, net end
    end
end

local function dealerAction(keep)
    local veh, net = dealerCar()
    if not veh then return end
    D.busy = true
    local r
    if keep then
        r = D.Callback('revinKeep', net, Hooks.GetVehicleProps(veh))
        if r and r.ok then Hooks.GiveKeys(veh, r.plate) end
    else
        r = D.Callback('revinSell', net)
    end
    if r and r.ok then
        clean[net] = nil
        if not next(clean) then dealerBlip = D.RemoveBlip(dealerBlip) end
    end
    if r and r.msg then D.Notify(r.msg, (r.ok and not r.refused) and 'good' or 'bad', 7000) end
    D.busy = false
end

-- --------------------------------------------------------------------------
--  Pętla: dostawy, eksport, handlarz
-- --------------------------------------------------------------------------
CreateThread(function()
    while true do
        local sleep = 1500
        local ped = PlayerPedId()
        local pc = GetEntityCoords(ped)
        if not D.busy then
            if order then
                local d = #(pc - vector3(order.drop.x, order.drop.y, order.drop.z))
                if d < 25.0 then
                    sleep = 0
                    DrawMarker(2, order.drop.x, order.drop.y, order.drop.z + 0.3, 0, 0, 0, 180.0, 0, 0, 0.3, 0.3, 0.3, 255, 200, 40, 170, true, true, 2, false, nil, nil, false)
                    if d < 2.0 and not IsPedInAnyVehicle(ped, false) then
                        D.Help(L('help_drop'))
                        if IsControlJustReleased(0, 38) then CreateThread(deliverOrder) end
                    end
                end
            end
            if exportJob then
                local p = exportJob.point
                local d = #(pc - vector3(p.x, p.y, p.z))
                if d < 40.0 then
                    sleep = 0
                    DrawMarker(1, p.x, p.y, p.z - 1.0, 0, 0, 0, 0, 0, 0, 5.0, 5.0, 0.8, 80, 170, 255, 80, false, false, 2, false, nil, nil, false)
                    local veh = GetVehiclePedIsIn(ped, false)
                    if d < 7.0 and veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
                        D.Help(L('help_export'))
                        if IsControlJustReleased(0, 38) then CreateThread(function() deliverExport(veh) end) end
                    end
                end
            end
            if next(clean) then
                local dl = Config.Revin.dealer
                local d = #(pc - dl.xyz)
                if d < 60.0 and not dealerPed then
                    dealerPed = D.SpawnPed(Config.Revin.dealerPed, dl, 'WORLD_HUMAN_CLIPBOARD')
                elseif d > 80.0 and dealerPed then
                    if DoesEntityExist(dealerPed) then DeleteEntity(dealerPed) end
                    dealerPed = nil
                end
                if d < 3.0 and not IsPedInAnyVehicle(ped, false) and dealerCar() then
                    sleep = 0
                    D.Help(Config.Revin.allowKeep and L('help_dealer_keep') or L('help_dealer'))
                    if IsControlJustReleased(0, 38) then CreateThread(function() dealerAction(false) end) end
                    if Config.Revin.allowKeep and IsControlJustReleased(0, 47) then CreateThread(function() dealerAction(true) end) end
                end
            elseif dealerPed then
                if DoesEntityExist(dealerPed) then DeleteEntity(dealerPed) end
                dealerPed = nil
            end
        end
        Wait(sleep)
    end
end)

-- przywrócenie stanu po restarcie zasobu / reconnect
CreateThread(function()
    Wait(3000)
    local r = D.Callback('streetState')
    if not r then return end
    if r.contract then
        setContract(r.contract)
        contract.net, contract.plate = r.contract.net, r.contract.plate
    end
    if r.order then TriggerEvent('dp-dziupla:client:order', r.order) end
    if r.export then TriggerEvent('dp-dziupla:client:export', r.export) end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearContractBlips()
    D.RemoveBlip(oBlip)
    D.RemoveBlip(eBlip)
    D.RemoveBlip(dealerBlip)
    for _, b in ipairs(tipBlips) do D.RemoveBlip(b) end
    if dealerPed and DoesEntityExist(dealerPed) then DeleteEntity(dealerPed) end
    if lp or scan then SetNuiFocus(false, false) end
end)
