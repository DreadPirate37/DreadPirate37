-- ==========================================================================
--  Laptop złodzieja (UIX-02, NAR-27): profil i umiejętności, notatnik (REK-02), sklep (NAR-37),
--  poczta (ZLE-19), torba z łupem
-- ==========================================================================
local prop
local ANIM = { 'amb@code_human_in_bus_passenger_idles@female@tablet@base', 'base' }

local function anim(on)
    local ped = PlayerPedId()
    if on then
        if W.LoadDict(ANIM[1]) then TaskPlayAnim(ped, ANIM[1], ANIM[2], 3.0, 3.0, -1, 49, 0, false, false, false) end
        local hash = W.LoadModel('prop_cs_tablet')
        if hash then
            prop = CreateObject(hash, 0.0, 0.0, 0.0, true, true, false)
            AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, 60309), 0.03, 0.002, -0.0, 10.0, 160.0, 0.0, true, false, false, false, 2, true)
            SetModelAsNoLongerNeeded(hash)
        end
    else
        StopAnimTask(ped, ANIM[1], ANIM[2], 2.0)
        if prop and DoesEntityExist(prop) then DeleteEntity(prop) end
        prop = nil
    end
end

function W.OpenLaptop()
    if W.busy then return end
    local r = W.Callback('laptop:data')
    if not r or not r.ok then W.Notify(r and r.msg or L('error'), 'bad') return end
    anim(true)
    W.OpenWindow('laptop', r, function(data)
        if data.action == 'buy' then
            local res = W.Callback('shop:buy', data.index, data.qty or 1)
            if res and res.ok and res.shop then W.SetDrops(res.shop.orders) end
            return res or { ok = false, msg = L('error') }
        elseif data.action == 'mail' then
            return W.Callback('mail:read', data.index)
        elseif data.action == 'refresh' then
            return W.Callback('laptop:data')
        elseif data.action == 'invite' then
            return W.Callback('crew:invite', tonumber(data.id))
        elseif data.action == 'leave' then
            return W.Callback('crew:leave')
        end
        return { ok = false }
    end)
end

AddEventHandler('dp-wlamywacz:client:windowClosed', function(kind)
    if kind == 'laptop' then anim(false) end
end)

RegisterCommand('wlm_laptop', function() if W.ready then W.OpenLaptop() end end, false)
RegisterKeyMapping('wlm_laptop', 'Włamywacz: laptop', 'keyboard', Config.Keys.laptop)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and prop and DoesEntityExist(prop) then DeleteEntity(prop) end
end)
