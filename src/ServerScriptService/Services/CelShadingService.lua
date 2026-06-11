--[[
	Server-side cel-shading service.

	Roblox has no custom shaders, so the cel-shaded look is faked with
	three building blocks:
	1. Flat lighting: environment reflections off, hard-edged shadows.
	2. A ColorCorrectionEffect that boosts saturation and contrast.
	3. Cartoon outlines via Highlight instances. One Highlight on a folder
	   outlines every model inside it and only counts as a single instance
	   toward the engine limit of 31 Highlights.

	NOTE: Lighting.Technology cannot be changed by scripts. Set it to
	"ShadowMap" or "Future" manually in Studio (Lighting properties),
	otherwise the hard shadows will not show up.
]]

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local CelShadingService = {}

local OUTLINE_COLOR = Color3.fromRGB(25, 25, 35)

-- Workspace folders whose contents get a cartoon outline.
-- They may be created later (first placed building, generated map),
-- so the service watches for them instead of requiring them at startup.
local OUTLINED_FOLDERS = {
	PlacedBuildings = true, -- Created by PlacementService.
	GeneratedMap = true, -- Created by TerrainService (feature/terrain-generation).
}

local function applyLightingSettings()
	-- Hard shadow edges are the core of the toon look.
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0

	-- Disable image-based lighting so surfaces are lit flat instead of
	-- picking up realistic sky reflections.
	Lighting.EnvironmentDiffuseScale = 0
	Lighting.EnvironmentSpecularScale = 0

	-- Bright, even daylight.
	Lighting.Brightness = 3
	Lighting.ClockTime = 10
	Lighting.Ambient = Color3.fromRGB(80, 80, 80)
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 140, 140)
end

local function applyColorCorrection()
	local existing = Lighting:FindFirstChild("CelShadingColorCorrection")
	if existing then
		existing:Destroy()
	end

	local colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Name = "CelShadingColorCorrection"
	colorCorrection.Saturation = 0.3
	colorCorrection.Contrast = 0.25
	colorCorrection.Brightness = 0.02
	colorCorrection.Parent = Lighting
end

local function addOutline(target: Instance)
	if target:FindFirstChild("CelShadingOutline") then
		return
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "CelShadingOutline"
	highlight.FillTransparency = 1 -- Outline only, no color overlay.
	highlight.OutlineColor = OUTLINE_COLOR
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = target
end

local function watchWorkspaceFolders()
	local function onChild(child: Instance)
		if OUTLINED_FOLDERS[child.Name] then
			addOutline(child)
		end
	end

	Workspace.ChildAdded:Connect(onChild)

	for _, child in Workspace:GetChildren() do
		onChild(child)
	end
end

function CelShadingService.Init()
	applyLightingSettings()
	applyColorCorrection()
	watchWorkspaceFolders()

	-- TODO: Cel Shading Polish - tune values once real building models exist
	-- (see feature/buildings-pack-01 in the roadmap).

	print("[CelShadingService] Cel shading applied")
end

return CelShadingService
