class_name TurnManager
extends Node

@onready var game_manager = $"../GameManager"

var current_team: int = 1
var turn_number: int = 1

signal turn_started(team: int)
signal turn_ended(team: int)

func start_game() -> void:
	current_team = 1
	turn_number = 1
	_begin_turn(current_team)

func _begin_turn(team: int) -> void:
	current_team = team

	for unit in game_manager.all_units:
		unit.tick_buffs()
		if unit.team == team and unit.is_in_overwatch:
			game_manager.clear_overwatch(unit)

	game_manager.recalculate_income()
	var income = game_manager.team1_income if team == 1 else game_manager.team2_income
	game_manager.add_funds(team, income)

	for unit in game_manager.all_units:
		if unit.is_shade() and unit.team == team:
			var shade = unit as Shade
			if shade.mana < shade.max_mana:
				shade.mana += 1

	for unit in game_manager.all_units:
		if unit.team == team:
			unit.state = Unit.State.IDLE
			unit.update_visual()

	game_manager.local_player_id = team
	turn_started.emit(team)

func end_turn(team: int) -> void:
	if team != current_team:
		return
	turn_ended.emit(team)
	if current_team == 2:
		game_manager.advance_element()
		turn_number += 1
	current_team = 2 if current_team == 1 else 1
	_begin_turn(current_team)

func is_my_turn(team: int) -> bool:
	return current_team == team
