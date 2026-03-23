class_name BaseAction
extends RefCounted

enum Type { MOVE, ATTACK, ABILITY, CAPTURE, PRODUCE, END_TURN }

var type: Type
var actor: Unit
var team: int

func to_dict() -> Dictionary:
	return {}
