-- ==========================================================================
--  dp-dziupla – serwer: rozbiórka (stanowiska, części, sesje demontażu,
--  noszenie, stół warsztatowy, montażownica, zgniatarka, przebitka VIN)
-- ==========================================================================
local Jobs = {}       -- [jobId] = job
local ByNet = {}      -- [netId] = jobId
local Sessions = {}   -- [src] = { kind, token, ... }
local Carry = {}      -- [src] = przedmiot niesiony na regał
local jobSeq = 0

local S = Config.Security

local blacklist = {}
for _, m in ipairs(Config.BlacklistModels) do blacklist[joaat(m)] = true end

-- --------------------------------------------------------------------------
--  Pomocnicze
-- --------------------------------------------------------------------------
local function vehFromNet(netId)
    if type(netId) ~= 'number' then return nil end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) or GetEntityType(veh) ~= 2 then return nil end
    return veh
end

local function nearEntity(src, ent, r)
    local c = DZ.PedCoords(src)
    return c and #(c - GetEntityCoords(ent)) <= r
end

local function occupied(veh)
    for seat = -1, 6 do
        if GetPedInVehicleSeat(veh, seat) ~= 0 then return true end
    end
    return false
end

local function trimPlate(p) return (p or ''):gsub('^%s+', ''):gsub('%s+$', '') end

local function publish(job)
    if not DoesEntityExist(job.veh) then return end
    local parts = {}
    for id, pt in pairs(job.parts) do parts[id] = { s = pt.s, c = pt.c } end
    job.ver = (job.ver or 0) + 1
    Entity(job.veh).state:set('dpChop', {
        id = job.id, mode = job.mode, lift = job.lift, moving = job.moving, label = job.label,
        flags = job.flags, parts = parts, ver = job.ver, ready = job.revinReady, shop = job.shop,
    }, true)
end

local function sessionOf(src, token, kind)
    local s = Sessions[src]
    if not s or s.kind ~= kind or type(token) ~= 'string' or s.token ~= token then return nil end
    return s
end

local function releasePart(src)
    local s = Sessions[src]
    if not s or s.kind ~= 'part' then return end
    local job = Jobs[s.jobId]
    if job and job.parts[s.partId] and job.parts[s.partId].s == 'busy' then
        job.parts[s.partId].s = 'on'
        job.parts[s.partId].by = nil
        publish(job)
    end
    Sessions[src] = nil
end

local function endJob(job, deleteVeh, keepFrozen)
    Jobs[job.id] = nil
    ByNet[job.net] = nil
    for src, s in pairs(Sessions) do
        if s.jobId == job.id then Sessions[src] = nil end
    end
    if DoesEntityExist(job.veh) then
        Entity(job.veh).state:set('dpChop', nil, true)
        if deleteVeh then
            DeleteEntity(job.veh)
        elseif not keepFrozen then
            SetEntityCoords(job.veh, job.base.x, job.base.y, job.base.z, false, false, false, false)
            FreezeEntityPosition(job.veh, false)
            SetVehicleDoorsLocked(job.veh, 1)
        end
    end
end

