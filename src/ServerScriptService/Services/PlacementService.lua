--[[
	Server-authoritative placement service.

	The client may ask to place a building, but only the server decides
	whether the placement is valid and whether money is spent.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Buildings = require(ReplicatedStorage.Shared.Config.Buildings)
local Grid = require(ReplicatedStorage.Shared.Util.Grid)
local Services = ServerScriptService:WaitForChild("Services")
local EconomyService = require(Services:WaitForChild("EconomyService"))

local PlacementService = {}

function PlacementService.Init()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local placeBuildingRemote = remotes:WaitForChild("PlaceBuilding")

	placeBuildingRemote.OnServerEvent:Connect(function(player, buildingId, requestedPosition)
		PlacementService.RequestPlaceBuilding(player, buildingId, requestedPosition)
	end)
end

function PlacementService.RequestPlaceBuilding(player: Player, buildingId: string, requestedPosition: Vector3)
	if typeof(buildingId) ~= "string" then
		warn("[PlacementService] Invalid building id from", player.Name)
		return
	end

	if typeof(requestedPosition) ~= "Vector3" then
		warn("[PlacementService] Invalid position from", player.Name)
		return
	end

	local buildingConfig = Buildings[buildingId]
	if not buildingConfig then
		warn("[PlacementService] Unknown building:", buildingId)
		return
	end

	local snappedPosition = Grid.SnapWorldPosition(requestedPosition)

	-- TODO: Check if the requested grid cells are inside the buildable map area.
	-- TODO: Check if another building already occupies these grid cells.
	-- TODO: Create or clone the real building model after validation passes.

	if not EconomyService.Spend(player, buildingConfig.Cost) then
		warn("[PlacementService]", player.Name, "cannot afford", buildingId)
		return
	end

	print(
		"[PlacementService]",
		player.Name,
		"placed",
		buildingId,
		"at",
		snappedPosition
	)
end

return PlacementService
