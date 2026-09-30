-- ==========================================================================
--  dp-mechanic – podnośniki (klient)
--  Geometria rysowana DrawPoly (cieniowane prostopadłościany), animacja
--  wysokości (deterministycznie, Config.Lifts.speed), trzymanie auta przez
--  właściciela sieciowego, panel sterowania (NUI lift.js).
--  Stan serwera: 'lift:all', 'lift:set', 'dp-mechanic:lift:state', 'dp-mechanic:lift:lowered'.
-- ==========================================================================
DPM.Lifts = {}

local LC = Config.Lifts or {}
local SPEED = tonumber(LC.speed) or 0.22
local DRIVE_ON = tonumber(LC.driveOnRadius) or 2.2
local DRAW_DIST = 40.0
local DETAIL_DIST = 22.0          -- drobne detale (sworznie, siłowniki) tylko z bliska
local PANEL_CLOSE = 4.0
local QUICK_DIST = 1.8            -- sterowanie klawiszami bez otwierania panelu
local RAMP_CLIMB = 0.15           -- na tej wysokości auto „wjeżdża” na grubość szyn
local ARMS_LIFT = 0.05            -- dodatkowy docisk poduszek ramion
local WORK_HEIGHT = { ramp = 1.8, arms = 1.2 }
local TYPE_LABEL = { ramp = 'Podnośnik najazdowy', arms = 'Podnośnik dwukolumnowy' }
local TYPE_NEED = { ramp = 'podnośnik najazdowy (rampa)', arms = 'podnośnik dwukolumnowy (ramiona)' }

local sin, cos, sqrt, abs, floor, rad, atan = math.sin, math.cos, math.sqrt, math.abs, math.floor, math.rad, math.atan
local DrawPoly = DrawPoly

local lifts, order = {}, {}
local panel = nil                 -- { key }
local quick = nil                 -- { key, dir } – sterowanie klawiszami przy panelu

