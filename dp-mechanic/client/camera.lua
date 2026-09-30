-- ==========================================================================
--  dp-mechanic – kamera skryptowa warsztatu
--  Płynne przeloty między presetami (Config.CamPresets, współrzędne w „połówkach”
--  bryły auta), celowanie w kości, miejsca montażu (Config.Anchors) oraz tryb
--  orbitalny (PPM = obrót, kółko = zoom) z inercją. Jeden wątek co klatkę –
--  wyłącznie gdy kamera jest aktywna.
-- ==========================================================================
DPM.Camera = {}

local C = {
    active = false,
    gen = 0,            -- numer „sesji” kamery (stare wątki kończą się same)
    veh = nil,
    cur = nil,          -- kamera docelowa (renderowana po przelocie)
    snap = nil,         -- kamera-migawka (start przelotu)
    snapUntil = 0,
    trash = {},         -- kamery do zniszczenia po przelocie
    tgt = nil,          -- { mode = 'local'|'world', pos, look, fov }
    ground = nil,       -- Z podłogi pod autem (ograniczenie kamery)
    preset = nil,
    orbit = false,
    orb = nil,
    lastPos = nil,      -- ostatnia pozycja świata (gdy auto zniknie)
    lastLook = nil,
}

local ORBIT_FOV = 50.0
local ORBIT_SENS_YAW = 7.5     -- stopnie na jednostkę ruchu myszy
local ORBIT_SENS_PITCH = 5.0
local ORBIT_SMOOTH = 11.0      -- szybkość doganiania celu (1/s)
local ORBIT_INERTIA = 4.2      -- wygaszanie bezwładności (1/s)
local ZOOM_STEP = 0.12         -- ułamek dystansu na „ząbek” kółka
local LIFTED_MIN = 0.9         -- prześwit uznawany za „auto podniesione”

local dimsCache = {}

-- --------------------------------------------------------------------------
--  Pomocnicze
-- --------------------------------------------------------------------------
local function dims(veh)
    local model = GetEntityModel(veh)
    local d = dimsCache[model]
    if not d then
        local min, max = GetModelDimensions(model)
        d = {
            min = min, max = max,
            c = vec3((min.x + max.x) * 0.5, (min.y + max.y) * 0.5, (min.z + max.z) * 0.5),
            h = vec3((max.x - min.x) * 0.5, (max.y - min.y) * 0.5, (max.z - min.z) * 0.5),
        }
        dimsCache[model] = d
    end
    return d
end

local function toWorld(veh, l)
    return GetOffsetFromEntityInWorldCoords(veh, l.x, l.y, l.z)
end

local function toLocal(veh, w)
    return GetOffsetFromEntityGivenWorldCoords(veh, w.x, w.y, w.z)
end

local function vehOk(veh)
    return veh ~= nil and veh ~= 0 and DoesEntityExist(veh)
end

-- prześwit spodu auta nad podłogą (m) i Z podłogi
local function clearance(veh)
    local d = dims(veh)
    local hag = GetEntityHeightAboveGround(veh)
    local z = GetEntityCoords(veh).z
    return hag + d.min.z, z - hag
end

-- rotacja (pitch, 0, heading) dla kierunku
local function rotFromDir(dx, dy, dz)
    local flat = math.sqrt(dx * dx + dy * dy)
    local pitch = math.deg(math.atan(dz, flat))
    local yaw = math.deg(math.atan(-dx, dy))
    return pitch, yaw
end

local function newCam(pos, rot, fov)
    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, fov or 45.0, false, 2)
    return cam
end

local function destroy(cam)
    if cam and DoesCamExist(cam) then
        SetCamActive(cam, false)
        DestroyCam(cam, false)
    end
end

local function flushTrash(keepA, keepB)
    for i = #C.trash, 1, -1 do
        local cam = C.trash[i]
        if cam ~= keepA and cam ~= keepB then destroy(cam) end
        C.trash[i] = nil
    end
end

local function setCamPose(cam, pos, look, fov)
    local p, y = rotFromDir(look.x - pos.x, look.y - pos.y, look.z - pos.z)
    SetCamCoord(cam, pos.x, pos.y, pos.z)
    SetCamRot(cam, p, 0.0, y, 2)
    if fov then SetCamFov(cam, fov) end
end

-- światowe położenie celu (z ograniczeniem do podłogi)
local function resolveTarget(t)
    local pos, look
    if t.mode == 'local' then
        if not vehOk(C.veh) then return C.lastPos, C.lastLook end
        pos, look = toWorld(C.veh, t.pos), toWorld(C.veh, t.look)
    else
        pos, look = t.pos, t.look
    end
    if C.ground and pos.z < C.ground + 0.18 then pos = vec3(pos.x, pos.y, C.ground + 0.18) end
    C.lastPos, C.lastLook = pos, look
    return pos, look
