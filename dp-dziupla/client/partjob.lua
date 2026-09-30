-- ==========================================================================
--  Sesja demontażu części (styl Car Mechanic Simulator):
--  kamera na część, rzutowanie śrub/klipsów/wtyczek 3D -> ekran, NUI z
--  narzędziami, efekty w świecie (iskry, ogień, poduszka) i noszenie części.
-- ==========================================================================
local D = Dz
local sess

-- --------------------------------------------------------------------------
--  Pozycjonowanie gracza i kamery
-- --------------------------------------------------------------------------
local function standPos(veh, def, loc)
    local mn, mx = GetModelDimensions(GetEntityModel(veh))
    local st = def.stand or { mode = 'side' }
    local x, y
    if st.mode == 'front' then
        x, y = loc.x * 0.6, mx.y + 0.55
    elseif st.mode == 'rear' then
        x, y = loc.x * 0.6, mn.y - 0.55
    elseif st.mode == 'under' then
        x, y = loc.x + 0.35, loc.y
    else
        local sx = st.s or ((def.side and def.side ~= 0) and def.side or -1)
        x = (sx > 0 and mx.x or mn.x) + sx * 0.45
        y = loc.y + (st.dy or 0.0)
    end
    local w = GetOffsetFromEntityInWorldCoords(veh, x, y, 0.0)
    return vector3(w.x, w.y, GetEntityCoords(PlayerPedId()).z)
end

local function poseAnim(def, lift)
    local a = Config.Anim[Logic.Pose(def, lift)] or Config.Anim.stand
    D.PlayAnim(a, 1)
end

local function fastenerDefs(def)
    local out = {}
    for i, f in ipairs(def.F) do
        out[i] = {
            t = f.t, size = f.size, bit = f.bit, fluid = f.fluid, sets = f.sets, airbag = f.airbag,
            sensitive = f.sensitive, sign = f.sign, cut = f.cut, fire = f.fire, after = f.after,
            tool = f.tool, closed = f.closed,
        }
    end
    return out
end

local function worldPoints(veh, def, loc)
    local list = {}
    for i, f in ipairs(def.F) do
        if f.pts then
            local arr = {}
            for j, p in ipairs(f.pts) do arr[j] = D.PartWorld(veh, def, loc, p) end
            list[i] = arr
        else
            list[i] = { D.PartWorld(veh, def, loc, f.o) }
        end
    end
    return list
end

local function round4(v) return math.floor(v * 10000 + 0.5) / 10000 end

local function project(list)
    local out = {}
    for i, arr in ipairs(list) do
        local pts = {}
        for j, w in ipairs(arr) do
            local on, x, y = GetScreenCoordFromWorldCoord(w.x, w.y, w.z)
            pts[j] = { round4(x), round4(y), on and 1 or 0 }
        end
        out[i] = pts
    end
    return out
end

-- ile ekranu (w wysokości) zajmuje 1 m w miejscu części – do skalowania ikon
local function screenScale(anchor)
    local _, _, y1 = GetScreenCoordFromWorldCoord(anchor.x, anchor.y, anchor.z)
    local _, _, y2 = GetScreenCoordFromWorldCoord(anchor.x, anchor.y, anchor.z + 0.1)
    return math.abs(y1 - y2) * 10.0
end

