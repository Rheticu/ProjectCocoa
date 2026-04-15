class_name CombatSystem
extends Node

@onready var game_manager = $"../GameManager"
@onready var grid_system = $"../GridSystem"

signal combat_happened(attacker: Unit, target: Unit, damage_dealt: int, counter_damage: int)
signal unit_died(unit: Unit)

func execute_attack(attacker: Unit, target: Unit) -> void:
	var damage = calculate_damage(attacker, target)
	target.health -= damage

	var counter = 0
	if target.health > 0 and _can_counterattack(target, attacker):
		counter = calculate_damage(target, attacker)
		attacker.health -= counter

	attacker.state = Unit.State.MOVED
	attacker.update_visual()
	target.update_visual()

	combat_happened.emit(attacker, target, damage, counter)

	if target.check_death():
		_handle_death(target)
	if attacker.check_death():
		_handle_death(attacker)

func execute_ability(shade: Shade, ability: String, target: Unit, current_element: GameManager.Element) -> void:
	shade.mana -= 2
	match ability:
		"MARK":
			target.marked_turns = 4 if current_element == GameManager.Element.WATER else 2
		"SCORCH":
			var multiplier = 2.5 if current_element == GameManager.Element.FIRE else 1.0
			var dmg = int(max(0.0, multiplier * shade.health/5 - target.get_total_defense(0)))
			target.health -= dmg
			target.update_visual()
			if target.check_death():
				_handle_death(target)
		"SHIELD":
			target.shield_turns = 4 if current_element == GameManager.Element.METAL else 2
		"MUDDLE":
			target.muddle_turns = 4 if current_element == GameManager.Element.EARTH else 2
		"BOOST":
			target.boost_turns = 4 if current_element == GameManager.Element.WOOD else 2
	shade.state = Unit.State.MOVED
	shade.update_visual()
	target.update_visual()

func execute_thrust(attacker: Unit, targets: Array[Unit]) -> void:
	for target in targets:
		if not is_instance_valid(target):
			continue
		if not target.visible:
			continue
		var damage = int(calculate_damage(attacker, target) * 0.8)
		target.health -= damage
		target.update_visual()
		if target.check_death():
			_handle_death(target)
	attacker.state = Unit.State.MOVED
	attacker.update_visual()

func execute_bash(attacker: Unit, targets: Array[Unit]) -> void:
	for target in targets:
		if not is_instance_valid(target):
			continue
		if not target.visible:
			continue
		var damage = int(calculate_damage(attacker, target) * 0.7)
		target.health -= damage
		target.update_visual()
		if target.check_death():
			_handle_death(target)
	attacker.state = Unit.State.MOVED
	attacker.update_visual()

func execute_volley(attacker: Unit, targets: Array[Unit]) -> void:
	for target in targets:
		if not is_instance_valid(target):
			continue
		if not target.visible:
			continue
		var damage = int(calculate_damage(attacker, target) * 0.6)
		target.health -= damage
		target.update_visual()
		if target.check_death():
			_handle_death(target)
	attacker.state = Unit.State.MOVED
	attacker.update_visual()

func calculate_damage(attacker: Unit, target: Unit) -> int:
	var multiplier = _get_type_multiplier(attacker.get_effective_type(), target.get_effective_type())
	var attack_mod = 1.0
	if attacker.muddle_turns > 0:
		attack_mod = 1.0 / 3.0
	elif attacker.boost_turns > 0:
		attack_mod = 2.0
	var terrain = grid_system.get_terrain_type(target.grid_position)
	var terrain_bonus = _get_defense_bonus(terrain)
	if target.is_shade():
		terrain_bonus = 0
	var base = multiplier * attacker.attack * attacker.health / 100.0
	return int(max(0.0, base * attack_mod - target.get_total_defense(terrain_bonus)))

