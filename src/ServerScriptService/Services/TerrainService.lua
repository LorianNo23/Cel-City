--[[
	Server-side terrain generation service.

	Generates the world once at server start:
	- A perfectly flat, buildable city plateau with its top surface at Y = 0,
	  matching Grid.gridToWorld which places buildings at Y = 0.
	- Hills and small mountains in a ring around the plateau, ramping up with
	  distance so the buildable area itself always stays flat.
	- A large meandering river crossing the whole map.
	- Small streams that start in the hills and flow into the river.
	- Several forest patches in the hill ring.

	All values live in CONFIG and the generation is split into small helpers,
	so the planned terrain-editing feature can reuse them later
	(see TerrainService.GetGroundHeight / TerrainService.GetRiverXAt).
]]

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local TerrainService = {}

local SEED = 1337

local CONFIG = {
	-- Flat, buildable city plateau.
	PlateauHalfSize = 256, -- Studs from the center to the edge of the buildable area.
	GroundDepth = 16, -- Thickness of the ground slab below Y = 0.

	-- Hill ring around the plateau.
	BorderWidth = 280, -- How far the hills extend past the plateau edge.
	ColumnSize = 8, -- Hills are filled in square columns of this size.
	MaxHillHeight = 90,
	HillNoiseScale = 1 / 80, -- Lower = wider, smoother hills.
	HillOctaves = 3,
	RockHeight = 55, -- Columns above this height become rock.
	DirtHeight = 25, -- Columns above this height become ground/dirt.

	-- Large river crossing the map from north to south.
	RiverHalfWidth = 14,
	RiverBankWidth = 8, -- Gravel bank on each side of the river.
	RiverDepth = 6,
	RiverWaterLevel = -1.5,
	RiverMeander = 140, -- Maximum sideways offset of the river path.
	RiverNoiseScale = 1 / 220,
	RiverSampleStep = 4,

	-- Small streams flowing from the hills into the river.
	StreamCount = 4,
	StreamHalfWidth = 3,
	StreamBankWidth = 7, -- Grass-free gravel band of ~2 m (1 stud = 28 cm) around the stream edge.
	StreamDepth = 3.5,
	StreamWaterLevelBelowGround = 0.4, -- Water surface sits this far below the surrounding ground.
	StreamStepSize = 3,

	-- Forest patches in the hill ring. Count, size, and density are
	-- randomized per world within these ranges.
	ForestCountMin = 4,
	ForestCountMax = 7,
	TreesPerForestMin = 10,
	TreesPerForestMax = 18,
	ForestRadiusMin = 90,
	ForestRadiusMax = 140,
	ImportedTreeScaleMin = 39,
	ImportedTreeScaleMax = 51,

	-- Temporary stylized details until custom grass/rock meshes exist.
	GrassTuftCount = 260,
	GrassTuftMinDistanceFromPlateau = 24,
}

-- Forests are intentionally different on every server start, while the
-- terrain itself (hills, river, streams) stays reproducible via SEED.
local rng = Random.new()

-- River path samples, indexed by math.floor(z / RiverSampleStep).
local riverPathX: { [number]: number } = {}

-- Carved stream sample points, used to keep trees out of the water.
local streamPoints: { Vector2 } = {}

local TERRAIN_COLORS = {
	[Enum.Material.Grass] = Color3.fromRGB(94, 166, 82),
	[Enum.Material.LeafyGrass] = Color3.fromRGB(64, 142, 75),
	[Enum.Material.Ground] = Color3.fromRGB(123, 103, 71),
	[Enum.Material.Rock] = Color3.fromRGB(92, 96, 98),
	[Enum.Material.Slate] = Color3.fromRGB(118, 124, 124),
	[Enum.Material.Water] = Color3.fromRGB(61, 132, 166),
}

local function totalHalfSize(): number
	return CONFIG.PlateauHalfSize + CONFIG.BorderWidth
end

local function logStep(message: string)
	print("[TerrainService]", message)
end