-- punkt na łamanej (linie cięcia) dla efektów
local function pointAlong(arr, t)
    if #arr == 1 then return arr[1] end
    local total, seg = 0.0, {}
    for i = 1, #arr - 1 do
        seg[i] = #(arr[i + 1] - arr[i])
        total = total + seg[i]
    end
    local want = total * math.max(0.0, math.min(1.0, t or 0.0))
    for i = 1, #arr - 1 do
        if want <= seg[i] or i == #arr - 1 then
            local k = seg[i] > 0 and want / seg[i] or 0
            return arr[i] + (arr[i + 1] - arr[i]) * math.min(1.0, k)
        end
        want = want - seg[i]
    end
    return arr[#arr]
end

-- --------------------------------------------------------------------------
--  Efekty w świecie
-- --------------------------------------------------------------------------
local function stopSparks()
    if sess and sess.sparks then
        StopParticleFxLooped(sess.sparks, false)
        sess.sparks = nil
    end
end

local function fx(data)
    if not sess then return end
    local arr = sess.pts[tonumber(data.i) or 1] or sess.pts[1]
    local pos = pointAlong(arr, tonumber(data.t))
    local kind = data.kind
    if kind == 'sparks' then
        if data.on then
            if sess.sparksAt and #(sess.sparksAt - pos) < 0.08 and sess.sparks then return end
            stopSparks()
            if D.LoadPtfx('scr_reconstructionaccident') then
                UseParticleFxAssetNextCall('scr_reconstructionaccident')
                sess.sparks = StartParticleFxLoopedAtCoord('scr_sparking_generator', pos.x, pos.y, pos.z, 0.0, 0.0, 0.0, 0.5, false, false, false, false)
                sess.sparksAt = pos
            end
        else
            stopSparks()
        end
    elseif kind == 'spark' then
        if D.LoadPtfx('core') then
            UseParticleFxAssetNextCall('core')
            StartParticleFxNonLoopedAtCoord('ent_brk_sparking_wires', pos.x, pos.y, pos.z, 0.0, 0.0, 0.0, 1.2, false, false, false)
        end
        if sess.cam then ShakeCam(sess.cam, 'SMALL_EXPLOSION_SHAKE', 0.2) end
    elseif kind == 'airbag' then
        sess.airbag = true
        if sess.cam then ShakeCam(sess.cam, 'SMALL_EXPLOSION_SHAKE', 0.6) end
        ApplyDamageToPed(PlayerPedId(), 8, false)
    elseif kind == 'fire' then
        local g = D.GroundZ(pos)
        local f = StartScriptFire(pos.x, pos.y, g, 8, false)
        sess.fires[#sess.fires + 1] = f
        SetTimeout(15000, function() RemoveScriptFire(f) end)
    end
end

-- --------------------------------------------------------------------------
--  Start / koniec sesji
-- --------------------------------------------------------------------------
local function closeSession(result)
    if not sess then return end
    local s = sess
    sess = nil
    stopSparks()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'partClose' })
    if s.cam then
        RenderScriptCams(false, true, 600, true, true)
        DestroyCam(s.cam, false)
    end
    local ped = PlayerPedId()
    ClearPedTasks(ped)
    D.busy = false
    if s.airbag then
        SetPedToRagdoll(ped, 1800, 1800, 0, false, false, false)
        D.Notify(L('airbag_boom'), 'bad')
    end
    if result and result.ok then
        if s.veh and DoesEntityExist(s.veh) then
            local st = Entity(s.veh).state.dpChop
            if st then D.ApplyVisuals(s.veh, st) end
        end
        if result.msg then D.Notify(result.msg, 'good', 6000) end
        if result.carry then D.StartCarry(result.carry) end
    end
end

function D.StartPart(veh, st, partId)
    if D.busy then return D.Notify(L('busy'), 'warn') end
    if D.carrying then return D.Notify(L('carry_first'), 'warn') end
    local def = Parts.ById[partId]
    if not def then return end
    D.busy = true
    local r = D.Callback('partBegin', st.id, partId)
    if not r or not r.ok then
        D.busy = false
        return D.Notify(r and r.msg or L('error'), 'bad')
    end
    D.fx = r.ctx and r.ctx.fx or D.fx

    local ped = PlayerPedId()
    if def.open and D.Control(veh) then
        for _, d in ipairs(def.open) do
            if GetIsDoorValid(veh, d) and not IsVehicleDoorDamaged(veh, d) then SetVehicleDoorOpen(veh, d, false, false) end
        end
    end
    local loc = D.AnchorLocal(veh, def)
    local anchorW = D.PartWorld(veh, def, loc, vector3(0.0, 0.0, 0.0))
    local stand = standPos(veh, def, loc)
    TaskGoStraightToCoord(ped, stand.x, stand.y, stand.z, 1.0, 2500, 0.0, 0.1)
    local t = GetGameTimer() + 2500
    while #(GetEntityCoords(ped).xy - stand.xy) > 0.4 and GetGameTimer() < t do Wait(50) end
    local pc = GetEntityCoords(ped)
    SetEntityHeading(ped, GetHeadingFromVector_2d(anchorW.x - pc.x, anchorW.y - pc.y))
    poseAnim(def, st.lift or 0)

    local cp = D.PartWorld(veh, def, loc, def.cam.o)
    local look = D.PartWorld(veh, def, loc, def.cam.look or vector3(0.0, 0.0, 0.0))
    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', cp.x, cp.y, cp.z, 0.0, 0.0, 0.0, def.cam.fov or 45.0, false, 0)
    PointCamAtCoord(cam, look.x, look.y, look.z)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 700, true, true)

    sess = {
        veh = veh, st = st, def = def, loc = loc, token = r.token, cam = cam, fires = {},
        pts = worldPoints(veh, def, loc), anchor = anchorW, started = GetGameTimer(),
    }
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'partOpen', part = r.part, ctx = r.ctx, F = fastenerDefs(def) })

    -- rzutowanie punktów (gęsto w trakcie najazdu kamery, potem rzadko)
    CreateThread(function()
        local mine = sess
        while sess == mine do
            SendNUIMessage({ action = 'partPoints', pts = project(mine.pts), scale = screenScale(mine.anchor) })
            Wait(GetGameTimer() - mine.started < 2200 and 40 or 350)
        end
    end)

    -- HUD gry schowany, postać niewidoczna lokalnie (nie zasłania części)
    CreateThread(function()
        local mine = sess
        while sess == mine do
            HideHudAndRadarThisFrame()
            SetEntityLocallyInvisible(PlayerPedId())
            Wait(0)
        end
    end)

    -- strażnik: śmierć / odjechanie auta
    CreateThread(function()
        local mine = sess
        while sess == mine do
            local p = PlayerPedId()
            if IsEntityDead(p) or not DoesEntityExist(veh) or #(GetEntityCoords(p) - GetEntityCoords(veh)) > Config.Security.maxDistance then
                SendNUIMessage({ action = 'forceClose' })
                D.Callback('partAbort', mine.token, {})
                closeSession(nil)
                break
            end
            Wait(500)
        end
    end)
