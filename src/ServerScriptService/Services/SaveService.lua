--[[
	Minimal server-side save service scaffold.

	DataStore writes are disabled for now so Studio testing is not blocked by
	publish/API settings. The service still owns the data shape we will persist:
	player money and placed buildings.
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local SaveService = {}

local DATASTORE_ENABLED = false
local DATASTORE_NAME = "CelCityPlayerData_v1"
local playerDataStore = DataStoreService:GetDataStore(DATASTORE_NAME)

local sessionData: {
	[Player]: {
		Money: number,
		Buildings: { any },
	},
} = {}

local function createDefaultData()
	return {
		Money = 1000,
		Buildings = {},
	}
end

local function getDataKey(player: Player): string
	return `player:{player.UserId}`
end

local function sanitizeLoadedData(loadedData)
	local data = createDefaultData()

	if typeof(loadedData) ~= "table" then
		return data
	end

	if typeof(loadedData.Money) == "number" then
		data.Money = loadedData.Money
	end

	if typeof(loadedData.Buildings) == "table" then
		for _, buildingData in loadedData.Buildings do
			if typeof(buildingData) ~= "table" then
				continue
			end

			if typeof(buildingData.BuildingId) ~= "string" then
				continue
			end

			if typeof(buildingData.OriginX) ~= "number"
				or typeof(buildingData.OriginY) ~= "number"
				or typeof(buildingData.Rotation) ~= "number"
			then
				continue
			end

			table.insert(data.Buildings, {
				BuildingId = buildingData.BuildingId,
				OriginX = buildingData.OriginX,
				OriginY = buildingData.OriginY,
				Rotation = buildingData.Rotation,
			})
		end
	end

	return data
end

local function loadPlayerData(player: Player)
	if not DATASTORE_ENABLED then
		return createDefaultData()
	end

	local success, result = pcall(function()
		return playerDataStore:GetAsync(getDataKey(player))
	end)

	if not success then
		warn("[SaveService] Failed to load data for", player.Name, result)
		return createDefaultData()
	end

	if result == nil then
		return createDefaultData()
	end

	return sanitizeLoadedData(result)
end

function SaveService.Init()
	Players.PlayerAdded:Connect(function(player)
		sessionData[player] = loadPlayerData(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		SaveService.SavePlayer(player)
		sessionData[player] = nil
	end)

	for _, player in Players:GetPlayers() do
		sessionData[player] = loadPlayerData(player)
	end

	if not DATASTORE_ENABLED then
		warn("[SaveService] DataStore disabled; using session-only save data")
	end
end

function SaveService.GetPlayerData(player: Player)
	local data = sessionData[player]
	if not data then
		data = createDefaultData()
		sessionData[player] = data
	end

	return data
end

function SaveService.SetMoney(player: Player, amount: number)
	SaveService.GetPlayerData(player).Money = amount
end

function SaveService.AddPlacedBuilding(player: Player, buildingId: string, origin: Vector2, rotation: number)
	local data = SaveService.GetPlayerData(player)

	table.insert(data.Buildings, {
		BuildingId = buildingId,
		OriginX = origin.X,
		OriginY = origin.Y,
		Rotation = rotation,
	})
end

function SaveService.ApplyLoadedData(player: Player, economyService, placementService)
	local data = SaveService.GetPlayerData(player)

	if economyService then
		economyService.SetBalance(player, data.Money)
	end

	if placementService then
		for _, buildingData in data.Buildings do
			placementService.RestoreBuilding(
				buildingData.BuildingId,
				Vector2.new(buildingData.OriginX, buildingData.OriginY),
				buildingData.Rotation
			)
		end
	end
end

function SaveService.SavePlayer(player: Player)
	if not DATASTORE_ENABLED then
		return
	end

	local data = SaveService.GetPlayerData(player)
	local success, err = pcall(function()
		playerDataStore:SetAsync(getDataKey(player), data)
	end)

	if not success then
		warn("[SaveService] Failed to save data for", player.Name, err)
	end
end

function SaveService.ApplyLoadedDataForExistingPlayers(economyService, placementService)
	for _, player in Players:GetPlayers() do
		SaveService.ApplyLoadedData(player, economyService, placementService)
	end
end

return SaveService
