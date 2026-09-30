-- ==========================================================================
--  Świat: domy w pobliżu (stan NEAR), wejścia i metody otwierania (WEJ), ukryty klucz (WEJ-08),
--  bezpieczniki (ZAB-18), dzwonek (REK-21), naklejka (REK-06), obchód (REK-14), syrena (ZAB-25),
--  przechodnie jako świadkowie (NPC-18), szopy (DOM-11)
-- ==========================================================================
local active = {}                  -- [houseId] = true (strefy założone)
local noted = {}                   -- [houseId:seed:entry] = true (obchód)
local sheds = {}                   -- [shedId] = { prop }
local sirenOn = false

local ICONS = {
    lockpick = 'fa-solid fa-key', rake = 'fa-solid fa-bars-staggered', key = 'fa-solid fa-key', pry = 'fa-solid fa-screwdriver-wrench',
    smash = 'fa-solid fa-hammer', glasscut = 'fa-solid fa-circle-notch', wire = 'fa-solid fa-wave-square', climb = 'fa-solid fa-person-walking',
    shim = 'fa-solid fa-ruler', cutters = 'fa-solid fa-scissors',
}

local function hs(id) return W.houseState[id] end

-- --------------------------------------------------------------------------
--  Otwieranie wejścia: serwer daje parametry minigry, klient gra, serwer sprawdza wynik
-- --------------------------------------------------------------------------
function W.TryEntry(houseId, entryId, method)
    if W.busy then return end
    local r = W.Call('entry:begin', houseId, entryId, method, W.Clock())
    if not r or not r.ok then return end
    local res = W.RunGame(r.game)
    local fin = W.Callback('entry:finish', r.token, { ok = res.ok, broken = res.broken })
    if not fin or not fin.ok then
        W.Notify(fin and fin.msg or L('error'), 'bad')
    elseif fin.opened then
        W.Notify(L('entry_opened'), 'good')
    elseif not res.aborted then
        W.Notify(L('entry_failed'), 'bad')
    end
end

local function canMethod(h, e, m)
    local s = hs(h.id)
    if not s or not s.entries[e.id] then return false end
    local es = s.entries[e.id]
    if es.open then return false end
    if e.requires == 'gate' and not s.gateOpen then return false end
    if m == 'wire' then return es.state == 'tilted' end
    if m == 'climb' then return e.type == 'gate' end
    if m == 'key' then return e.front == true and s.keyTaken == true end
    if m == 'rake' then
        local p = W.Profile(h.id)
        local lock = p and p.entries[e.id] and p.entries[e.id].lock
        return lock ~= nil and (Config.Locks[lock].rake or 0) > 0
    end
    return true
end

