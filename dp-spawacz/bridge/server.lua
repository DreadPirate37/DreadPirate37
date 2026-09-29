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

function Bridge.GetJob(src)
    local p = getPlayer(src)
    if not p then return nil end
    if fw == 'esx' then return p.job and p.job.name end
    return p.PlayerData.job and p.PlayerData.job.name
end

function Bridge.AddMoney(src, acc, amount, reason)
    amount = math.floor(amount)
    if amount <= 0 then return true end
    local p = getPlayer(src)
    if fw == 'esx' and p then p.addAccountMoney(account(acc), amount, reason) return true end
    if (fw == 'qb' or fw == 'qbx') and p then return p.Functions.AddMoney(acc, amount, reason) ~= false end
    TriggerEvent('dp-spawacz:standalone:addMoney', src, acc, amount, reason)
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
    -- standalone: brak ekonomii – kaucja zawsze „opłacona”
    return true
end

function Bridge.Notify(src, msg, kind)
    TriggerClientEvent('dp-spawacz:client:notify', src, msg, kind)
end
