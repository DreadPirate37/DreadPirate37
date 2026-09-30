-- ==========================================================================
--  NPC: paserzy (PAS-01), lombard (PAS-02), zleceniodawca Wiktor (ZLE-01) i skrytki (NAR-37).
--  Pedy spawnowane lokalnie tylko w pobliżu, pętla co 1 s.
-- ==========================================================================
local places = {}                  -- { key, label, model, scenario, coords, kind, ped }
local drops = {}                   -- [i] = { coords, blip }

local function spawn(p)
    local hash = W.LoadModel(p.model)
    if not hash then return end
    local c = p.coords
    local ped = CreatePed(4, hash, c.x, c.y, W.GroundZ(vector3(c.x, c.y, c.z)), c.w or 0.0, false, true)
    SetModelAsNoLongerNeeded(hash)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)
    if p.scenario then TaskStartScenarioInPlace(ped, p.scenario, 0, true) end
    p.ped = ped
end

local function despawn(p)
    if p.ped and DoesEntityExist(p.ped) then DeleteEntity(p.ped) end
    p.ped = nil
end

local function nearVehicleNet()
    local pc = GetEntityCoords(PlayerPedId())
    local best, bd
    for _, v in ipairs(GetGamePool('CVehicle')) do
        local d = #(GetEntityCoords(v) - pc)
        if d < 12.0 and (not bd or d < bd) and NetworkGetEntityIsNetworked(v) then best, bd = v, d end
    end
    return best and NetworkGetNetworkIdFromEntity(best) or nil
end

-- --------------------------------------------------------------------------
--  Paser i lombard: okno sprzedaży
-- --------------------------------------------------------------------------
function W.OpenFence(key, pawn)
    local net = not pawn and nearVehicleNet() or nil
    local r = pawn and W.Callback('pawn:offer') or W.Callback('fence:offer', key, net)
    if not r or not r.ok then W.Notify(r and r.msg or L('error'), 'bad') return end
    W.OpenWindow('fence', r, function(data)
        if data.action ~= 'sell' then return { ok = false } end
        local res = pawn and W.Callback('pawn:sell', data.uids) or W.Callback('fence:sell', key, data.uids, net)
        if res and res.ok then
            SendNUIMessage({ action = 'sound', kind = 'cash' })
            local fresh = pawn and W.Callback('pawn:offer') or W.Callback('fence:offer', key, net)
            return { ok = true, msg = res.msg, offer = fresh }
        end
        return { ok = false, msg = res and res.msg or L('error') }
    end)
end

-- --------------------------------------------------------------------------
--  Wiktor: rozmowa w oknie dialogowym
-- --------------------------------------------------------------------------
local function talk(action)
    local r = W.Callback('contact:talk', action)
    if not r or not r.ok then W.Notify(r and r.msg or L('error'), 'bad') return nil end
    local opts = {}
    if r.canNew then opts[#opts + 1] = { id = 'new', label = L('wiktor_opt_new') } end
    if r.contract then opts[#opts + 1] = { id = 'turnin', label = L('wiktor_opt_turnin') } end
    opts[#opts + 1] = { id = 'close', label = L('close') }
    return { title = Config.Contact.name, text = r.text, options = opts }
end

function W.TalkWiktor()
    local d = talk(nil)
    if not d then return end
    W.OpenWindow('dialog', d, function(data)
        if data.id == 'close' then W.CloseWindow('dialog') return { ok = true } end
        local nd = talk(data.id)
        return { ok = true, dialog = nd }
    end)
end

-- --------------------------------------------------------------------------
--  Skrytki czarnego rynku (NAR-37)
-- --------------------------------------------------------------------------
function W.SetDrops(orders)
    for i, d in pairs(drops) do
        if d.blip and DoesBlipExist(d.blip) then RemoveBlip(d.blip) end
        W.RemovePoint('n:drop:' .. i)
    end
    drops = {}
    for i, o in ipairs(orders or {}) do
        local c = vector3(o.coords.x, o.coords.y, o.coords.z)
        local b = AddBlipForCoord(c.x, c.y, c.z)
        SetBlipSprite(b, 478)
        SetBlipColour(b, o.ready and 2 or 5)
        SetBlipScale(b, 0.75)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(L('drop_blip'))
        EndTextCommandSetBlipName(b)
        drops[i] = { coords = c, blip = b }
        W.AddPoint('n:drop:' .. i, c, 1.2, { {
            label = L('drop_collect'), icon = 'fa-solid fa-box-open',
            action = function()
                if W.Progress(L('drop_searching'), 2.5, 'low') then
                    local r = W.Call('shop:collect')
                    if r and r.ok then
                        local o2 = W.Callback('shop:orders')
                        W.SetDrops(o2 and o2.orders or {})
                    end
                end
            end,
        } })
    end
end

-- --------------------------------------------------------------------------
--  Start: miejsca z serwera, blip Wiktora, pętla spawnów
-- --------------------------------------------------------------------------
AddEventHandler('dp-wlamywacz:client:ready', function()
    local r = W.Callback('econ:places')
    places = {}
    for _, f in ipairs(r and r.fences or {}) do
        places[#places + 1] = { key = f.key, label = f.label, model = f.model, scenario = f.scenario, coords = f.coords, kind = 'fence' }
    end
    local pw = Config.Pawn.ped
    places[#places + 1] = { key = 'pawn', label = Config.Pawn.label, model = pw.model, scenario = 'WORLD_HUMAN_STAND_IMPATIENT', coords = pw.coords, kind = 'pawn' }
    local c = Config.Contact
    places[#places + 1] = { key = 'wiktor', label = c.name, model = c.model, scenario = c.scenario, coords = c.coords, kind = 'contact' }

    local b = AddBlipForCoord(c.coords.x, c.coords.y, c.coords.z)
    SetBlipSprite(b, c.blip.sprite)
    SetBlipColour(b, c.blip.color)
    SetBlipScale(b, c.blip.scale)
    SetBlipAsShortRange(b, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(c.blip.label)
    EndTextCommandSetBlipName(b)

    for _, p in ipairs(places) do
        local action
        if p.kind == 'fence' then action = function() W.OpenFence(p.key) end
        elseif p.kind == 'pawn' then action = function() W.OpenFence('pawn', true) end
        else action = function() W.TalkWiktor() end end
        W.AddPoint('n:' .. p.key, p.coords, 1.6, { { label = L('talk_to', p.label), icon = 'fa-solid fa-comments', action = action } })
    end

    local o = W.Callback('shop:orders')
    if o and o.orders then W.SetDrops(o.orders) end
end)

CreateThread(function()
    while true do
        local pc = GetEntityCoords(PlayerPedId())
        for _, p in ipairs(places) do
            local d = #(pc - vector3(p.coords.x, p.coords.y, p.coords.z))
            if d < 60.0 and not p.ped then spawn(p)
            elseif d > 80.0 and p.ped then despawn(p) end
        end
        Wait(1000)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, p in ipairs(places) do despawn(p) end
end)
