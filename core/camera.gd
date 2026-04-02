class_name GameCamera
extends Camera2D

@export var move_speed: float = 300.0
@export var edge_margin: int = 20

@onready var grid_system = $"../GridSystem"

func _ready() -> void:
	#var map_width = grid_system.map_size.x * grid_system.TILE_SIZE
	#var map_height = grid_system.map_size.y * grid_system.TILE_SIZE
	position = Vector2((20.0*32.0) / 2.0, (11.0*32.0) / 2.0)

func _process(delta: float) -> void:
	var velocity = Vector2.ZERO

	# WASD
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		velocity.x -= 1
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		velocity.x += 1
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		velocity.y -= 1
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		velocity.y += 1

	# Mouse en orillas
	var mouse_pos = get_viewport().get_mouse_position()
	var viewport_size = get_viewport().get_visible_rect().size
	if mouse_pos.x < edge_margin:
		velocity.x -= 1
	if mouse_pos.x > viewport_size.x - edge_margin:
		velocity.x += 1
	if mouse_pos.y < edge_margin:
		velocity.y -= 1
	if mouse_pos.y > viewport_size.y - edge_margin:
		velocity.y += 1

	if velocity != Vector2.ZERO:
		position += velocity.normalized() * move_speed * delta
		_clamp_position()

func _clamp_position() -> void:
	var map_width = grid_system.map_size.x * grid_system.TILE_SIZE
	var map_height = grid_system.map_size.y * grid_system.TILE_SIZE
	var viewport_size = get_viewport().get_visible_rect().size
	position.x = clamp(position.x, viewport_size.x / 2.0, map_width - viewport_size.x / 2.0)
	position.y = clamp(position.y, viewport_size.y / 2.0, map_height - viewport_size.y / 2.0)
