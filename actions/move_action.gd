class_name MoveAction
extends BaseAction

var path: Array[Vector2i] = []
var is_wrapped: bool = false
var skip_animation: bool = false

func _init(p_actor: Unit, p_path: Array[Vector2i], p_wrapped: bool = false) -> void:
	type = Type.MOVE
	actor = p_actor
	team = p_actor.team
	path = p_path
	is_wrapped = p_wrapped

func to_dict() -> Dictionary:
	print("to_dict path: ", path)
	var path_x: Array = []
	var path_y: Array = []
	for p in path:
		path_x.append(p.x)
		path_y.append(p.y)
	return {
		"type": "MOVE",
		"actor_id": actor.unit_id,
		"path_x": path_x,
		"path_y": path_y,
		"is_wrapped": is_wrapped,
	}
