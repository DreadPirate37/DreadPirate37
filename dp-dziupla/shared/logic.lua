-- ==========================================================================
--  Logika wspólna dla klienta i serwera (czyste funkcje, bez natywek)
-- ==========================================================================
Logic = {}

local function clamp(v, a, b)
    if v < a then return a end
    if v > b then return b end
    return v
end
Logic.clamp = clamp

function Logic.LevelFor(xp)
    local lvl = 1
    for i, l in ipairs(Config.Levels) do
        if xp >= l.xp then lvl = i end
    end
    return lvl
end

function Logic.Rank(perks, key)
    return perks and tonumber(perks[key]) or 0
end

-- efekty umiejętności w jednym miejscu
function Logic.PerkFx(perks)
    local r = function(k) return Logic.Rank(perks, k) end
    return {
        speed = 1 + 0.12 * r('speed'),
        steady = 1 - 0.30 * r('steady'),          -- mnożnik ryzyka
        quiet = 1 - 0.25 * r('quiet'),
        trader = 1 + 0.05 * r('trader'),
        eye = r('eye') > 0,
        restorer = 10 * r('restorer'),
        thief = r('thief'),
        tech = r('tech') > 0,
        mule = r('mule') > 0,
        contacts = r('contacts'),
    }
end

-- --------------------------------------------------------------------------
--  Części
-- --------------------------------------------------------------------------
function Logic.Available(def, snap)
    if def.avail and not def.avail(snap) then return false end
    local b = def.anchor and def.anchor.bone
    -- część boczna na kości, której model nie ma (np. drzwi tylne w coupe) – brak części
    if b and def.anchor.required and not (snap.bones and snap.bones[b]) then return false end
    return true
end

function Logic.BuildParts(mode, snap)
    local out = {}
    for _, id in ipairs(Parts.Modes[mode] or {}) do
        local def = Parts.ById[id]
        if def and Logic.Available(def, snap) then out[#out + 1] = id end
    end
    return out
end

-- stan bazowy 0..1 wynikający z uszkodzeń auta
function Logic.BaseCond(def, snap)
    local body = clamp((snap.body or 1000) / 1000, 0, 1)
    local engine = clamp((snap.engine or 1000) / 1000, 0, 1)
    local src = def.cond or 'body'
    if src == 'body' then return body end
    if src == 'engine' then return engine end
    if src == 'mech' then return 0.5 * (body + engine) end
    if src == 'interior' then return 0.8 + 0.2 * body end
    if src == 'tank' then return clamp((snap.tank or 1000) / 1000, 0, 1) end
    local kind, arg = src:match('^(%w+):(.+)$')
    if kind == 'door' then
        local dmg = snap.doorDmg and snap.doorDmg[tonumber(arg) + 1]
        return body * (dmg and 0.6 or 1.0)
    elseif kind == 'tyre' then
        local burst = snap.tyres and snap.tyres[arg]
        return (burst and 0.55 or 1.0) * (0.7 + 0.3 * body)
    elseif kind == 'hl' then
        local dmg = snap.hl and snap.hl[arg]
        return dmg and 0.35 or body
    end
    return body
end

-- mnożnik za tuning (lepsze hamulce, turbo, felgi...)
function Logic.ModMult(def, snap)
    local m = def.mod
    if not m or not snap.mods then return 1.0 end
    local v = snap.mods[m.key]
    if v == nil or v == false then return 1.0 end
    if v == true then return m.mult or 1.0 end
    v = tonumber(v) or -1
    if v < 0 then return 1.0 end
    if m.per then return 1 + m.per * (v + 1) end
    return m.mult or 1.0
end

function Logic.ClassMult(snap)
    local name = snap.name and snap.name:lower()
    if name and Config.ModelMult[name] then return Config.ModelMult[name] end
    local c = Config.ClassMult[snap.class or 1]
    return c or 1.0
end

-- wartość części u pasera (bez popytu rynkowego i perków)
function Logic.PartValue(typeKey, cond, mult, kg)
    local t = Parts.Types[typeKey]
    if not t then return 0 end
    if typeKey == 'scrap' then
        return math.floor((kg or 0) * Config.Economy.scrapPerKg)
    end
    local c = clamp((cond or 0) / 100, 0, 1)
    local curve = 0.15 + 0.85 * c ^ Config.Economy.condCurve
    return math.floor(t.base * (mult or 1) * curve * Config.Economy.priceMult)
end

-- czego brakuje, żeby zabrać się za część (lista etykiet)
function Logic.Blockers(def, job, snap)
    local miss = {}
    local req = def.requires
    if type(req) == 'function' then req = req(snap or {}) end
    for _, r in ipairs(req or {}) do
        if r:sub(1, 1) == '@' then
            if not (job.flags and job.flags[r]) then miss[#miss + 1] = Parts.Flags[r] or r end
        else
            local p = job.parts and job.parts[r]
            if p and p.s ~= 'done' then
                local d = Parts.ById[r]
                miss[#miss + 1] = d and d.label or r
            end
        end
    end
    local lift = job.lift or 0
    if def.lift and (lift < def.lift[1] or lift > def.lift[2]) then
        local want = def.lift[1]
        miss[#miss + 1] = want == 0 and 'Opuść podnośnik' or ('Podnośnik na poziom ' .. want)
    end
    return miss
end

function Logic.Pose(def, lift)
    local p = def.pose
    if type(p) == 'table' then return p[lift] or p[1] or 'stand' end
    return p or 'stand'
end

function Logic.GradeLabel(cond)
    if cond >= 85 then return 'bardzo dobry' end
    if cond >= 65 then return 'dobry' end
    if cond >= 40 then return 'średni' end
    if cond >= 20 then return 'słaby' end
    return 'na złom'
end
