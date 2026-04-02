class_name GameRoot
extends Node2D

@onready var game_manager = $GameManager
@onready var grid_system = $GridSystem
@onready var turn_manager = $TurnManager
@onready var action_system = $ActionSystem
@onready var fog_system = $FogSystem
@onready var current_map_container = $CurrentMap
@onready var hud = $HUD

func _ready() -> void:
	# Cargar mapa
	var map_scene = load("res://scenes/maps/Map1.tscn")
	var map = map_scene.instantiate()
	current_map_container.add_child(map)
	game_manager.current_map = map

	# Inicializar GridSystem
	var terrain = map.get_node("Terrain")
	var grid_layer = map.get_node("Grid")
	grid_system.initialize(terrain)
	_fill_layer(grid_layer)
	game_manager.grid_layer = grid_layer

	# Inicializar FogSystem
	var fog_layer = map.get_node("Fog")
	var shade_fog_layer = map.get_node("ShadeFog")
	var shade_overlay = map.get_node("ShadeOverlay")
	fog_layer.visible = true
	_fill_layer(shade_overlay)
	fog_system.initialize(fog_layer, shade_fog_layer, shade_overlay)

	# Registrar unidades del mapa
	for unit in map.get_node("Units").get_children():
		if unit is Unit:
			unit.unit_id = randi_range(1, 999999)
			game_manager.register_unit(unit)

	# Registrar edificios
	for building in map.get_node("Buildings").get_children():
		if building is Building:
			game_manager.register_building(building)
			building.ownership_changed.connect(func(_b): game_manager.recalculate_income())

	game_manager.recalculate_income()
	game_manager.element_changed.connect(func(_e): hud.update_element())
	# Para probar: jugador local es equipo 1
	game_manager.local_player_id = 1
	turn_manager.start_game()
	fog_system.recalculate(1)

	hud.update_funds()
	hud.update_element()
	game_manager.funds_changed.connect(func(_team, _amount): hud.update_funds())
	turn_manager.turn_started.connect(func(_team): hud.update_funds())

func _fill_layer(layer: TileMapLayer) -> void:
	for x in range(grid_system.map_size.x):
		for y in range(grid_system.map_size.y):
			layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
