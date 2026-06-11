--[[
	Server-authoritative placement service.

	The client may ask to place a building, but only the server decides
	whether the placement is valid and whether money is spent.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Buildings = require(ReplicatedStorage.Shared.Config.Buildings)
local Grid = require(ReplicatedStorage.Shared.Util.Grid)

local PlacementService = {}

local occupiedCells: { [string]: boolean } = {}
local placedBuildingsFolder: Folder

local MAX_PLACE_DISTANCE = 80

local function cellKey(cell: Vector2): string
	return `{cell.X},{cell.Y}`
end

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
		if occupiedCells[cellKey(cell)] then
			return false
		end
	end

	return true
end

local function markCellsOccupied(cells: { Vector2 })
	for _, cell in cells do
		occupiedCells[cellKey(cell)] = true
	end
end

local function getBuildingCenterWorld(origin: Vector2, size: Vector2): Vector3
	local originWorld = Grid.gridToWorld(origin)
	local halfOffset = Vector3.new(
		(size.X - 1) * Grid.CellSize / 2,
		0,
		(size.Y - 1) * Grid.CellSize / 2
	)

	return originWorld + halfOffset
end

local function createPlaceholderBuilding(buildingId: string, buildingConfig, centerWorld: Vector3): Instance
	local height = 6
	local part = Instance.new("Part")
	part.Name = `{buildingId}_Placeholder`
	part.Anchored = true
	part.Size = Vector3.new(
		buildingConfig.Size.X * Grid.CellSize,
		height,
		buildingConfig.Size.Y * Grid.CellSize
	)
	part.Position = centerWorld + Vector3.new(0, height / 2, 0)
	part.Color = Color3.fromRGB(90, 180, 120)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	return part
end

local function createBuildingInstance(buildingId: string, buildingConfig, centerWorld: Vector3): Instance
	local buildingModels = ServerStorage:FindFirstChild("BuildingModels")
	local sourceModel = buildingModels and buildingModels:FindFirstChild(buildingConfig.ModelName)

	if sourceModel then
		local clone = sourceModel:Clone()

		if clone:IsA("Model") then
			clone:PivotTo(CFrame.new(centerWorld))
		elseif clone:IsA("BasePart") then
			clone.Anchored = true
			clone.Position = centerWorld + Vector3.new(0, clone.Size.Y / 2, 0)
		else
			clone:Destroy()
			return createPlaceholderBuilding(buildingId, buildingConfig, centerWorld)
		end

		clone.Name = buildingId
		return clone
	end

	return createPlaceholderBuilding(buildingId, buildingConfig, centerWorld)
end

function PlacementService.Init(placeBuildingRemote: RemoteEvent)
	placedBuildingsFolder = getPlacedBuildingsFolder()

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

	if not canPlayerRequestPosition(player, requestedPosition) then
		warn("[PlacementService] Placement request too far away from", player.Name)
		return
	end

	local origin = Grid.worldToGrid(requestedPosition)
	local occupiedByBuilding = Grid.getOccupiedCells(origin, buildingConfig.Size)

	-- TODO: Collision/Bounds - check whether these cells are inside the buildable city area.
	-- TODO: Rotation - rotate size and model orientation when rotation is added.
	if not areCellsFree(occupiedByBuilding) then
		warn("[PlacementService] Grid cells are already occupied for", buildingId)
		return
	end

	-- TODO: Economy Check - verify price before placement once the economy loop is ready.
	-- TODO: Save System - persist placed buildings after DataStore support exists.

	local centerWorld = getBuildingCenterWorld(origin, buildingConfig.Size)
	local buildingInstance = createBuildingInstance(buildingId, buildingConfig, centerWorld)
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
