-- ==========================================================================
--  dp-doorlock – rejestr drzwi, siatka przestrzenna, stan i znaczniki w świecie
--
--  Wydajność:
--   • drzwi trafiają do siatki (komórki Config.Perf.gridSize); wolna pętla co
--     Config.Perf.scanInterval ms przegląda tylko 9 komórek wokół gracza,
--   • szybka pętla (co klatkę) działa wyłącznie, gdy jakieś drzwi są w zasięgu
--     UI – inaczej śpi Config.Perf.idleSleep ms,
--   • widoczność (ściany) sprawdzana asynchronicznym raycastem w wolnej pętli,
--   • do NUI wysyłamy pozycje tylko po realnej zmianie (> chipEpsilon).
-- ==========================================================================
Doors = {}           -- [id] = { def, st, hashes, pos, ui, cell, autoEnd, vis, probe }
local grid = {}      -- [klucz komórki] = { [id] = true }
local near = {}      -- id drzwi w zasięgu UI (lista, z wolnej pętli)
local nearSet = {}   -- [id] = true (dla szybkiego sprawdzania)
local ready = false

local G = Config.Perf.gridSize
local DRAW = Config.UI.drawDistance
local EPS = Config.Perf.chipEpsilon
local MAX_CHIPS = Config.UI.maxChips or 6

local function cellKey(x, y)
    return (math.floor(x / G) + 4096) * 8192 + (math.floor(y / G) + 4096)
end

-- --------------------------------------------------------------------------
--  Rejestracja w systemie drzwi GTA
-- --------------------------------------------------------------------------
local function applyState(door)
    local st = door.st or {}
    local locked = (st.l and not st.b) and 1 or 0
    for _, h in ipairs(door.hashes) do
        DoorSystemSetDoorState(h, locked, false, false)
    end
end

local function register(def, st)
    local door = { def = def, st = st or { l = true }, hashes = {} }
    local gate = def.type == 'sliding' or def.type == 'garage'
    for i, leaf in ipairs(def.doors) do
        local h = joaat(('dpdl:%d:%d'):format(def.id, i))
        if not IsDoorRegisteredWithSystem(h) then
            AddDoorToSystem(h, leaf.model, leaf.coords.x, leaf.coords.y, leaf.coords.z, false, false, false)
        end
        if gate then
            DoorSystemSetAutomaticDistance(h, math.max(def.distance * 1.5, 10.0), false, false)
            DoorSystemSetAutomaticRate(h, 1.0, false, false)
        end
        door.hashes[i] = h
    end
    door.pos = vector3(def.coords.x, def.coords.y, def.coords.z)
    door.cell = cellKey(door.pos.x, door.pos.y)
    local cell = grid[door.cell]
    if not cell then cell = {} grid[door.cell] = cell end
    cell[def.id] = true
    if door.st.t then door.autoEnd = GetGameTimer() + door.st.t * 1000 end
    Doors[def.id] = door
    applyState(door)
    return door
end

local function unregister(id)
    local door = Doors[id]
    if not door then return end
    for _, h in ipairs(door.hashes) do
        if IsDoorRegisteredWithSystem(h) then RemoveDoorFromSystem(h) end
    end
    local cell = grid[door.cell]
    if cell then cell[id] = nil end
    Doors[id] = nil
end

