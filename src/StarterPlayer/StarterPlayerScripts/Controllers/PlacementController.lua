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
local placementResultRemote: RemoteEvent
local previewPart: Part
local previewOutline: SelectionBox
local selectedBuildingId = "House"
local isBuildMode = false
local currentRotation = 0
local currentOrigin: Vector2?
local currentRequestPosition: Vector3?
local knownOccupiedCells: { [string]: boolean } = {}
local lastFailureReason: string?
local lastFailureCells: { [string]: boolean } = {}

local PREVIEW_HEIGHT = 6
local FALLBACK_PLACE_DISTANCE = 16
local DEFAULT_PREVIEW_COLOR = Color3.fromRGB(150, 150, 150)
local INVALID_PREVIEW_COLOR = Color3.fromRGB(220, 90, 90)
local PREVIEW_TRANSPARENCY = 0.45
local buildingButtons: { [string]: TextButton } = {}

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

local function raycastGround(x: number, z: number): RaycastResult?
	local rayOrigin = Vector3.new(x, 1000, z)
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

	return Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
end

local function getGroundYAtPosition(position: Vector3): number
	local result = raycastGround(position.X, position.Z)
	if result then
		return result.Position.Y
	end

	return 0
end

-- Local approximation of the server-side water check: the river, the streams,
-- and their gravel banks are the only Water/Slate terrain on the map.
local WATER_MATERIALS = {
	[Enum.Material.Water] = true,
	[Enum.Material.Slate] = true,
}

local function areCellsOnDryLand(cells: { Vector2 }): boolean
	for _, cell in cells do
		local world = Grid.gridToWorld(cell)
		local result = raycastGround(world.X, world.Z)

		if result and WATER_MATERIALS[result.Material] then
			return false
		end
	end

	return true
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
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Transparency = PREVIEW_TRANSPARENCY
	part.Parent = Workspace

	mouse.TargetFilter = part

	return part
end

local function createPreviewOutline(part: Part): SelectionBox
	local outline = Instance.new("SelectionBox")
	outline.Name = "PlacementPreviewOutline"
	outline.Adornee = part
	outline.LineThickness = 0.06
	outline.SurfaceTransparency = 1
	outline.Parent = part

	return outline
end

local function areCellsKnownFree(cells: { Vector2 }): boolean
	for _, cell in cells do
		if knownOccupiedCells[Grid.cellKey(cell)] then
			return false
		end
	end

	return true
end

local function rememberOccupiedCellKeys(cellKeys: { string })
	for _, cellKey in cellKeys do
		knownOccupiedCells[cellKey] = true
	end
end

local function rememberLastFailure(reason: string?, cellKeys: { string }?)
	lastFailureReason = reason
	lastFailureCells = {}

	for _, cellKey in cellKeys or {} do
		lastFailureCells[cellKey] = true
	end
end

local function doCellsMatchLastFailure(cells: { Vector2 }): boolean
	if not lastFailureReason then
		return false
	end

	for _, cell in cells do
		if lastFailureCells[Grid.cellKey(cell)] then
			return true
		end
	end

	return false
end

local function setPreviewVisible(isVisible: boolean)
	if previewPart then
		previewPart.Transparency = if isVisible then PREVIEW_TRANSPARENCY else 1
	end

	if previewOutline then
		previewOutline.Visible = isVisible
	end
end

local function updatePreview()
	local buildingConfig = Buildings[selectedBuildingId]
	local pointedPosition = getPointedWorldPosition()

	if not isBuildMode or not buildingConfig or not pointedPosition then
		setPreviewVisible(false)
		currentOrigin = nil
		currentRequestPosition = nil
		return
	end

	local origin = Grid.worldToGrid(pointedPosition)
	local cells = Grid.getOccupiedCells(origin, buildingConfig.Size, currentRotation)
	local isInsideBounds = Grid.areCellsInsideBounds(cells)
	local isKnownFree = areCellsKnownFree(cells)
	local isDryLand = areCellsOnDryLand(cells)
	local matchesLastFailure = doCellsMatchLastFailure(cells)
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
	previewPart.Color = if isInsideBounds and isKnownFree and isDryLand and not matchesLastFailure
		then DEFAULT_PREVIEW_COLOR
		else INVALID_PREVIEW_COLOR
	previewOutline.Color3 = previewPart.Color

	currentOrigin = origin
	currentRequestPosition = Grid.gridToWorld(origin, groundY)
	setPreviewVisible(true)