func can_attack(attacker: Unit, target: Unit) -> bool:
	if attacker.team == target.team:
		return false
	if attacker.state == Unit.State.MOVED or attacker.state == Unit.State.IDLE:
		return false
	if attacker.is_shade() != target.is_shade():
		return false
	var dist = grid_system.manhattan_distance(attacker.grid_position, target.grid_position, attacker.is_shade())
	return dist <= attacker.attack_range

func can_use_ability(shade: Shade, target: Unit) -> bool:
	if shade.mana < 2:
		return false
	if shade.state == Unit.State.MOVED:
		return false
	var dist = grid_system.manhattan_distance(shade.grid_position, target.grid_position, true)
	return dist <= shade.ability_range

func _can_counterattack(counterattacker: Unit, original_attacker: Unit) -> bool:
	var dist = grid_system.manhattan_distance(counterattacker.grid_position, original_attacker.grid_position, counterattacker.is_shade())
	return dist <= counterattacker.attack_range

func _handle_death(unit: Unit) -> void:
	unit_died.emit(unit)
	game_manager.remove_unit(unit)
	unit.queue_free()

func _get_type_multiplier(attacker_type: String, defender_type: String) -> float:
	var matrix = {
		"Sword:Sword":1.0,"Sword:Archer":1,"Sword:Spear":0.6,"Sword:Cannon":2.0,"Sword:Junker":0.2,
		"Archer:Sword":1,"Archer:Archer":1.0,"Archer:Spear":1.8,"Archer:Cannon":1.0,"Archer:Junker":0.5,
		"Spear:Sword":1.8,"Spear:Archer":1.5,"Spear:Spear":1.0,"Spear:Cannon":1.2,"Spear:Junker":0.5,
		"Cannon:Sword":1,"Cannon:Archer":1,"Cannon:Spear":1,"Cannon:Cannon":1,"Cannon:Junker":1,
		"Junker:Sword":1.0,"Junker:Archer":1.0,"Junker:Spear":1.0,"Junker:Cannon":1.0,"Junker:Junker":1.0,
		"Shade_FIRE:Shade_FIRE":1.0,"Shade_FIRE:Shade_WATER":0.66,"Shade_FIRE:Shade_EARTH":1.0,"Shade_FIRE:Shade_WOOD":1.0,"Shade_FIRE:Shade_METAL":1.5,
		"Shade_WATER:Shade_FIRE":1.5,"Shade_WATER:Shade_WATER":1.0,"Shade_WATER:Shade_EARTH":0.66,"Shade_WATER:Shade_WOOD":1.0,"Shade_WATER:Shade_METAL":1.0,
		"Shade_EARTH:Shade_FIRE":0.66,"Shade_EARTH:Shade_WATER":1.5,"Shade_EARTH:Shade_EARTH":1.0,"Shade_EARTH:Shade_WOOD":1.0,"Shade_EARTH:Shade_METAL":1.0,
		"Shade_WOOD:Shade_FIRE":1.0,"Shade_WOOD:Shade_WATER":1.0,"Shade_WOOD:Shade_EARTH":1.5,"Shade_WOOD:Shade_WOOD":1.0,"Shade_WOOD:Shade_METAL":0.66,
		"Shade_METAL:Shade_FIRE":0.66,"Shade_METAL:Shade_WATER":1.0,"Shade_METAL:Shade_EARTH":1.0,"Shade_METAL:Shade_WOOD":1.5,"Shade_METAL:Shade_METAL":1.0,
	}
	return matrix.get(attacker_type + ":" + defender_type, 0.0)

func _get_defense_bonus(terrain: String) -> int:
	var bonuses = {
		"PLAINS":4,"FOREST":6,"MOUNTAIN":8,"WALL":99,"ROAD":0,"RIVER":-4,"OCEAN":4,"BUILDING":10
	}
	return bonuses.get(terrain, 0)

func execute_overwatch_attack(attacker: Unit, target: Unit) -> void:
	var damage = calculate_damage(attacker, target)
	target.health -= damage
	target.update_visual()
	if target.check_death():
		_handle_death(target)
	attacker.state = Unit.State.MOVED
	attacker.update_visual()
