-- ==========================================================================
--  Narzędzia po stronie serwera: rękawiczki (NAR-14), maska (NAR-15), przedmioty używalne
-- ==========================================================================
Tools = {}

local function setState(src, key, v) Player(src).state:set(key, v, true) end

-- zakładanie / zdejmowanie rękawiczek; fromClothing = rękawiczki wykryte z ubrania postaci
SV.Register('tool:gloves', function(src, on, fromClothing)
    local p = SV.P(src)
    if not on then
        p.gloves = nil
        setState(src, 'wlmGloves', false)
        return { ok = true }
    end
    if fromClothing then
        p.gloves = { clothing = true }
        setState(src, 'wlmGloves', true)
        return { ok = true, precision = 0 }
    end
    local list = Config.Items.gloves
    for i = #list, 1, -1 do
        local g = list[i]
        if Bridge.ItemCount(src, g.item) > 0 or not Config.RequireItems then
            p.gloves = { item = g.item, uses = g.uses, precision = g.precision }
            setState(src, 'wlmGloves', true)
            return { ok = true, label = g.label, precision = g.precision }
        end
    end
    return { ok = false, msg = L('need_gloves') }
end, 800)

-- każde dotknięcie w rękawiczkach zużywa lateksowe
function Tools.WearGloves(src)
    local g = SV.P(src).gloves
    if not g or not g.item or (g.uses or 0) <= 0 then return end
    g.uses = g.uses - 1
    if g.uses <= 0 then
        Bridge.RemoveItem(src, g.item, 1)
        SV.P(src).gloves = nil
        setState(src, 'wlmGloves', false)
        SV.Notify(src, L('gloves_torn'), 'warn')
        SV.Client(src, 'glovesOff')
    end
end

SV.Register('tool:has', function(src, item)
    return { ok = type(item) == 'string' and Bridge.HasItem(src, item) }
end, 300)

SV.Register('tool:mask', function(src, on)
    setState(src, 'wlmMask', on and true or false)
    return { ok = true }
end, 500)

-- przedmioty używalne z ekwipunku (ESX / QB; ox_inventory – patrz README)
CreateThread(function()
    Wait(1500)
    local map = {
        [Config.Items.laptop] = 'laptop',
        [Config.Items.binoculars] = 'binoculars',
        [Config.Items.flashlight] = 'flashlight',
        [Config.Items.mask] = 'mask',
    }
    for _, g in ipairs(Config.Items.gloves) do map[g.item] = 'gloves' end
    for item, what in pairs(map) do
        Bridge.RegisterUsable(item, function(src) SV.Client(src, 'useItem', what) end)
    end
end)
