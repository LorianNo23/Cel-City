--[[
	Server-side terrain generation service.

	Generates the world once at server start:
	- A perfectly flat, buildable city plateau with its top surface at Y = 0,
	  matching Grid.gridToWorld which places buildings at Y = 0.
	- Hills and small mountains in a ring around the plateau, ramping up with
	  distance so the buildable area itself always stays flat.
	- A large meandering river crossing the whole map.
	- Small streams that start in the hills and flow into the river.
	- A low, gently rolling grass rise on every meadow compartment between
	  the waterways, kept around character height so building on it works fine.
	- A small pond with a dirt shore and cattails in the largest compartment.
	- A loose forest covering the second-largest compartment.
	- Several forest patches in the hill ring.

	All values live in CONFIG and the generation is split into small helpers,
	so the planned terrain-editing feature can reuse them later
	(see TerrainService.GetGroundHeight / TerrainService.GetRiverXAt).
]]

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local TerrainService = {}

-- A fresh seed every server start makes hills, river, and streams different
-- each time, while CONFIG keeps the rules (plateau size, river width, hill
-- heights, ...) the same. Set FIXED_SEED to a number (e.g. 1337) to get a
-- reproducible world again; the active seed is printed in the logs.
local FIXED_SEED: number? = nil
local SEED = FIXED_SEED or Random.new():NextInteger(1, 1_000_000)

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
	RiverMaxStraightLength = 18, -- About 5 meters; add a bend before the path reads as straight.
	RiverShortBendAmplitude = 10,

	-- One gently rolling grass rise per meadow "compartment". The waterways
	-- split the plateau into separate compartments; the hill height grows
	-- with the distance from the nearest water, so every compartment gets
	-- exactly one rise that spreads across all of it. A wide noise wave adds
	-- natural ups and downs on top. Base + amplitude stays around character
	-- height (~5 studs) so everything remains comfortably buildable.
	PlateauHillBaseHeight = 2.8, -- Average rise height inside a compartment.
	PlateauHillNoiseAmplitude = 2.2, -- Natural up/down variation around the base.
	PlateauHillNoiseScale = 1 / 50, -- Lower = wider, smoother undulation.
	PlateauHillFlatMargin = 10, -- Flat meadow strip next to the gravel banks.
	PlateauHillRampDistance = 44, -- Distance over which the rise climbs to full height.
	PlateauHillColumnSize = 4, -- Hills are filled in square columns of this size.

	-- Small streams flowing from the hills into the river.
	StreamCount = 4,
	StreamHalfWidth = 3,
	StreamBankWidth = 7, -- Grass-free gravel band of ~2 m (1 stud = 28 cm) around the stream edge.
	StreamDepth = 3.5,
	StreamWaterLevelBelowGround = 0.4, -- Water surface sits this far below the surrounding ground.
	StreamStepSize = 3,

	-- Small pond in the largest meadow compartment, a bit off its center.
	-- The dirt shore ring (no grass, no gravel) is StreamBankWidth / 2 wide.
	PondRadius = 11,
	PondDepth = 3.5,
	PondWaterLevelBelowGround = 0.5,
	PondCenterOffsetMin = 18, -- How far off the compartment center the pond sits.
	PondCenterOffsetMax = 36,
	PondPlantCountMin = 480,
	PondPlantCountMax = 800,
	PondPlantScaleMin = 3, -- Every plant gets its own random size in this range.
	PondPlantScaleMax = 4,
	PondPlantSpreadMin = 5.4, -- How far past the shore plants reach (~1.5 m); varies
	PondPlantSpreadMax = 10.7, -- by direction up to ~3 m, so it is no perfect circle.
	PondPlantShrinkWithDistance = 0.7, -- Plants at the far edge are 70% smaller.
	PondPlantMinHeight = 1.07, -- ~30 cm; smaller plants do not spawn at all.
	PondSoilPatchRadius = 1.07, -- ~30 cm of brown soil under each plant.

	-- Loose forest covering one smaller meadow compartment completely.
	MeadowForestTreeChance = 0.15, -- Chance per 16x16 cell to hold a tree (sparse, loose forest).
	MeadowForestWaterClearance = 4, -- Trees keep this far from banks and pond shore.

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

