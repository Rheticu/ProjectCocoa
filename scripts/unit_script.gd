class_name MapUnit  
extends Area2D

# Core Properties
@export var movement_range : int
@export var health : int = 100:
	set(value):
		health = value
		$HealthLabel.text = str(health)
@export var attack : int 
@export var attack_range : int
@export var defense : int
@export var team := 1
@export var vision_range : int
@onready var main = get_node("/root/Main")
@onready var hud = get_node("/root/Main/UI/HUD")
enum UnitState { UNSELECTED, SELECTED, MOVED, UNSELECTABLE }
var current_state : UnitState = UnitState.UNSELECTED
var grid_position : Vector2i:
	get: return Vector2i(position / 32)
	set(value): _set_grid_position(value)
var current_player_team: int = 1  # Default to team 1
var original_position : Vector2i
var marked_turns: int = 0
var shield_turns: int = 0
var is_in_overwatch: bool = false
var unit_id: int = -1
@export var unit_type: String  # Can be "Sword", "Spear", "Archer", etc.
const damage_matrix = {
	"Sword": {
		"Sword": 1,
		"Archer": 2.5,
		"Spear": .6,
		"Cannon": 2,
		"Junker": .2,
		"Raider": 0,
	},
	"Archer": {
		"Sword": .6,
		"Archer": 1,
		"Spear": 2.5,
		"Cannon": 1,
		"Junker": .5,
		"Raider": 0,
	},
	"Spear": {
		"Sword": 2.5,
		"Archer": 1.5,
		"Spear": 1,
		"Cannon": 1.2,
		"Junker": .5,
		"Raider": 0,
	},
	"Raider": {
		"Sword": 0,
		"Archer": 0,
		"Spear": 0,
		"Junker": 0,
		"Cannon": 0,
		"Raider": 99,
	},
	"Junker": {
		"Sword": 1,
		"Archer": 1,
		"Spear": 1,
		"Cannon": 1,
		"Junker": 1,
		"Raider": 0,
	},
	"Cannon": {
		"Sword": 3,
		"Archer": 3,
		"Spear": 3,
		"Cannon": 1,
		"Junker": 2,
		"Raider": 0,
	},
}

func _ready():
	if team == main.player_id:
		unit_id = randi_range(1, 999999)
	$HealthLabel.text = str(health)
	main.multiplayer_ready.connect(create_id)

func create_id():
	var new_id
	unit_id = randi_range(1, 999999)
	sync_unit_id.rpc(unit_id)
	new_id = unit_id
	sync_unit_id.rpc(new_id)

@rpc("any_peer","reliable")
func sync_unit_id(new_id):
	unit_id = new_id

func update_visual_state():
	match current_state:
		UnitState.UNSELECTABLE:
			$Sprite2D.modulate = Color(1, 1, 1)
		UnitState.UNSELECTED:
			$Sprite2D.modulate = Color(1, 1, 1)
		UnitState.SELECTED:
			$Sprite2D.modulate = Color(1.5, 1.5, 1.5)
		UnitState.MOVED:
			$Sprite2D.modulate = Color(0.5, 0.5, 0.5)

func _on_input_event(_viewport, event, _shape_idx):
	# Verificar is_ai_processing solo si existe (PvE), en PvP no existe
	if "is_ai_processing" in main and main.is_ai_processing:
		return 
	
	# Si estamos en mark_mode, no procesar eventos de unidades (el mark se maneja en _unhandled_input)
	if main.is_action_mode():
		return

	if not main.raider_view_enabled:
		if event.is_action_pressed("LMClick"):
			main.active_overlay.clear()
			main.attack_range_overlay.clear()

			# Verificar si es PvP y si es mi turno
			var can_select = false
			if "player_id" in main:
				# PvP: solo puedo seleccionar si es mi turno y la unidad es de mi equipo
				can_select = (main.current_player_team == main.player_id and team == main.current_player_team)
			else:
				# PvE: solo team 1 puede seleccionar
				can_select = (team == 1)

			# Player unit selection
			if (current_state == UnitState.UNSELECTED
				and can_select
				and not main.is_menu_open
				and not main.is_action_mode()):
				select()

			# Enemy unit inspection
			elif (not main.is_menu_open
				and not main.is_action_mode()
				and current_state != UnitState.UNSELECTABLE):
				# Deselect all player units first
				for unit in main.active_units.get_children():
					if unit.team == main.current_player_team and unit.current_state != MapUnit.UnitState.MOVED:
						unit.deselect()

				main.update_active_layers()
				main.active_overlay.clear()
				hud.show_unit_info(self)
				# Show movement range of this enemy unit
				var reachable = main.get_reachable_cells(self.grid_position, self.movement_range, self, self.is_raider())
				for pos in reachable:
					main.active_overlay.set_cell(0, pos, 1, Vector2i.ZERO)

	print("shield_turns:", " ", shield_turns)