end

-- aktualna renderowana poza kamery
local function renderedPose()
    if C.active then
        return GetFinalRenderedCamCoord(), GetFinalRenderedCamRot(2), GetFinalRenderedCamFov()
    end
    return GetGameplayCamCoord(), GetGameplayCamRot(2), GetGameplayCamFov()
end

-- przelot: migawka bieżącej pozy → nowa kamera docelowa
local function flyTo(t, ms)
    ms = math.max(0, math.floor(tonumber(ms) or 900))
    local fromPos, fromRot, fromFov = renderedPose()
    if C.cur then C.trash[#C.trash + 1] = C.cur end
    if C.snap then C.trash[#C.trash + 1] = C.snap end

    C.tgt = t
    local pos, look = resolveTarget(t)
    local to = newCam(pos or fromPos, fromRot, t.fov or fromFov)
    if pos and look then setCamPose(to, pos, look, t.fov) end

    if ms <= 0 then
        SetCamActive(to, true)
        C.snap = nil
        flushTrash(to)
    else
        local snap = newCam(fromPos, fromRot, fromFov)
        SetCamActive(snap, true)
        flushTrash(snap, to)
        SetCamActiveWithInterp(to, snap, ms, 1, 1)
        C.snap = snap
        C.snapUntil = GetGameTimer() + ms + 150
    end
    C.cur = to
end

-- --------------------------------------------------------------------------
--  Orbita
-- --------------------------------------------------------------------------
local function wrapAngle(a)
    while a > math.pi do a = a - 2.0 * math.pi end
    while a < -math.pi do a = a + 2.0 * math.pi end
    return a
end

-- minimalny dystans od środka w danym kierunku (elipsa obrysu + margines)
local function minDistAt(d, yaw)
    local cx, sy = math.cos(yaw), math.sin(yaw)
    local r = 1.0 / math.sqrt((cx / d.h.x) ^ 2 + (sy / d.h.y) ^ 2)
    return r + 0.95
end

local function maxDist(d)
    return Utils.Clamp(math.max(d.h.x, d.h.y) * 3.3, 6.0, 15.0)
end

-- kąty orbity (lokalne względem auta) dla punktu lokalnego
local function orbitAnglesFor(d, lp)
    local rx, ry, rz = lp.x - d.c.x, lp.y - d.c.y, lp.z - d.c.z
    local dist = math.sqrt(rx * rx + ry * ry + rz * rz)
    if dist < 0.01 then dist = 0.01 end
    return math.atan(ry, rx), math.asin(Utils.Clamp(rz / dist, -1.0, 1.0)), dist
end

local function orbitBegin()
    if not vehOk(C.veh) then return false end
    local d = dims(C.veh)
    local pos, rot, fov = renderedPose()
    local yaw, pitch, dist = orbitAnglesFor(d, toLocal(C.veh, pos))
    C.orb = {
        yaw = yaw, pitch = pitch, dist = dist,
        tYaw = yaw, tPitch = pitch, tDist = dist,
        vYaw = 0.0, vPitch = 0.0,
        fov = fov, lastT = GetGameTimer(),
    }
    if C.cur then C.trash[#C.trash + 1] = C.cur end
    if C.snap then C.trash[#C.trash + 1] = C.snap end
    local cam = newCam(pos, rot, fov)
    SetCamActive(cam, true)
    flushTrash(cam)
    C.cur, C.snap, C.tgt = cam, nil, nil
    return true
end

local function orbitRetarget(lp)
    if not C.orb or not vehOk(C.veh) then return end
    local d = dims(C.veh)
    local yaw, pitch, dist = orbitAnglesFor(d, lp)
    local o = C.orb
    o.tYaw = o.yaw + wrapAngle(yaw - o.yaw)
    o.tPitch, o.tDist = pitch, Utils.Clamp(dist, minDistAt(d, yaw), maxDist(d))
    o.vYaw, o.vPitch = 0.0, 0.0
end

local function orbitTick(now)
    local o, veh = C.orb, C.veh
    if not o or not vehOk(veh) then return end
    local dt = Utils.Clamp((now - o.lastT) / 1000.0, 0.0, 0.1)
    o.lastT = now
    local d = dims(veh)

    -- wejście: PPM = obrót (kursor NUI zostaje, gra dostaje ruch myszy przez keepInput)
    if IsDisabledControlPressed(0, 25) then
        local mx = GetDisabledControlNormal(0, 1)
        local my = GetDisabledControlNormal(0, 2)
        local dy, dp = -math.rad(mx * ORBIT_SENS_YAW), math.rad(my * ORBIT_SENS_PITCH)
        o.tYaw = o.tYaw + dy
        o.tPitch = o.tPitch + dp
        if dt > 0 then
            o.vYaw = Utils.Lerp(o.vYaw, dy / dt, 0.5)
            o.vPitch = Utils.Lerp(o.vPitch, dp / dt, 0.5)
        end
    else
        -- bezwładność po puszczeniu PPM
        local k = math.exp(-ORBIT_INERTIA * dt)
        o.vYaw, o.vPitch = o.vYaw * k, o.vPitch * k
        if math.abs(o.vYaw) > 0.002 then o.tYaw = o.tYaw + o.vYaw * dt end
        if math.abs(o.vPitch) > 0.002 then o.tPitch = o.tPitch + o.vPitch * dt end
    end

    if IsDisabledControlJustPressed(0, 241) or IsDisabledControlJustPressed(0, 15) then
        o.tDist = o.tDist * (1.0 - ZOOM_STEP)
    elseif IsDisabledControlJustPressed(0, 242) or IsDisabledControlJustPressed(0, 14) then
        o.tDist = o.tDist * (1.0 + ZOOM_STEP)
    end

    -- ograniczenia zależne od auta (rozmiar, podniesienie, podłoga)
    local clr, groundZ = clearance(veh)
    local lifted = clr >= LIFTED_MIN
    local maxP = math.rad(78.0)
    local minP = lifted and math.rad(-42.0) or math.rad(-6.0)
    o.tPitch = Utils.Clamp(o.tPitch, minP, maxP)
    o.tDist = Utils.Clamp(o.tDist, minDistAt(d, o.tYaw), maxDist(d))

    local k = 1.0 - math.exp(-ORBIT_SMOOTH * dt)
    o.yaw = o.yaw + (o.tYaw - o.yaw) * k
    o.pitch = o.pitch + (o.tPitch - o.pitch) * k
    o.dist = o.dist + (o.tDist - o.dist) * k
    o.fov = o.fov + (ORBIT_FOV - o.fov) * k
    local dist = math.max(o.dist, minDistAt(d, o.yaw))

    local center = toWorld(veh, d.c)
    -- kamera nie schodzi pod podłogę
    local pitch = o.pitch
    local minZ = groundZ + 0.22
    if center.z + math.sin(pitch) * dist < minZ then
        pitch = math.asin(Utils.Clamp((minZ - center.z) / dist, -1.0, 1.0))
    end
    local cp = math.cos(pitch)
    local lp = vec3(d.c.x + math.cos(o.yaw) * cp * dist, d.c.y + math.sin(o.yaw) * cp * dist, d.c.z + math.sin(pitch) * dist)
    local pos = toWorld(veh, lp)
    setCamPose(C.cur, pos, center, o.fov)
    C.lastPos, C.lastLook = pos, center
end

local ORBIT_BLOCK = { 1, 2, 24, 25, 14, 15, 16, 17, 241, 242, 200 }

-- --------------------------------------------------------------------------
--  Wątek kamery (tylko gdy aktywna)
-- --------------------------------------------------------------------------
local function runThread(gen)
    CreateThread(function()
        while C.active and C.gen == gen do
            local now = GetGameTimer()
            if C.orbit then
                for i = 1, #ORBIT_BLOCK do DisableControlAction(0, ORBIT_BLOCK[i], true) end
                if vehOk(C.veh) then orbitTick(now) end
            elseif C.tgt and C.cur then
                local pos, look = resolveTarget(C.tgt)
                if pos and look then setCamPose(C.cur, pos, look, nil) end
            end
            -- sprzątanie migawki po przelocie
            if C.snap and now > C.snapUntil and C.cur and not IsCamInterpolating(C.cur) then
                destroy(C.snap)
                C.snap = nil
            end
            Wait(0)
        end
    end)
end

-- --------------------------------------------------------------------------
--  API
-- --------------------------------------------------------------------------
function DPM.Camera.Active() return C.active end
function DPM.Camera.IsOrbit() return C.active and C.orbit end
function DPM.Camera.Vehicle() return C.veh end
function DPM.Camera.Preset() return C.preset end

function DPM.Camera.Start(veh, noFocus)
    if not vehOk(veh) then return false end
    if C.active then
        if C.veh ~= veh then
            C.veh = veh
            local _, g = clearance(veh)
            C.ground = g
            if not noFocus then
                if C.orbit then orbitBegin() else DPM.Camera.Focus('overview', 900) end
            end
        end
        return true
    end
    C.gen = C.gen + 1
    C.active, C.veh, C.orbit, C.orb, C.tgt, C.preset = true, veh, false, nil, nil, nil
    local _, g = clearance(veh)
    C.ground = g
    -- start dokładnie z pozy kamery gry – bez przeskoku
    local pos, rot, fov = GetGameplayCamCoord(), GetGameplayCamRot(2), GetGameplayCamFov()
    local cam = newCam(pos, rot, fov)
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, true)
    C.cur, C.snap = cam, nil
    C.lastPos, C.lastLook = pos, pos
    runThread(C.gen)
    if not noFocus then DPM.Camera.Focus('overview', 1100) end
    return true
end

function DPM.Camera.Stop(ms)
    if not C.active then return end
    ms = math.max(0, math.floor(tonumber(ms) or 800))
    C.active = false
    C.gen = C.gen + 1
    C.orbit, C.orb, C.tgt, C.preset = false, nil, nil, nil
    RenderScriptCams(false, ms > 0, ms, true, true)
    local list = { C.cur, C.snap }
    for i = 1, #C.trash do list[#list + 1] = C.trash[i] end
    C.cur, C.snap, C.trash, C.veh = nil, nil, {}, nil
    SetTimeout(ms + 50, function()
        for i = 1, #list do destroy(list[i]) end
    end)
end

function DPM.Camera.Focus(preset, ms)
    if not C.active or not vehOk(C.veh) then return false end
    local veh = C.veh
    local p = Config.CamPresets[preset] or Config.CamPresets.overview
    local name = Config.CamPresets[preset] and preset or 'overview'
    -- widok od spodu tylko gdy auto jest podniesione
    if p.under then
        local clr = clearance(veh)
        if clr < LIFTED_MIN then
            name = p.fallback or 'side_l'
            p = Config.CamPresets[name] or Config.CamPresets.side_l
        end
    end
    local d = dims(veh)
    local pos = Utils.BoxOffset(d.min, d.max, p.pos)
    local look = Utils.BoxOffset(d.min, d.max, p.look)
    if p.bone then
        local bi = GetEntityBoneIndexByName(veh, p.bone)
        if bi ~= -1 then look = toLocal(veh, GetWorldPositionOfEntityBone(veh, bi)) end
    end
    local _, g = clearance(veh)
    C.ground = g
    C.preset = name
    if C.orbit then
        orbitRetarget(pos)
        return true
    end
    flyTo({ mode = 'local', pos = pos, look = look, fov = p.fov or 45.0 }, ms or 900)
    return true
end

function DPM.Camera.FocusWorld(from, look, fov, ms)
    if not C.active then
        -- kamera świata bez auta (np. maszyna do opon)
        C.gen = C.gen + 1
        C.active, C.veh, C.orbit, C.orb = true, nil, false, nil
        local pos, rot, f = GetGameplayCamCoord(), GetGameplayCamRot(2), GetGameplayCamFov()
        local cam = newCam(pos, rot, f)
        SetCamActive(cam, true)
        RenderScriptCams(true, false, 0, true, true)
        C.cur, C.snap = cam, nil
        runThread(C.gen)
    end
    C.orbit, C.orb, C.preset = false, nil, nil
    C.ground = nil
    flyTo({ mode = 'world', pos = vec3(from.x, from.y, from.z), look = vec3(look.x, look.y, look.z), fov = fov or 45.0 }, ms or 900)
    return true
end

function DPM.Camera.SetOrbit(on)
    on = on == true
    if not C.active then return false end
    if on == C.orbit then return true end
    if on then
        if not orbitBegin() then return false end
        C.orbit = true
    else
        C.orbit = false
        -- zostajemy w bieżącej pozie, dalej „przyklejeni” do auta
        if vehOk(C.veh) then
            local d = dims(C.veh)
            local pos = renderedPose()
            C.orb = nil
            flyTo({ mode = 'local', pos = toLocal(C.veh, pos), look = d.c, fov = GetFinalRenderedCamFov() }, 0)
        else
            C.orb = nil
        end
    end
    return true
end

function DPM.Camera.GetCoord()
    if C.active then return GetFinalRenderedCamCoord() end
    return GetGameplayCamCoord()
end

function DPM.Camera.GetRot()
    if C.active then return GetFinalRenderedCamRot(2) end
    return GetGameplayCamRot(2)
end

-- pozycja miejsca montażu w świecie
function DPM.Camera.AnchorWorld(veh, anchorName, wheel)
    if not vehOk(veh) then return nil end
    local a = Config.Anchors[anchorName]
    local d = dims(veh)
    if not a then return toWorld(veh, d.c) end
    if a.wheel then
        return DPM.WheelPos(veh, Utils.Clamp(tonumber(wheel) or 1, 1, 4))
    end
    for _, bone in ipairs(a.bones or {}) do
        local bi = GetEntityBoneIndexByName(veh, bone)
        if bi ~= -1 then
            local bp = GetWorldPositionOfEntityBone(veh, bi)
            if a.boneOff then
                local l = toLocal(veh, bp)
                return toWorld(veh, vec3(l.x + a.boneOff.x, l.y + a.boneOff.y, l.z + a.boneOff.z))
            end
            return bp
        end
    end
    return toWorld(veh, Utils.BoxOffset(d.min, d.max, a.off or vec3(0.0, 0.0, 0.0)))
end

function DPM.Camera.ScreenOf(world)
    if not world then return nil end
    local on, x, y = GetScreenCoordFromWorldCoord(world.x, world.y, world.z)
    if not on then return nil end
    return x, y
end

-- kamera patrząca na miejsce montażu z zewnątrz auta (dla 'under' – od dołu)
function DPM.Camera.FocusAnchor(veh, anchorName, wheel, ms)
    if not vehOk(veh) then return false end
    if not C.active or C.veh ~= veh then DPM.Camera.Start(veh, true) end
    if C.orbit then C.orbit, C.orb = false, nil end
    local a = Config.Anchors[anchorName] or {}
    local d = dims(veh)
    local w = DPM.Camera.AnchorWorld(veh, anchorName, wheel)
    local l = toLocal(veh, w)
    local dist = Utils.Clamp(1.6 + (a.size or 0.5) * 0.9, 1.6, 2.4)
    local clr, g = clearance(veh)
    C.ground = g
    local pos

    if a.under then
        if clr >= LIFTED_MIN then
            -- spod auta: z boku-dołu, pod lekkim kątem
            local side = (l.x >= d.c.x) and 1.0 or -1.0
            local downZ = math.max(d.min.z - 1.25, d.min.z - clr + 0.35)
            pos = vec3(l.x + side * 0.85, l.y - 0.7, downZ)
        else
            -- auto na ziemi: nisko z boku, zaglądając pod próg
            local side = (l.x >= d.c.x) and 1.0 or -1.0
            pos = vec3(side * (d.h.x + dist), l.y + 0.35, d.min.z + 0.28)
        end
    else
        -- kierunek „na zewnątrz” w przestrzeni połówek bryły
        local rx = (l.x - d.c.x) / d.h.x
        local ry = (l.y - d.c.y) / d.h.y
        local rz = (l.z - d.c.z) / d.h.z
        local dx, dy, dz = rx * d.h.x, ry * d.h.y, rz * d.h.z * 0.35
        local len = math.sqrt(dx * dx + dy * dy + dz * dz)
        if len < 0.25 then dx, dy, dz, len = -1.0, 0.35, 0.0, 1.06 end
        dx, dy, dz = dx / len, dy / len, dz / len + 0.45
        len = math.sqrt(dx * dx + dy * dy + dz * dz)
        dx, dy, dz = dx / len, dy / len, dz / len
        pos = vec3(l.x + dx * dist, l.y + dy * dist, l.z + dz * dist)
        -- wypchnij poza bryłę auta (kamera nie może być w karoserii)
        for _ = 1, 16 do
            local inside = math.abs(pos.x - d.c.x) < d.h.x + 0.3 and math.abs(pos.y - d.c.y) < d.h.y + 0.3
                and pos.z < d.max.z + 0.15 and pos.z > d.min.z - 0.2
            if not inside then break end
            pos = vec3(pos.x + dx * 0.25, pos.y + dy * 0.25, pos.z + dz * 0.25)
        end
    end

    C.preset = nil
    flyTo({ mode = 'local', pos = pos, look = l, fov = Utils.Clamp(38.0 + (a.size or 0.5) * 12.0, 36.0, 52.0) }, ms or 900)
    return true
end

-- --------------------------------------------------------------------------
--  Sprzątanie
-- --------------------------------------------------------------------------
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if C.active or C.cur then
        RenderScriptCams(false, false, 0, true, true)
        destroy(C.cur)
        destroy(C.snap)
        for i = 1, #C.trash do destroy(C.trash[i]) end
        C.active = false
    end
end)
