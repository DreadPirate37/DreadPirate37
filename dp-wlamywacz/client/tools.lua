-- ==========================================================================
--  Narzędzia gracza: pasek (NAR-33), latarka (NAR-04), rękawiczki (NAR-14), maska (NAR-15)
-- ==========================================================================
W.glovePrecision = 0
W.redFilter = false

local function inContext() return W.session ~= nil or next(W.near) ~= nil end

-- --------------------------------------------------------------------------
--  Rękawiczki
-- --------------------------------------------------------------------------
function W.ToggleGloves()
    if W.busy then return end
    local ped = PlayerPedId()
    if W.gloves then
        W.Callback('tool:gloves', false)
        W.gloves = false
        W.Notify(L('gloves_off'), 'info')
    else
        local clothing = Hooks.WearsGloves(ped)
        if not clothing and not W.Progress(L('gloves_putting'), 2.0, 'screw') then return end
        local r = W.Call('tool:gloves', true, clothing)
        if r and r.ok then
            W.gloves = true
            W.glovePrecision = r.precision or 0
            W.Notify(L('gloves_on', r.label or L('gloves_clothing')), 'good')
        end
    end
    W.Hud({ gloves = W.gloves })
end

RegisterNetEvent('dp-wlamywacz:client:glovesOff', function()
    W.gloves = false
    W.Hud({ gloves = false })
end)

-- --------------------------------------------------------------------------
--  Maska: wykrywana z ubrania, zmiana zgłaszana tylko gdy się zmieni
-- --------------------------------------------------------------------------
function W.CheckClothing()
    local ped = PlayerPedId()
    local m = Hooks.WearsMask(ped)
    if m ~= W.mask then
        W.mask = m
        W.Callback('tool:mask', m)
        W.Hud({ mask = m })
    end
    if not W.gloves and Hooks.WearsGloves(ped) then
        local r = W.Callback('tool:gloves', true, true)
        if r and r.ok then W.gloves = true W.Hud({ gloves = true }) end
    end
end

-- --------------------------------------------------------------------------
--  Latarka: światło rysowane w pętli tylko gdy ktoś (ty albo ekipa w domu) ma ją włączoną
-- --------------------------------------------------------------------------
local lightLoop = false

local function drawFor(ped, own, red)
    local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
    local dir
    if own then
        local rot = GetGameplayCamRot(2)
        local rx, rz = math.rad(rot.x), math.rad(rot.z)
        dir = vector3(-math.sin(rz) * math.abs(math.cos(rx)), math.cos(rz) * math.abs(math.cos(rx)), math.sin(rx))
    else
        dir = GetEntityForwardVector(ped)
    end
    if red then
        DrawSpotLight(head.x, head.y, head.z, dir.x, dir.y, dir.z, 255, 40, 30, 9.0, 3.0, 0.0, 22.0, 30.0)
    else
        DrawSpotLight(head.x, head.y, head.z, dir.x, dir.y, dir.z, 255, 245, 225, 16.0, 6.0, 0.0, 20.0, 40.0)
    end
end

local function others()
    local out = {}
    if not W.session then return out end
    for _, pid in ipairs(GetActivePlayers()) do
        if pid ~= PlayerId() then
            local sid = GetPlayerServerId(pid)
            local l = Player(sid).state.wlmLight
            if l then out[#out + 1] = { GetPlayerPed(pid), l == 'red' } end
        end
    end
    return out
end

local function startLightLoop()
    if lightLoop then return end
    lightLoop = true
    CreateThread(function()
        local list, nextScan = {}, 0
        while lightLoop do
            local now = GetGameTimer()
            if now > nextScan then list = others() nextScan = now + 1000 end
            if W.flashlight then drawFor(PlayerPedId(), true, W.redFilter) end
            for _, o in ipairs(list) do if DoesEntityExist(o[1]) then drawFor(o[1], false, o[2]) end end
            if not W.flashlight and #list == 0 then lightLoop = false end
            Wait(0)
        end
    end)
end
W.StartLightLoop = startLightLoop

function W.ToggleFlashlight()
    if not W.flashlight then
        local r = W.Callback('tool:has', Config.Items.flashlight)
        if Config.RequireItems and not (r and r.ok) then W.Notify(L('need_item', L('item_' .. Config.Items.flashlight)), 'bad') return end
    end
    W.flashlight = not W.flashlight
    LocalPlayer.state:set('wlmLight', W.flashlight and (W.redFilter and 'red' or 'white') or false, true)
    W.Hud({ flashlight = W.flashlight })
    SendNUIMessage({ action = 'sound', kind = 'click' })
    if W.flashlight then startLightLoop() end
    W.EmitNoise(Config.Noise.actions.light)
end

RegisterCommand('wlm_latarka', function() if W.ready then W.ToggleFlashlight() end end, false)
RegisterKeyMapping('wlm_latarka', 'Włamywacz: latarka', 'keyboard', Config.Keys.flashlight)
RegisterCommand('wlm_filtr', function()
    W.redFilter = not W.redFilter
    if W.flashlight then LocalPlayer.state:set('wlmLight', W.redFilter and 'red' or 'white', true) end
    W.Notify(W.redFilter and L('filter_red') or L('filter_white'), 'info')
end, false)
RegisterKeyMapping('wlm_filtr', 'Włamywacz: czerwony filtr latarki', 'keyboard', '')

-- --------------------------------------------------------------------------
--  Pasek narzędzi (NAR-33): działa tylko przy celu albo w środku
-- --------------------------------------------------------------------------
local SLOTS = {
    function() W.StartBinoculars() end,
    function() W.ToggleFlashlight() end,
    function() W.ToggleGloves() end,
    function() W.OpenLaptop() end,
}
for i, fn in ipairs(SLOTS) do
    RegisterCommand('wlm_slot' .. i, function()
        if W.ready and not W.busy and inContext() then fn() end
    end, false)
    RegisterKeyMapping('wlm_slot' .. i, ('Włamywacz: narzędzie %d'):format(i), 'keyboard', Config.Keys.slots[i] or '')
end

-- przedmioty użyte z ekwipunku (ESX/QB) albo przez eksport ox_inventory
RegisterNetEvent('dp-wlamywacz:client:useItem', function(what)
    if what == 'laptop' then W.OpenLaptop()
    elseif what == 'binoculars' then W.StartBinoculars()
    elseif what == 'flashlight' then W.ToggleFlashlight()
    elseif what == 'gloves' then W.ToggleGloves()
    elseif what == 'mask' then W.Notify(L('mask_hint'), 'info') end
end)

exports('useItem', function(data)
    local name = type(data) == 'table' and data.name or data
    local map = { [Config.Items.laptop] = 'laptop', [Config.Items.binoculars] = 'binoculars', [Config.Items.flashlight] = 'flashlight' }
    for _, g in ipairs(Config.Items.gloves) do map[g.item] = 'gloves' end
    if map[name] then TriggerEvent('dp-wlamywacz:client:useItem', map[name]) end
end)
