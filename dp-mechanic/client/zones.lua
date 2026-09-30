-- ==========================================================================
--  dp-mechanic – strefy interakcji, blipy, punkt służby, propy stanowisk
--  DPM.Zones.Add(id, opts) / DPM.Zones.Remove(id)
--  ox_target / qb-target (gdy dostępne) albo własny system [E] z markerem.
-- ==========================================================================
DPM.Zones = {}

local zones = {}          -- [id] = { id, coords, radius, label, icon, distance, control, canInteract, onSelect, target = handle }
local SCAN_RADIUS = 25.0  -- promień zbierania stref w pobliżu (system własny)
local MARKER_EXTRA = 2.5  -- marker widoczny trochę wcześniej niż podpowiedź

local KEY_CONTROLS = { E = 38, G = 47, H = 74, F = 23, X = 73, Y = 246, K = 311 }

-- --------------------------------------------------------------------------
--  Tryb (target / własny) – liczony leniwie, zgodnie z rdzeniem
-- --------------------------------------------------------------------------
local function targetMode()
    if DPM.usingTarget then return DPM.usingTarget end
    if not Config.UseTarget then return false end
    if GetResourceState('ox_target') == 'started' then return 'ox' end
    if GetResourceState('qb-target') == 'started' then return 'qb' end
    return false
end

local function labelOf(z)
    if type(z.label) == 'function' then
        local ok, l = pcall(z.label)
        return ok and tostring(l or '') or ''
    end
    return z.label or ''
end

-- wspólne warunki interakcji (poza własnym canInteract strefy)
local function baseAllowed(z)
    local ped = PlayerPedId()
    if not z.inVehicle and IsPedInAnyVehicle(ped, false) then return false end
    if DPM.busy and not z.whileBusy then return false end
    if Hooks.CanInteract and not Hooks.CanInteract() then return false end
    return true
end

local function allowed(z)
    if not baseAllowed(z) then return false end
    if z.canInteract then
        local ok, res = pcall(z.canInteract)
        if not ok then
            DPM.Debug('strefa', z.id, 'canInteract błąd:', res)
            return false
        end
        return res == true
    end
    return true
end

local function fireSelect(z)
    CreateThread(function()
        local ok, err = pcall(z.onSelect)
        if not ok then print(('[dp-mechanic] strefa %s: %s'):format(tostring(z.id), tostring(err))) end
    end)
end

-- --------------------------------------------------------------------------
--  Rejestracja w systemach target
-- --------------------------------------------------------------------------
local function addTarget(z, mode)
    if mode == 'ox' then
        local ok, handle = pcall(function()
            return exports.ox_target:addSphereZone({
                coords = z.coords,
                radius = z.radius,
                debug = Config.Debug == true,
                drawSprite = true,
                options = {
                    {
                        name = 'dpm:' .. z.id,
                        icon = z.icon,
                        label = labelOf(z),
                        distance = z.distance,
                        canInteract = function() return allowed(z) end,
                        onSelect = function() fireSelect(z) end,
                    },
                },
            })
        end)
        if ok then z.target = handle return true end
        DPM.Debug('ox_target addSphereZone błąd', handle)
    elseif mode == 'qb' then
        local name = 'dpm:' .. z.id
        local ok, err = pcall(function()
            exports['qb-target']:AddCircleZone(name, z.coords, z.radius, {
                name = name,
                debugPoly = Config.Debug == true,
                useZ = true,
            }, {
                options = {
                    {
                        icon = z.icon,
                        label = labelOf(z),
                        canInteract = function() return allowed(z) end,
                        action = function() fireSelect(z) end,
                    },
                },
                distance = z.distance,
            })
        end)
        if ok then z.target = name return true end
        DPM.Debug('qb-target AddCircleZone błąd', err)
    end
    return false
end

local function removeTarget(z)
    if not z.target then return end
    local mode = z.targetMode
    if mode == 'ox' then
        pcall(function() exports.ox_target:removeZone(z.target) end)
    elseif mode == 'qb' then
        pcall(function() exports['qb-target']:RemoveZone(z.target) end)
    end
    z.target = nil
