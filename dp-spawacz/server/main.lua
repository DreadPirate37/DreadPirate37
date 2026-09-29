-- ==========================================================================
--  dp-spawacz – serwer: zlecenia, sesje spawania, walidacja, wypłaty, XP
--  Serwer jest jedynym źródłem prawdy: sam generuje zadania i seedy, liczy
--  jakość z wag, pilnuje czasu, odległości i jednorazowych tokenów.
-- ==========================================================================
local Contracts = {}   -- [src] = kontrakt
local Offers = {}      -- [src] = { at = os.time(), list = {...} }
local Sessions = {}    -- [src] = { taskId, token, started }
local Profiles = {}    -- cache profili po identyfikatorze

local function dbg(...)
    if Config.Debug then print('^3[dp-spawacz]^7', ...) end
end

-- --------------------------------------------------------------------------
--  Callbacki (lekki system bez zależności)
-- --------------------------------------------------------------------------
local handlers, lastCall = {}, {}

local function register(name, fn) handlers[name] = fn end

RegisterNetEvent('dp-spawacz:server:cb', function(name, id, ...)
    local src = source
    if type(id) ~= 'number' or type(name) ~= 'string' then return end
    local h = handlers[name]
    if not h then return TriggerClientEvent('dp-spawacz:client:cb', src, id, nil) end
    lastCall[src] = lastCall[src] or {}
    local now = GetGameTimer()
    if lastCall[src][name] and now - lastCall[src][name] < 250 then
        return TriggerClientEvent('dp-spawacz:client:cb', src, id, nil)
    end
    lastCall[src][name] = now
    local ok, res = pcall(h, src, ...)
    if not ok then
        print(('^1[dp-spawacz] błąd w %s: %s^7'):format(name, res))
        res = { ok = false, msg = L('error') }
    end
    TriggerClientEvent('dp-spawacz:client:cb', src, id, res)
end)

-- --------------------------------------------------------------------------
--  Profil / progresja (KVP – bez bazy danych)
-- --------------------------------------------------------------------------
local function levelFor(xp)
    local lvl = 1
    for i, l in ipairs(Config.Levels) do
        if xp >= l.xp then lvl = i end
    end
    return lvl
end

local function getProfile(src)
    local id = Bridge.GetIdentifier(src)
    if not id then return nil end
    if Profiles[id] then return Profiles[id] end
    local raw = GetResourceKvpString('prof:' .. id)
    local data = raw and json.decode(raw) or {}
    local p = {
        id = id,
        xp = tonumber(data.xp) or 0,
        tasks = tonumber(data.tasks) or 0,
        earned = tonumber(data.earned) or 0,
        best = data.best,
    }
    Profiles[id] = p
    return p
end

local gradeRank = { S = 6, A = 5, B = 4, C = 3, D = 2, F = 1 }

local function saveProfile(p)
    SetResourceKvp('prof:' .. p.id, json.encode({ xp = p.xp, tasks = p.tasks, earned = p.earned, best = p.best }))
end

