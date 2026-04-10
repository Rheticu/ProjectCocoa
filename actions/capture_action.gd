class_name CaptureAction
extends BaseAction

var building: Building
var move_path: Array[Vector2i] = []

func _init(p_actor: Unit, p_building: Building, p_path: Array[Vector2i] = []) -> void:
	type = Type.CAPTURE
	actor = p_actor
	team = p_actor.team
	building = p_building
	move_path = p_path

func to_dict() -> Dictionary:
	var path_x: Array = []
	var path_y: Array = []
	for p in move_path:
		path_x.append(p.x)
		path_y.append(p.y)
	return {
		"type":       "CAPTURE",
		"actor_id":   actor.unit_id,
		"building_x": building.building_position.x,
		"building_y": building.building_position.y,
		"path_x":     path_x,
		"path_y":     path_y,
	}