end

-- --------------------------------------------------------------------------
--  API
-- --------------------------------------------------------------------------
function DPM.Zones.Add(id, opts)
    if id == nil or type(opts) ~= 'table' or not opts.coords then return nil end
    if zones[id] then DPM.Zones.Remove(id) end
    local c = opts.coords
    local z = {
        id = id,
        coords = vec3(c.x, c.y, c.z),
        radius = tonumber(opts.radius) or 1.2,
        label = opts.label or 'Interakcja',
        icon = opts.icon or 'fas fa-wrench',
        distance = tonumber(opts.distance) or 2.0,
        control = KEY_CONTROLS[string.upper(tostring(opts.key or 'E'))] or 38,
        keyLabel = string.upper(tostring(opts.key or 'E')),
        canInteract = opts.canInteract,
        onSelect = opts.onSelect or function() end,
        inVehicle = opts.inVehicle == true,
        whileBusy = opts.whileBusy == true,
        marker = opts.marker ~= false,
    }
    local mode = targetMode()
    if mode and addTarget(z, mode) then z.targetMode = mode end
    zones[id] = z
    return id
end

function DPM.Zones.Remove(id)
    local z = zones[id]
    if not z then return end
    removeTarget(z)
    zones[id] = nil
end

function DPM.Zones.Exists(id) return zones[id] ~= nil end

-- --------------------------------------------------------------------------
--  System własny [E] – skan co 500 ms, pętla co klatkę tylko przy strefie
-- --------------------------------------------------------------------------
local nearby = {}          -- strefy w promieniu SCAN_RADIUS (bez target)

local function scan(pos)
    local n = 0
    for _, z in pairs(zones) do
        if not z.target then
            local d = #(pos - z.coords)
            if d <= SCAN_RADIUS then
                n = n + 1
                nearby[n] = z
            end
        end
    end
    for i = #nearby, n + 1, -1 do nearby[i] = nil end
    return n
end

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)
        local count = scan(pos)
        if count == 0 then
            Wait(1000)
        else
            -- najbliższa strefa w zasięgu markera?
            local best, bestD = nil, 1e9
            for i = 1, count do
                local z = nearby[i]
                local d = #(pos - z.coords)
                if d <= z.distance + MARKER_EXTRA and d < bestD then best, bestD = z, d end
            end
            if not best then
                Wait(500)
            else
                -- aktywne: co klatkę przez ~500 ms, potem ponowny skan
                local untilT = GetGameTimer() + 500
                local cached, cachedAt, cachedZone = false, 0, nil
                while GetGameTimer() < untilT do
                    ped = PlayerPedId()
                    pos = GetEntityCoords(ped)
                    local now = GetGameTimer()
                    local cur, curD = nil, 1e9
                    for i = 1, count do
                        local z = nearby[i]
                        if zones[z.id] == z then
                            local d = #(pos - z.coords)
                            if d <= z.distance + MARKER_EXTRA and d < curD then cur, curD = z, d end
                        end
                    end
                    if not cur then break end
                    -- canInteract co 250 ms (może być kosztowne)
                    if cachedZone ~= cur or now - cachedAt > 250 then
                        cached, cachedAt, cachedZone = allowed(cur), now, cur
                    end
                    if cached and not IsNuiFocused() and not IsPauseMenuActive() then
                        local inRange = curD <= cur.distance
                        if cur.marker then
                            local c = cur.coords
                            local a = inRange and 200 or 90
                            local bob = math.sin(now / 320.0) * 0.04
                            DrawMarker(20, c.x, c.y, c.z + 0.35 + bob, 0.0, 0.0, 0.0, 0.0, 180.0, 0.0,
                                0.22, 0.22, 0.18, 255, 122, 26, a, false, true, 2, false, nil, nil, false)
                        end
                        if inRange then
                            local key = cur.control == 38 and '~INPUT_CONTEXT~' or ('~b~' .. cur.keyLabel .. '~s~')
                            DPM.Help(key .. ' ' .. labelOf(cur))
                            if IsControlJustReleased(0, cur.control) then
                                cachedAt = 0
                                fireSelect(cur)
                                Wait(250)
                            end
                        end
                    end
                    Wait(0)
                end
            end
        end
    end
