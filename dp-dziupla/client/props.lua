-- ==========================================================================
--  Rekwizyty w dziupli (lokalne, spawnowane tylko w pobliżu):
--  stół, regał z widocznymi częściami z magazynu, laptop, skrzynki i lampy przy
--  stanowiskach, wraki przy prasie + żuraw i miska w trakcie demontażu
-- ==========================================================================
local D = Dz
local P = Config.Props
local spawned, shelfObjs = {}, {}
local current

local function fwd(h)
    local r = math.rad(h)
    return vector3(-math.sin(r), math.cos(r), 0.0)
end

-- punkt przesunięty w układzie „heading”: dx w prawo, dy do przodu
local function offset(v, h, dx, dy, dz)
    local f = fwd(h)
    local right = vector3(f.y, -f.x, 0.0)
    return vector3(v.x, v.y, v.z) + right * dx + f * dy + vector3(0.0, 0.0, dz or 0.0)
end

local function place(model, pos, heading, ground, list)
    local hash = D.LoadModel(model)
    if not hash then return nil end
    local obj = CreateObject(hash, pos.x, pos.y, pos.z, false, false, false)
    SetEntityHeading(obj, heading or 0.0)
    if ground ~= false then PlaceObjectOnGroundProperly(obj) end
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(hash)
    list = list or spawned
    list[#list + 1] = obj
    return obj
end

local function clear(list)
    for _, o in ipairs(list) do
        if DoesEntityExist(o) then DeleteEntity(o) end
    end
    for i = #list, 1, -1 do list[i] = nil end
end

local function spawnShop(s)
    if s.bench then place(P.bench, offset(s.bench, s.bench.w, 0.0, 0.85), s.bench.w + 180.0) end
    if s.tyre then place(P.tyre, offset(s.tyre, s.tyre.w, 0.0, 0.9), s.tyre.w + 180.0) end
    if s.laptop then
        local t = offset(s.laptop, s.laptop.w, 0.0, 0.75)
        place(P.table, t, s.laptop.w)
        place(P.laptop, t + vector3(0.0, 0.0, P.tableHeight), s.laptop.w + 180.0, false)
    end
    if s.shelf then place(P.shelf, s.shelf, s.shelfHeading or 0.0) end
    for _, b in ipairs(s.bays or {}) do
        for _, d in ipairs(P.bay) do
            place(d.model, offset(b, b.w, d.off.x, d.off.y), b.w + d.h)
        end
    end
    if s.crusher then
        for i, m in ipairs(P.crusher) do
            place(m, s.crusher + vector3(4.5 + i * 0.5, (i - 1.5) * 3.5, 0.0), 30.0 * i)
        end
    end
    for _, e in ipairs(s.props or {}) do place(e.model, e.coords.xyz, e.coords.w) end
end

-- części z magazynu widoczne na regale
local function refreshShelf(s)
    clear(shelfObjs)
    if not P.shelfParts or not s.shelf then return end
    local r = D.Callback('shelfView')
    if not r or not r.items then return end
    local h = s.shelfHeading or 0.0
    for i, it in ipairs(r.items) do
        local lvl = math.floor((i - 1) / 4)
        local col = (i - 1) % 4
        local pos = offset(s.shelf, h, -0.75 + col * 0.5, 0.0, P.shelfLevels[lvl + 1] or 0.4)
        place(it.prop, pos, h + math.random(-20, 20), false, shelfObjs)
    end
end
D.RefreshShelf = function() if current then refreshShelf(current) end end

CreateThread(function()
    if not P.enabled then return end
    while true do
        local s = D.shop
        if s ~= current then
            clear(spawned)
            clear(shelfObjs)
            current = s
            if s then
                spawnShop(s)
                refreshShelf(s)
            end
        elseif s and s.shelf and #(GetEntityCoords(PlayerPedId()) - s.shelf) < 12.0 and GetGameTimer() % 20000 < 1000 then
            refreshShelf(s)
        end
        Wait(1000)
    end
end)

-- --------------------------------------------------------------------------
--  Rekwizyty do sesji demontażu (wołane z partjob.lua)
-- --------------------------------------------------------------------------
function D.PartProps(veh, def, anchorW)
    local list = {}
    if not P.enabled then return list end
    local vh = GetEntityHeading(veh)
    if def.tool == 'hoist' then
        -- żuraw przed maską (silnik) albo obok auta (skrzynia)
        local pos = def.id == 'engine' and GetOffsetFromEntityInWorldCoords(veh, 0.0, 3.2, 0.0) or GetOffsetFromEntityInWorldCoords(veh, 2.2, 0.0, 0.0)
        place(P.hoist, pos, def.id == 'engine' and vh + 180.0 or vh + 90.0, true, list)
    end
    for _, f in ipairs(def.F) do
        if f.t == 'drain' then
            local g = D.GroundZ(anchorW)
            place(P.basin, vector3(anchorW.x, anchorW.y, g), 0.0, true, list)
            break
        end
    end
    return list
end

function D.ClearProps(list) clear(list or {}) end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clear(spawned)
    clear(shelfObjs)
end)
