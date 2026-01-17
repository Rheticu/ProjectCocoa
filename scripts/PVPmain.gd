extends Node2D

### ========================== MULTIPLAYER STATE ========================== ###
var player_id: int = 0  # 0 = no conectado, 1 = host, 2 = cliente
var is_host: bool = false
var connection_ip: String = "127.0.0.1"
var connection_port: int = 9999
var connection_check_timer: float = 0.0
var connection_total_time: float = 0.0
var is_connecting: bool = false

### ========================== NODE REFERENCES ========================== ###
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
@onready var pause_menu = $UI/Pause_menu
@onready var multiplayer_menu = $UI/MultiplayerMenu

### ========================== GAME STATE ========================== ###
var action_menu_instance = null
var is_menu_open := false
var attack_mode := false
var mark_mode := false
var bash_mode := false
var thrust_mode := false
var volley_mode := false
var selected_unit: MapUnit
var potential_targets: Array[MapUnit] = []
var raider_view_enabled = false
var input_locked: bool = false
var current_player_team: int = 1
var team1_funds: int
var team2_funds: int
var team1_income: int = 0
var team2_income: int = 0
var turn: int = 1
enum Element { EARTH, METAL, WATER, WOOD, FIRE }
var current_element: Element = Element.EARTH
var inspected_unit: MapUnit = null

### ========================== MAP CONFIG ========================== ###
@export var map_size := Vector2i(22, 15)
var raider_visible_tiles : Array = []
var mapunit_visible_tiles : Array = []
var all_visible_tiles : Array = []
var ambush_revealed_positions : Array = []  # Posiciones reveladas por ambush

### ========================== PATHFINDING AND MOVEMENT ========================== ###
var astar := AStarGrid2D.new()
var astar_raider := AStarGrid2D.new()
var movement_arrow: Line2D
var cursor_path: Array[Vector2i] = []
var is_tracing_path: bool = false
var is_collapsed_to_astar: bool = false
var bash_overlay_set: Array[Vector2i] = []
var bash_overlay_up: Array[Vector2i] = []
var bash_overlay_down: Array[Vector2i] = []
var bash_overlay_right: Array[Vector2i] = []
var bash_overlay_left: Array[Vector2i] = []
var current_bash_overlay: Array[Vector2i] = []
var thrust_overlay_up: Array[Vector2i] = []
var thrust_overlay_down: Array[Vector2i] = []
var thrust_overlay_right: Array[Vector2i] = []
var thrust_overlay_left: Array[Vector2i] = []
var thrust_positions = thrust_overlay_up \
	+ thrust_overlay_down \
	+ thrust_overlay_right \
	+ thrust_overlay_left
var volley_tiles: Array[Vector2i] = []
var archer_attack_range_tiles: Array[Vector2i] = []

const UNIT_TERRAIN_COSTS = {
	"Sword": {
		"PLAINS": 1,
		"MOUNTAIN": 3,
		"ROAD":1,  
		"WALL": 99,    
		"RIVER": 2,     
		"FOREST": 2,
		"OCEAN": 99,      
		"CITY": 1,
	},
	"Archer": {
		"PLAINS": 1,
		"MOUNTAIN": 3,
		"ROAD":1,  
		"WALL": 99,    
		"RIVER": 2,   
		"FOREST": 2,
		"OCEAN": 99,      
		"CITY": 1,
	},
	"Spear": {
		"PLAINS": 1,
		"MOUNTAIN": 3,
		"ROAD":1,  
		"WALL": 99,    
		"RIVER": 2,     
		"FOREST": 2,
		"OCEAN": 99,      
		"CITY": 1,
	},
	"Raider": {
		"PLAINS": 1,
		"MOUNTAIN": 1,
		"ROAD":1, 
		"FOREST": 1,    
		"RIVER": 1,    
		"WALL": 1,
		"OCEAN": 1,     
		"CITY": 1,
	},
	"Junker": {
		"PLAINS": 99,
		"MOUNTAIN": 99, 
		"FOREST": 99,    
		"RIVER": 99,    
		"ROAD": 99,      
		"OCEAN": 1,
		"CITY": 99,
	},
	"Cannon": {
		"PLAINS": 2,
		"MOUNTAIN": 3, 
		"FOREST": 3,    
		"RIVER": 99,    
		"ROAD": 1,      
		"OCEAN": 99,
		"CITY": 1,
	},
}

### ========================== ACTIVE CONTEXT ========================== ###
var active_overlay: TileMap
var active_units: Node
var active_fog_tilemap: TileMap

### ========================== UNIT IDENTIFICATION (para multiplayer) ========================== ###
func get_unit_identifier(unit: MapUnit) -> Dictionary:
	return {
		"x": unit.grid_position.x,
		"y": unit.grid_position.y,
		"team": unit.team,
		"unit_type": unit.unit_type
	}

func find_unit_by_identifier(identifier: Dictionary) -> MapUnit:
	for unit in all_units:
		if (unit.grid_position.x == identifier.x and 
			unit.grid_position.y == identifier.y and
			unit.team == identifier.team and
			unit.unit_type == identifier.unit_type):
			return unit
	return null

### ========================== MULTIPLAYER CONNECTION ========================== ###

func _ready():
	# Configurar multiplayer
	setup_multiplayer()

	# Inicializar juego
	hud.visible = true
	update_active_layers()
	update_fog_of_war()
	for unit in $RaiderUnits.get_children():
		unit.visible = false
	$RaiderLayer.visible = false


	# Inicializar pathfinding
	astar.region = Rect2i(Vector2i(0, 0), map_size)
	astar.cell_size = Vector2(32, 32)
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()

	astar_raider.clear()
	astar_raider.region = Rect2i(Vector2i(-map_size.x, 0), Vector2i(map_size.x * 3, map_size.y))
	astar_raider.cell_size = Vector2(32, 32)
	astar_raider.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar_raider.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar_raider.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar_raider.update()

	# Calcular ingresos iniciales
	team1_income = 0
	team2_income = 0
	for b in $MapLayer/Buildings.get_children():
		b.ownership_changed.connect(_on_building_ownership_changed)
		b.production_menu_opened.connect(camera2d._on_production_menu_opened)
		b.production_menu_closed.connect(camera2d._on_production_menu_closed)
		if b.team == 1:
			team1_income += b.income_per_turn
		elif b.team == 2:
			team2_income += b.income_per_turn

	# Configurar menú de pausa
	pause_menu.resume_game.connect(_on_resume_game)
	pause_menu.exit_game.connect(_on_exit_game)

	# Input actions
	if not InputMap.has_action("ui_cancel"):
		var event = InputEventKey.new()
		event.keycode = KEY_ESCAPE
		InputMap.add_action("ui_cancel")
		InputMap.action_add_event("ui_cancel", event)

	# Conectar menú de multiplayer
	if multiplayer_menu:
		multiplayer_menu.create_game_pressed.connect(_on_create_game_pressed)
		multiplayer_menu.join_game_pressed.connect(_on_join_game_pressed)
		multiplayer_menu.ip_changed.connect(_on_ip_changed)
		multiplayer_menu.show()  # Mostrar al inicio

	await get_tree().process_frame
	_force_canvas_refresh()

	get_viewport().size_changed.connect(_on_viewport_resized)

func _force_canvas_refresh():
	var vp := get_viewport()
	vp.canvas_transform = Transform2D()
	vp.global_canvas_transform = Transform2D()

func _on_viewport_resized():
	_force_canvas_refresh()

func setup_multiplayer():
	multiplayer.set_multiplayer_peer(null)
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)

func position_window_for_player():
	# Posicionar ventanas automáticamente para pruebas locales
	if OS.get_name() == "Windows":
		var screen_size = DisplayServer.screen_get_size()
		var window_size = get_window().size
		var vertical_offset = screen_size.y / 4  # Bajar las ventanas un poco
		var horizontal_offset = screen_size.x / 8  # Mover hacia el centro horizontalmente
		
		if player_id == 1: # Host
			get_window().position = Vector2i(horizontal_offset, vertical_offset)
		elif player_id == 2: # Client
			get_window().position = Vector2i(screen_size.x - window_size.x - horizontal_offset, vertical_offset)

func _on_create_game_pressed():
	create_host()

func _on_join_game_pressed():
	# Leer la IP directamente del campo de texto
	if multiplayer_menu and multiplayer_menu.ip_input:
		var input_text = multiplayer_menu.ip_input.text.strip_edges()
		# Si el usuario incluyó el puerto en el formato "IP:PUERTO", separarlo
		if ":" in input_text:
			var parts = input_text.split(":")
			if parts.size() == 2:
				connection_ip = parts[0].strip_edges()
				var port_str = parts[1].strip_edges()
				if port_str.is_valid_int():
					connection_port = int(port_str)
			else:
				connection_ip = input_text
		else:
			connection_ip = input_text
	else:
		return
	join_host()

func _on_ip_changed(new_ip: String):
	connection_ip = new_ip

func create_host():
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(connection_port, 2)
	
	if error != OK:
		if multiplayer_menu:
			multiplayer_menu.set_status("Error al crear servidor")
		return

	multiplayer.set_multiplayer_peer(peer)
	player_id = 1
	current_player_team = 1
	hud.update_income_funds()
	hud.update_element_ui()
	# Cambiar título de ventana
	get_window().title = "Player 1 - HOST"

	# Posicionar ventana del host
	#position_window_for_player()

	if multiplayer_menu:
		multiplayer_menu.set_status("Esperando jugador...")
		multiplayer_menu.hide()
	start_turn(1)

func join_host():
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(connection_ip, connection_port)
	
	if error != OK:
		if multiplayer_menu:
			multiplayer_menu.set_status("Error al conectar")
		return

	multiplayer.set_multiplayer_peer(peer)
	is_connecting = true
	connection_check_timer = 0.0
	connection_total_time = 0.0
	
	if multiplayer_menu:
		multiplayer_menu.set_status("Conectando...")

func _on_player_connected(id: int):
	if player_id == 1:  # Si soy el host
		await get_tree().create_timer(0.5).timeout
		send_game_state_to_client(id)

