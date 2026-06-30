class_name UILayer
extends CanvasLayer

# Los overlays viven en el mundo 2D (hermanos de UILayer en Game),
# así que sus rutas suben un nivel con "../"
@onready var move_range_overlay: TileMapLayer  = $"../MoveRangeOverlay"
@onready var attack_range_overlay: TileMapLayer = $"../AttackRangeOverlay"
@onready var cursor_highlight: TileMapLayer    = $"../CursorHighlight"
@onready var movement_arrow: Line2D            = $"../MovementArrow"
var arrow_head: Line2D
var _thrust_overlays: Dictionary = {}
var _current_thrust_direction: Vector2i = Vector2i.ZERO
var _bash_overlays: Dictionary = {}
var _current_bash_direction: Vector2i = Vector2i.ZERO
var _volley_center: Vector2i = Vector2i(-1,-1)
var _scorch2_center: Vector2i = Vector2i(-1, -1)
var _divide_tiles: Array[Vector2i] = []
var _divide_hover_tile: Vector2i = Vector2i(-999, -999)
var _cursor_path: Array[Vector2i] = []
var _is_tracing: bool = false
var _saved_move_path: Array[Vector2i] = []
var _preview_target: Unit = null
var _preview_attacker: Unit = null
var _current_preview_target: Unit = null
var _preview_targets: Array[Unit] = []

# Sistemas — sin cambios
@onready var game_manager      = $"../GameManager"
@onready var action_system     = $"../ActionSystem"
@onready var selection_system  = $"../SelectionSystem"
@onready var grid_system       = $"../GridSystem"
@onready var turn_manager      = $"../TurnManager"
@onready var input_controller  = $"../InputController"
@onready var fog_system = $"../FogSystem"
@onready var hud = $"../HUD"
@onready var multiplayer_manager = $"../MultiplayerManager"
@onready var combat_system = $"../CombatSystem"

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
	combat_system.unit_damaged.connect(_on_unit_damaged)
	arrow_head = Line2D.new()
	arrow_head.width = movement_arrow.width
	arrow_head.default_color = movement_arrow.default_color
	arrow_head.z_index = movement_arrow.z_index
	movement_arrow.get_parent().call_deferred("add_child", arrow_head)
	action_menu.load_pressed.connect(_on_action_menu_load)
	action_menu.unload_pressed.connect(_on_action_menu_unload)

# ── Action Menu ───────────────────────────────────────────────────────────────

func show_action_menu(unit: Unit) -> void:
	hide_damage_preview()
	_current_preview_target = null
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
	var can_load = false
	var can_unload = false
	if unit is TransportUnit:
		can_unload = unit.carried_unit != null
	if unit.unit_type in ["Sword", "Archer", "Spear"]:
		var transport = _get_adjacent_transport(unit)
		can_load = transport != null
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
		has_shield_targets, has_muddle_targets, has_boost_targets, can_load, can_unload
	)
	action_menu.visible = true
	await get_tree().process_frame
	var screen_pos = get_viewport().get_canvas_transform() * unit.global_position
	var viewport_size = get_viewport().get_visible_rect().size
	action_menu.reset_size()
	if abs(viewport_size.y - screen_pos.y) < 64:
		action_menu.position = screen_pos + Vector2(20, -action_menu.size.y)
	elif abs(viewport_size.x - screen_pos.x) < 64:
		action_menu.position = screen_pos + Vector2(-90, -12)
	else:
		action_menu.position = screen_pos + Vector2(20, -12)

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
		var hostile_abilities = ["MARK", "SCORCH", "MUDDLE", "MARK2", "MUDDLE2", "SCORCH2"]
		var is_hostile = input_controller._pending_ability in hostile_abilities
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

func _on_unit_damaged(unit: Unit) -> void:
	if not is_instance_valid(unit):
		return
	var sprite = unit.get_node_or_null("Sprite2D")
	if not sprite:
		return
	sprite.modulate = Color(2, 0.5, 0.5)
	await get_tree().create_timer(0.6).timeout
	if is_instance_valid(unit):
		unit.update_visual()

