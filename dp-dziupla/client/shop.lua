-- ==========================================================================
--  Dziupla: lokacje, paser, laptop ChopNet, regał, stół warsztatowy,
--  montażownica, brama, wjazd na stanowisko / przebitkę, zgniatarka
-- ==========================================================================
local D = Dz
local peds = {}
local gzCache = {}

-- Z gruntu pod punktem (liczone raz, nie co klatkę)
local function gz(v)
    local k = ('%.1f_%.1f'):format(v.x, v.y)
    if not gzCache[k] then gzCache[k] = D.GroundZ(vector3(v.x, v.y, v.z)) end
    return gzCache[k]
end

-- --------------------------------------------------------------------------
--  Blipy i wykrywanie najbliższej dziupli
-- --------------------------------------------------------------------------
CreateThread(function()
    for _, s in ipairs(Config.Shops) do
        if s.blip and s.blip.show then
            local b = AddBlipForCoord(s.center.x, s.center.y, s.center.z)
            SetBlipSprite(b, s.blip.sprite)
            SetBlipColour(b, s.blip.color)
            SetBlipScale(b, s.blip.scale)
            SetBlipAsShortRange(b, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(s.label)
            EndTextCommandSetBlipName(b)
        end
    end
    while true do
        local pc = GetEntityCoords(PlayerPedId())
        local near
        for _, s in ipairs(Config.Shops) do
            if #(pc - s.center) < s.radius then near = s end
        end
        if near ~= D.shop then
            if D.shop and peds[D.shop.key] then
                if DoesEntityExist(peds[D.shop.key]) then DeleteEntity(peds[D.shop.key]) end
                peds[D.shop.key] = nil
            end
            D.shop = near
            if near and near.fence then
                local ped = D.SpawnPed(near.fencePed or 'g_m_m_armboss_01', near.fence, 'WORLD_HUMAN_SMOKING')
                peds[near.key] = ped
                if ped and D.usingTarget then
                    D.TargetPed(ped, 'dp_dziupla_fence', 'fa-solid fa-user-secret', L('target_fence'), function() D.OpenLaptop('warehouse') end)
                end
            end
        end
        Wait(1000)
    end
end)

-- --------------------------------------------------------------------------
--  Laptop ChopNet
-- --------------------------------------------------------------------------
local function zoneLabel(v)
    local z = GetNameOfZone(v.x, v.y, v.z)
    local l = GetLabelText(z)
    if not l or l == 'NULL' then return z end
    return l
end

local function decorate(data)
    if data.contracts then
        for _, c in ipairs(data.contracts.offers or {}) do
            if c.area then c.zone = zoneLabel(c.area) end
            c.label = GetLabelText(GetDisplayNameFromVehicleModel(joaat(c.model))) ~= 'NULL' and GetLabelText(GetDisplayNameFromVehicleModel(joaat(c.model))) or c.label
        end
        local a = data.contracts.active
        if a then
            a.zone = zoneLabel(a.area)
            local l = GetLabelText(GetDisplayNameFromVehicleModel(joaat(a.model)))
            if l and l ~= 'NULL' then a.label = l end
        end
    end
    return data
end

function D.OpenLaptop(tab)
    if D.busy or D.carrying then return end
    local r = D.Callback('overview')
    if not r or not r.ok then return D.Notify(r and r.msg or L('error'), 'bad') end
    D.busy = true
    D.laptop = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'laptopOpen', data = decorate(r.data), tab = tab })
end

local function closeLaptop()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'laptopClose' })
    D.busy = false
    D.laptop = false
end

local LaptopActions = {
    buy = 'buy', perk = 'perk', perkReset = 'perkReset', sell = 'sell', scrap = 'scrap',
    contractAccept = 'contractAccept', contractCancel = 'contractCancel',
    orderAccept = 'orderAccept', orderCancel = 'orderCancel',
    exportAccept = 'exportAccept', exportCancel = 'exportCancel',
}

RegisterNUICallback('laptop', function(data, cb)
    local a = data and data.action
    if a == 'close' then
        closeLaptop()
        return cb({ ok = true })
    end
    CreateThread(function()
        if a == 'refresh' then
            local r = D.Callback('overview')
            if r and r.data then decorate(r.data) end
            return cb(r or { ok = false })
        elseif a == 'waypoint' and data.x and data.y then
            SetNewWaypoint(data.x + 0.0, data.y + 0.0)
            return cb({ ok = true, msg = 'Zaznaczono na GPS.' })
        end
        local name = LaptopActions[a]
        if not name then return cb({ ok = false }) end
        local r = D.Callback(name, data.arg, data.arg2)
        if r and r.data then decorate(r.data) end
        cb(r or { ok = false, msg = L('error') })
    end)
end)

