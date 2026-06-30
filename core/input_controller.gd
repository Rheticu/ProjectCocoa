class_name InputController
extends Node

@onready var game_manager = $"../GameManager"
@onready var action_system = $"../ActionSystem"
@onready var selection_system = $"../SelectionSystem"
@onready var turn_manager = $"../TurnManager"
@onready var grid_system = $"../GridSystem"
@onready var ui_layer = $"../UILayer"
@onready var fog_system = $"../FogSystem"

enum Mode { 
	IDLE,
	UNIT_SELECTED,
	ACTION_MENU,
	TARGETING,
	SHADE_ABILITY,
	INSPECTING_A,
	INSPECTING_B,
	UNLOAD,
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
	if ui_layer.production_menu.visible:
		if event.is_action_pressed("RMClick") or event.is_action_pressed("LMClick"):
			ui_layer.hide_production_menu()
		return
	if game_manager.local_player_id == 0:
		return

	# Si el action menu está abierto, solo permitir cancelar con RMClick
	if ui_layer.action_menu.visible:
		if event.is_action_pressed("RMClick") or event.is_action_pressed("LMClick"):
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

	if event.is_action_pressed("toggle_shade_view"):
		game_manager.toggle_shade_view()
		if mode != Mode.SHADE_ABILITY:
			selection_system.deselect()
			mode = Mode.IDLE

	# Lo demás solo funciona en tu turno
	if not turn_manager.is_my_turn(game_manager.local_player_id):
		return
	if event.is_action_pressed("ui_cancel"):
		_cancel()
	if event.is_action_pressed("end_turn"):
		action_system.queue_action(EndTurnAction.new(game_manager.local_player_id))

func _handle_left_click() -> void:
	var mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * get_viewport().get_mouse_position()
	var grid_pos = grid_system.world_to_grid(mouse_pos)
	match mode:
		Mode.IDLE:
			var unit = game_manager.get_unit_at(grid_pos, game_manager.shade_view_enabled)
			if unit and unit.visible:
				var can_select = unit.team == game_manager.local_player_id and turn_manager.is_my_turn(unit.team)
				var is_transport_with_cargo = unit is TransportUnit and (unit as TransportUnit).carried_unit != null
				if can_select and (unit.state != Unit.State.MOVED or is_transport_with_cargo):
					selection_system.select_unit(unit)
					mode = Mode.UNIT_SELECTED
				else:
					selection_system.inspect_unit_move(unit)
					mode = Mode.INSPECTING_A
			elif turn_manager.is_my_turn(game_manager.local_player_id):
				var building = game_manager.get_building_at(grid_pos)
				if building and building.team == game_manager.local_player_id and not game_manager.shade_view_enabled and building.can_produce:
					ui_layer.show_production_menu(building)
				else:
					ui_layer.show_empty_tile_menu(grid_pos)

		Mode.UNIT_SELECTED:
			var unit = selection_system.selected_unit
			if not unit:
				mode = Mode.IDLE
				return
			if grid_pos == unit.grid_position:
				ui_layer.show_action_menu(unit)
				return
			if grid_pos in selection_system.reachable_cells:
				_pending_move_path = ui_layer._cursor_path.duplicate()
				if _pending_move_path.is_empty() or _pending_move_path.back() != grid_pos:
					_pending_move_path = selection_system.get_movement_path_to(grid_pos)
				if not _pending_move_path.is_empty():
					action_system.queue_action(MoveAction.new(unit, _pending_move_path))
				return
			var clicked_unit = game_manager.get_unit_at(grid_pos, game_manager.shade_view_enabled)
			if clicked_unit and clicked_unit.visible:
				if clicked_unit.team == game_manager.local_player_id and turn_manager.is_my_turn(clicked_unit.team) and clicked_unit.state != Unit.State.MOVED:
					selection_system.select_unit(clicked_unit)
					mode = Mode.UNIT_SELECTED
				else:
					_cancel()
					selection_system.inspect_unit_move(clicked_unit)
					mode = Mode.INSPECTING_A
			else:
				_cancel()

		Mode.INSPECTING_A:
			# Click izquierdo mientras inspecciona → limpiar y volver a IDLE
			_cancel()

		Mode.INSPECTING_B:
			_cancel()

