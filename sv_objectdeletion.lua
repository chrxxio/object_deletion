-- Initialize database connection when resource starts
local deletedObjects = {}
local lastDeletions = {} -- Track last deletion per player

-- Load the objects to delete from database when server starts
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    
    -- Initialize the database if it doesn't exist
    exports.oxmysql:execute([[
        CREATE TABLE IF NOT EXISTS deleted_objects (
            id INT AUTO_INCREMENT PRIMARY KEY,
            model_hash VARCHAR(50) NOT NULL,
            x FLOAT NOT NULL,
            y FLOAT NOT NULL,
            z FLOAT NOT NULL,
            deleted_by VARCHAR(50),
            deleted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            is_active BOOLEAN DEFAULT TRUE
        )
    ]], {}, function(result)
        print("Deleted objects database initialized")
        
        -- Load existing deleted objects from database
        exports.oxmysql:execute('SELECT * FROM deleted_objects WHERE is_active = TRUE', {}, function(results)
            if results and #results > 0 then
                for _, obj in ipairs(results) do
                    table.insert(deletedObjects, {
                        id = obj.id,
                        modelHash = obj.model_hash,
                        position = vector3(obj.x, obj.y, obj.z)
                    })
                end
                print("Loaded " .. #results .. " deleted objects from database")
            end
        end)
    end)
end)

-- Send the deleted objects list to clients when they connect
RegisterNetEvent('playerJoining')
AddEventHandler('playerJoining', function()
    local src = source
    Wait(5000) -- Give the client time to initialize
    TriggerClientEvent('object:loadDeletedObjects', src, deletedObjects)
end)

-- Check if player has permission to delete objects
RegisterNetEvent('object:checkDeletePermission')
AddEventHandler('object:checkDeletePermission', function()
    local src = source
    local hasPermission = IsPlayerAceAllowed(src, "command.deletethisobjectmodel")
    TriggerClientEvent('object:permissionResponse', src, hasPermission)
end)

-- Register command to delete an object permanently (kept for backward compatibility)
RegisterCommand("deletethisobjectmodel", function(source, args, rawCommand)
    if source > 0 then
        -- Check if player has permission
        if IsPlayerAceAllowed(source, "command.deletethisobjectmodel") then
            -- Get player identifier for tracking who deleted the object
            local playerIdentifier = GetPlayerIdentifiers(source)[1] or "console"
            
            -- Handle the deletion request
            if args[1] then
                -- If specific coords were provided (for server-side execution)
                if args[2] and args[3] and args[4] then
                    local x, y, z = tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
                    local modelName = args[1]
                    local modelHash = GetHashKey(modelName)
                    
                    -- Add to database
                    exports.oxmysql:execute('INSERT INTO deleted_objects (model_hash, x, y, z, deleted_by) VALUES (?, ?, ?, ?, ?)',
                    {modelHash, x, y, z, playerIdentifier}, function(insertId)
                        if insertId > 0 then
                            -- Add to memory cache with database ID
                            local newEntry = {
                                id = insertId,
                                modelHash = tostring(modelHash),
                                position = vector3(x, y, z)
                            }
                            table.insert(deletedObjects, newEntry)
                            
                            -- Track as last deletion for this player
                            lastDeletions[playerIdentifier] = newEntry
                            
                            -- Broadcast to all clients to delete this object
                            TriggerClientEvent('object:deleteObject', -1, modelHash, x, y, z)
                            TriggerClientEvent('chat:addMessage', source, {
                                args = {"^2Success", "Object added to permanent deletion list. Use /undoDelete to undo."}
                            })
                        end
                    end)
                else
                    -- Let the client handle detection of nearby object
                    TriggerClientEvent('object:requestDeletion', source, args[1], playerIdentifier)
                end
            else
                TriggerClientEvent('chat:addMessage', source, {
                    args = {"^1Error", "Please specify a model name."}
                })
            end
        else
            TriggerClientEvent('chat:addMessage', source, {
                args = {"^1Error", "You don't have permission to use this command."}
            })
        end
    else
        -- If executed from server console, need coordinates
        if args[1] and args[2] and args[3] and args[4] then
            local modelName = args[1]
            local x, y, z = tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
            local modelHash = GetHashKey(modelName)
            
            -- Add to database
            exports.oxmysql:execute('INSERT INTO deleted_objects (model_hash, x, y, z, deleted_by) VALUES (?, ?, ?, ?, ?)',
            {modelHash, x, y, z, "console"}, function(insertId)
                if insertId > 0 then
                    -- Add to memory cache
                    local newEntry = {
                        id = insertId,
                        modelHash = tostring(modelHash),
                        position = vector3(x, y, z)
                    }
                    table.insert(deletedObjects, newEntry)
                    
                    -- Track as last deletion for console
                    lastDeletions["console"] = newEntry
                    
                    -- Broadcast to all clients to delete this object
                    TriggerClientEvent('object:deleteObject', -1, modelHash, x, y, z)
                    print("Object added to permanent deletion list.")
                end
            end)
        else
            print("Usage: deletethisobjectmodel [model_name] [x] [y] [z]")
        end
    end
end, true)

