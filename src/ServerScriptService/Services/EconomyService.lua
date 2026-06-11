--[[
	Server-side economy service.

	For now this is intentionally simple and only stores temporary session money.
	Later this can load/save player money with DataStore.
]]

local Players = game:GetService("Players")

local EconomyService = {}

local STARTING_MONEY = 1000
local balances: { [Player]: number } = {}

local function getOrCreateMoneyValue(player: Player): IntValue
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end

	local money = leaderstats:FindFirstChild("Money")
	if money and money:IsA("IntValue") then
		return money
	end

	if money then
		money:Destroy()
	end

	local newMoney = Instance.new("IntValue")
	newMoney.Name = "Money"
	newMoney.Parent = leaderstats

	return newMoney
end

local function setBalance(player: Player, amount: number)
	balances[player] = amount
	getOrCreateMoneyValue(player).Value = amount
end

function EconomyService.Init()
	Players.PlayerAdded:Connect(function(player)
		setBalance(player, STARTING_MONEY)
	end)

	Players.PlayerRemoving:Connect(function(player)
		balances[player] = nil
	end)

	for _, player in Players:GetPlayers() do
		setBalance(player, STARTING_MONEY)
	end
end

function EconomyService.GetBalance(player: Player): number
	return balances[player] or 0
end

function EconomyService.CanAfford(player: Player, cost: number): boolean
	return EconomyService.GetBalance(player) >= cost
end

function EconomyService.Spend(player: Player, amount: number): boolean
	if not EconomyService.CanAfford(player, amount) then
		return false
	end

	setBalance(player, EconomyService.GetBalance(player) - amount)
	return true
end

return EconomyService
