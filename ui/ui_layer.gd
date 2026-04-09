class_name UILayer
extends CanvasLayer

# Los overlays viven en el mundo 2D (hermanos de UILayer en Game),
# así que sus rutas suben un nivel con "../"
@onready var move_range_overlay: TileMapLayer  = $"../MoveRangeOverlay"
@onready var attack_range_overlay: TileMapLayer = $"../AttackRangeOverlay"
@onready var cursor_highlight: TileMapLayer    = $"../CursorHighlight"
@onready var movement_arrow: Line2D            = $"../MovementArrow"
var _thrust_overlays: Dictionary = {}
var _current_thrust_direction: Vector2i = Vector2i.ZERO
var _bash_overlays: Dictionary = {}
var _current_bash_direction: Vector2i = Vector2i.ZERO
var _volley_center: Vector2i = Vector2i(-1,-1)
var _cursor_path: Array[Vector2i] = []
var _is_tracing: bool = false

# Sistemas — sin cambios
@onready var game_manager      = $"../GameManager"
@onready var action_system     = $"../ActionSystem"
@onready var selection_system  = $"../SelectionSystem"
@onready var grid_system       = $"../GridSystem"
@onready var turn_manager      = $"../TurnManager"
@onready var input_controller  = $"../InputController"
@onready var fog_system = $"../FogSystem"
@onready var hud = $"../HUD"

var _current_building: Building = null
var _overwatch_activated: bool = false
var _ambush_activated: bool = false
var _current_ability_shade: Shade = null
var _current_ability_is_hostile: bool = true
var _movement_tween: Tween = null

signal _overwatch_resolved

#Hijos del CanvasLayer
@onready var action_menu = $ActionMenu
@onready var production_menu = $ProductionMenu

func _ready() -> void:
	selection_system.unit_selected.connect(_on_unit_selected)
	selection_system.unit_deselected.connect(_on_unit_deselected)
	action_system.move_animation_requested.connect(_on_move_started)
	action_system.action_executed.connect(_on_action_executed)
	selection_system.attack_range_shown.connect(_draw_attack_range)
	action_menu.move_pressed.connect(_on_action_menu_move)
	action_menu.attack_pressed.connect(_on_action_menu_attack)
	action_menu.cancel_pressed.connect(_on_action_menu_cancel)
	action_menu.capture_pressed.connect(_on_action_menu_capture)
	action_menu.ability_pressed.connect(_on_action_menu_ability)
	action_menu.end_turn_pressed.connect(_on_action_menu_end_turn)
	production_menu.unit_selected.connect(_on_unit_produced)
	production_menu.closed.connect(hide_production_menu)
	action_system.overwatch_triggered.connect(_on_overwatch_triggered)
	action_system.ambush_triggered.connect(_on_ambush_triggered)
	game_manager.shade_view_toggled.connect(_on_shade_view_toggled)
	selection_system.ability_targets_shown.connect(_on_ability_targets_shown)

# ── Action Menu ───────────────────────────────────────────────────────────────

func show_action_menu(unit: Unit) -> void:
	var building = game_manager.get_building_at(unit.grid_position)
	var has_targets = selection_system.has_attack_targets(unit)
	if unit.unit_type == "Cannon":
		has_targets = has_targets and unit.grid_position == unit.original_position
	var has_thrust_targets = selection_system.has_thrust_targets(unit)
	var has_bash_targets = selection_system.has_bash_targets(unit)
	var has_volley_targets = selection_system.has_volley_targets(unit)
	var has_overwatch = unit.unit_type == "Cannon" and unit.grid_position == unit.original_position
	var has_mark_targets = false
	var has_scorch_targets = false
	var has_shield_targets = false
	var has_muddle_targets = false
	var has_boost_targets = false
	if unit.is_shade():
		var shade = unit as Shade
		if shade.mana >= 2:
			has_mark_targets = selection_system.has_ability_targets(shade, "MARK")
			has_scorch_targets = selection_system.has_ability_targets(shade, "SCORCH")
			has_shield_targets = selection_system.has_ability_targets(shade, "SHIELD")
			has_muddle_targets = selection_system.has_ability_targets(shade, "MUDDLE")
			has_boost_targets = selection_system.has_ability_targets(shade, "BOOST")
	action_menu.show_for_unit(
		unit, building, has_targets, has_thrust_targets, has_bash_targets,
		has_volley_targets, has_overwatch, has_mark_targets, has_scorch_targets,
		has_shield_targets, has_muddle_targets, has_boost_targets
	)
	var screen_pos = get_viewport().get_canvas_transform() * unit.global_position
	action_menu.position = screen_pos + Vector2(20, -20)
	action_menu.visible = true

