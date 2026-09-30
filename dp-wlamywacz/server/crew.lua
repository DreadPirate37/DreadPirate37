-- ==========================================================================
--  Ekipa (EKI-01, EKI-03, EKI-07): do 4 osób, wspólny dom i notatki, sygnały i oznaczenia czujki
-- ==========================================================================
Crew = {}
local crews, memberOf, invites = {}, {}, {}
local crewSeq = 0
local MAX = 4

function Crew.Members(src)
    local id = memberOf[src]
    if not id or not crews[id] then return { src } end
    local out = {}
    for m in pairs(crews[id].members) do out[#out + 1] = m end
    return out
end

function Crew.Others(src)
    local out = {}
    for _, m in ipairs(Crew.Members(src)) do if m ~= src then out[#out + 1] = m end end
    return out
end

function Crew.Same(a, b)
    if a == b then return true end
    local ia = memberOf[a]
    return ia ~= nil and ia == memberOf[b]
end

local function view(src)
    local id = memberOf[src]
    if not id then return nil end
    local list = {}
    for m in pairs(crews[id].members) do list[#list + 1] = { id = m, name = Bridge.GetName(m), leader = crews[id].leader == m } end
    return { id = id, members = list }
end

local function pushAll(id)
    for m in pairs(crews[id].members) do SV.Client(m, 'crew', view(m)) end
end

local function leaveCrew(src)
    local id = memberOf[src]
    if not id then return end
    memberOf[src] = nil
    local c = crews[id]
    if not c then return end
    c.members[src] = nil
    SV.Client(src, 'crew', nil)
    if not next(c.members) then crews[id] = nil return end
    if c.leader == src then c.leader = next(c.members) end
    local n = 0
    for _ in pairs(c.members) do n = n + 1 end
    if n == 1 then
        local last = next(c.members)
        memberOf[last] = nil
        crews[id] = nil
        SV.Client(last, 'crew', nil)
        return
    end
    pushAll(id)
end

SV.Register('crew:invite', function(src, target)
    target = tonumber(target)
    if not target or target == src or not GetPlayerName(target) then return { ok = false, msg = L('no_target') } end
    local a, b = SV.Coords(src), SV.Coords(target)
    if not a or not b or #(a - b) > 10.0 then return { ok = false, msg = L('too_far') } end
    if memberOf[target] then return { ok = false, msg = L('crew_taken') } end
    local id = memberOf[src]
    if id and crews[id] then
        local n = 0
        for _ in pairs(crews[id].members) do n = n + 1 end
        if n >= MAX then return { ok = false, msg = L('crew_full', MAX) } end
    end
    invites[target] = { from = src, at = os.time() }
    SV.Notify(target, L('crew_invited', Bridge.GetName(src)), 'info')
    return { ok = true, msg = L('crew_invite_sent') }
end, 2000)

SV.Register('crew:accept', function(src)
    local inv = invites[src]
    invites[src] = nil
    if not inv or os.time() - inv.at > 60 or not GetPlayerName(inv.from) then return { ok = false, msg = L('crew_no_invite') } end
    leaveCrew(src)
    local id = memberOf[inv.from]
    if not id then
        crewSeq = crewSeq + 1
        id = crewSeq
        crews[id] = { leader = inv.from, members = { [inv.from] = true } }
        memberOf[inv.from] = id
    end
    local n = 0
    for _ in pairs(crews[id].members) do n = n + 1 end
    if n >= MAX then return { ok = false, msg = L('crew_full', MAX) } end
    crews[id].members[src] = true
    memberOf[src] = id
    pushAll(id)
    return { ok = true, msg = L('crew_joined') }
end, 1000)

SV.Register('crew:leave', function(src)
    leaveCrew(src)
    return { ok = true, msg = L('crew_left') }
end, 1000)

-- sygnały ekipy (EKI-07): krótkie komunikaty bez głosu
local SIGNALS = { stop = true, quiet = true, go = true, clear = true, car = true, help = true }
SV.Register('crew:signal', function(src, kind)
    if not SIGNALS[kind] then return { ok = false } end
    local name = Bridge.GetName(src)
    for _, m in ipairs(Crew.Members(src)) do SV.Client(m, 'signal', kind, name, src) end
    return { ok = true }
end, 700)

-- oznaczenie czujki z lornetki (EKI-03)
SV.Register('crew:ping', function(src, coords, label)
    if type(coords) ~= 'table' or not coords.x then return { ok = false } end
    local name = Bridge.GetName(src)
    for _, m in ipairs(Crew.Members(src)) do
        SV.Client(m, 'ping', { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0 }, type(label) == 'string' and label:sub(1, 40) or '', name)
    end
    return { ok = true }
end, 1000)

AddEventHandler('dp-wlamywacz:internal:dropped', function(src)
    invites[src] = nil
    leaveCrew(src)
end)
