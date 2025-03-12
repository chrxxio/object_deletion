local deletedObjects = {}
local deleteRadius = 50.0 -- Radius to check for deleted objects
local isHighlightingEnabled = false
local highlightedObject = nil
local targetObject = nil
local targetModelHash = nil
local highlightColor = {r = 255, g = 0, b = 0, a = 200} -- Red with transparency

-- Load deleted objects from server
RegisterNetEvent('object:loadDeletedObjects')
AddEventHandler('object:loadDeletedObjects', function(objects)
    deletedObjects = objects
    print("Received " .. #objects .. " deleted objects from server")
    
    -- Process them immediately
    ProcessDeletedObjects()
end)

-- Add new deleted object from server
RegisterNetEvent('object:deleteObject')
AddEventHandler('object:deleteObject', function(modelHash, x, y, z)
    table.insert(deletedObjects, {
        modelHash = tostring(modelHash),
        position = vector3(x, y, z)
    })
    
    -- Delete this specific object if it exists
    local obj = GetClosestObjectOfType(x, y, z, 5.0, tonumber(modelHash), false, false, false)
    if DoesEntityExist(obj) then
        NetworkRequestControlOfEntity(obj)
        SetEntityAsMissionEntity(obj, false, true)
        DeleteObject(obj)
    end
end)

-- Restore an object (undo deletion)
RegisterNetEvent('object:restoreObject')
AddEventHandler('object:restoreObject', function(modelHash, x, y, z)
    -- Remove from local deleted objects cache
    for i, obj in ipairs(deletedObjects) do
        if obj.modelHash == tostring(modelHash) and 
           math.abs(obj.position.x - x) < 0.1 and 
           math.abs(obj.position.y - y) < 0.1 and 
           math.abs(obj.position.z - z) < 0.1 then
            table.remove(deletedObjects, i)
            break
        end
    end
    
    -- The object will naturally reappear after a game reload or when re-entering the area
    TriggerEvent('chat:addMessage', {
        args = {"^3Info", "Object restored. It will reappear when you reload the area."}
    })
end)

-- Process deleted objects whenever player moves to new area
Citizen.CreateThread(function()
    while true do
        ProcessDeletedObjects()
        Citizen.Wait(5000) -- Check every 5 seconds
    end
end)

-- Function to process all deleted objects near player
function ProcessDeletedObjects()
    local playerCoords = GetEntityCoords(PlayerPedId())
    
    for _, obj in ipairs(deletedObjects) do
        -- Check if object is within processing radius
        if #(playerCoords - obj.position) < deleteRadius then
            local modelHash = tonumber(obj.modelHash)
            local objEntity = GetClosestObjectOfType(
                obj.position.x, obj.position.y, obj.position.z, 
                5.0, modelHash, false, false, false
            )
            
            if DoesEntityExist(objEntity) then
                NetworkRequestControlOfEntity(objEntity)
                SetEntityAsMissionEntity(objEntity, false, true)
                DeleteObject(objEntity)
            end
        end
    end
end

-- Find and highlight the closest object
function FindAndHighlightObject()
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local found = false
    
    -- Clear previous highlighting
    if DoesEntityExist(highlightedObject) then
        SetEntityDrawOutline(highlightedObject, false)
        highlightedObject = nil
    end
    
    -- Get all objects
    local objects = GetGamePool('CObject')
    local closestDist = 3.0 -- Max distance to highlight
    local closestObj = nil
    
    -- Find the closest object
    for _, obj in ipairs(objects) do
        if DoesEntityExist(obj) then
            local objCoords = GetEntityCoords(obj)
            local distance = #(playerCoords - objCoords)
            
            if distance < closestDist then
                closestDist = distance
                closestObj = obj
                found = true
            end
        end
    end
    
    -- Highlight the closest object
    if found and DoesEntityExist(closestObj) then
        SetEntityDrawOutline(closestObj, true)
        SetEntityDrawOutlineColor(highlightColor.r, highlightColor.g, highlightColor.b, highlightColor.a)
        highlightedObject = closestObj
        targetObject = closestObj
        targetModelHash = GetEntityModel(closestObj)
        
        return true
    end
    
    return false
end

-- Thread for object highlighting when enabled
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        
        if isHighlightingEnabled then
            -- Find and highlight the closest object
            local found = FindAndHighlightObject()
            
            -- Show help text if an object is highlighted
            if found then
                BeginTextCommandDisplayHelp("STRING")
                AddTextComponentSubstringPlayerName("Press ~INPUT_CONTEXT~ to delete this object or ~INPUT_FRONTEND_CANCEL~ to cancel")
                EndTextCommandDisplayHelp(0, false, true, -1)
                
                -- Handle key press for deletion
                if IsControlJustPressed(0, 51) then -- E key (INPUT_CONTEXT)
                    if DoesEntityExist(targetObject) then
                        local objCoords = GetEntityCoords(targetObject)
                        
                        -- Request control and delete the object locally
                        NetworkRequestControlOfEntity(targetObject)
                        SetEntityAsMissionEntity(targetObject, false, true)
                        DeleteObject(targetObject)
                        
                        -- Clear highlighting
                        SetEntityDrawOutline(targetObject, false)
                        
                        -- Send to server to save in database
                        TriggerServerEvent('object:saveDeletedObject', 
                            targetModelHash, objCoords.x, objCoords.y, objCoords.z, nil)
                            
                        -- Disable highlighting mode
                        isHighlightingEnabled = false
                        highlightedObject = nil
                        targetObject = nil
                    end
                elseif IsControlJustPressed(0, 194) then -- ESC key (INPUT_FRONTEND_CANCEL)
                    -- Disable highlighting mode
                    isHighlightingEnabled = false
                    if DoesEntityExist(highlightedObject) then
                        SetEntityDrawOutline(highlightedObject, false)
                    end
                    highlightedObject = nil
                    targetObject = nil
                    TriggerEvent('chat:addMessage', {
                        args = {"^3Info", "Object deletion canceled."}
                    })
                end
            end
        end
    end
end)