func _on_player_disconnected(_id: int):
	# Volver al menú de conexión
	if multiplayer_menu:
		multiplayer_menu.show()
		multiplayer_menu.set_status("Jugador desconectado")
	player_id = 0
	multiplayer.set_multiplayer_peer(null)

func _on_connected_to_server():
	is_connecting = false
	var _unique_id = multiplayer.get_unique_id()
	# En ENet, el servidor siempre es 1, los clientes obtienen IDs únicos grandes
	# Para simplificar, asignamos player_id = 2 al cliente
	player_id = 2
	current_player_team = player_id
	hud.update_income_funds()
	hud.update_element_ui()
	# Cambiar título de ventana
	get_window().title = "Player 2 - Client"

	# Posicionar ventana del cliente
	#position_window_for_player()

	if multiplayer_menu:
		multiplayer_menu.set_status("Conectado como jugador " + str(player_id))
		multiplayer_menu.hide()
	# Solicitar estado inicial
	request_game_state.rpc_id(1)

### ========================== GAME STATE SYNC ========================== ###

@rpc("any_peer", "reliable")
func request_game_state():
	if player_id == 1:  # Solo el host responde
		var requester_id = multiplayer.get_remote_sender_id()
		send_game_state_to_client(requester_id)

func send_game_state_to_client(client_id: int):
	var state = {
		"team1_funds": team1_funds,
		"team2_funds": team2_funds,
		"team1_income": team1_income,
		"team2_income": team2_income,
		"current_player_team": current_player_team,
		"turn": turn,
		"buildings": [],
		"units": []
	}
	
	# Guardar edificios
	for building in $MapLayer/Buildings.get_children():
		state["buildings"].append({
			"x": building.building_position.x,
			"y": building.building_position.y,
			"team": building.team,
			"capture_points": building.capture_points
		})
	
	# Guardar unidades
	for unit in all_units:
		state["units"].append({
			"x": unit.grid_position.x,
			"y": unit.grid_position.y,
			"team": unit.team,
			"unit_type": unit.unit_type,
			"health": unit.health,
			"state": unit.current_state,
			"marked_turns": unit.marked_turns
		})
	
	sync_game_state.rpc_id(client_id, state)

@rpc("any_peer", "reliable")
func sync_game_state(state: Dictionary):
	if player_id == 1:
		return  # El host no necesita esto
	
	# Restaurar estado
	team1_funds = state.get("team1_funds", 0)
	team2_funds = state.get("team2_funds", 0)
	team1_income = state.get("team1_income", 0)
	team2_income = state.get("team2_income", 0)
	current_player_team = state.get("current_player_team", 1)
	turn = state.get("turn", 1)
	
	# Sincronizar edificios
	for b_data in state.get("buildings", []):
		var building = get_building_at(Vector2i(b_data.x, b_data.y))
		if building:
			building.team = b_data.team
			building.capture_points = b_data.capture_points
			building.update_visual()
	
	# Sincronizar unidades
	for u_data in state.get("units", []):
		var unit = find_unit_by_identifier({
			"x": u_data.x,
			"y": u_data.y,
			"team": u_data.team,
			"unit_type": u_data.unit_type
		})
		if unit:
			unit.health = u_data.health
			unit.current_state = u_data.state
			unit.marked_turns = u_data.marked_turns
			unit.update_visual_state()
	
	# Inicializar turno después de sincronizar
	start_turn(current_player_team)
	update_fog_of_war()
	hud.update_income_funds()
	hud.update_element_ui()

### ========================== MOVEMENT FUNCTIONS (copiadas del PvE) ========================== ###

func move_unit_along_wrapped_path(unit: MapUnit, path: Array[Vector2i], from_rpc: bool = false) -> void:
	if path.is_empty() or path.size() < 2:
		input_locked = false
		return
	
	input_locked = true
	unit.original_position = unit.grid_position
	var last_safe_tile = [unit.grid_position]
	
	var wrapped_path: Array[Vector2i] = []
	for tile in path:
		wrapped_path.append(Vector2i(posmod(tile.x, map_size.x), tile.y))
	
	# Guardar el wrapped_path en la unidad para sincronizar cuando se confirme (solo si no viene de un RPC)
	if not from_rpc:
		unit.set_meta("pending_move_path", wrapped_path)
		unit.set_meta("pending_move_is_wrapped", true)
	
	# Si viene de RPC, asegurar que la unidad empiece desde su posición original visualmente
	if from_rpc:
		unit.grid_position = unit.original_position
		unit.global_position = Vector2(unit.original_position * 32) + Vector2(16, 16)
		update_fog_of_war()
	
	var tween := create_tween()
	tween.set_parallel(false)
	var move_time := 0.1
	var pause_time := 0.04
	
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
		
		# NO actualizar grid_position antes del tween cuando viene de RPC
		# Se actualizará en el callback después del movimiento visual
		
		tween.tween_property(unit, "global_position", pos, move_time)
		tween.tween_interval(pause_time)
		
		# Actualizar posición lógica DESPUÉS del movimiento visual (en el callback)
		if from_rpc:
			var rpc_step_tile = tile
			tween.tween_callback(func():
				unit.grid_position = rpc_step_tile
				# Solo verificar visibilidad (el fog of war ya se actualizó al inicio)
				_check_unit_visibility(unit)
			)
		
		var step_tile = tile
		tween.tween_callback(func() -> void:
			var enemy := get_hidden_enemy_at(step_tile, unit.team, unit.is_raider())
			if enemy:
				# Agregar la posición a las posiciones reveladas por ambush (persistente)
				if enemy.grid_position not in ambush_revealed_positions:
					ambush_revealed_positions.append(enemy.grid_position)
				
				# Marcar la unidad como visible
				enemy.visible = true
				enemy.update_visual_state()
				
				# Actualizar posición de la unidad emboscada
				var final_pos = last_safe_tile[0]
				unit.grid_position = final_pos
				unit.global_position = Vector2(final_pos * 32) + Vector2(16, 16)
				show_ambush_effect(unit.global_position)
				unit.current_state = MapUnit.UnitState.MOVED
				unit.update_visual_state()
				
				# SINCRONIZAR: path hasta donde llegó (incluyendo la posición final) (solo si no viene de un RPC)
				if not from_rpc and multiplayer.multiplayer_peer != null:
					var ambush_path: Array[Vector2i] = []
					# Construir path hasta la posición final
					for j in range(wrapped_path.size()):
						ambush_path.append(wrapped_path[j])
						if wrapped_path[j] == step_tile:
							break
					ambush_path.append(final_pos)
					
					# Convertir path a arrays de x e y para RPC
					var path_x: Array = []
					var path_y: Array = []
					for p in ambush_path:
						path_x.append(p.x)
						path_y.append(p.y)
					
					sync_unit_move.rpc(unit.original_position.x, unit.original_position.y, path_x, path_y, true, unit.team, unit.unit_type)
				
				# SINCRONIZAR: descubrimiento del enemigo
				if multiplayer.multiplayer_peer != null:
					sync_ambush_reveal.rpc(enemy.grid_position.x, enemy.grid_position.y, enemy.team, enemy.unit_type)
				
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
			
			# Actualizar posición después del teleport (solo si viene de RPC)
			if from_rpc:
				unit.grid_position = next_tile
				# Solo verificar visibilidad (el fog of war ya está calculado)
				_check_unit_visibility(unit)
		)
	
	# Phase 3: move remaining tiles
	for i in range(wrap_index + 1, wrapped_path.size()):
		var tile = wrapped_path[i]
		var pos: Vector2 = Vector2(tile * 32) + Vector2(16, 16)
		
		# NO actualizar grid_position antes del tween cuando viene de RPC
		# Se actualizará en el callback después del movimiento visual
		
		tween.tween_property(unit, "global_position", pos, move_time)
		tween.tween_interval(pause_time)
		
		# Actualizar posición lógica DESPUÉS del movimiento visual (en el callback)
		if from_rpc:
			var rpc_step_tile = tile
			tween.tween_callback(func():
				unit.grid_position = rpc_step_tile
				# Solo verificar visibilidad (el fog of war ya está calculado)
				_check_unit_visibility(unit)
			)
		
		var step_tile = tile
		tween.tween_callback(func() -> void:
			var enemy := get_hidden_enemy_at(step_tile, unit.team, unit.is_raider())
			if enemy:
				# Agregar la posición a las posiciones reveladas por ambush (persistente)
				if enemy.grid_position not in ambush_revealed_positions:
					ambush_revealed_positions.append(enemy.grid_position)
				
				# Marcar la unidad como visible
				enemy.visible = true
				enemy.update_visual_state()
				
				# Actualizar posición de la unidad emboscada
				var final_pos = last_safe_tile[0]
				unit.grid_position = final_pos
				unit.global_position = Vector2(final_pos * 32) + Vector2(16, 16)
				show_ambush_effect(unit.global_position)
				unit.current_state = MapUnit.UnitState.MOVED
				unit.update_visual_state()
				
				# SINCRONIZAR: path hasta donde llegó (incluyendo la posición final) (solo si no viene de un RPC)
				if not from_rpc and multiplayer.multiplayer_peer != null:
					var ambush_path: Array[Vector2i] = []
					# Construir path hasta la posición final
					for j in range(wrapped_path.size()):
						ambush_path.append(wrapped_path[j])
						if wrapped_path[j] == step_tile:
							break
					ambush_path.append(final_pos)
					
					# Convertir path a arrays de x e y para RPC
					var path_x: Array = []
					var path_y: Array = []
					for p in ambush_path:
						path_x.append(p.x)
						path_y.append(p.y)
					
					sync_unit_move.rpc(unit.original_position.x, unit.original_position.y, path_x, path_y, true, unit.team, unit.unit_type)
				
				# SINCRONIZAR: descubrimiento del enemigo
				if multiplayer.multiplayer_peer != null:
					sync_ambush_reveal.rpc(enemy.grid_position.x, enemy.grid_position.y, enemy.team, enemy.unit_type)
				
				update_fog_of_war()
				active_overlay.clear()
				input_locked = false
				tween.stop()
			else:
				last_safe_tile[0] = step_tile
				unit.grid_position = step_tile
		)
	
	tween.tween_callback(func() -> void:
		if input_locked:
			unit.global_position = Vector2(wrapped_path.back() * 32) + Vector2(16, 16)
			input_locked = false
			# Solo mostrar action menu si el movimiento NO viene de un RPC (es el jugador local)
			if not from_rpc:
				show_action_menu(unit)
			else:
				# Si viene de un RPC, actualizar fog of war para ocultar la unidad si está fuera de visión
				update_fog_of_war()
	)

