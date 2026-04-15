class_name Building
extends Node2D

@export var team: int = 0
var building_position: Vector2i
var capture_points: int = 20
var max_capture_points: int = 20
var income_per_turn: int = 0
var can_produce: bool = false
var building_type: String = ""
var capturing_unit: Unit = null
@export var data: BuildingData

signal ownership_changed(building: Building)

func _ready() -> void:
	building_position = Vector2i(position / 32)
	capture_points = max_capture_points
	if data:
		building_type = data.building_type
		income_per_turn = data.income_per_turn
		can_produce = data.can_produce_units
		if data.sprite_neutral:
			$Sprite2D.texture = data.sprite_neutral
	update_visual()

func capture(amount: int, capturing_team: int, unit: Unit) -> void:
	if capturing_unit and capturing_unit != unit:
		return
	
	if not capturing_unit:
		capturing_unit = unit
		if not unit.tree_exiting.is_connected(_on_capturing_unit_died):
			unit.tree_exiting.connect(_on_capturing_unit_died)
		if not unit.moved.is_connected(_on_capturing_unit_moved):
			unit.moved.connect(_on_capturing_unit_moved)
	
	capture_points -= amount
	if capture_points <= 0:
		var old_team = team
		team = capturing_team
		capture_points = max_capture_points
		_clear_capturing_unit()
		if old_team != team:
			ownership_changed.emit(self)
	update_visual()

func _clear_capturing_unit() -> void:
	if capturing_unit:
		if is_instance_valid(capturing_unit):
			if capturing_unit.tree_exiting.is_connected(_on_capturing_unit_died):
				capturing_unit.tree_exiting.disconnect(_on_capturing_unit_died)
			if capturing_unit.moved.is_connected(_on_capturing_unit_moved):
				capturing_unit.moved.disconnect(_on_capturing_unit_moved)
		capturing_unit = null

func _on_capturing_unit_died() -> void:
	reset_capture()
	_clear_capturing_unit()

func _on_capturing_unit_moved(new_pos: Vector2i) -> void:
	if new_pos != building_position:
		reset_capture()
		_clear_capturing_unit()

func reset_capture() -> void:
	capture_points = max_capture_points
	update_visual()

func update_visual() -> void:
	if not has_node("Sprite2D"):
		return
	if data:
		match team:
			0: $Sprite2D.texture = data.sprite_neutral
			1: $Sprite2D.texture = data.sprite_team1
			2: $Sprite2D.texture = data.sprite_team2
	else:
		match team:
			0: $Sprite2D.modulate = Color(1, 1, 1)
			1: $Sprite2D.modulate = Color(0.0, 0.635, 0.957)
			2: $Sprite2D.modulate = Color(1, 0.5, 0.5)

func show_as_team(visual_team: int) -> void:
	if not has_node("Sprite2D"):
		return
	if data:
		match visual_team:
			0: $Sprite2D.texture = data.sprite_neutral
			1: $Sprite2D.texture = data.sprite_team1
			2: $Sprite2D.texture = data.sprite_team2
	else:
		match visual_team:
			0: $Sprite2D.modulate = Color(1, 1, 1)
			1: $Sprite2D.modulate = Color(0.0, 0.635, 0.957)
			2: $Sprite2D.modulate = Color(1, 0.5, 0.5)