		Mode.TARGETING:
			if _pending_ability == "VOLLEY":
				var unit = selection_system.selected_unit
				var range_tiles = grid_system.get_tiles_in_range(unit.grid_position, unit.attack_range, false)
				if grid_pos in range_tiles:
					var volley_tiles = ui_layer.get_volley_tiles(grid_pos)
					var targets: Array[Unit] = []
					for pos in volley_tiles:
						var t = game_manager.get_unit_at(pos)
						if t and t.team != unit.team and t.visible:
							targets.append(t)
					if not targets.is_empty():
						var path = _pending_move_path.duplicate()
						_pending_move_path.clear()
						_pending_ability = ""
						action_system.queue_action(SpecialAction.new(unit, "VOLLEY", targets, Vector2i.ZERO, path))
						mode = Mode.IDLE
						selection_system.deselect()
				return
			if _pending_ability == "THRUST":
				var dir = ui_layer.get_thrust_direction_at(grid_pos)
				if dir != Vector2i.ZERO:
					var unit = selection_system.selected_unit
					var targets: Array[Unit] = []
					for i in range(1, 3):
						var t = game_manager.get_unit_at(unit.grid_position + dir * i)
						if t and t.team != unit.team and t.visible:
							targets.append(t)
					if targets.is_empty():
						return
					var path = _pending_move_path.duplicate()
					_pending_move_path.clear()
					_pending_ability = ""
					action_system.queue_action(SpecialAction.new(unit, "THRUST", targets, dir, path))
					mode = Mode.IDLE
					selection_system.deselect()
				return
			if _pending_ability == "BASH":
				var dir = ui_layer.get_bash_direction_at(grid_pos)
				if dir != Vector2i.ZERO:
					var unit = selection_system.selected_unit
					var targets: Array[Unit] = []
					for d in [-1, 0, 1]:
						var pos: Vector2i
						if dir == Vector2i.UP or dir == Vector2i.DOWN:
							pos = unit.grid_position + dir + Vector2i(d, 0)
						else:
							pos = unit.grid_position + dir + Vector2i(0, d)
						var t = game_manager.get_unit_at(pos)
						if t and t.team != unit.team and t.visible:
							targets.append(t)
					if targets.is_empty():
						return
					var path = _pending_move_path.duplicate()
					_pending_move_path.clear()
					_pending_ability = ""
					action_system.queue_action(SpecialAction.new(unit, "BASH", targets, dir, path))
					mode = Mode.IDLE
					selection_system.deselect()
				return
			var is_shade_ability = _pending_ability in ["MARK", "SCORCH", "SHIELD", "MUDDLE", "BOOST"]
			var target = game_manager.get_unit_at(grid_pos, game_manager.shade_view_enabled) if not is_shade_ability else game_manager.get_any_unit_at(grid_pos)
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
			if _pending_ability == "DIVIDE":
				if grid_pos in ui_layer._divide_tiles:
					var drone = selection_system.selected_unit as Drone
					var path = _pending_move_path.duplicate()
					_pending_move_path.clear()
					_pending_ability = ""
					action_system.queue_action(DivideAction.new(drone, grid_pos, path))
					mode = Mode.IDLE
					selection_system.deselect()
				return

		Mode.SHADE_ABILITY:
			var target = game_manager.get_any_unit_at(grid_pos)
			if target and target in selection_system.attack_targets:
				var shade = selection_system.selected_unit as Shade
				if shade:
					var path = _pending_move_path.duplicate()
					_pending_move_path.clear()
					action_system.queue_action(AbilityAction.new(shade, _pending_ability, target, path))
					_pending_ability = ""
				mode = Mode.IDLE
				selection_system.deselect()

		Mode.UNLOAD:
			var transport = selection_system.selected_unit as TransportUnit
			if transport:
				var valid_tiles = selection_system.get_valid_unload_tiles(transport)
				if grid_pos in valid_tiles:
					var action = UnloadAction.new(transport, grid_pos)
					action.move_path = _pending_move_path.duplicate()
					_pending_move_path.clear()
					action_system.queue_action(action)
					selection_system.deselect()
					mode = Mode.IDLE

func _handle_right_click() -> void:
	var mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * get_viewport().get_mouse_position()
	var grid_pos = grid_system.world_to_grid(mouse_pos)

