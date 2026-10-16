fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rensyu_television'
description 'TVs and boomboxes for FiveM: YouTube / Twitch / web / images / video / audio, synced for every player'
version '1.1.0'

ui_page 'html/index.html'

dependencies { 'ox_lib' }

shared_scripts {
    '@ox_lib/init.lua',
    'shared/locale.lua',
    'config.lua',
    'shared/media.lua',
}

client_script 'client/main.lua'
server_script 'server/main.lua'

-- .gfx files in stream/ are streamed automatically
files {
    'locales/*.json',
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/player.html',
    'html/player.css',
    'html/player.js',
}
