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
@export var unit_type: String  # Can be "Sword", "Spear", "Archer", etc.
const damage_matrix = {
	"Sword": {
		"Sword": 1,
		"Archer": 2.5,
		"Spear": .6,
		"Junker": .2,
		"Raider": 0,
	},
	"Archer": {
		"Sword": .6,
		"Archer": 1,
		"Spear": 2.5,
		"Junker": .5,
		"Raider": 0,
	},
	"Spear": {
		"Sword": 2.5,
		"Archer": 1.5,
		"Spear": 1,
		"Junker": .5,
		"Raider": 0,
	},
	"Raider": {
		"Sword": 0,
		"Archer": 0,
		"Spear": 0,
		"Junker": 0,
		"Raider": 99,
	},
	"Junker": {
		"Sword": 1,
		"Archer": 1,
		"Spear": 1,
		"Junker": 1,
		"Raider": 0,
	},
	# Add more unit types as needed
}

func _ready():
	$HealthLabel.text = str(health)

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
	if main.attack_mode or main.mark_mode or main.bash_mode or main.thrust_mode or main.volley_mode:
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
				and not main.attack_mode
				and not main.mark_mode
				and not main.bash_mode
				and not main.thrust_mode
				and not main.volley_mode):
				select()

			# Enemy unit inspection
			elif (not main.is_menu_open
				and not main.attack_mode
				and not main.mark_mode
				and not main.bash_mode
				and not main.thrust_mode
				and not main.volley_mode
				and current_state != UnitState.UNSELECTABLE):
				# Deselect all player units first
				for unit in main.active_units.get_children():
					if unit.team == main.current_player_team and unit.current_state != MapUnit.UnitState.MOVED:
						unit.deselect()

				main.update_active_layers()
				main.active_overlay.clear()

				# Show movement range of this enemy unit
				var reachable = main.get_reachable_cells(self.grid_position, self.movement_range, self, self.is_raider())
				for pos in reachable:
					main.active_overlay.set_cell(0, pos, 1, Vector2i.ZERO)

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
		main.all_units.erase(self)
		queue_free()

func attacking(target: MapUnit):
	var multiplier_attacker = damage_matrix[unit_type][target.unit_type]
	var damage_attacker = max(0.0, (multiplier_attacker * attack * health/100) - target.defense)  # Basic damage formula
	target.health -= damage_attacker
	target.current_state = UnitState.UNSELECTABLE
	target.check_death()

	var multiplier_defender = damage_matrix[target.unit_type][unit_type]
	var damage_defender = max(0.0, (multiplier_defender * target.attack * target.health/100) - defense)  # Basic damage formula
	if (unit_type == "Archer" and target.unit_type != "Archer"):
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