-- Register command to enable/disable object highlighting for deletion
RegisterCommand("deleteobject", function(source, args, rawCommand)
    -- Check if player has permissions (will be server-side)
    TriggerServerEvent("object:checkDeletePermission")
end, false)

-- Handle permission check response
RegisterNetEvent('object:permissionResponse')
AddEventHandler('object:permissionResponse', function(hasPermission)
    if hasPermission then
        -- Toggle highlighting mode
        isHighlightingEnabled = not isHighlightingEnabled
        
        if isHighlightingEnabled then
            TriggerEvent('chat:addMessage', {
                args = {"^2Info", "Object deletion mode enabled. Look at an object and press E to delete it."}
            })
        else
            if DoesEntityExist(highlightedObject) then
                SetEntityDrawOutline(highlightedObject, false)
            end
            highlightedObject = nil
            targetObject = nil
            TriggerEvent('chat:addMessage', {
                args = {"^3Info", "Object deletion mode disabled."}
            })
        end
    else
        TriggerEvent('chat:addMessage', {
            args = {"^1Error", "You don't have permission to use this command."}
        })
    end
end)

-- Handle client-side deletion request from command
RegisterNetEvent('object:requestDeletion')
AddEventHandler('object:requestDeletion', function(modelName, playerIdentifier)
    local modelHash = GetHashKey(modelName)
    local playerCoords = GetEntityCoords(PlayerPedId())
    
    -- Find the closest object of the specified type
    local obj = GetClosestObjectOfType(
        playerCoords.x, playerCoords.y, playerCoords.z,
        3.0, modelHash, false, false, false
    )
    
    if DoesEntityExist(obj) then
        -- Get object position
        local objCoords = GetEntityCoords(obj)
        
        -- Request control and delete the object locally
        NetworkRequestControlOfEntity(obj)
        SetEntityAsMissionEntity(obj, false, true)
        DeleteObject(obj)
        
        -- Send to server to save in database
        TriggerServerEvent('object:saveDeletedObject', 
            modelHash, objCoords.x, objCoords.y, objCoords.z, playerIdentifier)
    else
        TriggerEvent('chat:addMessage', {
            args = {"^1Error", "Cannot find an object of model " .. modelName .. " nearby."}
        })
    end
end)