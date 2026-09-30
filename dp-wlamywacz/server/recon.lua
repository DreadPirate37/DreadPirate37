-- ==========================================================================
--  Rekonesans (REK). Fakty o domu liczy serwer z profilu i zapisuje w notatniku postaci
--  (REK-02). Notatnik jest związany z seedem domu – po rotacji wpisy są oznaczane jako stare.
-- ==========================================================================
Recon = {}
local U, Profile = WLM.U, WLM.Profile

local function book(src, st)
    local prof = Progress.Get(src)
    if not prof then return nil end
    local nb = prof.notebook[st.id]
    if not nb or nb.seed ~= st.seed then
        nb = { seed = st.seed, label = st.cfg.label, notes = {}, hours = {}, facts = {} }
        prof.notebook[st.id] = nb
    end
    return nb, prof
end

-- dopisuje (albo nadpisuje) wpis w notatniku; key pozwala aktualizować zamiast dublować
function Recon.Note(src, st, key, text)
    local nb, prof = book(src, st)
    if not nb then return end
    nb.notes[key] = text
    nb.updated = os.time()
    Store.Touch(prof.id)
    SV.Client(src, 'note', st.id, key, text)
    -- ekipa widzi te same notatki (EKI-01)
    for _, m in ipairs(Crew.Others(src)) do
        local nb2, prof2 = book(m, st)
        if nb2 then nb2.notes[key] = text Store.Touch(prof2.id) SV.Client(m, 'note', st.id, key, text) end
    end
end

-- ocena ryzyka i łupu w gwiazdkach 1–5 z tego, co gracz już wie (REK-11)
local function rating(st, nb)
    local f = nb.facts
    local sec = 1
    if f.sticker == 'real' then sec = sec + 2 end
    if f.cams then sec = sec + math.min(2, f.cams) end
    if f.dog then sec = sec + 1 end
    local loot = math.min(5, st.cfg.tier + (f.lootSeen or 0))
    local known = 0
    for _ in pairs(nb.hours) do known = known + 1 end
    return { security = math.min(5, sec), loot = loot, certainty = math.min(100, known * 12) }
end

