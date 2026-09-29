fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'dp-spawacz'
author 'DreadPirate37'
description 'Praca spawacza z rozbudowaną minigrą NUI (WPS, szlifowanie, sczepianie, spawanie, czyszczenie, RTG)'
version '1.0.0'

shared_scripts {
    'config.lua',
    'locales/pl.lua',
}

client_scripts {
    'client/hooks.lua',
    'client/core.lua',
    'client/depot.lua',
    'client/contract.lua',
    'client/work.lua',
}

server_scripts {
    'bridge/server.lua',
    'server/main.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/style.css',
    'html/js/*.js',
    'html/js/stages/*.js',
}
