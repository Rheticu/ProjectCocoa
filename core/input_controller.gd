class_name InputController
extends Node

@onready var game_manager = $"../GameManager"
@onready var action_system = $"../ActionSystem"
@onready var selection_system = $"../SelectionSystem"
@onready var turn_manager = $"../TurnManager"
@onready var grid_system = $"../GridSystem"
@onready var ui_layer = $"../UILayer"

enum Mode { 
	IDLE,
	UNIT_SELECTED,
	ACTION_MENU,
	TARGETING,
	INSPECTING_A,
	INSPECTING_B,
}

var mode: Mode = Mode.IDLE
var _pending_ability: String = ""
var _pending_move_path: Array[Vector2i] = []
var _locked: bool = false

func lock() -> void:   _locked = true
func unlock() -> void: _locked = false

func _unhandled_input(event: InputEvent) -> void:
	if _locked:
		return
	if game_manager.local_player_id == 0:
		return

	# Si el action menu está abierto, solo permitir cancelar con RMClick
	if ui_layer.action_menu.visible:
		if event.is_action_pressed("RMClick"):
			on_cancel_from_menu()
			ui_layer.hide_action_menu()
		return

	# Inspección funciona siempre, sin importar el turno
	if event.is_action_pressed("LMClick"):
		_handle_left_click()
		return
	if event.is_action_pressed("RMClick"):
		_handle_right_click()
		return

	# Lo demás solo funciona en tu turno
	if not turn_manager.is_my_turn(game_manager.local_player_id):
		return

	if event.is_action_pressed("ui_cancel"):
		_cancel()
	if event.is_action_pressed("toggle_shade_view"):
		game_manager.toggle_shade_view()
		selection_system.deselect()
		mode = Mode.IDLE
	if event.is_action_pressed("end_turn"):
		action_system.queue_action(EndTurnAction.new(game_manager.local_player_id))

func _handle_left_click() -> void:
	var mouse_pos = get_viewport().get_mouse_position()
	var grid_pos = grid_system.world_to_grid(mouse_pos)

	match mode:
		Mode.IDLE:
			var unit = game_manager.get_unit_at(grid_pos)
			if unit and unit.visible:
				# Es mi unidad, mi turno, sin acción → selección interactiva
				if unit.team == game_manager.local_player_id and turn_manager.is_my_turn(unit.team) and unit.state != Unit.State.MOVED:
					selection_system.select_unit(unit)
					mode = Mode.UNIT_SELECTED
				else:
					# Cualquier otro caso → inspección
					selection_system.inspect_unit_move(unit)
					mode = Mode.INSPECTING_A

		Mode.UNIT_SELECTED:
			var unit = selection_system.selected_unit
			if not unit:
				mode = Mode.IDLE
				return
			if grid_pos in selection_system.reachable_cells:
				_pending_move_path = selection_system.get_movement_path_to(grid_pos)
				if not _pending_move_path.is_empty():
					action_system.queue_action(MoveAction.new(unit, _pending_move_path))
				return
			var clicked_unit = game_manager.get_unit_at(grid_pos)
			if not clicked_unit:
				_cancel()

		Mode.INSPECTING_A:
			# Click izquierdo mientras inspecciona → limpiar y volver a IDLE
			_cancel()

		Mode.INSPECTING_B:
			_cancel()

		Mode.TARGETING:
			var target = game_manager.get_unit_at(grid_pos)
			if target and target in selection_system.attack_targets:
				var unit = selection_system.selected_unit
				var path = _pending_move_path.duplicate()
				_pending_move_path.clear()
				if _pending_ability.is_empty():
					action_system.queue_action(AttackAction.new(unit, target, path))
				else:
					var shade = unit as Shade
					if shade:
						action_system.queue_action(AbilityAction.new(shade, _pending_ability, target, path))
					_pending_ability = ""
				mode = Mode.IDLE
				selection_system.deselect()

func clear_pending_path() -> void:
	_pending_move_path.clear()

func _handle_right_click() -> void:
	var mouse_pos = get_viewport().get_mouse_position()
	var grid_pos = grid_system.world_to_grid(mouse_pos)

	match mode:
		Mode.IDLE:
			var unit = game_manager.get_unit_at(grid_pos)
			if unit and unit.visible:
				selection_system.inspect_unit_attack(unit)
				mode = Mode.INSPECTING_B

		Mode.INSPECTING_A:
			# Click derecho mientras hay move range → solo limpiar
			selection_system.clear_inspection()
			mode = Mode.IDLE

		Mode.INSPECTING_B:
			# Click derecho mientras hay attack range → limpiar
			selection_system.clear_inspection()
			ui_layer._clear_target_highlights()
			mode = Mode.IDLE

		Mode.TARGETING:
			selection_system.attack_targets.clear()
			ui_layer._clear_target_highlights()
			ui_layer.attack_range_overlay.clear()
			mode = Mode.ACTION_MENU
			ui_layer.show_action_menu(selection_system.selected_unit)

		_:
			_cancel()

func _cancel() -> void:
	selection_system.deselect()
	_pending_move_path.clear()
	ui_layer.attack_range_overlay.clear()
	mode = Mode.IDLE

# Llamados desde el ActionMenu
func on_attack_pressed() -> void:
	if selection_system.selected_unit:
		selection_system.show_attack_options(selection_system.selected_unit)
		mode = Mode.TARGETING

func on_ability_pressed(ability: String) -> void:
	var shade = selection_system.selected_unit as Shade
	if shade:
		selection_system.show_ability_options(shade, ability)
		_pending_ability = ability
		mode = Mode.TARGETING

func on_move_confirmed() -> void:
	var unit = selection_system.selected_unit
	if unit:
		unit.original_position = unit.grid_position
		unit.state = Unit.State.MOVED
		unit.update_visual()
	selection_system.deselect()
	_pending_move_path.clear()
	mode = Mode.IDLE

func on_capture_pressed(building: Building) -> void:
	if selection_system.selected_unit:
		action_system.queue_action(CaptureAction.new(selection_system.selected_unit, building))
		mode = Mode.IDLE

func on_produce_requested(building: Building, unit_type: String) -> void:
	var cost = building.production_costs.get(unit_type, 0) if building.has_method("get") else 0
	action_system.queue_action(ProduceAction.new(building, unit_type, cost, game_manager.local_player_id))

func on_cancel_from_menu() -> void:
	var unit = selection_system.selected_unit
	if unit:
		unit.grid_position = unit.original_position
		unit.state = Unit.State.IDLE
		unit.update_visual()
	selection_system.deselect()
	_pending_move_path.clear()
	mode = Mode.IDLE