local function entryOptions(h, e)
    local opts = {}
    if e.type ~= 'gate' then
        opts[#opts + 1] = {
            label = L('enter'), icon = 'fa-solid fa-door-open',
            canInteract = function() local s = hs(h.id) return s and s.entries[e.id] and s.entries[e.id].open end,
            action = function() W.EnterHouse(h.id, e.id) end,
        }
    end
    for _, m in ipairs(Config.EntryTypes[e.type].methods) do
        opts[#opts + 1] = {
            label = L('m_' .. m), icon = ICONS[m],
            canInteract = function() return canMethod(h, e, m) end,
            action = function() W.TryEntry(h.id, e.id, m) end,
        }
    end
    if e.front then
        opts[#opts + 1] = { label = L('doorbell'), icon = 'fa-solid fa-bell', action = function() W.Doorbell(h.id, e) end }
        opts[#opts + 1] = { label = L('sticker'), icon = 'fa-solid fa-shield-halved', action = function() W.Call('recon:sticker', h.id) end }
    end
    return opts
end

-- --------------------------------------------------------------------------
--  Dzwonek (REK-21): jeśli ktoś otworzy, na chwilę pojawia się w drzwiach
-- --------------------------------------------------------------------------
function W.Doorbell(houseId, e)
    if W.busy then return end
    SendNUIMessage({ action = 'sound', kind = 'doorbell' })
    local r = W.Call('recon:doorbell', houseId, W.Clock())
    if not r or not r.ok then return end
    if not r.answered then W.Notify(L('bell_nobody'), 'info') return end
    Wait(2500)
    local hash = W.LoadModel(r.model)
    if not hash then return end
    local c = e.coords
    local h = math.rad(c.w)
    local ped = CreatePed(4, hash, c.x + math.sin(h) * 1.1, c.y - math.cos(h) * 1.1, W.GroundZ(vector3(c.x, c.y, c.z)), c.w + 180.0, false, true)
    SetModelAsNoLongerNeeded(hash)
    SetBlockingOfNonTemporaryEvents(ped, true)
    TaskLookAtEntity(ped, PlayerPedId(), 6000, 2048, 3)
    PlayPedAmbientSpeechNative(ped, 'GENERIC_HI', 'SPEECH_PARAMS_FORCE')
    W.Notify(L('bell_answered', r.name), 'warn')
    Wait(6000)
    if DoesEntityExist(ped) then DeleteEntity(ped) end
end

-- --------------------------------------------------------------------------
--  Zakładanie i zdejmowanie stref domu
-- --------------------------------------------------------------------------
local function setupHouse(h)
    active[h.id] = true
    W.near[h.id] = true
    local r = W.Callback('house:watch', h.id, true)
    if r and r.ok then W.houseState[h.id] = r.state end
    for _, e in ipairs(h.entries) do
        W.AddPoint(('h:%s:e:%s'):format(h.id, e.id), e.coords, 1.2, entryOptions(h, e))
    end
    for i, spot in ipairs(h.keySpots or {}) do
        W.AddPoint(('h:%s:k:%d'):format(h.id, i), spot, 0.8, { {
            label = L('key_search'), icon = 'fa-solid fa-magnifying-glass',
            canInteract = function() local s = hs(h.id) return s and not s.keyTaken end,
            action = function()
                local b = W.Call('key:begin', h.id, i)
                if not b or not b.ok then return end
                local res = W.RunGame(b.game)
                if res.ok then W.Call('key:finish', b.token) end
            end,
        } })
    end
    if h.fuse then
        W.AddPoint(('h:%s:fuse'):format(h.id), h.fuse, 1.0, { {
            label = L('fuse_open'), icon = 'fa-solid fa-bolt',
            canInteract = function() local s = hs(h.id) return s and s.power end,
            action = function()
                local b = W.Call('fuse:begin', h.id)
                if not b or not b.ok then return end
                local res = W.Game(b.game)
                W.Call('fuse:finish', b.token, { ok = res.ok })
            end,
        } })
    end
    W.CheckClothing()
    W.HudShow(true)
end

local function teardownHouse(id)
    active[id] = nil
    W.near[id] = nil
    W.RemovePoints(('h:%s:'):format(id))
    W.Callback('house:watch', id, false)
    if not next(active) and not W.session then W.HudShow(false) end
end

AddEventHandler('dp-wlamywacz:client:housesChanged', function()
    for id in pairs(active) do
        if not W.houses[id] then teardownHouse(id) end
    end
end)

-- --------------------------------------------------------------------------
--  Szopy (DOM-11): skrzynię spawnujemy lokalnie tylko w pobliżu
-- --------------------------------------------------------------------------
local function shedAction(s, method)
    if W.busy then return end
    local r = W.Call('shed:begin', s.id, method)
    if not r or not r.ok then return end
    local res = W.RunGame(r.game)
    local fin = W.Callback('shed:finish', r.token, { ok = res.ok, broken = res.broken })
    if fin and fin.found then
        W.Notify(#fin.found > 0 and L('found', table.concat(fin.found, ', ')) or L('found_nothing'), #fin.found > 0 and 'good' or 'info')
    elseif fin and fin.opened then
        W.Notify(L('padlock_opened'), 'good')
    elseif fin and fin.ok and not res.aborted then
        W.Notify(L('entry_failed'), 'bad')
    end
end

local function setupShed(s)
    local hash = W.LoadModel(s.prop)
    local prop
    if hash then
        prop = CreateObject(hash, s.coords.x, s.coords.y, W.GroundZ(s.coords), false, false, false)
        SetEntityHeading(prop, s.coords.w)
        PlaceObjectOnGroundProperly(prop)
        FreezeEntityPosition(prop, true)
        SetModelAsNoLongerNeeded(hash)
    end
    sheds[s.id] = { prop = prop }
    local open = function() return W.sheds[s.id] and W.sheds[s.id].open end
    local opts = {}
    for _, m in ipairs({ 'lockpick', 'shim', 'cutters' }) do
        opts[#opts + 1] = { label = L('m_' .. m), icon = ICONS[m], canInteract = function() return not open() end, action = function() shedAction(s, m) end }
    end
    opts[#opts + 1] = { label = L('search_chest'), icon = 'fa-solid fa-toolbox', canInteract = open, action = function() shedAction(s, 'search') end }
    W.AddPoint('s:' .. s.id, s.coords, 1.3, opts)
end

local function teardownShed(id)
    local s = sheds[id]
    if s and s.prop and DoesEntityExist(s.prop) then DeleteEntity(s.prop) end
    sheds[id] = nil
    W.RemovePoint('s:' .. id)
end

-- --------------------------------------------------------------------------
--  Pętla NEAR (500 ms przy celach, 1500 ms poza nimi)
-- --------------------------------------------------------------------------
CreateThread(function()
    local clothingAt = 0
    while true do
        local sleep = 1500
        if W.ready and not W.session then
            local ped = PlayerPedId()
            local pc = GetEntityCoords(ped)
            for id in pairs(W.houses) do
                local h = WLM.HouseById[id]
                if h then
                    local c = h.entries[1].coords
                    local d = #(pc - vector3(c.x, c.y, c.z))
                    if d < 70.0 and not active[id] then setupHouse(h)
                    elseif d > 90.0 and active[id] then teardownHouse(id) end
                end
            end
            for _, s in ipairs(Config.Sheds) do
                local st = W.sheds[s.id]
                local d = #(pc - vector3(s.coords.x, s.coords.y, s.coords.z))
                local want = d < 60.0 and st and not st.cooldown
                if want and not sheds[s.id] then setupShed(s)
                elseif not want and sheds[s.id] then teardownShed(s.id) end
            end

            if next(active) then
                sleep = 500
                local siren, vol = false, 0.0
                for id in pairs(active) do
                    local h = WLM.HouseById[id]
                    local seed = W.houses[id]
                    -- obchód (REK-14): podejście do wejścia zapisuje, co przy nim widać
                    for _, e in ipairs(h.entries) do
                        local key = id .. ':' .. tostring(seed) .. ':' .. e.id
                        if not noted[key] and #(pc - vector3(e.coords.x, e.coords.y, e.coords.z)) < 4.0 then
                            noted[key] = true
                            CreateThread(function() W.Callback('recon:entry', id, e.id) end)
                        end
                    end
                    local s = hs(id)
                    if s and s.siren then
                        local c = h.entries[1].coords
                        local d = #(pc - vector3(c.x, c.y, c.z))
                        if d < Config.Security.siren.radius then
                            siren = true
                            vol = math.max(vol, 1.0 - d / Config.Security.siren.radius)
                        end
                    end
                end
                if siren or sirenOn then
                    sirenOn = siren
                    SendNUIMessage({ action = 'siren', on = siren, volume = vol })
                end
                if GetGameTimer() > clothingAt then
                    clothingAt = GetGameTimer() + 2500
                    W.CheckClothing()
                end
            end
        end
        Wait(sleep)
    end
end)

-- --------------------------------------------------------------------------
--  Przechodnie reagują na głośne zdarzenia (NPC-18): jedno przejście po puli pedów na zdarzenie
-- --------------------------------------------------------------------------
function W.VehicleDesc()
    local me = PlayerPedId()
    local veh = GetVehiclePedIsIn(me, true)
    if veh == 0 or not DoesEntityExist(veh) or #(GetEntityCoords(veh) - GetEntityCoords(me)) > 40.0 then return nil end
    local name = GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(veh)))
    local plate = (GetVehicleNumberPlateText(veh) or ''):gsub('%s', '')
    return L('desc_vehicle', name, plate:sub(1, 3) .. '???')
end

RegisterNetEvent('dp-wlamywacz:client:worldNoise', function(value, c, houseId)
    local range = math.min(50.0, value * 0.6)
    local me = PlayerPedId()
    local pc = GetEntityCoords(me)
    local count = 0
    for _, ped in ipairs(GetGamePool('CPed')) do
        if ped ~= me and not IsPedAPlayer(ped) and not IsEntityAMissionEntity(ped) and not IsPedDeadOrDying(ped, true) and IsPedHuman(ped) then
            if #(GetEntityCoords(ped) - pc) < range and HasEntityClearLosToEntity(ped, me, 17) then
                count = count + 1
                if count <= 2 then
                    ClearPedTasks(ped)
                    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_MOBILE', 0, true)
                end
            end
        end
    end
    if count > 0 then
        local desc = W.DescribePed(me)
        local v = W.VehicleDesc()
        if v then desc = desc .. '; ' .. v end
        W.Callback('witness:report', houseId, count, desc)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(sheds) do teardownShed(id) end
end)
