class_name EndTurnAction
extends BaseAction

func _init(p_team: int) -> void:
	type = Type.END_TURN
	team = p_team

func to_dict() -> Dictionary:
	return { "type": "END_TURN", "team": team }