-- Forests and details use their own unseeded RNG, so they stay random even
-- when FIXED_SEED pins the terrain layout to a reproducible world.
local rng = Random.new()

-- River path samples, indexed by math.floor(z / RiverSampleStep).
local riverPathX: { [number]: number } = {}

-- Carved stream sample points, used to keep trees out of the water.
local streamPoints: { Vector2 } = {}

-- Center and blocked radius (pond + dirt shore) of the generated pond, so
-- IsWaterArea also keeps buildings out of the pond.
local pondCenter: Vector2? = nil
local pondBlockRadius = 0

-- Meadow-forest trees block building placement. Hill-ring trees are outside
-- the buildable meadow, so only meadow trees are tracked here.
local meadowTreeBlockers: { { Position: Vector2, Radius: number } } = {}

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

	-- The pond and its dirt shore count as water area too, so buildings
	-- stay out of them just like they stay off the river banks.
	if pondCenter and (position - pondCenter).Magnitude <= pondBlockRadius then
		return true
	end

	return false
end

function TerrainService.IsTreeArea(x: number, z: number, clearance: number?): boolean
	local position = Vector2.new(x, z)
	local extraClearance = clearance or 0

	for _, blocker in meadowTreeBlockers do
		if (position - blocker.Position).Magnitude <= blocker.Radius + extraClearance then
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
	local seedPhase = SEED * 0.017

	for z = -half, half, CONFIG.RiverSampleStep do
		local noiseValue = math.noise(z * CONFIG.RiverNoiseScale, 1000, SEED)
		local broadMeander = noiseValue * 2 * CONFIG.RiverMeander

		-- The broad noise can occasionally look almost straight over longer
		-- sections. A small seeded bend with an about-5m wavelength keeps the
		-- silhouette moving without overpowering the main river shape.
		local shortBend = math.sin((z / CONFIG.RiverMaxStraightLength) * math.pi + seedPhase)
			* CONFIG.RiverShortBendAmplitude

		riverPathX[math.floor(z / CONFIG.RiverSampleStep)] = math.clamp(
			broadMeander + shortBend,
			-CONFIG.RiverMeander,
			CONFIG.RiverMeander
		)
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

-- How far a point is from the nearest water, measured from the outer edge of
-- the gravel banks (0 or negative = on the bank or in the water).
local function waterClearanceAt(x: number, z: number): number
	local clearance = math.abs(x - TerrainService.GetRiverXAt(z))
		- (CONFIG.RiverHalfWidth + CONFIG.RiverBankWidth)

	local position = Vector2.new(x, z)
	for _, point in streamPoints do
		local streamClearance = (position - point).Magnitude
			- (CONFIG.StreamHalfWidth + CONFIG.StreamBankWidth)
		clearance = math.min(clearance, streamClearance)
	end

	return clearance
end

-- Height of the meadow rise at a point. The base height only depends on the
-- distance to the nearest water (and to the plateau edge), so every meadow
-- compartment between the waterways automatically gets exactly one rise
-- that spreads across all of it: flat strip next to the banks, a gentle
-- smoothstep ramp, then a wide noise wave that rolls the surface up and
-- down so the rise reads as natural terrain instead of a plateau. The whole
-- height (including the wave) is scaled by the ramp, so it still runs out
-- to zero before any water. Must run after the water pass, because it needs
-- the river path and stream points.
local function plateauHillHeightAt(x: number, z: number): number
	local clearance = math.min(
		waterClearanceAt(x, z) - CONFIG.PlateauHillFlatMargin,
		-- Also ramp down toward the plateau edge so the rise does not end in
		-- a visible step where the hill ring begins.
		CONFIG.PlateauHalfSize - math.max(math.abs(x), math.abs(z))
	)

	local alpha = math.clamp(clearance / CONFIG.PlateauHillRampDistance, 0, 1)

	-- Smoothstep keeps the slope gentle at both ends. Combined with the low
	-- overall height, placed buildings never end up visibly tilted or floating.
	local ramp = alpha * alpha * (3 - 2 * alpha)

	-- Two noise octaves (each roughly -0.5..0.5) for natural ups and downs.
	local wave = (
		math.noise(x * CONFIG.PlateauHillNoiseScale, z * CONFIG.PlateauHillNoiseScale, SEED + 200)
		+ 0.5 * math.noise(x * CONFIG.PlateauHillNoiseScale * 2, z * CONFIG.PlateauHillNoiseScale * 2, SEED + 300)
	) / 1.5

	return ramp * (CONFIG.PlateauHillBaseHeight + wave * 2 * CONFIG.PlateauHillNoiseAmplitude)
