class_name ProduceAction
extends BaseAction

var building: Building
var unit_type: String
var cost: int

func _init(p_building: Building, p_unit_type: String, p_cost: int, p_team: int) -> void:
	type = Type.PRODUCE
	team = p_team
	building = p_building
	unit_type = p_unit_type
	cost = p_cost

func to_dict() -> Dictionary:
	return {
		"type": "PRODUCE",
		"building_x": building.building_position.x,
		"building_y": building.building_position.y,
		"unit_type": unit_type,
		"cost": cost,
		"team": team,
	}
