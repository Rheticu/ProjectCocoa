extends Node2D

@export var scroll_speed := 400
@export var scroll_margin := 2  # Pixels from edge that trigger scrolling
@onready var main = get_node("/root/Main")
@onready var move_limit: Vector2  # Adjust based on your map size
var production_menu_open: bool = false

var camera: Camera2D
var viewport_size: Vector2
var min_x: float
var min_y: float

func _ready():
	camera = main.get_node("Camera2D") # Adjust path to your camera
	viewport_size = get_viewport().get_visible_rect().size
	#camera.position = Vector2( ((main.map_size.x * 32) / 2) , ((main.map_size.y * 32) / 2) - 32 )
	move_limit.x = (main.map_size.x * 32) - (viewport_size.x / 2)
	move_limit.y =  (main.map_size.y * 32) - (viewport_size.y / 2)
	min_x = (viewport_size.x / 2)
	min_y = (viewport_size.y / 2)

func _on_production_menu_opened():
	production_menu_open = true

func _on_production_menu_closed():
	production_menu_open = false

func _process(delta):
	# Solo mover la cámara si la ventana tiene el foco del sistema operativo
	# Esto funciona tanto para pruebas locales (2 instancias) como para 2 PCs diferentes
	if not get_window().has_focus():
		return
	
	var mouse_pos = get_viewport().get_mouse_position()
	var camera_move = Vector2.ZERO

	# Check edges and calculate movement vector
	if mouse_pos.x < scroll_margin:
		camera_move.x = -1
	elif mouse_pos.x > viewport_size.x - scroll_margin:
		camera_move.x = 1

	if mouse_pos.y < scroll_margin:
		camera_move.y = -1
	elif mouse_pos.y > viewport_size.y - scroll_margin:
		camera_move.y = 1

	# Normalize diagonal movement
	if camera_move.length() > 0:
		camera_move = camera_move.normalized() * scroll_speed * delta

	# Apply movement with bounds checking
	if camera_move != Vector2.ZERO:
		var new_position = camera.global_position + camera_move
		new_position.x = clamp(new_position.x, min_x , move_limit.x)
		new_position.y = clamp(new_position.y, min_y, move_limit.y)
		camera.global_position = new_position
