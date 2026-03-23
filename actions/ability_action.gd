class_name AbilityAction
extends BaseAction

var ability: String = ""
var target: Unit
var move_path: Array[Vector2i] = []
var is_wrapped: bool = false

func _init(p_actor: Unit, p_ability: String, p_target: Unit,
		p_path: Array[Vector2i] = [], p_wrapped: bool = false) -> void:
	type = Type.ABILITY
	actor = p_actor
	team = p_actor.team
	ability = p_ability
	target = p_target
	move_path = p_path
	is_wrapped = p_wrapped

func to_dict() -> Dictionary:
	var path_x: Array = []
	var path_y: Array = []
	for p in move_path:
		path_x.append(p.x)
		path_y.append(p.y)
	return {
		"type": "ABILITY",
		"actor_id": actor.unit_id,
		"ability": ability,
		"target_id": target.unit_id,
		"path_x": path_x,
		"path_y": path_y,
		"is_wrapped": is_wrapped,
	}
