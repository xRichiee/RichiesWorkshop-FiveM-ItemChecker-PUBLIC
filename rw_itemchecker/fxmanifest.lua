fx_version 'cerulean'
game 'gta5'

author "Richie's Workshop"
description 'Read-only item configuration and image checker for ox_inventory'
version '1.0.0'
server_only 'yes'

server_scripts {
    'config.lua',
    'server/checker.lua',
    'adapters/ox_inventory.lua',
    'server/main.lua'
}