func get_wrapped_tile_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	update_astar_raider(start, goal)
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
	return dx > raider.movement_range

func update_astar_raider(start: Vector2i, goal: Vector2i):
	astar_raider.clear()
	astar_raider.region = Rect2i(Vector2i(-map_size.x, 0), Vector2i(map_size.x * 3, map_size.y))
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

func move_unit_along_path(unit: MapUnit, path: Array[Vector2i], from_rpc: bool = false) -> void:
	if path.is_empty():
		return
	
	input_locked = true
	unit.original_position = unit.grid_position
	var last_safe_tile = [unit.grid_position]
	
	# Guardar el path en la unidad para sincronizar cuando se confirme (solo si no viene de un RPC)
	if not from_rpc:
		unit.set_meta("pending_move_path", path)
		unit.set_meta("pending_move_is_wrapped", false)
	
	# Si viene de RPC, asegurar que la unidad empiece desde su posición original visualmente
	if from_rpc:
		unit.grid_position = unit.original_position
		unit.global_position = Vector2(unit.original_position * 32) + Vector2(16, 16)
		update_fog_of_war()
	
	var tween := create_tween()
	tween.set_parallel(false)
	var move_time := 0.1
	var pause_time := 0.04
	
	for tile in path:
		var step_tile := tile
		var pos: Vector2 = Vector2(step_tile * 32) + Vector2(16, 16)
		
		# NO actualizar grid_position antes del tween cuando viene de RPC
		# Se actualizará en el callback después del movimiento visual
		
		tween.tween_property(unit, "global_position", pos, move_time)
		tween.tween_interval(pause_time)
		
		# Actualizar posición lógica DESPUÉS del movimiento visual (en el callback)
		if from_rpc:
			tween.tween_callback(func():
				unit.grid_position = step_tile
				# Solo verificar visibilidad (el fog of war ya está calculado)
				_check_unit_visibility(unit)
			)
		
		if get_hidden_enemy_at(step_tile, unit.team, unit.is_raider()):
			tween.tween_callback(func() -> void:
				var enemy := get_hidden_enemy_at(step_tile, unit.team, unit.is_raider())
				if enemy:
					# Agregar la posición a las posiciones reveladas por ambush (persistente)
					if enemy.grid_position not in ambush_revealed_positions:
						ambush_revealed_positions.append(enemy.grid_position)
					
					# Marcar la unidad como visible
					enemy.visible = true
					enemy.update_visual_state()
					
					# Actualizar posición de la unidad emboscada
					var final_pos = last_safe_tile[0]
					unit.grid_position = final_pos
					unit.global_position = Vector2(final_pos * 32) + Vector2(16, 16)
					show_ambush_effect(unit.global_position)
					unit.current_state = MapUnit.UnitState.MOVED
					unit.update_visual_state()
					
					# SINCRONIZAR: path hasta donde llegó (incluyendo la posición final) (solo si no viene de un RPC)
					if not from_rpc and multiplayer.multiplayer_peer != null:
						var ambush_path: Array[Vector2i] = []
						# Construir path hasta la posición final
						for i in range(path.size()):
							ambush_path.append(path[i])
							if path[i] == step_tile:
								break
						ambush_path.append(final_pos)
						
						# Convertir path a arrays de x e y para RPC
						var path_x: Array = []
						var path_y: Array = []
						for p in ambush_path:
							path_x.append(p.x)
							path_y.append(p.y)
						
						sync_unit_move.rpc(unit.original_position.x, unit.original_position.y, path_x, path_y, false, unit.team, unit.unit_type)
					
					# SINCRONIZAR: descubrimiento del enemigo
					if multiplayer.multiplayer_peer != null:
						sync_ambush_reveal.rpc(enemy.grid_position.x, enemy.grid_position.y, enemy.team, enemy.unit_type)
					
					update_fog_of_war()
					active_overlay.clear()
					input_locked = false
					tween.stop()
			)
		else:
			tween.tween_callback(func() -> void:
				last_safe_tile[0] = step_tile
			)
	
	var end_move_callback = func() -> void:
		if input_locked:
			unit.global_position = Vector2(path.back() * 32) + Vector2(16, 16)
			# grid_position se actualiza cuando se confirma desde el menú
			input_locked = false
			# Solo mostrar action menu si el movimiento NO viene de un RPC (es el jugador local)
			if not from_rpc:
				show_action_menu(unit)
			else:
				# Si viene de un RPC, actualizar fog of war para ocultar la unidad si está fuera de visión
				update_fog_of_war()
	
	tween.tween_callback(end_move_callback)
	active_overlay.clear()

func get_tile_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	var raw_path: PackedVector2Array = astar.get_point_path(start, goal)
	for p in raw_path:
		var tile: Vector2i = Vector2i(p / 32)
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

func update_astar(moving_unit: MapUnit) -> void:
	astar.clear()
	astar.region = Rect2i(Vector2i(0, 0), map_size)
	astar.cell_size = Vector2(32, 32)
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	
	for x in range(map_size.x):
		for y in range(map_size.y):
			var pos = Vector2i(x, y)
			var terrain = get_terrain_at(pos)
			var cost = get_movement_cost(moving_unit.unit_type, terrain)
			astar.set_point_weight_scale(pos, float(cost))
	
	for u in all_units:
		if u != moving_unit and u.visible and _in_bounds(u.grid_position):
			var same_type = u.is_raider() == moving_unit.is_raider()
			if same_type and u.team != moving_unit.team:
				astar.set_point_weight_scale(u.grid_position, 99.0)

func is_position_free(pos: Vector2i, ignore_unit: MapUnit, final_tile: bool = true, ignore_hidden: bool = true) -> bool:
	for unit in all_units:
		if unit == ignore_unit:
			continue
		if unit.grid_position == pos:
			if ignore_hidden and not unit.visible:
				continue
			var same_type = unit.is_raider() == ignore_unit.is_raider()
			if same_type:
				if unit.team == ignore_unit.team:
					return not final_tile
				else:
					return false
	return true

func is_visibly_occupied(pos: Vector2i, mover: MapUnit) -> bool:
	for unit in all_units:
		if unit.visible and unit.grid_position == pos:
			if unit.team != mover.team and unit.is_raider() == mover.is_raider():
				return true
	return false

func get_reachable_cells(start: Vector2i, movement_points: int, mover: MapUnit, is_raider: bool) -> Array[Vector2i]:
	var reachable: Array[Vector2i] = []
	var visited := {}
	var queue = []
	
	queue.append({pos = start, cost = 0})
	visited[start] = 0
	
	while not queue.is_empty():
		queue.sort_custom(func(a, b): return a.cost < b.cost)
		var current = queue.pop_front()
		reachable.append(current.pos)
		
		for dir in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next_pos = current.pos + dir
			if is_raider:
				next_pos.x = posmod(next_pos.x, map_size.x)
			
			if not _in_bounds(next_pos):
				continue
			
			if is_visibly_occupied(next_pos, mover):
				continue
			
			var terrain = get_terrain_at(next_pos)
			var move_cost = get_movement_cost(mover.unit_type, terrain)
			var new_cost = current.cost + move_cost
			
			if new_cost <= movement_points and (not visited.has(next_pos) or new_cost < visited[next_pos]):
				visited[next_pos] = new_cost
				queue.append({pos = next_pos, cost = new_cost})
	
	return reachable

func get_terrain_at(pos: Vector2i) -> String:
	if not _in_bounds(pos):
		return "PLAINS"
	var feature_data = $MapLayer/TerrainFeatures.get_cell_tile_data(0, pos)
	if feature_data:
		var terrain = feature_data.get_custom_data("terrain_type")
		if terrain != "":
			return terrain
	return "PLAINS"

func get_movement_cost(unit_type: String, terrain: String) -> int:
	if unit_type in UNIT_TERRAIN_COSTS and terrain in UNIT_TERRAIN_COSTS[unit_type]:
		return UNIT_TERRAIN_COSTS[unit_type][terrain]
	return 99

### ========================== FOG OF WAR ========================== ###

func update_active_layers():
	active_overlay = raider_range_overlay if raider_view_enabled else standard_overlay
	active_units = $RaiderUnits if raider_view_enabled else $Units
	active_fog_tilemap = raider_fog_tilemap if raider_view_enabled else fog_tilemap

func is_tile_visible_for_team(tile_pos: Vector2i, _viewing_team: int, is_raider_unit: bool) -> bool:
	# Verificación rápida sin recalcular todo el fog of war
	# Solo verifica si el tile está en las listas de tiles visibles actuales
	if is_raider_unit:
		return (tile_pos in raider_visible_tiles and raider_view_enabled)
	else:
		return (tile_pos in all_visible_tiles)

func _check_unit_visibility(unit: MapUnit):
	# Verificar si la unidad debería estar visible después de actualizar fog of war
	var viewing_team = player_id if player_id > 0 else 1
	if unit.team != viewing_team:
		var should_be_visible = false
		if unit.is_raider():
			should_be_visible = (unit.marked_turns > 0) or (unit.grid_position in raider_visible_tiles and raider_view_enabled)
		else:
			should_be_visible = (unit.marked_turns > 0) or (unit.grid_position in all_visible_tiles)
		
		# Ocultar si no debería estar visible
		if not should_be_visible:
			unit.visible = false

