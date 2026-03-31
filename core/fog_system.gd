class_name FogSystem
extends Node

@onready var game_manager = $"../GameManager"
@onready var grid_system = $"../GridSystem"

var _fog_layer: TileMapLayer
var _visible_tiles: Dictionary = {}
var enabled: bool = true:
	set(value):
		enabled = value
		if _fog_layer:
			_fog_layer.visible = value

func initialize(fog_layer: TileMapLayer) -> void:
	_fog_layer = fog_layer

func recalculate(viewing_team: int) -> void:
	if not enabled:
		return
	if not _fog_layer:
		return

	var tiles: Dictionary = {}

	for unit in game_manager.all_units:
		if unit.team != viewing_team:
			continue
		if unit.is_shade():
			continue
		for tile in grid_system.get_tiles_in_range(unit.grid_position, unit.vision_range, false):
			tiles[tile] = true

	for building in game_manager.all_buildings:
		if building.team == viewing_team:
			tiles[building.building_position] = true

	for unit in game_manager.all_units:
		if unit.team != viewing_team and unit.marked_turns > 0:
			tiles[unit.grid_position] = true

	_visible_tiles[viewing_team] = tiles
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

func _update_unit_visibility(viewing_team: int) -> void:
	for unit in game_manager.all_units:
		if unit.team == viewing_team:
			unit.visible = true
			continue
		if unit.marked_turns > 0:
			unit.visible = true
			continue
		unit.visible = _visible_tiles.get(viewing_team, {}).has(unit.grid_position)

func is_visible(pos: Vector2i, team: int) -> bool:
	if not enabled:
		return true
	return _visible_tiles.get(team, {}).has(pos)
