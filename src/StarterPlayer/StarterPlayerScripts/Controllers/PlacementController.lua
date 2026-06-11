--[[
	Client-side placement controller.

	This module will later handle preview models, mouse input, and UI buttons.
	It only sends requests. The server still validates and owns the final result.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Buildings = require(ReplicatedStorage.Shared.Config.Buildings)

local PlacementController = {}

local placeBuildingRemote: RemoteEvent
local localPlayer = Players.LocalPlayer

local TEST_PLACE_DISTANCE = 12

local function getPositionInFrontOfPlayer(): Vector3?
	local character = localPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")

	if not rootPart or not rootPart:IsA("BasePart") then
		return nil
	end

	return rootPart.Position + rootPart.CFrame.LookVector * TEST_PLACE_DISTANCE
end

function PlacementController.Init()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	placeBuildingRemote = remotes:WaitForChild("PlaceBuilding")

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end

		if input.KeyCode == Enum.KeyCode.B then
			local targetPosition = getPositionInFrontOfPlayer()
			if targetPosition then
				PlacementController.RequestPlaceBuilding("House", targetPosition)
			end
		end
	end)

	-- TODO: Ghost Preview - show a transparent preview before sending the request.
	-- TODO: UI Selection - let the player choose which building to place.
	-- TODO: Rotation - rotate the preview and placement request.
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
