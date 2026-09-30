-- ==========================================================================
--  dp-wlamywacz – rdzeń serwera: callbacki z limitem, tokeny, logi, pora dnia
--  Serwer jest jedynym źródłem prawdy (TEC-04): generuje seedy, tokeny minigier,
--  rekordy łupu i sam decyduje o alarmach, dowodach i wypłatach.
-- ==========================================================================
SV = { players = {} }
local RES = GetCurrentResourceName()

function SV.Debug(...)
    if Config.Debug then print('^3[dp-wlamywacz]^7', ...) end
end

function SV.Log(kind, msg)
    print(('^5[dp-wlamywacz]^7 [%s] %s'):format(kind, msg))
    TriggerEvent('dp-wlamywacz:log', kind, msg)
end

local strikes = {}
function SV.Suspicious(src, reason)
    strikes[src] = (strikes[src] or 0) + 1
    SV.Log('podejrzane', ('%s (%s) – %s [%d]'):format(GetPlayerName(src) or '?', src, reason, strikes[src]))
    TriggerEvent('dp-wlamywacz:suspicious', src, reason, strikes[src])
end

-- --------------------------------------------------------------------------
--  Callbacki (lekki system bez zależności, limit częstotliwości per nazwa)
-- --------------------------------------------------------------------------
local handlers, lastCall = {}, {}

function SV.Register(name, fn, gap)
    handlers[name] = { fn = fn, gap = gap or 150 }
end

RegisterNetEvent('dp-wlamywacz:server:cb', function(name, id, ...)
    local src = source
    if type(id) ~= 'number' or type(name) ~= 'string' then return end
    local h = handlers[name]
    if not h then return TriggerClientEvent('dp-wlamywacz:client:cb', src, id, nil) end
    lastCall[src] = lastCall[src] or {}
    local now = GetGameTimer()
    if lastCall[src][name] and now - lastCall[src][name] < h.gap then
        return TriggerClientEvent('dp-wlamywacz:client:cb', src, id, { ok = false, msg = L('too_fast') })
    end
    lastCall[src][name] = now
    local ok, res = pcall(h.fn, src, ...)
    if not ok then
        print(('^1[dp-wlamywacz] błąd w %s: %s^7'):format(name, res))
        res = { ok = false, msg = L('error') }
    end
    TriggerClientEvent('dp-wlamywacz:client:cb', src, id, res)
end)

function SV.Client(src, event, ...)
    TriggerClientEvent('dp-wlamywacz:client:' .. event, src, ...)
end

function SV.Notify(src, msg, kind) Bridge.Notify(src, msg, kind) end

-- --------------------------------------------------------------------------
--  Tokeny jednorazowe (minigry, przeszukania, akcje z czasem trwania)
-- --------------------------------------------------------------------------
local tokens = {}
local tokenSeq = 0

function SV.IssueToken(src, kind, data, minTime, maxTime)
    tokenSeq = tokenSeq + 1
    local t = ('%x%x%x'):format(math.random(0x10000, 0xfffff), tokenSeq, os.time() % 0xffff)
    tokens[t] = { src = src, kind = kind, data = data or {}, at = GetGameTimer(), min = minTime or 0, max = maxTime or 600 }
    return t
end

-- zwraca dane tokenu albo nil + powód; token znika po użyciu
function SV.UseToken(src, t, kind)
    local tk = type(t) == 'string' and tokens[t]
    if not tk then return nil, 'no_token' end
    tokens[t] = nil
    if tk.src ~= src or tk.kind ~= kind then return nil, 'bad_token' end
    local el = (GetGameTimer() - tk.at) / 1000
    if el < tk.min then return nil, 'too_quick', el end
    if el > tk.max then return nil, 'expired', el end
    return tk.data, nil, el
end

function SV.DropTokens(src)
    for k, v in pairs(tokens) do if v.src == src then tokens[k] = nil end end
end

-- --------------------------------------------------------------------------
--  Pozycja gracza i dystanse (OneSync: pozycja z serwera, nie od klienta)
-- --------------------------------------------------------------------------
function SV.Coords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

function SV.Near(src, v, dist)
    local c = SV.Coords(src)
    if not c then return false end
    return #(c - vector3(v.x, v.y, v.z)) <= dist
end

-- --------------------------------------------------------------------------
--  Pora dnia gry. Serwer nie ma zegara GTA – przyjmujemy zegar gracza (jest synchronizowany
--  przez skrypty pogody), a jeśli podasz własną funkcję Config.GameTime(), użyjemy jej.
-- --------------------------------------------------------------------------
function SV.GameMinute(h, m)
    if type(Config.GameTime) == 'function' then
        local ok, hh, mm = pcall(Config.GameTime)
        if ok and hh then return WLM.U.Minute(hh, mm) end
    end
    h, m = tonumber(h) or 12, tonumber(m) or 0
    return WLM.U.Minute(math.floor(WLM.U.Clamp(h, 0, 23)), math.floor(WLM.U.Clamp(m, 0, 59)))
end

-- --------------------------------------------------------------------------
--  Gracze
-- --------------------------------------------------------------------------
function SV.P(src)
    local p = SV.players[src]
    if not p then
        p = { src = src }
        SV.players[src] = p
    end
    if not p.id then p.id = Bridge.GetIdentifier(src) end
    return p
end

AddEventHandler('playerDropped', function()
    local src = source
    TriggerEvent('dp-wlamywacz:internal:dropped', src)
    SV.DropTokens(src)
    SV.players[src] = nil
    lastCall[src] = nil
    strikes[src] = nil
end)

math.randomseed(os.time())
SV.Debug('start, framework:', Bridge.name, 'ekwipunek:', Bridge.inventory, 'zasób:', RES)
