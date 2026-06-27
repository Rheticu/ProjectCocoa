class_name HUD
extends CanvasLayer

@onready var game_manager = $"../GameManager"
@onready var turn_manager = $"../TurnManager"

var funds_panel: PanelContainer
var unit_info_panel: PanelContainer
var size_font = 8
var turn_message_label: Label
var _turn_tween: Tween

# Labels de game panel
var funds_label: Label
var funds_label2: Label
var income_label: Label
var turn_label: Label
var element_label: Label
var _border_tween: Tween
var _current_border_color: Color = Color(0.905, 0.0, 0.213)

# Labels de unidad
var unit_hp_label: Label
var unit_attack_label: Label
var unit_defense_label: Label
var unit_movement_label: Label
var unit_type_label: Label
var unit_mana_label: Label
var unit_status_label: Label

func _ready() -> void:
	_build_game_panel()
	_build_unit_info_panel()
	turn_message_label = Label.new()
	turn_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	turn_message_label.add_theme_font_size_override("font_size", 32)
	turn_message_label.add_theme_color_override("font_color", Color(1, 1, 1))
	turn_message_label.set_anchors_preset(Control.PRESET_CENTER)
	turn_message_label.visible = false
	add_child(turn_message_label)

func _build_game_panel() -> void:
	funds_panel = PanelContainer.new()
	var style = _make_panel_style()
	funds_panel.visible = true
	funds_panel.add_theme_stylebox_override("panel", style)
	add_child(funds_panel)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_bottom", 2)
	funds_panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 1)
	margin.add_child(vbox)

	turn_label = _make_label("Turn 1", size_font + 1, Color(0.961, 0.961, 1.0))
	vbox.add_child(turn_label)

	funds_label = _make_label("$: 0k", size_font, Color(0.961, 0.961, 1.0))
	vbox.add_child(funds_label)

	income_label = _make_label("+$: 0k", size_font, Color(0.961, 0.961, 1.0))
	vbox.add_child(income_label)

	element_label = _make_label("EARTH", size_font, Color(0.513, 0.338, 0.162))
	vbox.add_child(element_label)

	funds_panel.position = Vector2(16, 16)
	funds_panel.mouse_entered.connect(_on_funds_panel_mouse_entered)

func _start_panel_pulse() -> void:
	if _border_tween:
		_border_tween.kill()
	var style = funds_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if not style:
		return
	_border_tween = create_tween().set_loops()
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	_border_tween.tween_method(func(a: float):
		style.border_color = _current_border_color.lerp(Color.WHITE, a)
		turn_label.add_theme_color_override("font_color", _current_border_color.lerp(Color.WHITE, a)),
		0.0, 1.0, 1)
	_border_tween.tween_method(func(a: float):
		style.border_color = _current_border_color.lerp(Color.WHITE, a)
		turn_label.add_theme_color_override("font_color", _current_border_color.lerp(Color.WHITE, a)),
		1.0, 0.0, 1)

func _stop_panel_pulse() -> void:
	turn_label.add_theme_color_override("font_color", Color(0.961, 0.961, 1.0))
	if _border_tween:
		_border_tween.kill()
		_border_tween = null
	var style = funds_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		style.border_color = _current_border_color

func _build_unit_info_panel() -> void:
	unit_info_panel = PanelContainer.new()
	var style = _make_panel_style()
	unit_info_panel.add_theme_stylebox_override("panel", style)
	unit_info_panel.visible = false
	add_child(unit_info_panel)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	unit_info_panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	unit_type_label = _make_label("", size_font + 1 , Color(0.9, 0.8, 0.3))
	vbox.add_child(unit_type_label)

	unit_hp_label = _make_label("HP: -", size_font, Color(0.961, 0.961, 1.0))
	vbox.add_child(unit_hp_label)

	unit_attack_label = _make_label("Att: -", size_font, Color(0.961, 0.961, 1.0))
	vbox.add_child(unit_attack_label)

	unit_defense_label = _make_label("Def: -", size_font, Color(0.961, 0.961, 1.0))
	vbox.add_child(unit_defense_label)

	unit_movement_label = _make_label("Mov: -", size_font, Color(0.961, 0.961, 1.0))
	vbox.add_child(unit_movement_label)

	unit_mana_label = _make_label("", size_font, Color(0.502, 0.988, 1.0))
	vbox.add_child(unit_mana_label)

	unit_status_label = _make_label("", size_font, Color(0.9, 0.8, 0.3))
	vbox.add_child(unit_status_label)

	unit_info_panel.position = Vector2(16, 0)
	unit_info_panel.mouse_entered.connect(_on_unit_info_panel_mouse_entered)

func _make_panel_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.9)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.905, 0.0, 0.213)
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	return style

