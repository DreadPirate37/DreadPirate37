-- ==========================================================================
--  Haki serwerowe – podepnij tu własny dispatch, logi Discord itd.
-- ==========================================================================
ServerHooks = {}

-- wywoływane przy alarmie (poza wbudowanym powiadomieniem policji)
-- payload = { id, name, group, reason, coords = {x,y,z}, seconds }
function ServerHooks.Dispatch(src, payload)
    if GetResourceState('ps-dispatch') == 'started' then
        -- przykład: exports['ps-dispatch']:CustomAlert({ ... })
    end
end

-- każdy wpis dziennika (np. wysyłka na Discord). Zostaw pustą dla wydajności.
Config.Webhook = ''   -- adres webhooka Discord ('' = wyłączone)

local labels = {
    lock = '🔒 zamknięto', unlock = '🔓 otwarto', denied = '⛔ odmowa', pin_fail = '⌨️ błędny PIN',
    alarm = '🚨 alarm', breach = '💥 wyłamanie', repair = '🔧 naprawa', lockpick = '🗝️ wytrych',
    hack = '💻 hakowanie', lockdown = '🚧 blokada', lockdown_off = '✅ koniec blokady',
}

Hooks = Hooks or {}
function Hooks.OnLog(id, src, action, extra)
    if Config.Webhook == '' or action == 'lock' or action == 'unlock' then return end
    local d = Store.doors[id]
    PerformHttpRequest(Config.Webhook, function() end, 'POST', json.encode({
        username = 'dp-doorlock',
        embeds = { {
            title = (labels[action] or action) .. ' · ' .. (d and d.name or ('#' .. id)),
            description = ('Grupa: **%s**\nGracz: **%s**%s'):format(
                d and d.group ~= '' and d.group or '—',
                src and src > 0 and (GetPlayerName(src) or src) or 'System',
                extra and ('\nSzczegóły: `' .. tostring(extra) .. '`') or ''),
            color = action == 'alarm' and 16729165 or 3066993,
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        } },
    }), { ['Content-Type'] = 'application/json' })
end
