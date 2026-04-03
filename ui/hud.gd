class_name HUD
extends CanvasLayer

@onready var game_manager = $"../GameManager"
@onready var turn_manager = $"../TurnManager"

var funds_panel: PanelContainer
var unit_info_panel: PanelContainer

# Labels de fondos
var funds_label: Label
var income_label: Label
var turn_label: Label
var element_label: Label

# Labels de unidad
var unit_hp_label: Label
var unit_attack_label: Label
var unit_defense_label: Label
var unit_movement_label: Label
var unit_type_label: Label
var unit_mana_label: Label
var unit_status_label: Label


func _ready() -> void:
	_build_funds_panel()
	_build_unit_info_panel()

func _build_funds_panel() -> void:
	funds_panel = PanelContainer.new()
	var style = _make_panel_style()
	funds_panel.visible = true
	funds_panel.add_theme_stylebox_override("panel", style)
	add_child(funds_panel)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	funds_panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	turn_label = _make_label("Turn 1", 14, Color(0.9, 0.8, 0.3))
	vbox.add_child(turn_label)

	funds_label = _make_label("$: 0k", 13, Color(0.961, 0.961, 1.0))
	vbox.add_child(funds_label)

	income_label = _make_label("+$: 0k", 13, Color(0.961, 0.961, 1.0))
	vbox.add_child(income_label)

	element_label = _make_label("EARTH", 13, Color(0.513, 0.338, 0.162))
	vbox.add_child(element_label)

	funds_panel.position = Vector2(16, 16)
	funds_panel.mouse_entered.connect(_on_funds_panel_mouse_entered)

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

	unit_type_label = _make_label("", 14, Color(0.9, 0.8, 0.3))
	vbox.add_child(unit_type_label)

	unit_hp_label = _make_label("HP: -", 13, Color(0.961, 0.961, 1.0))
	vbox.add_child(unit_hp_label)

	unit_attack_label = _make_label("Att: -", 13, Color(0.961, 0.961, 1.0))
	vbox.add_child(unit_attack_label)

	unit_defense_label = _make_label("Def: -", 13, Color(0.961, 0.961, 1.0))
	vbox.add_child(unit_defense_label)

	unit_movement_label = _make_label("Mov: -", 13, Color(0.961, 0.961, 1.0))
	vbox.add_child(unit_movement_label)

	unit_mana_label = _make_label("", 13, Color(0.502, 0.988, 1.0))
	vbox.add_child(unit_mana_label)

	unit_status_label = _make_label("", 12, Color(0.9, 0.8, 0.3))
	vbox.add_child(unit_status_label)

	unit_info_panel.position = Vector2(16, 200)
	unit_info_panel.mouse_entered.connect(_on_unit_info_panel_mouse_entered)

func _make_panel_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.9)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.894, 0.093, 0.44, 1.0)
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

func update_funds() -> void:
	var team = game_manager.local_player_id
	var funds = game_manager.get_funds(team)
	var income = game_manager.team1_income if team == 1 else game_manager.team2_income
	funds_label.text = "$: %dk" % (funds / 1000)
	income_label.text = "+$: %dk" % (income / 1000)
	turn_label.text = "Team %d" % team

func show_unit_info(unit: Unit) -> void:
	if unit.is_shade():
		var shade = unit as Shade
		unit_type_label.text = shade.shade_element + " Shade"
		unit_mana_label.text = "Mana: %d/%d" % [shade.mana, shade.max_mana]
		unit_mana_label.visible = true
	else:
		unit_type_label.text = unit.unit_type
		unit_mana_label.visible = false
	unit_hp_label.text = "HP: %d" % unit.health
	unit_attack_label.text = "Att: %d" % unit.attack
	unit_defense_label.text = "Def: %d" % unit.defense
	unit_movement_label.text = "Mov: %d" % unit.movement_range
	var status_parts = []
	if unit.marked_turns > 0:
		status_parts.append("Marked %d" % unit.marked_turns)
	if unit.shield_turns > 0:
		status_parts.append("Shield %d" % unit.shield_turns)
	if unit.boost_turns > 0:
		status_parts.append("Boost %d" % unit.boost_turns)
	if unit.muddle_turns > 0:
		status_parts.append("Muddle %d" % unit.muddle_turns)
	if status_parts.is_empty():
		unit_status_label.visible = false
	else:
		unit_status_label.text = " | ".join(status_parts)
		unit_status_label.visible = true
	unit_info_panel.visible = true

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
