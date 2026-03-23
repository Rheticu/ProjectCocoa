class_name FogSystem
extends Node

@onready var game_manager = $"../GameManager"
@onready var grid_system = $"../GridSystem"

var _fog_layer: TileMapLayer
var _visible_tiles: Dictionary = {}

func initialize(fog_layer: TileMapLayer) -> void:
	_fog_layer = fog_layer

func recalculate(viewing_team: int) -> void:
	if not _fog_layer:
		return

	_visible_tiles.clear()
	var shade_view = game_manager.shade_view_enabled

	# Visión desde unidades propias
	for unit in game_manager.all_units:
		if unit.team != viewing_team:
			continue
		# En vista normal: solo unidades normales revelan
		# En vista shade: todos revelan (shades revelan ambas capas)
		if not shade_view and unit.is_shade():
			continue
		var use_wrap = unit.is_shade()
		for tile in grid_system.get_tiles_in_range(unit.grid_position, unit.vision_range, use_wrap):
			_visible_tiles[tile] = true

	# Visión desde edificios propios
	for building in game_manager.all_buildings:
		if building.team == viewing_team:
			_visible_tiles[building.building_position] = true

	# Unidades marcadas siempre visibles
	for unit in game_manager.all_units:
		if unit.team != viewing_team and unit.marked_turns > 0:
			_visible_tiles[unit.grid_position] = true

	_apply_fog()
	_update_unit_visibility(viewing_team)

func _apply_fog() -> void:
	for x in range(grid_system.map_size.x):
		for y in range(grid_system.map_size.y):
			var pos = Vector2i(x, y)
			if _visible_tiles.has(pos):
				_fog_layer.set_cell(pos, -1)
			else:
				_fog_layer.set_cell(pos, 0)

func _update_unit_visibility(viewing_team: int) -> void:
	for unit in game_manager.all_units:
		if unit.team == viewing_team:
			unit.visible = true
			continue
		if unit.marked_turns > 0:
			unit.visible = true
			continue
		unit.visible = _visible_tiles.has(unit.grid_position)

func is_visible(pos: Vector2i) -> bool:
	return _visible_tiles.has(pos)