end

local function spawnPlateauHills(terrain: Terrain)
	local columnSize = CONFIG.PlateauHillColumnSize
	local half = CONFIG.PlateauHalfSize

	for x = -half, half - columnSize, columnSize do
		for z = -half, half - columnSize, columnSize do
			local columnX = x + columnSize / 2
			local columnZ = z + columnSize / 2

			local columnHeight = plateauHillHeightAt(columnX, columnZ)
			if columnHeight < 0.5 then
				continue
			end

			-- Hard rule: water must never touch the hills. The clearance ramp
			-- already keeps the height at zero next to the banks; this check
			-- is the final guarantee that no terrain is ever raised over the
			-- river, the streams, or their gravel banks.
			if TerrainService.IsWaterArea(columnX, columnZ) then
				continue
			end

			terrain:FillBlock(
				CFrame.new(columnX, columnHeight / 2, columnZ),
				Vector3.new(columnSize, columnHeight, columnSize),
				Enum.Material.Grass
			)
		end

		-- Yield once per row so the full-plateau pass does not freeze the server.
		task.wait()
	end
end

-- Seeded so FIXED_SEED reproduces the pond position and plants too.
local pondRng = Random.new(SEED + 1)

type Compartment = {
	CenterX: number,
	CenterZ: number,
	CellCount: number,
	Cells: { Vector2 }, -- World-space centers of the coarse grid cells.
}

local compartmentsCache: { Compartment }? = nil

-- Finds the meadow compartments the waterways cut the plateau into, by
-- flood-filling a coarse grid. Cells count as land when they are clear of
-- the water and the gravel banks. Returns them sorted largest-first.
local function getCompartments(): { Compartment }
	if compartmentsCache then
		return compartmentsCache
	end

	local cellSize = 16
	local half = CONFIG.PlateauHalfSize
	local cellsPerAxis = math.floor((half * 2) / cellSize)

	local function cellPosition(ix: number, iz: number): (number, number)
		return -half + (ix - 0.5) * cellSize, -half + (iz - 0.5) * cellSize
	end

	local land: { [string]: boolean } = {}
	for ix = 1, cellsPerAxis do
		for iz = 1, cellsPerAxis do
			local x, z = cellPosition(ix, iz)
			if waterClearanceAt(x, z) > 0 then
				land[`{ix}:{iz}`] = true
			end
		end
	end

	local visited: { [string]: boolean } = {}
	local compartments: { Compartment } = {}

	for startX = 1, cellsPerAxis do
		for startZ = 1, cellsPerAxis do
			local startKey = `{startX}:{startZ}`
			if not land[startKey] or visited[startKey] then
				continue
			end

			visited[startKey] = true
			local queue = { { startX, startZ } }
			local cells: { Vector2 } = {}
			local sumX, sumZ = 0, 0

			while #queue > 0 do
				local cell = table.remove(queue)
				local x, z = cellPosition(cell[1], cell[2])
				table.insert(cells, Vector2.new(x, z))
				sumX += x
				sumZ += z

				for _, offset in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
					local nx = cell[1] + offset[1]
					local nz = cell[2] + offset[2]
					local neighborKey = `{nx}:{nz}`

					if
						nx >= 1
						and nx <= cellsPerAxis
						and nz >= 1
						and nz <= cellsPerAxis
						and land[neighborKey]
						and not visited[neighborKey]
					then
						visited[neighborKey] = true
						table.insert(queue, { nx, nz })
					end
				end
			end

			table.insert(compartments, {
				CenterX = sumX / #cells,
				CenterZ = sumZ / #cells,
				CellCount = #cells,
				Cells = cells,
			})
		end
	end

	table.sort(compartments, function(a, b)
		return a.CellCount > b.CellCount
	end)

	compartmentsCache = compartments
	return compartments
end

