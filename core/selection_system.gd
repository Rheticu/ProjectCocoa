class_name SelectionSystem
extends Node

@onready var game_manager = $"../GameManager"
@onready var movement_system = $"../MovementSystem"
@onready var combat_system = $"../CombatSystem"
@onready var turn_manager = $"../TurnManager"

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
	if unit.state == Unit.State.MOVED:
		return
	if unit.is_shade() != game_manager.shade_view_enabled:
		return
	deselect()
	selected_unit = unit
	unit.original_position = unit.grid_position
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
	attack_range_shown.emit(unit)

func has_attack_targets(unit: Unit) -> bool:
	for target in game_manager.all_units:
		if target.visible and combat_system.can_attack(unit, target):
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
			"MARK", "SCORCH", "MUDDLE":
				if unit.team != shade.team:
					targets.append(unit)
			"SHIELD", "BOOST":
				if unit.team == shade.team:
					targets.append(unit)
	ability_targets_shown.emit(targets)

func get_movement_path_to(destination: Vector2i) -> Array[Vector2i]:
	if not selected_unit:
		return []
	return movement_system.get_movement_path(selected_unit.grid_position, destination, selected_unit)
