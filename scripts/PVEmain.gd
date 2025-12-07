extends Node2D

### ==========================  NODE REFERENCES ========================== ###

@onready var standard_overlay = $MapLayer/MoveRangeOverlay
@onready var raider_range_overlay = $RaiderLayer/RaiderMoveRangeOverlay
@onready var cursor_highlight = $UI/CursorHighlight
@onready var action_menu = preload("res://scenes/UI/unit_actions.tscn")
@onready var fog_tilemap = $MapLayer/FogOfWar
@onready var raider_fog_tilemap = $RaiderLayer/FogOfWar2
@onready var raider_map = $RaiderLayer/RaiderMap
@onready var hud = $UI/HUD
@onready var all_units = $Units.get_children() + $RaiderUnits.get_children()
@onready var attack_range_overlay = $MapLayer/AttackRangeOverlay
var showing_attack_range := false
var current_attack_range_unit: MapUnit = null
@onready var camera2d = $Camera2D
#@onready var pause_menu = preload("res://scenes/UI/PauseMenu.tscn")
@onready var pause_menu = $UI/Pause_menu
var save_path = "user://savegame.save"

### ========================== GAME STATE ========================== ###

var action_menu_instance = null
var is_menu_open := false
var attack_mode := false
var mark_mode := false
var selected_unit: MapUnit
var potential_targets: Array[MapUnit] = []
var is_ai_processing := false
var raider_view_enabled = false
var input_locked: bool = false
enum TurnState { PLAYER1_TURN, PLAYER2_TURN }
var current_turn: TurnState = TurnState.PLAYER1_TURN
var current_player_team: int = 1
@export var team1_funds: int = 0
@export var team2_funds: int = 0
var team1_income: int = 0
var team2_income: int = 0
var turn: int = 1

### ========================== AI PRODUCTION SYSTEM ========================== ###
var ai_production_buildings: Array[Building] = []
var ai_production_queue: Array = []  # {building: Building, unit_type: String, cost: int}
var ai_production_budget: int = 0
var ai_minimum_balance: int = 2000  # Mantener este balance mínimo


### ========================== MAP CONFIG ========================== ###

@export var map_size := Vector2i(22, 15)
var raider_visible_tiles : Array = []
var mapunit_visible_tiles : Array = []
var all_visible_tiles : Array = []

### ========================== PATHFINDING AND MOVEMENT ========================== ###
var astar_regular = AStar2D.new()
var astar_points: Dictionary = {}  # Map Vector2i -> point_id
var astar := AStarGrid2D.new()
var astar_raider := AStarGrid2D.new()
var movement_arrow: Line2D
var cursor_path: Array[Vector2i] = []
var is_tracing_path: bool = false
var last_cursor_pos: Vector2i
var is_collapsed_to_astar: bool = false
const UNIT_TERRAIN_COSTS = {
	"Infantry": {
		"PLAINS": 1,
		"MOUNTAIN": 3,  # Infantry pay 2 MP for mountains
		"WALL": 99,    # Infantry move through forests easily
		"RIVER": 2,     # Rivers cost 2 MP
		"FOREST": 2,
		"OCEAN": 99,      # Cannot move on water
		"CITY": 1,
	},
	"Raider": {
		"PLAINS": 1,
		"MOUNTAIN": 1, # Tanks CANNOT cross mountains
		"FOREST": 1,    # Forests slow down tanks
		"RIVER": 1,    # Tanks cannot cross rivers
		"WALL": 1,
		"OCEAN": 1,      # Cannot move on water
		"CITY": 1,
	},
	"Naval": {
		"PLAINS": 99,
		"MOUNTAIN": 99, # Recon cannot cross mountains
		"FOREST": 99,    # Forests slow recon
		"RIVER": 99,    # Cannot cross rivers
		"ROAD": 99,      # Roads are fast
		"OCEAN": 1,
		"CITY": 99,
	},
	# Add more unit types as needed
}

### ========================== AI SYSTEM ========================== ###

var ai_timer: Timer
var ai_units: Array[MapUnit] = []

### ========================== ACTIVE CONTEXT ========================== ###

var active_overlay: TileMap
var active_units: Node
var active_fog_tilemap: TileMap

### ========================== UNIT MOVEMENT LOGIC ========================== ###

# MOVEMENT FUNCTIONS (WRAPPED + NORMAL)
func move_unit_along_wrapped_path(unit: MapUnit, path: Array[Vector2i]) -> void:
	if path.is_empty():  # Safety check
		return

	if path.size() < 2:
		input_locked = false
		return

	input_locked = true
	unit.original_position = unit.grid_position
	var last_safe_tile = [unit.grid_position]  # Lambda capture for ambush

	var tween := create_tween()
	tween.set_parallel(false)
	var move_time := 0.1
	var pause_time := 0.04

	# Convert extended coordinates to wrapped coordinates
	var wrapped_path: Array[Vector2i] = []
	for tile in path:
		wrapped_path.append(Vector2i(posmod(tile.x, map_size.x), tile.y))

	# Find wrap-around point
	var wrap_index = -1
	for i in range(1, wrapped_path.size()):
		var prev_tile = wrapped_path[i-1]
		var current_tile = wrapped_path[i]
		if abs(current_tile.x - prev_tile.x) > 1:
			wrap_index = i - 1
			break

	# Phase 1: move to edge
	for i in range(1, wrap_index + 1):
		var tile = wrapped_path[i]
		var pos: Vector2 = Vector2(tile * 32) + Vector2(16, 16)

		tween.tween_property(unit, "global_position", pos, move_time)
		tween.tween_interval(pause_time)

		# Ambush check
		var step_tile = tile
		tween.tween_callback(func() -> void:
			var enemy := get_hidden_enemy_at(step_tile, unit.team, unit.is_raider())
			if enemy:
				enemy.visible = true
				enemy.update_visual_state()
				show_ambush_effect(unit.global_position)

				# Revert to last safe tile and mark MOVED
				unit.grid_position = last_safe_tile[0]
				unit.global_position = Vector2(last_safe_tile[0] * 32) + Vector2(16, 16)
				unit.current_state = MapUnit.UnitState.MOVED
				unit.update_visual_state()
				update_fog_of_war()
				active_overlay.clear()
				input_locked = false
				tween.stop()
			else:
				last_safe_tile[0] = step_tile
				unit.grid_position = step_tile
		)

	# Phase 2: teleport across wrap
	if wrap_index >= 0:
		tween.tween_callback(func():
			var edge_tile = wrapped_path[wrap_index]
			var next_tile = wrapped_path[wrap_index + 1]
			if edge_tile.x == 0 and next_tile.x == map_size.x - 1:
				unit.global_position = Vector2((map_size.x - 1) * 32 + 16, edge_tile.y * 32 + 16)
			elif edge_tile.x == map_size.x - 1 and next_tile.x == 0:
				unit.global_position = Vector2(16, edge_tile.y * 32 + 16)
		)

	# Phase 3: move remaining tiles
	for i in range(wrap_index + 1, wrapped_path.size()):
		var tile = wrapped_path[i]
		var pos: Vector2 = Vector2(tile * 32) + Vector2(16, 16)

		tween.tween_property(unit, "global_position", pos, move_time)
		tween.tween_interval(pause_time)

		var step_tile = tile
		tween.tween_callback(func() -> void:
			var enemy := get_hidden_enemy_at(step_tile, unit.team, unit.is_raider())
			if enemy:
				enemy.visible = true
				enemy.update_visual_state()
				show_ambush_effect(unit.global_position)

				unit.grid_position = last_safe_tile[0]
				unit.global_position = Vector2(last_safe_tile[0] * 32) + Vector2(16, 16)
				unit.current_state = MapUnit.UnitState.MOVED
				unit.update_visual_state()
				update_fog_of_war()
				active_overlay.clear()
				input_locked = false
				tween.stop()
			else:
				last_safe_tile[0] = step_tile
				unit.grid_position = step_tile
		)

	# Final callback: end of path for normal movement
	tween.tween_callback(func() -> void:
		if input_locked:
			unit.global_position = Vector2(wrapped_path.back() * 32) + Vector2(16, 16)
			input_locked = false
			show_action_menu(unit)
	)

func get_wrapped_tile_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	update_astar_raider(start, goal)  # setup solids
	var offset_goal = goal
	if start.x > goal.x:
		offset_goal += Vector2i(map_size.x, 0)
	elif goal.x > start.x:
		offset_goal -= Vector2i(map_size.x, 0)

	var raw_path = astar_raider.get_point_path(start, offset_goal)
	if raw_path.is_empty():
		return []

	var points: Array[Vector2i] = []
	for p in raw_path:
		var tile = Vector2i(p / 32)
		if points.is_empty() or points.back() != tile:
			points.append(tile)

	var filtered_path: Array[Vector2i] = [points[0]]
	for i in range(1, points.size()):
		var prev = filtered_path.back()
		var next = points[i]
		if prev.x != next.x and prev.y != next.y:
			filtered_path.append(Vector2i(next.x, prev.y))
			filtered_path.append(Vector2i(next.x, next.y))
		else:
			filtered_path.append(next)
	return filtered_path

