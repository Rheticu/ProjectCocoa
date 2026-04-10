class_name SpecialAction
extends BaseAction

var ability_type: String
var targets: Array[Unit] = []
var move_path: Array[Vector2i] = []
var direction: Vector2i

func _init(p_actor: Unit, p_ability_type: String, p_targets: Array[Unit], p_direction: Vector2i, p_path: Array[Vector2i] = []) -> void:
	type = Type.SPECIAL
	actor = p_actor
	team = p_actor.team
	ability_type = p_ability_type
	targets = p_targets
	direction = p_direction
	move_path = p_path

func to_dict() -> Dictionary:
	var path_x: Array = []
	var path_y: Array = []
	for p in move_path:
		path_x.append(p.x)
		path_y.append(p.y)
	var target_ids: Array = []
	for t in targets:
		target_ids.append(t.unit_id)
	return {
		"type":         "SPECIAL",
		"actor_id":     actor.unit_id,
		"ability_type": ability_type,
		"target_ids":   target_ids,
		"path_x":       path_x,
		"path_y":       path_y,
		"dir_x":        direction.x,
		"dir_y":        direction.y,
	}
