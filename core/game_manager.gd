class_name GameManager
extends Node

var team1_funds: int = 5000
var team2_funds: int = 5000
var team1_income: int = 0
var team2_income: int = 0

enum Element { EARTH, METAL, WATER, WOOD, FIRE }
var current_element: Element = Element.EARTH

var shade_view_enabled: bool = false
var local_player_id: int = 0

var current_map: Node2D
var all_units: Array[Unit] = []
var all_buildings: Array[Building] = []

signal funds_changed(team: int, amount: int)
signal element_changed(element: Element)
signal shade_view_toggled(enabled: bool)
signal unit_registered(unit: Unit)
signal unit_removed(unit: Unit)

func register_unit(unit: Unit) -> void:
	if unit not in all_units:
		all_units.append(unit)
		unit_registered.emit(unit)

func remove_unit(unit: Unit) -> void:
	all_units.erase(unit)
	unit_removed.emit(unit)

func register_building(building: Building) -> void:
	if building not in all_buildings:
		all_buildings.append(building)

func get_unit_by_id(id: int) -> Unit:
	for u in all_units:
		if u.unit_id == id:
			return u
	return null

func get_unit_at(pos: Vector2i) -> Unit:
	for u in all_units:
		if u.grid_position == pos:
			return u
	return null

func get_building_at(pos: Vector2i) -> Building:
	for b in all_buildings:
		if b.building_position == pos:
			return b
	return null

func get_funds(team: int) -> int:
	return team1_funds if team == 1 else team2_funds

func add_funds(team: int, amount: int) -> void:
	if team == 1:
		team1_funds += amount
	else:
		team2_funds += amount
	funds_changed.emit(team, get_funds(team))

func deduct_funds(team: int, amount: int) -> void:
	add_funds(team, -amount)

func recalculate_income() -> void:
	team1_income = 0
	team2_income = 0
	for b in all_buildings:
		if b.team == 1:
			team1_income += b.data.income_per_turn
		elif b.team == 2:
			team2_income += b.data.income_per_turn

func advance_element() -> void:
	current_element = ((current_element + 1) % Element.size()) as Element
	element_changed.emit(current_element)

func toggle_shade_view() -> void:
	shade_view_enabled = !shade_view_enabled
	shade_view_toggled.emit(shade_view_enabled)
