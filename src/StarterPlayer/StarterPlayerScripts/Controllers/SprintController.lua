--[[
	Client-side sprint controller.

	Holding Shift doubles the walk speed. Releasing Shift restores the
	normal speed. Sprinting is purely cosmetic movement speed on the
	client; it does not touch any server-side systems.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local SprintController = {}

local localPlayer = Players.LocalPlayer

local SPRINT_MULTIPLIER = 2

local baseWalkSpeed = 16
local isSprinting = false

local function getHumanoid(): Humanoid?
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid
end

local function applySpeed()
	local humanoid = getHumanoid()
	if not humanoid then
		return
	end

	if isSprinting then
		humanoid.WalkSpeed = baseWalkSpeed * SPRINT_MULTIPLIER
	else
		humanoid.WalkSpeed = baseWalkSpeed
	end
end

local function onCharacterAdded(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid

	-- Remember the spawn speed so other systems can change the base
	-- speed later without the sprint overwriting it with a stale value.
	baseWalkSpeed = humanoid.WalkSpeed

	applySpeed()
end

local function isShift(keyCode: Enum.KeyCode): boolean
	return keyCode == Enum.KeyCode.LeftShift or keyCode == Enum.KeyCode.RightShift
end

local function onInputBegan(input: InputObject, gameProcessedEvent: boolean)
	if gameProcessedEvent then
		return
	end

	if isShift(input.KeyCode) then
		isSprinting = true
		applySpeed()
	end
end

local function onInputEnded(input: InputObject, _gameProcessedEvent: boolean)
	if isShift(input.KeyCode) then
		isSprinting = false
		applySpeed()
	end
end

function SprintController.Init()
	localPlayer.CharacterAdded:Connect(onCharacterAdded)

	if localPlayer.Character then
		onCharacterAdded(localPlayer.Character)
	end

	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputEnded:Connect(onInputEnded)

	print("[SprintController] Sprint ready (hold Shift)")
end

return SprintController
