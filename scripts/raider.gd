class_name Raider_Unit
extends MapUnit

enum Element { EARTH, METAL, WATER, WOOD, FIRE }
@export var raider_element: Element = Element.FIRE
@export var mark_range: int 
@export var scorch_range: int 
@export var spawn_range: int 
@export var shield_range: int 
@export var muddle_range: int 
@export var boost_range: int
var outline_material: ShaderMaterial
var outline_shader: Shader
static var OUTLINE_SHADER = preload("res://shaders/outline.gdshader")
# Array con los nombres en el MISMO ORDEN que el enum
const ELEMENT_NAMES = ["EARTH", "METAL", "WATER", "WOOD", "FIRE" ]

func get_element_name() -> String:
	return ELEMENT_NAMES[raider_element]

func _ready():
	outline_material = ShaderMaterial.new()
	outline_material.shader = OUTLINE_SHADER
	outline_material.set_shader_parameter("outline_width", 2.0)
	
	_setup_element_stats()
	_update_element_visual()
	set_team_outline(team)

func _setup_element_stats():
	match raider_element:
		Element.FIRE:
			movement_range = 5
			vision_range = 3
			mark_range = 0
			scorch_range = 3
			muddle_range = 0
			boost_range = 0
			shield_range = 0
			#max_ability_cooldown = 2
			# Fuego: daño extra a unidades marcadas

		Element.WATER:
			movement_range = 7  # Movimiento extra en ríos/océano
			vision_range = 2
			mark_range = 4
			scorch_range = 0
			muddle_range = 0
			boost_range = 0
			shield_range = 0
			#max_ability_cooldown = 3
			# Agua: puede moverse por agua sin costo

		Element.EARTH:
			movement_range = 4
			vision_range = 3
			mark_range = 0
			scorch_range = 0
			muddle_range = 4
			boost_range = 0
			shield_range = 0
			#max_ability_cooldown = 4
			# Tierra: defensa extra en montañas/colinas

		Element.WOOD:
			movement_range = 6
			vision_range = 6  # Visión extra en bosques
			mark_range = 0
			scorch_range = 0
			muddle_range = 0
			boost_range = 4
			shield_range = 0
			#max_ability_cooldown = 3
			# Madera: se camufla en bosques

		Element.METAL:
			movement_range = 5
			vision_range = 4
			mark_range = 0
			scorch_range = 0
			muddle_range = 0
			boost_range = 0
			shield_range = 4
			#max_ability_cooldown = 2
			# Metal: ignora defensa de fortificaciones

func set_potential_target(value: bool):
	is_potential_target = value
	update_visual_state()
	# No llamar a set_team_outline aquí, ya se llama en update_visual_state

func update_visual_state():
	if is_potential_target:
		$Sprite2D.modulate = Color(2, 0.5, 0.5)
	else:
		match current_state:
			UnitState.SELECTED:
				$Sprite2D.modulate = Color(1.5, 1.5, 1.5)
			UnitState.MOVED:
				$Sprite2D.modulate = Color(0.5, 0.5, 0.5)
			_:
				$Sprite2D.modulate = Color(1, 1, 1)

func apply_outline():
	set_team_outline(team)

func _update_element_visual():
	# Cargar textura basada en elemento y equipo
	var element_suffix = ""
	match raider_element:
		Element.FIRE: element_suffix = "_fire"
		Element.WATER: element_suffix = "_water"
		Element.EARTH: element_suffix = "_earth"
		Element.WOOD: element_suffix = "_wood"
		Element.METAL: element_suffix = "_metal"

	#var team_suffix = "_Blue" if team == 1 else "_Red"
	var texture_path = "res://art/units/raider%s.png" % [element_suffix]

	if ResourceLoader.exists(texture_path) and has_node("Sprite2D"):
		get_node("Sprite2D").texture = load(texture_path)

func set_team_outline(team_number: int):
	var mat = outline_material.duplicate()
	
	if team_number == 1:
		mat.set_shader_parameter("outline_color", Color(0.2, 0.5, 1.0))
	else:
		mat.set_shader_parameter("outline_color", Color(1.0, 0.3, 0.3))
	
	$Sprite2D.material = mat

func is_raider() -> bool:
	return true