RegisterCommand('chopnet', function()
    if D.shop then D.OpenLaptop() end
end, false)

-- --------------------------------------------------------------------------
--  Stół warsztatowy / montażownica
-- --------------------------------------------------------------------------
local bench

local function openBench(mode)
    if D.busy or D.carrying then return end
    local r = D.Callback('benchList', mode)
    if not r or not r.ok then return end
    if #r.items == 0 then return D.Notify(L('bench_none'), 'warn') end
    D.busy = true
    bench = { mode = mode }
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'benchPick', mode = mode, items = r.items })
end

local function closeBench()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'benchClose' })
    ClearPedTasks(PlayerPedId())
    bench = nil
    D.busy = false
end

RegisterNUICallback('bench', function(data, cb)
    if not bench then return cb({ ok = false }) end
    local a = data.action
    CreateThread(function()
        if a == 'pick' then
            local r = D.Callback('benchBegin', tonumber(data.uid), bench.mode)
            if not r or not r.ok then
                D.Notify(r and r.msg or L('error'), 'bad')
                return cb({ ok = false })
            end
            bench.token = r.token
            D.PlayAnim(Config.Anim.bench, 1)
            SendNUIMessage({ action = 'benchOpen', spec = r.spec })
            cb({ ok = true })
        elseif a == 'finish' then
            local r = D.Callback('benchFinish', bench.token, tonumber(data.score) or 0)
            closeBench()
            if r and r.msg then D.Notify(r.msg, r.ok and 'good' or 'bad', 6000) end
            cb(r or { ok = false })
        else
            if bench.token then D.Callback('benchAbort', bench.token) end
            closeBench()
            cb({ ok = true })
        end
    end)
end)

-- --------------------------------------------------------------------------
--  Wjazd na stanowisko / przebitkę / zgniatarkę
-- --------------------------------------------------------------------------
local function leaveVehicle(veh)
    local ped = PlayerPedId()
    TaskLeaveVehicle(ped, veh, 0)
    local t = GetGameTimer() + 4000
    while IsPedInAnyVehicle(ped, false) and GetGameTimer() < t do Wait(50) end
    Wait(400)
end

local function startBay(veh, cbName)
    D.busy = true
    SetVehicleEngineOn(veh, false, true, true)
    local snap = D.Snapshot(veh)
    if not NetworkGetEntityIsNetworked(veh) then NetworkRegisterEntityAsNetworked(veh) end
    local net = NetworkGetNetworkIdFromEntity(veh)
    leaveVehicle(veh)
    local r = D.Callback(cbName, net, snap)
    D.busy = false
    if r and r.ok then
        if r.msg then D.Notify(r.msg, 'good', 9000) end
    else
        D.Notify(r and r.msg or L('error'), 'bad')
    end
end

local function crushAnim(veh, ms)
    CreateThread(function()
        local t0 = GetGameTimer()
        local base = GetEntityCoords(veh)
        D.Control(veh)
        while GetGameTimer() - t0 < ms and DoesEntityExist(veh) do
            local k = (GetGameTimer() - t0) / ms
            if math.random() < 0.25 then
                SetVehicleDamage(veh, math.random(-10, 10) / 10, math.random(-20, 20) / 10, 0.6, 400.0, 150.0, true)
            end
            SetEntityCoordsNoOffset(veh, base.x, base.y, base.z - 0.6 * k, false, false, false)
            if math.random() < 0.08 then
                SmashVehicleWindow(veh, math.random(0, 7))
            end
            Wait(100)
        end
    end)
end

local function startCrush(veh)
    D.busy = true
    local snap = D.Snapshot(veh)
    local net = NetworkGetNetworkIdFromEntity(veh)
    leaveVehicle(veh)
    local r = D.Callback('crush', net, snap)
    D.busy = false
    if r and r.ok then
        crushAnim(veh, r.time or Config.Crusher.time)
    else
        D.Notify(r and r.msg or L('error'), 'bad')
    end
end