func _get_adjacent_transport(unit: Unit) -> TransportUnit:
	for u in game_manager.all_units:
		if u is TransportUnit and u.team == unit.team and u.grid_position == unit.grid_position:
			return u
	return null

func _on_action_menu_load() -> void:
	hide_action_menu()
	var unit = selection_system.selected_unit
	var transport = _get_adjacent_transport(unit)
	if transport:
		input_controller.on_load_pressed(transport)

func _on_action_menu_unload() -> void:
	hide_action_menu()
	input_controller.on_unload_pressed()

# ── Overlays ─────────────────────────────────────────────────────────

func _on_unit_selected(unit: Unit, reachable: Array[Vector2i]) -> void:
	move_range_overlay.clear()
	attack_range_overlay.clear()
	for pos in reachable:
		if pos != unit.grid_position:
			move_range_overlay.set_cell(pos, 0, Vector2i(0, 0))
	var attackable: Array[Vector2i] = []
	if unit.unit_type == "Cannon":
		attackable = grid_system.get_tiles_in_range(unit.grid_position, unit.attack_range, unit.is_shade())
	else:
		attackable = selection_system.get_attackable_tiles(unit)
	for unit2 in game_manager.all_units:
		if unit2.team != unit.team and unit2.visible and unit2.is_shade() == unit.is_shade():
			if unit2.grid_position in attackable:
				attack_range_overlay.set_cell(unit2.grid_position, 0, Vector2i(0, 0))
	hud.show_unit_info(unit)

func _on_unit_deselected() -> void:
	hide_damage_preview()
	_current_preview_target = null
	move_range_overlay.clear()
	attack_range_overlay.clear()
	movement_arrow.clear_points()
	arrow_head.clear_points()
	_clear_target_highlights()
	_cursor_path.clear()
	_is_tracing = false
	hud.hide_unit_info()

func _draw_attack_range(unit: Unit, immediate_only: bool = false) -> void:
	attack_range_overlay.clear()
	var tiles: Array[Vector2i] = []
	if immediate_only or unit.unit_type == "Cannon":
		tiles = grid_system.get_tiles_in_range(unit.grid_position, unit.attack_range, unit.is_shade())
	else:
		tiles = selection_system.get_attackable_tiles(unit)
	for pos in tiles:
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

func show_divide_options(drone: Drone) -> void:
	attack_range_overlay.clear()
	_divide_tiles.clear()
	_divide_hover_tile = Vector2i(-999, -999)

	var dirs = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

	for dir in dirs:
		var pos = drone.grid_position + dir
		if grid_system.is_in_bounds(pos) and game_manager.get_unit_at(pos, true) == null:
			attack_range_overlay.set_cell(pos, 0, Vector2i(0, 0))
			_divide_tiles.append(pos)

func show_unload_options(transport: TransportUnit) -> void:
	move_range_overlay.clear()
	attack_range_overlay.clear()
	var valid_tiles = selection_system.get_valid_unload_tiles(transport)
	for pos in valid_tiles:
		attack_range_overlay.set_cell(pos, 1, Vector2i(0, 0))

func hide_unload_options() -> void:
	attack_range_overlay.clear()

# ── Animación de movimiento ───────────────────────────────────────────────────

