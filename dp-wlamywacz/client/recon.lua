-- ==========================================================================
--  Lornetka (REK-01): kamera skryptowa z zoomem i drżeniem rąk. Celujesz w dom przez 3 s,
--  a serwer dopisuje fakty do notatnika. Cel wybiera się kątem do fasady (co 200 ms),
--  bez raycastów co klatkę. E oznacza punkt dla ekipy (EKI-03).
-- ==========================================================================
local active = false

local function rotToDir(rx, rz)
    local x, z = math.rad(rx), math.rad(rz)
    local c = math.abs(math.cos(x))
    return vector3(-math.sin(z) * c, math.cos(z) * c, math.sin(x))
end

local function ping(cpos, dir)
    local to = cpos + dir * 150.0
    local ray = StartExpensiveSynchronousShapeTestLosProbe(cpos.x, cpos.y, cpos.z, to.x, to.y, to.z, 1 + 2 + 8 + 16, PlayerPedId(), 7)
    local _, hit, coords, _, ent = GetShapeTestResult(ray)
    if hit ~= 1 then return end
    local label = L('ping_here')
    if ent and ent ~= 0 then
        local t = GetEntityType(ent)
        if t == 2 then label = L('ping_car') elseif t == 1 then label = L('ping_person') end
    end
    W.Callback('crew:ping', { x = coords.x, y = coords.y, z = coords.z }, label)
end

function W.StartBinoculars()
    if active or W.busy or W.session then return end
    local has = W.Callback('tool:has', Config.Items.binoculars)
    if Config.RequireItems and not (has and has.ok) then W.Notify(L('need_item', L('item_' .. Config.Items.binoculars)), 'bad') return end
    active = true
    W.busy = true
    local ped = PlayerPedId()
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_BINOCULARS', 0, true)
    Wait(1500)
    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    AttachCamToEntity(cam, ped, 0.0, 0.1, 0.75, true)
    local rx, rz, fov = 0.0, GetEntityHeading(ped), 40.0
    SetCamRot(cam, rx, 0.0, rz, 2)
    SetCamFov(cam, fov)
    ShakeCam(cam, 'HAND_SHAKE', 0.35)
    RenderScriptCams(true, false, 0, true, false)
    SendNUIMessage({ action = 'binoculars', on = true })

    local target, since, nextCheck, lastObs = nil, 0, 0, {}
    while active do
        DisableAllControlActions(0)
        EnableControlAction(0, 245, true) -- czat
        EnableControlAction(0, 249, true) -- push-to-talk
        local mx, my = GetDisabledControlNormal(0, 1), GetDisabledControlNormal(0, 2)
        local k = fov / 45.0
        rz = rz - mx * 8.0 * k
        rx = WLM.U.Clamp(rx - my * 8.0 * k, -60.0, 45.0)
        SetCamRot(cam, rx, 0.0, rz, 2)
        if IsDisabledControlJustPressed(0, 241) then fov = math.max(6.0, fov - 3.0) SetCamFov(cam, fov) end
        if IsDisabledControlJustPressed(0, 242) then fov = math.min(50.0, fov + 3.0) SetCamFov(cam, fov) end

        local now = GetGameTimer()
        if now > nextCheck then
            nextCheck = now + 200
            local cpos, dir = GetCamCoord(cam), rotToDir(rx, rz)
            local best, bestDot = nil, math.cos(math.rad(2.0 + fov * 0.08))
            for id in pairs(W.houses) do
                local c = WLM.HouseById[id].entries[1].coords
                local v = vector3(c.x, c.y, c.z + 1.0) - cpos
                local d = #v
                if d < 90.0 and d > 2.0 then
                    local dot = (v.x * dir.x + v.y * dir.y + v.z * dir.z) / d
                    if dot > bestDot then best, bestDot = id, dot end
                end
            end
            if best ~= target then target, since = best, now end
            local prog = target and math.min(1.0, (now - since) / 3000) or 0
            SendNUIMessage({ action = 'binoculars', on = true, target = target and WLM.HouseById[target].label or nil, progress = prog, zoom = math.floor(50 / fov * 10) / 10 })
            if target and prog >= 1.0 and (not lastObs[target] or now - lastObs[target] > 20000) then
                lastObs[target] = now
                local id = target
                CreateThread(function()
                    local r = W.Callback('recon:observe', id, W.Clock())
                    if r and r.ok then
                        SendNUIMessage({ action = 'binoculars', on = true, rating = r.rating, target = WLM.HouseById[id].label, progress = 1 })
                        W.Notify(L('recon_noted'), 'good')
                    elseif r and r.msg then
                        W.Notify(r.msg, 'bad')
                    end
                end)
            end
        end
        if IsDisabledControlJustPressed(0, 38) then
            ping(GetCamCoord(cam), rotToDir(rx, rz))
        end
        if IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 25) or IsDisabledControlJustPressed(0, 200) then
            active = false
        end
        Wait(0)
    end

    RenderScriptCams(false, false, 0, true, false)
    DestroyCam(cam, false)
    ClearPedTasks(ped)
    SendNUIMessage({ action = 'binoculars', on = false })
    W.busy = false
end

function W.StopBinoculars() active = false end

-- nowy wpis w notatniku (REK-02) – serwer wysyła też do całej ekipy
RegisterNetEvent('dp-wlamywacz:client:note', function(houseId, key, text)
    local h = WLM.HouseById[houseId]
    SendNUIMessage({ action = 'note', house = h and h.label or houseId, text = text })
end)