-- --------------------------------------------------------------------------
--  Pozycja znacznika: środek skrzydła (a nie zawias) – liczona raz, gdy drzwi
--  są zamknięte i ich obiekt jest wczytany
-- --------------------------------------------------------------------------
local function leafCenter(leaf, hash)
    local ent = GetClosestObjectOfType(leaf.coords.x, leaf.coords.y, leaf.coords.z, 1.2, leaf.model, false, false, false)
    if ent == 0 then return nil end
    if math.abs(DoorSystemGetOpenRatio(hash)) > 0.02 then return nil, true end
    local mn, mx = GetModelDimensions(leaf.model)
    return GetOffsetFromEntityInWorldCoords(ent, (mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5, (mn.z + mx.z) * 0.5)
end

local function resolveUi(door)
    local sum, n = vector3(0, 0, 0), 0
    for i, leaf in ipairs(door.def.doors) do
        local c = leafCenter(leaf, door.hashes[i])
        if not c then return end
        sum, n = sum + c, n + 1
    end
    local c = sum / n
    -- znacznik trochę nad klamką, ale nie wyżej niż 1,6 m nad progiem
    door.ui = vector3(c.x, c.y, math.min(c.z + 0.15, door.pos.z + 1.6))
end

-- --------------------------------------------------------------------------
--  Komunikacja z NUI
-- --------------------------------------------------------------------------
local function stateMsg(door)
    local st = door.st or {}
    local t = door.autoEnd and math.max(0, door.autoEnd - GetGameTimer()) or nil
    return { l = st.l, b = st.b, d = st.d, a = st.a, t = t, T = door.def.autoLock * 1000 }
end

local function metaMsg(door)
    local d = door.def
    return { id = d.id, name = d.name, group = d.group, security = d.security, type = d.type, st = stateMsg(door) }
end

function Doors.Get(id) return Doors[id] end

-- --------------------------------------------------------------------------
--  Zdarzenia z serwera
-- --------------------------------------------------------------------------
RegisterNetEvent('dp-doorlock:client:state', function(id, st)
    local door = Doors[id]
    if not door then return end
    local was = door.st
    door.st = st or { l = true }
    door.autoEnd = door.st.t and (GetGameTimer() + door.st.t * 1000) or nil
    applyState(door)
    if nearSet[id] then
        SendNUIMessage({ action = 'chipState', id = id, st = stateMsg(door) })
        if was and was.l ~= door.st.l then
            SendNUIMessage({ action = 'sound', name = door.st.l and 'lock' or 'unlock', vol = 0.8 })
        end
    end
    if DL.admin then SendNUIMessage({ action = 'adminState', id = id, st = door.st }) end
end)

RegisterNetEvent('dp-doorlock:client:door', function(id, def, st)
    unregister(id)
    if def then
        local door = register(def, st)
        if nearSet[id] then SendNUIMessage({ action = 'chipMeta', doors = { metaMsg(door) } }) end
    end
end)

local function load()
    ready = false
    for id in pairs(Doors) do if type(id) == 'number' then unregister(id) end end
    local data = DL.Callback('init')
    if not data then return false end
    for _, def in ipairs(data.doors) do register(def, data.states[tostring(def.id)]) end
    DL.admin = data.admin
    near, nearSet = {}, {}
    SendNUIMessage({ action = 'chips', list = {} })
    ready = true
    return true
end

RegisterNetEvent('dp-doorlock:client:reload', function() CreateThread(load) end)

CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(500) end
    Wait(1000)
    while not load() do Wait(5000) end
end)

-- --------------------------------------------------------------------------
--  Pętla wolna: kandydaci z siatki, fokus, widoczność (async raycast)
-- --------------------------------------------------------------------------
local SCAN = Config.Perf.scanRadius

