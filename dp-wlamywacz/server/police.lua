-- ==========================================================================
--  Policja: warunki startu (POL-16, POL-18), dispatch (POL-01), czas reakcji (POL-02),
--  heat dzielnicy (POL-08), dowody (POL-03) i sprawdzanie łupu (POL-10)
-- ==========================================================================
Police = {}
local U = WLM.U
local evidence = {}                -- [houseId] = { { kind, cid, name, desc, where, at } }

-- --------------------------------------------------------------------------
--  Warunki rozpoczęcia włamania
-- --------------------------------------------------------------------------
function Police.CanStart(src)
    local prof = Progress.Get(src)
    if not prof then return false, L('error') end
    local now = os.time()
    if Bridge.IsPolice(src) or Bridge.IsEms(src) then
        prof.lastDuty = now
        Store.Touch(prof.id)
        return false, L('on_duty')
    end
    if now - (prof.lastDuty or 0) < Config.Police.dutyCooldown * 60 then
        return false, L('duty_cooldown', math.ceil((Config.Police.dutyCooldown * 60 - (now - prof.lastDuty)) / 60))
    end
    if Bridge.PoliceCount() < Config.Police.minOnline then
        return false, L('no_police', Config.Police.minOnline)
    end
    if Progress.Heat(src) >= Config.Police.heatMax then
        return false, L('too_hot')
    end
    return true
end

-- co 2 minuty zapamiętujemy, kto jest na służbie – potrzebne do blokady po zejściu ze służby
CreateThread(function()
    while true do
        Wait(120000)
        local now = os.time()
        for _, id in ipairs(GetPlayers()) do
            local s = tonumber(id)
            if Bridge.IsPolice(s) or Bridge.IsEms(s) then
                local p = Progress.Get(s)
                if p then p.lastDuty = now Store.Touch(p.id) end
            end
        end
    end
end)

-- --------------------------------------------------------------------------
--  Heat dzielnicy (leniwy zanik)
-- --------------------------------------------------------------------------
function Police.DistrictHeat(d)
    local doc = Store.Doc('heat', {})
    local h = doc[d]
    if not h then return 0 end
    return U.Decay(h.v, h.at, Config.Heat.tau, os.time())
end

function Police.AddDistrictHeat(d, v)
    local doc = Store.Doc('heat', {})
    doc[d] = { v = Police.DistrictHeat(d) + v, at = os.time() }
    Store.TouchDoc('heat')
end

-- --------------------------------------------------------------------------
--  Czas dojazdu (POL-02): baza dzielnicy, skracana przez liczbę policjantów i heat dzielnicy
-- --------------------------------------------------------------------------
function Police.ETA(district)
    local base = Config.Police.eta[district] or Config.Police.eta.default
    local cops = math.max(1, Bridge.PoliceCount())
    local heat = Police.DistrictHeat(district)
    local eta = base / (1 + 0.12 * (cops - 1)) * (1 - math.min(0.3, heat / 400))
    return math.floor(U.Clamp(eta, 35, 420))
end

-- --------------------------------------------------------------------------
--  Dispatch (POL-01). Integracje klientowe odpala klient „zgłaszający”, wbudowany wysyła serwer.
-- --------------------------------------------------------------------------
local dispatchMode = Config.Dispatch
CreateThread(function()
    Wait(2000)
    if dispatchMode == 'auto' then
        local order = { { 'ps-dispatch', 'ps' }, { 'cd_dispatch', 'cd' }, { 'core_dispatch', 'core' }, { 'qs-dispatch', 'qs' }, { 'rcore_dispatch', 'rcore' } }
        dispatchMode = 'builtin'
        for _, o in ipairs(order) do
            if GetResourceState(o[1]) == 'started' then dispatchMode = o[2] break end
        end
    end
    SV.Debug('dispatch:', dispatchMode)
end)

local TITLES = {
    alarm = 'dispatch_alarm', call = 'dispatch_call', witness = 'dispatch_witness',
    security = 'dispatch_security', pawn = 'dispatch_pawn', report = 'dispatch_report',
}

-- kind: alarm | call | witness | security | pawn | report; reporter = gracz, u którego odpalamy eksport
function Police.Alert(kind, coords, district, description, reporter)
    local data = {
        kind = kind,
        coords = { x = coords.x, y = coords.y, z = coords.z },
        title = L(TITLES[kind] or 'dispatch_alarm'),
        message = description or '',
        code = kind == 'alarm' and '10-90' or '10-31',
        eta = Police.ETA(district),
    }
    TriggerEvent('dp-wlamywacz:dispatch', data)
    if dispatchMode == 'rcore' then
        TriggerEvent('rcore_dispatch:server:sendAlert', {
            code = data.code, default_priority = 'medium', coords = data.coords, job = Config.Police.jobs,
            text = data.title .. ': ' .. data.message, type = 'alerts', blip_time = 5,
            blip = { sprite = 40, colour = 1, scale = 1.0, text = data.title, flashes = true, radius = 0 },
        })
    elseif dispatchMode ~= 'builtin' and reporter and GetPlayerPing(reporter) > 0 then
        TriggerClientEvent('dp-wlamywacz:client:dispatch', reporter, dispatchMode, data)
    else
        for _, s in ipairs(Bridge.PoliceSources()) do
            TriggerClientEvent('dp-wlamywacz:client:policeAlert', s, data)
        end
    end
    Police.AddDistrictHeat(district, kind == 'alarm' and 10 or 6)
    return data.eta
