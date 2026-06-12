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
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local SaveService = require(script.Parent:WaitForChild("SaveService"))
local TerrainService = require(script.Parent:WaitForChild("TerrainService"))

local PlacementService = {}

local occupiedCells: { [string]: boolean } = {}
local placedBuildingsFolder: Folder
local placementResultRemote: RemoteEvent
local modelRng = Random.new()

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

-- Water and the slate gravel banks around the river and streams.
local WATER_MATERIALS = {
	[Enum.Material.Water] = true,
	[Enum.Material.Slate] = true,
}

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

local function serializeCells(cells: { Vector2 }): { string }
	local cellKeys = {}

	for _, cell in cells do
		table.insert(cellKeys, Grid.cellKey(cell))
	end

	return cellKeys
end

local function sendPlacementResult(player: Player, success: boolean, reason: string, cells: { Vector2 }?)
	if not placementResultRemote then
		return
	end

	placementResultRemote:FireClient(player, {
		Success = success,
		Reason = reason,
		Cells = if cells then serializeCells(cells) else {},
	})
end

local function isValidRotation(rotation: number): boolean
	return VALID_ROTATIONS[rotation] == true
end

local function getBuildingCenterWorld(origin: Vector2, size: Vector2, rotation: number, y: number): Vector3
	local footprintSize = Grid.getFootprintSize(size, rotation)
	local originWorld = Grid.gridToWorld(origin, y)
	local halfOffset = Vector3.new(
		(footprintSize.X - 1) * Grid.TileSize / 2,
		0,
		(footprintSize.Y - 1) * Grid.TileSize / 2
	)

	return originWorld + halfOffset
end

local function raycastGround(x: number, z: number): RaycastResult?
	local rayOrigin = Vector3.new(x, 1000, z)
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

	return Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
end

local function getGroundYAtPosition(position: Vector3): number
	local result = raycastGround(position.X, position.Z)
	if result then
		return result.Position.Y
	end

	return 0
end

local function areCellsOnDryLand(cells: { Vector2 }): boolean
	for _, cell in cells do
		local world = Grid.gridToWorld(cell)

		-- Analytic check against the generated river and stream paths.
		if TerrainService.IsWaterArea(world.X, world.Z) then
			return false
		end

		-- Material check against the real terrain: voxels are 4 studs, so the
		-- visible gravel can extend a few studs past the analytic radius.
		local result = raycastGround(world.X, world.Z)
		if result and WATER_MATERIALS[result.Material] then
			return false
		end
	end

	return true
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
	local footprintSize = Grid.getFootprintSize(buildingConfig.Size, rotation)
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

local function getModelNames(buildingConfig): { string }
	if typeof(buildingConfig.ModelNames) == "table" and #buildingConfig.ModelNames > 0 then
		return buildingConfig.ModelNames
	end

	if typeof(buildingConfig.ModelName) == "string" then
		return { buildingConfig.ModelName }
	end

	return {}
end