func _make_label(text: String, size: int, color: Color) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func update_game_panel() -> void:
	var local_team = game_manager.local_player_id
	var current_team = turn_manager.current_team
	var funds = game_manager.get_funds(local_team)
	var income = game_manager.team1_income if local_team == 1 else game_manager.team2_income
	funds_label.text = "$: %dk" % (funds / 1000)
	income_label.text = "+$: %dk" % (income / 1000)
	if local_team == current_team:
		turn_label.visible = true
		turn_label.text = "Tu Turno"
		_start_panel_pulse()
	else:
		turn_label.visible = false
		_stop_panel_pulse()

func show_unit_info(unit: Unit) -> void:
	if unit.is_shade():
		if unit.unit_type == "Shade":
			var shade = unit as Shade
			unit_type_label.text = shade.shade_element
			unit_mana_label.text = "Mana: %d/%d" % [shade.mana, shade.max_mana]
			unit_mana_label.visible = true
		else:
			unit_type_label.text = unit.unit_type
			unit_mana_label.visible = false
	else:
		unit_type_label.text = unit.unit_type
		unit_mana_label.visible = false
	unit_hp_label.text = "HP: %d" % unit.health
	unit_attack_label.text = "Att: %d" % unit.attack
	unit_defense_label.text = "Def: %d" % unit.defense
	unit_movement_label.text = "Mov: %d" % unit.movement_range
	var status_parts = []
	if unit.marked_turns > 0 and unit.marked2_turns == 0:
		status_parts.append("Marked %d" % unit.marked_turns)
	if unit.marked2_turns > 0:
		status_parts.append("++Marked %d" % unit.marked2_turns)
	if unit.shield_turns > 0 and unit.shield2_source_turns == 0:
		status_parts.append("Shield %d" % unit.shield_turns)
	if unit.boost_turns > 0 and unit.boost2_source_turns == 0:
		status_parts.append("Boost %d" % unit.boost_turns)
	if unit.muddle_turns > 0 and unit.muddle2_source_turns == 0:
		status_parts.append("Muddle %d" % unit.muddle_turns)
	if unit.boost2_source_turns > 0:
		status_parts.append("Boost Source")
	if unit.shield2_source_turns > 0:
		status_parts.append("Shield Source")
	if unit.muddle2_source_turns > 0:
		status_parts.append("Muddle Source")
	if unit.aura_boosted:
		status_parts.append("Aura Boost")
	if unit.aura_shielded:
		status_parts.append("Aura Shield")
	if unit.aura_muddled:
		status_parts.append("Aura Muddle")
	if status_parts.is_empty():
		unit_status_label.visible = false
	else:
		unit_status_label.text = " | ".join(status_parts)
		unit_status_label.visible = true
	unit_info_panel.visible = true
	unit_info_panel.reset_size()
	call_deferred("_reposition_unit_panel")

func _reposition_unit_panel() -> void:
	var viewport_height = get_viewport().get_visible_rect().size.y
	var panel_height = unit_info_panel.size.y
	var x = unit_info_panel.position.x  # mantener x actual (16 o 560)
	unit_info_panel.position = Vector2(x, viewport_height - panel_height - 16)

func hide_unit_info() -> void:
	unit_info_panel.visible = false

func _on_funds_panel_mouse_entered() -> void:
	if funds_panel.position.x < 100:
		funds_panel.position.x = 560
	else:
		funds_panel.position.x = 16

func _on_unit_info_panel_mouse_entered() -> void:
	if unit_info_panel.position.x < 100:
		unit_info_panel.position.x = 560
	else:
		unit_info_panel.position.x = 16

func update_element() -> void:
	var element_names = ["EARTH", "METAL", "WATER", "WOOD", "FIRE"]
	var style = funds_panel.get_theme_stylebox("panel") as StyleBoxFlat
	var unit_style = unit_info_panel.get_theme_stylebox("panel") as StyleBoxFlat
	var element_colors = [
		Color(0.513, 0.338, 0.162),
		Color(0.968, 0.862, 0.106),
		Color(0.502, 0.988, 1.0),
		Color(0.13, 0.827, 0.397),
		Color(0.905, 0.0, 0.213)
	]
	var idx = game_manager.current_element
	element_label.text = element_names[idx]
	element_label.add_theme_color_override("font_color", element_colors[idx])
	_current_border_color = element_colors[idx]
	if style:
		style.border_color = _current_border_color
	if unit_style:
		unit_style.border_color = _current_border_color

func show_turn_message(message: String) -> void:
	turn_message_label.text = message
	turn_message_label.modulate.a = 1.0
	turn_message_label.visible = true
	await get_tree().process_frame  # Esperar a que se calcule el tamaño
	var viewport_size = get_viewport().get_visible_rect().size
	turn_message_label.position = Vector2(
		(viewport_size.x - turn_message_label.size.x) / 2.0,
		(viewport_size.y - turn_message_label.size.y) / 2.0
	)
	if _turn_tween:
		_turn_tween.kill()
	_turn_tween = create_tween()
	_turn_tween.tween_interval(1.5)
	_turn_tween.tween_property(turn_message_label, "modulate:a", 0.0, 0.8)
	_turn_tween.tween_callback(func(): turn_message_label.visible = false)
