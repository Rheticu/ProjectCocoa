class_name ProduceAction
extends BaseAction

var building: Building
var unit_data: UnitData
var cost: int

func _init(p_building: Building, p_unit_data: UnitData, p_cost: int, p_team: int) -> void:
	type = Type.PRODUCE
	team = p_team
	building = p_building
	unit_data = p_unit_data
	cost = p_cost

func to_dict() -> Dictionary:
	return {
		"type":          "PRODUCE",
		"building_x":    building.building_position.x,
		"building_y":    building.building_position.y,
		"unit_type":     unit_data.unit_type,
		"is_shade":      unit_data.is_shade,
		"shade_element": unit_data.shade_element if unit_data.is_shade else "",
		"cost":          cost,
		"team":          team,
	}
