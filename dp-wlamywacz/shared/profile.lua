-- ==========================================================================
--  Generator profilu domu (DOM-05). Deterministyczny: ten sam dom + seed = ten sam profil
--  po stronie klienta i serwera. Dzięki temu rekonesans ma sens, a serwer nie musi wysyłać
--  całego profilu – wystarczy seed.
-- ==========================================================================
local U = WLM.U
local P = {}
WLM.Profile = P

local ARCH_KEYS = U.SortedKeys(Config.Archetypes)
local KEY_CHANCE = { emeryt = 0.55, para = 0.3, singiel = 0.25, nocny = 0.2 }

local function pickName(rng, sex)
    local N = Config.ResidentModels.names
    local first = N[sex][rng(#N[sex])]
    local last = N.last[rng(#N.last)]
    if sex == 'female' then
        -- żeńskie formy nazwisk na -ski / -cki
        last = last:gsub('ski$', 'ska'):gsub('cki$', 'cka')
    end
    return first .. ' ' .. last
end

function P.Build(house, seed)
    local rng = U.Rng(seed)
    local tier = Config.Tiers[house.tier] or Config.Tiers[1]
    local tpl = Config.Interiors[house.interior]

    -- archetyp domowników
    local weights = {}
    for _, k in ipairs(ARCH_KEYS) do
        weights[#weights + 1] = { k, Config.Archetypes[k].weight[house.tier] or 1 }
    end
    local archKey = house.archetype or U.PickWeighted(rng, weights)
    local A = Config.Archetypes[archKey]

    -- domownicy i ich plan dnia (NPC-01)
    local residents = {}
    local firstSex = rng() < 0.5 and 'male' or 'female'
    for i = 1, A.residents do
        local sex = i == 1 and firstSex or (firstSex == 'male' and 'female' or 'male')
        local models = Config.ResidentModels[sex]
        local r = {
            idx = i,
            sex = sex,
            model = models[rng(#models)],
            name = pickName(rng, sex),
            sched = {
                wake = U.RangeI(rng, A.wake) % 1440,
                leave = U.RangeI(rng, A.leave) % 1440,
                back = U.RangeI(rng, A.back) % 1440,
                sleep = U.RangeI(rng, A.sleep) % 1440,
            },
            sleepDeep = U.RangeF(rng, A.sleepDeep),
            homeDay = rng() < A.homeDay,
            nightTrip = A.nightTrip and ((A.nightTrip + rng(-25, 25)) % 1440) or nil,
        }
        -- druga osoba w parze wychodzi i wraca trochę inaczej
        if i > 1 then
            r.sched.leave = (r.sched.leave + rng(-30, 45)) % 1440
            r.sched.back = (r.sched.back + rng(-45, 60)) % 1440
        end
        residents[i] = r
    end

    -- pies (NPC-13)
    local dog
    if tpl and rng() < tier.dog then
        for _, p in ipairs(tpl.points) do
            if p.type == 'dog' then
                dog = U.Copy(Config.Dogs[rng(#Config.Dogs)])
                dog.point = p.id
                break
            end
        end
    end

    -- zabezpieczenia (ZAB-32)
    local alarm = house.alarm
    if alarm == nil then alarm = rng() < tier.alarm end
    local sub = 'none'
    if alarm then
        local subList, subKeys = {}, U.SortedKeys(Config.Security.subscription[house.tier] or { none = 1 })
        for _, k in ipairs(subKeys) do subList[#subList + 1] = { k, Config.Security.subscription[house.tier][k] } end
        sub = U.PickWeighted(rng, subList) or 'none'
    end
    local camCount = 0
    if tpl then
        local c = tier.cameras
        camCount = alarm and rng(c[1], c[2]) or ((house.tier >= 3 and rng() < 0.3) and 1 or 0)
    end
    local cameras = {}
    if camCount > 0 and tpl then
        local camPoints = {}
        for _, p in ipairs(tpl.points) do if p.type == 'camera' then camPoints[#camPoints + 1] = p.id end end
        for i = #camPoints, 2, -1 do local j = rng(i); camPoints[i], camPoints[j] = camPoints[j], camPoints[i] end
        for i = 1, math.min(camCount, #camPoints) do cameras[#cameras + 1] = camPoints[i] end
    end
    local sticker = 'none'
    if alarm and sub ~= 'none' then sticker = 'real'
    elseif rng() < Config.Security.stickerBluff then sticker = 'bluff' end

    local security = {
        alarm = alarm,
        sub = sub,
        cameras = cameras,
        dvr = #cameras > 0,
        ups = alarm and (Config.Security.ups[house.tier] or 0) or 0,
        code = ('%04d'):format(rng(0, 9999)),
        sticker = sticker,
        delay = Config.Security.entryDelay[house.tier] or 30,
        contacts = {},
    }

    -- wejścia: klasa zamka, stan okien (WEJ-03), kontaktrony (ZAB-12)
    local entries = {}
    for _, e in ipairs(house.entries) do
        local st = { lock = e.lock, state = 'closed' }
        if e.type == 'window' then
            local r = rng()
            if r < Config.WindowState.open then st.state = 'open'
            elseif r < Config.WindowState.open + Config.WindowState.tilted then st.state = 'tilted' end
        end
        if not st.lock and e.type ~= 'window' then
            st.lock = house.tier >= 4 and 'C' or house.tier >= 3 and 'B' or 'A'
        end
        if alarm and e.type ~= 'gate' then
            local chance = e.type == 'window' and Config.Security.contactChance.window or Config.Security.contactChance.door
            security.contacts[e.id] = rng() < chance
        end
        entries[e.id] = st
    end

    -- ukryty klucz (WEJ-08)
    local hiddenKey
    if house.keySpots and #house.keySpots > 0 and rng() < (KEY_CHANCE[archKey] or 0.25) then
        hiddenKey = rng(#house.keySpots)
    end

    -- łupy widoczne (LUP-05)
    local slots = {}
    if tpl then
        for _, p in ipairs(tpl.points) do
            if p.type == 'loot' then
                local def = Config.LootSlots[p.slot]
                if def and rng() < def.chance * math.min(1.3, tier.lootMult) then
                    slots[p.id] = def.items[rng(#def.items)]
                end
            end
        end
    end

    -- sejf z tarczą: trzy liczby (ZAM-10)
    local safe = { rng(0, 99), rng(0, 99), rng(0, 99) }
    while math.abs(safe[2] - safe[1]) < 8 do safe[2] = rng(0, 99) end
    while math.abs(safe[3] - safe[2]) < 8 do safe[3] = rng(0, 99) end

    return {
        seed = seed,
        arch = archKey,
        archLabel = A.label,
        residents = residents,
        dog = dog,
        security = security,
        entries = entries,
        hiddenKey = hiddenKey,
        slots = slots,
        safe = safe,
        safeFurniture = rng() < 0.08 and '0000' or ('%04d'):format(rng(0, 9999)),
        cash = U.RangeI(rng, tier.cash),
        lootMult = Config.LootProfile[archKey] or {},
        tierMult = tier.lootMult,
    }
end

-- 'away' | 'awake' | 'asleep' dla domownika w danej minucie doby (NPC-01)
function P.Status(r, minute)
    local s = r.sched
    if U.InRange(minute, s.sleep, s.wake) then return 'asleep' end
    if not r.homeDay and U.InRange(minute, s.leave, s.back) then return 'away' end
    return 'awake'
end

-- głębokość snu 0–1 w cyklach 90-minutowych (NPC-02). Na granicy cyklu sen jest płytki.
function P.SleepDepth(r, minute)
    local since = (minute - r.sched.sleep) % 1440
    local cyc = (since % 90) / 90
    return math.sin(cyc * math.pi) * r.sleepDeep
end

-- kto jest teraz w domu
function P.Present(profile, minute)
    local out = {}
    for _, r in ipairs(profile.residents) do
        local st = P.Status(r, minute)
        if st ~= 'away' then out[#out + 1] = { idx = r.idx, status = st } end
    end
    return out
end

-- tryb alarmu: 'off' | 'away' (nikogo nie ma: opóźnienie wejścia) | 'night' (śpią: kontaktrony od razu)
function P.AlarmMode(profile, minute)
    if not profile.security.alarm then return 'off' end
    local present = P.Present(profile, minute)
    if #present == 0 then return 'away' end
    for _, p in ipairs(present) do
        if p.status == 'awake' then return 'off' end
    end
    return 'night'
end
