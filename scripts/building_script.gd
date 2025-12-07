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
var capture_progress = 0
var building_position: Vector2i
var production_menu_instance = null
var production_data = {
	"Barracks": {
		"units": ["Sword", "Archer", "Spear"],
		"costs": {"Sword": 1000, "Archer": 800, "Spear": 2000}},
	"Port": {
		"units": ["Junker"],
		"costs": {"Junker": 3000}}
}

func _ready():
	building_position = Vector2i(position / 32)
	if capture_points == 0:
		capture_points = max_capture_points
	update_visual()

func capture(unit: MapUnit, amount: int, capturing_team: int):
	if unit.unit_type == "Infantry":
		capturing_unit = unit
	capture_points -= amount
	if capture_points <= 0:
		team = capturing_team
		capture_points = max_capture_points
	update_visual()
	emit_signal("ownership_changed", self)

@warning_ignore("unused_parameter")
func _process(delta):
	if capturing_unit:
	# Si la unidad muere
		if not is_instance_valid(capturing_unit):
			reset_capture()
			return
		# Si la unidad se mueve de su tile
		if capturing_unit.grid_position != building_position and capturing_unit.current_state == MapUnit.UnitState.MOVED:
			reset_capture()
			return

func reset_capture():
	capturing_unit = null
	capture_points = max_capture_points
	update_visual()

func update_visual():
	# Cambiar color del sprite según dueño
	match team:
		0: $Sprite2D.modulate = Color(1, 1, 1)      # Neutral
		1: $Sprite2D.modulate = Color(0.5, 1, 0.5)  # Player 1
		2: $Sprite2D.modulate = Color(1, 0.5, 0.5)  # Player 2

	# Actualizar label
	if has_node("CaptureLabel"):
		if capture_points < max_capture_points:
			$CaptureLabel.text = str(capture_points)
		else:
			$CaptureLabel.text = ""

func _unhandled_input(event):
	if event.is_action_pressed("RMClick"):
		close_production_menu()

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
		if (unit.grid_position == building_position and not unit.is_raider()) or unit.current_state == unit.UnitState.SELECTED:
			return

	if (not main.raider_view_enabled
		and not main.is_menu_open
		and not main.attack_mode
		and not main.mark_mode
		):
		if event.is_action_pressed("LMClick"):
			#if team == main.current_player_team and can_produce_units:
				show_production_menu()

func show_production_menu():
	close_production_menu()
	
	production_menu_instance = PopupPanel.new()
	main.add_child(production_menu_instance)
	
	# Tamaño del menú
	production_menu_instance.size = Vector2(300, 300)
	production_menu_instance.position = Vector2(camera.position.x - 150, camera.position.y - 150)
	
	var main_container = VBoxContainer.new()
	main_container.size = production_menu_instance.size
	main_container.add_theme_constant_override("separation", 5)
	production_menu_instance.add_child(main_container)
	
	# Título
	var title_label = Label.new()
	title_label.text = "PRODUCTION MENU"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(title_label)
	
	# Encabezado de columnas
	var header_container = HBoxContainer.new()
	header_container.add_theme_constant_override("separation", 10)
	main_container.add_child(header_container)
	
	var unit_header = Label.new()
	unit_header.text = "UNIT"
	unit_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	unit_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_container.add_child(unit_header)
	
	var cost_header = Label.new()
	cost_header.text = "COST"
	cost_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cost_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_container.add_child(cost_header)
	
	# Separador
	var separator = HSeparator.new()
	main_container.add_child(separator)
	
	# Obtener datos de producción
	var production_info = production_data.get(building_type, {})
	var available_units = production_info.get("units", [])
	var unit_costs = production_info.get("costs", {})
	
	# Unidades
	for unit_type in available_units:
		var unit_cost = unit_costs.get(unit_type, 0)
		# Verificar fondos según el equipo del edificio
		var can_afford = false
		if team == 1:
			can_afford = (main.team1_funds >= unit_cost)
		elif team == 2:
			can_afford = (main.team2_funds >= unit_cost)
		
		# Fila de unidad
		var unit_row = HBoxContainer.new()
		unit_row.add_theme_constant_override("separation", 10)
		main_container.add_child(unit_row)
		
		# Nombre de la unidad
		var name_label = Label.new()
		name_label.text = unit_type
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		unit_row.add_child(name_label)
		
		# Costo
		var cost_label = Label.new()
		cost_label.text = str(unit_cost)
		cost_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		unit_row.add_child(cost_label)
		
		# Botón (ocupa toda la fila)
		var unit_button = Button.new()
		unit_button.text = "Produce"
		unit_button.custom_minimum_size = Vector2(0, 30)
		unit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		unit_button.disabled = not can_afford
		
		# Color rojizo para unidades no asequibles
		if not can_afford:
			unit_button.add_theme_color_override("font_disabled_color", Color(1, 0.3, 0.3))
			name_label.modulate = Color(1, 0.6, 0.6)
			cost_label.modulate = Color(1, 0.6, 0.6)
		
		unit_button.pressed.connect(_on_unit_button_pressed.bind(unit_type, unit_cost))
		main_container.add_child(unit_button)
	
	# Botón de cerrar
	var close_button = Button.new()
	close_button.text = "CLOSE"
	close_button.custom_minimum_size = Vector2(0, 35)
	close_button.pressed.connect(close_production_menu)
	main_container.add_child(close_button)
	
	# Estilo simple - CORREGIDO
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.1, 0.1, 0.1, 0.98)
	style_box.border_color = Color(0.5, 0.5, 0.5)
	style_box.border_width_left = 2
	style_box.border_width_right = 2
	style_box.border_width_top = 2
	style_box.border_width_bottom = 2
	production_menu_instance.add_theme_stylebox_override("panel", style_box)
	
	production_menu_instance.popup()
	emit_signal("production_menu_opened")

func close_production_menu():
	if production_menu_instance:
		production_menu_instance.queue_free()
		production_menu_instance = null
	emit_signal("production_menu_closed")

func _on_unit_button_pressed(unit: String, cost: int):
	var unit_scene = load("res://scenes/units/" + unit + ".tscn")
	var unit_instance = unit_scene.instantiate()
	main.get_node("Units").add_child(unit_instance)
	unit_instance.team = self.team
	unit_instance.grid_position = building_position
	unit_instance.current_state = unit_instance.UnitState.MOVED
	unit_instance.update_visual_state()
	close_production_menu()
	
	# Restar fondos según el equipo
	if team == 1:
		main.team1_funds -= cost
	elif team == 2:
		main.team2_funds -= cost
	
	hud.update_income_funds()
	main.all_units.append(unit_instance)
	
	# Sincronizar producción en multiplayer (solo si existe el método y estamos conectados)
	if main.has_method("sync_unit_production") and main.multiplayer.multiplayer_peer != null:
		main.sync_unit_production.rpc(building_position.x, building_position.y, unit, team, cost)