func select():
	for unit in get_parent().get_children():
		if (unit.current_state != UnitState.MOVED and unit != self) :
			unit.deselect()
	current_state = UnitState.SELECTED
	update_visual_state()
	original_position = grid_position
	main.selected_unit = self
	main.show_movement_range(grid_position, self)
	hud.show_unit_info(self)
	main.hide_attack_range()

func deselect():
	# No cambiar el estado si la unidad ya está en MOVED (después de atacar o moverse)
	if current_state != UnitState.MOVED:
		current_state = UnitState.UNSELECTED
	update_visual_state()
	hud.hide_unit_info()
	main.potential_targets.clear()
	# Limpiar colores anteriores de todas las unidades enemigas
	for enemy in main.all_units:
		if enemy.team != main.current_player_team:
			enemy.update_visual_state() 

func can_attack(target: MapUnit) -> bool:
	if not target:
		return false
	if team == target.team:
		return false
	if current_state == UnitState.MOVED:
		return false
	if is_raider() != target.is_raider():
		return false

	var dx = abs(grid_position.x - target.grid_position.x)
	var dy = abs(grid_position.y - target.grid_position.y)
	var manhattan_distance = dx + dy

	return manhattan_distance <= attack_range

func check_death():
	if health <= 0:
		if has_meta("movement_tween"):
			var tween: Tween = get_meta("movement_tween")
			if tween:
				tween.kill() # <- ESTO es clave
		main.all_units.erase(self)
		main.input_locked = false
		queue_free()

func get_total_defense() -> int:
	var base_defense = defense
	var tile_bonus = 0

	if main and main.has_method("get_terrain_at"):
		var terrain = main.get_terrain_at(grid_position)
		if terrain in main.TILE_DEFENSE_BONUS:
			tile_bonus = main.TILE_DEFENSE_BONUS[terrain]

	if shield_turns == 0:
		return base_defense + tile_bonus
	else:
		return (base_defense)*(3) + tile_bonus

func attacking(target: MapUnit):
	var multiplier_attacker = damage_matrix[unit_type][target.unit_type]
	var damage_attacker = max(0.0, (multiplier_attacker * attack * health/100) - target.get_total_defense())  # Basic damage formula
	target.health -= damage_attacker
	target.current_state = UnitState.UNSELECTABLE
	target.check_death()

	var multiplier_defender = damage_matrix[target.unit_type][unit_type]
	var damage_defender = max(0.0, (multiplier_defender * target.attack * target.health/100) - get_total_defense())  # Basic damage formula
	if ( (unit_type == "Archer" and target.unit_type != "Archer") 
		or (unit_type == "Cannon") 
		or (unit_type == "Junker" and target.unit_type != "Junker")
		):
		check_death()
		current_state = UnitState.MOVED  # Can't move after attacking
		update_visual_state()
	else:
		health -= damage_defender
		check_death()
		current_state = UnitState.MOVED  # Can't move after attacking
		update_visual_state()

func bash_attacking(target: MapUnit):
	var multiplier_attacker = .6*damage_matrix[unit_type][target.unit_type]
	var damage_attacker = max(0.0, (multiplier_attacker * attack * health/100) - target.defense)  # Basic damage formula
	
	target.health -= damage_attacker
	target.current_state = UnitState.UNSELECTABLE
	target.check_death()
	current_state = UnitState.MOVED  # Can't move after attacking
	update_visual_state()

func thrust_attacking(target: MapUnit):
	var multiplier_attacker = .7*damage_matrix[unit_type][target.unit_type]
	var damage_attacker = max(0.0, (multiplier_attacker * attack * health/100) - target.defense)  # Basic damage formula
	
	target.health -= damage_attacker
	target.current_state = UnitState.UNSELECTABLE
	target.check_death()
	current_state = UnitState.MOVED  # Can't move after attacking
	update_visual_state()

func volley_attacking(target: MapUnit):
	var multiplier_attacker = damage_matrix[unit_type][target.unit_type]
	var damage_attacker = max(0.0, (multiplier_attacker * attack * health/100) - target.defense)  # Basic damage formula
	
	target.health -= damage_attacker
	target.current_state = UnitState.UNSELECTABLE
	target.check_death()
	current_state = UnitState.MOVED  # Can't move after attacking
	update_visual_state()

func attack_overwatch(target: MapUnit):
	attacking(target)  # Usa el mismo ataque normal
	is_in_overwatch = false  # Desactivar después de usar
	update_visual_state()  # Actualizar apariencia si es necesario

# New virtual method for child classes to override
func _set_grid_position(value: Vector2i) -> void:
	position = (Vector2(value) * 32) + Vector2(16, 16)

func is_raider() -> bool:  # Virtual method
	return false

func get_vision_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	# Use proper grid clamping
	for x in range(-vision_range, vision_range + 1):
		for y in range(-vision_range, vision_range + 1):
			if abs(x) + abs(y) <= vision_range:
				var pos = grid_position + Vector2i(x, y)
				# Clamp to map bounds
				pos = Vector2i(
					clamp(pos.x, 0, main.map_size.x - 1),
					clamp(pos.y, 0, main.map_size.y - 1))
				cells.append(pos)
	return cells
