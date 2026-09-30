-- ==========================================================================
--  Ekipa (crew): wspólny magazyn, kasa ekipy z udziałem w zarobkach, role,
--  zaproszenia, poziom ekipy (premia do cen). Zapis w KVP jak profile.
--  Rekord ekipy ma pola magazynu (wh, upg, seq), więc DZ.Wh* działa na nim wprost.
-- ==========================================================================
local CR = Config.Crew
local Crews = {}      -- [cid] = rekord
local Invites = {}    -- [identyfikator] = { cid, from, at }

local ROLE = { boss = 3, deputy = 2, member = 1 }
local ROLE_LABEL = { boss = 'Szef', deputy = 'Zastępca', member = 'Członek' }

local function kvpKey(cid) return 'dz:crew_' .. cid end

local function loadAll()
    local raw = GetResourceKvpString('dz:crews')
    for _, cid in ipairs(raw and json.decode(raw) or {}) do
        local r = GetResourceKvpString(kvpKey(cid))
        if r then
            local c = json.decode(r)
            c.id = 'crew_' .. cid
            c.cid = cid
            c.wh, c.upg, c.members = c.wh or {}, c.upg or {}, c.members or {}
            Crews[cid] = c
        end
    end
end

local function saveIndex()
    local ids = {}
    for cid in pairs(Crews) do ids[#ids + 1] = cid end
    SetResourceKvp('dz:crews', json.encode(ids))
end

function DZ.SaveCrew(c) DZ.Save(c) end

function DZ.CrewOf(p)
    return p and p.crew and Crews[p.crew] or nil
end

-- magazyn, na którym pracuje gracz (ekipy albo własny)
function DZ.Store(p)
    if not CR.enabled or not CR.sharedWarehouse or not p or not p.crew then return p end
    return Crews[p.crew] or p
end

function DZ.CrewLevel(c)
    local lvl = 1
    for i, xp in ipairs(CR.levels) do if c.xp >= xp then lvl = i end end
    return lvl
end

-- premia do cen za poziom ekipy
function DZ.CrewPriceMult(p)
    local c = DZ.CrewOf(p)
    if not c then return 1.0 end
    return 1 + CR.pricePerLevel * (DZ.CrewLevel(c) - 1)
end

-- udział ekipy w zarobku (wołane z DZ.Earn); zwraca kwotę dla gracza
function DZ.CrewCut(src, p, amount)
    local c = DZ.CrewOf(p)
    if not c then return amount end
    local cut = math.floor(amount * CR.cut)
    c.bank = (c.bank or 0) + cut
    c.xp = (c.xp or 0) + math.floor(amount / 100)
    c.earned = (c.earned or 0) + amount
    DZ.SaveCrew(c)
    return amount - cut
end

local function role(c, id) return c.members[id] and c.members[id].role or nil end
local function can(c, id, need) return (ROLE[role(c, id)] or 0) >= ROLE[need] end

local function view(src, p)
    local c = DZ.CrewOf(p)
    local inv = Invites[p.id]
    local out = { enabled = CR.enabled, price = CR.createPrice, maxMembers = CR.maxMembers, cut = CR.cut }
    if inv and Crews[inv.cid] and os.time() - inv.at < 600 then out.invite = { cid = inv.cid, name = Crews[inv.cid].name, from = inv.from } end
    if not c then return out end
    local members = {}
    for id, m in pairs(c.members) do
        members[#members + 1] = { id = id, name = m.name, role = m.role, roleLabel = ROLE_LABEL[m.role], me = id == p.id }
    end
    table.sort(members, function(a, b) return (ROLE[a.role] or 0) > (ROLE[b.role] or 0) end)
    local lvl = DZ.CrewLevel(c)
    out.crew = {
        name = c.name, tag = c.tag, bank = c.bank or 0, xp = c.xp or 0, level = lvl, nextXp = CR.levels[lvl + 1],
        earned = c.earned or 0, members = members, myRole = role(c, p.id), shared = CR.sharedWarehouse,
        priceBonus = CR.pricePerLevel * (lvl - 1),
    }
    return out
end

function DZ.CrewView(src, p, data) data.crew = view(src, p) end

-- --------------------------------------------------------------------------
--  Akcje
-- --------------------------------------------------------------------------
local function refresh(src) return DZ.Overview(src) end

DZ.register('crewCreate', function(src, name)
    if not CR.enabled then return { ok = false } end
    local p = DZ.Profile(src)
    if p.crew and Crews[p.crew] then return { ok = false, msg = 'Już jesteś w ekipie.' } end
    name = type(name) == 'string' and name:gsub('[^%w%s%-_ąćęłńóśźżĄĆĘŁŃÓŚŹŻ]', ''):sub(1, 24) or ''
    if #name < 3 then return { ok = false, msg = 'Nazwa ekipy: 3–24 znaki.' } end
    for _, c in pairs(Crews) do
        if c.name:lower() == name:lower() then return { ok = false, msg = 'Taka ekipa już istnieje.' } end
    end
    if DZ.Level(p) < CR.minLevel then return { ok = false, msg = ('Wymaga poziomu %d.'):format(CR.minLevel) } end
    if not Bridge.RemoveMoney(src, Config.ShopAccount, CR.createPrice, 'dp-dziupla-ekipa') then return { ok = false, msg = L('no_money', CR.createPrice) } end
    local cid = ('%x'):format(os.time()) .. ('%03x'):format(math.random(0, 4095))
    local c = { id = 'crew_' .. cid, cid = cid, name = name, owner = p.id, bank = 0, xp = 0, earned = 0, wh = {}, upg = {}, seq = 0,
        members = { [p.id] = { name = GetPlayerName(src), role = 'boss' } } }
    Crews[cid] = c
    p.crew = cid
    DZ.Save(p)
    DZ.SaveCrew(c)
    saveIndex()
    DZ.Log('shop', src, 'Nowa ekipa', name, 'info')
    return { ok = true, msg = 'Ekipa „' .. name .. '” założona.', data = refresh(src) }
end)

DZ.register('crewInvite', function(src, target)
    local p = DZ.Profile(src)
    local c = DZ.CrewOf(p)
    target = tonumber(target)
    if not c or not can(c, p.id, 'deputy') then return { ok = false, msg = 'Brak uprawnień.' } end
    if not target or not GetPlayerName(target) then return { ok = false, msg = 'Nie ma gracza o takim ID.' } end
    local tp = DZ.Profile(target)
    if not tp or (tp.crew and Crews[tp.crew]) then return { ok = false, msg = 'Ten gracz ma już ekipę.' } end
    local n = 0
    for _ in pairs(c.members) do n = n + 1 end
    if n >= CR.maxMembers then return { ok = false, msg = 'Ekipa jest pełna.' } end
    Invites[tp.id] = { cid = c.cid, from = GetPlayerName(src), at = os.time() }
    Bridge.Notify(target, ('%s zaprasza cię do ekipy „%s”. Otwórz ChopNet → Ekipa.'):format(GetPlayerName(src), c.name), 'info')
    return { ok = true, msg = 'Zaproszenie wysłane.' }
end)

DZ.register('crewAccept', function(src)
    local p = DZ.Profile(src)
    local inv = Invites[p.id]
    local c = inv and Crews[inv.cid]
    if not c or os.time() - inv.at > 600 then return { ok = false, msg = 'Zaproszenie wygasło.' } end
    if p.crew and Crews[p.crew] then return { ok = false, msg = 'Już jesteś w ekipie.' } end
    Invites[p.id] = nil
    c.members[p.id] = { name = GetPlayerName(src), role = 'member' }
    p.crew = c.cid
    DZ.Save(p)
    DZ.SaveCrew(c)
    return { ok = true, msg = 'Witaj w ekipie „' .. c.name .. '”.', data = refresh(src) }
end)

local function removeMember(c, id)
    c.members[id] = nil
    local mp
    for _, pid in ipairs(GetPlayers()) do
        local pp = DZ.Profile(tonumber(pid))
        if pp and pp.id == id then mp = pp end
    end
    if not mp then
        local raw = GetResourceKvpString('dz:' .. id)
        if raw then
            local d = json.decode(raw)
            d.crew = nil
            SetResourceKvp('dz:' .. id, json.encode(d))
        end
    else
        mp.crew = nil
        DZ.Save(mp)
    end
end

DZ.register('crewKick', function(src, id)
    local p = DZ.Profile(src)
    local c = DZ.CrewOf(p)
    if not c or type(id) ~= 'string' or not c.members[id] then return { ok = false } end
    if id == p.id or (ROLE[role(c, p.id)] or 0) <= (ROLE[role(c, id)] or 0) then return { ok = false, msg = 'Brak uprawnień.' } end
    removeMember(c, id)
    DZ.SaveCrew(c)
    return { ok = true, msg = 'Wyrzucono z ekipy.', data = refresh(src) }
end)

DZ.register('crewPromote', function(src, id)
    local p = DZ.Profile(src)
    local c = DZ.CrewOf(p)
    if not c or not can(c, p.id, 'boss') or type(id) ~= 'string' or not c.members[id] or id == p.id then return { ok = false } end
    local m = c.members[id]
    m.role = m.role == 'member' and 'deputy' or 'member'
    DZ.SaveCrew(c)
    return { ok = true, msg = m.name .. ': ' .. ROLE_LABEL[m.role], data = refresh(src) }
end)

DZ.register('crewLeave', function(src)
    local p = DZ.Profile(src)
    local c = DZ.CrewOf(p)
    if not c then return { ok = false } end
    if role(c, p.id) == 'boss' then
        local n = 0
        for _ in pairs(c.members) do n = n + 1 end
        if n > 1 then return { ok = false, msg = 'Szef musi najpierw wyrzucić resztę albo rozwiązać ekipę.' } end
        -- ostatni członek: rozwiązanie ekipy, kasa wraca do szefa (magazyn ekipy przepada)
        if (c.bank or 0) > 0 then Bridge.AddMoney(src, Config.PayAccount, c.bank, 'dp-dziupla-ekipa') end
        Crews[c.cid] = nil
        DeleteResourceKvp(kvpKey(c.cid))
        saveIndex()
        p.crew = nil
        DZ.Save(p)
        return { ok = true, msg = 'Ekipa rozwiązana.', data = refresh(src) }
    end
    removeMember(c, p.id)
    DZ.SaveCrew(c)
    return { ok = true, msg = 'Opuściłeś ekipę.', data = refresh(src) }
end)

DZ.register('crewBank', function(src, amount)
    local p = DZ.Profile(src)
    local c = DZ.CrewOf(p)
    amount = math.floor(tonumber(amount) or 0)
    if not c or amount == 0 then return { ok = false } end
    if amount > 0 then
        if not Bridge.RemoveMoney(src, Config.PayAccount, amount, 'dp-dziupla-ekipa') then return { ok = false, msg = L('no_money', amount) } end
        c.bank = (c.bank or 0) + amount
    else
        if not can(c, p.id, 'boss') then return { ok = false, msg = 'Tylko szef wypłaca z kasy.' } end
        local out = math.min(-amount, c.bank or 0)
        if out <= 0 then return { ok = false, msg = 'Kasa jest pusta.' } end
        c.bank = c.bank - out
        Bridge.AddMoney(src, Config.PayAccount, out, 'dp-dziupla-ekipa')
        amount = -out
    end
    DZ.SaveCrew(c)
    DZ.Log('earn', src, 'Kasa ekipy', ('%s: %+d$ (saldo %d$)'):format(c.name, amount, c.bank), 'info')
    return { ok = true, msg = ('Kasa ekipy: %d$'):format(c.bank), data = refresh(src) }
end)

loadAll()