-- Irregular patch of brown soil (~30 cm radius; 1 stud = 28 cm) under a
-- pond plant. Random size and offset per patch plus the 4-stud voxel
-- blending keep the patches from looking stamped. Note: terrain voxels are
-- 4 studs, so this is the smallest patch the engine can paint.
local function paintSoilPatch(terrain: Terrain, position: Vector3)
	local radius = CONFIG.PondSoilPatchRadius * pondRng:NextNumber(0.7, 1.3)
	local offsetX = pondRng:NextNumber(-0.4, 0.4)
	local offsetZ = pondRng:NextNumber(-0.4, 0.4)

	local region = Region3.new(
		Vector3.new(position.X + offsetX - radius, position.Y - 6, position.Z + offsetZ - radius),
		Vector3.new(position.X + offsetX + radius, position.Y + 4, position.Z + offsetZ + radius)
	):ExpandToGrid(4)

	terrain:ReplaceMaterial(region, 4, Enum.Material.Grass, Enum.Material.Ground)
	terrain:ReplaceMaterial(region, 4, Enum.Material.LeafyGrass, Enum.Material.Ground)
end

-- Stylized cattail, the typical plant next to a pond: a few thin green
-- stalks, each with a brown seed head on top. Random stalk heights and
-- counts on top of the caller-provided scale make every plant different.
local function createPondPlant(position: Vector3, scale: number): Model
	local plant = Instance.new("Model")
	plant.Name = "PondPlant"

	local stalkCount = pondRng:NextInteger(2, 4)
	for _ = 1, stalkCount do
		local stalkHeight = pondRng:NextNumber(1.4, 2.4) * scale
		local angle = pondRng:NextNumber(0, math.pi * 2)
		local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * pondRng:NextNumber(0, 0.6) * scale

		local stalk = Instance.new("Part")
		stalk.Name = "Stalk"
		stalk.Anchored = true
		stalk.CanCollide = false
		stalk.Material = Enum.Material.SmoothPlastic
		stalk.Color = Color3.fromRGB(88, 128, 58)
		stalk.Size = Vector3.new(0.08 * scale, stalkHeight, 0.08 * scale)
		stalk.CFrame = CFrame.new(position + offset + Vector3.new(0, stalkHeight / 2, 0))
			* CFrame.Angles(math.rad(pondRng:NextNumber(-7, 7)), angle, math.rad(pondRng:NextNumber(-7, 7)))
		stalk.Parent = plant

		local head = Instance.new("Part")
		head.Name = "Head"
		head.Shape = Enum.PartType.Cylinder
		head.Anchored = true
		head.CanCollide = false
		head.Material = Enum.Material.SmoothPlastic
		head.Color = Color3.fromRGB(96, 64, 40)
		head.Size = Vector3.new(0.55, 0.16, 0.16) * scale
		-- Cylinders point along X; tip it upright on top of the stalk.
		head.CFrame = CFrame.new(position + offset + Vector3.new(0, stalkHeight + 0.2 * scale, 0))
			* CFrame.Angles(0, 0, math.rad(90))
		head.Parent = plant
	end

	return plant
end

