fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'viking_foodtruck'
author 'VikingM0nk'
description 'Standalone in-game food truck business creator'
version '1.1.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js'
}

shared_scripts {
    'shared/globals.lua',
    'shared/lib_init.lua',
    'config.lua',
    'shared/templates.lua',
    'bridges/framework.lua',
    'bridges/inventory.lua',
    'bridges/banking.lua',
    'bridges/billing.lua',
    'bridges/food.lua',
    'bridges/restaurant.lua',
    'bridges/consumables.lua',
    'bridges/target.lua',
    'bridges/keys.lua',
    'bridges/garage.lua'
}

client_scripts {
    'client/lib_ui.lua',
    'client/main.lua',
    'client/runtime.lua',
    'client/target.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'shared/globals.lua',
    'bridges/framework.lua',
    'bridges/inventory.lua',
    'bridges/banking.lua',
    'bridges/billing.lua',
    'bridges/food.lua',
    'bridges/restaurant.lua',
    'bridges/consumables.lua',
    'bridges/keys.lua',
    'bridges/garage.lua',
    'server/database.lua',
    'server/business.lua',
    'server/main.lua'
}

dependencies {
    'oxmysql'
}
