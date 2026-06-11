-- Main server entry point.
-- This script starts server-only services.

local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService:WaitForChild("Services")

local EconomyService = require(Services:WaitForChild("EconomyService"))
local PlacementService = require(Services:WaitForChild("PlacementService"))

EconomyService.Init()
PlacementService.Init()

print("[Server] Cel-City server started")
