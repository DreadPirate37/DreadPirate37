-- ==========================================================================
--  Logi na Discord (webhook). Adres najlepiej ustawić w server.cfg:
--    set dziupla_webhook "https://discord.com/api/webhooks/..."
-- ==========================================================================
local Lg = Config.Logs
local url = GetConvar('dziupla_webhook', '')
if url == '' then url = Lg.webhook or '' end

local COLORS = { earn = 3066993, chop = 15105570, warn = 15158332, info = 3447003, police = 10181046 }

local function ids(src)
    local out = {}
    for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
        local k = id:match('^(%w+):')
        if k == 'license' or k == 'discord' or k == 'fivem' then out[#out + 1] = id end
    end
    return table.concat(out, '\n')
end

-- kind: klucz z Config.Logs.events, color: 'earn' | 'chop' | 'warn' | 'info' | 'police'
function DZ.Log(kind, src, title, text, color)
    if url == '' or not Lg.events[kind] then return end
    local fields = {}
    if src then
        fields[1] = { name = 'Gracz', value = ('%s (id %d)'):format(GetPlayerName(src) or '?', src), inline = true }
        fields[2] = { name = 'Identyfikatory', value = ids(src) ~= '' and ids(src) or '-', inline = true }
    end
    PerformHttpRequest(url, function() end, 'POST', json.encode({
        username = Lg.name,
        embeds = { {
            title = title, description = text, color = COLORS[color or 'info'], fields = fields,
            footer = { text = 'dp-dziupla · ' .. os.date('%Y-%m-%d %H:%M:%S') },
        } },
    }), { ['Content-Type'] = 'application/json' })
end
