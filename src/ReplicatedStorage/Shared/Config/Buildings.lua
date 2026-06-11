--[[
	Building configuration shared by client and server.

	The client can read this to show names, prices, or previews.
	The server must still validate everything before placing a building.
]]

local Buildings = {
	House = {
		DisplayName = "House",
		Cost = 100,
		Size = Vector2.new(2, 2), -- Grid cells used by this building.
	},

	Shop = {
		DisplayName = "Shop",
		Cost = 250,
		Size = Vector2.new(3, 2),
	},
}

return Buildings