func update_fog_of_war():
	for x in range(0, map_size.x + 1):
		for y in range(0, map_size.y + 1):
			var pos = Vector2i(x,y)
			raider_map.set_cell(0, pos, 1, Vector2.ZERO)
			raider_fog_tilemap.set_cell(0, pos, 0, Vector2.ZERO)
			fog_tilemap.set_cell(0, pos, 0, Vector2.ZERO)
	
	raider_visible_tiles.clear()
	mapunit_visible_tiles.clear()
	
	# Si no hay conexión (player_id == 0), mostrar todo para poder ver el juego
	# Una vez conectado, solo mostrar visión del jugador local
	var viewing_team = player_id if player_id > 0 else 1
	
	# Solo visión del jugador local (player_id) o equipo 1 si no hay conexión
	for unit in all_units:
		if unit.team == viewing_team:
			var center = unit.grid_position
			var vision = unit.vision_range
			for x in range(-vision, vision + 1):
				for y in range(-vision, vision + 1):
					var pos = center + Vector2i(x, y)
					if abs(x) + abs(y) <= vision:
						if unit.is_raider():
							var wpos = Vector2i(posmod(pos.x, map_size.x), pos.y)
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

	for b in $MapLayer/Buildings.get_children():
		if b.team == viewing_team:
			fog_tilemap.set_cell(0, b.building_position, -1)
		var _visible = b.building_position in all_visible_tiles
		if b.has_node("CaptureLabel"):
			b.get_node("CaptureLabel").visible = _visible

	# Agregar posiciones reveladas por ambush
	for pos in ambush_revealed_positions:
		if pos not in all_visible_tiles:
			all_visible_tiles.append(pos)
		if pos not in raider_visible_tiles:
			raider_visible_tiles.append(pos)
		if pos not in mapunit_visible_tiles:
			mapunit_visible_tiles.append(pos)
		# Revelar el fog en esas posiciones
		fog_tilemap.set_cell(0, pos, -1)
		raider_fog_tilemap.set_cell(0, pos, -1)
		raider_map.set_cell(0, pos, -1)
	
	# Actualizar visibilidad de unidades enemigas
	for unit in all_units:
		if unit.team != viewing_team:
			if unit.is_raider():
				unit.visible = (unit.marked_turns > 0) or (unit.grid_position in raider_visible_tiles and raider_view_enabled)
			else:
				unit.visible = (unit.marked_turns > 0) or (unit.grid_position in all_visible_tiles)
		else:
			# Las unidades propias siempre visibles
			unit.visible = true
	
	# Manejar unidades marcadas
	for unit in all_units:
		if unit.team != viewing_team and unit.marked_turns > 0:
			var pos = unit.grid_position
			fog_tilemap.set_cell(0, pos, -1)
			raider_fog_tilemap.set_cell(0, pos, -1)
			raider_map.set_cell(0, pos, -1)
			unit.visible = true
	
	# Manejar unidades propias (modulación)
	for unit in $Units.get_children():
		if unit.team == viewing_team:
			if raider_view_enabled:
				if unit.grid_position in raider_visible_tiles:
					unit.modulate.a = 0.4
				else:
					unit.modulate.a = 1.0
			else:
				unit.modulate.a = 1.0
		else:
			if raider_view_enabled:
				if unit.grid_position in raider_visible_tiles:
					unit.modulate.a = 0.4
				else:
					unit.modulate.a = 1.0
			else:
				unit.modulate.a = 1.0

	# Manejar raiders
	for unit in $RaiderUnits.get_children():
		if unit.team == viewing_team:
			unit.visible = raider_view_enabled
		else:
			if unit.marked_turns > 0:
				unit.visible = true
			elif raider_view_enabled:
				unit.visible = unit.grid_position in raider_visible_tiles
			else:
				unit.visible = false

func get_hidden_enemy_at(pos: Vector2i, my_team: int, my_is_raider: bool) -> MapUnit:
	for unit in all_units:
		if unit.grid_position == pos and unit.team != my_team:
			if not unit.visible:
				if unit.is_raider() == my_is_raider:
					return unit
	return null

func show_ambush_effect(unit_pos: Vector2):
	var exclaim = Sprite2D.new()
	exclaim.texture = preload("res://art/ui/Exclamation.png")
	exclaim.position = unit_pos + Vector2(0, -32)
	exclaim.scale = Vector2(.06, .06)
	add_child(exclaim)
	
	var tween = create_tween()
	tween.tween_interval(1.0)
	tween.tween_property(exclaim, "modulate:a", 0.0, 0.4)
	tween.tween_callback(func(): exclaim.queue_free())

### ========================== TURN MANAGEMENT ========================== ###

func start_turn(team: int):
	update_active_layers()
	update_fog_of_war()
	current_player_team = team
	
	team1_income = 0
	team2_income = 0
	
	for b in $MapLayer/Buildings.get_children():
		if b.team == 1:
			team1_income += b.income_per_turn
		elif b.team == 2:
			team2_income += b.income_per_turn
	
	if current_player_team == 1:
		team1_funds += team1_income
		turn += 1
	elif current_player_team == 2:
		team2_funds += team2_income
	
	hud.update_income_funds()

	# Solo permitir input si es mi turno
	if current_player_team == player_id:
		# Resetear TODAS las unidades del equipo (tanto Units como RaiderUnits)
		for unit in all_units:
			if unit.team == team:
				unit.current_state = MapUnit.UnitState.UNSELECTED
				unit.update_visual_state()
				# Limpiar metadatos de movimiento pendiente del turno anterior
				if unit.has_meta("pending_move_path"):
					unit.remove_meta("pending_move_path")
					unit.remove_meta("pending_move_is_wrapped")
	else:
		for unit in all_units:
			if unit.current_state == MapUnit.UnitState.SELECTED:
				unit.deselect()
			# Limpiar metadatos de movimiento pendiente del turno anterior
			if unit.has_meta("pending_move_path"):
				unit.remove_meta("pending_move_path")
				unit.remove_meta("pending_move_is_wrapped")

func _on_end_turn_pressed():
	if current_player_team != player_id:
		return
	end_turn()

func end_turn():
	update_active_layers()

	if current_player_team == 2:
		advance_element()
		sync_element_change.rpc(current_element)
		hud.update_element_ui()
	for unit in all_units:
		if unit.marked_turns > 0:
			unit.marked_turns -= 1

	current_player_team = 2 if current_player_team == 1 else 1

	# Sincronizar cambio de turno
	if multiplayer.multiplayer_peer != null:
		sync_turn_change.rpc(current_player_team)

	for unit in all_units:
		if unit.team == current_player_team:
			unit.current_state = MapUnit.UnitState.UNSELECTED
			unit.update_visual_state()

	start_turn(current_player_team)
	update_fog_of_war()

func advance_element():
	current_element = ((current_element + 1) % Element.size()) as Element

@rpc("any_peer", "reliable")
func sync_turn_change(new_team: int):
	var sender_id = multiplayer.get_remote_sender_id()
	
	# No procesar si ya es mi turno (evitar duplicados)
	if current_player_team == new_team:
		return
	
	# Validar que el sender tiene el turno actual
	# sender_id == 1 significa host (player_id = 1)
	# sender_id != 1 significa cliente (player_id = 2)
	var sender_player_id = 1 if sender_id == 1 else 2
	
	if sender_player_id != current_player_team:
		return
	
	current_player_team = new_team
	start_turn(new_team)
	update_fog_of_war()

@rpc("any_peer", "reliable")
func sync_element_change(new_element: int):
	current_element = new_element as Element
	hud.update_element_ui()
### ========================== INPUT HANDLING ========================== ###

func _input(event):
	if event.is_action_pressed("Tab"):
		if not is_menu_open:
			toggle_raider_view()

func _unhandled_input(event):
	# No procesar input si no es mi turno, está bloqueado, o no hay conexión
	if player_id == 0 or input_locked:
		return

	if current_player_team == player_id:
		if event.is_action_pressed("Enter"):
			_on_end_turn_pressed()

		if event.is_action_pressed("LMClick"):
			if is_menu_open:
				return
			if cursor_path:
				cursor_path.clear()
			is_tracing_path = false

			var mouse_pos = get_global_mouse_position()
			var grid_pos = Vector2i(mouse_pos / 32)

			if mark_mode:
				try_mark(grid_pos)
				return

			if attack_mode:
				try_attack(grid_pos)
				return

			if bash_mode:
				if grid_pos in current_bash_overlay:
					try_bash(current_bash_overlay)
					return

			if thrust_mode:
				if grid_pos in thrust_overlay_up:
					try_thrust(thrust_overlay_up)
					return
				if grid_pos in thrust_overlay_down:
					try_thrust(thrust_overlay_down)
					return
				if grid_pos in thrust_overlay_right:
					try_thrust(thrust_overlay_right)
					return
				if grid_pos in thrust_overlay_left:
					try_thrust(thrust_overlay_left)
					return

			if volley_mode:
				if grid_pos in volley_tiles:
					try_volley(volley_tiles)
					return

			else:
				for unit in active_units.get_children():
					if unit.current_state == MapUnit.UnitState.SELECTED:
						var final_path: Array[Vector2i] = []
						var use_wrapped_movement = false
						if is_position_free(grid_pos, unit, true):
							if movement_arrow and movement_arrow.get_point_count() > 1:
								for i in range(movement_arrow.get_point_count()):
									var world_pos = movement_arrow.get_point_position(i)
									var grid_pos_from_line = Vector2i(world_pos / 32)
									final_path.append(grid_pos_from_line)
							else:
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
		if is_action_mode():
			for unit in active_units.get_children():
				if unit.current_state == MapUnit.UnitState.SELECTED:
					unit.grid_position = unit.original_position
					end_action_mode()
					unit.select()
					return
		else:
			if is_menu_open:
				_on_cancel_pressed()
			else:
				if active_overlay.get_used_cells(0).size() > 0 or attack_range_overlay.get_used_cells(0).size() > 0:
					active_overlay.clear()
					attack_range_overlay.clear()
					for unit in active_units.get_children():
						if unit.current_state != MapUnit.UnitState.MOVED:
							unit.deselect()
					return

				var mouse_pos = get_global_mouse_position()
				var grid_pos = Vector2i(mouse_pos / 32)
				var clicked_unit: MapUnit = null
				for unit in all_units:
					if unit.grid_position == grid_pos and unit.visible and unit.current_state != unit.UnitState.SELECTED:
						clicked_unit = unit
						break

				if clicked_unit:
					if inspected_unit == clicked_unit:
						# Click derecho otra vez en la misma unidad → toggle OFF
						hide_attack_range()
						inspected_unit = null
					else:
						# Click derecho en una unidad distinta → switch
						hide_attack_range()
						show_attack_range(clicked_unit)
						inspected_unit = clicked_unit
				else:
					# Click derecho en tile vacío → comportamiento original
					inspected_unit = null
					hide_attack_range()

				for unit in active_units.get_children():
					if unit.current_state != MapUnit.UnitState.MOVED:
						unit.deselect()

					active_overlay.clear()
					close_action_menu()

