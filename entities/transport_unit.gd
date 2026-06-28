class_name TransportUnit
extends Unit

var carried_unit: Unit = null

func can_load(unit: Unit) -> bool:
	if carried_unit != null:
		return false
	if unit.unit_type not in ["Sword", "Archer", "Spear"]:
		return false
	if unit.team != team:
		return false
	return true

func load_unit(unit: Unit) -> void:
	carried_unit = unit
	unit.is_loaded = true
	unit.grid_position = grid_position
	unit.visible = false
	unit.state = Unit.State.MOVED
	unit.update_visual()

func unload_unit(tile: Vector2i) -> void:
	carried_unit.is_loaded = false
	carried_unit.grid_position = tile
	carried_unit.visible = true
	carried_unit.state = Unit.State.MOVED
	carried_unit.update_visual()
	carried_unit = null

func is_transport() -> bool:
	return true