-- --------------------------------------------------------------------------
--  Pętla interakcji w dziupli
-- --------------------------------------------------------------------------
CreateThread(function()
    while true do
        local sleep = 1000
        local s = D.shop
        if s and not D.busy then
            sleep = 400
            local ped = PlayerPedId()
            local pc = GetEntityCoords(ped)
            local veh = GetVehiclePedIsIn(ped, false)
            local inVeh = veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped

            if inVeh then
                local vc = GetEntityCoords(veh)
                local busyVeh = Entity(veh).state.dpChop ~= nil
                local nearBay
                for _, b in ipairs(s.bays) do
                    if #(vc.xy - b.xy) < Config.Bay.radius + 4.0 then
                        sleep = 0
                        DrawMarker(1, b.x, b.y, gz(b) + 0.02, 0, 0, 0, 0, 0, 0, Config.Bay.radius * 2, Config.Bay.radius * 2, 0.6, 255, 176, 32, 60, false, false, 2, false, nil, nil, false)
                        if #(vc.xy - b.xy) < Config.Bay.radius then nearBay = 'chop' end
                    end
                end
                if s.vinBay and #(vc.xy - s.vinBay.xy) < Config.Bay.radius + 4.0 then
                    sleep = 0
                    local b = s.vinBay
                    DrawMarker(1, b.x, b.y, gz(b) + 0.02, 0, 0, 0, 0, 0, 0, Config.Bay.radius * 2, Config.Bay.radius * 2, 0.6, 80, 170, 255, 60, false, false, 2, false, nil, nil, false)
                    if #(vc.xy - b.xy) < Config.Bay.radius then nearBay = 'revin' end
                end
                local nearCrusher = s.crusher and #(vc - s.crusher) < 5.0
                if s.crusher and #(vc - s.crusher) < 14.0 then
                    sleep = 0
                    DrawMarker(1, s.crusher.x, s.crusher.y, gz(s.crusher) + 0.02, 0, 0, 0, 0, 0, 0, 5.0, 5.0, 0.6, 255, 70, 70, 60, false, false, 2, false, nil, nil, false)
                end
                if not busyVeh then
                    if nearBay == 'chop' then
                        D.Help(L('help_bay'))
                        if IsControlJustReleased(0, 38) then startBay(veh, 'chopStart') end
                    elseif nearBay == 'revin' then
                        D.Help(L('help_vinbay'))
                        if IsControlJustReleased(0, 38) then startBay(veh, 'revinStart') end
                    elseif nearCrusher then
                        D.Help(L('help_crusher'))
                        if IsControlJustReleased(0, 38) then startCrush(veh) end
                    end
                end
            elseif not IsPedInAnyVehicle(ped, false) and not D.carrying then
                local points = {
                    { v = s.laptop, r = 1.6, help = L('help_laptop'), fn = function() D.OpenLaptop() end },
                    { v = s.bench, r = 1.6, help = L('help_bench'), fn = function() openBench('bench') end },
                    { v = s.tyre, r = 1.6, help = L('help_tyre'), fn = function() openBench('split') end },
                    { v = s.gate, r = 1.4, help = L('help_gate', GlobalState['dpGate_' .. s.key] and 'Otwórz' or 'Zamknij'), fn = function()
                        local r = D.Callback('gate', s.key)
                        if r and r.msg then D.Notify(r.msg, r.closed and 'good' or 'warn') end
                    end },
                }
                if s.fence and not D.usingTarget then
                    points[#points + 1] = { v = s.fence, r = 1.8, help = L('help_fence'), fn = function() D.OpenLaptop('warehouse') end }
                end
                for _, p in ipairs(points) do
                    if p.v then
                        local d = #(pc - p.v.xyz)
                        if d < 8.0 then
                            sleep = 0
                            DrawMarker(20, p.v.x, p.v.y, p.v.z + 0.1, 0, 0, 0, 0, 0, 0, 0.25, 0.25, 0.2, 255, 176, 32, 150, true, true, 2, false, nil, nil, false)
                        end
                        if d < p.r then
                            D.Help(p.help)
                            if IsControlJustReleased(0, 38) then CreateThread(p.fn) end
                        end
                    end
                end
            elseif D.carrying then
                -- znacznik regału przy noszeniu
                local sh = s.shelf
                if #(pc - sh) < 25.0 then
                    sleep = 0
                    DrawMarker(2, sh.x, sh.y, sh.z + 0.4, 0, 0, 0, 180.0, 0, 0, 0.3, 0.3, 0.3, 60, 220, 130, 170, true, true, 2, false, nil, nil, false)
                end
            end
        end
        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, p in pairs(peds) do
        if DoesEntityExist(p) then DeleteEntity(p) end
    end
    if D.laptop or bench then SetNuiFocus(false, false) end
end)