-- Digs a small pond into the largest meadow compartment, a bit off its
-- center. The shore is a dirt ring (Ground -- no grass, no gravel) that is
-- half as wide as the grass-free gravel band of the streams, with cattails
-- growing on it.
local function spawnPond(terrain: Terrain, mapFolder: Folder)
	local dirtBandWidth = CONFIG.StreamBankWidth / 2
	local totalRadius = CONFIG.PondRadius + dirtBandWidth

	local largestCompartment = getCompartments()[1]
	if not largestCompartment then
		warn("[TerrainService] No meadow compartment found, skipping pond")
		return
	end
	local centerX, centerZ = largestCompartment.CenterX, largestCompartment.CenterZ

	-- Push the pond off the compartment center, keeping it clear of the
	-- waterways and inside the plateau. Falls back to the center itself.
	local pondX, pondZ = centerX, centerZ
	for _ = 1, 20 do
		local angle = pondRng:NextNumber(0, math.pi * 2)
		local distance = pondRng:NextNumber(CONFIG.PondCenterOffsetMin, CONFIG.PondCenterOffsetMax)
		local x = centerX + math.cos(angle) * distance
		local z = centerZ + math.sin(angle) * distance

		if
			waterClearanceAt(x, z) >= totalRadius + 8
			and math.max(math.abs(x), math.abs(z)) < CONFIG.PlateauHalfSize - totalRadius
		then
			pondX, pondZ = x, z
			break
		end
	end

	local columnSize = 4

	-- The water surface must be level, so it is based on the lowest ground
	-- inside the pond basin.
	local minSurface = math.huge
	for x = pondX - CONFIG.PondRadius, pondX + CONFIG.PondRadius, columnSize do
		for z = pondZ - CONFIG.PondRadius, pondZ + CONFIG.PondRadius, columnSize do
			if math.sqrt((x - pondX) ^ 2 + (z - pondZ) ^ 2) <= CONFIG.PondRadius then
				minSurface = math.min(minSurface, plateauHillHeightAt(x, z))
			end
		end
	end

	local waterLevel = minSurface - CONFIG.PondWaterLevelBelowGround
	local bedY = minSurface - CONFIG.PondDepth

	-- Pass 1: turn the whole pond area (basin + shore ring) into dirt.
	for x = pondX - totalRadius, pondX + totalRadius, columnSize do
		for z = pondZ - totalRadius, pondZ + totalRadius, columnSize do
			local distance = math.sqrt((x - pondX) ^ 2 + (z - pondZ) ^ 2)
			if distance > totalRadius then
				continue
			end

			local surface = plateauHillHeightAt(x, z)
			terrain:FillBlock(
				CFrame.new(x, (surface + bedY - 2) / 2, z),
				Vector3.new(columnSize, surface - (bedY - 2), columnSize),
				Enum.Material.Ground
			)

			-- Voxel blending leaves grass on the surface; force it to dirt
			-- (and never gravel) within this column only, so the dirt shore
			-- stays round instead of becoming a square patch.
			local region = Region3.new(
				Vector3.new(x - columnSize / 2, bedY - 4, z - columnSize / 2),
				Vector3.new(x + columnSize / 2, surface + 4, z + columnSize / 2)
			):ExpandToGrid(4)
			terrain:ReplaceMaterial(region, 4, Enum.Material.Grass, Enum.Material.Ground)
			terrain:ReplaceMaterial(region, 4, Enum.Material.LeafyGrass, Enum.Material.Ground)
			terrain:ReplaceMaterial(region, 4, Enum.Material.Slate, Enum.Material.Ground)
		end
	end

	task.wait()

	-- Pass 2: carve the basin and fill it with still water.
	for x = pondX - CONFIG.PondRadius, pondX + CONFIG.PondRadius, columnSize do
		for z = pondZ - CONFIG.PondRadius, pondZ + CONFIG.PondRadius, columnSize do
			local distance = math.sqrt((x - pondX) ^ 2 + (z - pondZ) ^ 2)
			if distance > CONFIG.PondRadius then
				continue
			end

			local surface = plateauHillHeightAt(x, z)
			terrain:FillBlock(
				CFrame.new(x, (surface + 4 + bedY) / 2, z),
				Vector3.new(columnSize, (surface + 4) - bedY, columnSize),
				Enum.Material.Air
			)
			terrain:FillBlock(
				CFrame.new(x, (waterLevel + bedY) / 2, z),
				Vector3.new(columnSize, waterLevel - bedY, columnSize),
				Enum.Material.Water
			)
		end
	end

	-- Block building on the pond and its shore from now on.
	pondCenter = Vector2.new(pondX, pondZ)
	pondBlockRadius = totalRadius

	-- Cattails on the dirt shore ring.
	local pondFolder = Instance.new("Folder")
	pondFolder.Name = "Pond"
	pondFolder.Parent = mapFolder

	-- Plants spread irregularly around the pond: the maximum reach varies by
	-- direction (noise), so the belt is no perfect circle. They get rarer
	-- and smaller with distance, and every plant sits on its own irregular
	-- patch of brown soil.
	local plantCount = pondRng:NextInteger(CONFIG.PondPlantCountMin, CONFIG.PondPlantCountMax)
	for plantIndex = 1, plantCount do
		local angle = pondRng:NextNumber(0, math.pi * 2)

		local reachNoise = math.noise(math.cos(angle) * 1.7, math.sin(angle) * 1.7, SEED + 400) + 0.5
		local maxReach = CONFIG.PondPlantSpreadMin
			+ (CONFIG.PondPlantSpreadMax - CONFIG.PondPlantSpreadMin) * math.clamp(reachNoise, 0, 1)

		-- Bias toward the shore: dense belt at the water, thinning outward.
		local normalizedDistance = pondRng:NextNumber() ^ 1.6
		local distance = CONFIG.PondRadius + 0.8 + normalizedDistance * maxReach

		local x = pondX + math.cos(angle) * distance
		local z = pondZ + math.sin(angle) * distance

		-- Keep plants off the waterways and inside the plateau.
		if waterClearanceAt(x, z) < 1 or math.max(math.abs(x), math.abs(z)) > CONFIG.PlateauHalfSize - 4 then
			continue
		end

		local sizeFactor = 1 - CONFIG.PondPlantShrinkWithDistance * normalizedDistance
		local scale = pondRng:NextNumber(CONFIG.PondPlantScaleMin, CONFIG.PondPlantScaleMax) * sizeFactor

		-- The shortest possible stalk is 1.4 studs * scale; plants that
		-- would end up below the minimum height do not spawn at all.
		if 1.4 * scale < CONFIG.PondPlantMinHeight then
			continue
		end

		local position = Vector3.new(x, plateauHillHeightAt(x, z), z)

		paintSoilPatch(terrain, position)
		createPondPlant(position, scale).Parent = pondFolder

		if plantIndex % 25 == 0 then
			task.wait()
		end
	end

	logStep(`Pond at {math.floor(pondX)}, {math.floor(pondZ)} (largest compartment center {math.floor(centerX)}, {math.floor(centerZ)})`)
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

