class_name ActionSystem
extends Node

@onready var game_manager = $"../GameManager"
@onready var turn_manager = $"../TurnManager"
@onready var movement_system = $"../MovementSystem"
@onready var combat_system = $"../CombatSystem"
@onready var fog_system = $"../FogSystem"
@onready var grid_system = $"../GridSystem"
@onready var multiplayer_manager = $"../MultiplayerManager"

signal action_executed(action: BaseAction)
signal action_rejected(reason: String)
signal move_animation_requested(unit: Unit, path: Array[Vector2i], is_remote: bool)
signal move_confirmed(unit: Unit)
signal overwatch_triggered(attacker: Unit, target: Unit, tile: Vector2i, previous_tile: Vector2i)
signal ambush_triggered(moving_unit: Unit, hidden_unit: Unit, tile: Vector2i)

var _is_executing: bool = false
var _executing_remote: bool = false

func queue_action(action: BaseAction) -> void:
	if _is_executing:
		action_rejected.emit("Acción en curso")
		return
	if not _validate(action):
		return
	await _execute(action)
	if not _executing_remote and multiplayer_manager.is_network_connected:
		if action.type != BaseAction.Type.MOVE:
			var dict = multiplayer_manager.serialize_action(action)
			multiplayer_manager.send_action(dict)

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
		BaseAction.Type.DIVIDE: return _validate_divide(action as DivideAction)
		BaseAction.Type.END_TURN: return true
		BaseAction.Type.OVERWATCH: return _validate_overwatch(action as OverwatchAction)
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
		BaseAction.Type.CAPTURE: await _execute_capture(action as CaptureAction)
		BaseAction.Type.PRODUCE:  _execute_produce(action as ProduceAction)
		BaseAction.Type.END_TURN: _execute_end_turn(action as EndTurnAction)
		BaseAction.Type.SPECIAL: await _execute_special(action as SpecialAction)
		BaseAction.Type.OVERWATCH: _execute_overwatch(action as OverwatchAction)
		BaseAction.Type.DIVIDE: await _execute_divide(action as DivideAction)
	_is_executing = false
	action_executed.emit(action)
	if action.type != BaseAction.Type.MOVE:
		var _viewing_team = game_manager.local_player_id if game_manager.local_player_id > 0 else 1
		fog_system.recalculate(_viewing_team)

func _execute_move(action: MoveAction) -> void:
	if action.path.is_empty():
		return
	move_animation_requested.emit(action.actor, action.path, _executing_remote)
	await move_confirmed
	if is_instance_valid(action.actor) and action.actor.state != Unit.State.MOVED and not action.path.is_empty():
		action.actor.grid_position = action.path.back()

func confirm_move(unit: Unit, path: Array[Vector2i]) -> void:
	if multiplayer_manager.is_network_connected:
		var action = MoveAction.new(unit, path)
		var dict = multiplayer_manager.serialize_action(action)
		multiplayer_manager.send_action(dict)

func _execute_attack(action: AttackAction) -> void:
	if not action.move_path.is_empty():
		var destination = action.move_path.back()
		if action.actor.grid_position != destination:
			var move = MoveAction.new(action.actor, action.move_path, action.is_wrapped)
			await _execute_move(move)
	combat_system.execute_attack(action.actor, action.target)

func _execute_ability(action: AbilityAction) -> void:
	if not action.move_path.is_empty():
		var destination = action.move_path.back()
		if action.actor.grid_position != destination:
			var move = MoveAction.new(action.actor, action.move_path, action.is_wrapped)
			await _execute_move(move)
	var shade = action.actor as Shade
	combat_system.execute_ability(shade, action.ability, action.target, game_manager.current_element)

func _execute_capture(action: CaptureAction) -> void:
	if not action.move_path.is_empty():
		var destination = action.move_path.back()
		if action.actor.grid_position != destination:
			var move = MoveAction.new(action.actor, action.move_path)
			await _execute_move(move)
	action.building.capture(int(action.actor.health / 10.0), action.team, action.actor)
	action.actor.state = Unit.State.MOVED
	action.actor.update_visual()

