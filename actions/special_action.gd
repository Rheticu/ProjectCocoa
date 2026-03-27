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