func _on_input_event(_viewport, event, _shape_idx):
	
	# Verificar is_ai_processing solo si existe (PvE), en PvP no existe
	if "is_ai_processing" in main and main.is_ai_processing:
		return 
	
	# Si estamos en mark_mode, no procesar eventos de unidades (el mark se maneja en _unhandled_input)
	if main.is_action_mode():
		return

	if main.raider_view_enabled:
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

func _set_grid_position(value: Vector2i):
	var wrapped = Vector2i(
		posmod(value.x, main.map_size.x),
		value.y
		)
	super._set_grid_position(wrapped)

func can_mark(target: MapUnit) -> bool:
	if not target:
		return false
	if team == target.team:
		return false
	if current_state == UnitState.MOVED:
		return false
	if target.visible == false:
		return false

	var dx = abs(grid_position.x - target.grid_position.x)
	var dy = abs(grid_position.y - target.grid_position.y)
	var manhattan_distance = dx + dy

	return manhattan_distance <= mark_range

func marking(target: MapUnit):
	# Mark the target unit
	if main.current_element == main.Element.WATER:
		target.marked_turns = 8  # Mark for 6 turns
		#target.water_marked = true
	else:
		target.marked_turns = 4
	current_state = UnitState.MOVED  # Can't move after marking
	update_visual_state()
	hud.hide_unit_info()
	main.update_fog_of_war()  # Update fog to show marked unit

func can_scorch(target: MapUnit)-> bool:
	if not target:
		return false
	if team == target.team:
		return false
	if current_state == UnitState.MOVED:
		return false
	if target.visible == false:
		return false

	var dx = abs(grid_position.x - target.grid_position.x)
	var dy = abs(grid_position.y - target.grid_position.y)
	var manhattan_distance = dx + dy

	return manhattan_distance <= scorch_range

func scorching(target: MapUnit):
	var damage_attacker
	if main.current_element == main.Element.FIRE:
		@warning_ignore("integer_division")
		damage_attacker = max(0.0, (2.5*attack * health/100) - target.get_total_defense())  # Basic damage formula
	else:
		@warning_ignore("integer_division")
		damage_attacker = max(0.0, (attack * health/100) - target.get_total_defense())  # Basic damage formula
	target.health -= damage_attacker
	target.current_state = UnitState.UNSELECTABLE
	target.check_death()
	current_state = UnitState.MOVED  # Can't move after attacking
	update_visual_state()
	hud.hide_unit_info()

func can_shield(target: MapUnit)-> bool:
	if not target:
		return false
	if team != target.team:
		return false
	if current_state == UnitState.MOVED:
		return false
	if target.visible == false:
		return false

	var dx = abs(grid_position.x - target.grid_position.x)
	var dy = abs(grid_position.y - target.grid_position.y)
	var manhattan_distance = dx + dy

	return manhattan_distance <= shield_range

func shielding(target: MapUnit):
	if main.current_element == main.Element.METAL:
		target.shield_turns = 8
	else:
		target.shield_turns = 4 

	current_state = UnitState.MOVED  # Can't move after shielding
	update_visual_state()
	hud.hide_unit_info()

func can_muddle(target: MapUnit)-> bool:
	if not target:
		return false
	if team == target.team:
		return false
	if current_state == UnitState.MOVED:
		return false
	if target.visible == false:
		return false

	var dx = abs(grid_position.x - target.grid_position.x)
	var dy = abs(grid_position.y - target.grid_position.y)
	var manhattan_distance = dx + dy

	return manhattan_distance <= muddle_range

func muddling(target: MapUnit):
	if main.current_element == main.Element.EARTH:
		target.muddle_turns = 8
	else:
		target.muddle_turns = 4 

	current_state = UnitState.MOVED  # Can't move after shielding
	update_visual_state()
	hud.hide_unit_info()

func can_boost(target: MapUnit)-> bool:
	if not target:
		return false
	if team != target.team:
		return false
	if current_state == UnitState.MOVED:
		return false
	if target.visible == false:
		return false

	var dx = abs(grid_position.x - target.grid_position.x)
	var dy = abs(grid_position.y - target.grid_position.y)
	var manhattan_distance = dx + dy

	return manhattan_distance <= boost_range

func boosting(target: MapUnit):
	if main.current_element == main.Element.WOOD:
		target.boost_turns = 8
	else:
		target.boost_turns = 4 

	current_state = UnitState.MOVED  # Can't move after shielding
	update_visual_state()
	hud.hide_unit_info()