end)

-- --------------------------------------------------------------------------
--  Blipy warsztatów
-- --------------------------------------------------------------------------
local blips = {}

local function createBlips()
    for _, b in ipairs(blips) do if DoesBlipExist(b) then RemoveBlip(b) end end
    blips = {}
    for _, ws in pairs(Config.Workshops) do
        local b = ws.blip
        if b and b.coords then
            local blip = AddBlipForCoord(b.coords.x, b.coords.y, b.coords.z)
            SetBlipSprite(blip, b.sprite or 446)
            SetBlipColour(blip, b.color or 47)
            SetBlipScale(blip, b.scale or 0.85)
            SetBlipAsShortRange(blip, b.shortRange ~= false)
            SetBlipDisplay(blip, 4)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(b.label or ws.label or 'Warsztat')
            EndTextCommandSetBlipName(blip)
            blips[#blips + 1] = blip
        end
    end
end

-- --------------------------------------------------------------------------
--  Punkt służby (tylko członek danego warsztatu)
-- --------------------------------------------------------------------------
local dutyBusy = false

local function dutyLabel()
    if DPM.member and DPM.member.duty then return 'Zejdź ze służby' end
    return 'Wejdź na służbę'
end

local function registerDuty()
    for wsId, ws in pairs(Config.Workshops) do
        local id = 'duty:' .. wsId
        DPM.Zones.Remove(id)
        if ws.duty and DPM.member and DPM.member.workshop == wsId then
            DPM.Zones.Add(id, {
                coords = ws.duty,
                radius = 1.0,
                distance = 1.8,
                icon = 'fas fa-clipboard-user',
                label = targetMode() and dutyLabel() or dutyLabel,
                canInteract = function()
                    return not dutyBusy and DPM.member ~= nil and DPM.member.workshop == wsId
                end,
                onSelect = function()
                    if dutyBusy then return end
                    dutyBusy = true
                    local res = DPM.Callback('duty:toggle')
                    dutyBusy = false
                    if res and res.ok then
                        if DPM.member then DPM.member.duty = res.duty end
                        DPM.Notify(res.duty and ('Rozpoczynasz służbę – ' .. (ws.label or 'warsztat')) or 'Zakończyłeś służbę', res.duty and 'success' or 'info')
                        DPM.Sound(res.duty and 'success' or 'close')
                    else
                        DPM.Notify(res and res.err or 'Nie udało się zmienić służby', 'error')
                    end
                end,
            })
        end
    end
end

-- etykieta w ox/qb jest statyczna – odświeżamy strefę przy zmianie służby
local lastDuty, lastWs = nil, nil
AddEventHandler('dp-mechanic:memberChanged', function(member)
    local duty = member and member.duty or false
    local ws = member and member.workshop or nil
    if duty ~= lastDuty or ws ~= lastWs or not targetMode() then
        lastDuty, lastWs = duty, ws
        registerDuty()
    end
end)

-- --------------------------------------------------------------------------
--  Propy stanowisk (lokalne, niesieciowe, zamrożone)
-- --------------------------------------------------------------------------
local SPAWN_DIST, DESPAWN_DIST = 120.0, 150.0
local stations = {}       -- [wsId] = { spawned = bool, list = { { kind, idx, model, coords, heading, obj, placed } } }

local function stationList(ws)
    local m = Config.StationModels or {}
    local list = {}
    local function add(kind, idx, model, c, heading)
        if model and c then
            list[#list + 1] = { kind = kind, idx = idx, model = model, coords = vec3(c.x, c.y, c.z), heading = heading or 0.0 }
        end
    end
    for i, cab in ipairs(ws.cabinets or {}) do
        add('cabinet', i, m.cabinet, cab.coords, cab.coords.w)
    end
    if ws.tireChanger then add('tireChanger', 1, m.tireChanger, ws.tireChanger, ws.tireChanger.w) end
    if ws.balancer then add('balancer', 1, m.balancer, ws.balancer, ws.balancer.w) end
    for i, l in ipairs(ws.lifts or {}) do
        if l.panel then add('liftPanel', i, m.liftPanel, l.panel, (l.coords and l.coords.w or 0.0) + 90.0) end
    end
    return list
end

for wsId, ws in pairs(Config.Workshops) do
    stations[wsId] = { spawned = false, list = stationList(ws) }
end

-- podłoga pod punktem (Z z configu bywa wysokością gracza/punktu interakcji)
local function groundZ(c)
    local found, z = GetGroundZFor_3dCoord(c.x, c.y, c.z + 1.0, false)
    if found and z <= c.z + 1.0 and c.z - z < 2.0 then return z end
    return nil
end

local function spawnStation(st)
    for _, p in ipairs(st.list) do
        if not (p.obj and DoesEntityExist(p.obj)) then
            local hash = joaat(p.model)
            if IsModelInCdimage(hash) then
                local loaded = DPM.LoadModel(hash)
                if loaded then
                    local z = groundZ(p.coords) or p.coords.z
                    local obj = CreateObject(hash, p.coords.x, p.coords.y, z, false, false, false)
                    SetEntityHeading(obj, p.heading)
                    FreezeEntityPosition(obj, true)
                    SetEntityInvincible(obj, true)
                    SetEntityAsMissionEntity(obj, true, true)
                    SetModelAsNoLongerNeeded(hash)
                    p.obj, p.placed = obj, false
                end
            else
                DPM.Debug('brak modelu stanowiska w grze:', p.model)
            end
        end
    end
    st.spawned = true
end

local function despawnStation(st)
    for _, p in ipairs(st.list) do
        if p.obj then DPM.DeleteEntity(p.obj) end
        p.obj, p.placed = nil, false
    end
    st.spawned = false
end

CreateThread(function()
    Wait(500)
    createBlips()
    while true do
        local pos = GetEntityCoords(PlayerPedId())
        local minD = 1e9
        for wsId, st in pairs(stations) do
            local ws = Config.Workshops[wsId]
            local d = #(pos - ws.zone.center)
            if d < minD then minD = d end
            if not st.spawned and d <= SPAWN_DIST then
                spawnStation(st)
            elseif st.spawned and d > DESPAWN_DIST then
                despawnStation(st)
            elseif st.spawned and d <= 70.0 then
                -- dociśnięcie do podłogi, gdy kolizja już się wczytała
                for _, p in ipairs(st.list) do
                    if p.obj and not p.placed and DoesEntityExist(p.obj) and HasCollisionLoadedAroundEntity(p.obj) then
                        FreezeEntityPosition(p.obj, false)
                        p.placed = PlaceObjectOnGroundProperly(p.obj)
                        SetEntityHeading(p.obj, p.heading)
                        FreezeEntityPosition(p.obj, true)
                    end
                end
            end
        end
        Wait(minD < DESPAWN_DIST + 30.0 and 1500 or 4000)
    end
end)

-- encja propa stanowiska (np. do kamery na maszynę) lub nil
function DPM.Zones.StationProp(wsId, kind, idx)
    local st = stations[wsId]
    if not st then return nil end
    for _, p in ipairs(st.list) do
        if p.kind == kind and p.idx == (idx or 1) and p.obj and DoesEntityExist(p.obj) then return p.obj end
    end
    return nil
end

-- --------------------------------------------------------------------------
--  Sprzątanie
-- --------------------------------------------------------------------------
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, st in pairs(stations) do despawnStation(st) end
    for _, b in ipairs(blips) do if DoesBlipExist(b) then RemoveBlip(b) end end
    for id in pairs(zones) do
        local z = zones[id]
        if z then removeTarget(z) end
    end
    zones = {}
end)
