-- ==========================================================================
--  dp-wlamywacz – rdzeń klienta: callbacki, stan, profile domów z seedów, pomocnicze
--  Stany (TEC-01): IDLE (0 pętli), NEAR (dom < 70 m, pętla 500 ms), INSIDE (koordynator 250 ms
--  + pętla klatkowa tylko do klawiszy narzędzi), MINIGAME (Lua czeka, logika w NUI)
-- ==========================================================================
W = {
    houses = {},        -- [id] = seed aktywnych celów
    sheds = {},         -- [id] = { open, cooldown }
    near = {},          -- [id] = true – domy w pobliżu (strefy założone)
    houseState = {},    -- [id] = stan publiczny (wejścia, prąd, syrena)
    session = nil,      -- sesja włamania, gdy jesteś w środku
    busy = false,       -- trwa minigra / pasek postępu / laptop
    bag = { items = {}, kg = 0, cap = Config.BagFree },
    carry = nil,
    gloves = false, mask = false, flashlight = false,
    level = 1,
    ready = false,
}
local profiles = {}

-- --------------------------------------------------------------------------
--  Callbacki
-- --------------------------------------------------------------------------
local cbId, cbPending = 0, {}

function W.Callback(name, ...)
    cbId = cbId + 1
    local id = cbId
    local p = promise.new()
    cbPending[id] = p
    TriggerServerEvent('dp-wlamywacz:server:cb', name, id, ...)
    SetTimeout(15000, function()
        if cbPending[id] then cbPending[id] = nil p:resolve(nil) end
    end)
    return Citizen.Await(p)
end

RegisterNetEvent('dp-wlamywacz:client:cb', function(id, res)
    local p = cbPending[id]
    if p then cbPending[id] = nil p:resolve(res) end
end)

-- skrót: wywołaj i pokaż komunikat, jeśli jest
function W.Call(name, ...)
    local r = W.Callback(name, ...)
    if not r then W.Notify(L('error'), 'bad') return nil end
    if r.msg then W.Notify(r.msg, r.ok and 'good' or 'bad') end
    return r
end

-- --------------------------------------------------------------------------
--  Pomocnicze
-- --------------------------------------------------------------------------
function W.Notify(msg, kind, time) Hooks.Notify(msg, kind, time) end
RegisterNetEvent('dp-wlamywacz:client:notify', function(msg, kind) W.Notify(msg, kind) end)

function W.Help(text)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, false, -1)
end

function W.LoadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) do
        if GetGameTimer() > timeout then return nil end
        Wait(10)
    end
    return hash
end

function W.LoadDict(dict)
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 5000
    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() > timeout then return false end
        Wait(10)
    end
    return true
end

function W.GroundZ(v)
    local found, z = GetGroundZFor_3dCoord(v.x, v.y, v.z + 3.0, false)
    if found and math.abs(z - v.z) < 6.0 then return z end
    return v.z
end

function W.Clock() return { h = GetClockHours(), m = GetClockMinutes() } end
function W.Minute() return WLM.U.Minute(GetClockHours(), GetClockMinutes()) end
function W.IsNight() local h = GetClockHours() return h >= 21 or h < 6 end

-- profil domu z seeda – ten sam, który liczy serwer (DOM-05)
function W.Profile(houseId)
    local seed = W.houses[houseId]
    if not seed then return nil end
    local p = profiles[houseId]
    if p and p.seed == seed then return p end
    p = WLM.Profile.Build(WLM.HouseById[houseId], seed)
    profiles[houseId] = p
    return p
end

function W.Dist(a, b) return #(vector3(a.x, a.y, a.z) - vector3(b.x, b.y, b.z)) end

function W.FadeTo(cb)
    DoScreenFadeOut(300)
    local t = GetGameTimer() + 1000
    while not IsScreenFadedOut() and GetGameTimer() < t do Wait(10) end
    cb()
    Wait(200)
    DoScreenFadeIn(400)
end

-- opis wyglądu dla świadków (NPC-21): płeć, maska, rękawiczki, plecak
function W.DescribePed(ped)
    local parts = {}
    parts[#parts + 1] = IsPedMale(ped) and L('desc_male') or L('desc_female')
    if GetPedDrawableVariation(ped, 1) ~= 0 then parts[#parts + 1] = L('desc_mask') else parts[#parts + 1] = L('desc_face') end
    if GetPedDrawableVariation(ped, 5) ~= 0 then parts[#parts + 1] = L('desc_bag') end
    parts[#parts + 1] = L('desc_top', GetPedDrawableVariation(ped, 11), GetPedTextureVariation(ped, 11))
    return table.concat(parts, ', ')
end

-- --------------------------------------------------------------------------
--  Start i dane z serwera
-- --------------------------------------------------------------------------
RegisterNetEvent('dp-wlamywacz:client:houses', function(list, sheds)
    W.houses = list or {}
    W.sheds = sheds or W.sheds
    TriggerEvent('dp-wlamywacz:client:housesChanged')
end)

RegisterNetEvent('dp-wlamywacz:client:sheds', function(sheds)
    W.sheds = sheds or {}
    TriggerEvent('dp-wlamywacz:client:housesChanged')
end)

RegisterNetEvent('dp-wlamywacz:client:houseState', function(id, st)
    W.houseState[id] = st
    TriggerEvent('dp-wlamywacz:client:houseStateChanged', id, st)
end)

RegisterNetEvent('dp-wlamywacz:client:bag', function(bag)
    W.bag = bag or { items = {}, kg = 0, cap = Config.BagFree }
    W.Hud({ bag = { kg = W.bag.kg or 0, cap = W.bag.cap or Config.BagFree } })
end)

RegisterNetEvent('dp-wlamywacz:client:levelUp', function(lvl) W.level = lvl end)

CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(500) end
    Wait(2500)
    local r = W.Callback('init')
    if r and r.ok then
        W.houses = r.houses or {}
        W.sheds = r.sheds or {}
        W.level = r.level or 1
        W.bag.kg, W.bag.cap = r.bagKg or 0, r.bagCap or Config.BagFree
        W.ready = true
        TriggerEvent('dp-wlamywacz:client:housesChanged')
        TriggerEvent('dp-wlamywacz:client:ready')
    end
end)
