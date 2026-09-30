fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'dp-mechanic'
author 'DreadPirate37'
description 'DP Mechanic – realistyczny system mechanika: zużycie części, tuning z realnym wpływem na jazdę, montaż krok po kroku, opony i wyważanie, podnośniki, swapy, nitro, hamownia, tablet warsztatu, faktury i terminal płatniczy'
version '1.0.0'

dependencies {
    'oxmysql',
}

shared_scripts {
    'config/config.lua',
    'config/parts.lua',
    'config/swaps.lua',
    'config/tuning.lua',
    'config/assembly.lua',
    'shared/utils.lua',
    'shared/catalog.lua',
    'shared/handling.lua',
}

client_scripts {
    'client/hooks.lua',
    'client/core.lua',
    'client/zones.lua',
    'client/camera.lua',
    'client/handling.lua',
    'client/wear.lua',
    'client/nitro.lua',
    'client/lifts.lua',
    'client/assembly.lua',
    'client/cabinets.lua',
    'client/tires.lua',
    'client/tuning.lua',
    'client/payment.lua',
    'client/tablet.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/server.lua',
    'server/main.lua',
    'server/db.lua',
    'server/business.lua',
    'server/vehicles.lua',
    'server/orders.lua',
    'server/invoices.lua',
    'server/lifts.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/*.css',
    'html/js/*.js',
    'html/js/tablet/*.js',
    'html/js/games/*.js',
}
