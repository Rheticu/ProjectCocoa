class_name Building
extends Area2D

@export var max_capture_points := 20
@export var team := 0  # 0 = neutral, 1 = player, 2 = enemy
@export var income_per_turn := 1000
@export var can_produce_units := false
@export var building_type: String
@onready var main = get_node("/root/Main")
@onready var hud = get_node("/root/Main/UI/HUD")
@onready var camera = get_node("/root/Main/Camera2D")

@warning_ignore("unused_signal")
signal production_menu_opened
@warning_ignore("unused_signal")
signal production_menu_closed
@warning_ignore("unused_signal")
signal ownership_changed(building: Building)

var capturing_unit: MapUnit = null
var capture_points: int
var building_position: Vector2i
var production_menu_instance = null
var production_data = {
	"Barracks": {
		"units": ["Sword", "Archer", "Spear", "Cannon"],
		"costs": {"Sword": 2000, "Archer": 1000, "Spear": 5000, "Cannon": 7500}
	},
	"Port": {
		"units": ["Junker"],
		"costs": {"Junker": 7000}
	},
	"HQ": {
		"units": ["Raider_FIRE", "Raider_WATER", "Raider_EARTH", "Raider_WOOD", "Raider_METAL"],
		"costs": {
			"Raider_FIRE": 10000,
			"Raider_WATER": 10000,
			"Raider_EARTH": 10000,
			"Raider_WOOD": 10000,
			"Raider_METAL": 10000
		}
	}
}

func _ready():
	building_position = Vector2i(position / 32)
	if capture_points == 0:
		capture_points = max_capture_points
	update_visual()
	main.close_menu_production.connect(close_production_menu)

func _process(_delta):
	if capturing_unit == null:
		return

	if capturing_unit.grid_position != building_position:
		reset_capture()

func capture(unit: MapUnit, amount: int, capturing_team: int):
	var previous_team = team  # Guardar equipo anterior

	if unit.unit_type in ["Sword", "Spear", "Archer"]:
		capturing_unit = unit

		# Conectar a la señal de muerte de la unidad
		if not unit.tree_exiting.is_connected(_on_capturer_destroyed):
			unit.tree_exiting.connect(_on_capturer_destroyed.bind(unit))

	capture_points -= amount
	if capture_points <= 0:
		team = capturing_team
		capture_points = max_capture_points

	update_visual()

	# Emitir señal SOLO si el equipo cambió
	if team != previous_team:
		emit_signal("ownership_changed", self)

func _on_capturer_destroyed(unit: MapUnit):
	# Solo resetear si es NUESTRO capturador
	if capturing_unit == unit:
		reset_capture()

func reset_capture():
	if capturing_unit:
		# Desconectar señal de muerte si existe
		if capturing_unit.tree_exiting.is_connected(_on_capturer_destroyed):
			capturing_unit.tree_exiting.disconnect(_on_capturer_destroyed)

		capturing_unit = null

	capture_points = max_capture_points

	# Sincronizar en multiplayer si es necesario
	if main and main.has_method("sync_building_capture"):
		main.sync_building_capture.rpc(building_position.x, building_position.y, team, capture_points)

	update_visual()

func update_visual():
	
		# Cambiar color del sprite según dueño
		match team:
			0: $Sprite2D.modulate = Color(1, 1, 1)      # Neutral
			1: $Sprite2D.modulate = Color(0.0, 0.635, 0.957, 1.0)  # Player 1
			2: $Sprite2D.modulate = Color(1, 0.5, 0.5)  # Player 2

		# Actualizar label
		if has_node("CaptureLabel"):
			if capture_points < max_capture_points:
				$CaptureLabel.text = str(capture_points)
			else:
				$CaptureLabel.text = ""

