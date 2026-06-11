--[[
	Server-side economy service.

	For now this is intentionally simple and only stores temporary session money.
	Later this can load/save player money with DataStore.
]]

local Players = game:GetService("Players")

local EconomyService = {}

local STARTING_MONEY = 1000
local balances: { [Player]: number } = {}

function EconomyService.Init()
	Players.PlayerAdded:Connect(function(player)
		balances[player] = STARTING_MONEY
	end)

	Players.PlayerRemoving:Connect(function(player)
		balances[player] = nil
	end)

	for _, player in Players:GetPlayers() do
		balances[player] = STARTING_MONEY
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

	balances[player] -= amount
	return true
end

return EconomyService
