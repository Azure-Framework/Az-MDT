fx_version 'cerulean'
game 'gta5'

name 'Az-MDT'
author 'Azure(TheStoicBear)'
description 'Standalone Mobile Data Terminal with MySQL + ACE permission support'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/simtools.js',
    'html/config/*.json',
    'html/config/config.js',
    'html/img/*.png',
    'html/img/*.jpg',
    'config/postals.json'
}

client_scripts {
    'config.lua',
    'source/client.lua'
}

server_scripts {
    'source/schema.lua',
    'config.lua',
    'source/server.lua'
}