func _on_move_started(unit: Unit, path: Array[Vector2i], is_remote: bool) -> void:
	input_controller.lock()
	move_range_overlay.clear()
	var saved_path = path.duplicate()
	_saved_move_path = saved_path
	if is_remote and unit.team != game_manager.local_player_id:
		if unit.marked_turns > 0:
			if unit.is_shade():
				unit.visible = game_manager.shade_view_enabled
			else:
				unit.visible = true
		elif unit.is_shade():
			unit.visible = game_manager.shade_view_enabled and fog_system.is_shade_visible(path[0], game_manager.local_player_id)
		else:
			unit.visible = fog_system.is_visible(path[0], game_manager.local_player_id)
	await _animate_movement(unit, path, is_remote)
	if not is_instance_valid(unit):
		input_controller.unlock()
		return
	if _ambush_activated:
		_ambush_activated = false
		input_controller.unlock()
		action_system.move_confirmed.emit(null)
		return
	if _overwatch_activated:
		input_controller.clear_pending_path()
		unit.state = Unit.State.MOVED
		unit.update_visual()
		input_controller.unlock()
		input_controller.mode = InputController.Mode.IDLE
		_overwatch_activated = false
		fog_system.recalculate(game_manager.local_player_id)
		action_system.move_confirmed.emit(unit)
		unit.original_position = unit.grid_position
		if multiplayer_manager.is_network_connected and not is_remote:
			var action = MoveAction.new(unit, saved_path)
			var dict = multiplayer_manager.serialize_action(action)
			multiplayer_manager.send_action(dict)
		return
	action_system.move_confirmed.emit(unit)
	input_controller.unlock()
	if not is_remote:
		show_action_menu(unit)
	else:
		if is_instance_valid(unit):
			unit.state = Unit.State.MOVED
			unit.update_visual()

func _animate_movement(unit: Unit, path: Array[Vector2i], _is_remote: bool = false) -> void:
	_overwatch_activated = false
	_ambush_activated = false
	var previous_tile = unit.grid_position
	for tile in path:
		var tween = create_tween()
		tween.tween_property(unit, "position", grid_system.grid_to_world_center(tile), 0.1)
		tween.tween_interval(0.04)
		await tween.finished
		if unit.team != game_manager.local_player_id:
			if unit.marked_turns > 0:
				if unit.is_shade():
					unit.visible = game_manager.shade_view_enabled
				else:
					unit.visible = true
			elif unit.is_shade():
				unit.visible = game_manager.shade_view_enabled and fog_system.is_shade_visible(tile, game_manager.local_player_id)
			else:
				unit.visible = fog_system.is_visible(tile, game_manager.local_player_id)
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
			arrow_head.clear_points()
		BaseAction.Type.ATTACK:
			_clear_target_highlights()
		BaseAction.Type.END_TURN:
			move_range_overlay.clear()
			attack_range_overlay.clear()
			movement_arrow.clear_points()
			arrow_head.clear_points()
			_clear_target_highlights()
			selection_system.deselect()
			hud.hide_unit_info()
			input_controller.mode = InputController.Mode.IDLE