end

local function rotatePreview()
	currentRotation = (currentRotation + 90) % 360
	updatePreview()
	print("[PlacementController] Rotation:", currentRotation)
end

local function setSelectedBuilding(buildingId: string)
	if not Buildings[buildingId] then
		warn("[PlacementController] Unknown building:", buildingId)
		return
	end

	selectedBuildingId = buildingId
	rememberLastFailure(nil, nil)

	for id, button in buildingButtons do
		local isSelected = id == selectedBuildingId
		button.BackgroundColor3 = if isSelected then Color3.fromRGB(76, 126, 92) else Color3.fromRGB(35, 38, 42)
		button.TextColor3 = if isSelected then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(220, 220, 220)
	end

	print("[PlacementController] Selected building:", selectedBuildingId)
	updatePreview()
end

local function createBuildingSelectionGui()
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BuildingSelectionGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.new(0, 24, 1, -24)
	panel.Size = UDim2.fromOffset(470, 76)
	panel.BackgroundColor3 = Color3.fromRGB(25, 27, 31)
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	panel.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = panel

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 8)
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.Parent = panel

	for buildingId, config in Buildings do
		local button = Instance.new("TextButton")
		button.Name = `{buildingId}Button`
		button.Size = UDim2.fromOffset(142, 56)
		button.BackgroundColor3 = Color3.fromRGB(35, 38, 42)
		button.BorderSizePixel = 0
		button.Font = Enum.Font.GothamBold
		button.Text = `{config.DisplayName}\n${config.Cost}`
		button.TextColor3 = Color3.fromRGB(220, 220, 220)
		button.TextSize = 16
		button.TextWrapped = true
		button.Parent = panel

		local buttonCorner = Instance.new("UICorner")
		buttonCorner.CornerRadius = UDim.new(0, 6)
		buttonCorner.Parent = button

		button.Activated:Connect(function()
			setSelectedBuilding(buildingId)
			PlacementController.SetBuildMode(true)
		end)

		buildingButtons[buildingId] = button
	end
end

function PlacementController.Init()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	placeBuildingRemote = remotes:WaitForChild("PlaceBuilding")
	placementResultRemote = remotes:WaitForChild("PlacementResult")
	previewPart = createPreviewPart()
	previewOutline = createPreviewOutline(previewPart)
	createBuildingSelectionGui()

	placementResultRemote.OnClientEvent:Connect(function(result)
		if typeof(result) ~= "table" then
			return
		end

		if result.Success == true then
			rememberOccupiedCellKeys(result.Cells or {})
			rememberLastFailure(nil, nil)
		else
			rememberLastFailure(result.Reason, result.Cells or {})
		end
	end)

	RunService.RenderStepped:Connect(updatePreview)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end

		if input.KeyCode == Enum.KeyCode.B then
			PlacementController.SetBuildMode(not isBuildMode)
			return
		end

		if not isBuildMode then
			return
		end

		if input.KeyCode == Enum.KeyCode.R then
			rotatePreview()
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			PlacementController.RequestPlaceBuilding()
		end
	end)

	setSelectedBuilding(selectedBuildingId)
	print("[PlacementController] Press B to toggle build mode. In build mode: R rotates, left-click places.")
end

function PlacementController.SetBuildMode(enabled: boolean)
	isBuildMode = enabled

	if not isBuildMode then
		setPreviewVisible(false)
		currentOrigin = nil
		currentRequestPosition = nil
	end

	print("[PlacementController] Build mode:", if isBuildMode then "ON" else "OFF")
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
