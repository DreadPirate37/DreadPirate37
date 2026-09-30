fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'dp-pojazdy'
author 'DreadPirate37'
description 'Systemy pojazdu: tryby jazdy, przełączanie napędu, blokady dyferencjałów, reduktor, TC, launch control, tempomat, zawieszenie pneumatyczne, kierunkowskazy, pasy'
version '1.0.0'

shared_scripts {
    'config.lua',
    'locales/pl.lua',
}

client_scripts {
    'client/core.lua',
    'client/handling.lua',
    'client/extras.lua',
    'client/controls.lua',
    'client/nui.lua',
    'client/driver.lua', -- ostatni: startuje pętlę, gdy wszystko jest już zdefiniowane
}

server_scripts {
    'server/main.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/style.css',
    'html/js/app.js',
}