func _on_overwatch_triggered(_attacker: Unit, target: Unit, _tile: Vector2i, _previous_tile: Vector2i) -> void:
	_overwatch_activated = true
	if not is_instance_valid(target):
		_overwatch_resolved.emit()
		action_system.move_confirmed.emit(null)
		return
	target.get_node("Sprite2D").modulate = Color(2, 0.5, 0.5)
	movement_arrow.clear_points()
	arrow_head.clear_points()
	attack_range_overlay.clear()
	await get_tree().create_timer(0.5).timeout
	if not is_instance_valid(target):
		input_controller.unlock()
		hud.hide_unit_info()
		selection_system.deselect()
		input_controller.mode = InputController.Mode.IDLE
		_overwatch_resolved.emit()
		action_system.move_confirmed.emit(null)
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
	if multiplayer_manager.is_network_connected and not action_system._executing_remote:
			var truncated_path: Array[Vector2i] = []
			for p in _saved_move_path:
				truncated_path.append(p)
				if p == moving_unit.grid_position:
					break
			var action = MoveAction.new(moving_unit, truncated_path)
			var dict = multiplayer_manager.serialize_action(action)
			dict["show_ambush_effect"] = true
			multiplayer_manager.send_action(dict)
			_saved_move_path.clear()

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
	#if Engine.get_process_frames() % 60 == 0:
		#print("FPS: ", Engine.get_frames_per_second())
	var screen_pos  = get_viewport().get_mouse_position()
	var world_pos   = get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	var grid_pos    = grid_system.world_to_grid(world_pos)

	cursor_highlight.clear()
	if action_menu.visible:
		return
	if grid_system.is_in_bounds(grid_pos):
		cursor_highlight.set_cell(grid_pos, 0, Vector2i(0, 0))
		_update_movement_arrow(grid_pos)

		if input_controller.mode == InputController.Mode.UNIT_SELECTED:
			var attacker = selection_system.selected_unit
			if attacker:
				var hovered_enemy: Unit = null
				for unit in game_manager.all_units:
					if unit.team != attacker.team and unit.visible and unit.grid_position == grid_pos:
						if unit.is_shade() == attacker.is_shade():
							hovered_enemy = unit
							break
				var attackable_tiles = selection_system.get_attackable_tiles(attacker)
				if hovered_enemy and grid_pos in attackable_tiles:
					if hovered_enemy != _current_preview_target:
						hide_damage_preview()
						_current_preview_target = hovered_enemy
						show_damage_preview(attacker, hovered_enemy)
				else:
					if _current_preview_target != null:
						_current_preview_target = null
						hide_damage_preview()
			else:
				if _current_preview_target != null:
					_current_preview_target = null
					hide_damage_preview()

		if input_controller.mode == InputController.Mode.TARGETING:
			var ability = input_controller._pending_ability
			if ability not in ["THRUST", "BASH", "VOLLEY"]:
				var hovered_target: Unit = null
				for target in selection_system.attack_targets:
					if target.grid_position == grid_pos:
						target.get_node("Sprite2D").modulate = Color(2, 0.5, 0.5)
						hovered_target = target
					else:
						target.update_visual()
				var attacker = selection_system.selected_unit
				if hovered_target and attacker:
					if hovered_target != _current_preview_target:
						hide_damage_preview()
						_current_preview_target = hovered_target
						show_damage_preview(attacker, hovered_target)
				else:
					if _current_preview_target != null:
						_current_preview_target = null
						hide_damage_preview()

		if input_controller.mode == InputController.Mode.SHADE_ABILITY:
			var is_hostile = input_controller._pending_ability in ["MARK", "SCORCH", "MUDDLE", "MARK2", "SCORCH2", "MUDDLE2"]
			var ability = input_controller._pending_ability
			var attacker = selection_system.selected_unit
			if ability == "SCORCH2":
				if grid_pos != _scorch2_center:
					_scorch2_center = grid_pos
					hide_damage_preview()
					_current_preview_target = null
					for unit in game_manager.all_units:
						unit.update_visual()
					attack_range_overlay.clear()
					var range_tiles = grid_system.get_tiles_in_range(attacker.grid_position, attacker.ability_range, true)
					for pos in range_tiles:
						attack_range_overlay.set_cell(pos, 0, Vector2i(0, 0))
					if grid_pos in range_tiles:
						var area_tiles = [grid_pos, grid_pos + Vector2i.UP, grid_pos + Vector2i.DOWN, grid_pos + Vector2i.LEFT, grid_pos + Vector2i.RIGHT]
						for pos in area_tiles:
							attack_range_overlay.set_cell(pos, 1, Vector2i(0, 0))
						var mult = 2.5 if game_manager.current_element == GameManager.Element.FIRE else 1.0
						var first_target: Unit = null
						for pos in area_tiles:
							var t = game_manager.get_unit_at(pos, game_manager.shade_view_enabled)
							if t and t.team != attacker.team and t.visible and t.is_shade() == game_manager.shade_view_enabled:
								t.get_node("Sprite2D").modulate = Color(2, 0.5, 0.5)
								var scorch_dmg = int(max(0.0, mult * attacker.health / 5.0 - t.get_total_defense(0)))
								show_damage_preview(attacker, t, 1.0, true, scorch_dmg)
								if first_target == null:
									first_target = t
						_current_preview_target = first_target
			else:
				var hovered_target: Unit = null
				for target in selection_system.attack_targets:
					if target.grid_position == grid_pos:
						target.get_node("Sprite2D").modulate = Color(2, 0.5, 0.5) if is_hostile else Color(0.5, 2, 0.5)
						hovered_target = target
					else:
						target.update_visual()
				if hovered_target and attacker and ability == "SCORCH":
					var correct_view = hovered_target.is_shade() == game_manager.shade_view_enabled
					if correct_view and hovered_target != _current_preview_target:
						_current_preview_target = hovered_target
						var mult = 2.5 if game_manager.current_element == GameManager.Element.FIRE else 1.0
						var scorch_dmg = int(max(0.0, mult * attacker.health / 5.0 - hovered_target.get_total_defense(0)))
						show_damage_preview(attacker, hovered_target, 1.0, true, scorch_dmg)
					elif not correct_view and _current_preview_target != null:
						_current_preview_target = null
						hide_damage_preview()
				else:
					if _current_preview_target != null:
						_current_preview_target = null
						hide_damage_preview()

	if input_controller.mode == InputController.Mode.TARGETING and input_controller._pending_ability == "THRUST":
		var dir = get_thrust_direction_at(grid_pos)
		if dir != _current_thrust_direction:
			_current_thrust_direction = dir
			hide_damage_preview()
			_current_preview_target = null
			for unit in game_manager.all_units:
				unit.update_visual()
			for d in _thrust_overlays:
				for pos in _thrust_overlays[d]:
					attack_range_overlay.set_cell(pos, 0, Vector2i(0, 0))
			if dir != Vector2i.ZERO:
				for pos in _thrust_overlays[dir]:
					attack_range_overlay.set_cell(pos, 1, Vector2i(0, 0))
				var actor = selection_system.selected_unit
				if actor:
					for i in range(1, 3):
						var t = game_manager.get_unit_at(actor.grid_position + dir * i)
						if t and t.team != actor.team:
							t.get_node("Sprite2D").modulate = Color(2, 0.5, 0.5)
							show_damage_preview(actor, t, 0.8, true)

	if input_controller.mode == InputController.Mode.TARGETING and input_controller._pending_ability == "BASH":
		var dir = get_bash_direction_at(grid_pos)
		if dir != _current_bash_direction:
			_current_bash_direction = dir
			hide_damage_preview()
			_current_preview_target = null
			for unit in game_manager.all_units:
				unit.update_visual()
			for d in _bash_overlays:
				for pos in _bash_overlays[d]:
					attack_range_overlay.set_cell(pos, 0, Vector2i(0, 0))
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
							show_damage_preview(actor, t, 0.7, true)

	if input_controller.mode == InputController.Mode.TARGETING and input_controller._pending_ability == "VOLLEY":
		if grid_pos != _volley_center:
			_volley_center = grid_pos
			hide_damage_preview()
			_current_preview_target = null
			var unit = selection_system.selected_unit
			if unit:
				attack_range_overlay.clear()
				var range_tiles = grid_system.get_tiles_in_range(unit.grid_position, unit.attack_range, false)
				for pos in range_tiles:
					if pos != unit.grid_position:
						attack_range_overlay.set_cell(pos, 0, Vector2i(0, 0))
				if grid_pos in range_tiles:
					for pos in get_volley_tiles(grid_pos):
						attack_range_overlay.set_cell(pos, 1, Vector2i(0, 0))
			for unit2 in game_manager.all_units:
				unit2.update_visual()
			if grid_pos in grid_system.get_tiles_in_range(selection_system.selected_unit.grid_position, selection_system.selected_unit.attack_range, false):
				for pos in get_volley_tiles(grid_pos):
					var t = game_manager.get_unit_at(pos)
					if t and t.team != selection_system.selected_unit.team and t.visible:
						t.get_node("Sprite2D").modulate = Color(2, 0.5, 0.5)
						show_damage_preview(selection_system.selected_unit, t, 0.6, true)

	if input_controller.mode == InputController.Mode.TARGETING and input_controller._pending_ability == "DIVIDE":
		if grid_pos != _divide_hover_tile:
			_divide_hover_tile = grid_pos
			attack_range_overlay.clear()
			for pos in _divide_tiles:
				attack_range_overlay.set_cell(pos, 0, Vector2i(0, 0))
			if grid_pos in _divide_tiles:
				attack_range_overlay.set_cell(grid_pos, 1, Vector2i(0, 0))