local function applyStylizedTerrainPalette(terrain: Terrain)
	for material, color in TERRAIN_COLORS do
		local success, err = pcall(function()
			terrain:SetMaterialColor(material, color)
		end)

		if not success then
			warn("[TerrainService] Could not set terrain material color:", material, err)
		end
	end
end

local function fractalNoise(x: number, z: number): number
	local amplitude = 1
	local frequency = 1
	local total = 0
	local maxValue = 0

	for _ = 1, CONFIG.HillOctaves do
		total += math.noise(
			x * CONFIG.HillNoiseScale * frequency,
			z * CONFIG.HillNoiseScale * frequency,
			SEED
		) * amplitude
		maxValue += amplitude
		amplitude *= 0.5
		frequency *= 2
	end

	-- math.noise returns roughly -0.5..0.5 per octave; remap the sum to 0..1.
	return math.clamp(total / maxValue + 0.5, 0, 1)
end

-- 0 at the plateau edge, 1 at the outer border, so hills rise gradually
-- and never leak into the buildable area.
local function hillRamp(x: number, z: number): number
	local distanceFromPlateau = math.max(math.abs(x), math.abs(z)) - CONFIG.PlateauHalfSize
	local ramp = math.clamp(distanceFromPlateau / CONFIG.BorderWidth, 0, 1)

	return ramp ^ 1.5
end

local function groundHeightAt(x: number, z: number): number
	return fractalNoise(x, z) * CONFIG.MaxHillHeight * hillRamp(x, z)
end

function TerrainService.GetGroundHeight(x: number, z: number): number
	return groundHeightAt(x, z)
end

function TerrainService.GetRiverXAt(z: number): number
	local index = math.floor(z / CONFIG.RiverSampleStep)
	local minIndex = math.floor(-totalHalfSize() / CONFIG.RiverSampleStep)
	local maxIndex = math.floor(totalHalfSize() / CONFIG.RiverSampleStep)

	return riverPathX[math.clamp(index, minIndex, maxIndex)] or 0
end

-- Used by PlacementService to keep buildings out of the river and streams.
-- The gravel banks count as water so buildings never touch the shoreline.
function TerrainService.IsWaterArea(x: number, z: number): boolean
	if math.abs(x - TerrainService.GetRiverXAt(z)) <= CONFIG.RiverHalfWidth + CONFIG.RiverBankWidth then
		return true
	end

	local position = Vector2.new(x, z)
	for _, point in streamPoints do
		if (position - point).Magnitude <= CONFIG.StreamHalfWidth + CONFIG.StreamBankWidth then
			return true
		end
	end

	return false
end

local function fillGroundSlab(terrain: Terrain)
	local half = totalHalfSize()
	local size = Vector3.new(half * 2, CONFIG.GroundDepth, half * 2)

	terrain:FillBlock(CFrame.new(0, -CONFIG.GroundDepth / 2, 0), size, Enum.Material.Grass)
end

local function hillMaterialForHeight(height: number): Enum.Material
	if height > CONFIG.RockHeight then
		return Enum.Material.Rock
	elseif height > CONFIG.DirtHeight then
		return Enum.Material.Ground
	end

	return Enum.Material.LeafyGrass
end

local function fillHillRing(terrain: Terrain)
	local half = totalHalfSize()
	local columnSize = CONFIG.ColumnSize

	for x = -half, half - columnSize, columnSize do
		for z = -half, half - columnSize, columnSize do
			local centerX = x + columnSize / 2
			local centerZ = z + columnSize / 2

			local height = groundHeightAt(centerX, centerZ)
			if height < 1 then
				continue
			end

			terrain:FillBlock(
				CFrame.new(centerX, height / 2, centerZ),
				Vector3.new(columnSize, height, columnSize),
				hillMaterialForHeight(height)
			)
		end

		-- Yield once per row so a large map does not freeze the server on startup.
		task.wait()
	end
end

