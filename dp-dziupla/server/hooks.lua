-- ==========================================================================
--  Haki serwerowe – integracja z bazą pojazdów graczy. Edytuj pod swój serwer.
-- ==========================================================================
ServerHooks = {}

local hasSql = GetResourceState('oxmysql') ~= 'missing'

-- zapytanie przez eksport oxmysql (bez wymagania @oxmysql/lib w manifeście)
local function sql(fn, query, params)
    local p = promise.new()
    exports.oxmysql[fn](exports.oxmysql, query, params, function(r) p:resolve(r) end)
    return Citizen.Await(p)
end

-- Czy auto o tej tablicy należy do gracza? (blokuje rozbieranie aut z garaży graczy)
-- Zwraca true, jeśli auto jest w rejestrze.
function ServerHooks.IsVehicleOwned(plate)
    if not hasSql or not plate then return false end
    plate = plate:gsub('^%s+', ''):gsub('%s+$', '')
    if plate == '' then return false end
    local ok, res = pcall(function()
        if Bridge.name == 'esx' then
            return sql('scalar', 'SELECT 1 FROM owned_vehicles WHERE TRIM(plate) = ? LIMIT 1', { plate })
        elseif Bridge.name == 'qb' or Bridge.name == 'qbx' then
            return sql('scalar', 'SELECT 1 FROM player_vehicles WHERE TRIM(plate) = ? LIMIT 1', { plate })
        end
    end)
    return ok and res ~= nil
end

-- Przekazanie przebitego auta graczowi (Config.Revin.allowKeep = true).
-- props = właściwości pojazdu z klienta (Hooks.GetVehicleProps), model = nazwa modelu
function ServerHooks.GiveVehicle(src, plate, props, model)
    if not hasSql then return false end
    local id = Bridge.GetIdentifier(src)
    local ok = pcall(function()
        if Bridge.name == 'esx' then
            sql('insert', 'INSERT INTO owned_vehicles (owner, plate, vehicle, type, stored) VALUES (?, ?, ?, ?, 0)',
                { id, plate, json.encode(props or { plate = plate }), 'car' })
        elseif Bridge.name == 'qb' or Bridge.name == 'qbx' then
            local license = GetPlayerIdentifierByType(src, 'license')
            sql('insert', 'INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, state) VALUES (?, ?, ?, ?, ?, ?, 0)',
                { license, id, model, joaat(model or ''), json.encode(props or {}), plate })
        end
    end)
    return ok
end

-- Wywołane przy każdej sprzedaży/zarobku z dziupli (logi, podatki, discord webhook...)
function ServerHooks.OnEarn(src, amount, source)
    -- print(('[dp-dziupla] %s zarobił %d$ (%s)'):format(GetPlayerName(src), amount, source))
end