local function snapSanitize(snap, veh)
    if type(snap) ~= 'table' then return nil end
    local s = {
        name = type(snap.name) == 'string' and snap.name:sub(1, 32) or 'CAR',
        label = type(snap.label) == 'string' and snap.label:sub(1, 48) or 'Auto',
        class = math.floor(DZ.num(snap.class, 0, 22)),
        body = DZ.num(snap.body, 0, 1000),
        engine = DZ.num(snap.engine, -4000, 1000),
        tank = DZ.num(snap.tank, -1000, 1000),
        wheels = math.floor(DZ.num(snap.wheels, 0, 10)),
        doors = {}, doorDmg = {}, tyres = {}, hl = {}, bumperOff = {}, windows = {}, bones = {}, mods = {},
    }
    for i = 1, 6 do
        s.doors[i] = type(snap.doors) == 'table' and snap.doors[i] == true
        s.doorDmg[i] = type(snap.doorDmg) == 'table' and snap.doorDmg[i] == true
    end
    for _, b in ipairs(Parts.Bones) do
        s.bones[b] = type(snap.bones) == 'table' and snap.bones[b] == true
        s.tyres[b] = type(snap.tyres) == 'table' and snap.tyres[b] == true
    end
    for _, k in ipairs({ 'l', 'r' }) do s.hl[k] = type(snap.hl) == 'table' and snap.hl[k] == true end
    for _, k in ipairs({ 'f', 'r' }) do s.bumperOff[k] = type(snap.bumperOff) == 'table' and snap.bumperOff[k] == true end
    for _, k in ipairs({ 'front', 'rear' }) do s.windows[k] = type(snap.windows) == 'table' and snap.windows[k] == true end
    local m = type(snap.mods) == 'table' and snap.mods or {}
    for _, k in ipairs({ 'spoiler', 'bumperF', 'bumperR', 'exhaust', 'hood', 'engine', 'brakes', 'trans', 'susp', 'wheels' }) do
        s.mods[k] = math.floor(DZ.num(m[k], -1, 60))
    end
    s.mods.turbo = m.turbo == true
    s.mods.xenon = m.xenon == true
    -- model musi się zgadzać z tym, co widzi serwer
    if tonumber(snap.model) ~= GetEntityModel(veh) then return nil end
    return s
end

local function bayFree(shopKey, bayIdx)
    for _, j in pairs(Jobs) do
        if j.shop == shopKey and j.bay == bayIdx then return false end
    end
    return true
end