func is_move_wrapped(start: Vector2i, goal: Vector2i, raider: MapUnit) -> bool:
	var dx = abs(start.x - goal.x)
	var move_range = raider.movement_range
	return dx > move_range

func update_astar_raider(start: Vector2i, goal: Vector2i):
	astar_raider.clear()
	astar_raider.region = Rect2i(Vector2i(-map_size.x, 0),Vector2i(map_size.x * 3, map_size.y))
	astar_raider.cell_size = Vector2(32, 32)
	astar_raider.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar_raider.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar_raider.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar_raider.update()
	
	if start.x > goal.x:
		for y in range(map_size.y):
			for x in range(map_size.x):
				if active_overlay.get_cell_source_id(0, Vector2i(x,y)) == -1:
					if x > goal.x:
						astar_raider.set_point_solid(Vector2i(x,y), true)
					else:
						astar_raider.set_point_solid(Vector2i(x,y) + Vector2i(map_size.x, 0), true)

	if goal.x > start.x:
		for y in range(map_size.y):
			for x in range(map_size.x):
				if active_overlay.get_cell_source_id(0, Vector2i(x,y)) == -1:
					if x < goal.x:
						astar_raider.set_point_solid(Vector2i(x,y), true)
					else:
						astar_raider.set_point_solid(Vector2i(x,y) - Vector2i(map_size.x, 0), true)

func get_tile_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	# raw_path is a PackedVector2Array
	var raw_path: PackedVector2Array = astar.get_point_path(start, goal)
	# Convert manually into Array[Vector2i] (tile positions)
	for p in raw_path:
		var tile: Vector2i = Vector2i(p / 32)
		if points.is_empty() or points.back() != tile:
			points.append(tile)
	# Filter out diagonal steps
	var filtered_path: Array[Vector2i] = [points[0]]
	for i in range(1, points.size()):
		var prev = filtered_path.back()
		var next = points[i]
		if prev.x != next.x and prev.y != next.y:
			# Split diagonal into two cardinal moves
			filtered_path.append(Vector2i(next.x, prev.y))
			filtered_path.append(Vector2i(next.x, next.y))
		else:
			filtered_path.append(next)
	return filtered_path

func move_unit_along_path(unit: MapUnit, path: Array[Vector2i]) -> void:
	if path.is_empty():
		return

	input_locked = true
	unit.original_position = unit.grid_position  # Save starting tile
	var last_safe_tile = [unit.grid_position]  # Lambda capture for ambush

	var tween := create_tween()
	tween.set_parallel(false)
	var move_time := 0.1
	var pause_time := 0.04

	for tile in path:
		var step_tile := tile
		var pos: Vector2 = Vector2(step_tile * 32) + Vector2(16, 16)

		# Move visually
		tween.tween_property(unit, "global_position", pos, move_time)
		tween.tween_interval(pause_time)

		# Ambush callback only if hidden enemy
		if get_hidden_enemy_at(step_tile, unit.team, unit.is_raider()):
			tween.tween_callback(func() -> void:
				var enemy := get_hidden_enemy_at(step_tile, unit.team, unit.is_raider())
				if enemy:
					enemy.visible = true
					enemy.update_visual_state()
					
					# Revert to last safe tile and mark as MOVED
					unit.grid_position = last_safe_tile[0]
					unit.global_position = Vector2(last_safe_tile[0] * 32) + Vector2(16, 16)
					show_ambush_effect(unit.global_position)
					unit.current_state = MapUnit.UnitState.MOVED
					unit.update_visual_state()
					update_fog_of_war()
					active_overlay.clear()
					input_locked = false
					tween.stop()
			)
		else:
			# Just update last safe tile for potential ambush
			tween.tween_callback(func() -> void:
				last_safe_tile[0] = step_tile
			)

	# End-of-path callback for normal movement
	var end_move_callback = func() -> void:
		if input_locked:
			# Do not update grid_position yet! Wait for player to confirm
			unit.global_position = Vector2(path.back() * 32) + Vector2(16, 16)
			input_locked = false

			# Show action menu (MOVE/ATTACK/CANCEL)
			show_action_menu(unit)

	tween.tween_callback(end_move_callback)
	active_overlay.clear()

func update_astar(moving_unit: MapUnit) -> void:
	astar.clear()
	astar.region = Rect2i(Vector2i(0, 0), map_size)
	astar.cell_size = Vector2(32, 32)
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()

	# Set terrain costs for each tile using weight_scale
	for x in range(map_size.x):
		for y in range(map_size.y):
			var pos = Vector2i(x, y)
			var terrain = get_terrain_at(pos)
			var cost = get_movement_cost(moving_unit.unit_type, terrain)
			
			# Use weight_scale to set movement cost
			astar.set_point_weight_scale(pos, float(cost))


	# Enemy units block (set very high cost)
	for u in all_units:
		if u != moving_unit and u.visible and _in_bounds(u.grid_position):
			var same_type = u.is_raider() == moving_unit.is_raider()
			if same_type and u.team != moving_unit.team:
				astar.set_point_weight_scale(u.grid_position, 99.0)

func is_position_free(pos: Vector2i, ignore_unit: MapUnit, final_tile: bool = true, ignore_hidden: bool = true) -> bool:
	# Units
	for unit in all_units:
		if unit == ignore_unit:
			continue

		if unit.grid_position == pos:
			# Respect the ignore_hidden flag: if we're ignoring hidden, skip hidden units
			if ignore_hidden and not unit.visible:
				continue

			var same_type = unit.is_raider() == ignore_unit.is_raider()

			if same_type:
				if unit.team == ignore_unit.team:
					# Ally of same type: allow pass-through but not final position
					return not final_tile
				else:
					# Visible (or considered) enemy of same type: block
					return false
			else:
				# Different types (Raider vs non-Raider): never block
				continue

	return true

func is_visibly_occupied(pos: Vector2i, mover: MapUnit) -> bool:
	for unit in all_units:
		if unit.visible and unit.grid_position == pos:
			# Only block if enemy of the same type
			if unit.team != mover.team and unit.is_raider() == mover.is_raider():
				return true
	return false

func get_reachable_cells(start: Vector2i, movement_points: int, mover: MapUnit, is_raider: bool) -> Array[Vector2i]:
	var reachable: Array[Vector2i] = []
	var visited := {}  # Stores lowest cost to reach each cell {pos: cost}
	var queue = []     # Array of {pos: Vector2i, cost: int}
	
	queue.append({pos = start, cost = 0})
	visited[start] = 0
	
	while not queue.is_empty():
		# Process lowest cost first (Dijkstra's algorithm)
		queue.sort_custom(func(a, b): return a.cost < b.cost)
		var current = queue.pop_front()
		
		reachable.append(current.pos)
		
		# Check all four directions
		for dir in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next_pos = current.pos + dir
			if is_raider:
				next_pos.x = posmod(next_pos.x, map_size.x)
			
			if not _in_bounds(next_pos):
				continue
				
			# Skip if occupied by visible enemy of same type
			if is_visibly_occupied(next_pos, mover):
				continue
				
			# Get terrain cost for this tile
			var terrain = get_terrain_at(next_pos)
			var move_cost = get_movement_cost(mover.unit_type, terrain)
			var new_cost = current.cost + move_cost
			
			# Only add if within movement budget and better than previous path
			if new_cost <= movement_points and (not visited.has(next_pos) or new_cost < visited[next_pos]):
				visited[next_pos] = new_cost
				queue.append({pos = next_pos, cost = new_cost})
	
	return reachable

func show_ambush_effect(unit_pos: Vector2):
	var exclaim = Sprite2D.new()
	exclaim.texture = preload("res://art/ui/Exclamation.png")

	# Place slightly above the unit
	exclaim.position = unit_pos + Vector2(0, -32)
	exclaim.scale = Vector2(.06, .06)  # static size
	add_child(exclaim)

	var tween = create_tween()

	# Let it linger above the unit
	tween.tween_interval(1.0)

	# Fade out smoothly
	tween.tween_property(exclaim, "modulate:a", 0.0, 0.4)
	tween.tween_callback(func(): exclaim.queue_free())

func create_movement_arrow():
	if movement_arrow:
		movement_arrow.queue_free()

	movement_arrow = Line2D.new()
	movement_arrow.width = 4
	movement_arrow.default_color = Color(1, 1, 1, 0.9)
	movement_arrow.z_index = 10
	add_child(movement_arrow)

func get_terrain_at(pos: Vector2i) -> String:
	if not _in_bounds(pos):
		return "PLAINS"  # Default terrain
	
	# First check TerrainFeatures layer (mountains, forests, etc.)
	var feature_data = $MapLayer/TerrainFeatures.get_cell_tile_data(0, pos)
	if feature_data:
		var terrain = feature_data.get_custom_data("terrain_type")
		if terrain != "":
			return terrain

	return "PLAINS"  # Default if no terrain specified

