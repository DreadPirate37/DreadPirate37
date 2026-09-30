-- ==========================================================================
--  Interakcje (DOM-23, UIX-13): ox_target / qb-target na strefach albo własne [E].
--  Własne [E] nie rysuje nic co klatkę dla wielu punktów: pętla sprawdza najbliższy punkt
--  co 250 ms, a tryb klatkowy włącza się dopiero, gdy stoisz przy punkcie.
-- ==========================================================================
local points = {}                  -- [id] = { coords, radius, options, zone }
local mode                         -- 'ox' | 'qb' | nil
local current, currentOpt = nil, 1

CreateThread(function()
    Wait(1000)
    if Config.UseTarget then
        if GetResourceState('ox_target') == 'started' then mode = 'ox'
        elseif GetResourceState('qb-target') == 'started' then mode = 'qb' end
    end
    W.targetMode = mode
end)

local function visibleOptions(p)
    local out = {}
    for _, o in ipairs(p.options) do
        if not o.canInteract or o.canInteract() then out[#out + 1] = o end
    end
    return out
end

-- options = { { label, icon, action = fn, canInteract = fn } }
function W.AddPoint(id, coords, radius, options)
    W.RemovePoint(id)
    local p = { coords = vector3(coords.x, coords.y, coords.z), radius = radius or 1.2, options = options }
    points[id] = p
    if mode == 'ox' then
        local opts = {}
        for i, o in ipairs(options) do
            opts[i] = {
                name = id .. ':' .. i, label = o.label, icon = o.icon or 'fa-solid fa-hand', distance = (radius or 1.2) + 1.0,
                canInteract = o.canInteract and function() return (not W.busy) and o.canInteract() end or function() return not W.busy end,
                onSelect = function() CreateThread(o.action) end,
            }
        end
        p.zone = exports.ox_target:addSphereZone({ coords = p.coords, radius = radius or 1.2, debug = Config.Debug, options = opts })
    elseif mode == 'qb' then
        local opts = {}
        for i, o in ipairs(options) do
            opts[i] = {
                icon = o.icon or 'fas fa-hand', label = o.label,
                canInteract = function() return (not W.busy) and (not o.canInteract or o.canInteract()) end,
                action = function() CreateThread(o.action) end,
            }
        end
        exports['qb-target']:AddCircleZone('wlm_' .. id, p.coords, radius or 1.2, { name = 'wlm_' .. id, debugPoly = Config.Debug, useZ = true }, { options = opts, distance = (radius or 1.2) + 1.0 })
        p.zone = 'wlm_' .. id
    end
end

function W.RemovePoint(id)
    local p = points[id]
    if not p then return end
    if mode == 'ox' and p.zone then exports.ox_target:removeZone(p.zone)
    elseif mode == 'qb' and p.zone then exports['qb-target']:RemoveZone(p.zone) end
    points[id] = nil
    if current == id then current = nil end
end

function W.RemovePoints(prefix)
    for id in pairs(points) do
        if id:sub(1, #prefix) == prefix then W.RemovePoint(id) end
    end
end

function W.HasPoints(prefix)
    for id in pairs(points) do if id:sub(1, #prefix) == prefix then return true end end
    return false
end

-- --------------------------------------------------------------------------
--  Własne [E] (bez targetu): ←/→ zmienia opcję, E wybiera
-- --------------------------------------------------------------------------
CreateThread(function()
    while true do
        local sleep = 750
        if not mode and next(points) and not W.busy then
            sleep = 250
            local pc = GetEntityCoords(PlayerPedId())
            local best, bd = nil, 99.0
            for id, p in pairs(points) do
                local d = #(pc - p.coords)
                if d < p.radius + 0.6 and d < bd then best, bd = id, d end
            end
            if best ~= current then current, currentOpt = best, 1 end
            if current then
                local p = points[current]
                local opts = p and visibleOptions(p) or {}
                if #opts > 0 then
                    sleep = 0
                    if currentOpt > #opts then currentOpt = 1 end
                    local o = opts[currentOpt]
                    W.Help(('~INPUT_CONTEXT~ %s%s'):format(o.label, #opts > 1 and ('  ~INPUT_CELLPHONE_LEFT~/~INPUT_CELLPHONE_RIGHT~ (%d/%d)'):format(currentOpt, #opts) or ''))
                    if IsControlJustReleased(0, 174) then currentOpt = currentOpt > 1 and currentOpt - 1 or #opts end
                    if IsControlJustReleased(0, 175) then currentOpt = currentOpt < #opts and currentOpt + 1 or 1 end
                    if IsControlJustReleased(0, 38) then CreateThread(o.action) end
                end
            end
        end
        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(points) do W.RemovePoint(id) end
end)