	match mode:
		Mode.IDLE:
			var unit = game_manager.get_unit_at(grid_pos, game_manager.shade_view_enabled)
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
			_pending_ability = ""
			mode = Mode.ACTION_MENU
			ui_layer.show_action_menu(selection_system.selected_unit)

		Mode.SHADE_ABILITY:
			selection_system.attack_targets.clear()
			ui_layer._clear_target_highlights()
			ui_layer.hide_ability_range()
			_pending_ability = ""
			mode = Mode.ACTION_MENU
			if not game_manager.shade_view_enabled:
				game_manager.toggle_shade_view()
			ui_layer.show_action_menu(selection_system.selected_unit)

		Mode.UNLOAD:
			ui_layer.hide_unload_options()
			mode = Mode.ACTION_MENU
			ui_layer.show_action_menu(selection_system.selected_unit)

		_:
			_cancel()

func _cancel() -> void:
	selection_system.deselect()
	_pending_move_path.clear()
	ui_layer.attack_range_overlay.clear()
	mode = Mode.IDLE

func clear_pending_path() -> void:
	_pending_move_path.clear()

# Llamados desde el ActionMenu
func on_attack_pressed() -> void:
	if selection_system.selected_unit:
		ui_layer.move_range_overlay.clear()
		selection_system.show_attack_options(selection_system.selected_unit)
		ui_layer._draw_attack_range(selection_system.selected_unit, true)
		mode = Mode.TARGETING

func on_ability_pressed(ability: String) -> void:
	ui_layer.move_range_overlay.clear()
	_pending_ability = ability

	match ability:
		"THRUST":
			ui_layer.show_thrust_options(selection_system.selected_unit)

		"BASH":
			ui_layer.show_bash_options(selection_system.selected_unit)

		"VOLLEY":
			ui_layer.show_volley_options(selection_system.selected_unit)

		"OVERWATCH":
			action_system.queue_action(
				OverwatchAction.new(selection_system.selected_unit)
			)
			mode = Mode.IDLE
			selection_system.deselect()
			return

		"DIVIDE":
			var drone = selection_system.selected_unit as Drone
			if drone:
				ui_layer.show_divide_options(drone)
			mode = Mode.TARGETING
			return

		_:
			var shade = selection_system.selected_unit as Shade
			if shade:
				selection_system.show_ability_options(shade, ability)
			mode = Mode.SHADE_ABILITY
			return

	mode = Mode.TARGETING

func on_move_confirmed() -> void:
	var unit = selection_system.selected_unit
	if unit:
		var confirmed_path = _pending_move_path.duplicate()
		unit.original_position = unit.grid_position
		unit.state = Unit.State.MOVED
		unit.update_visual()
		action_system.confirm_move(unit, confirmed_path)
	fog_system.recalculate(game_manager.local_player_id)
	selection_system.deselect()
	_pending_move_path.clear()
	mode = Mode.IDLE

func on_capture_pressed(building: Building) -> void:
	if selection_system.selected_unit:
		var path = _pending_move_path.duplicate()
		_pending_move_path.clear()
		action_system.queue_action(CaptureAction.new(selection_system.selected_unit, building, path))
		selection_system.deselect()
		mode = Mode.IDLE

func on_cancel_from_menu() -> void:
	var unit = selection_system.selected_unit
	if unit:
		if unit.state == Unit.State.MOVED:
			selection_system.deselect()
			_pending_move_path.clear()
			mode = Mode.IDLE
			return
		unit.grid_position = unit.original_position
		unit.state = Unit.State.IDLE
		unit.update_visual()
	selection_system.deselect()
	_pending_move_path.clear()
	mode = Mode.IDLE

func on_load_pressed(transport: TransportUnit) -> void:
	var unit = selection_system.selected_unit
	if unit:
		_pending_move_path.clear()
		action_system.queue_action(LoadAction.new(unit, transport))
		selection_system.deselect()
		mode = Mode.IDLE

func on_unload_pressed() -> void:
	var transport = selection_system.selected_unit as TransportUnit
	if transport:
		mode = Mode.UNLOAD
		ui_layer.show_unload_options(transport)