func _on_input_event(_viewport, event, _shape_idx):
	# Verificar is_ai_processing solo si existe (PvE)
	if "is_ai_processing" in main and main.is_ai_processing:
		return 

	if main.current_player_team != team:
		return
	
	# Verificar player_id solo si existe (PvP)
	if "player_id" in main:
		if main.player_id == 0 or main.current_player_team != main.player_id:
			return

	if not can_produce_units:
		return

	for unit in main.all_units:
		if ((unit.grid_position == building_position and not unit.is_raider()) 
			or unit.current_state == unit.UnitState.SELECTED
			or unit.grid_position == building_position and unit.is_raider() and building_type == "HQ"):
			return

	if (not main.raider_view_enabled
		and not main.is_menu_open
		and not main.is_action_mode()
		):
		if event.is_action_pressed("LMClick"):
			#if team == main.current_player_team and can_produce_units:
				show_production_menu()

func show_production_menu():
	close_production_menu()

	production_menu_instance = PopupPanel.new()
	main.add_child(production_menu_instance)

	# Tamaño del menú más ajustado
	production_menu_instance.size = Vector2(320, 400)
	production_menu_instance.position = Vector2(camera.position.x - 160, camera.position.y - 200)

	# Contenedor principal con márgenes
	var main_container = MarginContainer.new()
	main_container.add_theme_constant_override("margin_left", 10)
	main_container.add_theme_constant_override("margin_right", 10)
	main_container.add_theme_constant_override("margin_top", 10)
	main_container.add_theme_constant_override("margin_bottom", 10)
	main_container.size = production_menu_instance.size
	production_menu_instance.add_child(main_container)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_container.add_child(vbox)

	# Título con estilo
	var title_container = HBoxContainer.new()
	title_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(title_container)

	var title_label = Label.new()
	title_label.text = "PRODUCTION"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	title_container.add_child(title_label)

	# Subtítulo con tipo de edificio
	var subtitle_label = Label.new()
	subtitle_label.text = building_type
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	subtitle_label.add_theme_font_size_override("font_size", 14)
	subtitle_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.9))
	vbox.add_child(subtitle_label)

	# Separador decorativo
	var separator = HSeparator.new()
	separator.add_theme_constant_override("separation", 10)
	vbox.add_child(separator)

	# Encabezado de columnas
	var header_container = HBoxContainer.new()
	header_container.add_theme_constant_override("separation", 15)
	vbox.add_child(header_container)

	var unit_header = Label.new()
	unit_header.text = "UNIT"
	unit_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	unit_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	unit_header.add_theme_font_size_override("font_size", 14)
	unit_header.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	header_container.add_child(unit_header)

	var cost_header = Label.new()
	cost_header.text = "COST"
	cost_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cost_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cost_header.add_theme_font_size_override("font_size", 14)
	cost_header.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	header_container.add_child(cost_header)

	# Lista de unidades con scroll
	var scroll_container = ScrollContainer.new()
	scroll_container.custom_minimum_size = Vector2(0, 250)
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll_container)

	var units_container = VBoxContainer.new()
	units_container.add_theme_constant_override("separation", 5)
	units_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.add_child(units_container)

	# Obtener datos de producción
	var production_info = production_data.get(building_type, {})
	var available_units = production_info.get("units", [])
	var unit_costs = production_info.get("costs", {})

	# Fondos actuales del equipo
	var current_funds = 0
	if team == 1:
		current_funds = main.team1_funds
	elif team == 2:
		current_funds = main.team2_funds

	for unit_type in available_units:
		var unit_cost = unit_costs.get(unit_type, 0)
		var can_afford = (current_funds >= unit_cost)
		
		# 👇 SOLO ESTO NUEVO: Verificar límite de raiders
		var can_produce = true
		if unit_type.begins_with("Raider_"):
			var current_raiders = main.count_raiders_for_team(team)
			can_produce = current_raiders < 5
		
		# 👇 Botón deshabilitado por dinero O por límite de raiders
		var button_disabled = not can_afford or (unit_type.begins_with("Raider_") and not can_produce)

		# Fila de unidad
		var unit_row = HBoxContainer.new()
		unit_row.add_theme_constant_override("separation", 15)
		unit_row.custom_minimum_size = Vector2(0, 36)
		units_container.add_child(unit_row)

		# Nombre de la unidad
		var name_label = Label.new()
		name_label.text = unit_type
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_label.add_theme_font_size_override("font_size", 16)
		unit_row.add_child(name_label)

		# Costo
		var cost_label = Label.new()
		cost_label.text = "$" + str(unit_cost)
		cost_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cost_label.add_theme_font_size_override("font_size", 16)
		unit_row.add_child(cost_label)

		# Botón de producción
		var unit_button = Button.new()
		unit_button.text = "BUILD"
		unit_button.custom_minimum_size = Vector2(80, 32)
		unit_button.disabled = button_disabled
		unit_button.pressed.connect(_on_unit_button_pressed.bind(unit_type, unit_cost))

		# Estilo del botón
		if can_afford:
			unit_button.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
			unit_button.add_theme_color_override("font_pressed_color", Color(0.7, 0.7, 0.7))
			# Botón verde cuando se puede comprar
			var normal_style = StyleBoxFlat.new()
			normal_style.bg_color = Color(0.2, 0.6, 0.2, 0.9)
			normal_style.border_color = Color(0.3, 0.8, 0.3)
			normal_style.border_width_left = 1
			normal_style.border_width_right = 1
			normal_style.border_width_top = 1
			normal_style.border_width_bottom = 1
			normal_style.corner_radius_top_left = 4
			normal_style.corner_radius_top_right = 4
			normal_style.corner_radius_bottom_left = 4
			normal_style.corner_radius_bottom_right = 4
			unit_button.add_theme_stylebox_override("normal", normal_style)

			var hover_style = normal_style.duplicate()
			hover_style.bg_color = Color(0.3, 0.7, 0.3, 0.95)
			unit_button.add_theme_stylebox_override("hover", hover_style)

			var pressed_style = normal_style.duplicate()
			pressed_style.bg_color = Color(0.1, 0.5, 0.1, 0.9)
			unit_button.add_theme_stylebox_override("pressed", pressed_style)
		else:
			# Botón gris cuando no se puede comprar
			name_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
			cost_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))

			var disabled_style = StyleBoxFlat.new()
			disabled_style.bg_color = Color(0.3, 0.3, 0.3, 0.7)
			disabled_style.border_color = Color(0.4, 0.4, 0.4)
			disabled_style.border_width_left = 1
			disabled_style.border_width_right = 1
			disabled_style.border_width_top = 1
			disabled_style.border_width_bottom = 1
			disabled_style.corner_radius_top_left = 4
			disabled_style.corner_radius_top_right = 4
			disabled_style.corner_radius_bottom_left = 4
			disabled_style.corner_radius_bottom_right = 4
			unit_button.add_theme_stylebox_override("disabled", disabled_style)

		unit_row.add_child(unit_button)

	# Información de fondos
	var funds_label = Label.new()
	funds_label.text = "Available: $" + str(current_funds)
	funds_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	funds_label.add_theme_font_size_override("font_size", 14)
	funds_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	vbox.add_child(funds_label)

	# Botón de cerrar
	var close_button = Button.new()
	close_button.text = "CLOSE"
	close_button.custom_minimum_size = Vector2(0, 35)
	close_button.pressed.connect(close_production_menu)

	# Estilo del botón de cerrar
	var close_style = StyleBoxFlat.new()
	close_style.bg_color = Color(0.4, 0.4, 0.4, 0.9)
	close_style.border_color = Color(0.6, 0.6, 0.6)
	close_style.border_width_left = 1
	close_style.border_width_right = 1
	close_style.border_width_top = 1
	close_style.border_width_bottom = 1
	close_style.corner_radius_top_left = 4
	close_style.corner_radius_top_right = 4
	close_style.corner_radius_bottom_left = 4
	close_style.corner_radius_bottom_right = 4
	close_button.add_theme_stylebox_override("normal", close_style)

	var close_hover_style = close_style.duplicate()
	close_hover_style.bg_color = Color(0.5, 0.5, 0.5, 0.95)
	close_button.add_theme_stylebox_override("hover", close_hover_style)

	close_button.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	vbox.add_child(close_button)

	# Estilo del panel principal
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	panel_style.border_color = Color(0.3, 0.3, 0.4)
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.shadow_color = Color(0, 0, 0, 0.5)
	panel_style.shadow_size = 8
	production_menu_instance.add_theme_stylebox_override("panel", panel_style)

	production_menu_instance.popup()
	emit_signal("production_menu_opened")

