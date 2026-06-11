--[[
	Grid helpers shared by client and server.

	The client may use these functions for previews later.
	The server must still run the final validation before placing anything.
]]

local Grid = {}

Grid.TileSize = 4
Grid.CellSize = Grid.TileSize -- Older code may still read CellSize.

Grid.MinX = -50
Grid.MaxX = 50
Grid.MinY = -50
Grid.MaxY = 50

function Grid.getFootprintSize(size: Vector2, rotation: number?): Vector2
	local normalizedRotation = rotation or 0

	if normalizedRotation == 90 or normalizedRotation == 270 then
		return Vector2.new(size.Y, size.X)
	end

	return size
end

function Grid.worldToGrid(position: Vector3): Vector2
	return Vector2.new(
		math.floor(position.X / Grid.TileSize + 0.5),
		math.floor(position.Z / Grid.TileSize + 0.5)
	)
end

function Grid.gridToWorld(gridPosition: Vector2, y: number?): Vector3
	return Vector3.new(
		gridPosition.X * Grid.TileSize,
		y or 0,
		gridPosition.Y * Grid.TileSize
	)
end

function Grid.snapToGrid(position: Vector3): Vector3
	local gridPosition = Grid.worldToGrid(position)
	return Grid.gridToWorld(gridPosition, position.Y)
end

function Grid.getOccupiedCells(origin: Vector2, size: Vector2, rotation: number?): { Vector2 }
	local cells = {}
	local footprintSize = Grid.getFootprintSize(size, rotation)

	for x = 0, footprintSize.X - 1 do
		for y = 0, footprintSize.Y - 1 do
			table.insert(cells, Vector2.new(origin.X + x, origin.Y + y))
		end
	end

	return cells
end

function Grid.isInsideBounds(cell: Vector2): boolean
	return cell.X >= Grid.MinX
		and cell.X <= Grid.MaxX
		and cell.Y >= Grid.MinY
		and cell.Y <= Grid.MaxY
end

function Grid.areCellsInsideBounds(cells: { Vector2 }): boolean
	for _, cell in cells do
		if not Grid.isInsideBounds(cell) then
			return false
		end
	end

	return true
end

function Grid.cellKey(cell: Vector2): string
	return `{math.floor(cell.X)}:{math.floor(cell.Y)}`
end

-- Backwards-compatible aliases while the project is still small.
Grid.WorldToCell = Grid.worldToGrid
Grid.CellToWorld = Grid.gridToWorld
Grid.SnapWorldPosition = Grid.snapToGrid

return Grid
