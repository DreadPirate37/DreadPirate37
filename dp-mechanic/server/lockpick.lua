-- ==========================================================================
--  Wytrych – serwer: wytrychy (przedmiot / magazyn warsztatu), XP ślusarza,
--  odblokowanie auta po sukcesie.
-- ==========================================================================
Lockpick = { sessions = {} }
local LP = Config.Lockpick

CreateThread(function()
    if not LP or not LP.enabled then return end
    while GetResourceState('oxmysql') ~= 'started' do Wait(200) end
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS dpm_skills (
            identifier VARCHAR(64) NOT NULL PRIMARY KEY,
            lockpick_xp INT NOT NULL DEFAULT 0
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
end)

-- --------------------------------------------------------------------------
--  XP / poziomy
-- --------------------------------------------------------------------------
local function levelOf(xp)
    local lv = 1
    for i, need in ipairs(LP.xp.levels) do
        if xp >= need then lv = i end
    end
    return lv, LP.xp.levels[lv] or 0, LP.xp.levels[lv + 1]
end

local function getXp(identifier)
    return MySQL.scalar.await('SELECT lockpick_xp FROM dpm_skills WHERE identifier = ?', { identifier }) or 0
end

local function addXp(identifier, amount)
    if amount <= 0 then return getXp(identifier) end
    MySQL.query.await('INSERT INTO dpm_skills (identifier, lockpick_xp) VALUES (?, ?) ON DUPLICATE KEY UPDATE lockpick_xp = lockpick_xp + VALUES(lockpick_xp)', { identifier, amount })
    return getXp(identifier)
end

-- --------------------------------------------------------------------------
--  Źródło wytrychów: magazyn warsztatu albo ekwipunek gracza
-- --------------------------------------------------------------------------
local function itemCount(src, item)
    if GetResourceState('ox_inventory') == 'started' then
        return exports.ox_inventory:Search(src, 'count', item) or 0
    end
    local p = Bridge.GetPlayer(src)
    if not p then return Bridge.name == 'standalone' and 99 or 0 end
    if Bridge.name == 'esx' then
        local it = p.getInventoryItem(item)
        return it and it.count or 0
    end
    local it = p.Functions.GetItemByName(item)
    return it and (it.amount or it.count) or 0
end

local function itemRemove(src, item)
    if GetResourceState('ox_inventory') == 'started' then
        return exports.ox_inventory:RemoveItem(src, item, 1)
    end
    local p = Bridge.GetPlayer(src)
    if not p then return Bridge.name == 'standalone' end
    if Bridge.name == 'esx' then p.removeInventoryItem(item, 1) return true end
    return p.Functions.RemoveItem(item, 1) ~= false
end

local function workshopFor(src)
    if not LP.workshopStock or not DPM or not DPM.GetMember then return nil end
    local m = DPM.GetMember(src)
    if not m or (Config.RequireDuty and not m.duty) then return nil end
    local ws = Config.Workshops[m.workshop]
    if not ws then return nil end
    local c = GetEntityCoords(GetPlayerPed(src))
    if #(c - ws.zone.center) > ws.zone.radius then return nil end
    return m.workshop
end

local function stockCount(ws)
    return MySQL.scalar.await('SELECT qty FROM dpm_stock WHERE workshop = ? AND item = ?', { ws, 'lockpick' }) or 0
end

local function picksLeft(s)
    if s.source == 'stock' then return stockCount(s.ws) end
    if s.source == 'item' then return itemCount(s.src, LP.item) end
    return 99
end

-- --------------------------------------------------------------------------
--  Callbacki
-- --------------------------------------------------------------------------
CreateThread(function()
    while not DPM or not DPM.RegisterCallback do Wait(100) end

    -- start: sprawdza wytrychy, zwraca dane do HUD
    DPM.RegisterCallback('lockpick:start', function(src, netId, opts)
        if not LP.enabled then return { ok = false, err = 'Wytrych jest wyłączony' } end
        opts = type(opts) == 'table' and opts or {}
        local ped = GetPlayerPed(src)
        local ent
        if netId then
            ent = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
            if not ent or ent == 0 or not DoesEntityExist(ent) then return { ok = false, err = 'Nie znaleziono pojazdu' } end
            if #(GetEntityCoords(ped) - GetEntityCoords(ent)) > 6.0 then return { ok = false, err = 'Jesteś za daleko od auta' } end
        end
        local ws = workshopFor(src)
        if LP.mechanicOnly and not ws then return { ok = false, err = 'Tylko mechanik na służbie w warsztacie może to zrobić' } end

        local s = { src = src, netId = netId, ent = ent, ws = ws, pins = 0, started = os.time() }
        if opts.consume == false then s.source = 'free'
        elseif ws then s.source = 'stock'
        elseif LP.item then s.source = 'item'
        else s.source = 'free' end
        local picks = picksLeft(s)
        if picks <= 0 then
            return { ok = false, err = s.source == 'stock' and 'Brak wytrychów w magazynie warsztatu' or 'Nie masz wytrycha' }
        end
        Lockpick.sessions[src] = s

        local identifier = Bridge.GetIdentifier(src)
        local xp = getXp(identifier)
        local lv, cur, nxt = levelOf(xp)
        return {
            ok = true, picks = s.source == 'free' and -1 or picks, xp = xp, level = lv, levelXp = cur, nextXp = nxt,
            money = Bridge.GetMoney(src, 'cash'), source = s.source,
        }
    end)

    -- złamany wytrych
    DPM.RegisterCallback('lockpick:break', function(src)
        local s = Lockpick.sessions[src]
        if not s then return { ok = false } end
        if s.source == 'stock' then
            MySQL.update.await('UPDATE dpm_stock SET qty = qty - 1 WHERE workshop = ? AND item = ? AND qty > 0', { s.ws, 'lockpick' })
        elseif s.source == 'item' then
            itemRemove(src, LP.item)
        end
        local left = s.source == 'free' and -1 or picksLeft(s)
        return { ok = true, picks = left }
    end)

    -- ustawiona zapadka (XP za postęp – max liczba zapadek zamka)
    DPM.RegisterCallback('lockpick:pin', function(src)
        local s = Lockpick.sessions[src]
        if not s or s.pins >= 8 then return { ok = false } end
        s.pins = s.pins + 1
        local xp = addXp(Bridge.GetIdentifier(src), LP.xp.pin)
        local lv, cur, nxt = levelOf(xp)
        return { ok = true, xp = xp, level = lv, levelXp = cur, nextXp = nxt }
    end)

    -- koniec: sukces = odblokowanie auta + XP
    DPM.RegisterCallback('lockpick:done', function(src, success)
        local s = Lockpick.sessions[src]
        Lockpick.sessions[src] = nil
        if not s then return { ok = false } end
        local identifier = Bridge.GetIdentifier(src)
        local xp
        if success == true and s.pins > 0 and os.time() - s.started >= 2 then
            xp = addXp(identifier, LP.xp.lock)
            if s.ent and DoesEntityExist(s.ent) and LP.unlockDoors then
                SetVehicleDoorsLocked(s.ent, 1)
                Entity(s.ent).state:set('dpm_unlocked', os.time(), true)
            end
            TriggerEvent('dp-mechanic:lockpicked', src, s.netId, s.ws)
        else
            xp = getXp(identifier)
        end
        local lv, cur, nxt = levelOf(xp)
        return { ok = true, xp = xp, level = lv, levelXp = cur, nextXp = nxt }
    end)
end)

-- alarm (hałas) – hak dla systemów dyspozytorskich policji
RegisterNetEvent('dp-mechanic:lockpick:alarm', function(netId)
    local src = source
    local s = Lockpick.sessions[src]
    if not s then return end
    local coords = GetEntityCoords(GetPlayerPed(src))
    TriggerEvent('dp-mechanic:lockpickAlarm', src, coords, netId, s.ws ~= nil)
end)

AddEventHandler('playerDropped', function()
    Lockpick.sessions[source] = nil
end)
