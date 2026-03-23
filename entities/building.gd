class_name Building
extends Area2D

var team: int = 0
var building_position: Vector2i
var capture_points: int = 20
var max_capture_points: int = 20
var income_per_turn: int = 0
var can_produce: bool = false
var building_type: String = ""

signal ownership_changed(building: Building)

func _ready() -> void:
	building_position = Vector2i(position / 32)
	capture_points = max_capture_points
	update_visual()

func capture(amount: int, capturing_team: int) -> void:
	capture_points -= amount
	if capture_points <= 0:
		var old_team = team
		team = capturing_team
		capture_points = max_capture_points
		if old_team != team:
			ownership_changed.emit(self)
	update_visual()

func reset_capture() -> void:
	capture_points = max_capture_points
	update_visual()

func update_visual() -> void:
	if not has_node("Sprite2D"):
		return
	match team:
		0: $Sprite2D.modulate = Color(1, 1, 1)
		1: $Sprite2D.modulate = Color(0.0, 0.635, 0.957)
		2: $Sprite2D.modulate = Color(1, 0.5, 0.5)
