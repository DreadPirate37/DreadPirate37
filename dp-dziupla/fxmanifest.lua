fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'dp-dziupla'
author 'DreadPirate37'
description 'Dziupla (chop shop): rozbiórka aut śruba po śrubie w stylu Car Mechanic / Thief Simulator, kradzieże na zlecenie, wytrych, nadajniki GPS, magazyn części, rynek, zamówienia, eksport, przebitka VIN, zgniatarka i regeneracja części'
version '1.0.0'

shared_scripts {
    'config.lua',
    'config_parts.lua',
    'locales/pl.lua',
    'shared/logic.lua',
}

client_scripts {
    'client/hooks.lua',
    'client/core.lua',
    'client/visuals.lua',
    'client/props.lua',
    'client/partjob.lua',
    'client/chop.lua',
    'client/shop.lua',
    'client/street.lua',
}

server_scripts {
    'bridge/server.lua',
    'server/hooks.lua',
    'server/main.lua',
    'server/storage.lua',
    'server/logs.lua',
    'server/chop.lua',
    'server/street.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/style.css',
    'html/js/*.js',
}