func get_movement_cost(unit_type: String, terrain: String) -> int:
	if unit_type in UNIT_TERRAIN_COSTS and terrain in UNIT_TERRAIN_COSTS[unit_type]:
		return UNIT_TERRAIN_COSTS[unit_type][terrain]
	return 99  # Cannot move (default for unknown combinations)

### ========================== FOG OF WAR ========================== ###

func update_active_layers():
	active_overlay = raider_range_overlay if raider_view_enabled else standard_overlay
	active_units = $RaiderUnits if raider_view_enabled else $Units
	active_fog_tilemap = raider_fog_tilemap if raider_view_enabled else fog_tilemap

func update_fog_of_war():
	for x in range(0, map_size.x + 1):
		for y in range(0, map_size.y + 1):
			var pos= Vector2i(x,y)
			raider_map.set_cell(0, pos, 1, Vector2.ZERO)
			raider_fog_tilemap.set_cell(0, pos, 0, Vector2.ZERO)
			fog_tilemap.set_cell(0, pos, 0, Vector2.ZERO)

	raider_visible_tiles.clear()
	mapunit_visible_tiles.clear()
	
	for unit in all_units:
		if unit.team == 1:
			var center = unit.grid_position
			var vision = unit.vision_range
			for x in range(-vision, vision + 1):
				for y in range(-vision, vision + 1):
					var pos = center + Vector2i(x, y)
					if abs(x) + abs(y) <= vision:
						if unit.is_raider():
							var wpos = Vector2i(posmod(pos.x, map_size.x),pos.y)
							raider_fog_tilemap.set_cell(0, wpos, -1)
							fog_tilemap.set_cell(0, wpos, -1)
							raider_map.set_cell(0, wpos, -1)
							raider_visible_tiles.append(wpos)
							raider_fog_tilemap.set_cell(0, pos, -1)
							fog_tilemap.set_cell(0, pos, -1)
							raider_map.set_cell(0, pos, -1)
							raider_visible_tiles.append(pos)
						else:
							fog_tilemap.set_cell(0, pos, -1)
							mapunit_visible_tiles.append(pos)
	
	all_visible_tiles = raider_visible_tiles + mapunit_visible_tiles
	

	for unit in all_units:
		if unit.team == 2:
			if unit.is_raider():
				# Marked raiders are always visible, others only when in raider vision
				unit.visible = (unit.marked_turns > 0) or (unit.grid_position in raider_visible_tiles and raider_view_enabled)
			else:
				# Marked units are always visible, others only when in vision
				unit.visible = (unit.marked_turns > 0) or (unit.grid_position in all_visible_tiles)

	for unit in $Units.get_children():
		if unit.team == 1:
			if raider_view_enabled:
				if unit.grid_position in raider_visible_tiles:
					unit.modulate.a = 0.4
					unit.visible = true
				else:
					unit.visible = false
			else:
				unit.modulate.a = 1.0
				unit.visible = true
		else:
			if raider_view_enabled:
				if unit.grid_position in raider_visible_tiles:
					unit.modulate.a = 0.4
					unit.visible = true
				else:
					unit.visible = false
			else:
				unit.modulate.a = 1.0
				unit.visible = unit.grid_position in all_visible_tiles

		# Handle marked units - they stay visible even if not in vision
	for unit in all_units:
		if unit.team == 2 and unit.marked_turns > 0:
			var pos = unit.grid_position
			fog_tilemap.set_cell(0, pos, -1)
			raider_fog_tilemap.set_cell(0, pos, -1)
			raider_map.set_cell(0, pos, -1)
			unit.visible = true
			if unit.is_raider():
				raider_fog_tilemap.set_cell(0, pos, -1)
				raider_map.set_cell(0, pos, -1)

func get_hidden_enemy_at(pos: Vector2i, my_team: int, my_is_raider: bool) -> MapUnit:
	for unit in all_units:
		if unit.grid_position == pos and unit.team != my_team:
			if not unit.visible:
				# Only ambush if they are the same type
				if unit.is_raider() == my_is_raider:
					return unit
	return null

### ========================== TURN MANAGEMENT ========================== ###

func start_turn(team: int):
	update_active_layers()
	update_fog_of_war()
	current_player_team = team

	# Reset income
	team1_income = 0
	team2_income = 0

	# Recalculate income fresh
	for b in $MapLayer/Buildings.get_children():
		if b.team == 1:
			team1_income += b.income_per_turn
		elif b.team == 2:
			team2_income += b.income_per_turn

	# Add funds for the active team
	if current_player_team == 1:
		team1_funds += team1_income
		turn += 1
	elif current_player_team == 2:
		team2_funds += team2_income
		# IA: Planificar producción al inicio del turno
		if team == 2:
			ai_plan_production()

	hud.update_income_funds()

	# Handle AI / player setup
	if team == 2:
		is_ai_processing = true
		hud.set_end_turn_enabled(false)
		ai_units = get_ai_units()
		# Ejecutar producción primero, luego movimiento
		await ai_execute_production()
		ai_timer.start(0.8)
	else:
		is_ai_processing = false
		hud.set_end_turn_enabled(true)
		for unit in active_units.get_children():
			if unit.team == team:
				unit.current_state = MapUnit.UnitState.UNSELECTED
				unit.update_visual_state()

func end_turn():
	update_active_layers()

	# Decrement marked turns
	for unit in all_units:
		if unit.marked_turns > 0:
			unit.marked_turns -= 1

	# Switch turn here (not in start_turn)
	current_player_team = 2 if current_player_team == 1 else 1

	# Reset units for next player
	for unit in all_units:
		if unit.team == current_player_team:
			unit.current_state = MapUnit.UnitState.UNSELECTED
			unit.update_visual_state()

	start_turn(current_player_team)
	update_fog_of_war()

### ========================== PLAYER INPUT / UI ========================== ###

func _ready():
	hud.visible = true
	update_active_layers()
	update_fog_of_war()
	for unit in $RaiderUnits.get_children():
		unit.visible = false
	$RaiderLayer.visible = false
	hud.end_turn_requested.connect(end_turn)
	ai_timer = Timer.new()
	add_child(ai_timer)
	ai_timer.timeout.connect(_on_ai_turn)
	ai_timer.one_shot = true
	astar.region = Rect2i(Vector2i(0, 0), map_size) # same size as your map
	astar.cell_size = Vector2(32, 32) # your tile size
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.update()
	astar_raider.clear()
	astar_raider.region = Rect2i(Vector2i(-map_size.x, 0),Vector2i(map_size.x * 3, map_size.y))
	astar_raider.cell_size = Vector2(32, 32)
	astar_raider.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar_raider.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar_raider.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar_raider.update()
	team1_income = 0
	team2_income = 0
	for b in $MapLayer/Buildings.get_children():
		b.ownership_changed.connect(_on_building_ownership_changed)
		b.production_menu_opened.connect(camera2d._on_production_menu_opened)
		b.production_menu_closed.connect(camera2d._on_production_menu_closed)
		if b.team == 1 and current_player_team == 1:
			team1_income += b.income_per_turn
		elif b.team == 2 and current_player_team == 2:
			team2_income += b.income_per_turn
	if current_player_team == 1:
		team1_funds += team1_income
	elif current_player_team == 2:
		team2_funds += team2_income
	hud.update_income_funds()

	# Configurar menú de pausa
	#pause_menu_instance = pause_menu.instantiate()
	#add_child(pause_menu_instance)
	pause_menu.resume_game.connect(_on_resume_game)
	pause_menu.exit_game.connect(_on_exit_game)
	
	# Asegurar que InputMap tiene la acción ESC
	if not InputMap.has_action("ui_cancel"):
		var event = InputEventKey.new()
		event.keycode = KEY_ESCAPE
		InputMap.add_action("ui_cancel")
		InputMap.action_add_event("ui_cancel", event)

func _on_resume_game():
	input_locked = false
	update_cursor_visibility()

func _on_exit_game():
	get_tree().quit()

func save_game(slot: int, save_name: String = ""):
	var save_data = {
		"name": save_name if save_name != "" else "Turno %d" % current_turn,
		"current_turn": current_turn,
		"current_player_team": current_player_team,
		"team1_funds": team1_funds,
		"team2_funds": team2_funds,
		"team1_income": team1_income,
		"team2_income": team2_income,
		"raider_view_enabled": raider_view_enabled,
		"units": [],
		"buildings": [],
		"raider_visible_tiles": raider_visible_tiles,
		"mapunit_visible_tiles": mapunit_visible_tiles
	}
	
	# Guardar unidades
	for unit in all_units:
		var unit_data = {
			"type": unit.unit_type,
			"position": [unit.grid_position.x, unit.grid_position.y],
			"health": unit.health,
			"team": unit.team,
			"state": unit.current_state,
			"movement_range": unit.movement_range,
			"attack": unit.attack,
			"defense": unit.defense,
			"attack_range": unit.attack_range,
			"vision_range": unit.vision_range,
			"marked_turns": unit.marked_turns,
			"is_raider": unit.is_raider(),
			"scene_path": unit.get_scene_file_path(),
			"visibility": unit.visible
		}
		save_data["units"].append(unit_data)
	
	# Guardar edificios
	for building in $MapLayer/Buildings.get_children():
		var building_data = {
			"type": building.building_type,
			"position": [building.building_position.x, building.building_position.y],
			"team": building.team,
			"capture_points": building.capture_points,
			"max_capture_points": building.max_capture_points,
			"income_per_turn": building.income_per_turn,
			"can_produce_units": building.can_produce_units
		}
		save_data["buildings"].append(building_data)
	
	# Guardar archivo en slot
	var path = "user://save_slot_%d.save" % slot
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_var(save_data)
		file.close()
	else:
		pass

