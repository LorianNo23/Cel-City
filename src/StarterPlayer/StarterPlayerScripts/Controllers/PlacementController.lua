--[[
	Client-side placement controller.

	This module will later handle preview models, mouse input, and UI buttons.
	It only sends requests. The server still validates and owns the final result.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Buildings = require(ReplicatedStorage.Shared.Config.Buildings)

local PlacementController = {}

local placeBuildingRemote: RemoteEvent

function PlacementController.Init()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	placeBuildingRemote = remotes:WaitForChild("PlaceBuilding")

	-- TODO: Connect UI buttons and mouse input here.
	-- Example later:
	-- PlacementController.RequestPlaceBuilding("House", mouse.Hit.Position)
end

function PlacementController.RequestPlaceBuilding(buildingId: string, worldPosition: Vector3)
	if not Buildings[buildingId] then
		warn("[PlacementController] Unknown building:", buildingId)
		return
	end

	if not placeBuildingRemote then
		warn("[PlacementController] PlaceBuilding remote is not ready")
		return
	end

	placeBuildingRemote:FireServer(buildingId, worldPosition)
end

return PlacementController
