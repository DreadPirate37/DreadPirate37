-- ==========================================================================
--  Naloty policji: każda dziupla zbiera „heat” (auta, części, zgłoszenia).
--  Powyżej progu może przyjść obława: ostrzeżenie → blokada dziupli →
--  policja może przeszukać regały i zabezpieczyć „gorące” części.
-- ==========================================================================
local R = Config.Raid
local Heat = {}       -- [shopKey] = { v, t }
local Recent = {}     -- [shopKey] = { [identyfikator] = czas }
local Raids = {}      -- [shopKey] = { phase, t, searched = {} }
local Bribed = {}     -- [shopKey] = czas ostatniej łapówki

local function load()
    local raw = GetResourceKvpString('dz:heat')
    for k, v in pairs(raw and json.decode(raw) or {}) do Heat[k] = v end
end

local function save() SetResourceKvp('dz:heat', json.encode(Heat)) end

local function heatOf(key)
    local h = Heat[key]
    if not h then return 0 end
    local v = h.v - (os.time() - h.t) / 3600 * R.decayPerHour
    return math.max(0, v)
end

function DZ.AddHeat(key, n, src)
    if not R.enabled or not key then return end
    Heat[key] = { v = heatOf(key) + n, t = os.time() }
    if src then
        local p = DZ.Profile(src)
        Recent[key] = Recent[key] or {}
        if p then Recent[key][p.id] = os.time() end
    end
    save()
end

function DZ.RaidActive(key)
    local r = Raids[key]
    return r ~= nil and r.phase == 'raid'
end

local function isPolice(src)
    local job = Bridge.GetJob(src)
    for _, j in ipairs(Config.Police.jobs) do
        if j == job then return true end
    end
    return false
end

local function playersIn(shop)
    local out = {}
    for _, id in ipairs(GetPlayers()) do
        local ped = GetPlayerPed(id)
        if ped ~= 0 and #(GetEntityCoords(ped) - shop.center) < shop.radius then out[#out + 1] = tonumber(id) end
    end
    return out
end

local function startRaid(shop)
    local key = shop.key
    Raids[key] = { phase = 'warning', t = os.time() + R.warning, searched = {} }
    GlobalState['dpRaid_' .. key] = { phase = 'warning', t = os.time() + R.warning }
    local inside = playersIn(shop)
    for _, src in ipairs(inside) do
        Bridge.Notify(src, ('OBŁAWA! Policja będzie tu za %d s – zwijajcie się!'):format(R.warning), 'bad')
    end
    -- dispatch wysyła klient (skrypty dispatch są klienckie): ktoś z dziupli albo policjant
    local who = inside[1]
    if not who then
        for _, id in ipairs(GetPlayers()) do
            if isPolice(tonumber(id)) then who = tonumber(id) break end
        end
    end
    if who then TriggerClientEvent('dp-dziupla:client:dispatch', who, 'raid', shop.center, {}) end
    DZ.Log('police', nil, 'Obława na dziuplę', shop.label, 'police')
    SetTimeout(R.warning * 1000, function()
        if not Raids[key] then return end
        Raids[key].phase = 'raid'
        Raids[key].t = os.time() + R.lockdown
        GlobalState['dpRaid_' .. key] = { phase = 'raid', t = Raids[key].t }
        if DZ.CancelShopJobs then DZ.CancelShopJobs(key) end
        Heat[key] = { v = R.threshold * 0.3, t = os.time() }
        save()
        SetTimeout(R.lockdown * 1000, function()
            Raids[key] = nil
            GlobalState['dpRaid_' .. key] = nil
        end)
    end)
end

CreateThread(function()
    load()
    if not R.enabled then return end
    while true do
        Wait(300000)
        for _, shop in ipairs(Config.Shops) do
            if not Raids[shop.key] and heatOf(shop.key) >= R.threshold and Bridge.CountPolice() >= R.minPolice and math.random() < R.chance then
                startRaid(shop)
            end
        end
    end
end)

-- --------------------------------------------------------------------------
--  Przeszukanie przez policję
-- --------------------------------------------------------------------------
DZ.register('raidSearch', function(src, key)
    local shop = DZ.ShopByKey(key)
    local r = Raids[key]
    if not shop or not r or r.phase ~= 'raid' then return { ok = false, msg = 'Tu nie trwa obława.' } end
    if not isPolice(src) then return { ok = false, msg = 'Tylko policja może zabezpieczać dowody.' } end
    if not DZ.Near(src, shop.shelf, R.searchRadius) then return { ok = false, msg = L('too_far') } end
    if r.searched[src] then return { ok = false, msg = 'Już przeszukałeś tę dziuplę.' } end
    r.searched[src] = true
    local now, seized = os.time(), 0
    for id, at in pairs(Recent[key] or {}) do
        if now - at < R.hotTime then
            local p = DZ.ProfileById(id)
            if p then
                local n = 0
                for _, it in ipairs(DZ.WhList(p)) do
                    if n >= R.maxSeize then break end
                    if it.h and now - it.h < R.hotTime and not DZ.IsRes(p, it.u) then
                        if DZ.WhTake(p, it.u) then n = n + 1 end
                    end
                end
                if n > 0 then DZ.Save(p) end
                seized = seized + n
            end
        end
    end
    Recent[key] = {}
    if seized > 0 then Bridge.AddMoney(src, 'bank', seized * R.rewardPerPart, 'dp-dziupla-dowody') end
    DZ.Log('police', src, 'Przeszukanie dziupli', ('%s: zabezpieczono %d części'):format(shop.label, seized), 'police')
    return { ok = true, msg = ('Zabezpieczono %d części jako dowody.'):format(seized) }
end)

-- łapówka „dla dzielnicowego” – zbija heat
DZ.register('raidBribe', function(src)
    local shop = DZ.ShopAtRaw(src)
    if not shop then return { ok = false, msg = L('not_at_shop') } end
    local B = R.bribe
    if Bribed[shop.key] and os.time() - Bribed[shop.key] < B.cooldown then return { ok = false, msg = 'Dzielnicowy już dostał swoje – spróbuj później.' } end
    if not Bridge.RemoveMoney(src, Config.ShopAccount, B.price, 'dp-dziupla-lapowka') then return { ok = false, msg = L('no_money', B.price) } end
    Bribed[shop.key] = os.time()
    Heat[shop.key] = { v = math.max(0, heatOf(shop.key) - B.amount), t = os.time() }
    save()
    return { ok = true, msg = 'Koperta poszła. Na mieście trochę ciszej o tej dziupli.', data = DZ.Overview(src) }
end)

function DZ.RaidView(src, p, data)
    local shop = DZ.ShopAtRaw(src)
    if not R.enabled or not shop then return end
    local r = Raids[shop.key]
    data.raid = {
        heat = math.floor(heatOf(shop.key)), threshold = R.threshold, shop = shop.label,
        phase = r and r.phase or nil, left = r and math.max(0, r.t - os.time()) or nil,
        bribe = R.bribe.price, canBribe = not Bribed[shop.key] or os.time() - Bribed[shop.key] >= R.bribe.cooldown,
    }
end
