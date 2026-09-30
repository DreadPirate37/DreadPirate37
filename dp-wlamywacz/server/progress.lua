-- ==========================================================================
--  Progresja: XP i poziomy (PRO-01), reputacja u kontaktów (PRO-05), heat gracza (POL-08),
--  kara za zatrzymanie (PRO-11)
-- ==========================================================================
Progress = {}
local U = WLM.U

function Progress.Get(src)
    return Store.Profile(SV.P(src).id)
end

function Progress.Level(src)
    local p = Progress.Get(src)
    return p and U.LevelFor(p.xp) or 1
end

function Progress.AddXP(src, amount, reason)
    local p = Progress.Get(src)
    if not p then return end
    amount = math.floor(amount)
    local before = U.LevelFor(p.xp)
    p.xp = math.max(0, p.xp + amount)
    Store.Touch(p.id)
    local after = U.LevelFor(p.xp)
    if after > before then
        SV.Notify(src, L('level_up', Config.Levels[after].label), 'good')
        SV.Client(src, 'levelUp', after, Config.Levels[after].label)
    end
    TriggerEvent('dp-wlamywacz:xp', src, amount, reason)
end

function Progress.Rep(src, key)
    local p = Progress.Get(src)
    return p and (p.rep[key] or 0) or 0
end

function Progress.AddRep(src, key, v)
    local p = Progress.Get(src)
    if not p then return end
    p.rep[key] = math.max(0, math.floor((p.rep[key] or 0) + v))
    Store.Touch(p.id)
end

function Progress.Heat(src)
    local p = Progress.Get(src)
    if not p then return 0 end
    return U.Decay(p.heat, p.heatAt, Config.Heat.tau, os.time())
end

function Progress.AddHeat(src, v)
    local p = Progress.Get(src)
    if not p then return end
    p.heat = Progress.Heat(src) + v
    p.heatAt = os.time()
    Store.Touch(p.id)
end

-- zatrzymanie: utrata części XP postępu w poziomie (PRO-11)
function Progress.Arrested(src)
    local p = Progress.Get(src)
    if not p then return end
    local lvl = U.LevelFor(p.xp)
    local base = Config.Levels[lvl].xp
    local nextXp = Config.Levels[lvl + 1] and Config.Levels[lvl + 1].xp or (base + 2000)
    p.xp = math.max(base, math.floor(p.xp - (nextXp - base) * Config.XP.arrestLoss))
    p.stats.arrests = (p.stats.arrests or 0) + 1
    Store.Touch(p.id)
end

function Progress.View(src)
    local p = Progress.Get(src)
    if not p then return nil end
    local lvl = U.LevelFor(p.xp)
    local nextL = Config.Levels[lvl + 1]
    return {
        xp = p.xp, level = lvl, label = Config.Levels[lvl].label,
        next = nextL and nextL.xp or nil, base = Config.Levels[lvl].xp,
        rep = p.rep, stats = p.stats, heat = math.floor(Progress.Heat(src)),
    }
end

exports('GetBurglarLevel', function(src) return Progress.Level(src) end)
exports('AddBurglarXP', function(src, amount) Progress.AddXP(src, amount, 'export') end)