func create_movement_arrow():
	if movement_arrow:
		movement_arrow.queue_free()
	movement_arrow = Line2D.new()
	movement_arrow.width = 4
	movement_arrow.default_color = Color(1, 1, 1, 0.9)
	movement_arrow.z_index = 10
	add_child(movement_arrow)

func update_movement_arrow(unit: MapUnit, cursor_pos: Vector2i):
	if not movement_arrow:
		create_movement_arrow()
	
	var unit_pos = unit.grid_position
	
	if is_move_wrapped(unit_pos, cursor_pos, unit):
		movement_arrow.clear_points()
		return
	
	if active_overlay.get_cell_source_id(0, cursor_pos) == -1:
		cursor_path = []
		movement_arrow.clear_points()
		is_tracing_path = false
		is_collapsed_to_astar = false
		return
	
	if not is_tracing_path:
		if cursor_pos != unit_pos:
			is_tracing_path = true
			cursor_path = [unit_pos]
			is_collapsed_to_astar = false
		else:
			movement_arrow.clear_points()
			return
	
	if is_collapsed_to_astar:
		var last_astar_pos = cursor_path.back() if not cursor_path.is_empty() else unit_pos
		if (cursor_pos - last_astar_pos).abs().x + (cursor_pos - last_astar_pos).abs().y == 1:
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
	
	var final_cost = calculate_path_cost(cursor_path, unit)
	var final_path = cursor_path.duplicate()
	if final_cost > unit.movement_range:
		final_path = get_valid_subpath_by_cost(final_path, unit.movement_range, unit)
	
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

func show_movement_range(center: Vector2i, mover: MapUnit):
	update_active_layers()
	active_overlay.clear()
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

	for unit in active_units.get_children():
		if unit.current_state == MapUnit.UnitState.SELECTED:
			unit.deselect()
			hud.hide_unit_info()
	active_overlay.clear()

### ========================== ACTION MENU ========================== ###

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
	
	var cancel_btn = action_menu_instance.get_node("Cancel")
	var move_btn = action_menu_instance.get_node("Move")
	var attack_btn = action_menu_instance.get_node("Attack")
	var mark_btn = action_menu_instance.get_node("Mark")
	var capture_btn = action_menu_instance.get_node("Capture")
	var bash_btn = action_menu_instance.get_node("Bash")
	var thrust_btn = action_menu_instance.get_node("Thrust")
	var volley_btn = action_menu_instance.get_node("Volley")
	var overwatch_btn = action_menu_instance.get_node("Overwatch")
	var has_targets = false
	var has_mark_targets = false


	for other in active_units.get_children():
		if other.visible:
			if unit.can_attack(other):
				has_targets = true

	for other in all_units:
		if unit is Raider_Unit and unit.can_mark(other):
			has_mark_targets = true

	attack_btn.visible = has_targets
	mark_btn.visible = has_mark_targets and unit is Raider_Unit
	capture_btn.visible = (unit.unit_type == "Sword" or "Archer" or "Spear") and (building_underneath != null) and (building_underneath.team != unit.team)
	bash_btn.visible = unit.unit_type == "Spear"
	thrust_btn.visible = unit.unit_type == "Sword"
	volley_btn.visible = unit.unit_type == "Archer"
	overwatch_btn.visible = unit.unit_type == "Cannon"

	attack_btn.pressed.connect(_on_attack_pressed)
	mark_btn.pressed.connect(_on_mark_pressed)
	cancel_btn.pressed.connect(_on_cancel_pressed)
	move_btn.pressed.connect(_on_move_confirmed)
	capture_btn.pressed.connect(_on_capture_pressed.bind(unit, building_underneath))
	bash_btn.pressed.connect(_on_bash_pressed.bind())
	thrust_btn.pressed.connect(_on_thrust_pressed.bind())
	volley_btn.pressed.connect(_on_volley_pressed.bind())

	is_menu_open = true
	update_cursor_visibility()

func is_action_mode() -> bool:
	return attack_mode or mark_mode or bash_mode or thrust_mode or volley_mode

func _on_overwatch_pressed():
	return

func _on_volley_pressed():
	volley_tiles.clear()
	archer_attack_range_tiles.clear()
	active_overlay.clear()
	close_action_menu()
	volley_mode = true
	for a in range(-selected_unit.attack_range, selected_unit.attack_range + 1):
		for b in range(-selected_unit.attack_range, selected_unit.attack_range + 1):
			if abs(a) + abs(b) <= selected_unit.attack_range:
				archer_attack_range_tiles.append(selected_unit.grid_position + Vector2i(a,b))

func _on_bash_pressed():
	bash_overlay_up.clear()
	bash_overlay_down.clear()
	bash_overlay_right.clear()
	bash_overlay_left.clear()
	bash_overlay_set.clear()
	active_overlay.clear()
	close_action_menu()
	bash_mode = true
	for x in range(-1, 2):
		for y in range(-1,2):
			if x == 0 and y == 0:
				continue
			bash_overlay_set.append(selected_unit.grid_position + Vector2i(x,y))

			# Poner el tile del highlight
	for pos in bash_overlay_set:
		active_overlay.set_cell(0, pos, 0, Vector2i.ZERO)

	for i in range(-1,2):
		bash_overlay_up.append(selected_unit.grid_position + Vector2i(i,-1))
		bash_overlay_down.append(selected_unit.grid_position + Vector2i(i,1))
		bash_overlay_right.append(selected_unit.grid_position + Vector2i(1,i))
		bash_overlay_left.append(selected_unit.grid_position + Vector2i(-1,i))

	for u in active_units.get_children():
		u.update_visual_state()
		for pos in bash_overlay_set:
			if u.grid_position == pos and u.team != selected_unit.team:
				u.get_node("Sprite2D").modulate = Color(2, 0.5, 0.5)

func _on_thrust_pressed():
	thrust_overlay_up.clear()
	thrust_overlay_down.clear()
	thrust_overlay_right.clear()
	thrust_overlay_left.clear()
	thrust_positions.clear()
	active_overlay.clear()
	close_action_menu()
	thrust_mode = true

	for i in range(1,3):
		thrust_overlay_up.append(selected_unit.grid_position + Vector2i(0,-i))
		active_overlay.set_cell(0, selected_unit.grid_position + Vector2i(0,-i), 0, Vector2i.ZERO)
		thrust_overlay_down.append(selected_unit.grid_position + Vector2i(0,i))
		active_overlay.set_cell(0, selected_unit.grid_position + Vector2i(0,i), 0, Vector2i.ZERO)
		thrust_overlay_right.append(selected_unit.grid_position + Vector2i(i,0))
		active_overlay.set_cell(0, selected_unit.grid_position + Vector2i(i,0), 0, Vector2i.ZERO)
		thrust_overlay_left.append(selected_unit.grid_position + Vector2i(-i,0))
		active_overlay.set_cell(0, selected_unit.grid_position + Vector2i(-i,0), 0, Vector2i.ZERO)

	for u in active_units.get_children():
		u.update_visual_state()
		if u.grid_position in thrust_positions and u.team != selected_unit.team:
			u.get_node("Sprite2D").modulate = Color(2, 0.5, 0.5)

func try_volley(volley_pos: Array[Vector2i]):
	var attacker_id = get_unit_identifier(selected_unit)
	var path_x: Array = []
	var path_y: Array = []
	var is_wrapped = false
	var attacker_old_x = selected_unit.original_position.x
	var attacker_old_y = selected_unit.original_position.y
	var volley_targets: Array = []

	for pos in volley_pos:
		for unit in active_units.get_children():
			if unit.grid_position == pos and unit.team != selected_unit.team:
				selected_unit.volley_attacking(unit)
				volley_targets.append(get_unit_identifier(unit))
				unit.update_visual_state()

	# Movimiento (igual que attack)
	if multiplayer.multiplayer_peer != null:
		if selected_unit.current_state == MapUnit.UnitState.MOVED:
			if selected_unit.has_meta("pending_move_path"):
				var pending_path: Array[Vector2i] = selected_unit.get_meta("pending_move_path")
				for p in pending_path:
					path_x.append(p.x)
					path_y.append(p.y)
				if selected_unit.has_meta("pending_move_is_wrapped"):
					is_wrapped = selected_unit.get_meta("pending_move_is_wrapped")
		sync_unit_move_and_volley.rpc(
			attacker_old_x, attacker_old_y,
			path_x, path_y, is_wrapped,
			attacker_id.team, attacker_id.unit_type,
			volley_targets
		)

	selected_unit.current_state = MapUnit.UnitState.MOVED
	active_overlay.clear()
	end_volley_mode()
	return