local function getTreeFootprintRadius(tree: Instance): number
	if tree:IsA("Model") then
		local _, boundsSize = tree:GetBoundingBox()
		return math.max(boundsSize.X, boundsSize.Z) / 2
	elseif tree:IsA("BasePart") then
		return math.max(tree.Size.X, tree.Size.Z) / 2
	end

	return 0
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
		blade.Size = Vector3.new(0.015, rng:NextNumber(0.13, 0.25), 0.015)

		local angle = rng:NextNumber(0, math.pi * 2)
		local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * rng:NextNumber(0, 0.047)
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

-- Covers one smaller meadow compartment (the second largest) completely
-- with a loose forest: roughly one tree per 16x16 cell, jittered, so it
-- reads as a forest without being dense. Uses the unseeded forest RNG, so
-- the trees vary every server start like the hill-ring forests.
local function spawnMeadowForest(forestsFolder: Folder)
	local compartment = getCompartments()[2]
	if not compartment then
		warn("[TerrainService] No smaller meadow compartment found, skipping meadow forest")
		return
	end

	local treesPlaced = 0
	for _, cell in compartment.Cells do
		if rng:NextNumber() > CONFIG.MeadowForestTreeChance then
			continue
		end

		local x = cell.X + rng:NextNumber(-6, 6)
		local z = cell.Y + rng:NextNumber(-6, 6)

		if waterClearanceAt(x, z) < CONFIG.MeadowForestWaterClearance then
			continue
		end

		-- Keep the forest off the pond and its dirt shore.
		if pondCenter and (Vector2.new(x, z) - pondCenter).Magnitude < pondBlockRadius + CONFIG.MeadowForestWaterClearance then
			continue
		end

		local tree = createTree(Vector3.new(x, plateauHillHeightAt(x, z), z))
		tree.Parent = forestsFolder
		table.insert(meadowTreeBlockers, {
			Position = Vector2.new(x, z),
			Radius = getTreeFootprintRadius(tree) + 2,
		})
		treesPlaced += 1

		if treesPlaced % 10 == 0 then
			task.wait()
		end
	end

	logStep(`Meadow forest with {treesPlaced} trees at {math.floor(compartment.CenterX)}, {math.floor(compartment.CenterZ)}`)
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
	table.clear(meadowTreeBlockers)
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

	runGenerationStep("plateau hills", function()
		spawnPlateauHills(terrain)
	end)

	runGenerationStep("pond", function()
		spawnPond(terrain, mapFolder)
	end)

	local forestsFolder = Instance.new("Folder")
	forestsFolder.Name = "Forests"
	forestsFolder.Parent = mapFolder

	runGenerationStep("forests", function()
		spawnForests(forestsFolder)
	end)

	runGenerationStep("meadow forest", function()
		spawnMeadowForest(forestsFolder)
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
