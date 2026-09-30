-- ==========================================================================
--  Policja po stronie klienta: ślady na miejscu (POL-03), sprawdzenie łupu (POL-10),
--  konfiskata przy zatrzymaniu (PRO-11). Komendy działają tylko dla służb z Config.Police.jobs.
-- ==========================================================================
local function nearestHouse()
    local pc = GetEntityCoords(PlayerPedId())
    local best, bd
    for _, h in ipairs(Config.Houses) do
        for _, e in ipairs(h.entries) do
            local d = #(pc - vector3(e.coords.x, e.coords.y, e.coords.z))
            if d < 25.0 and (not bd or d < bd) then best, bd = h.id, d end
        end
    end
    for _, s in ipairs(Config.Sheds) do
        local d = #(pc - vector3(s.coords.x, s.coords.y, s.coords.z))
        if d < 25.0 and (not bd or d < bd) then best, bd = s.id, d end
    end
    return best
end

local function nearestPlayer()
    local me = PlayerPedId()
    local pc = GetEntityCoords(me)
    local best, bd
    for _, pid in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(pid)
        if ped ~= me then
            local d = #(GetEntityCoords(ped) - pc)
            if d < Config.Evidence.inspectDistance and (not bd or d < bd) then best, bd = GetPlayerServerId(pid), d end
        end
    end
    return best
end

RegisterCommand('wlm_slady', function()
    local id = nearestHouse()
    if not id then W.Notify(L('no_house_near'), 'bad') return end
    if not W.Progress(L('evidence_searching'), 6.0, 'low') then return end
    local r = W.Callback('police:evidence', id)
    if not r or not r.ok then W.Notify(r and r.msg or L('error'), 'bad') return end
    W.OpenWindow('evidence', r, function() return { ok = true } end)
end, false)

RegisterCommand('wlm_sprawdz', function(_, args)
    local target = tonumber(args[1]) or nearestPlayer()
    if not target then W.Notify(L('no_target'), 'bad') return end
    local r = W.Callback('police:inspect', target)
    if not r or not r.ok then W.Notify(r and r.msg or L('error'), 'bad') return end
    W.OpenWindow('inspect', r, function() return { ok = true } end)
end, false)

RegisterCommand('wlm_zabierz', function(_, args)
    local target = tonumber(args[1]) or nearestPlayer()
    if not target then W.Notify(L('no_target'), 'bad') return end
    W.Call('police:confiscate', target)
end, false)
