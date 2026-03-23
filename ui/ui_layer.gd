class_name UILayer
extends CanvasLayer

# Los overlays viven en el mundo 2D (hermanos de UILayer en Game),
# así que sus rutas suben un nivel con "../"
@onready var move_range_overlay: TileMapLayer  = $"../MoveRangeOverlay"
@onready var attack_range_overlay: TileMapLayer = $"../AttackRangeOverlay"
@onready var cursor_highlight: TileMapLayer    = $"../CursorHighlight"
@onready var movement_arrow: Line2D            = $"../MovementArrow"

# Sistemas — sin cambios
@onready var game_manager      = $"../GameManager"
@onready var action_system     = $"../ActionSystem"
@onready var selection_system  = $"../SelectionSystem"
@onready var grid_system       = $"../GridSystem"
@onready var turn_manager      = $"../TurnManager"
@onready var input_controller  = $"../InputController"

# ActionMenu sigue siendo hijo del CanvasLayer
@onready var action_menu = $ActionMenu

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

# ── Action Menu ───────────────────────────────────────────────────────────────

func show_action_menu(unit: Unit) -> void:
	var building = game_manager.get_building_at(unit.grid_position)
	var has_targets = selection_system.has_attack_targets(unit)
	action_menu.show_for_unit(unit, building, has_targets)
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
	# TODO

func _on_action_menu_ability(ability: String) -> void:
	hide_action_menu()
	input_controller.on_ability_pressed(ability)

# ── Overlays de rango ─────────────────────────────────────────────────────────

func _on_unit_selected(unit: Unit, reachable: Array[Vector2i]) -> void:
	move_range_overlay.clear()
	for pos in reachable:
		if pos != unit.grid_position:
			move_range_overlay.set_cell(pos, 0, Vector2i(0, 0))

func _on_unit_deselected() -> void:
	move_range_overlay.clear()
	attack_range_overlay.clear()
	movement_arrow.clear_points()
	_clear_target_highlights()

func _draw_attack_range(unit: Unit) -> void:
	attack_range_overlay.clear()
	var tiles = grid_system.get_tiles_in_range(unit.grid_position, unit.attack_range, unit.is_shade())
	for pos in tiles:
		if pos != unit.grid_position:
			attack_range_overlay.set_cell(pos, 0, Vector2i(0, 0))

func _clear_target_highlights() -> void:
	for unit in game_manager.all_units:
		unit.update_visual()

# ── Animación de movimiento ───────────────────────────────────────────────────

func _on_move_started(unit: Unit, path: Array[Vector2i]) -> void:
	input_controller.lock()
	move_range_overlay.clear()
	await _animate_movement(unit, path)
	action_system.move_confirmed.emit(unit)
	input_controller.clear_pending_path()
	input_controller.unlock()
	show_action_menu(unit)

func _animate_movement(unit: Unit, path: Array[Vector2i]) -> void:
	var tween = create_tween()
	tween.set_parallel(false)
	for tile in path:
		var world_pos = grid_system.grid_to_world_center(tile)
		tween.tween_property(unit, "position", world_pos, 0.1)
		tween.tween_interval(0.04)
	await tween.finished

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

func _update_movement_arrow(cursor_pos: Vector2i) -> void:
	if action_menu.visible:
		movement_arrow.clear_points()
		return
	if input_controller.mode == InputController.Mode.TARGETING:
		movement_arrow.clear_points()
		return
	var unit = selection_system.selected_unit
	if not unit or unit.state != Unit.State.SELECTED:
		movement_arrow.clear_points()
		return
	if cursor_pos not in selection_system.reachable_cells:
		movement_arrow.clear_points()
		return
	var path = selection_system.get_movement_path_to(cursor_pos)
	movement_arrow.clear_points()
	for tile in path:
		movement_arrow.add_point(grid_system.grid_to_world_center(tile))