-- --------------------------------------------------------------------------
--  Start rozbiórki / przebitki
-- --------------------------------------------------------------------------
local function startJob(src, netId, rawSnap, mode)
    if not DZ.HasAccess(src) then return { ok = false, msg = L('no_access') } end
    if Bridge.CountPolice() < Config.Police.minForChop then return { ok = false, msg = L('police_low') } end
    local shop = DZ.ShopAt(src)
    if not shop then return { ok = false, msg = L('not_at_shop') } end
    if Sessions[src] then return { ok = false, msg = L('busy') } end
    local veh = vehFromNet(netId)
    if not veh then return { ok = false, msg = L('chop_not_vehicle') } end
    if ByNet[netId] then return { ok = false, msg = L('chop_already') } end
    if occupied(veh) then return { ok = false, msg = L('chop_occupied') } end
    local p = DZ.Profile(src)

    local vc = GetEntityCoords(veh)
    local bayIdx, heading
    if mode == 'revin' then
        if not shop.vinBay or #(vc.xy - shop.vinBay.xy) > Config.Bay.radius then return { ok = false, msg = L('chop_not_vehicle') } end
        if DZ.Level(p) < Config.Revin.minLevel then return { ok = false, msg = L('revin_level', Config.Revin.minLevel) } end
        if not DZ.HasTool(p, 'stamps') then return { ok = false, msg = L('part_tool', Config.Tools.stamps.label) } end
        bayIdx, heading = 0, shop.vinBay.w
    else
        for i, b in ipairs(shop.bays) do
            if #(vc.xy - b.xy) <= Config.Bay.radius then bayIdx, heading = i, b.w end
        end
        if not bayIdx then return { ok = false, msg = L('chop_not_vehicle') } end
    end
    if not bayFree(shop.key, bayIdx) then return { ok = false, msg = L('chop_bay_taken') } end

    local model = GetEntityModel(veh)
    if blacklist[model] then return { ok = false, msg = L('chop_blacklisted') } end
    local snap = snapSanitize(rawSnap, veh)
    if not snap then
        DZ.warn(src, 'niezgodny snapshot pojazdu')
        return { ok = false, msg = L('suspicious') }
    end
    if Config.ClassMult[snap.class] == false or Config.ClassMult[snap.class] == nil then return { ok = false, msg = L('chop_class') } end
    local plate = trimPlate(GetVehicleNumberPlateText(veh))
    local target = Entity(veh).state.dpTarget
    if not target and ServerHooks.IsVehicleOwned(plate) then return { ok = false, msg = L('chop_owned') } end

    jobSeq = jobSeq + 1
    local fx = DZ.Fx(p)
    local classMult = Logic.ClassMult(snap)
    local job = {
        id = jobSeq, mode = mode, net = netId, veh = veh, shop = shop.key, bay = bayIdx, owner = src,
        started = os.time(), touched = os.time(), snap = snap, label = snap.label, plate = plate,
        parts = {}, flags = {}, lift = 0, base = vc, heading = heading, stampQ = {},
    }
    for _, id in ipairs(Logic.BuildParts(mode, snap)) do
        local def = Parts.ById[id]
        local base = Logic.BaseCond(def, snap) * 100 + math.random(-6, 6) + (fx.eye and 4 or 0)
        job.parts[id] = {
            s = 'on',
            c = math.floor(math.max(5, math.min(100, base))),
            m = classMult * Logic.ModMult(def, snap),
            done = {},
        }
    end
    if mode == 'revin' then
        local chars = 'ABCDEFGHJKLMNPRSTUVWXYZ0123456789'
        local vin = {}
        for i = 1, 8 do
            local k = math.random(#chars)
            vin[i] = chars:sub(k, k)
        end
        job.vin = vin
    end

    Jobs[job.id] = job
    ByNet[netId] = job.id
    SetEntityCoords(veh, vc.x, vc.y, vc.z, false, false, false, false)
    SetEntityHeading(veh, heading)
    FreezeEntityPosition(veh, true)
    SetVehicleDoorsLocked(veh, 2)
    publish(job)

    if mode == 'chop' then
        p.stats.cars = p.stats.cars + 1
        DZ.Save(p)
        if DZ.OnChopStart then DZ.OnChopStart(src, veh, snap, job) end
    end
    DZ.dbg(('job %d (%s) %s przez %d, części: %d'):format(job.id, mode, snap.label, src, #Logic.BuildParts(mode, snap)))
    return { ok = true, id = job.id, msg = mode == 'chop' and L('chop_started', snap.label) or nil }
end

DZ.register('chopStart', function(src, netId, snap) return startJob(src, netId, snap, 'chop') end)
DZ.register('revinStart', function(src, netId, snap) return startJob(src, netId, snap, 'revin') end)

DZ.register('chopCancel', function(src, jobId)
    local job = Jobs[tonumber(jobId) or -1]
    if not job then return { ok = false } end
    if not nearEntity(src, job.veh, 12.0) then return { ok = false, msg = L('too_far') } end
    for _, pt in pairs(job.parts) do
        if pt.s == 'busy' then return { ok = false, msg = L('lift_busy') } end
    end
    endJob(job, false)
    return { ok = true, msg = L('chop_cancelled') }
end)

-- --------------------------------------------------------------------------
--  Podnośnik
-- --------------------------------------------------------------------------
DZ.register('lift', function(src, jobId, level)
    local job = Jobs[tonumber(jobId) or -1]
    level = math.floor(DZ.num(level, 0, #Config.Bay.lift - 1))
    if not job or job.mode ~= 'chop' then return { ok = false } end
    if job.moving then return { ok = false, msg = L('busy') } end
    if not nearEntity(src, job.veh, S.maxDistance) then return { ok = false, msg = L('too_far') } end
    for _, pt in pairs(job.parts) do
        if pt.s == 'busy' then return { ok = false, msg = L('lift_busy') } end
    end
    if level == job.lift then return { ok = true } end
    job.moving = true
    publish(job)
    local from = Config.Bay.lift[job.lift + 1]
    local to = Config.Bay.lift[level + 1]
    CreateThread(function()
        local steps = 30
        for i = 1, steps do
            if not DoesEntityExist(job.veh) then return end
            local z = job.base.z + from + (to - from) * (i / steps)
            SetEntityCoords(job.veh, job.base.x, job.base.y, z, false, false, false, false)
            Wait(math.floor(Config.Bay.liftTime / steps))
        end
        job.lift = level
        job.moving = nil
        job.touched = os.time()
        publish(job)
    end)
    return { ok = true, msg = L('lift_set', level) }
end)

-- --------------------------------------------------------------------------
--  Demontaż części
-- --------------------------------------------------------------------------
DZ.register('partBegin', function(src, jobId, partId)
    local job = Jobs[tonumber(jobId) or -1]
    if not job or type(partId) ~= 'string' then return { ok = false, msg = L('error') } end
    if Sessions[src] then return { ok = false, msg = L('busy') } end
    if Carry[src] then return { ok = false, msg = L('carry_first') } end
    if job.moving then return { ok = false, msg = L('busy') } end
    if not nearEntity(src, job.veh, S.maxDistance) then return { ok = false, msg = L('too_far') } end
    local pt = job.parts[partId]
    local def = Parts.ById[partId]
    if not pt or not def then return { ok = false, msg = L('error') } end
    if pt.s == 'done' then return { ok = false, msg = L('part_done') } end
    if pt.s == 'busy' then return { ok = false, msg = L('part_locked') } end
    local miss = Logic.Blockers(def, job, job.snap)
    if #miss > 0 then return { ok = false, msg = L('part_blocked', table.concat(miss, ', ')) } end
    local p = DZ.Profile(src)
    if def.tool and not DZ.HasTool(p, def.tool) then return { ok = false, msg = L('part_tool', Config.Tools[def.tool].label) } end
    if not def.op and DZ.WhFree(p) <= 0 then return { ok = false, msg = L('warehouse_full') } end

    local spec, remaining = {}, 0
    for i, f in ipairs(def.F) do
        local rust = 0
        if f.rust and math.random() < f.rust then rust = 0.35 + 0.65 * math.random() end
        spec[i] = { i = i, rust = math.floor(rust * 100) / 100, done = pt.done[i] == true }
        if f.t == 'stamp' and job.vin then spec[i].ch = job.vin[i] end
        if not spec[i].done then remaining = remaining + 1 end
    end

    pt.s, pt.by = 'busy', src
    job.touched = os.time()
    publish(job)
    local token = DZ.token()
    Sessions[src] = { kind = 'part', token = token, jobId = job.id, partId = partId, started = os.time(), remaining = remaining }

    local fx = DZ.Fx(p)
    local tdef = def.type and Parts.Types[def.type]
    local est
    if fx.eye and tdef and not def.shell then
        est = DZ.Price(p, { t = def.type, c = pt.c, m = pt.m })
    end
    return {
        ok = true, token = token,
        part = {
            id = partId, label = def.label, typeLabel = tdef and tdef.label or def.label, op = def.op == true,
            cond = pt.c, value = est, F = spec, flags = job.flags, heavy = tdef and tdef.heavy or false,
        },
        ctx = {
            tools = DZ.OwnedTools(p), cons = p.cons, fx = fx, sockets = Parts.Sockets, bits = Parts.Bits,
            vehicle = job.label, lift = job.lift,
        },
    }
end)

local function applySets(job, def, doneList)
    for i in pairs(doneList) do
        local f = def.F[i]
        if f and f.sets then job.flags[f.sets] = true end
    end
end

local function readDone(def, list, into)
    if type(list) ~= 'table' then return end
    for _, i in ipairs(list) do
        i = tonumber(i)
        if i and def.F[i] then into[i] = true end
    end
end

DZ.register('partAbort', function(src, token, done)
    local s = sessionOf(src, token, 'part')
    if not s then return { ok = false } end
    local job = Jobs[s.jobId]
    if job then
        local def = Parts.ById[s.partId]
        local pt = job.parts[s.partId]
        -- postęp zostaje jak w CMS: odkręcone śruby są odkręcone
        readDone(def, done, pt.done)
        applySets(job, def, pt.done)
    end
    releasePart(src)
    return { ok = true }
end)

local function partPenalty(r, fx)
    local n = function(k, hi) return DZ.num(r[k], 0, hi or 50) end
    local pen = 3 * n('broken') + 2 * n('stripped') + 3 * n('snapped') + 4 * n('cut')
        + 1.5 * n('gouge', 30) + 6 * n('spills', 10) + 8 * n('sparks', 10) + 4 * n('bumps', 10)
        + 14 * n('sensitive', 5) * (fx.tech and 0.5 or 1.0)
    if r.fire == true then pen = pen + 20 end
    return pen
end

DZ.register('partFinish', function(src, token, report)
    local s = sessionOf(src, token, 'part')
    if not s or type(report) ~= 'table' then return { ok = false, msg = L('session_invalid') } end
    local job = Jobs[s.jobId]
    local def = Parts.ById[s.partId]
    if not job or not def then
        Sessions[src] = nil
        return { ok = false, msg = L('session_invalid') }
    end
    local pt = job.parts[s.partId]
    local elapsed = os.time() - s.started
    local minT = math.floor(S.partBase + s.remaining * S.perFastener)
    local far = not nearEntity(src, job.veh, S.maxDistance)
    if elapsed < minT or elapsed > S.maxPartSeconds or far then
        DZ.warn(src, ('demontaż %s: %ds (min %ds), daleko=%s'):format(s.partId, elapsed, minT, tostring(far)))
        releasePart(src)
        return { ok = false, msg = L('suspicious') }
    end
    Sessions[src] = nil

    local p = DZ.Profile(src)
    local fx = DZ.Fx(p)
    -- zużyte materiały
    local used = type(report.used) == 'table' and report.used or {}
    for _, k in ipairs({ 'penetrant', 'disc', 'extractor' }) do
        local u = math.floor(DZ.num(used[k], 0, 99))
        p.cons[k] = math.max(0, (p.cons[k] or 0) - u)
    end

    for i in ipairs(def.F) do pt.done[i] = true end
    applySets(job, def, pt.done)
    pt.s, pt.by = 'done', nil
    job.touched = os.time()

    local cond = pt.c - partPenalty(report, fx)
    if report.airbag == true then cond = def.type == 'airbag' and 3 or cond - 30 end
    cond = math.floor(math.max(1, math.min(100, cond)))
    pt.c = cond

    DZ.AddNoise(src, job.shop, DZ.num(report.noise, 0, 20), p)

    local res = { ok = true, cond = cond, label = def.label }
    local tdef = def.type and Parts.Types[def.type]
    local xp = (def.xp or (tdef and tdef.xp) or 5) * (0.6 + 0.4 * cond / 100)

    if def.shell then
        local kg = math.floor((Config.Crusher.kgBase[job.snap.class] or 1200) * 0.65)
        DZ.WhAdd(p, { t = 'scrap', c = 100, m = 1, k = kg, v = job.label })
        res.msg = L('shell_done', kg)
        res.shell = true
        publish(job)
        SetTimeout(1500, function() endJob(job, true) end)
    elseif def.op then
        res.msg = L('op_done', def.label)
        if s.partId == 'vin_stamp' then
            local q = type(report.stamps) == 'table' and report.stamps or {}
            local sum, n = 0, 0
            for i = 1, #def.F do
                sum = sum + DZ.num(q[i], 0, 1)
                n = n + 1
            end
            job.stampQ = n > 0 and sum / n or 0
        elseif s.partId == 'plate_swap' then
            local L3 = 'ABCDEFGHJKLMNPRSTUVWXYZ'
            local function ch() local k = math.random(#L3) return L3:sub(k, k) end
            job.newPlate = ('%d%d%s%s%s%d%d%d'):format(math.random(0, 9), math.random(0, 9), ch(), ch(), ch(), math.random(0, 9), math.random(0, 9), math.random(0, 9))
            SetVehicleNumberPlateText(job.veh, job.newPlate)
            res.plate = job.newPlate
        end
        if job.mode == 'revin' then
            local all = true
            for _, pp in pairs(job.parts) do
                if pp.s ~= 'done' then all = false end
            end
            if all then
                job.revinReady = true
                res.msg = L('revin_done_parts')
            end
        end
        publish(job)
    else
        local item = { t = def.type, c = cond, m = pt.m, v = job.label, cls = job.snap.class }
        local value = DZ.Price(p, item)
        res.value = value
        res.msg = L('part_removed', def.label, cond, value)
        p.stats.parts = p.stats.parts + 1
        if tdef.heavy then
            DZ.WhAdd(p, item)
            res.heavy = true
            res.msg = res.msg .. ' ' .. L('heavy_stored', tdef.label)
        else
            Carry[src] = item
            res.carry = { prop = tdef.prop, kind = tdef.carry or 'box', label = def.label, kg = tdef.kg }
        end
        publish(job)
    end

    DZ.AddXP(src, p, xp)
    DZ.Save(p)
    TriggerEvent('dp-dziupla:partRemoved', src, { part = s.partId, cond = cond, vehicle = job.label })
    return res
end)

-- odłożenie niesionej części na regał
DZ.register('carryStore', function(src)
    local it = Carry[src]
    if not it then return { ok = false } end
    local ok = false
    for _, shop in ipairs(Config.Shops) do
        if DZ.Near(src, shop.shelf, 3.5) then ok = true end
    end
    if not ok then return { ok = false, msg = L('too_far') } end
    local p = DZ.Profile(src)
    Carry[src] = nil
    DZ.WhAdd(p, it)
    DZ.Save(p)
    return { ok = true, msg = L('carry_stored', DZ.ItemLabel(it), #p.wh, DZ.WhCap(p)) }
end)

DZ.register('carryState', function(src)
    return { carrying = Carry[src] ~= nil }
end)

-- --------------------------------------------------------------------------
--  Przebitka: lakier + papiery (koniec pracy na stanowisku)
-- --------------------------------------------------------------------------
DZ.register('revinPaint', function(src, jobId, color, papers)
    local job = Jobs[tonumber(jobId) or -1]
    if not job or job.mode ~= 'revin' or not job.revinReady then return { ok = false, msg = L('error') } end
    if not nearEntity(src, job.veh, S.maxDistance) then return { ok = false, msg = L('too_far') } end
    local valid = false
    color = math.floor(tonumber(color) or -1)
    for _, c in ipairs(Config.Revin.colors) do
        if c[1] == color then valid = true end
    end
    if not valid then return { ok = false } end
    local price = Config.Revin.paintPrice + (papers and Config.Revin.papersPrice or 0)
    if not Bridge.RemoveMoney(src, Config.ShopAccount, price, 'dp-dziupla-lakiernia') then
        return { ok = false, msg = L('no_money', price) }
    end
    local p = DZ.Profile(src)
    local q = DZ.num(job.stampQ, 0, 1)
    local plate = job.newPlate or job.plate
    SetVehicleColours(job.veh, color, color)
    SetVehicleNumberPlateText(job.veh, plate)
    Entity(job.veh).state:set('dpClean', {
        owner = Bridge.GetIdentifier(src), q = q, papers = papers == true, class = job.snap.class,
        plate = plate, name = job.snap.name, label = job.label,
    }, true)
    Entity(job.veh).state:set('dpTarget', nil, true)
    endJob(job, false, false)
    DZ.AddXP(src, p, 40)
    DZ.Save(p)
    return { ok = true, plate = plate, color = color, net = job.net, msg = L('revin_finished', plate) }
end)

-- --------------------------------------------------------------------------
--  Stół warsztatowy (regeneracja) i montażownica (koło -> felga + opona)
-- --------------------------------------------------------------------------
DZ.register('benchList', function(src, mode)
    local p = DZ.Profile(src)
    local out = {}
    for _, it in ipairs(p.wh) do
        local t = Parts.Types[it.t]
        if t and not it.res then
            local fits = (mode == 'split' and it.t == 'wheel') or (mode ~= 'split' and t.bench and t.bench ~= 'split' and not it.r)
            if fits then out[#out + 1] = DZ.ItemView(p, it) end
        end
    end
    return { ok = true, items = out, cap = DZ.Fx(p).restorer }
end)

DZ.register('benchBegin', function(src, uid, mode)
    if Sessions[src] then return { ok = false, msg = L('busy') } end
    local p = DZ.Profile(src)
    local it = DZ.WhFind(p, tonumber(uid))
    if not it or it.res then return { ok = false, msg = L('error') } end
    local t = Parts.Types[it.t]
    local shopOk = false
    for _, shop in ipairs(Config.Shops) do
        local pt = mode == 'split' and shop.tyre or shop.bench
        if pt and DZ.Near(src, pt, 3.0) then shopOk = true end
    end
    if not shopOk then return { ok = false, msg = L('too_far') } end
    local kind
    if mode == 'split' then
        if it.t ~= 'wheel' then return { ok = false } end
        if not DZ.HasTool(p, 'tyretool') then return { ok = false, msg = L('part_tool', Config.Tools.tyretool.label) } end
        if DZ.WhFree(p) <= 0 then return { ok = false, msg = L('warehouse_full') } end
        kind = 'split'
    else
        if not t or not t.bench or t.bench == 'split' then return { ok = false } end
        if it.r then return { ok = false, msg = L('bench_once') } end
        kind = t.bench
    end
    local token = DZ.token()
    it.res = true
    Sessions[src] = { kind = 'bench', token = token, uid = it.u, mode = kind, started = os.time() }
    return { ok = true, token = token, spec = { mode = kind, seed = math.random(1, 2147483646), label = DZ.ItemLabel(it), cond = it.c, cap = 20 + DZ.Fx(p).restorer } }
end)

local function benchRelease(src)
    local s = Sessions[src]
    if not s or s.kind ~= 'bench' then return end
    local p = DZ.Profile(src)
    local it = p and DZ.WhFind(p, s.uid)
    if it then it.res = nil end
    Sessions[src] = nil
end

DZ.register('benchAbort', function(src, token)
    if sessionOf(src, token, 'bench') then benchRelease(src) end
    return { ok = true }
end)

DZ.register('benchFinish', function(src, token, score)
    local s = sessionOf(src, token, 'bench')
    if not s then return { ok = false, msg = L('session_invalid') } end
    local elapsed = os.time() - s.started
    if elapsed < S.benchMin then
        DZ.warn(src, ('stół: %ds'):format(elapsed))
        benchRelease(src)
        return { ok = false, msg = L('suspicious') }
    end
    local p = DZ.Profile(src)
    local it = DZ.WhFind(p, s.uid)
    Sessions[src] = nil
    if not it then return { ok = false, msg = L('error') } end
    it.res = nil
    score = DZ.num(score, 0, 1)
    local res = { ok = true }
    if s.mode == 'split' then
        DZ.WhTake(p, it.u)
        local rimC = math.floor(math.max(1, math.min(100, it.c + 5 - (1 - score) * 25)))
        local tyreC = math.floor(math.max(1, math.min(100, it.c * 0.9 - (1 - score) * 20)))
        DZ.WhAdd(p, { t = 'rim', c = rimC, m = it.m, v = it.v })
        DZ.WhAdd(p, { t = 'tyre', c = tyreC, m = it.m, v = it.v })
        res.msg = L('split_done', rimC, tyreC)
    else
        local before = it.c
        local gain = math.floor((20 + DZ.Fx(p).restorer) * score)
        it.c = math.min(100, it.c + gain)
        it.r = true
        p.stats.regen = p.stats.regen + 1
        res.msg = L('bench_done', DZ.ItemLabel(it), before, it.c)
    end
    DZ.AddXP(src, p, 6 + math.floor(score * 8))
    DZ.Save(p)
    return res
end)

-- --------------------------------------------------------------------------
--  Zgniatarka
-- --------------------------------------------------------------------------
DZ.register('crush', function(src, netId, rawSnap)
    if not DZ.HasAccess(src) then return { ok = false, msg = L('no_access') } end
    local veh = vehFromNet(netId)
    if not veh then return { ok = false, msg = L('chop_not_vehicle') } end
    local shop
    for _, s in ipairs(Config.Shops) do
        if s.crusher and #(GetEntityCoords(veh) - s.crusher) <= 6.0 and DZ.Near(src, s.crusher, 12.0) then shop = s end
    end
    if not shop then return { ok = false, msg = L('too_far') } end
    if ByNet[netId] then return { ok = false, msg = L('crush_job') } end
    if occupied(veh) then return { ok = false, msg = L('chop_occupied') } end
    if blacklist[GetEntityModel(veh)] then return { ok = false, msg = L('chop_blacklisted') } end
    local snap = snapSanitize(rawSnap, veh)
    if not snap then return { ok = false, msg = L('suspicious') } end
    local plate = trimPlate(GetVehicleNumberPlateText(veh))
    if not Entity(veh).state.dpTarget and ServerHooks.IsVehicleOwned(plate) then return { ok = false, msg = L('chop_owned') } end
    local base = Config.Crusher.kgBase[snap.class]
    if not base then return { ok = false, msg = L('chop_class') } end
    local p = DZ.Profile(src)
    FreezeEntityPosition(veh, true)
    SetVehicleDoorsLocked(veh, 2)
    ByNet[netId] = -1
    local kg = math.floor(base * (0.85 + 0.15 * math.random()))
    local pay = math.floor(kg * Config.Economy.scrapPerKg)
    SetTimeout(Config.Crusher.time, function()
        ByNet[netId] = nil
        if DoesEntityExist(veh) then DeleteEntity(veh) end
        DZ.Earn(src, p, pay, 'zgniatarka')
        DZ.AddXP(src, p, Config.Crusher.xp)
        DZ.Save(p)
        Bridge.Notify(src, L('crush_done', kg, pay), 'good')
    end)
    return { ok = true, time = Config.Crusher.time }
end)

-- --------------------------------------------------------------------------
--  Widok dla klienta: czy auto jest na stanowisku
-- --------------------------------------------------------------------------
function DZ.JobByNet(netId)
    local id = ByNet[netId]
    return id and Jobs[id]
end

-- --------------------------------------------------------------------------
--  Sprzątanie
-- --------------------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(15000)
        local now = os.time()
        for _, job in pairs(Jobs) do
            if not DoesEntityExist(job.veh) then
                endJob(job, false)
            elseif now - job.touched > Config.Bay.maxJobAge then
                endJob(job, false)
            end
        end
    end
end)

DZ.OnDrop[#DZ.OnDrop + 1] = function(src)
    local s = Sessions[src]
    if s and s.kind == 'part' then releasePart(src)
    elseif s and s.kind == 'bench' then benchRelease(src) end
    local it = Carry[src]
    if it then
        -- niesiona część trafia do magazynu, żeby nie przepadła przy crashu
        local p = DZ.Profile(src)
        if p then
            DZ.WhAdd(p, it)
            DZ.Save(p)
        end
        Carry[src] = nil
    end
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, job in pairs(Jobs) do endJob(job, false) end
end)
