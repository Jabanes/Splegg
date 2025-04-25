-- PlayerSetup.server.lua (Revised to use ServerStorage template)
-- Location: src/ServerScriptService/PlayerSetup.server.lua

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage") -- Use ServerStorage

-- Find the shovel template directly in ServerStorage
local shovelTemplate = ServerStorage:FindFirstChild("ShovelTemplate") -- Use the name you gave it in ServerStorage

if not shovelTemplate then
    warn("!!! ShovelTemplate not found in ServerStorage !!!")
    -- Attempt to wait briefly in case it's still loading (less ideal than direct path)
    task.wait(2)
    shovelTemplate = ServerStorage:FindFirstChild("ShovelTemplate")
    if not shovelTemplate then
         warn("!!! ShovelTemplate still not found after waiting!")
         return
    end
end

if not shovelTemplate:IsA("Tool") then
    warn("!!! Object named ShovelTemplate in ServerStorage is NOT a Tool !!!")
    return
end


local function giveShovel(player)
    local character = player.Character
    if not character then return end
    local backpack = player:WaitForChild("Backpack")

    -- Check if player already has the shovel
    -- Use the template's actual name "ShovelTemplate" might be wrong here,
    -- the CLONED tool should probably be named "Shovel"
    if backpack:FindFirstChild("Shovel") or character:FindFirstChild("Shovel") then
       -- print(player.Name .. " already has a shovel.") -- Optional print
        return
    end

    -- Clone the shovel and give it to the player's backpack
    local newShovel = shovelTemplate:Clone()
    newShovel.Name = "Shovel" -- Ensure the cloned tool has the desired name
    newShovel.Parent = backpack
    print("Gave shovel to " .. player.Name .. " from ServerStorage template.")
end

local function onPlayerAdded(player)
    print(player.Name .. " joined.")
    player.CharacterAdded:Connect(function(character)
        print(player.Name .. "'s character added.")
        giveShovel(player)
    end)
    if player.Character then
        giveShovel(player)
    end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(onPlayerAdded, player)
end

print("PlayerSetup script loaded (using ServerStorage template).")