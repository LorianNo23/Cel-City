--[[
	Simple grid helpers used by placement code.

	Keep shared utility modules pure when possible:
	they should calculate values, not change the game world.
]]

local Grid = {}

Grid.CellSize = 4

function Grid.worldToGrid(position: Vector3): Vector2
	return Vector2.new(
		math.floor(position.X / Grid.CellSize + 0.5),
		math.floor(position.Z / Grid.CellSize + 0.5)
	)
end

function Grid.gridToWorld(gridPosition: Vector2): Vector3
	return Vector3.new(gridPosition.X * Grid.CellSize, 0, gridPosition.Y * Grid.CellSize)
end

function Grid.snapToGrid(position: Vector3): Vector3
	local gridPosition = Grid.worldToGrid(position)
	return Grid.gridToWorld(gridPosition)
end

function Grid.getOccupiedCells(origin: Vector2, size: Vector2): { Vector2 }
	local cells = {}

	for x = 0, size.X - 1 do
		for y = 0, size.Y - 1 do
			table.insert(cells, Vector2.new(origin.X + x, origin.Y + y))
		end
	end

	return cells
end

-- Backwards-compatible aliases while the project is still small.
Grid.WorldToCell = Grid.worldToGrid
Grid.CellToWorld = Grid.gridToWorld
Grid.SnapWorldPosition = Grid.snapToGrid

return Grid
