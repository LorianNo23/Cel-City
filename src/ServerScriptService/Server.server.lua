-- Main server entry point.
-- This script starts server-only services.

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Services = ServerScriptService:WaitForChild("Services")

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

local function requireService(serviceName: string)
	local moduleScript = Services:WaitForChild(serviceName)
	local success, result = pcall(function()
		return require(moduleScript)
	end)

	if not success then
		warn("[Server] Failed to require", serviceName, result)
		return nil
	end

	return result
end

local CelShadingService = requireService("CelShadingService")
local TerrainService = requireService("TerrainService")
local SaveService = requireService("SaveService")
local EconomyService = requireService("EconomyService")
local PlacementService = requireService("PlacementService")

if not TerrainService then
	error("[Server] TerrainService is required for startup")
end

startService("CelShadingService", function()
	if CelShadingService then
		CelShadingService.Init()
	end
end)
startService("TerrainService", function()
	TerrainService.Init()
end)
startService("SaveService", function()
	if SaveService then
		SaveService.Init()
	end
end)
startService("EconomyService", function()
	if EconomyService then
		EconomyService.Init(SaveService)
	end
end)
startService("PlacementService", function()
	if PlacementService then
		PlacementService.Init(placeBuildingRemote, placementResultRemote)
	end
end)
startService("SaveService restore", function()
	if SaveService and EconomyService and PlacementService then
		SaveService.ApplyLoadedDataForExistingPlayers(EconomyService, PlacementService)
	end
end)

print("[Server] Cel-City server started")
