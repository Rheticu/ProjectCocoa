class_name ProductionMenu
extends PanelContainer

signal unit_selected(unit_data: UnitData, cost: int)
signal closed()

func setup(building: Building, funds: int) -> void:
	# Limpiar contenido previo
	for child in get_children():
		child.queue_free()
	
	# Estilo del panel
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
	add_theme_stylebox_override("panel", panel_style)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)
	
	# Título
	var title = Label.new()
	title.text = "PRODUCTION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	vbox.add_child(title)
	
	# Subtítulo
	var subtitle = Label.new()
	subtitle.text = building.building_type
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.7, 0.9))
	vbox.add_child(subtitle)
	
	vbox.add_child(HSeparator.new())
	
	# Lista de unidades
	for unit_data in building.data.producible_units:
		var cost = unit_data.cost
		var can_afford = funds >= cost
		
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 15)
		row.custom_minimum_size = Vector2(0, 36)
		vbox.add_child(row)
		
		var name_label = Label.new()
		if unit_data.is_shade and unit_data.shade_element != "":
			name_label.text = unit_data.shade_element + " Shade"
		else:
			name_label.text = unit_data.unit_type
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 16)
		if not can_afford:
			name_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		row.add_child(name_label)
		
		var cost_label = Label.new()
		cost_label.text = "$" + str(cost)
		cost_label.add_theme_font_size_override("font_size", 16)
		if not can_afford:
			cost_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		row.add_child(cost_label)
		
		var btn = Button.new()
		btn.text = "BUILD"
		btn.custom_minimum_size = Vector2(80, 32)
		btn.disabled = not can_afford
		if can_afford:
			var style = StyleBoxFlat.new()
			style.bg_color = Color(0.2, 0.6, 0.2, 0.9)
			style.border_color = Color(0.3, 0.8, 0.3)
			style.border_width_left = 1
			style.border_width_right = 1
			style.border_width_top = 1
			style.border_width_bottom = 1
			style.corner_radius_top_left = 4
			style.corner_radius_top_right = 4
			style.corner_radius_bottom_left = 4
			style.corner_radius_bottom_right = 4
			btn.add_theme_stylebox_override("normal", style)
		btn.pressed.connect(func(): unit_selected.emit(unit_data, cost))
		row.add_child(btn)
	
	# Fondos disponibles
	var funds_label = Label.new()
	funds_label.text = "Available: $" + str(funds)
	funds_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	funds_label.add_theme_font_size_override("font_size", 14)
	funds_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	vbox.add_child(funds_label)
	
	# Botón cerrar
	var close_btn = Button.new()
	close_btn.text = "CLOSE"
	close_btn.custom_minimum_size = Vector2(0, 35)
	close_btn.pressed.connect(func(): closed.emit())
	vbox.add_child(close_btn)
