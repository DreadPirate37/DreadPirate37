-- ==========================================================================
--  dp-pojazdy – serwer: pilnuje, żeby klienci nie wpychali śmieci do state bagów.
--  Cała logika jazdy działa po stronie kierowcy (tam liczona jest fizyka auta),
--  serwer tylko odrzuca nieprawidłowe wartości.
-- ==========================================================================
local drives = { FWD = true, RWD = true, AWD = true }
local keys = { mode = true, drive = true, diff = true, low = true, tc = true, susp = true }

local function validState(v)
    if type(v) ~= 'table' then return false end
    for k in pairs(v) do
        if not keys[k] then return false end
    end
    return type(v.mode) == 'string' and Config.Modes[v.mode] ~= nil
        and (v.drive == nil or drives[v.drive] == true)
        and type(v.diff) == 'number' and v.diff >= 0 and v.diff <= 3 and math.floor(v.diff) == v.diff
        and type(v.low) == 'boolean'
        and type(v.tc) == 'string' and Config.TractionControl.levels[v.tc] ~= nil
        and type(v.susp) == 'string' and Config.AirSuspension.levels[v.susp] ~= nil
end

local function reject(bagName, key, value)
    local ent = GetEntityFromStateBagName(bagName)
    if ent == 0 then return end
    local owner = NetworkGetEntityOwner(ent)
    print(('^1[dp-pojazdy]^7 odrzucono %s=%s od gracza %s (%s)'):format(key, json.encode(value), owner, GetPlayerName(owner) or '?'))
    Entity(ent).state:set(key, nil, true)
end

AddStateBagChangeHandler('dpcar', nil, function(bagName, key, value)
    if value == nil then return end
    if not validState(value) then reject(bagName, key, value) end
end)

AddStateBagChangeHandler('dpcar_ind', nil, function(bagName, key, value)
    if value == nil then return end
    if type(value) ~= 'number' or value < 0 or value > 3 or math.floor(value) ~= value then
        reject(bagName, key, value)
    end
end)
