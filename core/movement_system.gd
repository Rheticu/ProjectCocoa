class_name MovementSystem
extends Node

const DIRS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

# Tabla de costos de movimiento: se crea una sola vez, no en cada llamada
const MOVE_COSTS: Dictionary = {
		"Sword":  {"PLAINS":1,"MOUNTAIN":3,"ROAD":1,"WALL":99,"RIVER":2,"FOREST":2,"OCEAN":99,"BUILDING":1},
		"Archer": {"PLAINS":1,"MOUNTAIN":3,"ROAD":1,"WALL":99,"RIVER":2,"FOREST":2,"OCEAN":99,"BUILDING":1},
		"Spear":  {"PLAINS":1,"MOUNTAIN":3,"ROAD":1,"WALL":99,"RIVER":2,"FOREST":2,"OCEAN":99,"BUILDING":1},
		"Cannon": {"PLAINS":2,"MOUNTAIN":99,"ROAD":1,"WALL":99,"RIVER":99,"FOREST":3,"OCEAN":99,"BUILDING":1},
		"Transport":  {"PLAINS":1,"MOUNTAIN":3,"ROAD":1,"WALL":99,"RIVER":2,"FOREST":2,"OCEAN":99,"BUILDING":1},
		"Junker": {"PLAINS":99,"MOUNTAIN":99,"ROAD":99,"WALL":99,"RIVER":99,"FOREST":99,"OCEAN":1,"BUILDING":99},
}

@onready var grid_system = $"../GridSystem"
@onready var game_manager = $"../GameManager"

func get_reachable_cells(unit: Unit) -> Array[Vector2i]:
	var use_wrap = unit.is_shade()
	# visited: pos -> menor costo encontrado (también sirve para no duplicar casillas)
	var visited: Dictionary = { unit.grid_position: 0 }
	var queue: Array[Vector2i] = [unit.grid_position]
	var head := 0  # índice en vez de pop_front(), que es O(n)

	while head < queue.size():
		var current_pos: Vector2i = queue[head]
		head += 1
		var current_cost: int = visited[current_pos]

		for dir in DIRS:
			var next_pos = current_pos + dir
			if use_wrap:
				next_pos = grid_system.wrap_x(next_pos)
			if not grid_system.is_in_bounds(next_pos):
				continue
			if _is_visibly_blocked(next_pos, unit):
				continue

			var terrain = grid_system.get_terrain_type(next_pos)
			var new_cost = current_cost + _get_movement_cost(unit, terrain)

			if new_cost <= unit.movement_range:
				if not visited.has(next_pos) or new_cost < visited[next_pos]:
					visited[next_pos] = new_cost
					queue.append(next_pos)  # se reencola solo si encontró un camino más barato

	var reachable: Array[Vector2i] = []
	reachable.assign(visited.keys())
	return reachable

func get_movement_path(from: Vector2i, to: Vector2i, unit: Unit) -> Array[Vector2i]:
	var use_wrap = unit.is_shade()
	var open: Array = [{ "pos": from, "g": 0, "f": 0, "parent": null }]
	var closed: Dictionary = {}

	while not open.is_empty():
		open.sort_custom(func(a, b): return a.f < b.f)
		var current = open.pop_front()

		if current.pos == to:
			return _reconstruct_path(current)

		closed[current.pos] = true

		for dir in DIRS:
			var next_pos = current.pos + dir
			if use_wrap:
				next_pos = grid_system.wrap_x(next_pos)
			if not grid_system.is_in_bounds(next_pos):
				continue
			if closed.has(next_pos):
				continue
			if _is_visibly_blocked(next_pos, unit):
				continue

			var terrain = grid_system.get_terrain_type(next_pos)
			var step_cost = _get_movement_cost(unit, terrain)
			var g = current.g + step_cost
			var h = grid_system.manhattan_distance(next_pos, to, use_wrap)
			open.append({ "pos": next_pos, "g": g, "f": g + h, "parent": current })

	return []

func _reconstruct_path(node) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var current = node
	while current != null:
		path.push_front(current.pos)
		current = current.parent
	return path

func _is_visibly_blocked(pos: Vector2i, mover: Unit, is_final_tile: bool = false) -> bool:
	for unit in game_manager.all_units:
		if unit.grid_position == pos and unit != mover and unit.visible:
			if unit.is_shade() != mover.is_shade():
				continue
			if unit.team != mover.team:
				return true
			if is_final_tile:
				# Permitir si hay un transport aliado que puede cargar al mover
				if unit is TransportUnit and unit.can_load(mover):
					return false
				return true
	return false

func is_position_free(pos: Vector2i, mover: Unit, final_tile: bool = true) -> bool:
	for unit in game_manager.all_units:
		if unit == mover or not unit.visible:
			continue
		if unit.grid_position == pos and unit.is_shade() == mover.is_shade():
			if unit.team == mover.team:
				if final_tile and unit is TransportUnit and unit.can_load(mover):
					return true
				return not final_tile
			else:
				return false
	return true

func path_is_wrapped(from: Vector2i, to: Vector2i) -> bool:
	return abs(from.x - to.x) > grid_system.map_size.x / 2.0

func _get_movement_cost(unit: Unit, terrain: String) -> int:
	if unit.is_shade():
		return 1
	var unit_costs = MOVE_COSTS.get(unit.get_effective_type(), {})
	return unit_costs.get(terrain, 99)