func _execute_produce(action: ProduceAction) -> void:
	game_manager.deduct_funds(action.team, action.cost)
	var unit_scene
	if action.unit_data.unit_type == "Drone":
		unit_scene = load("res://scenes/units/Drone.tscn")
	elif action.unit_data.is_shade:
		unit_scene = load("res://scenes/units/Shade.tscn")
	else:
		unit_scene = load("res://scenes/units/Unit.tscn")
	var unit = unit_scene.instantiate()
	unit.data = action.unit_data
	unit.team = action.team
	unit.unit_id = action.unit_id
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
		var destination = action.move_path.back()
		if action.actor.grid_position != destination:
			var move = MoveAction.new(action.actor, action.move_path)
			await _execute_move(move)
	match action.ability_type:
		"THRUST": combat_system.execute_thrust(action.actor, action.targets)
		"BASH":   combat_system.execute_bash(action.actor, action.targets)
		"VOLLEY": combat_system.execute_volley(action.actor, action.targets)

func _validate_overwatch(action: OverwatchAction) -> bool:
	if action.actor.state == Unit.State.MOVED:
		action_rejected.emit("Unidad ya actuó")
		return false
	if action.actor.grid_position != action.actor.original_position:
		action_rejected.emit("No puedes moverte antes de activar overwatch")
		return false
	return true

func _execute_overwatch(action: OverwatchAction) -> void:
	action.actor.is_in_overwatch = true
	action.actor.state = Unit.State.MOVED
	action.actor.update_visual()
	game_manager.register_overwatch(action.actor)

func check_overwatch_at(unit: Unit, tile: Vector2i, previous_tile: Vector2i) -> bool:
	return _check_overwatch(unit, tile, previous_tile)

func _check_overwatch(moving_unit: Unit, tile: Vector2i, previous_tile: Vector2i) -> bool:
	for cannon in game_manager.overwatch_units:
		if not is_instance_valid(cannon) or not cannon.is_in_overwatch:
			continue
		if cannon.team == moving_unit.team:
			continue
		if moving_unit.is_shade():
			continue
		if not fog_system.is_visible(tile, cannon.team):
			continue
		var dist = grid_system.manhattan_distance(cannon.grid_position, tile, false)
		if dist <= cannon.attack_range:
			combat_system.execute_overwatch_attack(cannon, moving_unit)
			overwatch_triggered.emit(cannon, moving_unit, tile, previous_tile)
			game_manager.clear_overwatch(cannon)
			return true
	return false

func check_ambush_at(moving_unit: Unit, tile: Vector2i, previous_tile: Vector2i) -> bool:
	for unit in game_manager.all_units:
		if unit.team == moving_unit.team:
			continue
		if unit.grid_position != tile:
			continue
		if unit.is_shade() != moving_unit.is_shade():
			continue
		if unit.visible:
			continue
		unit.visible = true
		unit.update_visual()
		moving_unit.state = Unit.State.MOVED
		moving_unit.grid_position = previous_tile
		moving_unit.update_visual()
		ambush_triggered.emit(moving_unit, unit, tile)
		return true
	return false

func execute_remote(action: BaseAction) -> void:
	_executing_remote = true
	await _execute(action)
	_executing_remote = false
	var viewing_team = game_manager.local_player_id if game_manager.local_player_id > 0 else 1
	fog_system.recalculate(viewing_team)

func _validate_divide(action: DivideAction) -> bool:
	var drone = action.actor as Drone
	if not drone:
		return false
	if drone.state == Unit.State.MOVED:
		action_rejected.emit("Unidad ya actuó")
		return false
	if game_manager.get_unit_at(action.target_pos, true) != null:
		action_rejected.emit("Tile ocupado")
		return false
	return true

func _execute_divide(action: DivideAction) -> void:
	if not action.move_path.is_empty():
		var destination = action.move_path.back()
		if action.actor.grid_position != destination:
			var move = MoveAction.new(action.actor, action.move_path)
			await _execute_move(move)
	var drone = action.actor as Drone
	var new_hp = int(drone.health * 0.4)
	drone.health = new_hp
	drone.state = Unit.State.MOVED
	drone.update_visual()
	var new_drone_scene = load("res://scenes/units/Drone.tscn")
	if not _executing_remote:
		action.new_unit_id = randi_range(1, 999999)
	var new_drone = new_drone_scene.instantiate()
	new_drone.data = drone.data
	new_drone.team = drone.team
	new_drone.unit_id = action.new_unit_id
	new_drone.grid_position = action.target_pos
	new_drone.health = new_hp
	new_drone.state = Unit.State.MOVED
	game_manager.current_map.get_node("Units").add_child(new_drone)
	game_manager.register_unit(new_drone)
