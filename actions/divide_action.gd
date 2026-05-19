class_name DivideAction
extends BaseAction

var target_pos: Vector2i
var move_path: Array[Vector2i] = []
var new_unit_id: int = -1

func _init(p_actor: Drone, p_target_pos: Vector2i, p_path: Array[Vector2i] = []) -> void:
	type = Type.DIVIDE
	actor = p_actor
	team = p_actor.team
	target_pos = p_target_pos
	move_path = p_path

func to_dict() -> Dictionary:
	var path_x: Array = []
	var path_y: Array = []
	for p in move_path:
		path_x.append(p.x)
		path_y.append(p.y)
	return {
		"type": "DIVIDE",
		"actor_id": actor.unit_id,
		"target_x": target_pos.x,
		"target_y": target_pos.y,
		"path_x": path_x,
		"path_y": path_y,
		"new_unit_id": new_unit_id
	}
