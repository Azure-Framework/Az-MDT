fx_version 'cerulean'
game 'gta5'

name 'az_mdt'
author 'Azure(TheStoicBear)'
description 'Mobile Data Terminal integrated with Az-Framework (basic DB + UI wiring)'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/config/*.json',
    'html/config/config.js',
    'html/img/*.png',
    'html/img/*.jpg'
}

client_scripts {
    'config.lua',
    'client.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'schema.lua',
    'config.lua',
    'server.lua'
}