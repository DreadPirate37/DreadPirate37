-- ==========================================================================
--  Bridge (serwer): frameworki ESX / QBCore / QBox / standalone + ekwipunki
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
    elseif fw == 'esx' then inv = 'esx'
    elseif fw == 'qb' or fw == 'qbx' then inv = 'qb'
    else inv = 'standalone' end
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
    if fw == 'esx' and p then return p.getName() end
    if (fw == 'qb' or fw == 'qbx') and p then
        local ci = p.PlayerData.charinfo
        if ci then return ('%s %s'):format(ci.firstname or '', ci.lastname or '') end
    end
    return GetPlayerName(src) or ('#' .. src)
end

--- { name, grade, duty } albo nil
function Bridge.GetJob(src)
    local p = getPlayer(src)
    if not p then return nil end
    if fw == 'esx' then
        return p.job and { name = p.job.name, grade = tonumber(p.job.grade) or 0, duty = true }
    end
    local j = p.PlayerData.job
    if not j then return nil end
    local grade = type(j.grade) == 'table' and (j.grade.level or 0) or j.grade
    return { name = j.name, grade = tonumber(grade) or 0, duty = j.onduty ~= false }
end

function Bridge.GetGang(src)
    if fw ~= 'qb' and fw ~= 'qbx' then return nil end
    local p = getPlayer(src)
    local g = p and p.PlayerData.gang
    if not g then return nil end
    local grade = type(g.grade) == 'table' and (g.grade.level or 0) or g.grade
    return { name = g.name, grade = tonumber(grade) or 0 }
end

function Bridge.IsAdmin(src)
    if IsPlayerAceAllowed(src, Config.AdminAce) then return true end
    if fw == 'esx' then
        local p = getPlayer(src)
        local g = p and p.getGroup()
        return g == 'admin' or g == 'superadmin'
    end
    if fw == 'qb' then
        local core = qb()
        return core.Functions.HasPermission(src, 'admin') or core.Functions.HasPermission(src, 'god')
    end
    if fw == 'qbx' then return IsPlayerAceAllowed(src, 'group.admin') end
    return false
end

-- --------------------------------------------------------------------------
--  Ekwipunek
-- --------------------------------------------------------------------------
function Bridge.ItemCount(src, item)
    if inv == 'ox' then return exports.ox_inventory:Search(src, 'count', item) or 0 end
    local p = getPlayer(src)
    if inv == 'esx' and p then
        local it = p.getInventoryItem(item)
        return it and it.count or 0
    end
    if inv == 'qb' and p then
        local it = p.Functions.GetItemByName(item)
        return it and (it.amount or it.count) or 0
    end
    return Config.Debug and 1 or 0   -- standalone: w trybie debug „masz wszystko”
end

--- Pierwszy posiadany przedmiot z listy (lub pojedynczej nazwy).
function Bridge.FirstItem(src, items)
    if items == nil then return nil end
    if type(items) == 'string' then items = { items } end
    for _, it in ipairs(items) do
        if Bridge.ItemCount(src, it) > 0 then return it end
    end
    return nil
end

function Bridge.RemoveItem(src, item, count)
    count = count or 1
    if inv == 'ox' then return exports.ox_inventory:RemoveItem(src, item, count) end
    local p = getPlayer(src)
    if inv == 'esx' and p then p.removeInventoryItem(item, count) return true end
    if inv == 'qb' and p then return p.Functions.RemoveItem(item, count) end
    return true
end

--- Najwyższy poziom posiadanej karty dostępu.
function Bridge.KeycardLevel(src)
    local best = 0
    for item, level in pairs(Config.Keycards) do
        if level > best and Bridge.ItemCount(src, item) > 0 then best = level end
    end
    return best
end

function Bridge.Notify(src, msg, kind)
    TriggerClientEvent('dp-doorlock:client:notify', src, msg, kind)
end