-- --------------------------------------------------------------------------
--  Lornetka (REK-01, REK-04): kto jest w domu teraz + jeden fakt z planu dnia
-- --------------------------------------------------------------------------
SV.Register('recon:observe', function(src, houseId, clock)
    local st = Houses.state[houseId]
    if not st then return { ok = false, msg = L('house_inactive') } end
    if not Bridge.HasItem(src, Config.Items.binoculars) then return { ok = false, msg = L('need_item', Economy.ItemLabel(Config.Items.binoculars)) } end
    if not SV.Near(src, st.cfg.entries[1].coords, 90.0) then return { ok = false, msg = L('too_far') } end
    local minute = SV.GameMinute(clock and clock.h, clock and clock.m)
    local nb = book(src, st)
    local hourKey = tostring(math.floor(minute / 60))
    local fresh = not nb.hours[hourKey]
    nb.hours[hourKey] = true

    local present = Profile.Present(st.profile, minute)
    local names = {}
    for _, p in ipairs(present) do
        local r = st.profile.residents[p.idx]
        names[#names + 1] = r.name .. (p.status == 'asleep' and L('nb_asleep') or '')
    end
    Recon.Note(src, st, 'now', L('nb_now', U.Clock(minute), #names > 0 and table.concat(names, ', ') or L('nb_empty')))

    -- fakt z planu dnia – im więcej różnych godzin obserwacji, tym więcej wiesz
    if fresh then
        local known = 0
        for _ in pairs(nb.hours) do known = known + 1 end
        local idx = ((known - 1) % #st.profile.residents) + 1
        local r = st.profile.residents[idx]
        local s = r.sched
        local facts = {
            L('nb_leave', r.name, U.Clock(s.leave), U.Clock(s.back)),
            L('nb_sleep', r.name, U.Clock(s.sleep), U.Clock(s.wake)),
        }
        if r.homeDay then facts[1] = L('nb_homeday', r.name) end
        local which = (known % 2) + 1
        Recon.Note(src, st, 'r' .. idx .. '_' .. which, facts[which])
        if r.nightTrip and known >= 3 then
            Recon.Note(src, st, 'r' .. idx .. '_night', L('nb_night', r.name, U.Clock(r.nightTrip)))
        end
        if st.profile.dog and known >= 2 and not nb.facts.dog then
            nb.facts.dog = true
            Recon.Note(src, st, 'dog', L('nb_dog', st.profile.dog.label))
        end
        -- łup widoczny przez okno (namiastka REK-03: telewizor w salonie)
        if st.profile.slots.tv and not nb.facts.tv then
            nb.facts.tv = true
            nb.facts.lootSeen = (nb.facts.lootSeen or 0) + 1
            Recon.Note(src, st, 'tv', L('nb_tv'))
        end
        Progress.AddXP(src, Config.XP.perRecon, 'rekonesans')
    end
    return { ok = true, rating = rating(st, nb), present = #present }
end, 2500)

-- --------------------------------------------------------------------------
--  Obchód (REK-14): podejście do wejścia zapisuje, co przy nim widać
-- --------------------------------------------------------------------------
SV.Register('recon:entry', function(src, houseId, entryId)
    local st = Houses.state[houseId]
    if not st then return { ok = false } end
    local e = U.FindEntry(st.cfg, entryId)
    if not e or not SV.Near(src, e.coords, 6.0) then return { ok = false } end
    local es = st.entries[e.id]
    local et = Config.EntryTypes[e.type]
    local parts = { et.label }
    if es.lock then parts[#parts + 1] = L('nb_lock', es.lock) end
    if es.state == 'tilted' then parts[#parts + 1] = L('nb_tilted') elseif es.state == 'open' then parts[#parts + 1] = L('nb_open') end
    if st.profile.security.contacts[e.id] then parts[#parts + 1] = L('nb_contact') end
    if e.requires == 'gate' then parts[#parts + 1] = L('nb_behind_gate') end
    Recon.Note(src, st, 'e_' .. e.id, table.concat(parts, ', '))
    local cams = #st.profile.security.cameras
    local nb = book(src, st)
    if cams > 0 and not nb.facts.cams then
        nb.facts.cams = cams
        Recon.Note(src, st, 'cams', L('nb_cams', cams))
    end
    return { ok = true }
end, 1500)

-- naklejka firmy ochroniarskiej (REK-06) – bywa blefem
SV.Register('recon:sticker', function(src, houseId)
    local st = Houses.state[houseId]
    if not st or not SV.Near(src, st.cfg.entries[1].coords, 8.0) then return { ok = false } end
    local sec = st.profile.security
    local nb = book(src, st)
    local text
    if sec.sticker == 'none' then text = L('nb_sticker_none')
    else
        nb.facts.sticker = sec.sticker == 'real' and 'real' or 'maybe'
        text = L('nb_sticker', L('sub_' .. (sec.sticker == 'real' and sec.sub or 'monitor')))
    end
    Recon.Note(src, st, 'sticker', text)
    return { ok = true, msg = text }
end, 1500)

-- --------------------------------------------------------------------------
--  Dzwonek (REK-21): ktoś otworzy albo nie; otwierający widzi twarz
-- --------------------------------------------------------------------------
SV.Register('recon:doorbell', function(src, houseId, clock)
    local st = Houses.state[houseId]
    if not st then return { ok = false } end
    local front
    for _, e in ipairs(st.cfg.entries) do if e.front then front = e end end
    if not front or not SV.Near(src, front.coords, 3.0) then return { ok = false, msg = L('too_far') } end
    local minute = SV.GameMinute(clock and clock.h, clock and clock.m)
    TriggerEvent('dp-wlamywacz:internal:worldNoise', st, front.coords, Config.Noise.actions.doorbell, nil, minute)
    local awake
    for _, p in ipairs(Profile.Present(st.profile, minute)) do
        if p.status == 'awake' or (st.woken and st.woken[p.idx]) then awake = st.profile.residents[p.idx] break end
    end
    if not awake then
        Recon.Note(src, st, 'bell', L('nb_bell_none', U.Clock(minute)))
        return { ok = true, answered = false }
    end
    Recon.Note(src, st, 'bell', L('nb_bell_yes', U.Clock(minute), awake.name))
    if Player(src).state.wlmMask ~= true then
        Police.AddEvidence(st.id, { kind = 'witness', cid = SV.P(src).id, name = Bridge.GetName(src), desc = L('ev_doorbell') })
    end
    return { ok = true, answered = true, model = awake.model, name = awake.name }
end, 4000)

-- --------------------------------------------------------------------------
--  Notatnik do laptopa (REK-02)
-- --------------------------------------------------------------------------
function Recon.View(src)
    local prof = Progress.Get(src)
    if not prof then return {} end
    local out = {}
    for id, nb in pairs(prof.notebook) do
        local st = Houses.state[id]
        local notes = {}
        for k, v in pairs(nb.notes) do notes[#notes + 1] = { k = k, t = v } end
        table.sort(notes, function(a, b) return a.k < b.k end)
        out[#out + 1] = {
            id = id, label = nb.label, stale = not st or st.seed ~= nb.seed, active = st ~= nil,
            notes = notes, rating = st and st.seed == nb.seed and rating(st, nb) or nil, updated = nb.updated or 0,
        }
    end
    table.sort(out, function(a, b) return (a.updated or 0) > (b.updated or 0) end)
    return out
end
