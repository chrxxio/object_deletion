fx_version 'cerulean'
game 'gta5'

author 'Chrxme'
description 'Enhanced Object Deletion System with Visual Highlighting'
version '1.0.0'

-- Specify the resource scripts
client_scripts {
    'client/cl_objectdeletion.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua', -- Dependency on oxmysql
    'server/sv_objectdeletion.lua'
}

-- Dependency
dependencies {
    'oxmysql'
}