-- Bank laying and channel carving are separate passes: the wide gravel fill
-- of one path sample would otherwise cover the channel carved at the
-- previous sample and leave the basin full of slate.
-- Roblox terrain has no real gravel material; Slate is the closest match.
local function layGravelBank(
	terrain: Terrain,
	x: number,
	z: number,
	halfWidth: number,
	bankWidth: number,
	bedY: number,
	groundY: number
)
	local bankTotalWidth = (halfWidth + bankWidth) * 2

	-- Solid slate block: wider than the channel and reaching below the bed,
	-- so the carved channel ends up with gravel around and underneath it.
	terrain:FillBlock(
		CFrame.new(x, (groundY + bedY - 2) / 2, z),
		Vector3.new(bankTotalWidth, groundY - (bedY - 2), bankTotalWidth),
		Enum.Material.Slate
	)
end

-- FillBlock leaves the topmost surface voxels partially grass-covered because
-- terrain voxels (4 studs) blend materials. ReplaceMaterial swaps the material
-- without touching the geometry, so the band around the channel is guaranteed
-- to be grass-free.
local function clearGrassAroundChannel(
	terrain: Terrain,
	x: number,
	z: number,
	halfWidth: number,
	bankWidth: number,
	bedY: number,
	groundY: number
)
	local extent = halfWidth + bankWidth
	local region = Region3.new(
		Vector3.new(x - extent, bedY - 2, z - extent),
		Vector3.new(x + extent, groundY + 4, z + extent)
	):ExpandToGrid(4)

	terrain:ReplaceMaterial(region, 4, Enum.Material.Grass, Enum.Material.Slate)
	terrain:ReplaceMaterial(region, 4, Enum.Material.LeafyGrass, Enum.Material.Slate)
end

local function carveChannel(
	terrain: Terrain,
	x: number,
	z: number,
	halfWidth: number,
	bedY: number,
	waterLevel: number,
	groundY: number
)
	local width = halfWidth * 2
	local clearTop = groundY + 4

	terrain:FillBlock(
		CFrame.new(x, (clearTop + bedY) / 2, z),
		Vector3.new(width, clearTop - bedY, width),
		Enum.Material.Air
	)
	terrain:FillBlock(
		CFrame.new(x, (waterLevel + bedY) / 2, z),
		Vector3.new(width, waterLevel - bedY, width),
		Enum.Material.Water
	)
end

local function generateRiverPath()
	local half = totalHalfSize()

	for z = -half, half, CONFIG.RiverSampleStep do
		local noiseValue = math.noise(z * CONFIG.RiverNoiseScale, 1000, SEED)
		riverPathX[math.floor(z / CONFIG.RiverSampleStep)] = noiseValue * 2 * CONFIG.RiverMeander
	end
end

local function computeStreamPath(startX: number, startZ: number): { Vector2 }
	local path = {}
	local x = startX
	local z = startZ

	for _ = 1, 500 do
		local riverX = TerrainService.GetRiverXAt(z)
		local dx = riverX - x

		-- The stream reached the river.
		if math.abs(dx) <= CONFIG.RiverHalfWidth then
			break
		end

		table.insert(path, Vector2.new(x, z))

		-- Move toward the river with a noisy sideways wobble.
		local wobble = math.noise(x * 0.05, z * 0.05, SEED + 50) * 4
		x += math.sign(dx) * CONFIG.StreamStepSize
		z += wobble
	end

	return path
end

local function computeStreamPaths(): { { Vector2 } }
	local startDistance = CONFIG.PlateauHalfSize + CONFIG.BorderWidth * 0.6
	local paths = {}

	for index = 1, CONFIG.StreamCount do
		-- Alternate sides and spread the starts along the Z axis.
		local side = if index % 2 == 0 then 1 else -1
		local zFraction = (index / (CONFIG.StreamCount + 1)) * 2 - 1
		local startZ = zFraction * totalHalfSize() * 0.7

		local path = computeStreamPath(side * startDistance, startZ)
		table.insert(paths, path)

		for _, point in path do
			table.insert(streamPoints, point)
		end
	end

	return paths
end