func close_production_menu():
	if production_menu_instance:
		production_menu_instance.queue_free()
		production_menu_instance = null
	emit_signal("production_menu_closed")

func _on_unit_button_pressed(unit: String, cost: int):
	if capturing_unit != null:
		return
	
	var unit_scene
	if unit.begins_with("Raider_"):
		unit_scene = load("res://scenes/units/Raider.tscn")
	else:
		unit_scene = load("res://scenes/units/" + unit + ".tscn")
	
	if not unit_scene:
		print("Error: No se pudo cargar la escena para ", unit)
		return
	
	var unit_instance = unit_scene.instantiate()
	
	# Configurar sprite según equipo
	var color_suffix = "_Blue" if team == 1 else "_Red"
	
	# Si es un raider, extraer el elemento del nombre
	if unit.begins_with("Raider_") and unit_instance is Raider_Unit:
		# Extraer el elemento (ej: "Raider_FIRE" → "FIRE")
		var element_name = unit.trim_prefix("Raider_")
		
		# Convertir string a enum
		match element_name:
			"FIRE": unit_instance.raider_element = Raider_Unit.Element.FIRE
			"WATER": unit_instance.raider_element = Raider_Unit.Element.WATER
			"EARTH": unit_instance.raider_element = Raider_Unit.Element.EARTH
			"WOOD": unit_instance.raider_element = Raider_Unit.Element.WOOD
			"METAL": unit_instance.raider_element = Raider_Unit.Element.METAL
		
		# Llamar manualmente a la configuración (porque _ready() ya se ejecutó)
		unit_instance._setup_element_stats()
		unit_instance._update_element_visual()
	else:
		# Para unidades normales, usar sprite normal
		var sprite_path = "res://art/units/%s1%s.png" % [unit, color_suffix]
		if unit_instance.get_node("Sprite2D") and ResourceLoader.exists(sprite_path):
			unit_instance.get_node("Sprite2D").texture = load(sprite_path)
	
# Con esto:
	if unit.begins_with("Raider_"):
		main.get_node("RaiderUnits").add_child(unit_instance)
	else:
		main.get_node("Units").add_child(unit_instance)
	unit_instance.team = self.team
	var _new_id = unit_instance.unit_id

	unit_instance.grid_position = building_position
	unit_instance.current_state = unit_instance.UnitState.MOVED
	unit_instance.update_visual_state()
	close_production_menu()
	
	# Restar fondos según el equipo
	if team == 1:
		main.team1_funds -= cost
	elif team == 2:
		main.team2_funds -= cost

	if unit.begins_with("Raider_"):
		main.toggle_raider_view()

	hud.update_income_funds()
	main.all_units.append(unit_instance)
	main.update_fog_of_war()
	
	# Sincronizar producción en multiplayer
	if main.has_method("sync_unit_production") and main.multiplayer.multiplayer_peer != null:
		# Enviar el nombre completo (ej: "Raider_FIRE") para que el otro jugador sepa qué elemento crear
		main.sync_unit_production.rpc(building_position.x, building_position.y, unit, team, cost, _new_id)