func load_game(slot: int):
	var path = "user://save_slot_%d.save" % slot
	if not FileAccess.file_exists(path):
		return
	
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	
	var save_data = file.get_var()
	file.close()
	
	# Restaurar estado del juego
	current_turn = save_data["current_turn"]
	current_player_team = save_data["current_player_team"]
	team1_funds = save_data["team1_funds"]
	team2_funds = save_data["team2_funds"]
	team1_income = save_data["team1_income"]
	team2_income = save_data["team2_income"]
	raider_view_enabled = save_data["raider_view_enabled"]
	raider_visible_tiles = save_data["raider_visible_tiles"]
	mapunit_visible_tiles = save_data["mapunit_visible_tiles"]
	
	# Limpiar unidades existentes
	for unit in all_units:
		unit.queue_free()
	all_units.clear()
	
	# Cargar unidades
	for unit_data in save_data["units"]:
		var unit_scene = load(unit_data["scene_path"])
		var unit_instance = unit_scene.instantiate()
		
		if unit_data["is_raider"]:
			$RaiderUnits.add_child(unit_instance)
		else:
			$Units.add_child(unit_instance)
		
		unit_instance.grid_position = Vector2i(unit_data["position"][0], unit_data["position"][1])
		unit_instance.health = unit_data["health"]
		unit_instance.team = unit_data["team"]
		unit_instance.current_state = unit_data["state"]
		unit_instance.movement_range = unit_data["movement_range"]
		unit_instance.attack = unit_data["attack"]
		unit_instance.defense = unit_data["defense"]
		unit_instance.attack_range = unit_data["attack_range"]
		unit_instance.vision_range = unit_data["vision_range"]
		unit_instance.marked_turns = unit_data["marked_turns"]
		unit_instance.visible = unit_data["visibility"]
		unit_instance.update_visual_state()
		
		all_units.append(unit_instance)
	
	# Cargar edificios
	for building_data in save_data["buildings"]:
		var building_pos = Vector2i(building_data["position"][0], building_data["position"][1])
		
		for building in $MapLayer/Buildings.get_children():
			if Vector2i(building.position / 32) == building_pos:
				building.team = building_data["team"]
				building.capture_points = building_data["capture_points"]
				building.max_capture_points = building_data["max_capture_points"]
				building.income_per_turn = building_data["income_per_turn"]
				building.can_produce_units = building_data["can_produce_units"]
				building.update_visual()
				break
	
	# Actualizar UI y estado del juego
	hud.update_income_funds()
	update_fog_of_war()
	update_active_layers()

func _on_building_ownership_changed(_building: Building):
	team1_income = 0
	team2_income = 0
	for b in $MapLayer/Buildings.get_children():
		if b.team == 1:
			team1_income += b.income_per_turn
		elif b.team == 2:
			team2_income += b.income_per_turn
	hud.update_income_funds()

func _input(event):
	if event.is_action_pressed("Tab"):
		if not is_menu_open:
			toggle_raider_view()

func _unhandled_input(event):
	if is_ai_processing:
		return 

	if input_locked:
		return

	if event.is_action_pressed("LMClick"):
		if is_menu_open:
			return

		# Clear the traced cursor path
		if cursor_path:
			cursor_path.clear()

		# Reset tracing flag
		is_tracing_path = false

		# Reset current unit selection if needed
		#selected_unit = null

		var mouse_pos = get_global_mouse_position()
		var grid_pos = Vector2i(mouse_pos / 32)
		
		if mark_mode:
			try_mark(grid_pos)
			return
		
		if attack_mode:
			try_attack(grid_pos)
		else:
			for unit in active_units.get_children():
				if unit.current_state == MapUnit.UnitState.SELECTED:
					var final_path: Array[Vector2i] = []
					var use_wrapped_movement = false
					if is_position_free(grid_pos, unit, true):
						# GET THE PATH FROM THE LINE2D (what's actually shown)
						if movement_arrow and movement_arrow.get_point_count() > 1:
							# Convert Line2D points back to grid positions
							for i in range(movement_arrow.get_point_count()):
								var world_pos = movement_arrow.get_point_position(i)
								var grid_pos_from_line = Vector2i(world_pos / 32)
								final_path.append(grid_pos_from_line)
						else:
							# Fallback to direct click if no arrow path
							var reachable = get_reachable_cells(unit.grid_position, unit.movement_range, unit, unit.is_raider())
							if grid_pos in reachable:
								update_astar_raider(unit.grid_position, grid_pos)
								final_path = get_wrapped_tile_path(unit.grid_position, grid_pos)
								use_wrapped_movement = true
						if not final_path.is_empty():
							var movement_path = final_path.duplicate()
							if use_wrapped_movement:
								move_unit_along_wrapped_path(unit, movement_path)
							else:
								move_unit_along_path(unit, movement_path)
							is_tracing_path = false
							cursor_path.clear()
							if movement_arrow:
								movement_arrow.clear_points()
					if unit.grid_position == grid_pos:
						show_action_menu(unit)
						break

	if event.is_action_pressed("RMClick"):
		if attack_mode or mark_mode:
			for unit in active_units.get_children():
				if unit.current_state == MapUnit.UnitState.SELECTED:
					unit.grid_position = unit.original_position
					end_attack_mode()
					end_mark_mode()
					unit.select()
					return
		else:
			if is_menu_open:
				_on_cancel_pressed()
			else:
				# NUEVO: Mostrar rango de ataque al hacer right-click en cualquier unidad
				var mouse_pos = get_global_mouse_position()
				var grid_pos = Vector2i(mouse_pos / 32)
				
				# Buscar unidad bajo el cursor
				var clicked_unit: MapUnit = null
				for unit in all_units:
					if unit.grid_position == grid_pos and unit.visible and unit.current_state != unit.UnitState.SELECTED:
						clicked_unit = unit
						break
				
				if clicked_unit:
					# Mostrar rango de ataque de esta unidad
					show_attack_range(clicked_unit)
				else:
					# Comportamiento original: deseleccionar unidades
					for unit in active_units.get_children():
						if unit.current_state != MapUnit.UnitState.MOVED:
							unit.deselect()
							active_overlay.clear()
					close_action_menu()
					hide_attack_range()  # Ocultar rango si se hace click en vacío

func update_movement_arrow(unit: MapUnit, cursor_pos: Vector2i):
	if not movement_arrow:
		create_movement_arrow()

	var unit_pos = unit.grid_position

	if is_move_wrapped(unit_pos, cursor_pos, unit):
		movement_arrow.clear_points()
		return

	# Check if a tile is reachable at a given grid position
	if active_overlay.get_cell_source_id(0, cursor_pos) == -1:
		cursor_path = []
		movement_arrow.clear_points()
		is_tracing_path = false
		is_collapsed_to_astar = false
		return

	# Start path if not tracing
	if not is_tracing_path:
		if cursor_pos != unit_pos:
			is_tracing_path = true
			cursor_path = [unit_pos]
			is_collapsed_to_astar = false
		else:
			movement_arrow.clear_points()
			return

	# Handle collapsed-to-A* mode
	if is_collapsed_to_astar:
		var last_astar_pos = cursor_path.back() if not cursor_path.is_empty() else unit_pos

		if (cursor_pos - last_astar_pos).abs().x + (cursor_pos - last_astar_pos).abs().y == 1:
			# Try to continue manually
			var test_manual_path = cursor_path.duplicate()
			test_manual_path.append(cursor_pos)
			var test_cost = calculate_path_cost(test_manual_path, unit)
			if test_cost <= unit.movement_range:
				is_collapsed_to_astar = false
				cursor_path = test_manual_path
			else:
				update_astar(unit)
				cursor_path = get_tile_path(unit_pos, cursor_pos)
		else:
			update_astar(unit)
			cursor_path = get_tile_path(unit_pos, cursor_pos)

	# Handle manual mode
	else:
		if cursor_pos in cursor_path:
			var index = cursor_path.find(cursor_pos)
			cursor_path = cursor_path.slice(0, index + 1)
		else:
			var last_pos = cursor_path.back()
			if (cursor_pos - last_pos).abs().x + (cursor_pos - last_pos).abs().y == 1:
				cursor_path.append(cursor_pos)
				var current_cost = calculate_path_cost(cursor_path, unit)
				if current_cost > unit.movement_range:
					is_collapsed_to_astar = true
			else:
				is_collapsed_to_astar = true
				update_astar(unit)
				cursor_path = get_tile_path(unit_pos, cursor_pos)

	# Calculate final path cost
	var final_cost = calculate_path_cost(cursor_path, unit)
	var final_path = cursor_path.duplicate()
	if final_cost > unit.movement_range:
		final_path = get_valid_subpath_by_cost(final_path, unit.movement_range, unit)

	# Draw the line
	movement_arrow.clear_points()
	for tile in final_path:
		var world_pos = Vector2(tile * 32) + Vector2(16, 16)
		movement_arrow.add_point(world_pos)

