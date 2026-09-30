-- ==========================================================================
--  Ekipa (EKI-01, EKI-03, EKI-07): zaproszenia, koło sygnałów bez głosu, oznaczenia czujki
-- ==========================================================================
W.crew = nil
local pings = {}

RegisterNetEvent('dp-wlamywacz:client:crew', function(view)
    W.crew = view
    W.Hud({ crew = view and view.members or false })
end)

-- /wlm_ekipa zapros <id> | akceptuj | opusc
RegisterCommand('wlm_ekipa', function(_, args)
    local a = args[1]
    if a == 'zapros' or a == 'invite' then W.Call('crew:invite', tonumber(args[2]))
    elseif a == 'akceptuj' or a == 'accept' then W.Call('crew:accept')
    elseif a == 'opusc' or a == 'leave' then W.Call('crew:leave')
    else W.Notify(L('crew_usage'), 'info') end
end, false)

-- koło sygnałów (EKI-07)
local SIGNALS = { 'stop', 'quiet', 'go', 'clear', 'car', 'help' }
RegisterCommand('wlm_sygnaly', function()
    if not W.ready or W.busy or not W.crew then return end
    local opts = {}
    for _, k in ipairs(SIGNALS) do opts[#opts + 1] = { id = k, label = L('sig_' .. k) } end
    W.OpenWindow('signals', { options = opts }, function(data)
        W.CloseWindow('signals')
        if data.id then W.Callback('crew:signal', data.id) end
        return { ok = true }
    end)
end, false)
RegisterKeyMapping('wlm_sygnaly', 'Włamywacz: sygnały ekipy', 'keyboard', Config.Keys.signals)

RegisterNetEvent('dp-wlamywacz:client:signal', function(kind, name)
    SendNUIMessage({ action = 'signal', kind = kind, text = L('sig_' .. kind), from = name })
end)

-- oznaczenie z lornetki (EKI-03): znacznik 3D i blip na 12 s
RegisterNetEvent('dp-wlamywacz:client:ping', function(c, label, name)
    local b = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(b, 161)
    SetBlipColour(b, 5)
    SetBlipScale(b, 0.8)
    local p = { c = vector3(c.x, c.y, c.z), until_ = GetGameTimer() + 12000, blip = b }
    pings[#pings + 1] = p
    SendNUIMessage({ action = 'signal', kind = 'ping', text = label, from = name })
    if #pings == 1 then
        CreateThread(function()
            while #pings > 0 do
                local now = GetGameTimer()
                for i = #pings, 1, -1 do
                    local q = pings[i]
                    if now > q.until_ then
                        if DoesBlipExist(q.blip) then RemoveBlip(q.blip) end
                        table.remove(pings, i)
                    else
                        DrawMarker(2, q.c.x, q.c.y, q.c.z + 1.2, 0, 0, 0, 180.0, 0, 0, 0.35, 0.35, 0.35, 217, 170, 79, 200, true, true, 2, false, nil, nil, false)
                    end
                end
                Wait(0)
            end
        end)
    end
end)

RegisterNetEvent('dp-wlamywacz:client:memberJoin', function(src)
    if src ~= GetPlayerServerId(PlayerId()) then
        local pid = GetPlayerFromServerId(src)
        W.Notify(L('member_joined', pid ~= -1 and GetPlayerName(pid) or ('#' .. src)), 'info')
    end
end)
