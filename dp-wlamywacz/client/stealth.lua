-- ==========================================================================
--  Skradanie w domu: koordynator stanu INSIDE (250 ms). Hałas kroków (SKR-01, SKR-03, SKR-05),
--  widoczność (SKR-02), pokój i światło (SKR-07), paczki hałasu do AI (TEC-16)
-- ==========================================================================
local running = false
local pending, pendingSrc = 0, nil
local lastVis = -1
W.room = nil
W.residentPeds = {}

-- hałas z akcji gracza: host AI słyszy go od razu, reszta przez serwer w paczkach (max 4/s)
function W.EmitNoise(v, src)
    v = tonumber(v) or 0
    if v <= 0 then return end
    W.Hud({ noise = math.floor(v) })
    if not W.session or not W.room then return end
    if W.session.host and W.AINoise then W.AINoise(GetPlayerServerId(PlayerId()), W.room, v) end
    if v > pending then pending, pendingSrc = v, src end
end

function W.ApplyLighting()
    local s = W.session
    if not s then return end
    local lit = s.power ~= false and s.lights[W.room or ''] == true
    SetArtificialLightsState(W.IsNight() and not lit)
    W.Hud({ lit = lit })
end

-- domownicy i psy w pobliżu (dla kryjówek i ostrzeżeń); lista odświeżana co 1 s
function W.ResidentNear(dist)
    local pc = GetEntityCoords(PlayerPedId())
    for _, ped in ipairs(W.residentPeds) do
        if DoesEntityExist(ped) and #(GetEntityCoords(ped) - pc) < dist then return ped end
    end
    return nil
end

local function footMode(ped)
    if GetEntitySpeed(ped) < 0.3 then return nil end
    if IsPedSprinting(ped) then return 'sprint' end
    if IsPedRunning(ped) then return 'run' end
    if GetPedStealthMovement(ped) then return 'crouch' end
    return 'walk'
end

local function visibility(ped)
    if W.hidden then return 0 end
    local s = W.session
    local lit = s.power ~= false and s.lights[W.room or ''] == true
    local v = (lit or not W.IsNight()) and 55 or 20
    if W.flashlight then v = v + (W.redFilter and 15 or 35) end
    local m = footMode(ped)
    if m == 'run' or m == 'sprint' then v = v + 20 elseif m == 'walk' then v = v + 8 elseif m == 'crouch' then v = v - 12 end
    if W.carry then v = v + 10 end
    return math.floor(WLM.U.Clamp(v, 0, 100) / 5) * 5
end

function W.StartStealth(s)
    if running then return end
    running = true
    LocalPlayer.state:set('wlmVis', 30, true)
    CreateThread(function()
        local tpl = Config.Interiors[s.interior]
        local rainAt, rainMult, scanAt = 0, 1.0, 0
        local roomsById = {}
        for _, r in ipairs(tpl.rooms) do roomsById[r.id] = r end
        while running and W.session do
            local ped = PlayerPedId()
            local pc = GetEntityCoords(ped)
            local now = GetGameTimer()
            -- pokój
            local rel = vector3(pc.x - s.origin.x, pc.y - s.origin.y, pc.z - s.origin.z)
            local room = WLM.Noise.RoomAt(s.interior, rel) or W.room
            if room ~= W.room then
                W.room = room
                W.ApplyLighting()
                W.Hud({ room = room and roomsById[room] and roomsById[room].label or false })
            end
            -- pogoda raz na 5 s (REK-15)
            if now > rainAt then
                rainAt = now + 5000
                rainMult = GetRainLevel() > 0.2 and Config.Noise.rain or 1.0
            end
            -- kroki
            local m = footMode(ped)
            if m and room then
                local floor = Config.Noise.floor[roomsById[room] and roomsById[room].floor or 'panel'] or 1.0
                local heavy = (W.bag.cap and W.bag.cap > 0 and (W.bag.kg or 0) / W.bag.cap > 0.7) and 1.3 or 1.0
                if W.carry then heavy = heavy * 1.3 end
                local v = Config.Noise.footsteps[m] * floor * rainMult * heavy
                if v >= 3 then W.EmitNoise(v, 'kroki') end
            end
            -- widoczność (statebag tylko przy zmianie)
            local vis = visibility(ped)
            if vis ~= lastVis then
                lastVis = vis
                LocalPlayer.state:set('wlmVis', vis, true)
                W.Hud({ vis = vis })
            end
            -- paczka hałasu do serwera
            if pending > 0 then
                if not s.host then TriggerServerEvent('dp-wlamywacz:server:noise', W.room or '', pending) end
                pending, pendingSrc = 0, nil
            end
            -- domownicy w pobliżu (lista peds ze statebagiem, co 1 s – w instancji pula jest mała)
            if now > scanAt then
                scanAt = now + 1000
                local list = {}
                for _, p in ipairs(GetGamePool('CPed')) do
                    if Entity(p).state.wlmRes then list[#list + 1] = p end
                end
                W.residentPeds = list
                local close = W.ResidentNear(4.0)
                W.GameWarn(close and 1 or 0)
            end
            Wait(250)
        end
        running = false
    end)
end

function W.StopStealth()
    running = false
    W.room = nil
    W.residentPeds = {}
    LocalPlayer.state:set('wlmVis', false, true)
    lastVis = -1
end
