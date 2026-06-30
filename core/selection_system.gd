class_name SelectionSystem
extends Node

@onready var game_manager = $"../GameManager"
@onready var movement_system = $"../MovementSystem"
@onready var combat_system = $"../CombatSystem"
@onready var turn_manager = $"../TurnManager"
@onready var grid_system = $"../GridSystem"
@onready var fog_system = $"../FogSystem"

var selected_unit: Unit = null
var inspected_unit: Unit = null
var reachable_cells: Array[Vector2i] = []
var attack_targets: Array[Unit] = []

signal unit_selected(unit: Unit, reachable: Array[Vector2i])
signal unit_deselected()
signal ability_targets_shown(targets: Array[Unit])
signal attack_range_shown(unit: Unit)

func select_unit(unit: Unit) -> void:
	if not turn_manager.is_my_turn(unit.team):
		return
	var is_transport_with_cargo = unit is TransportUnit and (unit as TransportUnit).carried_unit != null
	if unit.state == Unit.State.MOVED and not is_transport_with_cargo:
		return
	if unit.is_shade() != game_manager.shade_view_enabled:
		return
	deselect()
	selected_unit = unit
	unit.original_position = unit.grid_position
	if unit.state != Unit.State.MOVED:
		unit.state = Unit.State.SELECTED
		unit.update_visual()
	reachable_cells = movement_system.get_reachable_cells(unit)
	unit_selected.emit(unit, reachable_cells)

func deselect() -> void:
	if selected_unit:
		if selected_unit.state == Unit.State.SELECTED:
			selected_unit.state = Unit.State.IDLE
			selected_unit.update_visual()
		selected_unit = null
	reachable_cells.clear()
	attack_targets.clear()
	unit_deselected.emit()

func inspect_unit_move(unit: Unit) -> void:
	clear_inspection()
	inspected_unit = unit
	reachable_cells = movement_system.get_reachable_cells(unit)
	unit_selected.emit(unit, reachable_cells)

func inspect_unit_attack(unit: Unit) -> void:
	clear_inspection()
	inspected_unit = unit
	attack_range_shown.emit(unit)

func clear_inspection() -> void:
	inspected_unit = null
	reachable_cells.clear()
	unit_deselected.emit()

func show_attack_options(unit: Unit) -> void:
	attack_targets.clear()
	for target in game_manager.all_units:
		if target.visible and combat_system.can_attack(unit, target):
			attack_targets.append(target)

func has_attack_targets(unit: Unit) -> bool:
	for target in game_manager.all_units:
		if target.visible and combat_system.can_attack(unit, target):
			return true
	return false

func has_thrust_targets(unit: Unit) -> bool:
	for i in range(1, 3):
		for dir in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var pos = unit.grid_position + dir * i
			for target in game_manager.all_units:
				if target.visible and target.team != unit.team and target.grid_position == pos:
					return true
	return false

func has_bash_targets(unit: Unit) -> bool:
	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		for offset in [-1, 0, 1]:
			var pos: Vector2i
			if dir == Vector2i.UP or dir == Vector2i.DOWN:
				pos = unit.grid_position + dir + Vector2i(offset, 0)
			else:
				pos = unit.grid_position + dir + Vector2i(0, offset)
			for target in game_manager.all_units:
				if target.visible and target.team != unit.team and target.grid_position == pos:
					return true
	return false

func has_volley_targets(unit: Unit) -> bool:
	var reachable = movement_system.get_reachable_cells(unit)
	for center in reachable:
		for dir in [Vector2i.ZERO, Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var pos = center + dir
			for target in game_manager.all_units:
				if target.visible and target.team != unit.team and target.grid_position == pos:
					return true
	return false

func show_ability_options(shade: Shade, ability: String) -> void:
	var targets: Array[Unit] = []
	for unit in game_manager.all_units:
		if not unit.visible:
			continue
		if not combat_system.can_use_ability(shade, unit):
			continue
		match ability:
			"MARK", "SCORCH", "MUDDLE", "MARK2", "MUDDLE2", "SCORCH2":
				if unit.team != shade.team:
					targets.append(unit)
			"SHIELD", "BOOST", "SHIELD2", "BOOST2":
				if unit.team == shade.team:
					targets.append(unit)
	attack_targets = targets
	ability_targets_shown.emit(targets)

func has_ability_targets(shade: Shade, ability: String) -> bool:
	for unit in game_manager.all_units:
		if not unit.visible:
			continue
		if not combat_system.can_use_ability(shade, unit):
			continue
		match ability:
			"MARK", "SCORCH", "MUDDLE":
				if unit.team != shade.team:
					return true
			"SHIELD", "BOOST":
				if unit.team == shade.team:
					return true
	return false

func get_movement_path_to(destination: Vector2i) -> Array[Vector2i]:
	if not selected_unit:
		return []
	return movement_system.get_movement_path(selected_unit.grid_position, destination, selected_unit)

func calculate_path_cost(path: Array[Vector2i], unit: Unit) -> int:
	var total = 0
	for i in range(1, path.size()):
		var terrain = grid_system.get_terrain_type(path[i])
		total += movement_system._get_movement_cost(unit, terrain)
	return total

func get_attackable_tiles(unit: Unit) -> Array[Vector2i]:
	var seen: Dictionary = {}
	var attackable: Array[Vector2i] = []
	var reachable = movement_system.get_reachable_cells(unit)
	for move_pos in reachable:
		var attack_tiles = grid_system.get_tiles_in_range(move_pos, unit.attack_range, unit.is_shade())
		for tile in attack_tiles:
			var key = tile.x * 10000 + tile.y
			if not seen.has(key):
				seen[key] = true
				attackable.append(tile)
	return attackable

func get_valid_unload_tiles(transport: TransportUnit) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var pos = transport.grid_position + dir
		if not grid_system.is_in_bounds(pos):
			continue
		var unit_at = game_manager.get_unit_at(pos, false)
		if unit_at != null and not unit_at.is_shade() and fog_system.is_visible(pos, transport.team):
			continue
		var terrain = grid_system.get_terrain_type(pos)
		var cost = movement_system._get_movement_cost(transport.carried_unit, terrain)
		if cost < 99:
			tiles.append(pos)
	return tiles