func hide_action_menu() -> void:
	action_menu.visible = false

func _on_action_menu_move() -> void:
	hide_action_menu()
	input_controller.on_move_confirmed()

func _on_action_menu_attack() -> void:
	hide_action_menu()
	input_controller.on_attack_pressed()

func _on_action_menu_cancel() -> void:
	hide_action_menu()
	input_controller.on_cancel_from_menu()

func _on_action_menu_capture() -> void:
	hide_action_menu()
	var building = game_manager.get_building_at(selection_system.selected_unit.grid_position)
	input_controller.on_capture_pressed(building)

func _on_action_menu_ability(ability: String) -> void:
	hide_action_menu()
	input_controller.on_ability_pressed(ability)

func _on_ability_targets_shown(targets: Array[Unit]) -> void:
	move_range_overlay.clear()
	selection_system.attack_targets = targets
	var shade = selection_system.selected_unit as Shade
	if shade:
		var is_hostile = shade.shade_element in ["FIRE", "WATER", "EARTH"]
		show_ability_range(shade, is_hostile)

func show_ability_range(shade: Shade, is_hostile: bool) -> void:
	_current_ability_shade = shade
	_current_ability_is_hostile = is_hostile
	attack_range_overlay.clear()
	var tiles = grid_system.get_tiles_in_range(shade.grid_position, shade.ability_range, false)
	var source_id = 0 if is_hostile else 2
	for pos in tiles:
		attack_range_overlay.set_cell(pos, source_id, Vector2i(0, 0))

func hide_ability_range() -> void:
	attack_range_overlay.clear()
	_current_ability_shade = null

# ── Overlays ─────────────────────────────────────────────────────────

func _on_unit_selected(unit: Unit, reachable: Array[Vector2i]) -> void:
	move_range_overlay.clear()
	for pos in reachable:
		if pos != unit.grid_position:
			move_range_overlay.set_cell(pos, 0, Vector2i(0, 0))
	hud.show_unit_info(unit)

func _on_unit_deselected() -> void:
	move_range_overlay.clear()
	attack_range_overlay.clear()
	movement_arrow.clear_points()
	_clear_target_highlights()
	_cursor_path.clear()
	_is_tracing = false
	hud.hide_unit_info()

func _draw_attack_range(unit: Unit) -> void:
	attack_range_overlay.clear()
	var tiles = grid_system.get_tiles_in_range(unit.grid_position, unit.attack_range, unit.is_shade())
	for pos in tiles:
		if pos != unit.grid_position:
			attack_range_overlay.set_cell(pos, 0, Vector2i(0, 0))

func _clear_target_highlights() -> void:
	for unit in game_manager.all_units:
		unit.update_visual()

func show_thrust_options(unit: Unit) -> void:
	attack_range_overlay.clear()
	_thrust_overlays.clear()

	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var tiles: Array[Vector2i] = []
		for i in range(1, 3):
			tiles.append(unit.grid_position + dir * i)
		_thrust_overlays[dir] = tiles
		for pos in tiles:
			attack_range_overlay.set_cell(pos, 0, Vector2i(0, 0))

func hide_thrust_options() -> void:
	attack_range_overlay.clear()
	_thrust_overlays.clear()

	_current_thrust_direction = Vector2i.ZERO

func get_thrust_direction_at(grid_pos: Vector2i) -> Vector2i:
	for dir in _thrust_overlays:
		if grid_pos in _thrust_overlays[dir]:
			return dir
	return Vector2i.ZERO

func show_bash_options(unit: Unit) -> void:
	attack_range_overlay.clear()
	_bash_overlays.clear()
	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var tiles: Array[Vector2i] = []
		for d in [-1, 0, 1]:
			if dir == Vector2i.UP or dir == Vector2i.DOWN:
				tiles.append(unit.grid_position + dir + Vector2i(d, 0))
			else:
				tiles.append(unit.grid_position + dir + Vector2i(0, d))
		_bash_overlays[dir] = tiles
		for pos in tiles:
			attack_range_overlay.set_cell(pos, 0, Vector2i(0, 0))

func hide_bash_options() -> void:
	attack_range_overlay.clear()
	_bash_overlays.clear()
	_current_bash_direction = Vector2i.ZERO

