-- Main client entry point.
-- This script starts client-only controllers.

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local Controllers = script.Parent:WaitForChild("Controllers")

local PlacementController = require(Controllers:WaitForChild("PlacementController"))

PlacementController.Init()

print("[Client] Cel-City client started for", player.Name)