local function profileView(p)
    local lvl = levelFor(p.xp)
    local nextL = Config.Levels[lvl + 1]
    local unlocks = {}
    local function add(list, key)
        for k, v in pairs(list) do
            unlocks[#unlocks + 1] = { label = v.label, level = v.minLevel, ok = lvl >= v.minLevel, key = key .. k }
        end
    end
    add(Config.Processes, 'p')
    add(Config.Materials, 'm')
    add(Config.Positions, 'o')
    add(Config.Types, 't')
    table.sort(unlocks, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        return a.key < b.key
    end)
    return {
        level = lvl,
        label = Config.Levels[lvl].label,
        xp = p.xp,
        curXp = Config.Levels[lvl].xp,
        nextXp = nextL and nextL.xp or nil,
        nextLabel = nextL and nextL.label or nil,
        stats = { tasks = p.tasks, earned = p.earned, best = p.best },
        unlocks = unlocks,
    }
end

-- --------------------------------------------------------------------------
--  Uprawnienia
-- --------------------------------------------------------------------------
local function hasJob(src)
    if not Config.Job.required then return true end
    local job = Bridge.GetJob(src)
    for _, n in ipairs(Config.Job.names) do
        if n == job then return true end
    end
    return false
end

local function pedCoords(src)
    local ped = GetPlayerPed(src)
    if ped == 0 then return nil end
    return GetEntityCoords(ped)
end

local function atDepot(src)
    local c = pedCoords(src)
    return c and #(c - Config.Depot.ped.coords.xyz) <= Config.Depot.finishRadius
end

-- --------------------------------------------------------------------------
--  Generowanie zadań
-- --------------------------------------------------------------------------
local function pick(t) return t[math.random(#t)] end

local function pickWeighted(keys, map)
    local total = 0
    for _, k in ipairs(keys) do total = total + (map[k].weight or 1) end
    local r = math.random() * total
    for _, k in ipairs(keys) do
        r = r - (map[k].weight or 1)
        if r <= 0 then return k end
    end
    return keys[#keys]
end

local function unlocked(map, lvl)
    local out = {}
    for k, v in pairs(map) do
        if lvl >= v.minLevel then out[#out + 1] = k end
    end
    table.sort(out)
    return out
end

local function taskBasePay(t, lvl)
    local P = Config.Payment
    local p = P.basePerTask
        * Config.Types[t.type].pay
        * Config.Materials[t.material].pay
        * Config.Positions[t.position].pay
        * Config.Processes[t.process].pay
    p = p * (1 + (t.passes - 1) * P.perExtraPass) * (1 + (t.difficulty - 1) * P.perDifficulty)
    return p * Config.Levels[lvl].payMult
end

local function qualityCurve(q)
    return 0.3 + 0.9 * (q / 100) ^ 1.5
end

local function genTask(site, spot, lvl)
    local types = {}
    for _, ty in ipairs(spot.types) do
        if Config.Types[ty] and lvl >= Config.Types[ty].minLevel then types[#types + 1] = ty end
    end
    if #types == 0 then return nil end
    local ty = pick(types)

    local mats = unlocked(Config.Materials, lvl)
    local mat = pick(mats)
    local procs = {}
    for _, pr in ipairs(Config.Materials[mat].processes) do
        if Config.Processes[pr] and lvl >= Config.Processes[pr].minLevel then procs[#procs + 1] = pr end
    end
    if #procs == 0 then mat, procs = 'steel', { 'MMA' } end
    local proc = pick(procs)

    local pos = pickWeighted(unlocked(Config.Positions, lvl), Config.Positions)
    local range = Config.Thickness[lvl] or { 3, 6 }
    local tmin, tmax = range[1], range[2]
    if proc == 'MMA' then tmin = math.max(3, tmin) end
    if proc == 'TIG' then tmax = math.min(6, tmax) end
    local th = math.random(tmin, math.max(tmin, tmax))
    local passes = th <= 4 and 1 or (th <= 8 and 2 or 3)
    if proc == 'TIG' then passes = th <= 3 and 1 or 2 end

    local diff = site.tier + (pos == 'overhead' and 1 or 0) + math.random(0, 1) - 1 + math.floor((lvl - 1) / 2)
    diff = math.max(1, math.min(5, diff))

    local props = spot.props or Config.Types[ty].props
    return {
        type = ty, material = mat, process = proc, position = pos,
        thickness = th, passes = passes, difficulty = diff,
        coords = spot.coords, prop = props and pick(props) or nil,
    }
end

local function shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

local function genOffer(lvl)
    local sites = {}
    for _, s in ipairs(Config.Sites) do
        if lvl >= (s.minLevel or 1) then sites[#sites + 1] = s end
    end
    if #sites == 0 then return nil end
    local site = pick(sites)
    local spots = shuffle({ table.unpack(site.spots) })
    local want = math.random(site.tasks[1], math.min(site.tasks[2], #spots))
    local tasks, est, xp = {}, 0, 0
    for i = 1, #spots do
        if #tasks >= want then break end
        local t = genTask(site, spots[i], lvl)
        if t then
            tasks[#tasks + 1] = t
            est = est + taskBasePay(t, lvl) * qualityCurve(80)
            xp = xp + math.floor(Config.XP.perTask * (0.6 + 0.2 * t.difficulty) * 0.8 ^ 1.2)
        end
    end
    if #tasks == 0 then return nil end
    est = est * (1 + Config.Payment.contractBonus)
    return {
        id = ('%06d'):format(math.random(0, 999999)),
        site = site.key,
        tier = site.tier,
        tasks = tasks,
        estPay = math.floor(est),
        estXp = xp,
        deposit = Config.Vehicle.enabled and Config.Vehicle.deposit or 0,
    }
end

local function siteByKey(key)
    for _, s in ipairs(Config.Sites) do
        if s.key == key then return s end
    end
end

local function offerView(o)
    local tasks = {}
    for i, t in ipairs(o.tasks) do
        tasks[i] = {
            typeLabel = Config.Types[t.type].label,
            materialLabel = Config.Materials[t.material].label,
            process = Config.Processes[t.process].label,
            positionLabel = Config.Positions[t.position].label,
            thickness = t.thickness,
            passes = t.passes,
        }
    end
    return { id = o.id, siteLabel = siteByKey(o.site).label, tier = o.tier, tasks = tasks, estPay = o.estPay, estXp = o.estXp, deposit = o.deposit }
end

local function getOffers(src, lvl)
    local o = Offers[src]
    if o and os.time() - o.at < Config.Offers.refresh and o.lvl == lvl and #o.list > 0 then return o.list end
    local list = {}
    for _ = 1, Config.Offers.count do
        local of = genOffer(lvl)
        if of then list[#list + 1] = of end
    end
    Offers[src] = { at = os.time(), list = list, lvl = lvl }
    return list
end

-- --------------------------------------------------------------------------
--  Widoki dla klienta
-- --------------------------------------------------------------------------
local function contractView(c)
    local tasks = {}
    for i, t in ipairs(c.tasks) do
        tasks[i] = {
            id = i,
            coords = t.coords,
            prop = t.prop,
            type = t.type,
            typeLabel = Config.Types[t.type].label,
            done = t.done or false,
            failed = t.failed or false,
            grade = t.grade,
        }
    end
    return { siteLabel = c.siteLabel, center = c.center, tasks = tasks, vehicle = Config.Vehicle.enabled }
end

local function remaining(c)
    local n = 0
    for _, t in ipairs(c.tasks) do
        if not t.done and not t.failed then n = n + 1 end
    end
    return n
end

local function overview(src)
    local p = getProfile(src)
    local pv = profileView(p)
    local data = { profile = pv }
    local c = Contracts[src]
    if c then
        local tasks = {}
        for i, t in ipairs(c.tasks) do
            tasks[i] = { typeLabel = Config.Types[t.type].label, done = t.done, failed = t.failed, grade = t.grade }
        end
        data.active = { siteLabel = c.siteLabel, tasks = tasks, left = remaining(c), atDepot = atDepot(src) }
    else
        local list = getOffers(src, pv.level)
        data.offers = {}
        for i, o in ipairs(list) do data.offers[i] = offerView(o) end
    end
    return data
end

-- --------------------------------------------------------------------------
--  Pojazd / kaucja
-- --------------------------------------------------------------------------
local function settleVehicle(src, c)
    if not Config.Vehicle.enabled or not c.deposit or c.deposit <= 0 then return 0 end
    local refund = 0
    if c.van then
        local ent = NetworkGetEntityFromNetworkId(c.van)
        if ent ~= 0 and DoesEntityExist(ent) then
            local dist = #(GetEntityCoords(ent) - Config.Depot.vehicleSpawn.xyz)
            if dist <= Config.Vehicle.returnRadius then
                local body = math.max(0.0, math.min(1000.0, GetVehicleBodyHealth(ent)))
                local engine = math.max(0.0, math.min(1000.0, GetVehicleEngineHealth(ent)))
                refund = math.floor(c.deposit * math.min(body, engine) / 1000.0)
                DeleteEntity(ent)
            end
        end
    end
    if refund > 0 then Bridge.AddMoney(src, Config.Vehicle.depositAccount, refund, 'dp-spawacz-kaucja') end
    return refund
end

local function clearContract(src, deleteVan)
    local c = Contracts[src]
    if c and deleteVan and c.van then
        local ent = NetworkGetEntityFromNetworkId(c.van)
        if ent ~= 0 and DoesEntityExist(ent) then DeleteEntity(ent) end
    end
    Contracts[src] = nil
    Sessions[src] = nil
end

-- --------------------------------------------------------------------------
--  Callbacki gry
-- --------------------------------------------------------------------------
register('overview', function(src)
    if not hasJob(src) then return { ok = false, msg = L('no_job') } end
    return { ok = true, data = overview(src) }
end)

register('accept', function(src, offerId)
    if not hasJob(src) then return { ok = false, msg = L('no_job') } end
    if Contracts[src] then return { ok = false, msg = L('has_contract') } end
    if not atDepot(src) then return { ok = false, msg = L('not_at_depot') } end
    local p = getProfile(src)
    local lvl = levelFor(p.xp)
    local o = Offers[src]
    local offer
    if o then
        for _, of in ipairs(o.list) do
            if of.id == offerId then offer = of end
        end
    end
    if not offer then return { ok = false, msg = L('offer_gone') } end
    local site = siteByKey(offer.site)
    if lvl < (site.minLevel or 1) then return { ok = false, msg = L('level_low') } end
    if offer.deposit > 0 and not Bridge.RemoveMoney(src, Config.Vehicle.depositAccount, offer.deposit, 'dp-spawacz-kaucja') then
        return { ok = false, msg = L('no_money_deposit', offer.deposit) }
    end
    local tasks = {}
    for i, t in ipairs(offer.tasks) do
        tasks[i] = {
            type = t.type, material = t.material, process = t.process, position = t.position,
            thickness = t.thickness, passes = t.passes, difficulty = t.difficulty,
            coords = t.coords, prop = t.prop, attempts = 0, paid = 0,
        }
    end
    Contracts[src] = {
        site = site.key, siteLabel = site.label, center = site.center,
        tasks = tasks, deposit = offer.deposit, started = os.time(), lvl = lvl,
    }
    Offers[src] = nil
    dbg(('gracz %d przyjął zlecenie %s (%d zadań)'):format(src, site.key, #tasks))
    return { ok = true, msg = L('accepted', site.label), contract = contractView(Contracts[src]) }
end)

register('registerVan', function(src, netId)
    local c = Contracts[src]
    if c and type(netId) == 'number' and not c.van then c.van = netId end
    return true
end)

register('startTask', function(src, taskId)
    local c = Contracts[src]
    if not c then return { ok = false, msg = L('no_contract') } end
    local t = c.tasks[tonumber(taskId) or -1]
    if not t or t.done or t.failed then return { ok = false, msg = L('error') } end
    if Sessions[src] then return { ok = false, msg = L('task_active') } end
    local pc = pedCoords(src)
    if not pc or #(pc.xy - t.coords.xy) > Config.Security.maxDistance then return { ok = false, msg = L('too_far') } end
    t.seed = math.random(1, 2147483646)
    local token = ('%08x%08x'):format(math.random(0, 0x7fffffff), math.random(0, 0x7fffffff))
    Sessions[src] = { taskId = taskId, token = token, started = os.time() }
    return {
        ok = true,
        task = {
            token = token, seed = t.seed, type = t.type, material = t.material, process = t.process,
            thickness = t.thickness, position = t.position, passes = t.passes, difficulty = t.difficulty,
        },
    }
end)

register('abortTask', function(src)
    Sessions[src] = nil
    return true
end)

local function gradeFor(q)
    for _, g in ipairs(Config.Scoring.grades) do
        if q >= g[1] then return g[2] end
    end
    return 'F'
end

local function num(v, lo, hi)
    v = tonumber(v) or 0
    if v ~= v then v = 0 end -- NaN
    return math.max(lo, math.min(hi, v))
end

register('finishTask', function(src, data)
    local s = Sessions[src]
    local c = Contracts[src]
    if not s or not c or type(data) ~= 'table' or data.token ~= s.token then
        return { ok = false, msg = L('session_invalid') }
    end
    Sessions[src] = nil
    local t = c.tasks[s.taskId]
    if not t or t.done or t.failed then return { ok = false, msg = L('session_invalid') } end

    -- walidacja czasu i pozycji
    local elapsed = os.time() - s.started
    local minT = Config.Security.minSecondsBase + Config.Security.minSecondsPerPass * t.passes
    local pc = pedCoords(src)
    local far = not pc or #(pc.xy - t.coords.xy) > Config.Security.maxDistance
    if elapsed < minT or elapsed > Config.Security.maxSeconds or far then
        print(('^1[dp-spawacz] odrzucono wynik gracza %d (%s): czas=%ds (min %ds), daleko=%s^7'):format(src, GetPlayerName(src) or '?', elapsed, minT, tostring(far)))
        return { ok = false, msg = L('suspicious') }
    end

    -- ocena liczona po stronie serwera
    local sc = type(data.scores) == 'table' and data.scores or {}
    local q = 0
    for k, w in pairs(Config.Scoring.weights) do q = q + num(sc[k], 0, 100) * w end
    local burn = type(data.defects) == 'table' and num(data.defects.burn, 0, 999) or 0
    if burn > 0 then q = math.min(q, 90 - (burn - 1) * 6) end
    q = num(q, 0, 100)
    local grade = gradeFor(q)
    local p = getProfile(src)
    local lvlBefore = levelFor(p.xp)
    t.attempts = t.attempts + 1

    local res = { ok = true, quality = q, grade = grade }
    if grade == 'F' then
        local left = Config.Payment.maxAttempts - t.attempts
        if left <= 0 then t.failed = true end
        res.failed = true
        res.attemptsLeft = math.max(0, left)
        res.pay = 0
        res.xp = Config.XP.failXp
    else
        local base = taskBasePay(t, lvlBefore) * qualityCurve(q)
        local bonusPct = Config.Payment.gradeBonus[grade] or 0
        local bonus = math.floor(base * bonusPct)
        local pay = math.floor(base) + bonus
        Bridge.AddMoney(src, Config.PayAccount, pay, 'dp-spawacz-spaw')
        t.done, t.grade, t.paid = true, grade, pay
        res.pay, res.bonus = pay, bonus
        res.xp = math.floor(Config.XP.perTask * (0.6 + 0.2 * t.difficulty) * (q / 100) ^ 1.2) + (Config.XP.gradeBonus[grade] or 0)
        p.tasks = p.tasks + 1
        p.earned = p.earned + pay
        if not p.best or gradeRank[grade] > (gradeRank[p.best] or 0) then p.best = grade end
    end
    p.xp = p.xp + res.xp
    local lvlAfter = levelFor(p.xp)
    if lvlAfter > lvlBefore then
        res.levelUp = true
        res.levelLabel = Config.Levels[lvlAfter].label
    end
    saveProfile(p)
    res.contract = contractView(c)
    res.left = remaining(c)
    dbg(('gracz %d: zadanie %d jakość %.1f (%s) wypłata %s'):format(src, s.taskId, q, grade, tostring(res.pay)))
    TriggerEvent('dp-spawacz:taskFinished', src, { quality = q, grade = grade, pay = res.pay or 0, type = t.type })
    return res
end)

register('finishContract', function(src)
    local c = Contracts[src]
    if not c then return { ok = false, msg = L('no_contract') } end
    if not atDepot(src) then return { ok = false, msg = L('not_at_depot') } end
    if Sessions[src] then return { ok = false, msg = L('busy') } end
    local allDone, sum = true, 0
    for _, t in ipairs(c.tasks) do
        if not t.done then allDone = false end
        sum = sum + (t.paid or 0)
    end
    local bonus = 0
    if allDone then
        bonus = math.floor(sum * Config.Payment.contractBonus)
        Bridge.AddMoney(src, Config.PayAccount, bonus, 'dp-spawacz-premia')
        local p = getProfile(src)
        p.earned = p.earned + bonus
        saveProfile(p)
    end
    local refund = settleVehicle(src, c)
    clearContract(src, false)
    return { ok = true, msg = L('finished', bonus, refund), close = true }
end)

register('cancelContract', function(src)
    local c = Contracts[src]
    if not c then return { ok = false, msg = L('no_contract') } end
    local refund = settleVehicle(src, c)
    clearContract(src, true)
    local msg = L('cancelled')
    if Config.Vehicle.enabled and c.deposit > 0 and refund == 0 then msg = msg .. ' ' .. L('deposit_lost') end
    return { ok = true, msg = msg, close = true }
end)

-- --------------------------------------------------------------------------
--  Sprzątanie
-- --------------------------------------------------------------------------
AddEventHandler('playerDropped', function()
    local src = source
    clearContract(src, true)
    Offers[src] = nil
    lastCall[src] = nil
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for src in pairs(Contracts) do clearContract(src, true) end
end)

-- --------------------------------------------------------------------------
--  Eksporty
-- --------------------------------------------------------------------------
exports('GetWelderLevel', function(src)
    local p = getProfile(src)
    return p and levelFor(p.xp) or 1
end)

exports('AddWelderXP', function(src, amount)
    local p = getProfile(src)
    if not p then return false end
    p.xp = math.max(0, p.xp + (tonumber(amount) or 0))
    saveProfile(p)
    return true
end)

math.randomseed(os.time())
print(('^2[dp-spawacz]^7 uruchomiono (framework: %s)'):format(Bridge.name))