CreateThread(function()
    while true do
        Wait(Config.Perf.scanInterval)
        if ready then
            local ped = PlayerPedId()
            local p = GetEntityCoords(ped)
            local cx, cy = math.floor(p.x / G) + 4096, math.floor(p.y / G) + 4096
            local newNear, newSet, entered = {}, {}, nil
            local best, bestD = nil, 1e9
            local cam = GetFinalRenderedCamCoord()
            local inVeh = IsPedInAnyVehicle(ped, false)
            local now = GetGameTimer()

            for dx = -1, 1 do
                for dy = -1, 1 do
                    local cell = grid[(cx + dx) * 8192 + (cy + dy)]
                    if cell then
                        for id in pairs(cell) do
                            local door = Doors[id]
                            local dist = #(p - door.pos)
                            if dist <= SCAN then
                                if not door.ui and (door.uiNext or 0) < now then
                                    resolveUi(door)
                                    if not door.ui then door.uiNext = now + 2000 end
                                end
                                local reach = door.def.distance + (inVeh and 4.0 or 0.0)
                                if dist <= reach and dist < bestD then best, bestD = id, dist end
                                if dist <= math.max(DRAW, reach + 1.0) and not door.def.hideUi then
                                    newNear[#newNear + 1] = id
                                    door.dist = dist
                                    -- widoczność: wynik poprzedniego raycastu + nowy probe
                                    if door.probe then
                                        local status, hit = GetShapeTestResult(door.probe)
                                        if status == 2 then door.vis = hit == 0 door.probe = nil
                                        elseif status == 0 then door.probe = nil end
                                    end
                                    if not door.probe then
                                        local t = door.ui or door.pos
                                        door.probe = StartShapeTestLosProbe(cam.x, cam.y, cam.z, t.x, t.y, t.z, 1, ped, 7)
                                    end
                                    if door.vis == nil then door.vis = true end
                                end
                            end
                        end
                    end
                end
            end

            -- najbliższe MAX_CHIPS drzwi (w bloku cel może być ich kilkanaście)
            if #newNear > MAX_CHIPS then
                table.sort(newNear, function(a, b) return Doors[a].dist < Doors[b].dist end)
                for i = #newNear, MAX_CHIPS + 1, -1 do newNear[i] = nil end
            end
            for i = 1, #newNear do
                local id = newNear[i]
                newSet[id] = true
                if not nearSet[id] then
                    entered = entered or {}
                    entered[#entered + 1] = metaMsg(Doors[id])
                end
            end
            if entered then SendNUIMessage({ action = 'chipMeta', doors = entered }) end
            for id in pairs(nearSet) do
                local d = Doors[id]
                if not newSet[id] and d then d.probe, d.vis, d.on = nil, nil, nil end
            end
            near, nearSet = newNear, newSet
            DL.focus = best
        end
    end
end)

-- --------------------------------------------------------------------------
--  Pętla szybka: tylko projekcja znaczników. W bezruchu nic nie alokuje i nic
--  nie wysyła – porównuje z wartościami zapamiętanymi na obiekcie drzwi.
-- --------------------------------------------------------------------------
local lastCount = 0
local SCALE = Config.UI.scaleByDistance

local function flush(count)
    local list = {}
    for i = 1, #near do
        local door = Doors[near[i]]
        if door and door.on then
            list[#list + 1] = { id = near[i], x = door.sx, y = door.sy, s = door.ss, f = door.sf }
        end
    end
    lastCount = count
    SendNUIMessage({ action = 'chips', list = list })
end

CreateThread(function()
    while true do
        if #near == 0 or DL.busy then
            if lastCount > 0 then
                lastCount = 0
                SendNUIMessage({ action = 'chips', list = {} })
            end
            Wait(Config.Perf.idleSleep)
        else
            Wait(0)
            local p = GetEntityCoords(PlayerPedId())
            local changed, count, focus = false, 0, DL.focus
            for i = 1, #near do
                local id = near[i]
                local door = Doors[id]
                if door then
                    local on, x, y = false, 0.0, 0.0
                    if door.vis ~= false then
                        local w = door.ui or door.pos
                        on, x, y = GetScreenCoordFromWorldCoord(w.x, w.y, w.z)
                        if on then
                            count = count + 1
                            local s = SCALE and math.max(0.55, 1.15 - #(p - w) * 0.08) or 1.0
                            local f = focus == id
                            if not door.on or door.sf ~= f or math.abs(door.sx - x) > EPS
                                or math.abs(door.sy - y) > EPS or math.abs(door.ss - s) > 0.02 then
                                door.sx, door.sy, door.ss, door.sf = x, y, s, f
                                changed = true
                            end
                        end
                    end
                    if door.on ~= on then door.on = on changed = true end
                end
            end
            if changed or count ~= lastCount then flush(count) end
        end
    end
end)

-- --------------------------------------------------------------------------
--  API dla innych modułów klienta
-- --------------------------------------------------------------------------
function Doors.Fx(id, fx)
    SendNUIMessage({ action = 'chipFx', id = id, fx = fx })
end

function Doors.Target(id)
    local door = Doors[id]
    return door and (door.ui or door.pos)
end

exports('GetClosestDoor', function() return DL.focus end)
exports('IsLocked', function(id) local d = Doors[id] return d and d.st.l end)
