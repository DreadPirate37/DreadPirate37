fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'dp-doorlock'
author 'DreadPirate37'
description 'Rozbudowany system zamków drzwi: klucze, PIN, karty, biometria, wytrychy, hakowanie, wyważanie, blokady budynków, harmonogramy, edytor w grze'
version '1.0.0'

shared_scripts {
    'config.lua',
    'locales/pl.lua',
    'shared/door.lua',
}

client_scripts {
    'client/hooks.lua',
    'client/core.lua',
    'client/doors.lua',
    'client/interact.lua',
    'client/admin.lua',
}

server_scripts {
    'bridge/server.lua',
    'server/hooks.lua',
    'server/storage.lua',
    'server/main.lua',
    'server/actions.lua',
    'server/admin.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/*.css',
    'html/js/*.js',
}
