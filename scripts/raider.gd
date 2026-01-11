class_name Raider_Unit
extends MapUnit

#@export var map_size := Vector2i(20, 15)
@export var mark_range: int = 4

func is_raider() -> bool:
	return true

func _on_input_event(_viewport, event, _shape_idx):
	# Verificar is_ai_processing solo si existe (PvE), en PvP no existe
	if "is_ai_processing" in main and main.is_ai_processing:
		return 
	
	# Si estamos en mark_mode, no procesar eventos de unidades (el mark se maneja en _unhandled_input)
	if "mark_mode" in main and main.mark_mode:
		return
	
	if main.raider_view_enabled:
		if event.is_action_pressed("LMClick"):
			# Si estamos en mark_mode, no hacer nada (el mark se maneja en _unhandled_input)
			if "mark_mode" in main and main.mark_mode:
				return
			
			# Verificar si es PvP y si es mi turno
			var can_select = false
			if "player_id" in main:
				# PvP: solo puedo seleccionar si es mi turno y la unidad es de mi equipo
				can_select = (main.current_player_team == main.player_id and team == main.current_player_team)
			else:
				# PvE: solo team 1 puede seleccionar
				can_select = (team == 1)
			
			if (
				current_state == UnitState.UNSELECTED
				and can_select
				and not main.is_menu_open
				and not main.attack_mode
				and not main.mark_mode):
				select()
			elif (
				team != main.current_player_team
				and not main.is_menu_open
				and not main.attack_mode
				and not main.mark_mode
				and current_state != UnitState.UNSELECTABLE):
				main.update_active_layers()
				main.active_overlay.clear()
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
	target.marked_turns = 4  # Mark for 3 turns
	current_state = UnitState.MOVED  # Can't move after marking
	update_visual_state()
	
	# Visual feedback for marking
	if target.has_node("Sprite2D"):
		var sprite: Sprite2D = target.get_node("Sprite2D")
		var original_modulate = sprite.modulate
		sprite.modulate = Color(1, 1, 0)  # Yellow flash for marking
		
		# Create a tween to flash back to normal
		var tween = create_tween()
		tween.tween_interval(0.3)
		tween.tween_callback(func():
			if is_instance_valid(sprite):
				sprite.modulate = original_modulate
		)
	
	main.update_fog_of_war()  # Update fog to show marked unit