end

RegisterNUICallback('part', function(data, cb)
    local a = data and data.action
    if not sess then return cb({ ok = false }) end
    if a == 'fx' then
        fx(data)
        return cb({ ok = true })
    end
    local s = sess
    CreateThread(function()
        if a == 'finish' then
            local r = D.Callback('partFinish', s.token, data.report or {})
            if r and r.ok then
                cb(r)
                closeSession(r)
            else
                if not r then D.Callback('partAbort', s.token, {}) end
                cb(r or { ok = false, msg = L('error') })
                D.Notify(r and r.msg or L('error'), 'bad')
                closeSession(nil)
            end
        elseif a == 'abort' then
            D.Callback('partAbort', s.token, data.done or {})
            cb({ ok = true })
            closeSession(nil)
        else
            cb({ ok = false })
        end
    end)
end)

-- --------------------------------------------------------------------------
--  Noszenie części na regał
-- --------------------------------------------------------------------------
local function nearShelf()
    local pc = GetEntityCoords(PlayerPedId())
    for _, shop in ipairs(Config.Shops) do
        if #(pc - shop.shelf) < 2.2 then return shop end
    end
end

function D.StartCarry(info)
    if D.carrying then return end
    D.carrying = info
    CreateThread(function()
        local ped = PlayerPedId()
        local model = (info.prop and D.LoadModel(info.prop)) or D.LoadModel('prop_cs_cardbox_01')
        local grip = Parts.Carry[info.kind or 'box'] or Parts.Carry.box
        local obj
        if model then
            local c = GetEntityCoords(ped)
            obj = CreateObject(model, c.x, c.y, c.z + 0.2, true, true, false)
            SetEntityCollision(obj, false, false)
            AttachEntityToEntity(obj, ped, GetPedBoneIndex(ped, grip.bone), grip.pos.x, grip.pos.y, grip.pos.z, grip.rot.x, grip.rot.y, grip.rot.z, true, true, false, true, 1, true)
            SetModelAsNoLongerNeeded(model)
        end
        local a = Config.Anim.carry
        D.LoadDict(a.dict)
        local storing = false
        while D.carrying do
            ped = PlayerPedId()
            if not IsEntityDead(ped) and not IsPedRagdoll(ped) and not IsEntityPlayingAnim(ped, a.dict, a.clip, 3) then
                TaskPlayAnim(ped, a.dict, a.clip, 3.0, 3.0, -1, 49, 0, false, false, false)
            end
            if not (D.fx and D.fx.mule) then DisableControlAction(0, 21, true) end
            DisableControlAction(0, 22, true)
            DisableControlAction(0, 23, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 44, true)
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)
            local shelf = nearShelf()
            if shelf then
                D.Help(L('help_shelf'))
                if IsControlJustReleased(0, 38) and not storing then
                    storing = true
                    CreateThread(function()
                        local r = D.Callback('carryStore')
                        if r and r.ok then
                            D.carrying = nil
                            D.Notify(r.msg, 'good')
                        else
                            D.Notify(r and r.msg or L('error'), 'bad')
                        end
                        storing = false
                    end)
                end
            else
                D.Help(L('help_carry'))
            end
            Wait(0)
        end
        StopAnimTask(ped, a.dict, a.clip, 2.0)
        if obj and DoesEntityExist(obj) then
            DetachEntity(obj, true, true)
            DeleteEntity(obj)
        end
    end)
end

-- przywrócenie noszenia po restarcie zasobu / reconnect
CreateThread(function()
    Wait(4000)
    local r = D.Callback('carryState')
    if r and r.carrying then D.StartCarry({ kind = 'box' }) end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if sess then
        stopSparks()
        if sess.cam then
            RenderScriptCams(false, false, 0, true, true)
            DestroyCam(sess.cam, false)
        end
        SetNuiFocus(false, false)
        ClearPedTasks(PlayerPedId())
    end
end)
