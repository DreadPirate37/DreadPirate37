-- ==========================================================================
--  Kamery w domu (ZAB-01, ZAB-02, ZAB-03). Każdy klient sprawdza tylko siebie i tylko kamery
--  w swoim pokoju: kąt → zasięg → asynchroniczny raycast co 200 ms. Obrót kamery liczony jest
--  z czasu sieciowego, więc wszyscy widzą ten sam obrót bez żadnej synchronizacji.
--  Dioda i obrót propu rysowane są tylko, gdy kamera jest bliżej niż 25 m.
-- ==========================================================================
local cams = {}
local running = false
local camsOffUntil = 0
local CAM_MODEL = 'prop_cctv_cam_01a'

local function yawOf(c)
    if not c.sweep then return c.base end
    local t = GetNetworkTime() / 1000.0
    return c.base + (Config.Security.camera.sweep / 2) * math.sin(t / Config.Security.camera.period * math.pi * 2)
end

function W.StartSecurity(s)
    cams = {}
    local tpl = Config.Interiors[s.interior]
    local ir = WLM.HouseById[s.house].tier >= 3   -- kamery IR: dioda niewidoczna gołym okiem
    local hash = W.LoadModel(CAM_MODEL)
    for _, id in ipairs(s.cameras or {}) do
        local p = WLM.U.FindPoint(tpl, id)
        if p then
            local c = WLM.U.Rel(s.origin, p.pos)
            local obj
            if hash then
                obj = CreateObject(hash, c.x, c.y, c.z, false, false, false)
                FreezeEntityPosition(obj, true)
                SetEntityHeading(obj, p.pos.w or 0.0)
            end
            cams[#cams + 1] = { id = id, room = p.room, pos = c, base = p.pos.w or 0.0, sweep = p.sweep == true, obj = obj, ir = ir, spot = 0 }
        end
    end
    if hash then SetModelAsNoLongerNeeded(hash) end
    if #cams == 0 then return end
    running = true

    -- detekcja co 200 ms
    CreateThread(function()
        local cfg = Config.Security.camera
        local cosHalf = math.cos(math.rad(cfg.fov / 2))
        local reported = false
        while running and W.session do
            local s2 = W.session
            local active = s2.power ~= false and s2.dvr ~= 'destroyed' and GetGameTimer() > camsOffUntil and not W.hidden
            if active and not reported then
                local ped = PlayerPedId()
                local pc = GetEntityCoords(ped)
                for _, c in ipairs(cams) do
                    if c.room == W.room then
                        if c.ray then
                            local st, hit = GetShapeTestResult(c.ray)
                            if st == 2 then
                                if hit == 0 then c.spot = c.spot + 0.2 else c.spot = math.max(0, c.spot - 0.2) end
                                c.ray = nil
                            elseif st == 0 then c.ray = nil end
                        else
                            local d = pc - c.pos
                            local dist = #d
                            if dist < cfg.range then
                                local yaw = math.rad(yawOf(c))
                                local fx, fy = -math.sin(yaw), math.cos(yaw)
                                local h = math.sqrt(d.x * d.x + d.y * d.y)
                                if h > 0.01 and (d.x * fx + d.y * fy) / h > cosHalf then
                                    local to = GetPedBoneCoords(ped, 24818, 0.0, 0.0, 0.0)
                                    c.ray = StartShapeTestLosProbe(c.pos.x, c.pos.y, c.pos.z - 0.15, to.x, to.y, to.z, 1 + 16, c.obj or 0, 4)
                                else
                                    c.spot = math.max(0, c.spot - 0.2)
                                end
                            else
                                c.spot = math.max(0, c.spot - 0.2)
                            end
                        end
                        W.Hud({ cam = math.floor(math.min(1, c.spot / cfg.spotTime) * 100) })
                        if c.spot >= cfg.spotTime then
                            reported = true
                            CreateThread(function() W.Callback('cam:spotted', c.id) end)
                        end
                    end
                end
            end
            Wait(200)
        end
    end)

    -- dioda i obrót propu – tylko w pobliżu kamer
    CreateThread(function()
        while running and W.session do
            local pc = GetEntityCoords(PlayerPedId())
            local any = false
            local powered = W.session.power ~= false and GetGameTimer() > camsOffUntil
            for _, c in ipairs(cams) do
                if #(pc - c.pos) < 25.0 then
                    any = true
                    local yaw = yawOf(c)
                    if c.obj and c.sweep then SetEntityRotation(c.obj, 0.0, 0.0, yaw, 2, false) end
                    if powered and not c.ir and (GetGameTimer() % 2000) < 160 then
                        local f = GetOffsetFromEntityInWorldCoords(c.obj or 0, 0.0, 0.18, -0.05)
                        DrawLightWithRange(f.x, f.y, f.z, 255, 20, 20, 0.6, 6.0)
                    end
                end
            end
            Wait(any and 0 or 500)
        end
    end)
end

function W.StopSecurity()
    running = false
    for _, c in ipairs(cams) do
        if c.obj and DoesEntityExist(c.obj) then DeleteEntity(c.obj) end
    end
    cams = {}
    W.Hud({ cam = false })
end

RegisterNetEvent('dp-wlamywacz:client:camsOff', function(sec)
    camsOffUntil = GetGameTimer() + (tonumber(sec) or 60) * 1000
end)