-- Pass 1: lay every gravel bank (river and streams).
-- Pass 2: carve every channel and fill it with water.
local function generateWater(terrain: Terrain)
	local half = totalHalfSize()
	local streamPaths = computeStreamPaths()

	for z = -half, half, CONFIG.RiverSampleStep do
		local x = TerrainService.GetRiverXAt(z)
		layGravelBank(
			terrain,
			x,
			z,
			CONFIG.RiverHalfWidth,
			CONFIG.RiverBankWidth,
			-CONFIG.RiverDepth,
			groundHeightAt(x, z)
		)

		if z % 64 == 0 then
			task.wait()
		end
	end

	for _, path in streamPaths do
		for _, point in path do
			local groundHeight = groundHeightAt(point.X, point.Y)
			layGravelBank(
				terrain,
				point.X,
				point.Y,
				CONFIG.StreamHalfWidth,
				CONFIG.StreamBankWidth,
				groundHeight - CONFIG.StreamDepth,
				groundHeight
			)
		end

		task.wait()
	end

	for z = -half, half, CONFIG.RiverSampleStep do
		local x = TerrainService.GetRiverXAt(z)
		carveChannel(
			terrain,
			x,
			z,
			CONFIG.RiverHalfWidth,
			-CONFIG.RiverDepth,
			CONFIG.RiverWaterLevel,
			groundHeightAt(x, z)
		)

		if z % 64 == 0 then
			task.wait()
		end
	end

	for _, path in streamPaths do
		for _, point in path do
			local groundHeight = groundHeightAt(point.X, point.Y)
			carveChannel(
				terrain,
				point.X,
				point.Y,
				CONFIG.StreamHalfWidth,
				groundHeight - CONFIG.StreamDepth,
				groundHeight - CONFIG.StreamWaterLevelBelowGround,
				groundHeight
			)
		end

		task.wait()
	end

	-- Pass 3: remove leftover grass from the surface voxels along the banks.
	for z = -half, half, CONFIG.RiverSampleStep do
		local x = TerrainService.GetRiverXAt(z)
		clearGrassAroundChannel(
			terrain,
			x,
			z,
			CONFIG.RiverHalfWidth,
			CONFIG.RiverBankWidth,
			-CONFIG.RiverDepth,
			groundHeightAt(x, z)
		)

		if z % 64 == 0 then
			task.wait()
		end
	end

	for _, path in streamPaths do
		for _, point in path do
			local groundHeight = groundHeightAt(point.X, point.Y)
			clearGrassAroundChannel(
				terrain,
				point.X,
				point.Y,
				CONFIG.StreamHalfWidth,
				CONFIG.StreamBankWidth,
				groundHeight - CONFIG.StreamDepth,
				groundHeight
			)
		end

		task.wait()
	end
end

local function isNearWater(x: number, z: number): boolean
	if math.abs(x - TerrainService.GetRiverXAt(z)) < CONFIG.RiverHalfWidth + 15 then
		return true
	end

	for _, point in streamPoints do
		if (Vector2.new(x, z) - point).Magnitude < 12 then
			return true
		end
	end

	return false
end

-- Fallback used when no imported tree models exist in ServerStorage.TreeModels.
local function createPlaceholderTree(position: Vector3): Model
	local trunkHeight = rng:NextNumber(6, 10)
	local crownSize = rng:NextNumber(7, 11)

	local tree = Instance.new("Model")
	tree.Name = "Tree"

	local trunk = Instance.new("Part")
	trunk.Name = "Trunk"
	trunk.Anchored = true
	trunk.Size = Vector3.new(1.6, trunkHeight, 1.6)
	trunk.Position = position + Vector3.new(0, trunkHeight / 2, 0)
	trunk.Color = Color3.fromRGB(110, 80, 55)
	trunk.Material = Enum.Material.SmoothPlastic
	trunk.Parent = tree

	local crown = Instance.new("Part")
	crown.Name = "Crown"
	crown.Shape = Enum.PartType.Ball
	crown.Anchored = true
	crown.Size = Vector3.one * crownSize
	crown.Position = position + Vector3.new(0, trunkHeight + crownSize / 2 - 1.5, 0)
	crown.Color = Color3.fromRGB(70, rng:NextInteger(130, 170), 80)
	crown.Material = Enum.Material.SmoothPlastic
	crown.Parent = tree

	tree.PrimaryPart = trunk
	return tree
end