end

-- --------------------------------------------------------------------------
--  Dowody (POL-03)
-- --------------------------------------------------------------------------
function Police.AddEvidence(houseId, ev)
    local list = evidence[houseId]
    if not list then list = {} evidence[houseId] = list end
    ev.at = os.time()
    list[#list + 1] = ev
    if #list > 60 then table.remove(list, 1) end
end

function Police.GetEvidence(houseId)
    local list = evidence[houseId]
    if not list then return {} end
    local now, out = os.time(), {}
    for _, ev in ipairs(list) do
        if now - ev.at <= Config.Evidence.ttl then out[#out + 1] = ev end
    end
    evidence[houseId] = out
    return out
end

local function houseCoords(houseId)
    local h = WLM.HouseById[houseId]
    if h then return h.entries[1].coords end
    local s = WLM.ShedById[houseId]
    return s and s.coords
end

-- policjant przy domu: lista śladów
SV.Register('police:evidence', function(src, houseId)
    if not Bridge.IsPolice(src) then return { ok = false, msg = L('not_police') } end
    local c = houseCoords(houseId)
    if not c or not SV.Near(src, c, 25.0) then return { ok = false, msg = L('too_far') } end
    local out = {}
    for _, ev in ipairs(Police.GetEvidence(houseId)) do
        out[#out + 1] = {
            kind = ev.kind, where = ev.where, desc = ev.desc,
            who = ev.cid and (ev.name .. ' (' .. ev.cid .. ')') or nil,
            ago = math.floor((os.time() - ev.at) / 60),
        }
    end
    return { ok = true, list = out, label = (WLM.HouseById[houseId] or WLM.ShedById[houseId]).label }
end, 1000)

-- policjant sprawdza łup przy zatrzymanym (POL-10)
SV.Register('police:inspect', function(src, target)
    target = tonumber(target)
    if not Bridge.IsPolice(src) then return { ok = false, msg = L('not_police') } end
    if not target or not GetPlayerName(target) then return { ok = false, msg = L('no_target') } end
    local a, b = SV.Coords(src), SV.Coords(target)
    if not a or not b or #(a - b) > Config.Evidence.inspectDistance then return { ok = false, msg = L('too_far') } end
    local prof = Progress.Get(target)
    local out = {}
    for _, it in ipairs(prof and prof.bag or {}) do
        local def = Config.Loot[it.key]
        local h = WLM.HouseById[it.house] or WLM.ShedById[it.house]
        out[#out + 1] = { label = def and def.label or it.key, house = h and h.label or it.house, ago = math.floor((os.time() - (it.t or 0)) / 60) }
    end
    return { ok = true, list = out, name = Bridge.GetName(target) }
end, 1000)

-- konfiskata łupu i narzędzi + kara w progresji (PRO-11)
function Police.Confiscate(target)
    local prof = Progress.Get(target)
    if not prof then return 0 end
    local n = #prof.bag
    prof.bag = {}
    Store.Touch(prof.id)
    local tools = { Config.Items.rake, Config.Items.shim, Config.Items.crowbar, Config.Items.glasscutter, Config.Items.wire }
    for _, lp in ipairs(Config.Items.lockpicks) do tools[#tools + 1] = lp.item end
    for _, item in ipairs(tools) do
        local c = Bridge.ItemCount(target, item)
        if c > 0 and Config.RequireItems then Bridge.RemoveItem(target, item, c) end
    end
    Progress.Arrested(target)
    Burglary.DropCarry(target)
    SV.Client(target, 'bag', {})
    return n
end

SV.Register('police:confiscate', function(src, target)
    target = tonumber(target)
    if not Bridge.IsPolice(src) then return { ok = false, msg = L('not_police') } end
    if not target or not GetPlayerName(target) then return { ok = false, msg = L('no_target') } end
    local a, b = SV.Coords(src), SV.Coords(target)
    if not a or not b or #(a - b) > Config.Evidence.inspectDistance then return { ok = false, msg = L('too_far') } end
    local n = Police.Confiscate(target)
    SV.Notify(target, L('confiscated'), 'bad')
    SV.Log('policja', ('%s zabrał łup (%d szt.) graczowi %s'):format(GetPlayerName(src), n, GetPlayerName(target)))
    return { ok = true, msg = L('confiscated_cop', n) }
end, 2000)

exports('ArrestPlayer', function(target) return Police.Confiscate(target) end)
exports('GetHouseEvidence', function(houseId) return Police.GetEvidence(houseId) end)
