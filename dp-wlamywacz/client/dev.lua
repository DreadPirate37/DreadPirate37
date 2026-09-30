-- ==========================================================================
--  Narzędzia deweloperskie (Config.Debug): punkty względne wnętrza, szablon domu,
--  rysowanie pokoi i punktów w środku (TEC-11 w wersji podstawowej)
-- ==========================================================================
if not Config.Debug then return end

local function out(s)
    print(s)
    W.Notify(s, 'info', 12000)
end

-- /wlm_punkt <typ> [parametr] – w domu wypisuje pozycję względną do szablonu wnętrza
RegisterCommand('wlm_punkt', function(_, args)
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local h = GetEntityHeading(ped)
    local typ, param = args[1] or 'search', args[2]
    if W.session then
        local o = W.session.origin
        local room = W.room or '?'
        local extra = param and ((typ == 'search' and (", furniture = '%s'"):format(param)) or (typ == 'loot' and (", slot = '%s'"):format(param)) or (", label = '%s'"):format(param)) or ''
        out(("{ id = 'p%d', type = '%s'%s, room = '%s', pos = vec4(%.2f, %.2f, %.2f, %.1f) },"):format(GetGameTimer() % 10000, typ, extra, room, c.x - o.x, c.y - o.y, c.z - o.z - 1.0, h))
    else
        out(('vec4(%.2f, %.2f, %.2f, %.1f)'):format(c.x, c.y, c.z, h))
    end
end, false)

-- /wlm_dom <id> – szablon domu z Twoją pozycją jako drzwiami frontowymi
RegisterCommand('wlm_dom', function(_, args)
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local h = GetEntityHeading(ped)
    local id = args[1] or ('dom_%d'):format(GetGameTimer() % 10000)
    out(("{ id = '%s', label = 'Nowy dom', district = 'city', tier = 2, interior = 'studio', entries = { { id = 'front', type = 'door_wood', coords = vec4(%.2f, %.2f, %.2f, %.1f), lock = 'B', street = 1.0, spawn = 'front', front = true } }, keySpots = { vec3(%.2f, %.2f, %.2f) } },")
        :format(id, c.x, c.y, c.z, h, c.x, c.y, c.z - 1.0))
end, false)

-- rysowanie pokoi i punktów w środku
CreateThread(function()
    while true do
        local s = W.session
        if s then
            local tpl = Config.Interiors[s.interior]
            local o = s.origin
            for _, r in ipairs(tpl.rooms) do
                local a, b = r.min, r.max
                DrawBox(o.x + a.x, o.y + a.y, o.z + a.z, o.x + b.x, o.y + b.y, o.z + b.z, 80, 160, 255, 25)
            end
            for _, p in ipairs(tpl.points) do
                local w = WLM.U.Rel(o, p.pos)
                DrawMarker(28, w.x, w.y, w.z + 0.1, 0, 0, 0, 0, 0, 0, 0.12, 0.12, 0.12, 217, 170, 79, 180, false, false, 2, false, nil, nil, false)
            end
            Wait(0)
        else
            Wait(1000)
        end
    end
end)
