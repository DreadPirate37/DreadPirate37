-- ==========================================================================
--  Zleceniodawca Wiktor (ZLE-01), samouczek (PRO-16), zlecenia na przedmiot (ZLE-03),
--  poczta w laptopie (ZLE-19)
-- ==========================================================================
Contracts = {}
local U = WLM.U

-- kroki samouczka: po spełnieniu warunku przychodzi mail i nagroda
local TUTORIAL = {
    { hook = 'meet' },                                            -- 0 -> 1: rozmowa z Wiktorem
    { hook = 'shed',  reward = { xp = 40, rep = 20 } },           -- 1 -> 2: szopa (DOM-11)
    { hook = 'recon', reward = { xp = 30, rep = 20 } },           -- 2 -> 3: lornetka (REK-01)
    { hook = 'burglary', reward = { xp = 80, rep = 50, money = 400 } }, -- 3 -> 4: pierwszy dom
    { hook = 'sale',  reward = { xp = 50, rep = 60 } },           -- 4 -> 5: paser
}

function Contracts.Mail(src, subject, body)
    local prof = Progress.Get(src)
    if not prof then return end
    table.insert(prof.mail, 1, { from = Config.Contact.name, subject = subject, body = body, t = os.time(), read = false })
    while #prof.mail > 30 do table.remove(prof.mail) end
    Store.Touch(prof.id)
    SV.Client(src, 'mail', subject)
end

local function advanceTutorial(src, prof)
    local step = prof.tutorial or 0
    local def = TUTORIAL[step + 1]
    if not def then return end
    prof.tutorial = step + 1
    Store.Touch(prof.id)
    if def.reward then
        if def.reward.xp then Progress.AddXP(src, def.reward.xp, 'samouczek') end
        if def.reward.rep then Progress.AddRep(src, 'wiktor', def.reward.rep) end
        if def.reward.money then Bridge.AddMoney(src, def.reward.money, 'samouczek') end
    end
    Contracts.Mail(src, L('tut_subject_' .. prof.tutorial), L('tut_body_' .. prof.tutorial))
end

-- haki wywoływane przez resztę serwera: entry | take | burglary | shed | recon | sale
function Contracts.Hook(src, kind, data)
    local prof = Progress.Get(src)
    if not prof then return end
    local step = prof.tutorial or 0
    local def = TUTORIAL[step + 1]
    if def and def.hook == kind then
        if kind ~= 'burglary' or (data.grade and data.grade ~= 'F') then advanceTutorial(src, prof) end
    end
    -- zlecenie na przedmiot: wystarczy go ukraść, oddaje się u Wiktora
    local c = prof.contract
    if c and kind == 'take' and data.house == c.house and data.key == c.key and not c.stolen then
        c.stolen = true
        Store.Touch(prof.id)
        SV.Notify(src, L('contract_stolen'), 'good')
    end
end

AddEventHandler('dp-wlamywacz:xp', function(src, amount, reason)
    if reason == 'rekonesans' then Contracts.Hook(src, 'recon', {}) end
end)

-- --------------------------------------------------------------------------
--  Zlecenie na przedmiot (ZLE-03): widoczny łup z aktywnego domu
-- --------------------------------------------------------------------------
local function newContract(src)
    local options = {}
    local lvl = Progress.Level(src)
    for id, st in pairs(Houses.state) do
        if (Config.Tiers[st.cfg.tier].minLevel or 1) <= lvl then
            for pid, key in pairs(st.profile.slots) do
                if not Config.Loot[key].large then options[#options + 1] = { house = id, key = key, point = pid } end
            end
        end
    end
    if #options == 0 then return nil end
    local o = options[math.random(#options)]
    local def = Config.Loot[o.key]
    return { house = o.house, key = o.key, reward = math.floor(def.value[2] * 1.5), label = def.label, houseLabel = WLM.HouseById[o.house].label, at = os.time() }
end

-- rozmowa z Wiktorem: samouczek, zlecenia, oddanie przedmiotu
SV.Register('contact:talk', function(src, action)
    local c = Config.Contact.coords
    if not SV.Near(src, c, 4.0) then return { ok = false, msg = L('too_far') } end
    local prof = Progress.Get(src)
    if (prof.tutorial or 0) == 0 then
        advanceTutorial(src, prof)
        -- zestaw startowy: drut i shim, żeby samouczek był do przejścia
        Bridge.AddItem(src, Config.Items.lockpicks[1].item, 2)
        Bridge.AddItem(src, Config.Items.shim, 1)
        return { ok = true, text = L('wiktor_intro') }
    end
    if prof.tutorial < #TUTORIAL then
        return { ok = true, text = L('wiktor_tut_' .. prof.tutorial) }
    end
    local ct = prof.contract
    if action == 'turnin' and ct and ct.stolen then
        for _, it in ipairs(Bag.Items(src)) do
            if it.key == ct.key and it.house == ct.house then
                Bag.RemoveUids(src, { it.uid })
                local members = Crew.Members(src)
                local share = math.floor(ct.reward / #members)
                for _, m in ipairs(members) do Bridge.AddMoney(m, share, 'zlecenie') end
                Progress.AddRep(src, 'wiktor', 80)
                Progress.AddXP(src, 60, 'zlecenie')
                prof.contract = nil
                Store.Touch(prof.id)
                Bag.Sync(src)
                return { ok = true, text = L('wiktor_paid', ct.reward) }
            end
        end
        return { ok = true, text = L('wiktor_no_item') }
    end
    if action == 'new' and (not ct or os.time() - ct.at > 3600) then
        ct = newContract(src)
        prof.contract = ct
        Store.Touch(prof.id)
        if not ct then return { ok = true, text = L('wiktor_nothing') } end
        Contracts.Mail(src, L('contract_subject', ct.label), L('contract_body', ct.label, ct.houseLabel, ct.reward))
        return { ok = true, text = L('wiktor_contract', ct.label, ct.houseLabel, ct.reward) }
    end
    if ct then return { ok = true, text = L('wiktor_waiting', ct.label, ct.houseLabel), contract = true } end
    return { ok = true, text = L('wiktor_idle'), canNew = true }
end, 1000)

function Contracts.View(src)
    local prof = Progress.Get(src)
    return { mail = prof.mail, contract = prof.contract, tutorial = prof.tutorial or 0, tutorialMax = #TUTORIAL }
end

SV.Register('mail:read', function(src, index)
    local prof = Progress.Get(src)
    local m = prof.mail[tonumber(index) or 0]
    if m then m.read = true Store.Touch(prof.id) end
    return { ok = true }
end, 200)

-- --------------------------------------------------------------------------
--  Laptop (UIX-02): jeden callback z danymi wszystkich aplikacji
-- --------------------------------------------------------------------------
SV.Register('laptop:data', function(src)
    if not Bridge.HasItem(src, Config.Items.laptop) then return { ok = false, msg = L('need_item', Economy.ItemLabel(Config.Items.laptop)) } end
    return {
        ok = true,
        profile = Progress.View(src),
        notebook = Recon.View(src),
        shop = Economy.ShopView(src),
        mail = Contracts.View(src),
        bag = Bag.View(src),
        levels = Config.Levels,
    }
end, 1000)
