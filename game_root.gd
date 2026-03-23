class_name GameRoot
extends Node2D

@onready var game_manager = $GameManager
@onready var grid_system = $GridSystem
@onready var turn_manager = $TurnManager
@onready var action_system = $ActionSystem
@onready var fog_system = $FogSystem
@onready var current_map_container: Node2D = $CurrentMap

func _ready() -> void:
	# Cargar mapa
	var map_scene = load("res://scenes/maps/Map1.tscn")
	var map = map_scene.instantiate()
	current_map_container.add_child(map)
	game_manager.current_map = map

	# Inicializar GridSystem
	var terrain = map.get_node("Terrain")
	grid_system.initialize(terrain)

	# Inicializar FogSystem
	var fog_layer = map.get_node("Fog")
	fog_system.initialize(fog_layer)

	# Registrar unidades del mapa
	for unit in map.get_node("Units").get_children():
		if unit is Unit:
			unit.unit_id = randi_range(1, 999999)
			game_manager.register_unit(unit)

	# Registrar edificios
	for building in map.get_node("Buildings").get_children():
		if building is Building:
			game_manager.register_building(building)

	game_manager.recalculate_income()

	# Para probar: jugador local es equipo 1
	game_manager.local_player_id = 1
	turn_manager.start_game()
	fog_system.recalculate(1)
