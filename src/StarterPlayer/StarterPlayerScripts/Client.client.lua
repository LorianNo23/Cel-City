-- Main client entry point.
-- This script starts client-only controllers.

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local Controllers = script.Parent:WaitForChild("Controllers")

local EconomyController = require(Controllers:WaitForChild("EconomyController"))
local PlacementController = require(Controllers:WaitForChild("PlacementController"))

EconomyController.Init()
PlacementController.Init()

print("[Client] Cel-City client started for", player.Name)