-- --------------------------------------------------------------------------
--  Inicjalizacja podnośników z configu
-- --------------------------------------------------------------------------
for wsId, ws in pairs(Config.Workshops) do
    for idx, l in ipairs(ws.lifts or {}) do
        local key = wsId .. ':' .. idx
        local t = (l.type == 'arms') and 'arms' or 'ramp'
        local hd = rad(l.coords.w or 0.0)
        local lf = {
            key = key, ws = wsId, wsLabel = ws.label or wsId, idx = idx, cfg = l, type = t,
            geo = LC[t] or {},
            max = tonumber(l.maxHeight) or 1.8,
            origin = vec3(l.coords.x, l.coords.y, l.coords.z),
            heading = l.coords.w or 0.0,
            fx = -sin(hd), fy = cos(hd),   -- przód podnośnika
            rx = cos(hd), ry = sin(hd),    -- prawa strona
            floor = nil, floorTries = 0,
            h = 0.0, target = 0.0, veh = nil, by = nil,
            ent = nil, entAt = 0, vehAt = 0, rest = nil, frozen = nil, reported = true,
            pads = nil, sending = false, queued = nil, dist = 1e9, prop = nil,
        }
        lf.label = l.label or (TYPE_LABEL[t] .. ' #' .. idx)
        lifts[key] = lf
        order[#order + 1] = lf
    end
end

local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function myServerId() return GetPlayerServerId(PlayerId()) end

-- --------------------------------------------------------------------------
--  Geometria pomocnicza (lokalny układ podnośnika: x w prawo, y w przód, z w górę od podłogi)
-- --------------------------------------------------------------------------
local camX, camY, camZ = 0.0, 0.0, 0.0
local LX, LY, LZ
do
    local lx, ly, lz = 0.35, 0.45, 0.82
    local l = sqrt(lx * lx + ly * ly + lz * lz)
    LX, LY, LZ = lx / l, ly / l, lz / l
end

-- jedna ściana: środek p, półwektory a i b w płaszczyźnie, normalna n (jednostkowa)
-- rysowana tylko gdy zwrócona do kamery; obie kolejności wierzchołków = zawsze widoczna
local function face(px, py, pz, ax, ay, az, bx, by, bz, nx, ny, nz, r, g, b, alpha)
    if nx * (camX - px) + ny * (camY - py) + nz * (camZ - pz) <= 0.0 then return end
    local l = nx * LX + ny * LY + nz * LZ
    if l < 0.0 then l = 0.0 end
    local s = 0.4 + 0.6 * l
    if nz < -0.5 then s = s * 0.7 end
    local cr, cg, cb = floor(r * s), floor(g * s), floor(b * s)
    local x1, y1, z1 = px - ax - bx, py - ay - by, pz - az - bz
    local x2, y2, z2 = px + ax - bx, py + ay - by, pz + az - bz
    local x3, y3, z3 = px + ax + bx, py + ay + by, pz + az + bz
    local x4, y4, z4 = px - ax + bx, py - ay + by, pz - az + bz
    DrawPoly(x1, y1, z1, x2, y2, z2, x3, y3, z3, cr, cg, cb, alpha)
    DrawPoly(x3, y3, z3, x2, y2, z2, x1, y1, z1, cr, cg, cb, alpha)
    DrawPoly(x1, y1, z1, x3, y3, z3, x4, y4, z4, cr, cg, cb, alpha)
    DrawPoly(x4, y4, z4, x3, y3, z3, x1, y1, z1, cr, cg, cb, alpha)
end

-- prostopadłościan: środek c, półosie u, v, w (wzajemnie prostopadłe, w metrach)
local function box(cx, cy, cz, ux, uy, uz, vx, vy, vz, wx, wy, wz, col)
    local r, g, b, a = col[1], col[2], col[3], col[4] or 255
    local lu = sqrt(ux * ux + uy * uy + uz * uz)
    local lv = sqrt(vx * vx + vy * vy + vz * vz)
    local lw = sqrt(wx * wx + wy * wy + wz * wz)
    if lu < 1e-4 or lv < 1e-4 or lw < 1e-4 then return end
    local nux, nuy, nuz = ux / lu, uy / lu, uz / lu
    local nvx, nvy, nvz = vx / lv, vy / lv, vz / lv
    local nwx, nwy, nwz = wx / lw, wy / lw, wz / lw
    face(cx + ux, cy + uy, cz + uz, vx, vy, vz, wx, wy, wz, nux, nuy, nuz, r, g, b, a)
    face(cx - ux, cy - uy, cz - uz, wx, wy, wz, vx, vy, vz, -nux, -nuy, -nuz, r, g, b, a)
    face(cx + vx, cy + vy, cz + vz, wx, wy, wz, ux, uy, uz, nvx, nvy, nvz, r, g, b, a)
    face(cx - vx, cy - vy, cz - vz, ux, uy, uz, wx, wy, wz, -nvx, -nvy, -nvz, r, g, b, a)
    face(cx + wx, cy + wy, cz + wz, ux, uy, uz, vx, vy, vz, nwx, nwy, nwz, r, g, b, a)
    face(cx - wx, cy - wy, cz - wz, vx, vy, vz, ux, uy, uz, -nwx, -nwy, -nwz, r, g, b, a)
end

-- prostopadłościan w układzie podnośnika: środek (x,y,z), półwymiary, obrót yaw (wokół z) i pitch (pochylenie długości)
local function lbox(lf, x, y, z, hx, hy, hz, yaw, pitch, col)
    local rx, ry, fx, fy = lf.rx, lf.ry, lf.fx, lf.fy
    local cy_, sy_ = 1.0, 0.0
    if yaw and yaw ~= 0.0 then cy_, sy_ = cos(yaw), sin(yaw) end
    local cp, sp = 1.0, 0.0
    if pitch and pitch ~= 0.0 then cp, sp = cos(pitch), sin(pitch) end
    -- półosie w układzie lokalnym
    local ux, uy, uz = cy_ * hx, sy_ * hx, 0.0
    local vx, vy, vz = -sy_ * cp * hy, cy_ * cp * hy, sp * hy
    local wx, wy, wz = sy_ * sp * hz, -cy_ * sp * hz, cp * hz
    -- do świata
    local ox, oy, oz = lf.origin.x, lf.origin.y, lf.floor or lf.origin.z
    box(ox + rx * x + fx * y, oy + ry * x + fy * y, oz + z,
        rx * ux + fx * uy, ry * ux + fy * uy, uz,
        rx * vx + fx * vy, ry * vx + fy * vy, vz,
        rx * wx + fx * wy, ry * wx + fy * wy, wz, col)
end

-- belka między dwoma punktami lokalnymi (w płaszczyźnie y-z lub dowolnej)
local function segment(lf, x1, y1, z1, x2, y2, z2, hw, hh, col)
    local dx, dy, dz = x2 - x1, y2 - y1, z2 - z1
    local len = sqrt(dx * dx + dy * dy + dz * dz)
    if len < 0.01 then return end
    local flat = sqrt(dx * dx + dy * dy)
    local yaw = atan(-dx, dy)
    if flat < 1e-4 then yaw = 0.0 end
    local pitch = atan(dz, flat)
    lbox(lf, (x1 + x2) * 0.5, (y1 + y2) * 0.5, (z1 + z2) * 0.5, hw, len * 0.5, hh, yaw, pitch, col)
end

local function rgb(t, def)
    if type(t) == 'table' and t[1] then return { t[1], t[2], t[3], 255 } end
    return def
end

local COL_DARK = { 30, 34, 40, 255 }
local COL_RUBBER = { 20, 20, 22, 255 }
local COL_CHROME = { 176, 182, 190, 255 }
local COL_STEEL = { 96, 102, 112, 255 }
local COL_HAZARD = { 240, 196, 40, 255 }

-- --------------------------------------------------------------------------
--  Podłoga pod podnośnikiem (sonda raz – taka sama u wszystkich klientów)
-- --------------------------------------------------------------------------
local function probeFloor(lf)
    if lf.floor or lf.floorTries > 8 then return end
    lf.floorTries = lf.floorTries + 1
    local o = lf.origin
    local found, z = GetGroundZFor_3dCoord(o.x, o.y, o.z + 1.5, false)
    if found and abs(z - o.z) < 0.6 then
        lf.floor = z
    elseif lf.floorTries > 8 then
        lf.floor = o.z
    end
end

-- --------------------------------------------------------------------------
--  Rysowanie: rampa najazdowa
-- --------------------------------------------------------------------------
local function drawRamp(lf, detail)
    local g = lf.geo
    local L = tonumber(g.length) or 5.2
    local W = tonumber(g.width) or 2.6
    local rw = tonumber(g.railWidth) or 0.62
    local t = tonumber(g.thickness) or 0.12
    local base = lf.colBase
    local acc = lf.colAcc
    local h = lf.h
    local railX = W * 0.5 - rw * 0.5
    local scis = math.min(L * 0.72, 3.8)
    local hEff = clamp(h, 0.0, scis * 0.95)
    local span = sqrt(scis * scis - hEff * hEff)
    local pitch = atan(hEff, span)
    local hasProp = lf.prop ~= nil

    for s = -1, 1, 2 do
        local x = railX * s
        if not hasProp then
            -- szyna najazdowa
            lbox(lf, x, 0.0, h + t * 0.5, rw * 0.5, L * 0.5, t * 0.5, 0.0, 0.0, base)
            -- krawędź zewnętrzna (akcent) i odbój kół z przodu
            lbox(lf, x + s * (rw * 0.5 - 0.025), 0.0, h + t + 0.03, 0.025, L * 0.5, 0.03, 0.0, 0.0, acc)
            lbox(lf, x, L * 0.5 - 0.09, h + t + 0.05, rw * 0.5 - 0.05, 0.05, 0.05, 0.0, 0.0, COL_DARK)
            -- najazd z tyłu (zawias na końcu szyny): leży na podłodze, po podniesieniu staje jako blokada
            local ar = 0.75
            local drop = h + t
            local down = math.asin(clamp(drop / ar, 0.0, 0.98))
            local up = rad(-72.0)
            local k = clamp((h - 0.45) / 0.25, 0.0, 1.0)
            local ang = down + (up - down) * k
            local cp, sp = cos(ang), sin(ang)
            local hy, hz = -L * 0.5, h + t
            lbox(lf, x, hy - cp * ar * 0.5, hz - sp * ar * 0.5, rw * 0.5 - 0.03, ar * 0.5, 0.018, 0.0, ang, COL_STEEL)
            if detail then
                -- pasy ostrzegawcze na najeździe
                lbox(lf, x, hy - cp * ar * 0.8, hz - sp * ar * 0.8 + cp * 0.02, rw * 0.5 - 0.06, 0.04, 0.006, 0.0, ang, COL_HAZARD)
            end
        end

        if h > 0.02 then
            -- nożyce (dwie belki na krzyż, lekko przesunięte w x)
            local zc = h * 0.5 + 0.02
            lbox(lf, x - 0.1, 0.0, zc, 0.05, scis * 0.5, 0.05, 0.0, pitch, COL_DARK)
            lbox(lf, x + 0.1, 0.0, zc, 0.05, scis * 0.5, 0.05, 0.0, -pitch, COL_DARK)
            -- rama bazowa na podłodze
            lbox(lf, x, 0.0, 0.02, rw * 0.5 - 0.06, span * 0.5 + 0.12, 0.02, 0.0, 0.0, base)
            if detail then
                -- sworzeń środkowy
                lbox(lf, x, 0.0, zc, 0.17, 0.05, 0.05, 0.0, 0.0, acc)
                -- siłownik hydrauliczny: cylinder + tłoczysko
                if h > 0.12 then
                    local y0, z0 = -span * 0.36, 0.08
                    local y1, z1 = 0.0, zc
                    local ym, zm = y0 + (y1 - y0) * 0.55, z0 + (z1 - z0) * 0.55
                    segment(lf, x, y0, z0, x, ym, zm, 0.055, 0.055, COL_DARK)
                    segment(lf, x, ym, zm, x, y1, z1, 0.025, 0.025, COL_CHROME)
                end
            end
        end
    end
end

-- --------------------------------------------------------------------------
--  Rysowanie: podnośnik dwukolumnowy na ramionach
-- --------------------------------------------------------------------------
local DEF_PADS = { { -0.72, 0.95 }, { -0.72, -0.95 }, { 0.72, 0.95 }, { 0.72, -0.95 } }

local function angDiff(a, b)
    local d = b - a
    while d > math.pi do d = d - 2.0 * math.pi end
    while d < -math.pi do d = d + 2.0 * math.pi end
    return d
end

local function drawArms(lf, detail)
    local g = lf.geo
    local gap = tonumber(g.columnGap) or 3.3
    local cs = tonumber(g.columnSize) or 0.34
    local H = tonumber(g.columnHeight) or 3.3
    local armLen = tonumber(g.armLength) or 1.1
    local base = lf.colBase
    local acc = lf.colAcc
    local h = lf.h
    local hasProp = lf.prop ~= nil
    local colX = gap * 0.5

    if not hasProp then
        for s = -1, 1, 2 do
            local x = colX * s
            lbox(lf, x, 0.0, H * 0.5, cs * 0.5, cs * 0.5, H * 0.5, 0.0, 0.0, base)
            lbox(lf, x, 0.0, 0.015, cs * 0.5 + 0.12, cs * 0.5 + 0.12, 0.015, 0.0, 0.0, COL_DARK)
            lbox(lf, x, 0.0, H + 0.04, cs * 0.5 + 0.02, cs * 0.5 + 0.02, 0.04, 0.0, 0.0, acc)
            if detail then
                -- pionowy pas akcentu na froncie kolumny
                lbox(lf, x, cs * 0.5 + 0.004, H * 0.55, cs * 0.18, 0.004, H * 0.35, 0.0, 0.0, acc)
            end
        end
        -- osłona przewodów na podłodze (auto przejeżdża po niej)
        lbox(lf, 0.0, 0.0, 0.012, colX - cs * 0.5, 0.2, 0.012, 0.0, 0.0, COL_DARK)
        if detail then
            -- silnik hydrauliczny na lewej kolumnie
            lbox(lf, -colX - cs * 0.5 - 0.11, 0.0, 1.1, 0.1, 0.16, 0.22, 0.0, 0.0, COL_STEEL)
        end
    end

    -- wózki (suwaki) na wewnętrznej stronie kolumn
    local zc = h + 0.36
    for s = -1, 1, 2 do
        lbox(lf, s * (colX - cs * 0.5 - 0.07), 0.0, zc, 0.07, 0.25, 0.3, 0.0, 0.0, acc)
    end

    -- ramiona: obrót do środka w trakcie pierwszych centymetrów podnoszenia
    local k = clamp(h / 0.12, 0.0, 1.0)
    k = k * k * (3.0 - 2.0 * k)
    local pads = lf.pads or DEF_PADS
    local armZ = h + 0.1
    for i = 1, 4 do
        local sx = (i <= 2) and -1 or 1
        local sy = (i % 2 == 1) and 1 or -1
        local px, py = sx * (colX - cs * 0.5 - 0.1), sy * 0.16
        -- kąt spoczynkowy: wzdłuż kolumny, lekko na zewnątrz
        local restYaw = (sy > 0) and (sx * -0.14) or (math.pi + sx * 0.14)
        local tx, ty = pads[i][1], pads[i][2]
        local dx, dy = tx - px, ty - py
        local tYaw = atan(-dx, dy)
        local tLen = clamp(sqrt(dx * dx + dy * dy), 0.7, armLen * 1.45)
        local yaw = restYaw + angDiff(restYaw, tYaw) * k
        local len = armLen * 0.85 + (tLen - armLen * 0.85) * k
        local vx, vy = -sin(yaw), cos(yaw)
        local outer = math.min(len, armLen * 0.62)
        -- część zewnętrzna (gruba) i wysuw teleskopowy
        lbox(lf, px + vx * outer * 0.5, py + vy * outer * 0.5, armZ, 0.075, outer * 0.5, 0.045, yaw, 0.0, base)
        if len > outer then
            local inner = len - outer + 0.12
            local c0 = outer - 0.12
            lbox(lf, px + vx * (c0 + inner * 0.5), py + vy * (c0 + inner * 0.5), armZ + 0.005, 0.058, inner * 0.5, 0.037, yaw, 0.0, COL_STEEL)
        end
        -- poduszka gumowa pod progiem
        local ex, ey = px + vx * len, py + vy * len
        lbox(lf, ex, ey, armZ + 0.045 + 0.05, 0.085, 0.085, 0.05, yaw, 0.0, COL_RUBBER)
        if detail then
            lbox(lf, ex, ey, armZ + 0.045 + 0.105, 0.07, 0.07, 0.006, yaw, 0.0, acc)
            -- sworzeń obrotu ramienia
            lbox(lf, px, py, armZ + 0.02, 0.05, 0.05, 0.075, 0.0, 0.0, COL_CHROME)
        end
    end
end

-- --------------------------------------------------------------------------
--  Opcjonalny prop podnośnika (Config.Lifts.<typ>.model)
-- --------------------------------------------------------------------------
local function ensureProp(lf)
    local model = lf.geo.model
    if not model or lf.prop or lf.propFailed then return end
    local hash = DPM.LoadModel(model)
    if not hash then lf.propFailed = true return end
    local o = lf.origin
    local obj = CreateObject(hash, o.x, o.y, (lf.floor or o.z), false, false, false)
    SetEntityHeading(obj, lf.heading)
    FreezeEntityPosition(obj, true)
    SetEntityCollision(obj, false, false)
    SetModelAsNoLongerNeeded(hash)
    lf.prop, lf.propH = obj, -1.0
end

local function removeProp(lf)
    if lf.prop then DPM.DeleteEntity(lf.prop) end
    lf.prop, lf.propH = nil, nil
end

local function updateProp(lf)
    if not lf.prop or lf.type ~= 'ramp' then return end
    if abs((lf.propH or -1) - lf.h) < 0.001 then return end
    local o = lf.origin
    SetEntityCoordsNoOffset(lf.prop, o.x, o.y, (lf.floor or o.z) + lf.h, false, false, false)
    lf.propH = lf.h
end

-- --------------------------------------------------------------------------
--  Auto na podnośniku
-- --------------------------------------------------------------------------
local function carOffset(lf, h)
    if h <= 0.0 then return 0.0 end
    if lf.type == 'ramp' then
        local t = tonumber(lf.geo.thickness) or 0.12
        return h + t * clamp(h / RAMP_CLIMB, 0.0, 1.0)
    end
    return h + ARMS_LIFT * clamp(h / 0.1, 0.0, 1.0)
end

local function resolveEnt(lf, now)
    if not lf.veh then lf.ent = nil return nil end
    if lf.ent and now - lf.entAt < 1000 and DoesEntityExist(lf.ent) then return lf.ent end
    lf.entAt = now
    lf.ent = nil
    if NetworkDoesNetworkIdExist(lf.veh) then
        local e = NetworkGetEntityFromNetworkId(lf.veh)
        if e and e ~= 0 and DoesEntityExist(e) and GetEntityType(e) == 2 then lf.ent = e end
    end
    return lf.ent
end

-- Z „spoczynkowe” auta (stoi na podłodze): zapamiętane przy wiązaniu albo wyliczone z bryły
local function restZ(lf, e)
    if lf.rest and lf.rest.ent == e then return lf.rest.z end
    local min = GetModelDimensions(GetEntityModel(e))
    return (lf.floor or lf.origin.z) - min.z
end

local function captureRest(lf, e)
    if lf.rest and lf.rest.ent == e then return end
    if lf.h > 0.05 then return end
    local c = GetEntityCoords(e)
    local expected = (lf.floor or lf.origin.z) - GetModelDimensions(GetEntityModel(e)).z
    local z = c.z - carOffset(lf, lf.h)
    -- odrzucamy nierealne odczyty (np. auto jeszcze spada)
    if abs(z - expected) > 0.6 then z = expected end
    lf.rest = { ent = e, z = z, heading = GetEntityHeading(e) }
end

-- punkty podparcia progów (do ramion) w układzie podnośnika
local function computePads(lf, e)
    local min, max = GetModelDimensions(GetEntityModel(e))
    local hx = (max.x - min.x) * 0.5
    local hy = (max.y - min.y) * 0.5
    local cx, cy = (min.x + max.x) * 0.5, (min.y + max.y) * 0.5
    local px = math.max(0.35, hx - 0.2)
    local py = hy * 0.5
    local raw = {}
    for i, p in ipairs({ { -px, py }, { -px, -py }, { px, py }, { px, -py } }) do
        local w = GetOffsetFromEntityInWorldCoords(e, cx + p[1], cy + p[2], 0.0)
        local dx, dy = w.x - lf.origin.x, w.y - lf.origin.y
        raw[i] = { dx * lf.rx + dy * lf.ry, dx * lf.fx + dy * lf.fy }
    end
    -- przypisanie do ramion wg stron (auto może stać tyłem)
    table.sort(raw, function(a, b) return a[1] < b[1] end)
    local left = { raw[1], raw[2] }
    local right = { raw[3], raw[4] }
    table.sort(left, function(a, b) return a[2] > b[2] end)
    table.sort(right, function(a, b) return a[2] > b[2] end)
    lf.pads = { left[1], left[2], right[1], right[2] }
end

local function isOwner(e)
    return NetworkGetEntityOwner(e) == PlayerId()
end

local function unfreezeLocal(lf, e)
    if not e or not DoesEntityExist(e) then return end
    if not isOwner(e) then return end
    if IsEntityPositionFrozen(e) then
        local c = GetEntityCoords(e)
        SetEntityCoordsNoOffset(e, c.x, c.y, restZ(lf, e) + 0.03, false, false, false)
        FreezeEntityPosition(e, false)
        SetVehicleOnGroundProperly(e)
    end
end

local function handleVehicle(lf, now)
    local e = resolveEnt(lf, now)
    if not e then return end
    captureRest(lf, e)
    if lf.type == 'arms' and (not lf.padsAt or now - lf.padsAt > 500) then
        lf.padsAt = now
        computePads(lf, e)
    end
    if not isOwner(e) then return end
    if lf.h <= 0.0005 and lf.target <= 0.0 then
        if lf.frozen == e then
            unfreezeLocal(lf, e)
            lf.frozen = nil
        end
        return
    end
    local c = GetEntityCoords(e)
    local heading = (lf.rest and lf.rest.ent == e) and lf.rest.heading or GetEntityHeading(e)
    if not IsEntityPositionFrozen(e) then FreezeEntityPosition(e, true) end
    SetEntityCoordsNoOffset(e, c.x, c.y, restZ(lf, e) + carOffset(lf, lf.h), false, false, false)
    SetEntityRotation(e, 0.0, 0.0, heading, 2, true)
    lf.frozen = e
end

-- zwolnienie auta po zmianie przypisania
local function releaseBinding(lf)
    local e = lf.frozen or lf.ent
    if e and DoesEntityExist(e) and isOwner(e) and IsEntityPositionFrozen(e) then
        unfreezeLocal(lf, e)
    end
    lf.frozen, lf.ent, lf.entAt, lf.rest, lf.pads, lf.padsAt = nil, nil, 0, nil, nil, nil
end

-- --------------------------------------------------------------------------
--  Stan z serwera
-- --------------------------------------------------------------------------
local function applyState(key, st, initial)
    local lf = lifts[key]
    if not lf or type(st) ~= 'table' then return end
    local sh = tonumber(st.h)
    if sh then
        sh = clamp(sh, 0.0, lf.max)
        -- ciągłość animacji; skok tylko przy dużej rozbieżności lub z daleka
        if initial or abs(sh - lf.h) > 0.25 or lf.dist > DRAW_DIST + 20.0 then lf.h = sh end
    end
    lf.target = clamp(tonumber(st.target) or 0.0, 0.0, lf.max)
    lf.by = st.by
    local nv = tonumber(st.veh)
    if nv ~= lf.veh then
        releaseBinding(lf)
        lf.veh = nv
        if nv then
            local e = resolveEnt(lf, GetGameTimer())
            if e then captureRest(lf, e) end
        end
    end
    if lf.target > 0.0 then lf.reported = false end
    if lf.veh and lf.target <= 0.0 and lf.h <= 0.0 then lf.reported = false end
end

RegisterNetEvent('dp-mechanic:lift:state', function(key, st)
    applyState(key, st, false)
end)

CreateThread(function()
    Wait(1500)
    local res = DPM.Callback('lift:all')
    if res and res.ok and type(res.list) == 'table' then
        for key, st in pairs(res.list) do applyState(key, st, true) end
    end
end)

-- --------------------------------------------------------------------------
--  Główna pętla: wysokości, auta, rysowanie (co klatkę tylko ≤ 40 m)
-- --------------------------------------------------------------------------
local function stepHeight(lf, dt)
    local d = lf.target - lf.h
    if d == 0.0 then return end
    local s = SPEED * dt
    if abs(d) <= s then lf.h = lf.target else lf.h = lf.h + (d > 0 and s or -s) end
end

local function checkLowered(lf)
    if lf.reported or not lf.veh or lf.target > 0.0 or lf.h > 0.0 then return end
    local e = lf.ent
    local me = myServerId()
    local owner = e and DoesEntityExist(e) and isOwner(e)
    if owner or lf.by == me then
        lf.reported = true
        TriggerServerEvent('dp-mechanic:lift:lowered', lf.key)
    end
end

CreateThread(function()
    local last = GetGameTimer()
    while true do
        local now = GetGameTimer()
        local dt = (now - last) / 1000.0
        if dt > 1.5 then dt = 1.5 end
        last = now
        local pos = GetEntityCoords(PlayerPedId())
        local near, moving, bound = false, false, false

        for i = 1, #order do
            local lf = order[i]
            stepHeight(lf, dt)
            lf.dist = #(pos - lf.origin)
            local mv = lf.h ~= lf.target
            if mv then moving = true end
            if lf.dist <= DRAW_DIST then
                near = true
                probeFloor(lf)
                if lf.geo.model then ensureProp(lf) updateProp(lf) end
            elseif lf.prop and lf.dist > DRAW_DIST + 30.0 then
                removeProp(lf)
            end
            if lf.veh then
                bound = true
                if mv or now - lf.vehAt >= 500 then
                    lf.vehAt = now
                    handleVehicle(lf, now)
                end
            end
            checkLowered(lf)
        end

        if near then
            local c = GetFinalRenderedCamCoord()
            camX, camY, camZ = c.x, c.y, c.z
            for i = 1, #order do
                local lf = order[i]
                if lf.dist <= DRAW_DIST and lf.floor then
                    local o = lf.origin
                    if IsSphereVisible(o.x, o.y, lf.floor + 1.2, 4.2) then
                        local detail = lf.dist <= DETAIL_DIST
                        if lf.type == 'ramp' then drawRamp(lf, detail) else drawArms(lf, detail) end
                    end
                end
            end
            Wait(0)
        else
            Wait(moving and 150 or (bound and 500 or 1000))
        end
    end
end)

-- kolory z configu (raz)
for _, lf in ipairs(order) do
    lf.colBase = rgb(lf.geo.color, { 58, 64, 72, 255 })
    lf.colAcc = rgb(lf.geo.accent, { 255, 122, 26, 255 })
end

-- --------------------------------------------------------------------------
--  API dla innych modułów
-- --------------------------------------------------------------------------
function DPM.Lifts.Get(key) return lifts[key] end
function DPM.Lifts.HeightOf(key)
    local lf = lifts[key]
    return lf and lf.h or 0.0
end

-- auto stoi na podnośniku: statebag / przypisanie, albo najbliższy podnośnik ≤ driveOnRadius
function DPM.Lifts.GetVehicleLift(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return nil end
    local key = Entity(veh).state.dpm_lift
    if key and lifts[key] then return key, lifts[key].type, lifts[key].h end
    if NetworkGetEntityIsNetworked(veh) then
        local nid = NetworkGetNetworkIdFromEntity(veh)
        for k, lf in pairs(lifts) do
            if lf.veh == nid then return k, lf.type, lf.h end
        end
    end
    local c = GetEntityCoords(veh)
    local best, bestD = nil, DRIVE_ON
    for _, lf in ipairs(order) do
        local dx, dy = c.x - lf.origin.x, c.y - lf.origin.y
        local d = sqrt(dx * dx + dy * dy)
        if d <= bestD and abs(c.z - lf.origin.z) < 2.5 then best, bestD = lf, d end
    end
    if best then
        -- auto nieprzypięte stoi na podłodze – jego wysokość to 0
        return best.key, best.type, 0.0
    end
    return nil
end

function DPM.Lifts.VehicleOnLift(veh, needType, minHeight)
    local key, t, h = DPM.Lifts.GetVehicleLift(veh)
    if not key then
        if needType then return false, 'Auto musi stać na: ' .. (TYPE_NEED[needType] or needType) end
        return false, 'Auto musi stać na podnośniku'
    end
    if needType and t ~= needType then
        return false, 'Ta praca wymaga: ' .. (TYPE_NEED[needType] or needType)
    end
    minHeight = tonumber(minHeight) or 0.0
    if minHeight > 0.0 and (h or 0.0) + 0.01 < minHeight then
        return false, ('Podnieś auto na min. %.1f m (teraz %.2f m)'):format(minHeight, h or 0.0)
    end
    return true, nil
end

-- --------------------------------------------------------------------------
--  Sterowanie (panel / klawisze)
-- --------------------------------------------------------------------------
local function canOperate(lf)
    return DPM.member ~= nil and DPM.member.workshop == lf.ws and DPM.OnDuty()
end

-- auto stojące na podnośniku (najbliżej środka, ≤ driveOnRadius) – tylko na żądanie
local function candidateVehicle(lf)
    local best, bestD = nil, DRIVE_ON
    for _, v in ipairs(GetGamePool('CVehicle')) do
        local c = GetEntityCoords(v)
        local dx, dy = c.x - lf.origin.x, c.y - lf.origin.y
        local d = sqrt(dx * dx + dy * dy)
        if d <= bestD and abs(c.z - lf.origin.z) < 2.5 then best, bestD = v, d end
    end
    return best
end

local function vehicleLabel(lf)
    local e = lf.veh and resolveEnt(lf, GetGameTimer()) or candidateVehicle(lf)
    if e and DoesEntityExist(e) then
        return DPM.VehLabel(e) .. ' · ' .. DPM.Plate(e), lf.veh ~= nil
    end
    return nil, false
end

local function sendTarget(lf, target, netId)
    local res = DPM.Callback('lift:set', lf.key, target, netId)
    if res and res.ok and type(res.state) == 'table' then applyState(lf.key, res.state, false) end
    return res or { ok = false, err = 'Brak odpowiedzi serwera' }
end

-- ustawienie wysokości docelowej; stop = zatrzymaj w bieżącym miejscu
local function setTarget(key, target, stop, dir)
    local lf = lifts[key]
    if not lf then return { ok = false, err = 'Nieznany podnośnik' } end
    if not canOperate(lf) then return { ok = false, err = 'Musisz być na służbie w tym warsztacie' } end
    if stop then
        target = lf.h + (tonumber(dir) or 0.0) * 0.01
    end
    target = tonumber(target)
    if not target or target ~= target then return { ok = false, err = 'Nieprawidłowa wysokość' } end
    target = Utils.Round(clamp(target, 0.0, lf.max), 2)
    if abs(target - lf.target) < 0.005 and not stop then return { ok = true } end

    local netId
    if target > lf.h + 0.004 and not lf.veh and lf.h <= 0.15 then
        local v = candidateVehicle(lf)
        if v then
            local drv = GetPedInVehicleSeat(v, -1)
            if drv ~= 0 and DoesEntityExist(drv) then
                if drv == PlayerPedId() then return { ok = false, err = 'Wyjdź z auta przed podnoszeniem' } end
                return { ok = false, err = 'Kierowca musi wyjść z auta' }
            end
            if NetworkGetEntityIsNetworked(v) then netId = NetworkGetNetworkIdFromEntity(v) end
        end
    end

    -- jedno żądanie naraz; kolejne zastępuje oczekujące
    if lf.sending then
        lf.queued = { target = target, netId = netId }
        return { ok = true, queued = true }
    end
    lf.sending = true
    local res = sendTarget(lf, target, netId)
    while lf.queued do
        local q = lf.queued
        lf.queued = nil
        res = sendTarget(lf, q.target, q.netId)
    end
    lf.sending = false
    return res
end

local function presetsFor(lf)
    local work = math.min(WORK_HEIGHT[lf.type] or 1.2, lf.max)
    return {
        { id = 'down', label = 'Na dół', value = 0.0, icon = 'arrowDown' },
        { id = 'work', label = 'Robocza', value = Utils.Round(work, 2), icon = 'wrench' },
        { id = 'max', label = 'Maks.', value = Utils.Round(lf.max, 2), icon = 'arrowUp' },
    }
end

local function closePanel(fromNui)
    if not panel then return end
    panel = nil
    DPM.Nui('lift:close', { silent = fromNui == true })
    DPM.Focus(false, false, false)
    if DPM.busy == 'lift' then DPM.SetBusy(false) end
end

function DPM.Lifts.OpenPanel(key)
    local lf = lifts[key]
    if not lf or panel then return false end
    if DPM.busy then DPM.Notify('Najpierw skończ bieżącą czynność', 'error') return false end
    if not canOperate(lf) then DPM.Notify('Musisz być na służbie w tym warsztacie', 'error') return false end
    DPM.SetBusy('lift')
    local p = { key = key, sentH = -1.0, sentT = -1.0, sentV = false, vAt = 0 }
    panel = p
    local vlabel, vbound = vehicleLabel(lf)
    p.vlabel, p.vbound, p.vAt = vlabel, vbound, GetGameTimer()
    DPM.Focus(true, true, false)
    DPM.Nui('lift:open', {
        key = key,
        label = lf.label,
        workshop = lf.wsLabel,
        type = lf.type,
        typeLabel = TYPE_LABEL[lf.type],
        height = Utils.Round(lf.h, 3),
        target = lf.target,
        max = lf.max,
        speed = SPEED,
        step = 0.05,
        vehicle = vlabel,
        bound = vbound,
        presets = presetsFor(lf),
    })
    p.sentH, p.sentT = lf.h, lf.target

    CreateThread(function()
        while panel == p do
            Wait(100)
            if panel ~= p then break end
            local ped = PlayerPedId()
            if IsEntityDead(ped) or #(GetEntityCoords(ped) - (lf.cfg.panel or lf.origin)) > PANEL_CLOSE then
                closePanel(false)
                break
            end
            local now = GetGameTimer()
            if now - p.vAt > 1000 then
                p.vAt = now
                p.vlabel, p.vbound = vehicleLabel(lf)
            end
            if abs(lf.h - p.sentH) >= 0.004 or lf.target ~= p.sentT or p.vlabel ~= p.sentV or p.vbound ~= p.sentB then
                p.sentH, p.sentT, p.sentV, p.sentB = lf.h, lf.target, p.vlabel, p.vbound
                DPM.Nui('lift:update', {
                    key = key,
                    height = Utils.Round(lf.h, 3),
                    target = lf.target,
                    vehicle = p.vlabel or false,
                    bound = p.vbound,
                })
            end
        end
    end)
    return true
end

function DPM.Lifts.ClosePanel() closePanel(false) end

DPM.RegisterNui('lift_target', function(data)
    if not panel then return { ok = false, err = 'Panel zamknięty' } end
    return setTarget(panel.key, data.target, data.stop == true, data.dir)
end)

DPM.RegisterNui('lift_close', function()
    closePanel(true)
    return { ok = true }
end)

-- strefy paneli
for _, lf in ipairs(order) do
    if lf.cfg.panel then
        DPM.Zones.Add('lift:' .. lf.key, {
            coords = lf.cfg.panel,
            radius = 0.9,
            distance = 1.8,
            icon = 'fas fa-arrows-up-down',
            label = 'Panel – ' .. lf.label,
            canInteract = function() return panel == nil and canOperate(lf) end,
            onSelect = function() DPM.Lifts.OpenPanel(lf.key) end,
        })
    end
end

-- szybkie sterowanie klawiszami przy panelu (bez otwierania UI): przytrzymaj = ruch, puść = stop
local function nearestPanel()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) or DPM.busy then return nil end
    local pos = GetEntityCoords(ped)
    for _, lf in ipairs(order) do
        local p = lf.cfg.panel
        if p and #(pos - p) <= QUICK_DIST and canOperate(lf) then return lf end
    end
    return nil
end

local function quickPress(dir)
    if panel or quick then return end
    local lf = nearestPanel()
    if not lf then return end
    quick = { key = lf.key, dir = dir }
    CreateThread(function()
        local res = setTarget(lf.key, dir > 0 and lf.max or 0.0, false)
        if res and res.ok == false and res.err then DPM.Notify(res.err, 'error') end
    end)
end

local function quickRelease(dir)
    local q = quick
    if not q or q.dir ~= dir then return end
    quick = nil
    CreateThread(function() setTarget(q.key, nil, true, dir) end)
end

RegisterCommand('+dpm_lift_up', function() quickPress(1) end, false)
RegisterCommand('-dpm_lift_up', function() quickRelease(1) end, false)
RegisterCommand('+dpm_lift_down', function() quickPress(-1) end, false)
RegisterCommand('-dpm_lift_down', function() quickRelease(-1) end, false)
RegisterKeyMapping('+dpm_lift_up', 'Podnośnik – w górę (przy panelu)', 'keyboard', (Config.Keys and Config.Keys.liftUp) or 'UP')
RegisterKeyMapping('+dpm_lift_down', 'Podnośnik – w dół (przy panelu)', 'keyboard', (Config.Keys and Config.Keys.liftDown) or 'DOWN')

-- --------------------------------------------------------------------------
--  Sprzątanie
-- --------------------------------------------------------------------------
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, lf in ipairs(order) do
        local e = lf.frozen or lf.ent
        if e and DoesEntityExist(e) and isOwner(e) and IsEntityPositionFrozen(e) then
            local c = GetEntityCoords(e)
            SetEntityCoordsNoOffset(e, c.x, c.y, restZ(lf, e) + 0.03, false, false, false)
            FreezeEntityPosition(e, false)
        end
        removeProp(lf)
    end
    if panel then
        panel = nil
        SetNuiFocus(false, false)
    end
end)
