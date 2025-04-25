-- ShovelHandler.server.lua
-- Location: src/ServerScriptService/ShovelHandler.server.lua
-- Handles server-side egg firing.
-- Changes: Increased spawn offset, ignore self-collision in Touched,
--          adjusted impulse values (potentially), added warnings for Massless.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local ServerStorage = game:GetService("ServerStorage") -- Keep if still used for shovel template

local eggTemplate = ReplicatedStorage:FindFirstChild("EggProjectile")
if not eggTemplate then
    warn("!!! ShovelHandler: EggProjectile template not found in ReplicatedStorage !!!")
    return
end
if not eggTemplate:IsA("BasePart") then
     warn("!!! ShovelHandler: EggProjectile template MUST be a BasePart !!!")
     return
end

-- --- Verify Template Properties (IMPORTANT) ---
if eggTemplate.Anchored then
    warn("!!! ShovelHandler: EggProjectile template is ANCHORED in ReplicatedStorage. Please unanchor it! !!!")
    -- Optionally force it here, but better to fix the template: eggTemplate.Anchored = false
end
if eggTemplate.Massless then
    warn("!!! ShovelHandler: EggProjectile template has Massless=TRUE. Gravity will NOT work! Set Massless to FALSE in Studio. !!!")
    -- Optionally force it here, but better to fix the template: eggTemplate.Massless = false
end
-- --- End Verification ---


-- --- Tweakable Projectile Physics ---
-- NOTE: You MUST ensure EggProjectile.Massless is FALSE for the arc to work!
local EGG_FORWARD_SPEED = 30  -- Forward speed component (Adjust as needed)
local EGG_UPWARD_IMPULSE = 35 -- Upward speed component for arc (Adjust as needed)
local EGG_LIFETIME = 5        -- Max seconds before despawn
local SPAWN_OFFSET = 5        -- INCREASED distance in front of player to spawn egg
-- --- End Tweakable Physics ---

-- Forward declaration for the connection setup
local setupCharacter

-- This function now takes an 'aimDirection' vector provided by the client
local function fireEgg(player, toolInstance, aimDirection)
    -- print("Server: fireEgg received aimDirection:", aimDirection) -- Debug

    local character = player.Character
    local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
    local handle = toolInstance and toolInstance:FindFirstChild("Handle")

    -- Validate essential components
    if not humanoidRootPart or not handle then
        warn("Cannot fire egg: Missing Character, HRP, or Handle for " .. player.Name)
        return
    end
    -- Validate the aimDirection received from the client
    if not (aimDirection and typeof(aimDirection) == "Vector3" and aimDirection.Magnitude > 0.1) then
         warn("Cannot fire egg: Invalid aimDirection received from client " .. player.Name)
         -- Fallback to character's look vector if aim is invalid? Or just return? Let's return for now.
         return
    end

    -- Clone the egg
    local newEgg = eggTemplate:Clone()
    newEgg.Anchored = false -- Ensure clone is unanchored
    newEgg.Massless = false -- Ensure clone is not massless

    -- **1. Parent to workspace FIRST**
    newEgg.Parent = workspace

    -- **2. Set Network Owner to Server**
    newEgg:SetNetworkOwner(nil)

    -- **3. Calculate Spawn Position (using HRP's look vector for offset direction)**
    -- We use the HRP's direction just to determine *where* to spawn it relative to the handle/player.
    local offsetDirection = humanoidRootPart.CFrame.LookVector
    local spawnPosition = handle.Position + (offsetDirection * SPAWN_OFFSET)
    local upVector = Vector3.new(0, 1, 0) -- World's up direction

    -- **4. Set CFrame and Initial Velocity (Using Client's Aim Direction)**
    newEgg.CFrame = CFrame.new(spawnPosition)

    -- Apply combined velocity using the *client's aim direction* for forward component
    -- The magnitude/force comes from the server constants.
    newEgg.AssemblyLinearVelocity = (aimDirection.Unit * EGG_FORWARD_SPEED) + (upVector * EGG_UPWARD_IMPULSE)

    -- **5. Add Touched connection for despawning (with self-collision check)**
    local touchedConnection = nil
    touchedConnection = newEgg.Touched:Connect(function(hitPart)
        -- Check if the part hit belongs to the player who fired the egg OR the tool itself
        if hitPart and character and (hitPart:IsDescendantOf(character) or hitPart:IsDescendantOf(toolInstance)) then
             -- print("Egg self-collided, ignoring.") -- Debug
            return -- Ignore collision with the firing player's character or the shovel parts
        end

        -- If the hit part is valid (not self) and the egg still exists, destroy it
        if newEgg.Parent then
            -- print("Egg touched valid part (".. hitPart.Name .. "), destroying.") -- Debug
            newEgg:Destroy()
        end
    end)

    -- Cleanup with Debris (backup timeout)
    Debris:AddItem(newEgg, EGG_LIFETIME)

    -- print("Server: Fired arcing egg for " .. player.Name .. " towards " .. aimDirection) -- Debug
end


-- == Setup Code (Connecting RemoteEvent - Modified to receive aimDirection) ==

setupCharacter = function(character) -- Assign to the previously declared variable
    local player = Players:GetPlayerFromCharacter(character) -- Get player early for context if needed

    local function setupToolConnections(toolInstance)
        if toolInstance:IsA("Tool") and toolInstance.Name == "Shovel" then
            local shootEvent = toolInstance:FindFirstChild("ShootEvent")
            if shootEvent and shootEvent:IsA("RemoteEvent") then
                -- Disconnect existing connections for this tool first (prevents duplicates on respawn/re-equip)
                -- This requires storing the connection, which adds complexity. A simpler approach for now
                -- is to rely on tool/character cleanup, but be aware of potential duplicate connections.

                -- Connect to the server event, now expecting 'aimDirection' from client
                shootEvent.OnServerEvent:Connect(function(playerWhoFired, aimDirection)
                    -- Basic validation: Ensure the player firing matches the character owner
                    if playerWhoFired ~= player then return end

                    -- Pass the tool instance and the received aimDirection to fireEgg
                    fireEgg(playerWhoFired, toolInstance, aimDirection)
                end)
                -- print("Server: Connected OnServerEvent for", player.Name, "'s Shovel") -- Debug
            else
                warn("Server: Shovel found for", player.Name, "but ShootEvent RemoteEvent is missing!")
            end
        end
    end

    -- Handle tools already present when character loads/spawns
    for _, child in ipairs(character:GetChildren()) do
        if child:IsA("Tool") then
            setupToolConnections(child)
        end
    end
    -- Handle tools added later (e.g., from StarterPack getting equipped)
    character.ChildAdded:Connect(setupToolConnections)

    -- Also check Backpack for tools that might be equipped later/initially
    if player then
        local backpack = player:FindFirstChildOfClass("Backpack")
        if backpack then
            -- Handle tools already in backpack when player joins/character spawns
            for _, tool in ipairs(backpack:GetChildren()) do
                 if tool:IsA("Tool") then setupToolConnections(tool) end -- Setup even if in backpack
            end
            -- Handle tools added to backpack later (less common for this event setup, but safe)
            backpack.ChildAdded:Connect(setupToolConnections)
        end
    end
end

-- ... (PlayerAdded connection and loop remain the same) ...
local function onPlayerAdded(player)
    player.CharacterAdded:Connect(setupCharacter)
    if player.Character then
        task.spawn(setupCharacter, player.Character)
    end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(onPlayerAdded, player)
end


print("ShovelHandler Server Script Loaded (v5 - Mouse Aim & Collision Fix).")