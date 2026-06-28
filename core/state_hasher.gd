class_name StateHasher
extends Node

@onready var game_manager = $"../GameManager"
@onready var turn_manager = $"../TurnManager"

func compute_state_string() -> String:
	var parts: Array = []

	# Turno y equipo
	parts.append("turn:%d" % turn_manager.turn_number)
	parts.append("team:%d" % turn_manager.current_team)
	parts.append("element:%d" % game_manager.current_element)

	# Fondos
	parts.append("f1:%d" % game_manager.team1_funds)
	parts.append("f2:%d" % game_manager.team2_funds)

	# Unidades — ordenadas por unit_id para ser deterministas
	var units = game_manager.all_units.duplicate()
	units.sort_custom(func(a, b): return a.unit_id < b.unit_id)
	for u in units:
		var entry = "u:%d,pos:%d:%d,hp:%d,mk:%d,sh:%d,bo:%d,mu:%d,loaded:%d" % [
			u.unit_id,
			u.grid_position.x, u.grid_position.y,
			u.health,
			u.marked_turns, u.shield_turns,
			u.boost_turns, u.muddle_turns,
			1 if u.is_loaded else 0
		]
		if u.is_shade():
			entry += ",mana:%d" % (u as Shade).mana
		if u is TransportUnit:
			var t = u as TransportUnit
			entry += ",carried:%d" % (t.carried_unit.unit_id if t.carried_unit else -1)
		parts.append(entry)

	# Buildings — ordenados por posición
	var buildings = game_manager.all_buildings.duplicate()
	buildings.sort_custom(func(a, b): 
		if a.building_position.x != b.building_position.x:
			return a.building_position.x < b.building_position.x
		return a.building_position.y < b.building_position.y
	)
	for b in buildings:
		parts.append("b:%d:%d,team:%d,cp:%d" % [
			b.building_position.x, b.building_position.y,
			b.team, b.capture_points
		])

	return "|".join(parts)

func compute_checksum() -> int:
	return compute_state_string().hash()
