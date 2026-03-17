extends CanvasLayer

@onready var unit_info_panel = $UnitInfoPanel
@onready var funds_panel = $FundsPanel
#@onready var unit_name_label = $UnitInfoPanel/UnitName
@onready var health_label = $UnitInfoPanel/VBoxContainer/HealthLabel
@onready var attack_label = $UnitInfoPanel/VBoxContainer/AttackLabel
@onready var defense_label = $UnitInfoPanel/VBoxContainer/DefenseLabel
@onready var movement_label = $UnitInfoPanel/VBoxContainer/MovementLabel
@onready var strong_label = $UnitInfoPanel/VBoxContainer/StrongLabel
@onready var status_label = $UnitInfoPanel/VBoxContainer/StatusLabel
@onready var raider_element_label = $UnitInfoPanel/VBoxContainer/RaiderElementLabel
#@onready var weak_label = $UnitInfoPanel/VBoxContainer/WeakLabel
@onready var element_label = $FundsPanel/VBoxContainer/ElementLabel
@onready var funds_label = $FundsPanel/VBoxContainer/FundsLabel
@onready var income_label = $FundsPanel/VBoxContainer/IncomeLabel
#@onready var health_label = $UnitInfoPanel/HealthLabel
#@onready var unit_sprite = $UnitInfoPanel/UnitSprite
@onready var turn_label = $TurnLabel
var turn_label_tween: Tween
@onready var main = get_node("/root/Main")
var original_position: Vector2

func _ready():
	# Configurar estilo del panel de unidad
	var unit_style = StyleBoxFlat.new()
	unit_style.bg_color = Color(0.1, 0.1, 0.15, 0.9)  # Azul grisáceo oscuro
	unit_style.border_width_left = 2
	unit_style.border_width_top = 2
	unit_style.border_width_right = 2
	unit_style.border_width_bottom = 2
	unit_style.border_color = Color(0.894, 0.093, 0.44, 1.0)  # Borde azul
	unit_style.corner_radius_top_left = 5
	unit_style.corner_radius_top_right = 5
	unit_style.corner_radius_bottom_left = 5
	unit_style.corner_radius_bottom_right = 5
	unit_info_panel.add_theme_stylebox_override("panel", unit_style)
	
	# Mismo estilo para el panel de fondos
	funds_panel.add_theme_stylebox_override("panel", unit_style)
	
	# Estilo para los textos
	var label_settings = LabelSettings.new()
	label_settings.font_color = Color(0.961, 0.961, 1.0, 1.0)  # Blanco azulado
	label_settings.font_size = 14
	
	# Aplicar a todos los labels
	for label in [health_label, attack_label, defense_label, movement_label, 
				  strong_label, status_label, element_label, funds_label, income_label]:
		label.label_settings = label_settings
	
	# El status label en amarillo si hay marcado
	status_label.label_settings = label_settings.duplicate()
	status_label.label_settings.font_color = Color(1, 0.8, 0.2)  # Amarillo
	
	unit_info_panel.visible = false 
	update_income_funds()

func show_unit_info(unit: MapUnit):
	unit_info_panel.visible = true
	health_label.text = "HP: %d" % unit.health
	attack_label.text = "Att: %d" % unit.attack
	defense_label.text = "Def: %d" % unit.defense
	movement_label.text = "Mov: %d" % unit.movement_range
	
	# Texto de ventaja (siempre visible)
	if unit.unit_type == "Sword":
		strong_label.text = "+vs: Archer"
	elif unit.unit_type == "Spear":
		strong_label.text = "+vs: Sword"
	elif unit.unit_type == "Archer":
		strong_label.text = "+vs: Spear"
	elif unit.unit_type == "Raider":
		strong_label.text = "+vs: Raider"
	elif unit.unit_type == "Junker":
		strong_label.text = "+vs: "
	
	# 👇 NUEVO: Mostrar elemento del raider (solo si es raider)
	if unit.is_raider() and unit is Raider_Unit:
		var raider = unit as Raider_Unit
		var element_names = ["EARTH", "METAL", "WATER", "WOOD", "FIRE"]
		var element_name = element_names[raider.raider_element]
		raider_element_label.text = "Element: " + element_name
		raider_element_label.visible = true
		
		# Color según elemento
		match element_name:
			"FIRE": raider_element_label.modulate = Color(1, 0.5, 0.5)  # Rojo claro
			"WATER": raider_element_label.modulate = Color(0.502, 0.988, 1.0, 1.0)  # Azul claro
			"EARTH": raider_element_label.modulate = Color(0.6, 0.4, 0.2)  # Café
			"WOOD": raider_element_label.modulate = Color(0.4, 0.8, 0.4)  # Verde
			"METAL": raider_element_label.modulate = Color(0.9, 0.9, 0.5)  # Amarillo claro
	else:
		raider_element_label.visible = false  # 👈 Ocultar si no es raider
	
	# Status - recolectar estados activos
	var status_texts = []
	if unit.marked_turns != 0:
		status_texts.append("Marked %d" % ceil(unit.marked_turns / 2.0))
	if unit.shield_turns != 0:
		status_texts.append("Shield %d" % ceil(unit.shield_turns / 2.0))
	if unit.boost_turns != 0:
		status_texts.append("Boost %d" % ceil(unit.boost_turns / 2.0 ))
	if unit.muddle_turns != 0:
		status_texts.append("Muddle %d" % ceil(unit.muddle_turns / 2.0))
	
	if status_texts.size() > 0:
		status_label.text = " | ".join(status_texts)
		status_label.visible = true
	else:
		status_label.visible = false

func hide_unit_info():
	unit_info_panel.visible = false

func update_income_funds():
	var team = main.player_id

	if team == 1:
		funds_label.text = "$: %dk" % (main.team1_funds/1000)
		income_label.text = "+$: %dk" % (main.team1_income/1000)
	elif team == 2:
		funds_label.text = "$: %dk" % (main.team2_funds/1000)
		income_label.text = "+$: %dk" % (main.team2_income/1000)

func _on_unit_info_panel_mouse_entered() -> void:
	if unit_info_panel.position.x < 100:
		unit_info_panel.position.x = 560
	else:
		unit_info_panel.position.x = 16.0

func _on_funds_panel_mouse_entered() -> void:
	if funds_panel.position.x < 100:
		funds_panel.position.x = 540
	else:
		funds_panel.position.x = 16.0

func update_element_ui():
	var element_name = main.Element.keys()[main.current_element]
	element_label.text = element_name

	match element_name:
		"FIRE":
			element_label.modulate = Color(0.905, 0.0, 0.213, 1.0)
		"WATER":
			element_label.modulate = Color(0.502, 0.988, 1.0, 1.0)
		"WOOD":
			element_label.modulate = Color(0.13, 0.827, 0.397, 1.0)
		"EARTH":
			element_label.modulate = Color(0.513, 0.338, 0.162, 1.0)
		"METAL":
			element_label.modulate = Color(0.968, 0.862, 0.106, 1.0)

func show_turn_message(message: String):
	turn_label.visible = true
	if turn_label_tween:
		turn_label_tween.kill()
	
	turn_label.text = message
	turn_label.modulate = Color(1, 1, 1, 1)
	
	turn_label_tween = create_tween()
	turn_label_tween.tween_interval(1.5)
	turn_label_tween.tween_property(turn_label, "modulate:a", 0.0, 0.8)
