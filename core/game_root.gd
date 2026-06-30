class_name GameRoot
extends Node2D

@onready var game_manager = $GameManager
@onready var grid_system = $GridSystem
@onready var turn_manager = $TurnManager
@onready var action_system = $ActionSystem
@onready var fog_system = $FogSystem
@onready var current_map_container = $CurrentMap
@onready var hud = $HUD
@onready var multiplayer_manager = $MultiplayerManager
@onready var lobby = $Lobby

@export var map_scene: PackedScene

func _ready() -> void:
	var map = map_scene.instantiate()  # map_scene es la variable exportada
	current_map_container.add_child(map)
	game_manager.current_map = map
	var terrain = map.get_node("Terrain")
	var grid_layer = map.get_node("Grid")
	grid_system.initialize(terrain)
	_fill_layer(grid_layer)
	game_manager.grid_layer = grid_layer
	var fog_layer = map.get_node("Fog")
	var shade_fog_layer = map.get_node("ShadeFog")
	var shade_overlay = map.get_node("ShadeOverlay")
	fog_layer.visible = true
	_fill_layer(shade_overlay)
	fog_system.initialize(fog_layer, shade_fog_layer, shade_overlay)
	for unit in map.get_node("Units").get_children():
		if unit is Unit:
			unit.unit_id = randi_range(1, 999999)
			game_manager.register_unit(unit)
	for building in map.get_node("Buildings").get_children():
		if building is Building:
			game_manager.register_building(building)
			building.ownership_changed.connect(func(_b): game_manager.recalculate_income())
	game_manager.recalculate_income()
	game_manager.element_changed.connect(func(_e): hud.update_element())
	game_manager.funds_changed.connect(func(_team, _amount): hud.update_game_panel())
	turn_manager.turn_started.connect(func(_team): hud.update_game_panel())

func _fill_layer(layer: TileMapLayer) -> void:
	for x in range(grid_system.map_size.x):
		for y in range(grid_system.map_size.y):
			layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))

func start_multiplayer_game() -> void:
	game_manager.local_player_id = multiplayer_manager.player_id
	game_manager.is_network_game = true
	hud.update_game_panel()
	hud.update_element()
	turn_manager.turn_started.connect(func(team):
		if team == game_manager.local_player_id:
			hud.show_turn_message("¡Es tu turno!")
		else:
			hud.show_turn_message("¡Turno enemigo!")
	)
	if multiplayer_manager.player_id == 1:
		turn_manager.start_game()
		fog_system.recalculate(1)
		await get_tree().create_timer(0.1).timeout
		multiplayer_manager.send_initial_state_to_all()