func _update_movement_arrow(cursor_pos: Vector2i) -> void:
	if input_controller._locked:
		movement_arrow.clear_points()
		arrow_head.clear_points()
		return
	if action_menu.visible:
		movement_arrow.clear_points()
		arrow_head.clear_points()
		return
	if input_controller.mode == InputController.Mode.TARGETING or input_controller.mode == InputController.Mode.SHADE_ABILITY or input_controller.mode == InputController.Mode.UNLOAD:
		movement_arrow.clear_points()
		arrow_head.clear_points()
		return
	var unit = selection_system.selected_unit
	if not unit or unit.state != Unit.State.SELECTED:
		movement_arrow.clear_points()
		arrow_head.clear_points()
		return
	if cursor_pos not in selection_system.reachable_cells:
		movement_arrow.clear_points()
		arrow_head.clear_points()
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
	arrow_head.clear_points()
	for tile in _cursor_path:
		movement_arrow.add_point(grid_system.grid_to_world_center(tile))

	if arrow_head:
		arrow_head.clear_points()
		if _cursor_path.size() >= 2:
			var tip = grid_system.grid_to_world_center(_cursor_path.back())
			var prev = grid_system.grid_to_world_center(_cursor_path[_cursor_path.size() - 2])
			var dir = (tip - prev).normalized()
			var perp = Vector2(-dir.y, dir.x)
			var size = 6.0
			arrow_head.add_point(tip - dir * size + perp * size)
			arrow_head.add_point(tip)
			arrow_head.add_point(tip - dir * size - perp * size)

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
	var shade_count = 0
	var shades_pos: Array
	for unit in game_manager.all_units:
		if unit.is_shade():
			shades_pos.append(unit.grid_position)
			if unit.team == building.team:
				shade_count += 1
	_current_building = building
	if building.building_type == "HQ" and building.building_position in shades_pos:
		return
	production_menu.setup(building, funds, shade_count)
	production_menu.visible = true
	await get_tree().process_frame
	var viewport_size = get_viewport().get_visible_rect().size
	production_menu.position = (viewport_size / 2) - (production_menu.size / 2)

func hide_production_menu() -> void:
	production_menu.visible = false

func _on_unit_produced(unit_data: UnitData, cost: int) -> void:
	hide_production_menu()
	action_system.queue_action(ProduceAction.new(_current_building, unit_data, cost, _current_building.team))

func show_damage_preview(attacker: Unit, target: Unit, multiplier: float = 1.0, no_counter: bool = false, custom_dmg: int = -1) -> void:
	_preview_attacker = attacker
	if not (_preview_target == target):
		_preview_targets.append(target)
	_preview_target = target
	var preview = combat_system.preview_damage(attacker, target, multiplier)
	var dmg = custom_dmg if custom_dmg >= 0 else preview["damage"]
	target.show_hp_preview(target.health - dmg)
	if not no_counter and preview["has_counter"]:
		attacker.show_hp_preview(attacker.health - preview["counter"])

func hide_damage_preview() -> void:
	if is_instance_valid(_preview_attacker):
		_preview_attacker.hide_hp_preview()
	for t in _preview_targets:
		if is_instance_valid(t):
			t.hide_hp_preview()
	_preview_targets.clear()
	_preview_target = null
	_preview_attacker = null