-- Imported tree models (e.g. CelCityTree1) placed in ServerStorage.TreeModels.
-- Multiple models in the folder are picked randomly for variety.
local treeTemplates: { Instance } = {}

local function loadTreeTemplates()
	table.clear(treeTemplates)

	local treeModels = ServerStorage:FindFirstChild("TreeModels")
	if not treeModels then
		warn("[TerrainService] ServerStorage.TreeModels not found, using placeholder trees")
		return
	end

	for _, child in treeModels:GetChildren() do
		if child:IsA("Model") or child:IsA("BasePart") then
			table.insert(treeTemplates, child)
		end
	end

	if #treeTemplates == 0 then
		warn("[TerrainService] ServerStorage.TreeModels is empty, using placeholder trees")
	end
end

local function createTree(position: Vector3): Instance
	if #treeTemplates == 0 then
		return createPlaceholderTree(position)
	end

	local template = treeTemplates[rng:NextInteger(1, #treeTemplates)]
	local clone = template:Clone()

	-- Imported meshes are often unanchored and would fall through the map.
	if clone:IsA("BasePart") then
		clone.Anchored = true
	end
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end

	local yRotation = CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)

	if clone:IsA("Model") then
		clone:ScaleTo(rng:NextNumber(CONFIG.ImportedTreeScaleMin, CONFIG.ImportedTreeScaleMax))

		-- Place the bottom of the bounding box on the ground, regardless of
		-- where the import put the pivot.
		local boundsCFrame, boundsSize = clone:GetBoundingBox()
		local pivotToBottom = clone:GetPivot().Position.Y - (boundsCFrame.Position.Y - boundsSize.Y / 2)
		clone:PivotTo(CFrame.new(position + Vector3.new(0, pivotToBottom, 0)) * yRotation)
	elseif clone:IsA("BasePart") then
		clone.CFrame = CFrame.new(position + Vector3.new(0, clone.Size.Y / 2, 0)) * yRotation
	end

	return clone
end

local function createGrassTuft(position: Vector3): Model
	local tuft = Instance.new("Model")
	tuft.Name = "GrassTuft"

	local bladeCount = rng:NextInteger(3, 5)
	for _ = 1, bladeCount do
		local blade = Instance.new("Part")
		blade.Name = "Blade"
		blade.Anchored = true
		blade.CanCollide = false
		blade.Material = Enum.Material.SmoothPlastic
		blade.Color = Color3.fromRGB(58, rng:NextInteger(135, 165), 66)
		blade.Size = Vector3.new(0.22, rng:NextNumber(2.0, 3.8), 0.22)

		local angle = rng:NextNumber(0, math.pi * 2)
		local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * rng:NextNumber(0, 0.7)
		blade.CFrame = CFrame.new(position + offset + Vector3.new(0, blade.Size.Y / 2, 0))
			* CFrame.Angles(math.rad(rng:NextNumber(-16, 16)), angle, math.rad(rng:NextNumber(-16, 16)))
		blade.Parent = tuft
	end

	return tuft
end

local function spawnGrassTufts(detailsFolder: Folder)
	local half = totalHalfSize() - 24

	for _ = 1, CONFIG.GrassTuftCount do
		local x = rng:NextNumber(-half, half)
		local z = rng:NextNumber(-half, half)
		local distanceFromPlateau = math.max(math.abs(x), math.abs(z)) - CONFIG.PlateauHalfSize

		if distanceFromPlateau < CONFIG.GrassTuftMinDistanceFromPlateau then
			continue
		end

		if isNearWater(x, z) then
			continue
		end

		local y = groundHeightAt(x, z)
		if y < 2 or y > CONFIG.RockHeight then
			continue
		end

		createGrassTuft(Vector3.new(x, y, z)).Parent = detailsFolder
	end
end

local function isValidTreePosition(x: number, z: number): boolean
	local distanceFromCenter = math.max(math.abs(x), math.abs(z))

	-- Keep trees out of the buildable area and inside the map.
	if distanceFromCenter < CONFIG.PlateauHalfSize + 16 then
		return false
	end
	if distanceFromCenter > totalHalfSize() - 20 then
		return false
	end

	return not isNearWater(x, z)
end

local function spawnForests(forestsFolder: Folder)
	local forestCount = rng:NextInteger(CONFIG.ForestCountMin, CONFIG.ForestCountMax)

	for _ = 1, forestCount do
		-- Find a cluster center in the hill ring, away from the water.
		local centerX, centerZ
		for _ = 1, 25 do
			local angle = rng:NextNumber(0, math.pi * 2)
			local distance = CONFIG.PlateauHalfSize + rng:NextNumber(60, CONFIG.BorderWidth * 0.7)
			centerX = math.cos(angle) * distance
			centerZ = math.sin(angle) * distance

			if isValidTreePosition(centerX, centerZ) then
				break
			end
		end

		local forestRadius = rng:NextNumber(CONFIG.ForestRadiusMin, CONFIG.ForestRadiusMax)
		local treeCount = rng:NextInteger(CONFIG.TreesPerForestMin, CONFIG.TreesPerForestMax)

		for _ = 1, treeCount do
			-- Bias positions toward the cluster center so the forest core is dense
			-- and the edge thins out naturally.
			local angle = rng:NextNumber(0, math.pi * 2)
			local offset = forestRadius * rng:NextNumber() ^ 0.7
			local x = centerX + math.cos(angle) * offset
			local z = centerZ + math.sin(angle) * offset

			if not isValidTreePosition(x, z) then
				continue
			end

			local tree = createTree(Vector3.new(x, groundHeightAt(x, z), z))
			tree.Parent = forestsFolder
		end

		task.wait()
	end
end

local function getGeneratedMapFolder(): Folder
	local folder = Workspace:FindFirstChild("GeneratedMap")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "GeneratedMap"
		folder.Parent = Workspace
	end

	return folder
end

local function clearGeneratedMapFolder(): Folder
	local folder = getGeneratedMapFolder()
	folder:ClearAllChildren()
	return folder
end

local function runGenerationStep(stepName: string, callback)
	logStep(`Starting {stepName}`)

	local success, err = pcall(callback)
	if not success then
		error(`[TerrainService] Failed during {stepName}: {err}`, 0)
	end

	logStep(`Finished {stepName}`)
end

local function runOptionalGenerationStep(stepName: string, callback)
	logStep(`Starting optional {stepName}`)

	local success, err = pcall(callback)
	if not success then
		warn(`[TerrainService] Optional step failed during {stepName}:`, err)
		return
	end

	logStep(`Finished optional {stepName}`)
end

function TerrainService.Init()
	local terrain = Workspace.Terrain

	logStep(`Generation started with seed {SEED}`)
	loadTreeTemplates()

	-- NOTE: This wipes any terrain painted in the Studio editor.
	-- The whole map is script-generated so it stays reproducible.
	local mapFolder = clearGeneratedMapFolder()
	terrain:Clear()
	applyStylizedTerrainPalette(terrain)

	runGenerationStep("ground slab", function()
		fillGroundSlab(terrain)
	end)

	runGenerationStep("hill ring", function()
		fillHillRing(terrain)
	end)

	runGenerationStep("river path", function()
		generateRiverPath()
	end)

	runGenerationStep("water", function()
		generateWater(terrain)
	end)

	local forestsFolder = Instance.new("Folder")
	forestsFolder.Name = "Forests"
	forestsFolder.Parent = mapFolder

	runGenerationStep("forests", function()
		spawnForests(forestsFolder)
	end)

	local detailsFolder = Instance.new("Folder")
	detailsFolder.Name = "StylizedDetails"
	detailsFolder.Parent = mapFolder

	runOptionalGenerationStep("stylized details", function()
		spawnGrassTufts(detailsFolder)
	end)

	-- TODO: Terrain Editing - the planned feature should reuse layGravelBank,
	-- carveChannel, GetGroundHeight and GetRiverXAt instead of duplicating logic.
	-- TODO: Placement Water Check - PlacementService must reject cells covered by
	-- the river or a stream once bounds checking is added.
	-- TODO: Bridges - allow roads to cross the river using GetRiverXAt.

	logStep(`Terrain generated with seed {SEED}`)
end

return TerrainService