func try_thrust(thrust_pos):
	var attacker_id = get_unit_identifier(selected_unit)
	var path_x: Array = []
	var path_y: Array = []
	var is_wrapped = false
	var attacker_old_x = selected_unit.original_position.x
	var attacker_old_y = selected_unit.original_position.y
	var thrust_targets: Array = []

	for pos in thrust_pos:
		for unit in active_units.get_children():
			if unit.grid_position == pos and unit.team != selected_unit.team:
				selected_unit.thrust_attacking(unit)
				thrust_targets.append(get_unit_identifier(unit))
				unit.update_visual_state()

	# Movimiento (igual que attack)
	if multiplayer.multiplayer_peer != null:
		if selected_unit.current_state == MapUnit.UnitState.MOVED:
			if selected_unit.has_meta("pending_move_path"):
				var pending_path: Array[Vector2i] = selected_unit.get_meta("pending_move_path")
				for p in pending_path:
					path_x.append(p.x)
					path_y.append(p.y)
				if selected_unit.has_meta("pending_move_is_wrapped"):
					is_wrapped = selected_unit.get_meta("pending_move_is_wrapped")
		sync_unit_move_and_thrust.rpc(
			attacker_old_x, attacker_old_y,
			path_x, path_y, is_wrapped,
			attacker_id.team, attacker_id.unit_type,
			thrust_targets
		)

	selected_unit.current_state = MapUnit.UnitState.MOVED
	active_overlay.clear()
	end_thrust_mode()

func try_bash(bash_pos: Array[Vector2i]):
	var attacker_id = get_unit_identifier(selected_unit)
	var path_x: Array = []
	var path_y: Array = []
	var is_wrapped = false
	var attacker_old_x = selected_unit.original_position.x
	var attacker_old_y = selected_unit.original_position.y
	var bash_targets: Array = []

	for pos in bash_pos:
		for unit in active_units.get_children():
			if unit.grid_position == pos and unit.team != selected_unit.team:
				selected_unit.bash_attacking(unit)
				bash_targets.append(get_unit_identifier(unit))
				unit.update_visual_state()

	# Movimiento (igual que attack)
	if multiplayer.multiplayer_peer != null:
		if selected_unit.current_state == MapUnit.UnitState.MOVED:
			if selected_unit.has_meta("pending_move_path"):
				var pending_path: Array[Vector2i] = selected_unit.get_meta("pending_move_path")
				for p in pending_path:
					path_x.append(p.x)
					path_y.append(p.y)
				if selected_unit.has_meta("pending_move_is_wrapped"):
					is_wrapped = selected_unit.get_meta("pending_move_is_wrapped")

		sync_unit_move_and_bash.rpc(
			attacker_old_x, attacker_old_y,
			path_x, path_y, is_wrapped,
			attacker_id.team, attacker_id.unit_type,
			bash_targets
		)

	selected_unit.current_state = MapUnit.UnitState.MOVED
	active_overlay.clear()
	end_bash_mode()

func end_volley_mode():
	update_active_layers()
	volley_mode = false
	volley_tiles.clear()
	archer_attack_range_tiles.clear()
	active_overlay.clear()
	for unit in all_units:
		unit.update_visual_state()
	update_fog_of_war()

func end_bash_mode():
	update_active_layers()
	bash_mode = false
	bash_overlay_set.clear()
	current_bash_overlay.clear()
	for unit in all_units:
		unit.update_visual_state()
	update_fog_of_war()

func end_thrust_mode():
	update_active_layers()
	thrust_mode = false
	thrust_overlay_up.clear()
	thrust_overlay_down.clear()
	thrust_overlay_right.clear()
	thrust_overlay_left.clear()
	thrust_positions.clear()
	active_overlay.clear()
	for unit in all_units:
		unit.update_visual_state()
	update_fog_of_war()

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
			unit.grid_position = unit.original_position
			unit.global_position = Vector2(unit.grid_position * 32) + Vector2(16, 16)
			unit.select()
			unit.update_visual_state()
			# Limpiar metadata de movimiento pendiente si existe
			if unit.has_meta("pending_move_path"):
				unit.remove_meta("pending_move_path")
				unit.remove_meta("pending_move_is_wrapped")
			break
	if movement_arrow:
		movement_arrow.clear_points()
		is_tracing_path = false
		cursor_path.clear()
	close_action_menu()

func _on_move_confirmed():
	update_active_layers()
	close_action_menu()
	potential_targets.clear()
	
	for enemy in all_units:
		if enemy.team != player_id:
			enemy.update_visual_state()
	
	for unit in active_units.get_children():
		if unit.current_state == MapUnit.UnitState.SELECTED:
			# Actualizar grid_position a la posición final (donde está visualmente)
			var final_pos = Vector2i(unit.global_position / 32)
			unit.grid_position = final_pos
			
			# SINCRONIZAR: path completo SOLO cuando se confirma el movimiento
			if multiplayer.multiplayer_peer != null and unit.has_meta("pending_move_path"):
				var pending_path: Array[Vector2i] = unit.get_meta("pending_move_path")
				var is_wrapped: bool = unit.get_meta("pending_move_is_wrapped")
				
				# Convertir path a arrays de x e y para RPC
				var path_x: Array = []
				var path_y: Array = []
				for p in pending_path:
					path_x.append(p.x)
					path_y.append(p.y)
				
				sync_unit_move.rpc(unit.original_position.x, unit.original_position.y, path_x, path_y, is_wrapped, unit.team, unit.unit_type)
				
				# Limpiar metadata
				unit.remove_meta("pending_move_path")
				unit.remove_meta("pending_move_is_wrapped")
			
			unit.current_state = MapUnit.UnitState.MOVED
			unit.update_visual_state()
			break
	
	active_overlay.clear()
	update_fog_of_war()

@rpc("any_peer", "reliable")
func sync_unit_move(old_x: int, old_y: int, path_x: Array, path_y: Array, is_wrapped: bool, team: int, unit_type: String):
	var sender_id = multiplayer.get_remote_sender_id()
	# Validar que el sender tiene el turno actual
	var sender_player_id = 1 if sender_id == 1 else 2
	
	if sender_player_id != current_player_team:
		return
	
	# No procesar si es mi propia acción (ya la hice localmente)
	if sender_player_id == player_id:
		return
	
	var unit = find_unit_by_identifier({
		"x": old_x,
		"y": old_y,
		"team": team,
		"unit_type": unit_type
	})
	
	if unit:
		# Establecer explícitamente la posición original antes de comenzar el movimiento
		# Esto asegura que la unidad comience desde la posición correcta visualmente
		var original_pos = Vector2i(old_x, old_y)
		unit.original_position = original_pos
		unit.grid_position = original_pos
		# Establecer posición visual inmediatamente para evitar que se vea en el destino
		unit.global_position = Vector2(original_pos * 32) + Vector2(16, 16)
		
		# Usar call_deferred para asegurar que el tween comience después de que el frame se procese
		call_deferred("_start_rpc_movement", unit, path_x, path_y, is_wrapped)

func _start_rpc_movement(unit: MapUnit, path_x: Array, path_y: Array, is_wrapped: bool):
	# Asegurar que la posición visual esté correcta (por si acaso)
	unit.global_position = Vector2(unit.original_position * 32) + Vector2(16, 16)
	
	# Reconstruir el path desde los arrays de x e y
	var path: Array[Vector2i] = []
	for i in range(path_x.size()):
		path.append(Vector2i(path_x[i], path_y[i]))
	
	# Si el path incluye la posición original como primer elemento, removerla
	# (el jugador local ya está en esa posición, así que no necesita moverse allí)
	if not path.is_empty() and path[0] == unit.original_position:
		path = path.slice(1)
	
	# Si el path está vacío después de remover el primer elemento, no hacer nada
	if path.is_empty():
		return
	
	# Reproducir el movimiento usando el mismo sistema que el jugador local
	# Pasar from_rpc=true para evitar sincronización duplicada
	if is_wrapped:
		move_unit_along_wrapped_path(unit, path, true)
	else:
		move_unit_along_path(unit, path, true)

@rpc("any_peer", "reliable")
func sync_ambush_reveal(enemy_x: int, enemy_y: int, enemy_team: int, enemy_unit_type: String):
	var sender_id = multiplayer.get_remote_sender_id()
	var sender_player_id = 1 if sender_id == 1 else 2
	
	# No procesar si es mi propia acción (ya la hice localmente)
	if sender_player_id == player_id:
		return
	
	# Buscar la unidad enemiga
	var enemy = find_unit_by_identifier({
		"x": enemy_x,
		"y": enemy_y,
		"team": enemy_team,
		"unit_type": enemy_unit_type
	})
	
	if enemy:
		# Agregar la posición a las posiciones reveladas por ambush
		if enemy.grid_position not in ambush_revealed_positions:
			ambush_revealed_positions.append(enemy.grid_position)
		# Marcar la unidad como visible
		enemy.visible = true
		enemy.update_visual_state()
		update_fog_of_war()

func _on_attack_pressed():
	close_action_menu()
	show_attack_options(selected_unit)

func show_attack_options(unit: MapUnit):
	update_active_layers()
	selected_unit = unit
	attack_mode = true
	potential_targets.clear()
	for target in active_units.get_children():
		if target.visible and unit.can_attack(target):
			potential_targets.append(target)
			target.get_node("Sprite2D").modulate = Color(2, 0.5, 0.5)

func try_attack(grid_pos: Vector2i):
	update_active_layers()
	for unit in active_units.get_children():
		if unit.grid_position == grid_pos && selected_unit.can_attack(unit):
			selected_unit.attacking(unit)

			# SINCRONIZAR ATAQUE CON MOVIMIENTO (si se movió este turno)
			if multiplayer.multiplayer_peer != null:
				var attacker_id = get_unit_identifier(selected_unit)
				var target_id = get_unit_identifier(unit)

				# Si la unidad se movió, enviar path completo; si no, enviar path vacío
				var path_x: Array = []
				var path_y: Array = []
				var is_wrapped = false
				var attacker_old_x = selected_unit.original_position.x
				var attacker_old_y = selected_unit.original_position.y

				if selected_unit.current_state == MapUnit.UnitState.MOVED:
					# La unidad se movió este turno, enviar su path
					if selected_unit.has_meta("pending_move_path"):
						var pending_path: Array[Vector2i] = selected_unit.get_meta("pending_move_path")
						for p in pending_path:
							path_x.append(p.x)
							path_y.append(p.y)
						if selected_unit.has_meta("pending_move_is_wrapped"):
							is_wrapped = selected_unit.get_meta("pending_move_is_wrapped")

				# Enviar RPC con movimiento y ataque atomicamente
				sync_unit_move_and_attack.rpc(
					attacker_old_x, attacker_old_y,
					path_x, path_y, is_wrapped,
					attacker_id.team, attacker_id.unit_type,
					target_id.x, target_id.y, target_id.team, target_id.unit_type
				)

			# Limpiar selección visual sin cambiar el estado MOVED
			selected_unit.update_visual_state()
			hud.hide_unit_info()
			selected_unit = null
			end_attack_mode()
			active_overlay.clear()
			return