func calculate_path_cost(path: Array[Vector2i], unit: MapUnit) -> int:
	var total_cost = 0
	for i in range(1, path.size()):
		var to_pos = path[i]
		var terrain = get_terrain_at(to_pos)
		var segment_cost = get_movement_cost(unit.unit_type, terrain)
		total_cost += segment_cost
	return total_cost

func get_valid_subpath_by_cost(full_path: Array[Vector2i], max_cost: int, unit: MapUnit) -> Array[Vector2i]:
	var result: Array[Vector2i] = [full_path[0]]
	var current_cost = 0
	
	for i in range(1, full_path.size()):
		var terrain = get_terrain_at(full_path[i])
		var segment_cost = get_movement_cost(unit.unit_type, terrain)
		
		if current_cost + segment_cost <= max_cost:
			result.append(full_path[i])
			current_cost += segment_cost
		else:
			break
	
	return result

func calculate_line2d_length(line: Line2D) -> float:
	var length = 0.0
	if line.get_point_count() < 2:
		return length
	
	for i in range(line.get_point_count() - 1):
		length += line.get_point_position(i).distance_to(line.get_point_position(i + 1))
	
	return length

func get_valid_subpath(full_path: Array[Vector2i], max_length: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = [full_path[0]]
	var current_length = 0
	
	for i in range(1, full_path.size()):
		var segment_length = abs(full_path[i].x - full_path[i-1].x) + abs(full_path[i].y - full_path[i-1].y)
		if current_length + segment_length <= max_length:
			result.append(full_path[i])
			current_length += segment_length
		else:
			break
	
	return result

func calculate_path_length(path: Array[Vector2i]) -> int:
	var length = 0
	for i in range(path.size() - 1):
		length += abs(path[i].x - path[i+1].x) + abs(path[i].y - path[i+1].y)
	return length

func find_closest_reachable_position(target: Vector2i, reachable: Array[Vector2i]) -> Vector2i:
	var closest = target
	var min_distance = INF
	
	for pos in reachable:
		var distance = abs(target.x - pos.x) + abs(target.y - pos.y)
		if distance < min_distance:
			min_distance = distance
			closest = pos
	
	return closest

func show_movement_range(center: Vector2i, mover: MapUnit):
	update_active_layers()
	active_overlay.clear()
	
	# Use movement points instead of simple radius!
	var reachable = get_reachable_cells(center, mover.movement_range, mover, mover.is_raider())
	
	for pos in reachable:
		active_overlay.set_cell(0, pos, 1, Vector2i.ZERO)

func toggle_raider_view():
	raider_view_enabled = !raider_view_enabled
	update_active_layers()
	update_fog_of_war()

	active_overlay.clear()
	$MapLayer/FogOfWar.visible = not raider_view_enabled
	$MapLayer/MoveRangeOverlay.visible = not raider_view_enabled
	$RaiderLayer.visible = raider_view_enabled

	for unit in $RaiderUnits.get_children():
		if unit.team == 1:
			unit.visible = raider_view_enabled
		else:
			if raider_view_enabled:
				unit.visible = unit.grid_position in raider_visible_tiles
			else:
				unit.visible = false

	for unit in active_units.get_children():
		if unit.current_state == MapUnit.UnitState.SELECTED:
			unit.deselect()
			hud.hide_unit_info()
	active_overlay.clear()

func show_action_menu(unit: MapUnit):
	update_active_layers()
	close_action_menu()

	var unit_position = unit.global_position
	var half_map_width: float = (map_size.x * 32) / 2.0
	var half_map_height: float = (map_size.y * 32) / 2.0
	var building_underneath = get_building_at(unit.grid_position)

	action_menu_instance = action_menu.instantiate()
	add_child(action_menu_instance)
	if unit_position.x >= half_map_width and unit_position.y >= half_map_height:
		action_menu_instance.position = unit_position + Vector2(-75, -32)
	elif unit_position.x < half_map_width and unit_position.y > half_map_height:
		action_menu_instance.position = unit_position + Vector2(25, -32)
	elif unit_position.x <= half_map_width and unit_position.y <= half_map_height:
		action_menu_instance.position = unit_position + Vector2(25, 0)
	elif unit_position.x > half_map_width and unit_position.y < half_map_height:
		action_menu_instance.position = unit_position + Vector2(-75, 0)

	var cancel_btn = action_menu_instance.get_node("VBoxContainer/Cancel")
	var move_btn = action_menu_instance.get_node("VBoxContainer/Move")
	var attack_btn = action_menu_instance.get_node("VBoxContainer/Attack")
	var mark_btn = action_menu_instance.get_node("VBoxContainer/Mark")  # Add this line
	var capture_btn = action_menu_instance.get_node("VBoxContainer/Capture")
	var has_targets = false
	var has_mark_targets = false

	for other in active_units.get_children():
		# Only consider visible enemies
		if other.visible:
			if unit.can_attack(other):
				has_targets = true
			# Check if unit can mark (only for raiders)
			
	for other in all_units:
		if unit is Raider_Unit and unit.can_mark(other):
			has_mark_targets = true

	attack_btn.visible = has_targets
	mark_btn.visible = has_mark_targets and unit is Raider_Unit  # Only show for raiders
	capture_btn.visible = unit.unit_type == "Infantry" and building_underneath != null and building_underneath.team != unit.team

	attack_btn.pressed.connect(_on_attack_pressed.bind())
	mark_btn.pressed.connect(_on_mark_pressed.bind())  # Connect mark button
	cancel_btn.pressed.connect(_on_cancel_pressed)
	move_btn.pressed.connect(_on_move_confirmed)
	capture_btn.pressed.connect(_on_capture_pressed.bind(unit, building_underneath))

	is_menu_open = true
	update_cursor_visibility()

func close_action_menu():
	if action_menu_instance:
		action_menu_instance.queue_free()
		action_menu_instance = null
	is_menu_open = false
	update_cursor_visibility()
	if movement_arrow:
		movement_arrow.clear_points()
		is_tracing_path = false
		cursor_path.clear()

func _on_cancel_pressed():
	for unit in active_units.get_children():
		if unit.current_state == MapUnit.UnitState.SELECTED:
			# Teleport back
			unit.grid_position = unit.original_position
			unit.global_position = Vector2(unit.grid_position * 32) + Vector2(16, 16)
			#unit.current_state = MapUnit.UnitState.UNSELECTED
			unit.select()
			unit.update_visual_state()
			break
	if movement_arrow:
		movement_arrow.clear_points()
		is_tracing_path = false
		cursor_path.clear()
	close_action_menu()
	#active_overlay.clear()

func _on_mark_pressed():
	close_action_menu()
	show_mark_options(selected_unit)

func show_mark_options(unit: Raider_Unit):
	update_active_layers()
	selected_unit = unit
	mark_mode = true
	potential_targets.clear()
	for target in all_units:
		# Only **visible units** can be targeted
		if target.visible and unit.can_mark(target):
			potential_targets.append(target)
			target.get_node("Sprite2D").modulate = Color(2, 0.5, 0.5)

func _on_move_confirmed():
	update_active_layers()
	close_action_menu()
	potential_targets.clear()
	# Limpiar colores anteriores de todas las unidades enemigas
	for enemy in all_units:
		if enemy.team != 1:
			enemy.update_visual_state() 
	for unit in active_units.get_children():
		if unit.current_state == MapUnit.UnitState.SELECTED:
			unit.current_state = MapUnit.UnitState.MOVED
			unit.update_visual_state()
			break
	active_overlay.clear()
	update_fog_of_war()

func _on_attack_pressed():
	close_action_menu()
	show_attack_options(selected_unit)

func get_building_at(pos: Vector2i) -> Building:
	for b in $MapLayer/Buildings.get_children():
		if Vector2i(b.position / 32) == pos:
			return b
	return null

func _on_capture_pressed(unit: MapUnit, building: Building):
	close_action_menu()
	if building:
		@warning_ignore("narrowing_conversion", "integer_division")
		building.capture(unit, unit.health /10, unit.team) # ej. 10 HP = 10 puntos de captura
	_on_move_confirmed()

func get_reachable_attack_targets(unit: MapUnit) -> Array[MapUnit]:
	var reachable_targets: Array[MapUnit] = []
	
	# Primero obtener todas las celdas alcanzables
	var reachable_cells = get_reachable_cells(unit.grid_position, unit.movement_range, unit, unit.is_raider())
	
	# Para cada celda alcanzable, verificar qué objetivos se pueden atacar desde allí
	for cell in reachable_cells:
		# Verificar todos los enemigos visibles
		for enemy in all_units:
			if (enemy.visible and 
				enemy.team != unit.team and 
				enemy.is_raider() == unit.is_raider()):  # Mismo tipo de unidad
				
				# Calcular distancia desde esta celda al enemigo
				var distance = abs(cell.x - enemy.grid_position.x) + abs(cell.y - enemy.grid_position.y)
				
				# Si está en rango de ataque y no está ya en la lista, añadirlo
				if distance <= unit.attack_range and enemy not in reachable_targets:
					reachable_targets.append(enemy)
	
	return reachable_targets

func show_possible_attack_targets(unit: MapUnit):
	potential_targets.clear()
	
	# Limpiar colores anteriores de todas las unidades enemigas
	for enemy in all_units:
		if enemy.team != unit.team:
			enemy.update_visual_state()  # Restaurar color normal
	
	# Encontrar TODOS los objetivos alcanzables (incluyendo después de movimiento)
	var attackable_targets = get_reachable_attack_targets(unit)
	
	# Resaltar objetivos posibles
	for target in attackable_targets:
		potential_targets.append(target)
		target.get_node("Sprite2D").modulate = Color(2, 0.5, 0.5)  # Rojo para objetivos de ataque
	
	# También mostrar objetivos que se pueden atacar desde la posición actual (color diferente)
	for target in all_units:
		if (target.visible and 
			target.team != unit.team and 
			unit.can_attack(target) and 
			target not in potential_targets):  # Solo si no está ya en la lista
			
			# Color diferente para objetivos alcanzables desde posición actual
			target.get_node("Sprite2D").modulate = Color(2, 0.8, 0.8)  # Rosa claro
			potential_targets.append(target)

func get_attackable_tiles(unit: MapUnit) -> Array[Vector2i]:
	var attackable_tiles: Array[Vector2i] = []
	
	# 1. Obtener todas las celdas alcanzables con movimiento
	var reachable_cells = get_reachable_cells(unit.grid_position, unit.movement_range, unit, unit.is_raider())
	
	# 2. Para cada celda alcanzable, calcular el rango de ataque desde allí
	for move_cell in reachable_cells:
		for x in range(-unit.attack_range, unit.attack_range + 1):
			for y in range(-unit.attack_range, unit.attack_range + 1):
				var attack_pos = move_cell + Vector2i(x, y)
				
				# Verificar si está dentro del rango de ataque (patrón diamante)
				if (abs(x) + abs(y)) <= unit.attack_range and _in_bounds(attack_pos):
					# Añadir si no está ya en la lista
					if attack_pos not in attackable_tiles:
						attackable_tiles.append(attack_pos)
	
	return attackable_tiles

func show_attack_range(unit: MapUnit):
	hide_attack_range()
	
	# Crear overlay si no existe
	if not attack_range_overlay:
		attack_range_overlay = TileMap.new()
		attack_range_overlay.tile_set = standard_overlay.tile_set  # Usar mismo tileset
		attack_range_overlay.z_index = 5
		add_child(attack_range_overlay)
	
	# Calcular TODAS las tiles que podrían ser atacadas después de moverse
	var attackable_tiles = get_attackable_tiles(unit)
	
	# Mostrar el rango de ataque potencial
	for tile_pos in attackable_tiles:
		attack_range_overlay.set_cell(0, tile_pos, 1, Vector2i.ZERO)
		#attack_range_overlay.set_cell_modulate(0, tile_pos, Color(1, 0, 0, 0.4))  # Rojo transparente
	
	showing_attack_range = true
	current_attack_range_unit = unit

func hide_attack_range():
	if attack_range_overlay:
		attack_range_overlay.clear()
	showing_attack_range = false
	current_attack_range_unit = null

func show_attack_options(unit: MapUnit):
	update_active_layers()
	selected_unit = unit
	attack_mode = true
	potential_targets.clear()
	for target in active_units.get_children():
		# Only **visible units** can be targeted
		if target.visible and unit.can_attack(target):
			potential_targets.append(target)
			target.get_node("Sprite2D").modulate = Color(2, 0.5, 0.5)

func try_attack(grid_pos: Vector2i):
	update_active_layers()
	for unit in active_units.get_children():
		if unit.grid_position == grid_pos && selected_unit.can_attack(unit):
			selected_unit.attacking(unit)
			end_attack_mode()
			active_overlay.clear()
			return

func try_mark(grid_pos: Vector2i):
	update_active_layers()
	for unit in all_units:
		if unit.grid_position == grid_pos && selected_unit.can_mark(unit) && selected_unit.is_raider():
			selected_unit.marking(unit)
			end_mark_mode()
			active_overlay.clear()
			return

func end_mark_mode():
	update_active_layers()
	mark_mode = false
	for unit in active_units.get_children():
		if unit in potential_targets or unit.modulate == Color(1, 0.5, 0.5):
			unit.update_visual_state()
	potential_targets.clear()
	update_fog_of_war()

func end_attack_mode():
	update_active_layers()
	attack_mode = false
	for unit in active_units.get_children():
		if unit in potential_targets or unit.modulate == Color(2, 0.5, 0.5):
			unit.update_visual_state()
	potential_targets.clear()
	update_fog_of_war()

func _in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.x < map_size.x and p.y >= 0 and p.y < map_size.y

func _process(_delta):
	var mouse_p = get_global_mouse_position()
	var cursor_grid_pos = Vector2i(floor(mouse_p.x / 32.0), floor(mouse_p.y / 32.0))
	cursor_highlight.clear()
	
	if _in_bounds(cursor_grid_pos):
		cursor_highlight.set_cell(0, cursor_grid_pos, 0, Vector2i.ZERO)
		
		# Show movement arrow when a unit is selected
		if not attack_mode and not is_menu_open and not input_locked and not mark_mode:
			for unit in active_units.get_children():
				if unit.current_state == MapUnit.UnitState.SELECTED:
					update_movement_arrow(unit, cursor_grid_pos)
					break  # Only show arrow for one selected unit
	else:
		cursor_highlight.clear()

func update_cursor_visibility():
	cursor_highlight.visible = not is_menu_open


### ========================== AI LOGIC ========================== ###

func _on_ai_turn() -> void:
	update_active_layers()

	if ai_units.is_empty():
		is_ai_processing = false
		hud.set_end_turn_enabled(true)
		end_turn()
		return

	var current_unit = ai_units.pop_back()
	await ai_move_unit(current_unit)
	_on_ai_turn()

func get_ai_units() -> Array[MapUnit]:
	update_active_layers()
	var units: Array[MapUnit] = []
	for unit in $Units.get_children():
		if unit.team == 2 and unit.health > 0:
			units.append(unit)
	for unit in $RaiderUnits.get_children():
		if unit.team == 2 and unit.health > 0:
			units.append(unit)
	return units

func ai_move_unit(unit: MapUnit) -> void:
	if is_unit_stuck(unit):
		ai_move_away_from_stuck(unit)
		unit.current_state = MapUnit.UnitState.MOVED
		unit.update_visual_state()
		return


	# STEP 1: Get reachable cells considering terrain
	var reachable_cells = get_reachable_cells(
		unit.grid_position,
		unit.movement_range,
		unit,
		unit.is_raider()
	)
	
	# STEP 2: Check if we can capture a building from current position
	var building_to_capture = get_building_at(unit.grid_position)
	if building_to_capture and building_to_capture.team != 2 and unit.unit_type == "Infantry":
		await ai_capture_building(unit, building_to_capture)
		unit.current_state = MapUnit.UnitState.MOVED
		unit.update_visual_state()
		return
	
	# STEP 3: Find best action (including building capture)
	var best_choice = find_best_ai_action(unit, reachable_cells)
	
	# STEP 4: Execute movement
	if best_choice["move_pos"] != unit.grid_position and best_choice["score"] > -100:
		var path = get_path_to_cell(unit, best_choice["move_pos"])
		if not path.is_empty():
			var target_pos = path[min(path.size() - 1, unit.movement_range - 1)]
			
			if target_pos in reachable_cells and is_position_free(target_pos, unit, true, false):
				unit.grid_position = target_pos
				unit.global_position = Vector2(target_pos * 32) + Vector2(16, 16)
				
				update_fog_of_war()
				await get_tree().create_timer(0.3).timeout
				
				# Check if we reached a capturable building
				building_to_capture = get_building_at(unit.grid_position)
				if building_to_capture and building_to_capture.team != 2 and unit.unit_type == "Infantry":
					await ai_capture_building(unit, building_to_capture)
					unit.current_state = MapUnit.UnitState.MOVED
					unit.update_visual_state()
					return

	# STEP 5: Execute attack if possible
	if best_choice["attack_target"] != null and is_instance_valid(best_choice["attack_target"]):
		var target = best_choice["attack_target"]
		var distance_after_move = abs(unit.grid_position.x - target.grid_position.x) + abs(unit.grid_position.y - target.grid_position.y)
		
		if distance_after_move <= unit.attack_range:
			await ai_execute_attack(unit, target)

	# STEP 6: Mark unit as finished
	unit.current_state = MapUnit.UnitState.MOVED
	unit.update_visual_state()

func ai_capture_building(unit: MapUnit, building: Building) -> void:
	# Calculate capture points based on unit health
	var capture_points: int = floor(floor(unit.health) / 10)

	# Perform capture
	building.capture(unit, capture_points, unit.team)
	
	# Visual feedback
	if building.has_node("Sprite2D"):
		var sprite = building.get_node("Sprite2D")
		var original_color = sprite.modulate
		sprite.modulate = Color(1.5, 1.5, 1.0)  # Yellow flash for capture
		await get_tree().create_timer(0.3).timeout
		if is_instance_valid(sprite):
			sprite.modulate = original_color
	
	await get_tree().create_timer(0.3).timeout

func find_best_ai_action(unit: MapUnit, reachable_cells: Array[Vector2i]) -> Dictionary:
	var best_choice = {
		"move_pos": unit.grid_position,
		"attack_target": null,
		"score": -9999
	}
	
	# Get all potential targets
	var enemies = get_visible_enemies(unit)
	var capturable_buildings = get_capturable_buildings(unit)
	
	# If there are capturable buildings and unit is Infantry, prioritize them
	if not capturable_buildings.is_empty() and unit.unit_type == "Infantry":
		var building_choice = find_best_building_to_capture(unit, reachable_cells, capturable_buildings)
		if building_choice["score"] > best_choice["score"]:
			return building_choice
	
	# Evaluate enemy targets
	if not enemies.is_empty():
		for move_cell in reachable_cells:
			var score = evaluate_position_score(unit, move_cell, enemies, capturable_buildings)
			
			if score > best_choice["score"]:
				best_choice["move_pos"] = move_cell
				best_choice["score"] = score
				best_choice["attack_target"] = find_best_target_from_position(unit, move_cell, enemies)
	
	# If no good combat options, consider strategic movement
	if best_choice["score"] < 0 and not capturable_buildings.is_empty():
		return find_strategic_move(unit, reachable_cells, capturable_buildings)
	
	return best_choice

func get_capturable_buildings(unit: MapUnit) -> Array[Building]:
	var buildings: Array[Building] = []
	
	for building in $MapLayer/Buildings.get_children():
		if (building.team != 2 and  # Not owned by AI
			building.team != 0 and  # Not neutral (or include neutral if desired)
			unit.unit_type == "Infantry"):  # Only infantry can capture
			buildings.append(building)
	
	return buildings

func find_best_building_to_capture(unit: MapUnit, reachable_cells: Array[Vector2i], buildings: Array[Building]) -> Dictionary:
	var best_choice = {
		"move_pos": unit.grid_position,
		"attack_target": null,
		"score": -9999
	}
	
	for building in buildings:
		var building_pos = building.building_position
		
		# Find closest reachable position to the building
		var closest_position = find_closest_reachable_position(building_pos, reachable_cells)
		var distance_to_building = abs(closest_position.x - building_pos.x) + abs(closest_position.y - building_pos.y)
		
		# Score based on proximity and building value
		var score = 200 - distance_to_building * 10  # Base score for building capture
		
		# Add value based on building type
		match building.building_type:
			"HQ":
				score += 100  # High value target
			"City":
				score += 50
			"Factory":
				score += 60
			"Airport":
				score += 70
		
		if score > best_choice["score"]:
			best_choice["move_pos"] = closest_position
			best_choice["score"] = score
	
	return best_choice

func evaluate_position_score(unit: MapUnit, _position: Vector2i, enemies: Array[MapUnit], buildings: Array[Building]) -> float:
	var score = 0.0
	
	# Base score for moving forward
	score += _position.x * 0.1
	
	# Evaluate enemy threats and opportunities
	for enemy in enemies:
		var distance = abs(_position.x - enemy.grid_position.x) + abs(_position.y - enemy.grid_position.y)
		
		if distance <= unit.attack_range:
			score += 100 + (100 - enemy.health) * 0.5
		elif distance <= unit.attack_range + 2:
			score += 50 - distance * 2
		else:
			score -= distance * 0.1
	
	# Evaluate building capture opportunities
	for building in buildings:
		var building_pos = building.building_position
		var distance_to_building = abs(_position.x - building_pos.x) + abs(_position.y - building_pos.y)
		
		if distance_to_building == 0:  # On the building
			score += 150  # Very high score for being on a capturable building
		elif distance_to_building <= 2:  # Close to building
			score += 80 - distance_to_building * 10
	
	# Safety evaluation
	var nearby_enemies = 0
	for enemy in enemies:
		var dist = abs(_position.x - enemy.grid_position.x) + abs(_position.y - enemy.grid_position.y)
		if dist <= 2:
			nearby_enemies += 1
	
	if nearby_enemies > 1:
		score -= 30 * nearby_enemies
	
	# Terrain advantages
	var terrain = get_terrain_at(position)
	if terrain == "MOUNTAIN" or terrain == "FOREST":
		score += 10
	
	return score

func get_visible_enemies(unit: MapUnit) -> Array[MapUnit]:
	var enemies: Array[MapUnit] = []
	for u in all_units:
		if (u.team != unit.team and 
			u.visible and 
			u.is_raider() == unit.is_raider() and
			u.health > 0):
			enemies.append(u)
	return enemies

func find_best_target_from_position(unit: MapUnit, _position: Vector2i, enemies: Array[MapUnit]) -> MapUnit:
	var best_target = null
	var best_score = -9999
	
	for enemy in enemies:
		var distance = abs(_position.x - enemy.grid_position.x) + abs(_position.y - enemy.grid_position.y)
		
		if distance <= unit.attack_range:
			var score = calculate_attack_score(unit, enemy)
			if score > best_score:
				best_score = score
				best_target = enemy
	
	return best_target

func calculate_attack_score(attacker: MapUnit, defender: MapUnit) -> float:
	var score = 0.0
	
	# Damage potential
	var potential_damage = attacker.attack - defender.defense
	score += potential_damage * 10
	
	# Prefer killing blows
	if defender.health <= potential_damage:
		score += 50  # Kill bonus
	
	# Prefer weaker enemies
	score += (100 - defender.health) * 2
	
	# Prefer high-value targets (you can add unit type weights here)
	match defender.unit_type:
		"Infantry":
			score += 10
		"Raider":
			score += 20
		# Add more unit types as needed
	
	return score

func find_strategic_move(unit: MapUnit, reachable_cells: Array[Vector2i], buildings: Array[Building] = []) -> Dictionary:
	var best_pos = unit.grid_position
	var best_score = -9999
	
	# If there are buildings to capture, prioritize them
	if not buildings.is_empty() and unit.unit_type == "Infantry":
		var building_target = buildings[0]  # Start with first building
		var target_pos = building_target.building_position
		
		for cell in reachable_cells:
			var score = 0.0
			var dist_to_target = abs(cell.x - target_pos.x) + abs(cell.y - target_pos.y)
			score = 100 - dist_to_target  # Higher score for closer to building
			
			if score > best_score:
				best_score = score
				best_pos = cell
	else:
		# Default strategic movement
		var target_x = int(map_size.x * 0.75)  # 22 * 0.75 = 16.5 → 16
		var target_y : int = floor(map_size.y) / 2         # 15 ÷ 2 = 7
		var target_pos = Vector2i(target_x, target_y)
		
		for cell in reachable_cells:
			var score = 0.0
			var dist_to_target = abs(cell.x - target_pos.x) + abs(cell.y - target_pos.y)
			score -= dist_to_target
			
			# Vision bonus
			var vision_cells = 0
			for x in range(-unit.vision_range, unit.vision_range + 1):
				for y in range(-unit.vision_range, unit.vision_range + 1):
					if abs(x) + abs(y) <= unit.vision_range:
						var vis_pos = cell + Vector2i(x, y)
						if _in_bounds(vis_pos):
							vision_cells += 1
			
			score += vision_cells * 0.1
			
			if score > best_score:
				best_score = score
				best_pos = cell
	
	return {
		"move_pos": best_pos,
		"attack_target": null,
		"score": best_score
	}

func find_nearest_building(unit: MapUnit) -> Building:
	var nearest_building = null
	var min_distance = 9999
	
	for building in $MapLayer/Buildings.get_children():
		if building.team != 2:  # Not owned by AI
			var distance = abs(unit.grid_position.x - building.building_position.x) + abs(unit.grid_position.y - building.building_position.y)
			if distance < min_distance:
				min_distance = distance
				nearest_building = building
	
	return nearest_building

func get_path_to_cell(unit: MapUnit, target_cell: Vector2i):
	# Simple pathfinding toward target
	var path = []
	var current = unit.grid_position
	
	# Simple 4-directional pathfinding
	while current != target_cell and path.size() < unit.movement_range * 2:
		var dir = Vector2i(
			sign(target_cell.x - current.x),
			sign(target_cell.y - current.y)
		)
		
		# Prefer horizontal movement first
		var next_cell = current
		if dir.x != 0:
			next_cell = current + Vector2i(dir.x, 0)
		elif dir.y != 0:
			next_cell = current + Vector2i(0, dir.y)
		
		# Check if next cell is reachable
		var reachable = get_reachable_cells(unit.grid_position, unit.movement_range, unit, unit.is_raider())
		if next_cell in reachable:
			path.append(next_cell)
			current = next_cell
		else:
			break  # Can't move further
	
	return path

func ai_execute_attack(unit: MapUnit, target: MapUnit) -> void:
	# Damage calculation
	var damage = max(1, unit.attack - target.defense)
	target.health -= damage
	
	# Visual feedback
	if target.has_node("Sprite2D"):
		var sprite = target.get_node("Sprite2D")
		var original_color = sprite.modulate
		sprite.modulate = Color(2, 0.5, 0.5)
		await get_tree().create_timer(0.2).timeout
		if is_instance_valid(sprite):
			sprite.modulate = original_color
	
	# Check for death
	if target.health <= 0:
		all_units.erase(target)
		target.queue_free()
	
	await get_tree().create_timer(0.3).timeout

func ai_plan_production():
	ai_production_queue.clear()
	ai_production_budget = max(0, team2_funds - ai_minimum_balance)
	
	if ai_production_budget <= 0:
		return
	
	# Obtener edificios de producción de la IA
	ai_production_buildings = get_ai_production_buildings()
	
	if ai_production_buildings.is_empty():
		return
	
	# Evaluar necesidades y planificar producción
	var production_plan = ai_evaluate_production_needs()
	
	for plan in production_plan:
		if plan.cost <= ai_production_budget:
			ai_production_queue.append(plan)
			ai_production_budget -= plan.cost

func get_ai_production_buildings() -> Array[Building]:
	var buildings: Array[Building] = []
	
	for building in $MapLayer/Buildings.get_children():
		if building.team == 2 and building.can_produce_units:
			# Verificar que el edificio no esté ocupado
			var is_occupied = false
			for unit in all_units:
				if unit.grid_position == building.building_position and not unit.is_raider():
					is_occupied = true
					break
			
			if not is_occupied:
				buildings.append(building)
	
	return buildings

func ai_evaluate_production_needs() -> Array:
	var production_plans = []
	var enemy_strength = ai_calculate_enemy_strength()
	var ai_strength = ai_calculate_ai_strength()
	
	# Análisis de necesidades básicas
	var needs_infantry = true  # Siempre necesitamos infantería para capturar
	var needs_anti_tank = enemy_strength.vehicles > ai_strength.anti_vehicle
	var needs_vehicles = ai_strength.vehicles < enemy_strength.infantry * 0.5
	
	# Priorizar según necesidades
	for building in ai_production_buildings:
		var available_units = get_available_units_for_building(building)
		
		for unit_type in available_units:
			var cost: int = get_unit_cost(unit_type)
			var priority: int = 0
			
			match unit_type:
				"Sword", "Spear":
					if needs_infantry:
						priority = 80
					else:
						priority = 30
				
				"Archer", "Artillery":
					if needs_anti_tank:
						priority = 70
					else:
						priority = 40
				
				"Raider", "Tank":
					if needs_vehicles:
						priority = 90
					else:
						priority = 50
				
				_:
					priority = 40  # Prioridad por defecto
			
			# Ajustar prioridad según costo
			priority -= int(floor(cost) / 100)  # Unidades más caras = menor prioridad relativa
			
			production_plans.append({
				"building": building,
				"unit_type": unit_type,
				"cost": cost,
				"priority": priority
			})
	
	# Ordenar por prioridad (más alta primero)
	production_plans.sort_custom(func(a, b): return a.priority > b.priority)
	return production_plans

func ai_calculate_enemy_strength() -> Dictionary:
	var strength = {
		"infantry": 0,
		"vehicles": 0,
		"anti_vehicle": 0,
		"total_health": 0
	}
	
	for unit in all_units:
		if unit.team == 1 and unit.visible:  # Solo unidades enemigas visibles
			strength.total_health += unit.health
			
			if unit.unit_type in ["Infantry", "Sword", "Spear", "Archer"]:
				strength.infantry += 1
			elif unit.unit_type in ["Raider", "Tank"]:
				strength.vehicles += 1
			elif unit.unit_type in ["Artillery"]:
				strength.anti_vehicle += 1
	
	return strength

func ai_calculate_ai_strength() -> Dictionary:
	var strength = {
		"infantry": 0,
		"vehicles": 0,
		"anti_vehicle": 0,
		"total_health": 0
	}
	
	for unit in all_units:
		if unit.team == 2:  # Unidades de IA
			strength.total_health += unit.health
			
			if unit.unit_type in ["Infantry", "Sword", "Spear", "Archer"]:
				strength.infantry += 1
			elif unit.unit_type in ["Raider", "Tank"]:
				strength.vehicles += 1
			elif unit.unit_type in ["Artillery"]:
				strength.anti_vehicle += 1
	
	return strength

func get_available_units_for_building(building: Building) -> Array[String]:
	# Definir qué unidades puede producir cada tipo de edificio
	match building.building_type:
		"Barracks":
			return ["Sword", "Archer", "Spear"]
		"Factory":
			return ["Raider", "Tank"]
		"Port":
			return ["Junker"]  # Unidades navales
		_:
			return ["Sword"]  # Por defecto

func get_unit_cost(unit_type: String) -> int:
	# Definir costos de unidades
	var unit_costs = {
		"Sword": 1000,
		"Archer": 800,
		"Spear": 2000,
		"Raider": 3000,
		"Tank": 5000,
		"Junker": 2500,
		"Artillery": 3500
	}
	
	return unit_costs.get(unit_type, 1000)

func ai_execute_production():
	if ai_production_queue.is_empty():
		return
	
	for production in ai_production_queue:
		if team2_funds >= production.cost:
			await ai_produce_unit(production.building, production.unit_type, production.cost)
			await get_tree().create_timer(0.5).timeout  # Pausa entre producciones

func ai_produce_unit(building: Building, unit_type: String, cost: int) -> void:
	# Crear la unidad
	var unit_scene = load("res://scenes/units/" + unit_type + ".tscn")
	if not unit_scene:
		return
	
	var unit_instance = unit_scene.instantiate()
	$Units.add_child(unit_instance)
	
	# Configurar la unidad
	unit_instance.team = 2  # IA
	unit_instance.grid_position = building.building_position
	unit_instance.current_state = MapUnit.UnitState.MOVED  # No puede actuar este turno
	unit_instance.update_visual_state()
	
	# Restar fondos
	team2_funds -= cost
	hud.update_income_funds()
	
	# Añadir a la lista de unidades
	all_units.append(unit_instance)
	
	# Efecto visual opcional
	if building.has_node("Sprite2D"):
		var sprite = building.get_node("Sprite2D")
		var original_color = sprite.modulate
		sprite.modulate = Color(1.0, 1.0, 1.5)  # Efecto azul claro
		await get_tree().create_timer(0.3).timeout
		if is_instance_valid(sprite):
			sprite.modulate = original_color

func is_unit_stuck(unit: MapUnit) -> bool:
	# Lógica simple para detectar unidades atoradas
	# Puedes hacer esto más sofisticado guardando historial de posiciones
	var stuck_count = 0
	for i in range(min(3, turn)):  # Revisar últimos 3 turnos
		# Aquí necesitarías guardar historial de posiciones por unidad
		# Por ahora, una implementación simple:
		if unit.grid_position == unit.original_position:
			stuck_count += 1
	
	return stuck_count >= 2  # Atorada si no se movió por 2 turnos

func ai_move_away_from_stuck(unit: MapUnit) -> void:
	var reachable_cells = get_reachable_cells(
		unit.grid_position,
		unit.movement_range,
		unit,
		unit.is_raider()
	)
	
	if reachable_cells.size() > 1:  # Excluyendo la posición actual
		# Mover a una posición aleatoria lejos de la actual
		var best_pos = unit.grid_position
		var max_distance = 0
		
		for cell in reachable_cells:
			var distance = abs(cell.x - unit.grid_position.x) + abs(cell.y - unit.grid_position.y)
			if distance > max_distance and is_position_free(cell, unit, true, false):
				max_distance = distance
				best_pos = cell
		
		if best_pos != unit.grid_position:
			unit.grid_position = best_pos
			unit.global_position = Vector2(best_pos * 32) + Vector2(16, 16)
			update_fog_of_war()
