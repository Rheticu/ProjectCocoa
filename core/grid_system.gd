class_name GridSystem
extends Node

const TILE_SIZE: int = 32
var map_size: Vector2i = Vector2i.ZERO
var _terrain: TileMapLayer

func initialize(terrain: TileMapLayer) -> void:
	_terrain = terrain
	map_size = terrain.get_used_rect().size

func world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(floor(world_pos.x / TILE_SIZE), floor(world_pos.y / TILE_SIZE))

func grid_to_world_center(grid_pos: Vector2i) -> Vector2:
	return Vector2(grid_pos) * TILE_SIZE + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)

func is_in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < map_size.x and pos.y >= 0 and pos.y < map_size.y

func wrap_x(pos: Vector2i) -> Vector2i:
	return Vector2i(posmod(pos.x, map_size.x), pos.y)

func get_terrain_type(pos: Vector2i) -> String:
	if not _terrain:
		return "PLAINS"
	var td = _terrain.get_cell_tile_data(pos)
	if td:
		var t = td.get_custom_data("terrain_type")
		if t != "":
			return t
	return "PLAINS"

func manhattan_distance(a: Vector2i, b: Vector2i, use_wrap: bool = false) -> int:
	var dx = abs(a.x - b.x)
	if use_wrap:
		dx = min(dx, map_size.x - dx)
	return dx + abs(a.y - b.y)

func get_tiles_in_range(center: Vector2i, range_val: int, use_wrap: bool = false) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x in range(-range_val, range_val + 1):
		for y in range(-range_val, range_val + 1):
			if abs(x) + abs(y) <= range_val:
				var pos = center + Vector2i(x, y)
				if use_wrap:
					pos = wrap_x(pos)
				if is_in_bounds(pos):
					result.append(pos)
	return result
