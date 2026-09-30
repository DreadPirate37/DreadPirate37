-- ==========================================================================
--  Propagacja hałasu przez pokoje (SKR-04). Graf liczony raz na szablon wnętrza,
--  a BFS rusza wyłącznie przy zdarzeniu hałasu – bez żadnych pętli co klatkę.
-- ==========================================================================
local N = {}
WLM.Noise = N

local graphs = {}

function N.Graph(tplName)
    local g = graphs[tplName]
    if g then return g end
    local tpl = Config.Interiors[tplName]
    if not tpl then return nil end
    g = { adj = {}, street = {}, rooms = {} }
    for _, r in ipairs(tpl.rooms) do
        g.adj[r.id] = {}
        g.street[r.id] = r.street == true
        g.rooms[r.id] = r
    end
    for _, l in ipairs(tpl.links) do
        local a, b, door = l[1], l[2], l[3]
        local att = door and Config.Noise.link.door or Config.Noise.link.open
        if g.adj[a] and g.adj[b] then
            table.insert(g.adj[a], { to = b, att = att })
            table.insert(g.adj[b], { to = a, att = att })
        end
    end
    graphs[tplName] = g
    return g
end

-- zwraca { [pokój] = słyszalna wartość } dla hałasu `value` z pokoju `room`
function N.Propagate(tplName, room, value)
    local g = N.Graph(tplName)
    local out = {}
    if not g or not g.adj[room] then return out end
    out[room] = value
    local queue, head = { room }, 1
    while head <= #queue do
        local cur = queue[head]; head = head + 1
        for _, e in ipairs(g.adj[cur]) do
            local v = out[cur] * e.att
            if v >= 1 and (not out[e.to] or out[e.to] < v) then
                out[e.to] = v
                queue[#queue + 1] = e.to
            end
        end
    end
    return out
end

-- ile hałasu z wnętrza słychać na ulicy (pokoje z oknem na ulicę)
function N.Outside(tplName, room, value)
    local g = N.Graph(tplName)
    if not g then return 0 end
    local best = 0
    for r, v in pairs(N.Propagate(tplName, room, value)) do
        if g.street[r] then best = math.max(best, v) end
    end
    return best * Config.Noise.outside
end

-- pokój, w którym leży punkt (pozycja względna)
function N.RoomAt(tplName, rel)
    local tpl = Config.Interiors[tplName]
    if not tpl then return nil end
    for _, r in ipairs(tpl.rooms) do
        if rel.x >= r.min.x and rel.x <= r.max.x and rel.y >= r.min.y and rel.y <= r.max.y and rel.z >= r.min.z and rel.z <= r.max.z then
            return r.id
        end
    end
    return nil
end
