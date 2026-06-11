-- Main server entry point.
-- This script starts server-only services.

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Services = ServerScriptService:WaitForChild("Services")

local CelShadingService = require(Services:WaitForChild("CelShadingService"))
local EconomyService = require(Services:WaitForChild("EconomyService"))
local PlacementService = require(Services:WaitForChild("PlacementService"))
local TerrainService = require(Services:WaitForChild("TerrainService"))

local function getOrCreateRemoteEvent(folder: Instance, remoteName: string): RemoteEvent
	local remote = folder:FindFirstChild(remoteName)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end

	if remote then
		warn("[Server] Replacing non-RemoteEvent named", remoteName)
		remote:Destroy()
	end

	local newRemote = Instance.new("RemoteEvent")
	newRemote.Name = remoteName
	newRemote.Parent = folder
	return newRemote
end

local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if remotes and not remotes:IsA("Folder") then
	warn("[Server] Replacing non-Folder named Remotes")
	remotes:Destroy()
	remotes = nil
end

if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
end

local placeBuildingRemote = getOrCreateRemoteEvent(remotes, "PlaceBuilding")
local placementResultRemote = getOrCreateRemoteEvent(remotes, "PlacementResult")

local function startService(serviceName: string, initCallback)
	local success, err = pcall(initCallback)
	if not success then
		warn("[Server] Failed to start", serviceName, err)
	end
end

startService("CelShadingService", function()
	CelShadingService.Init()
end)
TerrainService.Init()
EconomyService.Init()
PlacementService.Init(placeBuildingRemote, placementResultRemote)

print("[Server] Cel-City server started")