@rpc("any_peer", "reliable")
func sync_unit_move_and_volley(
	attacker_old_x: int, attacker_old_y: int,
	path_x: Array, path_y: Array, is_wrapped: bool,
	attacker_team: int, attacker_type: String,
	volley_targets: Array):

	var sender_id = multiplayer.get_remote_sender_id()
	var sender_player_id = 1 if sender_id == 1 else 2

	if sender_player_id != current_player_team:
		return
	if sender_player_id == player_id:
		return

	var attacker = find_unit_by_identifier({
		"x": attacker_old_x,
		"y": attacker_old_y,
		"team": attacker_team,
		"unit_type": attacker_type
	})
	if not attacker:
		return

	# Movimiento (idéntico a attack)
	if not path_x.is_empty():
		var path: Array[Vector2i] = []
		for i in range(path_x.size()):
			path.append(Vector2i(path_x[i], path_y[i]))

		if is_wrapped:
			move_unit_along_wrapped_path(attacker, path, true)
		else:
			move_unit_along_path(attacker, path, true)

		await get_tree().create_timer(path.size() * 0.14).timeout

	# VOLLEY REAL
	for t in volley_targets:
		var target = find_unit_by_identifier(t)
		if target:
			attacker.volley_attacking(target)

	update_fog_of_war()

@rpc("any_peer", "reliable")
func sync_unit_move_and_bash(
	attacker_old_x: int, attacker_old_y: int,
	path_x: Array, path_y: Array, is_wrapped: bool,
	attacker_team: int, attacker_type: String,
	bash_targets: Array):

	var sender_id = multiplayer.get_remote_sender_id()
	var sender_player_id = 1 if sender_id == 1 else 2

	if sender_player_id != current_player_team:
		return
	if sender_player_id == player_id:
		return

	var attacker = find_unit_by_identifier({
		"x": attacker_old_x,
		"y": attacker_old_y,
		"team": attacker_team,
		"unit_type": attacker_type
	})
	if not attacker:
		return

	# Movimiento (idéntico a attack)
	if not path_x.is_empty():
		var path: Array[Vector2i] = []
		for i in range(path_x.size()):
			path.append(Vector2i(path_x[i], path_y[i]))

		if is_wrapped:
			move_unit_along_wrapped_path(attacker, path, true)
		else:
			move_unit_along_path(attacker, path, true)

		await get_tree().create_timer(path.size() * 0.14).timeout

	# BASH REAL
	for t in bash_targets:
		var target = find_unit_by_identifier(t)
		if target:
			attacker.bash_attacking(target)

	update_fog_of_war()

@rpc("any_peer", "reliable")
func sync_unit_move_and_thrust(
	attacker_old_x: int, attacker_old_y: int,
	path_x: Array, path_y: Array, is_wrapped: bool,
	attacker_team: int, attacker_type: String,
	thrust_targets: Array):

	var sender_id = multiplayer.get_remote_sender_id()
	var sender_player_id = 1 if sender_id == 1 else 2

	if sender_player_id != current_player_team:
		return
	if sender_player_id == player_id:
		return

	var attacker = find_unit_by_identifier({
		"x": attacker_old_x,
		"y": attacker_old_y,
		"team": attacker_team,
		"unit_type": attacker_type
	})
	if not attacker:
		return

	# Movimiento (idéntico a attack)
	if not path_x.is_empty():
		var path: Array[Vector2i] = []
		for i in range(path_x.size()):
			path.append(Vector2i(path_x[i], path_y[i]))

		if is_wrapped:
			move_unit_along_wrapped_path(attacker, path, true)
		else:
			move_unit_along_path(attacker, path, true)

		await get_tree().create_timer(path.size() * 0.14).timeout

	# BASH REAL
	for t in thrust_targets:
		var target = find_unit_by_identifier(t)
		if target:
			attacker.thrust_attacking(target)

	update_fog_of_war()

@rpc("any_peer", "reliable")
func sync_unit_move_and_attack(
		attacker_old_x: int, attacker_old_y: int,
		path_x: Array, path_y: Array, is_wrapped: bool,
		attacker_team: int, attacker_type: String,
		target_x: int, target_y: int, target_team: int, target_type: String):
	
	var sender_id = multiplayer.get_remote_sender_id()
	var sender_player_id = 1 if sender_id == 1 else 2

	if sender_player_id != current_player_team:
		return

	if sender_player_id == player_id:
		return

	# Buscar la unidad atacante por su posición vieja (antes del movimiento)
	var attacker = find_unit_by_identifier({
		"x": attacker_old_x,
		"y": attacker_old_y,
		"team": attacker_team,
		"unit_type": attacker_type
	})

	if not attacker:
		return

	# PASO 1: Si hay path, reproducir el movimiento
	if not path_x.is_empty():
		# Reconstruir path desde arrays
		var path: Array[Vector2i] = []
		for i in range(path_x.size()):
			path.append(Vector2i(path_x[i], path_y[i]))

		# Aplicar movimiento visual (tween) y actualización de estado
		if is_wrapped:
			move_unit_along_wrapped_path(attacker, path, true)
		else:
			move_unit_along_path(attacker, path, true)

		# Esperar a que el tween termine (0.14s por tile aproximadamente)
		await get_tree().create_timer(path.size() * 0.14).timeout

	# PASO 2: Ejecutar el ataque
	var target = find_unit_by_identifier({
		"x": target_x,
		"y": target_y,
		"team": target_team,
		"unit_type": target_type
	})

	if target:
		attacker.attacking(target)
		update_fog_of_war()

func end_attack_mode():
	update_active_layers()
	attack_mode = false
	for unit in all_units:
		if unit in potential_targets or unit.modulate == Color(2, 0.5, 0.5):
			unit.update_visual_state()
	potential_targets.clear()
	update_fog_of_war()

func _on_mark_pressed():
	close_action_menu()
	update_active_layers()
	mark_mode = true
	potential_targets.clear()
	for target in all_units:
		if target.visible and selected_unit.can_mark(target):
			potential_targets.append(target)
			target.get_node("Sprite2D").modulate = Color(2, 0.5, 0.5)

func try_mark(grid_pos: Vector2i):
	update_active_layers()
	# Limpiar overlay inmediatamente para prevenir que unidades enemigas muestren su rango
	active_overlay.clear()
	
	for unit in all_units:
		if unit.grid_position == grid_pos && selected_unit.can_mark(unit):
			selected_unit.marking(unit)

			# SINCRONIZAR ATAQUE CON MOVIMIENTO (si se movió este turno)
			if multiplayer.multiplayer_peer != null:
				var attacker_id = get_unit_identifier(selected_unit)
				var target_id = get_unit_identifier(unit)

				# Si la unidad se movió, enviar path completo; si no, enviar path vacío
				var path_x: Array = []
				var path_y: Array = []
				var is_wrapped = false
				var attacker_old_x = selected_unit.original_position.x
				var attacker_old_y = selected_unit.original_position.y

				if selected_unit.current_state == MapUnit.UnitState.MOVED:
					# La unidad se movió este turno, enviar su path
					if selected_unit.has_meta("pending_move_path"):
						var pending_path: Array[Vector2i] = selected_unit.get_meta("pending_move_path")
						for p in pending_path:
							path_x.append(p.x)
							path_y.append(p.y)
						if selected_unit.has_meta("pending_move_is_wrapped"):
							is_wrapped = selected_unit.get_meta("pending_move_is_wrapped")

				# Enviar RPC con movimiento y ataque atomicamente
				sync_mark.rpc(
					attacker_old_x, attacker_old_y,
					path_x, path_y, is_wrapped,
					attacker_id.team, attacker_id.unit_type,
					target_id.x, target_id.y, target_id.team, target_id.unit_type
				)
			
			# Limpiar overlay nuevamente después del mark para asegurar
			active_overlay.clear()
			break

	selected_unit.current_state = MapUnit.UnitState.MOVED
	active_overlay.clear()
	end_mark_mode()

@rpc("any_peer", "reliable")
func sync_mark(
		attacker_old_x: int, attacker_old_y: int,
		path_x: Array, path_y: Array, is_wrapped: bool,
		attacker_team: int, attacker_type: String,
		target_x: int, target_y: int, target_team: int, target_type: String):
	
	var sender_id = multiplayer.get_remote_sender_id()
	var sender_player_id = 1 if sender_id == 1 else 2

	if sender_player_id != current_player_team:
		return

	if sender_player_id == player_id:
		return

	# Buscar la unidad atacante por su posición vieja (antes del movimiento)
	var attacker = find_unit_by_identifier({
		"x": attacker_old_x,
		"y": attacker_old_y,
		"team": attacker_team,
		"unit_type": attacker_type
	})

	if not attacker:
		return

	# PASO 1: Si hay path, reproducir el movimiento
	if not path_x.is_empty():
		# Reconstruir path desde arrays
		var path: Array[Vector2i] = []
		for i in range(path_x.size()):
			path.append(Vector2i(path_x[i], path_y[i]))

		# Aplicar movimiento visual (tween) y actualización de estado
		if is_wrapped:
			move_unit_along_wrapped_path(attacker, path, true)
		else:
			move_unit_along_path(attacker, path, true)

		# Esperar a que el tween termine (0.14s por tile aproximadamente)
		await get_tree().create_timer(path.size() * 0.14).timeout

	# PASO 2: Ejecutar el ataque
	var target = find_unit_by_identifier({
		"x": target_x,
		"y": target_y,
		"team": target_team,
		"unit_type": target_type
	})

	if target:
		attacker.marking(target)

	update_fog_of_war()

func end_mark_mode():
	update_active_layers()
	mark_mode = false
	for unit in all_units:
		unit.update_visual_state()
	potential_targets.clear()
	update_fog_of_war()

