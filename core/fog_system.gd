class_name FogSystem
extends Node

@onready var game_manager = $"../GameManager"
@onready var grid_system = $"../GridSystem"

var _fog_layer: TileMapLayer
var _shade_fog_layer: TileMapLayer
var _shade_overlay: TileMapLayer
var _visible_tiles: Dictionary = {}
var _shade_visible_tiles: Dictionary = {}
var _last_known_building_team: Dictionary = {}  # building_position -> team

var enabled: bool = true:
	set(value):
		enabled = value
		if _fog_layer:
			_fog_layer.visible = value

func initialize(fog_layer: TileMapLayer, shade_fog_layer: TileMapLayer, shade_overlay: TileMapLayer) -> void:
	_fog_layer = fog_layer
	_shade_fog_layer = shade_fog_layer
	_shade_overlay = shade_overlay
	_fog_layer.collision_enabled = false
	_shade_fog_layer.collision_enabled = false
	_shade_overlay.collision_enabled = false
	_shade_fog_layer.visible = false
	_shade_overlay.visible = false

func recalculate(viewing_team: int) -> void:
	if not enabled:
		return
	if not _fog_layer:
		return
	# Calcular tiles visibles para AMBOS equipos
	for team in [1, 2]:
		var tiles: Dictionary = {}
		for unit in game_manager.all_units:
			if unit.team != team:
				continue
			for tile in grid_system.get_tiles_in_range(unit.grid_position, unit.vision_range, false):
				tiles[tile] = true
		for building in game_manager.all_buildings:
			if building.team == team:
				tiles[building.building_position] = true
		for unit in game_manager.all_units:
			if unit.team != team and unit.marked_turns > 0:
				tiles[unit.grid_position] = true
				if unit.marked2_turns > 0:
					for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
						var adj = unit.grid_position + dir
						if grid_system.is_in_bounds(adj):
							tiles[adj] = true
		_visible_tiles[team] = tiles
		var shade_tiles: Dictionary = {}
		for unit in game_manager.all_units:
			if unit.team != team or not unit.is_shade():
				continue
			for tile in grid_system.get_tiles_in_range(unit.grid_position, unit.vision_range, false):
				shade_tiles[tile] = true
				tiles[tile] = true
		_shade_visible_tiles[team] = shade_tiles
	# Solo aplicar visualmente para el equipo local
	_apply_fog(viewing_team)
	_update_unit_visibility(viewing_team)

func _apply_fog(viewing_team: int) -> void:
	for x in range(grid_system.map_size.x):
		for y in range(grid_system.map_size.y):
			var pos = Vector2i(x, y)
			if _visible_tiles.get(viewing_team, {}).has(pos):
				_fog_layer.erase_cell(pos)
			else:
				_fog_layer.set_cell(pos, 0, Vector2i(0, 0))
			if _shade_fog_layer:
				if _shade_visible_tiles.get(viewing_team, {}).has(pos):
					_shade_fog_layer.erase_cell(pos)
				else:
					_shade_fog_layer.set_cell(pos, 0, Vector2i(0, 0))
	
	for building in game_manager.all_buildings:
		var pos = building.building_position
		var tile_visible = _visible_tiles.get(viewing_team, {}).has(pos)  # ← nombre diferente

		# Manejar label de captura (solo si es visible)
		if building.has_node("CaptureLabel"):
			var label = building.get_node("CaptureLabel")
			if tile_visible and building.capture_points < building.max_capture_points:
				label.text = str(building.capture_points)
				label.visible = true
			else:
				label.visible = false

		# HQ siempre visible (si es HQ)
		if building.building_type == "HQ":
			building.show_as_team(building.team)
			continue

		# Para otros edificios
		if tile_visible:
			_last_known_building_team[pos] = building.team
			building.update_visual()
		else:
			var known_team = _last_known_building_team.get(pos, -1)
			if known_team == -1:
				building.show_as_team(0)
			else:
				building.show_as_team(known_team)

func _update_unit_visibility(viewing_team: int) -> void:
	var shade_view = game_manager.shade_view_enabled
	for unit in game_manager.all_units:
		if unit.team == viewing_team:
			if unit.is_shade():
				unit.visible = shade_view
			else:
				unit.visible = true
			continue
		if unit.marked_turns > 0:
					if unit.is_shade():
						unit.visible = shade_view
					else:
						unit.visible = true
					continue
		if unit.is_shade():
			unit.visible = shade_view and _shade_visible_tiles.get(viewing_team, {}).has(unit.grid_position)
		else:
			unit.visible = _visible_tiles.get(viewing_team, {}).has(unit.grid_position)

func is_visible(pos: Vector2i, team: int) -> bool:
	if not enabled:
		return true
	return _visible_tiles.get(team, {}).has(pos)

func update_shade_view(shade_enabled: bool, viewing_team: int) -> void:
	_shade_overlay.visible = shade_enabled
	_shade_fog_layer.visible = shade_enabled
	_fog_layer.visible = not shade_enabled
	_update_unit_visibility(viewing_team)

func is_shade_visible(pos: Vector2i, team: int) -> bool:
	if not enabled:
		return true
	return _shade_visible_tiles.get(team, {}).has(pos)