-- Register network event to save deleted object from client
RegisterNetEvent('object:saveDeletedObject')
AddEventHandler('object:saveDeletedObject', function(modelHash, x, y, z, deletedBy)
    -- Verify source to prevent spoofing
    local src = source
    local playerIdentifier = GetPlayerIdentifiers(src)[1] or "unknown"
    
    -- Check permissions
    if not IsPlayerAceAllowed(src, "command.deletethisobjectmodel") then
        TriggerClientEvent('chat:addMessage', src, {
            args = {"^1Error", "You don't have permission to delete objects."}
        })
        return
    end
    
    -- If deletedBy wasn't provided, use the player's identifier
    if not deletedBy then
        deletedBy = playerIdentifier
    end
    
    -- Add to database
    exports.oxmysql:execute('INSERT INTO deleted_objects (model_hash, x, y, z, deleted_by) VALUES (?, ?, ?, ?, ?)',
    {modelHash, x, y, z, deletedBy}, function(insertId)
        if insertId > 0 then
            -- Add to memory cache with database ID
            local newEntry = {
                id = insertId,
                modelHash = tostring(modelHash),
                position = vector3(x, y, z)
            }
            table.insert(deletedObjects, newEntry)
            
            -- Track as last deletion for this player
            lastDeletions[deletedBy] = newEntry
            
            -- Broadcast to all clients to delete this object
            TriggerClientEvent('object:deleteObject', -1, modelHash, x, y, z)
            TriggerClientEvent('chat:addMessage', src, {
                args = {"^2Success", "Object permanently deleted from the map. Use /undoDelete to undo."}
            })
        else
            TriggerClientEvent('chat:addMessage', src, {
                args = {"^1Error", "Failed to save deleted object to database."}
            })
        end
    end)
end)

-- Register command to undo the last deletion
RegisterCommand("undoDelete", function(source, args, rawCommand)
    local identifier
    local isConsole = false
    
    if source > 0 then
        -- Player command
        if not IsPlayerAceAllowed(source, "command.deletethisobjectmodel") then
            TriggerClientEvent('chat:addMessage', source, {
                args = {"^1Error", "You don't have permission to use this command."}
            })
            return
        end
        identifier = GetPlayerIdentifiers(source)[1] or "unknown"
    else
        -- Console command
        identifier = "console"
        isConsole = true
    end
    
    -- Check if this player/console has any deletions to undo
    if not lastDeletions[identifier] then
        if isConsole then
            print("No recent deletions to undo.")
        else
            TriggerClientEvent('chat:addMessage', source, {
                args = {"^1Error", "You have no recent deletions to undo."}
            })
        end
        return
    end
    
    local lastDeletion = lastDeletions[identifier]
    
    -- Mark the object as inactive in the database
    exports.oxmysql:execute('UPDATE deleted_objects SET is_active = FALSE WHERE id = ?',
    {lastDeletion.id}, function(affectedRows)
        if affectedRows > 0 then
            -- Remove from memory cache
            for i, obj in ipairs(deletedObjects) do
                if obj.id == lastDeletion.id then
                    table.remove(deletedObjects, i)
                    break
                end
            end
            
            -- Clear from last deletions
            lastDeletions[identifier] = nil
            
            -- Broadcast to all clients to restore this object
            TriggerClientEvent('object:restoreObject', -1, lastDeletion.modelHash, lastDeletion.position.x, lastDeletion.position.y, lastDeletion.position.z)
            
            if isConsole then
                print("Last deleted object was restored.")
            else
                TriggerClientEvent('chat:addMessage', source, {
                    args = {"^2Success", "Last deleted object was restored."}
                })
            end
        else
            if isConsole then
                print("Failed to restore the object.")
            else
                TriggerClientEvent('chat:addMessage', source, {
                    args = {"^1Error", "Failed to restore the object."}
                })
            end
        end
    end)
end, true)