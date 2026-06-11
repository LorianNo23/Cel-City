--[[
	Simple grid helpers used by placement code.

	Keep shared utility modules pure when possible:
	they should calculate values, not change the game world.
]]

local Grid = {}

Grid.CellSize = 4

function Grid.WorldToCell(position: Vector3): Vector2
	return Vector2.new(
		math.floor(position.X / Grid.CellSize + 0.5),
		math.floor(position.Z / Grid.CellSize + 0.5)
	)
end

function Grid.CellToWorld(cell: Vector2): Vector3
	return Vector3.new(cell.X * Grid.CellSize, 0, cell.Y * Grid.CellSize)
end

function Grid.SnapWorldPosition(position: Vector3): Vector3
	local cell = Grid.WorldToCell(position)
	return Grid.CellToWorld(cell)
end

return Grid