local function getSourceModel(buildingId: string, buildingConfig): Instance?
	local buildingModels = ServerStorage:FindFirstChild("BuildingModels")
	if not buildingModels then
		return nil
	end

	local modelNames = getModelNames(buildingConfig)
	if #modelNames == 0 then
		return nil
	end

	local startIndex = modelRng:NextInteger(1, #modelNames)
	for offset = 0, #modelNames - 1 do
		local index = ((startIndex + offset - 1) % #modelNames) + 1
		local sourceModel = buildingModels:FindFirstChild(modelNames[index])

		if sourceModel then
			return sourceModel
		end
	end

	warn("[PlacementService] No model variant found for", buildingId)
	return nil
end

local function getTargetFootprintSize(buildingConfig, rotation: number): Vector2
	return Grid.getFootprintSize(buildingConfig.Size, rotation) * Grid.TileSize
end

local function scaleModelToFootprint(model: Model, targetFootprintSize: Vector2)
	local _, boundsSize = model:GetBoundingBox()
	local currentX = math.max(boundsSize.X, 0.001)
	local currentZ = math.max(boundsSize.Z, 0.001)
	local scale = math.min(targetFootprintSize.X / currentX, targetFootprintSize.Y / currentZ)

	if scale > 0 and scale < math.huge then
		model:ScaleTo(scale)
	end
end

local function scalePartToFootprint(part: BasePart, targetFootprintSize: Vector2)
	local currentX = math.max(part.Size.X, 0.001)
	local currentZ = math.max(part.Size.Z, 0.001)
	local scale = math.min(targetFootprintSize.X / currentX, targetFootprintSize.Y / currentZ)

	if scale > 0 and scale < math.huge then
		part.Size *= scale
	end
end

local function pivotModelBottomTo(model: Model, targetPivot: CFrame)
	local boundsCFrame, boundsSize = model:GetBoundingBox()
	local pivotToBottom = model:GetPivot().Position.Y - (boundsCFrame.Position.Y - boundsSize.Y / 2)
	model:PivotTo(targetPivot + Vector3.new(0, pivotToBottom, 0))
end

local function anchorBuildingInstance(instance: Instance)
	if instance:IsA("BasePart") then
		instance.Anchored = true
	end

	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
end

local function createBuildingInstance(buildingId: string, buildingConfig, centerWorld: Vector3, rotation: number): Instance
	local sourceModel = getSourceModel(buildingId, buildingConfig)
	local pivot = CFrame.new(centerWorld) * CFrame.Angles(0, math.rad(rotation), 0)

	if sourceModel then
		local clone = sourceModel:Clone()
		local targetFootprintSize = getTargetFootprintSize(buildingConfig, rotation)
		anchorBuildingInstance(clone)

		if clone:IsA("Model") then
			scaleModelToFootprint(clone, targetFootprintSize)
			pivotModelBottomTo(clone, pivot)
		elseif clone:IsA("BasePart") then
			scalePartToFootprint(clone, targetFootprintSize)
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

local function placeValidatedBuilding(buildingId: string, buildingConfig, origin: Vector2, rotation: number)
	local occupiedByBuilding = Grid.getOccupiedCells(origin, buildingConfig.Size, rotation)
	local flatCenterWorld = getBuildingCenterWorld(origin, buildingConfig.Size, rotation, 0)
	local groundY = getGroundYAtPosition(flatCenterWorld)
	local centerWorld = Vector3.new(flatCenterWorld.X, groundY, flatCenterWorld.Z)
	local buildingInstance = createBuildingInstance(buildingId, buildingConfig, centerWorld, rotation)
	buildingInstance.Parent = placedBuildingsFolder
	markCellsOccupied(occupiedByBuilding)

	return occupiedByBuilding, centerWorld
end

function PlacementService.Init(placeBuildingRemote: RemoteEvent, resultRemote: RemoteEvent)
	placementResultRemote = resultRemote
	placedBuildingsFolder = getPlacedBuildingsFolder()
	createDebugGrid()

	placeBuildingRemote.OnServerEvent:Connect(function(player, buildingId, requestedPosition, rotation)
		PlacementService.RequestPlaceBuilding(player, buildingId, requestedPosition, rotation)
	end)
end

function PlacementService.RequestPlaceBuilding(player: Player, buildingId: string, requestedPosition: Vector3, rotation: number?)
	if typeof(buildingId) ~= "string" then
		warn("[PlacementService] Invalid building id from", player.Name)
		sendPlacementResult(player, false, "InvalidBuildingId")
		return
	end

	if typeof(requestedPosition) ~= "Vector3" then
		warn("[PlacementService] Invalid position from", player.Name)
		sendPlacementResult(player, false, "InvalidPosition")
		return
	end

	local requestedRotation = rotation or 0
	if typeof(requestedRotation) ~= "number" or not isValidRotation(requestedRotation) then
		warn("[PlacementService] Invalid rotation from", player.Name, requestedRotation)
		sendPlacementResult(player, false, "InvalidRotation")
		return
	end

	local buildingConfig = Buildings[buildingId]
	if not buildingConfig then
		warn("[PlacementService] Unknown building:", buildingId)
		sendPlacementResult(player, false, "UnknownBuilding")
		return
	end

	if not canPlayerRequestPosition(player, requestedPosition) then
		warn("[PlacementService] Placement request too far away from", player.Name)
		sendPlacementResult(player, false, "TooFar")
		return
	end

	local origin = Grid.worldToGrid(requestedPosition)
	local occupiedByBuilding = Grid.getOccupiedCells(origin, buildingConfig.Size, requestedRotation)

	if not Grid.areCellsInsideBounds(occupiedByBuilding) then
		warn("[PlacementService] Building is outside grid bounds:", buildingId, Grid.cellKey(origin))
		sendPlacementResult(player, false, "OutOfBounds", occupiedByBuilding)
		return
	end

	if not areCellsOnDryLand(occupiedByBuilding) then
		warn("[PlacementService] Building overlaps river or stream:", buildingId)
		sendPlacementResult(player, false, "Water", occupiedByBuilding)
		return
	end

	-- TODO: Collision - add checks for roads, steep slopes, and reserved map areas.
	if not areCellsFree(occupiedByBuilding) then
		warn("[PlacementService] Grid cells are already occupied for", buildingId)
		sendPlacementResult(player, false, "Occupied", occupiedByBuilding)
		return
	end

	local cost = buildingConfig.Cost or 0
	if not EconomyService.CanAfford(player, cost) then
		warn("[PlacementService]", player.Name, "cannot afford", buildingId, "cost:", cost)
		sendPlacementResult(player, false, "NotEnoughMoney", occupiedByBuilding)
		return
	end

	local _, centerWorld = placeValidatedBuilding(buildingId, buildingConfig, origin, requestedRotation)
	EconomyService.Spend(player, cost)
	SaveService.AddPlacedBuilding(player, buildingId, origin, requestedRotation)
	sendPlacementResult(player, true, "Placed", occupiedByBuilding)

	print(
		"[PlacementService]",
		player.Name,
		"placed",
		buildingId,
		"at",
		centerWorld
	)
end

function PlacementService.RestoreBuilding(buildingId: string, origin: Vector2, rotation: number): boolean
	if not isValidRotation(rotation) then
		warn("[PlacementService] Cannot restore building with invalid rotation:", rotation)
		return false
	end

	local buildingConfig = Buildings[buildingId]
	if not buildingConfig then
		warn("[PlacementService] Cannot restore unknown building:", buildingId)
		return false
	end

	local occupiedByBuilding = Grid.getOccupiedCells(origin, buildingConfig.Size, rotation)
	if not Grid.areCellsInsideBounds(occupiedByBuilding) then
		warn("[PlacementService] Cannot restore building outside grid bounds:", buildingId, Grid.cellKey(origin))
		return false
	end

	if not areCellsOnDryLand(occupiedByBuilding) then
		warn("[PlacementService] Cannot restore building on water:", buildingId)
		return false
	end

	if not areCellsFree(occupiedByBuilding) then
		warn("[PlacementService] Cannot restore building on occupied cells:", buildingId)
		return false
	end

	placeValidatedBuilding(buildingId, buildingConfig, origin, rotation)
	return true
end

return PlacementService
