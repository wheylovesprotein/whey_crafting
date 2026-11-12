fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'whey_crafting'
author 'wheylovesprotein'
version '1.0.0'
description 'Placeable crafting benches for Qbox with a live in-game recipe editor'
repository 'https://github.com/wheylovesprotein/whey_crafting'

shared_script '@ox_lib/init.lua'

client_scripts {
    '@qbx_core/modules/playerdata.lua',
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

ui_page 'web/dist/index.html'

files {
    'config/general.lua',
    'config/stations.lua',
    'shared/limits.lua',
    'locales/*.json',
    'web/dist/index.html',
    'web/dist/**/*',
}

dependencies {
    '/onesync',
    'qbx_core',
    'ox_lib',
    'oxmysql',
    'ox_inventory',
}
