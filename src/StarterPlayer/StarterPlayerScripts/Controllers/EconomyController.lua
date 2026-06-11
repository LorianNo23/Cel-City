--[[
	Simple client-side money HUD.

	The server owns the real money value through leaderstats.
	This controller only displays that value and shows a small red popup when
	money decreases after placing a building.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local EconomyController = {}

local localPlayer = Players.LocalPlayer

local moneyLabel: TextLabel
local popupLayer: Frame
local lastMoneyValue: number?

local MONEY_LABEL_SIZE = UDim2.fromOffset(180, 42)
local MONEY_LABEL_POSITION = UDim2.new(1, -24, 0, 24)

local function createMoneyGui(): TextLabel
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "EconomyGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.Name = "MoneyLabel"
	label.AnchorPoint = Vector2.new(1, 0)
	label.Position = MONEY_LABEL_POSITION
	label.Size = MONEY_LABEL_SIZE
	label.BackgroundColor3 = Color3.fromRGB(32, 34, 38)
	label.BackgroundTransparency = 0.08
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.Text = "Money: 0"
	label.TextColor3 = Color3.fromRGB(245, 245, 245)
	label.TextSize = 22
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.82
	stroke.Thickness = 1
	stroke.Parent = label

	popupLayer = Instance.new("Frame")
	popupLayer.Name = "MoneyPopupLayer"
	popupLayer.AnchorPoint = Vector2.new(1, 0)
	popupLayer.Position = UDim2.new(1, -24, 0, 70)
	popupLayer.Size = UDim2.fromOffset(180, 80)
	popupLayer.BackgroundTransparency = 1
	popupLayer.Parent = screenGui

	return label
end

local function getMoneyValue(): IntValue
	local leaderstats = localPlayer:WaitForChild("leaderstats")
	return leaderstats:WaitForChild("Money") :: IntValue
end

local function formatMoney(amount: number): string
	return `Money: {amount}`
end

local function showSpendPopup(amountSpent: number)
	local popup = Instance.new("TextLabel")
	popup.Name = "MoneySpentPopup"
	popup.AnchorPoint = Vector2.new(1, 0)
	popup.Position = UDim2.new(1, 0, 0, 0)
	popup.Size = UDim2.fromOffset(180, 28)
	popup.BackgroundTransparency = 1
	popup.Font = Enum.Font.GothamBold
	popup.Text = `-${amountSpent}`
	popup.TextColor3 = Color3.fromRGB(230, 72, 72)
	popup.TextSize = 20
	popup.TextXAlignment = Enum.TextXAlignment.Right
	popup.TextYAlignment = Enum.TextYAlignment.Center
	popup.Parent = popupLayer

	local tween = TweenService:Create(
		popup,
		TweenInfo.new(0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Position = UDim2.new(1, 0, 0, 32),
			TextTransparency = 1,
		}
	)

	tween.Completed:Connect(function()
		popup:Destroy()
	end)

	tween:Play()
end

local function updateMoneyDisplay(newValue: number)
	moneyLabel.Text = formatMoney(newValue)

	if lastMoneyValue and newValue < lastMoneyValue then
		showSpendPopup(lastMoneyValue - newValue)
	end

	lastMoneyValue = newValue
end

function EconomyController.Init()
	moneyLabel = createMoneyGui()

	local moneyValue = getMoneyValue()
	updateMoneyDisplay(moneyValue.Value)

	moneyValue:GetPropertyChangedSignal("Value"):Connect(function()
		updateMoneyDisplay(moneyValue.Value)
	end)
end

return EconomyController