func get_bash_direction_at(grid_pos: Vector2i) -> Vector2i:
	for dir in _bash_overlays:
		if grid_pos in _bash_overlays[dir]:
			return dir
	return Vector2i.ZERO

func show_volley_options(unit: Unit) -> void:
	attack_range_overlay.clear()
	var tiles = grid_system.get_tiles_in_range(unit.grid_position, unit.attack_range, false)
	for pos in tiles:
		if pos != unit.grid_position:
			attack_range_overlay.set_cell(pos, 0, Vector2i(0, 0))

func hide_volley_options() -> void:
	attack_range_overlay.clear()
	_volley_center = Vector2i(-1, -1)

func get_volley_tiles(center: Vector2i) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for dir in [Vector2i.ZERO, Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		tiles.append(center + dir)
	return tiles

func _on_shade_view_toggled(enabled: bool) -> void:
	if enabled:
		move_range_overlay.z_index = 6
		attack_range_overlay.z_index = 6
		cursor_highlight.z_index = 6
		game_manager.grid_layer.z_index = 5

	else:
		move_range_overlay.z_index = 2
		attack_range_overlay.z_index = 2
		cursor_highlight.z_index = 2

	for unit in game_manager.all_units:
		if not unit.is_shade():
			unit.get_node("HealthLabel").modulate.a = 0.2 if enabled else 1.0

	if _current_ability_shade and input_controller.mode == InputController.Mode.SHADE_ABILITY:
		show_ability_range(_current_ability_shade, _current_ability_is_hostile)

	fog_system.update_shade_view(enabled, game_manager.local_player_id)

# ── Animación de movimiento ───────────────────────────────────────────────────

func _on_move_started(unit: Unit, path: Array[Vector2i]) -> void:
	input_controller.lock()
	move_range_overlay.clear()
	await _animate_movement(unit, path)
	if not is_instance_valid(unit):
		input_controller.unlock()
		return
	if _ambush_activated:
		input_controller.clear_pending_path()
		action_system.move_confirmed.emit(null)
		return
	if _overwatch_activated and unit.state == Unit.State.MOVED:
		input_controller.clear_pending_path()
		input_controller.unlock()
		return
	action_system.move_confirmed.emit(unit)
	input_controller.clear_pending_path()
	input_controller.unlock()
	show_action_menu(unit)

func _animate_movement(unit: Unit, path: Array[Vector2i]) -> void:
	_overwatch_activated = false
	_ambush_activated = false
	var previous_tile = unit.grid_position
	for tile in path:
		var tween = create_tween()
		tween.tween_property(unit, "position", grid_system.grid_to_world_center(tile), 0.1)
		tween.tween_interval(0.04)
		await tween.finished
		
		if action_system.check_ambush_at(unit, tile, previous_tile):
			return
		if action_system.check_overwatch_at(unit, tile, previous_tile):
			await _overwatch_resolved
			if not is_instance_valid(unit):
				return
		previous_tile = tile

func _on_action_executed(action: BaseAction) -> void:
	hide_action_menu()
	match action.type:
		BaseAction.Type.MOVE:
			move_range_overlay.clear()
			movement_arrow.clear_points()
		BaseAction.Type.ATTACK:
			_clear_target_highlights()
		BaseAction.Type.END_TURN:
			move_range_overlay.clear()
			attack_range_overlay.clear()
			movement_arrow.clear_points()
			_clear_target_highlights()
			selection_system.deselect()
			hud.hide_unit_info()
			input_controller.mode = InputController.Mode.IDLE

func _on_overwatch_triggered(_attacker: Unit, target: Unit, _tile: Vector2i, _previous_tile: Vector2i) -> void:
	_overwatch_activated = true
	if not is_instance_valid(target):
		_overwatch_resolved.emit()
		return
	target.get_node("Sprite2D").modulate = Color(2, 0.5, 0.5)
	movement_arrow.clear_points()
	await get_tree().create_timer(0.5).timeout
	if not is_instance_valid(target):
		input_controller.unlock()
		hud.hide_unit_info()
		selection_system.deselect()
		action_system.move_confirmed.emit(null)
		input_controller.mode = InputController.Mode.IDLE
		_overwatch_resolved.emit()
		return
	target.update_visual()
	_overwatch_resolved.emit()

func _on_ambush_triggered(moving_unit: Unit, _hidden_unit: Unit, _tile: Vector2i) -> void:
	_ambush_activated = true
	if _movement_tween:
		_movement_tween.kill()
	moving_unit.state = Unit.State.MOVED
	moving_unit.update_visual()
	_show_ambush_effect(moving_unit.position)
	input_controller.unlock()
	input_controller.mode = InputController.Mode.IDLE
	selection_system.deselect()
	fog_system.recalculate(game_manager.local_player_id)

func _show_ambush_effect(world_pos: Vector2) -> void:
	var exclaim = Sprite2D.new()
	exclaim.texture = preload("res://art/ui/Exclamation.png")
	exclaim.position = world_pos + Vector2(0, -16)
	exclaim.scale = Vector2(0.03125, 0.03125)
	exclaim.z_index = 20
	get_tree().current_scene.add_child(exclaim)
	var tween = create_tween()
	tween.tween_interval(1.0)
	tween.tween_property(exclaim, "modulate:a", 0.0, 0.4)
	tween.tween_callback(func(): exclaim.queue_free())

# ── Cursor y flecha de movimiento ─────────────────────────────────────────────

func _process(_delta: float) -> void:
	# get_viewport().get_mouse_position() devuelve coordenadas de pantalla.
	# Como los overlays ya están en el mundo, necesitamos convertir a mundo.
	var screen_pos  = get_viewport().get_mouse_position()
	var world_pos   = get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	var grid_pos    = grid_system.world_to_grid(world_pos)

	cursor_highlight.clear()
	if action_menu.visible:
		return
	if grid_system.is_in_bounds(grid_pos):
		cursor_highlight.set_cell(grid_pos, 0, Vector2i(0, 0))
		_update_movement_arrow(grid_pos)
		if input_controller.mode == InputController.Mode.TARGETING:
			for target in selection_system.attack_targets:
				if target.grid_position == grid_pos:
					target.get_node("Sprite2D").modulate = Color(2, 0.5, 0.5)
				else:
					target.update_visual()
		if input_controller.mode == InputController.Mode.SHADE_ABILITY:
			var is_hostile = input_controller._pending_ability in ["MARK", "SCORCH", "MUDDLE"]
			for target in selection_system.attack_targets:
				if target.grid_position == grid_pos:
					target.get_node("Sprite2D").modulate = Color(2, 0.5, 0.5) if is_hostile else Color(0.5, 2, 0.5)
				else:
					target.update_visual()

	if input_controller.mode == InputController.Mode.TARGETING and input_controller._pending_ability == "THRUST":
		var dir = get_thrust_direction_at(grid_pos)
		if dir != _current_thrust_direction:
			_current_thrust_direction = dir
			for unit in game_manager.all_units:
				unit.update_visual()
			# Restaurar todos los tiles a rojo
			for d in _thrust_overlays:
				for pos in _thrust_overlays[d]:
					attack_range_overlay.set_cell(pos, 0, Vector2i(0, 0))
			# Pintar dirección hover en amarillo
			if dir != Vector2i.ZERO:
				for pos in _thrust_overlays[dir]:
					attack_range_overlay.set_cell(pos, 1, Vector2i(0, 0))
				var actor = selection_system.selected_unit
				if actor:
					for i in range(1, 3):
						var t = game_manager.get_unit_at(actor.grid_position + dir * i)
						if t and t.team != actor.team:
							t.get_node("Sprite2D").modulate = Color(2, 0.5, 0.5)

	if input_controller.mode == InputController.Mode.TARGETING and input_controller._pending_ability == "BASH":
		var dir = get_bash_direction_at(grid_pos)
		if dir != _current_bash_direction:
			_current_bash_direction = dir
			for unit in game_manager.all_units:
				unit.update_visual()
			# Restaurar todos los tiles a rojo
			for d in _bash_overlays:
				for pos in _bash_overlays[d]:
					attack_range_overlay.set_cell(pos, 0, Vector2i(0, 0))
			# Pintar dirección hover en amarillo
			if dir != Vector2i.ZERO:
				for pos in _bash_overlays[dir]:
					attack_range_overlay.set_cell(pos, 1, Vector2i(0, 0))
				var actor = selection_system.selected_unit
				if actor:
					for d in [-1, 0, 1]:
						var pos: Vector2i
						if dir == Vector2i.UP or dir == Vector2i.DOWN:
							pos = actor.grid_position + dir + Vector2i(d, 0)
						else:
							pos = actor.grid_position + dir + Vector2i(0, d)
						var t = game_manager.get_unit_at(pos)
						if t and t.team != actor.team:
							t.get_node("Sprite2D").modulate = Color(2, 0.5, 0.5)

	if input_controller.mode == InputController.Mode.TARGETING and input_controller._pending_ability == "VOLLEY":
		if grid_pos != _volley_center:
			_volley_center = grid_pos
			# Restaurar overlay base
			var unit = selection_system.selected_unit
			if unit:
				attack_range_overlay.clear()
				var range_tiles = grid_system.get_tiles_in_range(unit.grid_position, unit.attack_range, false)
				for pos in range_tiles:
					if pos != unit.grid_position:
						attack_range_overlay.set_cell(pos, 0, Vector2i(0, 0))
				# Pintar hover tiles en amarillo si el cursor está en rango
				if grid_pos in range_tiles:
					for pos in get_volley_tiles(grid_pos):
						attack_range_overlay.set_cell(pos, 1, Vector2i(0, 0))
				# Colorear unidades enemigas en hover tiles
			for unit2 in game_manager.all_units:
				unit2.update_visual()
			if grid_pos in grid_system.get_tiles_in_range(selection_system.selected_unit.grid_position, selection_system.selected_unit.attack_range, false):
				for pos in get_volley_tiles(grid_pos):
					var t = game_manager.get_unit_at(pos)
					if t and t.team != selection_system.selected_unit.team and t.visible:
						t.get_node("Sprite2D").modulate = Color(2, 0.5, 0.5)

func _update_movement_arrow(cursor_pos: Vector2i) -> void:
	if input_controller._locked:
		movement_arrow.clear_points()
		return
	if action_menu.visible:
		movement_arrow.clear_points()
		return
	if input_controller.mode == InputController.Mode.TARGETING or input_controller.mode == InputController.Mode.SHADE_ABILITY:
		movement_arrow.clear_points()
		return
	var unit = selection_system.selected_unit
	if not unit or unit.state != Unit.State.SELECTED:
		movement_arrow.clear_points()
		return
	if cursor_pos not in selection_system.reachable_cells:
		movement_arrow.clear_points()
		_is_tracing = false
		_cursor_path.clear()
		return

	# Iniciar tracing si no está activo
	if not _is_tracing:
		_is_tracing = true
		_cursor_path = [unit.grid_position]

	# Si el cursor retrocedió a un tile que ya está en el path, truncar
	if cursor_pos in _cursor_path:
		var idx = _cursor_path.find(cursor_pos)
		_cursor_path = _cursor_path.slice(0, idx + 1)
	else:
		var last = _cursor_path.back()
		var dx = abs(cursor_pos.x - last.x)
		var dy = abs(cursor_pos.y - last.y)
		# Si es adyacente, añadir al path manual
		if dx + dy == 1:
			_cursor_path.append(cursor_pos)
			# Verificar costo del path manual
			var cost = selection_system.calculate_path_cost(_cursor_path, unit)
			if cost > unit.movement_range:
				# Revertir a A*
				_cursor_path = selection_system.get_movement_path_to(cursor_pos)
		else:
			# No adyacente — salto del mouse, usar A*
			_cursor_path = selection_system.get_movement_path_to(cursor_pos)

	movement_arrow.clear_points()
	for tile in _cursor_path:
		movement_arrow.add_point(grid_system.grid_to_world_center(tile))

func _on_action_menu_end_turn() -> void:
	hide_action_menu()
	action_system.queue_action(EndTurnAction.new(game_manager.local_player_id))

func show_empty_tile_menu(grid_pos: Vector2i) -> void:
	action_menu.show_for_empty_tile()
	var world_pos = grid_system.grid_to_world_center(grid_pos)
	var screen_pos = get_viewport().get_canvas_transform() * world_pos
	action_menu.position = screen_pos + Vector2(20, -20)
	action_menu.visible = true

# ── Production Menu ─────────────────────────────────────────────

func show_production_menu(building: Building) -> void:
	var funds = game_manager.get_funds(building.team)
	_current_building = building
	production_menu.setup(building, funds)
	production_menu.position = Vector2(get_viewport().get_visible_rect().size / 2) - Vector2(160, 170)
	production_menu.visible = true

func hide_production_menu() -> void:
	production_menu.visible = false

func _on_unit_produced(unit_data: UnitData, cost: int) -> void:
	hide_production_menu()
	action_system.queue_action(ProduceAction.new(_current_building, unit_data, cost, _current_building.team))
