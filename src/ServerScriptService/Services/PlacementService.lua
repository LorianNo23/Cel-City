--[[
	Server-authoritative placement service.

	The client may ask to place a building, but only the server decides
	whether the placement is valid and whether money is spent.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Buildings = require(ReplicatedStorage.Shared.Config.Buildings)
local Grid = require(ReplicatedStorage.Shared.Util.Grid)

local PlacementService = {}

local occupiedCells: { [string]: boolean } = {}
local placedBuildingsFolder: Folder

local DEBUG_GRID = false
local MAX_PLACE_DISTANCE = 80
local VALID_ROTATIONS = {
	[0] = true,
	[90] = true,
	[180] = true,
	[270] = true,
}

local function getPlacedBuildingsFolder(): Folder
	local folder = Workspace:FindFirstChild("PlacedBuildings")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "PlacedBuildings"
		folder.Parent = Workspace
	end

	return folder
end

local function canPlayerRequestPosition(player: Player, position: Vector3): boolean
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return false
	end

	return (rootPart.Position - position).Magnitude <= MAX_PLACE_DISTANCE
end

local function areCellsFree(cells: { Vector2 }): boolean
	for _, cell in cells do
		if occupiedCells[Grid.cellKey(cell)] then
			return false
		end
	end

	return true
end

local function markCellsOccupied(cells: { Vector2 })
	for _, cell in cells do
		occupiedCells[Grid.cellKey(cell)] = true
	end
end

local function isValidRotation(rotation: number): boolean
	return VALID_ROTATIONS[rotation] == true
end

local function getFootprintSize(size: Vector2, rotation: number): Vector2
	if rotation == 90 or rotation == 270 then
		return Vector2.new(size.Y, size.X)
	end

	return size
end

local function getBuildingCenterWorld(origin: Vector2, size: Vector2, rotation: number, y: number): Vector3
	local footprintSize = getFootprintSize(size, rotation)
	local originWorld = Grid.gridToWorld(origin, y)
	local halfOffset = Vector3.new(
		(footprintSize.X - 1) * Grid.TileSize / 2,
		0,
		(footprintSize.Y - 1) * Grid.TileSize / 2
	)

	return originWorld + halfOffset
end

local function getGroundYAtPosition(position: Vector3): number
	local rayOrigin = Vector3.new(position.X, 1000, position.Z)
	local rayDirection = Vector3.new(0, -2000, 0)
	local raycastParams = RaycastParams.new()
	local excludedInstances = {}

	if placedBuildingsFolder then
		table.insert(excludedInstances, placedBuildingsFolder)
	end

	local gridDebug = Workspace:FindFirstChild("GridDebug")
	if gridDebug then
		table.insert(excludedInstances, gridDebug)
	end

	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = excludedInstances

	local result = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	if result then
		return result.Position.Y
	end

	return 0
end

local function createDebugGrid()
	if not DEBUG_GRID then
		return
	end

	local existingDebugFolder = Workspace:FindFirstChild("GridDebug")
	if existingDebugFolder then
		existingDebugFolder:Destroy()
	end

	local debugFolder = Instance.new("Folder")
	debugFolder.Name = "GridDebug"
	debugFolder.Parent = Workspace

	local minWorld = Grid.gridToWorld(Vector2.new(Grid.MinX, Grid.MinY), 0)
	local maxWorld = Grid.gridToWorld(Vector2.new(Grid.MaxX, Grid.MaxY), 0)
	local width = maxWorld.X - minWorld.X
	local depth = maxWorld.Z - minWorld.Z

	for x = Grid.MinX, Grid.MaxX do
		local world = Grid.gridToWorld(Vector2.new(x, Grid.MinY), 0)
		local line = Instance.new("Part")
		line.Name = "GridLineX"
		line.Anchored = true
		line.CanCollide = false
		line.CanQuery = false
		line.Transparency = 0.75
		line.Color = Color3.fromRGB(80, 160, 255)
		line.Size = Vector3.new(0.05, 0.05, depth)
		line.Position = Vector3.new(world.X, 0.05, minWorld.Z + depth / 2)
		line.Parent = debugFolder
	end

	for y = Grid.MinY, Grid.MaxY do
		local world = Grid.gridToWorld(Vector2.new(Grid.MinX, y), 0)
		local line = Instance.new("Part")
		line.Name = "GridLineY"
		line.Anchored = true
		line.CanCollide = false
		line.CanQuery = false
		line.Transparency = 0.75
		line.Color = Color3.fromRGB(80, 160, 255)
		line.Size = Vector3.new(width, 0.05, 0.05)
		line.Position = Vector3.new(minWorld.X + width / 2, 0.05, world.Z)
		line.Parent = debugFolder
	end
end

local function createPlaceholderBuilding(buildingId: string, buildingConfig, centerWorld: Vector3, rotation: number): Instance
	local height = 6
	local footprintSize = getFootprintSize(buildingConfig.Size, rotation)
	local part = Instance.new("Part")
	part.Name = `{buildingId}_Placeholder`
	part.Anchored = true
	part.Size = Vector3.new(
		footprintSize.X * Grid.TileSize,
		height,
		footprintSize.Y * Grid.TileSize
	)
	part.Position = centerWorld + Vector3.new(0, height / 2, 0)
	part.Color = Color3.fromRGB(90, 180, 120)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	return part
end

local function createBuildingInstance(buildingId: string, buildingConfig, centerWorld: Vector3, rotation: number): Instance
	local buildingModels = ServerStorage:FindFirstChild("BuildingModels")
	local sourceModel = buildingModels and buildingModels:FindFirstChild(buildingConfig.ModelName)
	local pivot = CFrame.new(centerWorld) * CFrame.Angles(0, math.rad(rotation), 0)

	if sourceModel then
		local clone = sourceModel:Clone()

		if clone:IsA("Model") then
			clone:PivotTo(pivot)
		elseif clone:IsA("BasePart") then
			clone.Anchored = true
			clone.Position = centerWorld + Vector3.new(0, clone.Size.Y / 2, 0)
			clone.Orientation = Vector3.new(0, rotation, 0)
		else
			clone:Destroy()
			return createPlaceholderBuilding(buildingId, buildingConfig, centerWorld, rotation)
		end

		clone.Name = buildingId
		return clone
	end

	return createPlaceholderBuilding(buildingId, buildingConfig, centerWorld, rotation)
end

function PlacementService.Init(placeBuildingRemote: RemoteEvent)
	placedBuildingsFolder = getPlacedBuildingsFolder()
	createDebugGrid()

	placeBuildingRemote.OnServerEvent:Connect(function(player, buildingId, requestedPosition, rotation)
		PlacementService.RequestPlaceBuilding(player, buildingId, requestedPosition, rotation)
	end)
end

function PlacementService.RequestPlaceBuilding(player: Player, buildingId: string, requestedPosition: Vector3, rotation: number?)
	if typeof(buildingId) ~= "string" then
		warn("[PlacementService] Invalid building id from", player.Name)
		return
	end

	if typeof(requestedPosition) ~= "Vector3" then
		warn("[PlacementService] Invalid position from", player.Name)
		return
	end

	local requestedRotation = rotation or 0
	if typeof(requestedRotation) ~= "number" or not isValidRotation(requestedRotation) then
		warn("[PlacementService] Invalid rotation from", player.Name, requestedRotation)
		return
	end

	local buildingConfig = Buildings[buildingId]
	if not buildingConfig then
		warn("[PlacementService] Unknown building:", buildingId)
		return
	end

	if not canPlayerRequestPosition(player, requestedPosition) then
		warn("[PlacementService] Placement request too far away from", player.Name)
		return
	end

	local origin = Grid.worldToGrid(requestedPosition)
	local occupiedByBuilding = Grid.getOccupiedCells(origin, buildingConfig.Size, requestedRotation)

	if not Grid.areCellsInsideBounds(occupiedByBuilding) then
		warn("[PlacementService] Building is outside grid bounds:", buildingId, Grid.cellKey(origin))
		return
	end

	-- TODO: Collision - add checks for roads, water, steep slopes, and reserved map areas.
	if not areCellsFree(occupiedByBuilding) then
		warn("[PlacementService] Grid cells are already occupied for", buildingId)
		return
	end

	-- TODO: Economy Check - verify price before placement once the economy loop is ready.
	-- TODO: Save System - persist placed buildings after DataStore support exists.

	local flatCenterWorld = getBuildingCenterWorld(origin, buildingConfig.Size, requestedRotation, requestedPosition.Y)
	local groundY = getGroundYAtPosition(flatCenterWorld)
	local centerWorld = Vector3.new(flatCenterWorld.X, groundY, flatCenterWorld.Z)
	local buildingInstance = createBuildingInstance(buildingId, buildingConfig, centerWorld, requestedRotation)
	buildingInstance.Parent = placedBuildingsFolder
	markCellsOccupied(occupiedByBuilding)

	print(
		"[PlacementService]",
		player.Name,
		"placed",
		buildingId,
		"at",
		centerWorld
	)
end

return PlacementService
