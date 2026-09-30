-- ==========================================================================
--  Bridge (serwer): frameworki ESX / QBCore / QBox / standalone i ekwipunki
--  ox_inventory / qb-inventory / qs-inventory / ESX. Wszystko, co dotyka zewnętrznych
--  zasobów, jest tutaj – reszta skryptu woła tylko Bridge.*.
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

local inv = Config.Inventory
if inv == 'auto' then
    if GetResourceState('ox_inventory') ~= 'missing' then inv = 'ox'
    elseif GetResourceState('qs-inventory') ~= 'missing' then inv = 'qs'
    elseif fw == 'qb' then inv = 'qb'
    elseif fw == 'esx' then inv = 'esx'
    else inv = 'none' end
end
Bridge.inventory = inv

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
    if fw == 'esx' and p then return p.getName and p.getName() or GetPlayerName(src) end
    if (fw == 'qb' or fw == 'qbx') and p then
        local c = p.PlayerData.charinfo
        if c then return (c.firstname or '') .. ' ' .. (c.lastname or '') end
    end
    return GetPlayerName(src) or ('#' .. src)
end

-- nazwa pracy i czy na służbie
function Bridge.GetJob(src)
    local p = getPlayer(src)
    if not p then return nil, false end
    if fw == 'esx' then
        local j = p.job or {}
        return j.name, j.onDuty ~= false
    end
    local j = p.PlayerData.job or {}
    return j.name, j.onduty ~= false
end

local function inList(list, v)
    for _, x in ipairs(list) do if x == v then return true end end
    return false
end

function Bridge.IsPolice(src)
    local job, duty = Bridge.GetJob(src)
    return job ~= nil and inList(Config.Police.jobs, job) and duty
end

function Bridge.IsEms(src)
    local job, duty = Bridge.GetJob(src)
    return job ~= nil and inList(Config.Police.emsJobs, job) and duty
end

-- liczba policjantów na służbie – liczona najwyżej raz na 20 s (TEC: bez pętli per zapytanie)
local copCache, copAt = 0, -1
function Bridge.PoliceCount()
    local now = os.time()
    if now - copAt < 20 then return copCache end
    local n = 0
    for _, id in ipairs(GetPlayers()) do
        if Bridge.IsPolice(tonumber(id)) then n = n + 1 end
    end
    copCache, copAt = n, now
    return n
end

function Bridge.PoliceSources()
    local out = {}
    for _, id in ipairs(GetPlayers()) do
        local s = tonumber(id)
        if Bridge.IsPolice(s) then out[#out + 1] = s end
    end
    return out
end

-- --------------------------------------------------------------------------
--  Pieniądze
-- --------------------------------------------------------------------------
function Bridge.AddMoney(src, amount, reason, dirty)
    amount = math.floor(amount)
    if amount <= 0 then return true end
    local p = getPlayer(src)
    if dirty == nil then dirty = Config.Payout.dirty end
    if fw == 'esx' and p then
        p.addAccountMoney(dirty and 'black_money' or (Config.Payout.account == 'cash' and 'money' or Config.Payout.account), amount, reason)
        return true
    end
    if (fw == 'qb' or fw == 'qbx') and p then
        if dirty and Config.Payout.qbDirtyItem then
            return Bridge.AddItem(src, Config.Payout.qbDirtyItem, 1, { worth = amount })
        end
        return p.Functions.AddMoney(Config.Payout.account, amount, reason) ~= false
    end
    TriggerEvent('dp-wlamywacz:standalone:addMoney', src, dirty and 'dirty' or Config.Payout.account, amount, reason)
    return true
end

function Bridge.RemoveMoney(src, amount, reason)
    amount = math.floor(amount)
    if amount <= 0 then return true end
    local p = getPlayer(src)
    if fw == 'esx' and p then
        for _, acc in ipairs({ 'money', 'bank' }) do
            local a = p.getAccount(acc)
            if a and a.money >= amount then p.removeAccountMoney(acc, amount, reason) return true end
        end
        return false
    end
    if (fw == 'qb' or fw == 'qbx') and p then
        if p.Functions.RemoveMoney('cash', amount, reason) then return true end
        return p.Functions.RemoveMoney('bank', amount, reason) == true
    end
    return true -- standalone: brak ekonomii
end

-- --------------------------------------------------------------------------
--  Przedmioty
-- --------------------------------------------------------------------------
function Bridge.ItemCount(src, item)
    if inv == 'none' then return Config.RequireItems and 0 or 99 end
    if inv == 'ox' then return exports.ox_inventory:GetItemCount(src, item) or 0 end
    if inv == 'qs' then return exports['qs-inventory']:GetItemTotalAmount(src, item) or 0 end
    local p = getPlayer(src)
    if not p then return 0 end
    if inv == 'qb' then
        local it = p.Functions.GetItemByName(item)
        return it and (it.amount or it.count) or 0
    end
    if inv == 'esx' then
        local it = p.getInventoryItem(item)
        return it and it.count or 0
    end
    return 0
end

function Bridge.HasItem(src, item, count)
    if not Config.RequireItems then return true end
    return Bridge.ItemCount(src, item) >= (count or 1)
end

function Bridge.AddItem(src, item, count, meta)
    count = count or 1
    if inv == 'none' then return true end
    if inv == 'ox' then return exports.ox_inventory:AddItem(src, item, count, meta) ~= false end
    if inv == 'qs' then return exports['qs-inventory']:AddItem(src, item, count, nil, meta) ~= false end
    local p = getPlayer(src)
    if not p then return false end
    if inv == 'qb' then
        local ok = p.Functions.AddItem(item, count, false, meta)
        if ok and qb().Shared.Items[item] then TriggerClientEvent('inventory:client:ItemBox', src, qb().Shared.Items[item], 'add', count) end
        return ok ~= false
    end
    if inv == 'esx' then p.addInventoryItem(item, count) return true end
    return false
end

function Bridge.RemoveItem(src, item, count)
    count = count or 1
    if inv == 'none' then return true end
    if not Config.RequireItems and Bridge.ItemCount(src, item) < count then return true end
    if inv == 'ox' then return exports.ox_inventory:RemoveItem(src, item, count) ~= false end
    if inv == 'qs' then return exports['qs-inventory']:RemoveItem(src, item, count) ~= false end
    local p = getPlayer(src)
    if not p then return false end
    if inv == 'qb' then
        local ok = p.Functions.RemoveItem(item, count)
        if ok and qb().Shared.Items[item] then TriggerClientEvent('inventory:client:ItemBox', src, qb().Shared.Items[item], 'remove', count) end
        return ok ~= false
    end
    if inv == 'esx' then p.removeInventoryItem(item, count) return true end
    return false
end

-- przedmioty „używalne” z ekwipunku (ESX / QB). Dla ox_inventory ustaw w items.lua:
-- client = { export = 'dp-wlamywacz.useItem' } – szczegóły w README.
function Bridge.RegisterUsable(item, cb)
    if fw == 'esx' then
        esx().RegisterUsableItem(item, function(src) cb(src) end)
    elseif fw == 'qb' then
        qb().Functions.CreateUseableItem(item, function(src) cb(src) end)
    elseif fw == 'qbx' and GetResourceState('qbx_core') == 'started' then
        pcall(function() exports.qbx_core:CreateUseable(item, function(src) cb(src) end) end)
    end
end

function Bridge.Notify(src, msg, kind)
    TriggerClientEvent('dp-wlamywacz:client:notify', src, msg, kind)
end
