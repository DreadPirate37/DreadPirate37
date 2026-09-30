-- ==========================================================================
--  Zapis danych w KVP zasobu (TEC-06) – bez bazy danych.
--  Zmiany są oznaczane jako „brudne” i zapisywane paczką co minutę oraz przy wyjściu gracza.
-- ==========================================================================
Store = {}
local profiles, dirtyProfiles = {}, {}
local docs, dirtyDocs = {}, {}

local function defaults()
    return {
        xp = 0,
        rep = {},                  -- reputacja u kontaktów (PRO-05, PAS-09)
        stats = { houses = 0, loot = 0, arrests = 0, best = nil },
        tutorial = 0,              -- postęp samouczka (PRO-16)
        notebook = {},             -- [houseId] = wpisy z rekonesansu (REK-02)
        bag = {},                  -- łup w torbie: { uid, key, value, kg, house, t }
        heat = 0, heatAt = 0,      -- heat z leniwym zanikiem (POL-08)
        lastDuty = 0,              -- ostatnio widziany na służbie policji/EMS (POL-18)
        lastBurglary = 0,
        sales = { day = '', value = 0 },
        mail = {},                 -- poczta w laptopie (ZLE-19)
        contract = nil,            -- aktywne zlecenie (ZLE-03)
        orders = {},               -- zamówienia ze sklepu czekające w skrytce (NAR-37)
    }
end

function Store.Profile(cid)
    if not cid then return nil end
    local p = profiles[cid]
    if p then return p end
    local raw = GetResourceKvpString('wlm:p:' .. cid)
    local data = raw and json.decode(raw) or {}
    p = defaults()
    for k, v in pairs(data) do p[k] = v end
    p.id = cid
    profiles[cid] = p
    return p
end

function Store.Touch(cid) if cid then dirtyProfiles[cid] = true end end

function Store.Doc(key, default)
    if docs[key] == nil then
        local raw = GetResourceKvpString('wlm:d:' .. key)
        docs[key] = raw and json.decode(raw) or default or {}
    end
    return docs[key]
end

function Store.TouchDoc(key) dirtyDocs[key] = true end

local function flushProfile(cid)
    local p = profiles[cid]
    if not p then return end
    local copy = {}
    for k, v in pairs(p) do if k ~= 'id' then copy[k] = v end end
    SetResourceKvp('wlm:p:' .. cid, json.encode(copy))
end

function Store.Flush()
    for cid in pairs(dirtyProfiles) do flushProfile(cid) end
    for key in pairs(dirtyDocs) do SetResourceKvp('wlm:d:' .. key, json.encode(docs[key])) end
    dirtyProfiles, dirtyDocs = {}, {}
end

function Store.Unload(cid)
    if dirtyProfiles[cid] then flushProfile(cid) dirtyProfiles[cid] = nil end
    profiles[cid] = nil
end

CreateThread(function()
    while true do
        Wait(60000)
        Store.Flush()
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then Store.Flush() end
end)

AddEventHandler('dp-wlamywacz:internal:dropped', function(src)
    local p = SV.players[src]
    if p and p.id then Store.Unload(p.id) end
end)

-- dzień gry do limitów dziennych
function Store.Today() return os.date('%Y-%m-%d') end
