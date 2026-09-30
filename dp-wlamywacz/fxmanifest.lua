fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'dp-wlamywacz'
author 'DreadPirate37'
description 'Włamania do domów inspirowane Thief Simulatorem: rekonesans, zamki i wytrychy, domownicy z AI, alarmy, kamery, łup, paser i policja'
version '0.1.0'

shared_scripts {
    'config.lua',
    'config/houses.lua',
    'config/interiors.lua',
    'config/loot.lua',
    'locales/pl.lua',
    'locales/en.lua',
    'shared/utils.lua',
    'shared/profile.lua',
    'shared/noise.lua',
}

client_scripts {
    'client/core.lua',
    'client/hooks.lua',
    'client/interact.lua',
    'client/nui.lua',
    'client/tools.lua',
    'client/world.lua',
    'client/recon.lua',
    'client/interior.lua',
    'client/stealth.lua',
    'client/ai.lua',
    'client/security.lua',
    'client/loot.lua',
    'client/npcs.lua',
    'client/laptop.lua',
    'client/crew.lua',
    'client/police.lua',
    'client/dev.lua',
}

server_scripts {
    'bridge/server.lua',
    'server/core.lua',
    'server/store.lua',
    'server/progress.lua',
    'server/police.lua',
    'server/houses.lua',
    'server/bag.lua',
    'server/tools.lua',
    'server/burglary.lua',
    'server/recon.lua',
    'server/economy.lua',
    'server/contracts.lua',
    'server/crew.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/style.css',
    'html/js/*.js',
    'html/js/games/*.js',
}
