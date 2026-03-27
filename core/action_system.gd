class_name ActionSystem
extends Node

@onready var game_manager = $"../GameManager"
@onready var turn_manager = $"../TurnManager"
@onready var movement_system = $"../MovementSystem"
@onready var combat_system = $"../CombatSystem"
@onready var fog_system = $"../FogSystem"

signal action_executed(action: BaseAction)
signal action_rejected(reason: String)
signal move_animation_requested(unit: Unit, path: Array[Vector2i])
signal move_confirmed(unit: Unit)

var _is_executing: bool = false

func queue_action(action: BaseAction) -> void:
	if _is_executing:
		action_rejected.emit("Acción en curso")
		return
	if not _validate(action):
		return
	_execute(action)

func _validate(action: BaseAction) -> bool:
	if not turn_manager.is_my_turn(action.team):
		action_rejected.emit("No es tu turno")
		return false
	match action.type:
		BaseAction.Type.MOVE:     return _validate_move(action as MoveAction)
		BaseAction.Type.ATTACK:   return _validate_attack(action as AttackAction)
		BaseAction.Type.ABILITY:  return _validate_ability(action as AbilityAction)
		BaseAction.Type.CAPTURE:  return _validate_capture(action as CaptureAction)
		BaseAction.Type.PRODUCE:  return _validate_produce(action as ProduceAction)
		BaseAction.Type.SPECIAL: return _validate_special(action as SpecialAction)
		BaseAction.Type.END_TURN: return true
	return false

func _validate_move(action: MoveAction) -> bool:
	if action.actor.state == Unit.State.MOVED or action.actor.state == Unit.State.IDLE:
		action_rejected.emit("Unidad ya se movió")
		return false
	if action.path.is_empty():
		action_rejected.emit("Path vacío")
		return false
	var destination = action.path.back()
	var reachable = movement_system.get_reachable_cells(action.actor)
	if destination not in reachable:
		action_rejected.emit("Destino no alcanzable")
		return false
	# Verificar que el tile final esté libre
	if not movement_system.is_position_free(destination, action.actor, true):
		action_rejected.emit("Casilla ocupada")
		return false
	return true

func _validate_attack(action: AttackAction) -> bool:
	if not combat_system.can_attack(action.actor, action.target):
		action_rejected.emit("No puede atacar")
		return false
	return true

func _validate_ability(action: AbilityAction) -> bool:
	var shade = action.actor as Shade
	if not shade:
		action_rejected.emit("No es un Shade")
		return false
	if not combat_system.can_use_ability(shade, action.target):
		action_rejected.emit("No puede usar habilidad")
		return false
	return true

func _validate_capture(action: CaptureAction) -> bool:
	if action.building.team == action.team:
		action_rejected.emit("Ya es tuyo")
		return false
	if action.actor.unit_type not in ["Sword", "Archer", "Spear"]:
		action_rejected.emit("Esta unidad no puede capturar")
		return false
	return true

func _validate_produce(action: ProduceAction) -> bool:
	if game_manager.get_funds(action.team) < action.cost:
		action_rejected.emit("Fondos insuficientes")
		return false
	return true

func _execute(action: BaseAction) -> void:
	_is_executing = true
	match action.type:
		BaseAction.Type.MOVE:     await _execute_move(action as MoveAction)
		BaseAction.Type.ATTACK:   await _execute_attack(action as AttackAction)
		BaseAction.Type.ABILITY:  await _execute_ability(action as AbilityAction)
		BaseAction.Type.CAPTURE:  _execute_capture(action as CaptureAction)
		BaseAction.Type.PRODUCE:  _execute_produce(action as ProduceAction)
		BaseAction.Type.END_TURN: _execute_end_turn(action as EndTurnAction)
		BaseAction.Type.SPECIAL: await _execute_special(action as SpecialAction)
	_is_executing = false
	action_executed.emit(action)
	var _viewing_team = game_manager.local_player_id if game_manager.local_player_id > 0 else 1
	#fog_system.recalculate(_viewing_team)

func _execute_move(action: MoveAction) -> void:
	if action.path.is_empty():
		return
	move_animation_requested.emit(action.actor, action.path)
	await move_confirmed
	action.actor.grid_position = action.path.back()

func _execute_attack(action: AttackAction) -> void:
	if not action.move_path.is_empty():
		var move = MoveAction.new(action.actor, action.move_path, action.is_wrapped)
		await _execute_move(move)
	combat_system.execute_attack(action.actor, action.target)

func _execute_ability(action: AbilityAction) -> void:
	if not action.move_path.is_empty():
		var move = MoveAction.new(action.actor, action.move_path, action.is_wrapped)
		await _execute_move(move)
	var shade = action.actor as Shade
	combat_system.execute_ability(shade, action.ability, action.target, game_manager.current_element)

func _execute_capture(action: CaptureAction) -> void:
	action.building.capture(int(action.actor.health / 10.0), action.team, action.actor)
	action.actor.state = Unit.State.MOVED
	action.actor.update_visual()

func _execute_produce(action: ProduceAction) -> void:
	game_manager.deduct_funds(action.team, action.cost)
	var unit_scene = load("res://scenes/units/Unit.tscn")
	var unit = unit_scene.instantiate()
	unit.data = action.unit_data
	unit.team = action.team
	unit.grid_position = action.building.building_position
	unit.state = Unit.State.MOVED
	game_manager.current_map.get_node("Units").add_child(unit)
	game_manager.register_unit(unit)

func _execute_end_turn(action: EndTurnAction) -> void:
	turn_manager.end_turn(action.team)

func _validate_special(action: SpecialAction) -> bool:
	if action.actor.state == Unit.State.MOVED:
		action_rejected.emit("Unidad ya actuó")
		return false
	if action.targets.is_empty():
		action_rejected.emit("Sin targets")
		return false
	return true

func _execute_special(action: SpecialAction) -> void:
	if not action.move_path.is_empty():
		var move = MoveAction.new(action.actor, action.move_path)
		await _execute_move(move)
	match action.ability_type:
		"THRUST": combat_system.execute_thrust(action.actor, action.targets)
		"BASH": combat_system.execute_bash(action.actor, action.targets)
		"VOLLEY": combat_system.execute_volley(action.actor, action.targets)
