class_name OverwatchAction
extends BaseAction

func _init(p_actor: Unit) -> void:
	type = Type.OVERWATCH
	actor = p_actor
	team = p_actor.team
