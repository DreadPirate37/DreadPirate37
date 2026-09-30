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
    if acc == 'black_money' then return 'cash' end
    return acc
end

-- strict = true: nil, gdy framework nie ma (jeszcze / już) postaci gracza
function Bridge.GetIdentifier(src, strict)
    local p = getPlayer(src)
    if fw == 'esx' and p then return p.identifier end
    if (fw == 'qb' or fw == 'qbx') and p then return p.PlayerData.citizenid end
    if strict and fw ~= 'standalone' then return nil end
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:sub(1, 8) == 'license:' then return id end
    end
    return GetPlayerIdentifier(src, 0)
end

function Bridge.GetJob(src)
    local p = getPlayer(src)
    if not p then return nil, false end
    if fw == 'esx' then return p.job and p.job.name, true end
    local j = p.PlayerData.job
    return j and j.name, j and j.onduty ~= false
end

function Bridge.CountPolice()
    local n = 0
    for _, id in ipairs(GetPlayers()) do
        local job, duty = Bridge.GetJob(tonumber(id))
        if job and duty then
            for _, pj in ipairs(Config.Police.jobs) do
                if pj == job then n = n + 1 break end
            end
        end
    end
    return n
end

function Bridge.AddMoney(src, acc, amount, reason)
    amount = math.floor(amount)
    if amount <= 0 then return true end
    local p = getPlayer(src)
    if fw == 'esx' and p then p.addAccountMoney(account(acc), amount, reason) return true end
    if (fw == 'qb' or fw == 'qbx') and p then return p.Functions.AddMoney(account(acc), amount, reason) ~= false end
    TriggerEvent('dp-dziupla:standalone:addMoney', src, acc, amount, reason)
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
        return p.Functions.RemoveMoney(account(acc), amount, reason) == true
    end
    -- standalone: brak ekonomii – zakupy zawsze „opłacone”
    return true
end

function Bridge.Notify(src, msg, kind)
    TriggerClientEvent('dp-dziupla:client:notify', src, msg, kind)
end
