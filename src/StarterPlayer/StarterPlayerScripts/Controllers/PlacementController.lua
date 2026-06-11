--[[
	Client-side placement controller.

	This creates a local-only ghost preview and sends placement requests.
	The server still validates the final building type, position, bounds, rotation,
	and occupied cells before creating the real building.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Buildings = require(ReplicatedStorage.Shared.Config.Buildings)
local Grid = require(ReplicatedStorage.Shared.Util.Grid)

local PlacementController = {}

local localPlayer = Players.LocalPlayer
local mouse = localPlayer:GetMouse()

local placeBuildingRemote: RemoteEvent
local previewPart: Part
local selectedBuildingId = "House"
local currentRotation = 0
local currentOrigin: Vector2?
local currentRequestPosition: Vector3?

local PREVIEW_HEIGHT = 6
local FALLBACK_PLACE_DISTANCE = 16
local VALID_PREVIEW_COLOR = Color3.fromRGB(80, 220, 120)
local INVALID_PREVIEW_COLOR = Color3.fromRGB(240, 80, 80)

local function getCharacterRootPart(): BasePart?
	local character = localPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")

	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end

	return nil
end

local function getFallbackPosition(): Vector3?
	local rootPart = getCharacterRootPart()
	if not rootPart then
		return nil
	end

	return rootPart.Position + rootPart.CFrame.LookVector * FALLBACK_PLACE_DISTANCE
end

local function getPointedWorldPosition(): Vector3?
	if mouse.Hit then
		return mouse.Hit.Position
	end

	return getFallbackPosition()
end

local function getGroundYAtPosition(position: Vector3): number
	local rayOrigin = Vector3.new(position.X, 1000, position.Z)
	local rayDirection = Vector3.new(0, -2000, 0)
	local raycastParams = RaycastParams.new()
	local excludedInstances = {}

	local character = localPlayer.Character
	if character then
		table.insert(excludedInstances, character)
	end

	if previewPart then
		table.insert(excludedInstances, previewPart)
	end

	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = excludedInstances

	local result = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	if result then
		return result.Position.Y
	end

	return 0
end

local function getPreviewCenterWorld(origin: Vector2, size: Vector2, rotation: number, y: number): Vector3
	local footprintSize = Grid.getFootprintSize(size, rotation)
	local originWorld = Grid.gridToWorld(origin, y)
	local halfOffset = Vector3.new(
		(footprintSize.X - 1) * Grid.TileSize / 2,
		0,
		(footprintSize.Y - 1) * Grid.TileSize / 2
	)

	return originWorld + halfOffset
end

local function createPreviewPart(): Part
	local part = Instance.new("Part")
	part.Name = "PlacementPreview"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.ForceField
	part.Transparency = 0.45
	part.Parent = Workspace

	return part
end

local function setPreviewVisible(isVisible: boolean)
	if previewPart then
		previewPart.Transparency = if isVisible then 0.45 else 1
	end
end

local function updatePreview()
	local buildingConfig = Buildings[selectedBuildingId]
	local pointedPosition = getPointedWorldPosition()

	if not buildingConfig or not pointedPosition then
		setPreviewVisible(false)
		currentOrigin = nil
		currentRequestPosition = nil
		return
	end

	local origin = Grid.worldToGrid(pointedPosition)
	local cells = Grid.getOccupiedCells(origin, buildingConfig.Size, currentRotation)
	local isInsideBounds = Grid.areCellsInsideBounds(cells)
	local footprintSize = Grid.getFootprintSize(buildingConfig.Size, currentRotation)
	local flatCenter = getPreviewCenterWorld(origin, buildingConfig.Size, currentRotation, pointedPosition.Y)
	local groundY = getGroundYAtPosition(flatCenter)
	local centerWorld = Vector3.new(flatCenter.X, groundY, flatCenter.Z)

	previewPart.Size = Vector3.new(
		footprintSize.X * Grid.TileSize,
		PREVIEW_HEIGHT,
		footprintSize.Y * Grid.TileSize
	)
	previewPart.CFrame = CFrame.new(centerWorld + Vector3.new(0, PREVIEW_HEIGHT / 2, 0))
		* CFrame.Angles(0, math.rad(currentRotation), 0)
	previewPart.Color = if isInsideBounds then VALID_PREVIEW_COLOR else INVALID_PREVIEW_COLOR

	currentOrigin = origin
	currentRequestPosition = Grid.gridToWorld(origin, groundY)
	setPreviewVisible(true)
end

local function rotatePreview()
	currentRotation = (currentRotation + 90) % 360
	updatePreview()
	print("[PlacementController] Rotation:", currentRotation)
end

function PlacementController.Init()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	placeBuildingRemote = remotes:WaitForChild("PlaceBuilding")
	previewPart = createPreviewPart()

	RunService.RenderStepped:Connect(updatePreview)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end

		if input.KeyCode == Enum.KeyCode.R then
			rotatePreview()
			return
		end

		if input.KeyCode == Enum.KeyCode.B then
			PlacementController.RequestPlaceBuilding()
		end
	end)

	print("[PlacementController] Ready. Move mouse to preview, press R to rotate, B to place.")
end

function PlacementController.RequestPlaceBuilding()
	if not Buildings[selectedBuildingId] then
		warn("[PlacementController] Unknown building:", selectedBuildingId)
		return
	end

	if not placeBuildingRemote then
		warn("[PlacementController] PlaceBuilding remote is not ready")
		return
	end

	if not currentOrigin or not currentRequestPosition then
		warn("[PlacementController] No valid preview position yet")
		return
	end

	placeBuildingRemote:FireServer(selectedBuildingId, currentRequestPosition, currentRotation)
end

return PlacementController