func _on_capture_pressed(unit: MapUnit, building: Building):
	close_action_menu()
	if building:
		@warning_ignore("narrowing_conversion", "integer_division")
		building.capture(unit, unit.health / 10, unit.team)
		# SINCRONIZAR CAPTURA
		if multiplayer.multiplayer_peer != null:
			sync_building_capture.rpc(building.building_position.x, building.building_position.y, building.team, building.capture_points)
	_on_move_confirmed()

@rpc("any_peer", "reliable")
func sync_building_capture(building_x: int, building_y: int, new_team: int, capture_points: int):
	var building = get_building_at(Vector2i(building_x, building_y))
	if building:
		building.team = new_team
		building.capture_points = capture_points
		building.update_visual()
		_on_building_ownership_changed(building)

@rpc("any_peer", "reliable")
func sync_unit_production(building_x: int, building_y: int, unit_type: String, team: int, cost: int):
	var unit_scene = load("res://scenes/units/" + unit_type + ".tscn")
	var unit_instance = unit_scene.instantiate()
	var color_suffix = "_Blue" if team == 1 else "_Red"
	var sprite_path = "res://art/units/%s1%s.png" % [unit_type, color_suffix]
	$Units.add_child(unit_instance)

	if unit_instance.get_node("Sprite2D") and ResourceLoader.exists(sprite_path):
		unit_instance.get_node("Sprite2D").texture = load(sprite_path)

	unit_instance.team = team
	unit_instance.grid_position = Vector2i(building_x, building_y)
	unit_instance.current_state = MapUnit.UnitState.MOVED
	unit_instance.update_visual_state()
	
	if team == 1:
		team1_funds -= cost
	elif team == 2:
		team2_funds -= cost
	
	all_units.append(unit_instance)
	hud.update_income_funds()
	update_fog_of_war()

func get_building_at(pos: Vector2i) -> Building:
	for b in $MapLayer/Buildings.get_children():
		if Vector2i(b.position / 32) == pos:
			return b
	return null

func get_attackable_tiles(unit: MapUnit) -> Array[Vector2i]:
	var attackable_tiles: Array[Vector2i] = []
	var reachable_cells = get_reachable_cells(unit.grid_position, unit.movement_range, unit, unit.is_raider())
	for move_cell in reachable_cells:
		for x in range(-unit.attack_range, unit.attack_range + 1):
			for y in range(-unit.attack_range, unit.attack_range + 1):
				var attack_pos = move_cell + Vector2i(x, y)
				if (abs(x) + abs(y)) <= unit.attack_range and _in_bounds(attack_pos):
					if attack_pos not in attackable_tiles:
						attackable_tiles.append(attack_pos)
	return attackable_tiles

func show_attack_range(unit: MapUnit):
	hide_attack_range()
	if not attack_range_overlay:
		attack_range_overlay = TileMap.new()
		attack_range_overlay.tile_set = standard_overlay.tile_set
		attack_range_overlay.z_index = 5
		add_child(attack_range_overlay)
	
	var attackable_tiles = get_attackable_tiles(unit)
	for tile_pos in attackable_tiles:
		attack_range_overlay.set_cell(0, tile_pos, 1, Vector2i.ZERO)
	showing_attack_range = true
	current_attack_range_unit = unit

func hide_attack_range():
	if attack_range_overlay:
		attack_range_overlay.clear()
	showing_attack_range = false
	current_attack_range_unit = null

func _on_building_ownership_changed(_building: Building):
	team1_income = 0
	team2_income = 0
	for b in $MapLayer/Buildings.get_children():
		if b.team == 1:
			team1_income += b.income_per_turn
		elif b.team == 2:
			team2_income += b.income_per_turn
	hud.update_income_funds()

func _on_resume_game():
	input_locked = false
	update_cursor_visibility()

func end_action_mode():
	if attack_mode:
		end_attack_mode()
	if bash_mode:
		end_bash_mode()
	if mark_mode:
		end_mark_mode()
	if thrust_mode:
		end_thrust_mode()
	if volley_mode:
		end_volley_mode()

func _on_exit_game():
	get_tree().quit()

func _in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.x < map_size.x and p.y >= 0 and p.y < map_size.y

func _process(_delta):
	# Verificar estado de conexión cuando estamos intentando conectarnos como cliente
	if is_connecting and multiplayer.multiplayer_peer != null:
		connection_check_timer += _delta
		connection_total_time += _delta
		
		if connection_check_timer >= 1.0:  # Cada segundo
			connection_check_timer = 0.0
			var status = multiplayer.multiplayer_peer.get_connection_status()
			
			# Si lleva más de 10 segundos conectando, considerar fallo
			if connection_total_time >= 10.0 and status == MultiplayerPeer.CONNECTION_CONNECTING:
				is_connecting = false
				connection_total_time = 0.0
				if multiplayer_menu:
					multiplayer_menu.set_status("Error: Timeout de conexión")
					multiplayer_menu.show()
			
			if status == MultiplayerPeer.CONNECTION_DISCONNECTED:
				is_connecting = false
				connection_total_time = 0.0
				if multiplayer_menu:
					multiplayer_menu.set_status("Error: No se pudo conectar")
					multiplayer_menu.show()
			elif status == MultiplayerPeer.CONNECTION_CONNECTED:
				# La señal debería haberse disparado, pero por si acaso...
				if player_id == 0:
					_on_connected_to_server()
	
	var mouse_p = get_global_mouse_position()
	var cursor_grid_pos = Vector2i(floor(mouse_p.x / 32.0), floor(mouse_p.y / 32.0))
	cursor_highlight.clear()
	
	if _in_bounds(cursor_grid_pos):
		cursor_highlight.set_cell(0, cursor_grid_pos, 0, Vector2i.ZERO)
		
		if not(is_menu_open or input_locked or is_action_mode()):
			for unit in active_units.get_children():
				if unit.current_state == MapUnit.UnitState.SELECTED:
					update_movement_arrow(unit, cursor_grid_pos)
					break
	else:
		cursor_highlight.clear()

	if thrust_mode == true:
		for pos in thrust_overlay_up:
			if cursor_grid_pos in thrust_overlay_up:
					active_overlay.set_cell(0,pos,1,Vector2i.ZERO)
			else:
				active_overlay.set_cell(0,pos,0,Vector2i.ZERO)
		for pos in thrust_overlay_down:
			if cursor_grid_pos in thrust_overlay_down:
					active_overlay.set_cell(0,pos,1,Vector2i.ZERO)
			else:
				active_overlay.set_cell(0,pos,0,Vector2i.ZERO)
		for pos in thrust_overlay_right:
			if cursor_grid_pos in thrust_overlay_right:
					active_overlay.set_cell(0,pos,1,Vector2i.ZERO)
			else:
				active_overlay.set_cell(0,pos,0,Vector2i.ZERO)
		for pos in thrust_overlay_left:
			if cursor_grid_pos in thrust_overlay_left:
					active_overlay.set_cell(0,pos,1,Vector2i.ZERO)
			else:
				active_overlay.set_cell(0,pos,0,Vector2i.ZERO)

	if bash_mode == true:
		var new_overlay: Array[Vector2i] = []

		# 1) Detectar ancla (solo 4 tiles)
		if cursor_grid_pos == selected_unit.grid_position + Vector2i(0, -1):
			new_overlay = bash_overlay_up
		elif cursor_grid_pos == selected_unit.grid_position + Vector2i(0, 1):
			new_overlay = bash_overlay_down
		elif cursor_grid_pos == selected_unit.grid_position + Vector2i(-1, 0):
			new_overlay = bash_overlay_left
		elif cursor_grid_pos == selected_unit.grid_position + Vector2i(1, 0):
			new_overlay = bash_overlay_right

		# 2) Si no tocó ancla, pero sigue dentro del overlay actual, mantenerlo
		elif current_bash_overlay.size() > 0 and cursor_grid_pos in current_bash_overlay:
			new_overlay = current_bash_overlay

		# 3) Si no está en ningún lado, limpiar
		else:
			new_overlay = []

		# 4) Aplicar solo si cambió
		if new_overlay != current_bash_overlay:
			current_bash_overlay = new_overlay
			active_overlay.clear()

			# Base gris
			for pos in bash_overlay_set:
				active_overlay.set_cell(0, pos, 0, Vector2i.ZERO)

			# Amarillo
			for pos in current_bash_overlay:
				active_overlay.set_cell(0, pos, 1, Vector2i.ZERO)


	if volley_mode == true:
		active_overlay.clear()
		volley_tiles.clear()
		for pos in archer_attack_range_tiles:
			active_overlay.set_cell(0,pos,0,Vector2i.ZERO)

		if cursor_grid_pos in archer_attack_range_tiles:
			active_overlay.set_cell(0,cursor_grid_pos,1,Vector2i.ZERO)
			active_overlay.set_cell(0,cursor_grid_pos + Vector2i(0,1),1,Vector2i.ZERO)
			active_overlay.set_cell(0,cursor_grid_pos + Vector2i(0,-1),1,Vector2i.ZERO)
			active_overlay.set_cell(0,cursor_grid_pos + Vector2i(1,0),1,Vector2i.ZERO)
			active_overlay.set_cell(0,cursor_grid_pos + Vector2i(-1,0),1,Vector2i.ZERO)
			volley_tiles.append(cursor_grid_pos)
			volley_tiles.append(cursor_grid_pos + Vector2i(0,1))
			volley_tiles.append(cursor_grid_pos + Vector2i(0,-1))
			volley_tiles.append(cursor_grid_pos + Vector2i(1,0))
			volley_tiles.append(cursor_grid_pos + Vector2i(-1,0))
			for u in active_units.get_children():
				u.update_visual_state()
				if u.grid_position in volley_tiles and u.team != selected_unit.team:
					u.get_node("Sprite2D").modulate = Color(2, 0.5, 0.5)
		else:
			for pos in archer_attack_range_tiles:
				active_overlay.clear()
			for u in active_units.get_children():
				u.update_visual_state()

func update_cursor_visibility():
	cursor_highlight.visible = not is_menu_open
