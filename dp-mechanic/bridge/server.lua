-- ==========================================================================
--  Bridge frameworków (serwer): ESX / QBCore / QBox / standalone
-- ==========================================================================
Bridge = {}

local fw = Config.Framework
if fw == 'auto' then
    if GetResourceState('qbx_core') ~= 'missing' then fw = 'qbx'
    elseif GetResourceState('es_extended') ~= 'missing' then fw = 'esx'
    elseif GetResourceState('qb-core') ~= 'missing' then fw = 'qb'
    else fw = 'standalone' end
end
Bridge.name = fw

local ESX, QB
local function esx()
    if not ESX then ESX = exports.es_extended:getSharedObject() end
    return ESX
end
local function qb()
    if not QB then QB = exports['qb-core']:GetCoreObject() end
    return QB
end

local function getPlayer(src)
    if fw == 'esx' then return esx().GetPlayerFromId(src) end
    if fw == 'qb' then return qb().Functions.GetPlayer(src) end
    if fw == 'qbx' then return exports.qbx_core:GetPlayer(src) end
    return nil
end
Bridge.GetPlayer = getPlayer

local function account(acc)
    if fw == 'esx' then return acc == 'cash' and 'money' or acc end
    return acc
end

function Bridge.GetIdentifier(src)
    local p = getPlayer(src)
    if fw == 'esx' and p then return p.identifier end
    if (fw == 'qb' or fw == 'qbx') and p then return p.PlayerData.citizenid end
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:sub(1, 8) == 'license:' then return id end
    end
    return GetPlayerIdentifier(src, 0)
end

function Bridge.GetName(src)
    local p = getPlayer(src)
    if fw == 'esx' and p then
        local n = p.getName and p.getName()
        if n and n ~= '' then return n end
    elseif (fw == 'qb' or fw == 'qbx') and p then
        local c = p.PlayerData.charinfo
        if c then return ('%s %s'):format(c.firstname or '', c.lastname or '') end
    end
    return GetPlayerName(src) or ('Gracz ' .. src)
end

function Bridge.GetJob(src)
    local p = getPlayer(src)
    if not p then return nil, 0 end
    if fw == 'esx' then return p.job and p.job.name, p.job and p.job.grade or 0 end
    local j = p.PlayerData.job
    if not j then return nil, 0 end
    local g = type(j.grade) == 'table' and (j.grade.level or 0) or (j.grade or 0)
    return j.name, g
end

function Bridge.SetJob(src, job, grade)
    local p = getPlayer(src)
    if not p then return end
    if fw == 'esx' then p.setJob(job, grade)
    elseif fw == 'qb' then p.Functions.SetJob(job, grade)
    elseif fw == 'qbx' then exports.qbx_core:SetJob(src, job, grade) end
end

function Bridge.GetMoney(src, acc)
    local p = getPlayer(src)
    if fw == 'esx' and p then
        local a = p.getAccount(account(acc))
        return a and a.money or 0
    end
    if (fw == 'qb' or fw == 'qbx') and p then
        return p.PlayerData.money and p.PlayerData.money[acc] or 0
    end
    return 999999999
end

function Bridge.AddMoney(src, acc, amount, reason)
    amount = math.floor(amount)
    if amount <= 0 then return true end
    local p = getPlayer(src)
    if fw == 'esx' and p then p.addAccountMoney(account(acc), amount, reason) return true end
    if (fw == 'qb' or fw == 'qbx') and p then return p.Functions.AddMoney(acc, amount, reason) ~= false end
    TriggerEvent('dp-mechanic:standalone:addMoney', src, acc, amount, reason)
    return true
end

function Bridge.RemoveMoney(src, acc, amount, reason)
    amount = math.floor(amount)
    if amount <= 0 then return true end
    local p = getPlayer(src)
    if fw == 'esx' and p then
        local a = p.getAccount(account(acc))
        if not a or a.money < amount then return false end
        p.removeAccountMoney(account(acc), amount, reason)
        return true
    end
    if (fw == 'qb' or fw == 'qbx') and p then
        return p.Functions.RemoveMoney(acc, amount, reason) == true
    end
    return true
end

function Bridge.Notify(src, msg, kind, time)
    TriggerClientEvent('dp-mechanic:notify', src, msg, kind, time)
end

-- przedmiot „tablet” (opcjonalnie)
function Bridge.RegisterUsable(item, cb)
    if not item then return end
    if fw == 'esx' then esx().RegisterUsableItem(item, cb)
    elseif fw == 'qb' then qb().Functions.CreateUseableItem(item, cb)
    elseif fw == 'qbx' then exports.qbx_core:CreateUseableItem(item, cb) end
    if GetResourceState('ox_inventory') == 'started' then
        exports('use_' .. item, function(event, _, inventory)
            if event == 'usingItem' then cb(inventory.id) end
        end)
    end
end

-- zapis wyglądu auta w garażu frameworka (mody GTA, kolory itd.)
function Bridge.SaveVehicleProps(plate, props)
    if type(props) ~= 'table' or GetResourceState('oxmysql') ~= 'started' then return end
    plate = Utils.Plate(plate)
    if fw == 'esx' then
        local row = MySQL.single.await('SELECT vehicle FROM owned_vehicles WHERE TRIM(UPPER(plate)) = ?', { plate })
        if not row then return end
        local cur = json.decode(row.vehicle or '{}') or {}
        for k, v in pairs(props) do cur[k] = v end
        MySQL.update('UPDATE owned_vehicles SET vehicle = ? WHERE TRIM(UPPER(plate)) = ?', { json.encode(cur), plate })
    elseif fw == 'qb' or fw == 'qbx' then
        local row = MySQL.single.await('SELECT mods FROM player_vehicles WHERE TRIM(UPPER(plate)) = ?', { plate })
        if not row then return end
        local cur = json.decode(row.mods or '{}') or {}
        for k, v in pairs(props) do cur[k] = v end
        MySQL.update('UPDATE player_vehicles SET mods = ? WHERE TRIM(UPPER(plate)) = ?', { json.encode(cur), plate })
    end
end

-- właściciel auta (do faktur / projektów) – opcjonalne
function Bridge.GetVehicleOwner(plate)
    plate = Utils.Plate(plate)
    if fw == 'esx' then
        local r = MySQL.single.await('SELECT owner FROM owned_vehicles WHERE TRIM(UPPER(plate)) = ?', { plate })
        return r and r.owner
    elseif fw == 'qb' or fw == 'qbx' then
        local r = MySQL.single.await('SELECT citizenid FROM player_vehicles WHERE TRIM(UPPER(plate)) = ?', { plate })
        return r and r.citizenid
    end
    return nil
end

function Bridge.GetSourceByIdentifier(identifier)
    for _, s in ipairs(GetPlayers()) do
        local src = tonumber(s)
        if Bridge.GetIdentifier(src) == identifier then return src end
    end
    return nil
end
