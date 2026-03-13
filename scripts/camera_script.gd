extends Node2D

@export var scroll_speed := 400
@export var scroll_margin := 2
@onready var main = get_node("/root/Main")
@onready var move_limit: Vector2
var production_menu_open: bool = false

var camera: Camera2D
var viewport_size: Vector2
var min_x: float
var min_y: float

# Variables para input WASD
var wasd_input := Vector2.ZERO

func _ready():
	camera = main.get_node("Camera2D")
	viewport_size = get_viewport().get_visible_rect().size
	await main.ready
	move_limit.x = (main.map_size.x * 32) - (viewport_size.x / 2)
	move_limit.y =  (main.map_size.y * 32) - (viewport_size.y / 2)
	min_x = (viewport_size.x / 2)
	min_y = (viewport_size.y / 2)

func _on_production_menu_opened():
	production_menu_open = true

func _on_production_menu_closed():
	production_menu_open = false

func _input(event):
	# Capturar input de teclado para WASD
	if event.is_action_pressed("move_up") or event.is_action_pressed("move_down") or \
	   event.is_action_pressed("move_left") or event.is_action_pressed("move_right"):
		update_wasd_input()
	elif event.is_action_released("move_up") or event.is_action_released("move_down") or \
		 event.is_action_released("move_left") or event.is_action_released("move_right"):
		update_wasd_input()

func update_wasd_input():
	wasd_input = Vector2.ZERO
	if Input.is_action_pressed("move_right"):
		wasd_input.x += 1
	if Input.is_action_pressed("move_left"):
		wasd_input.x -= 1
	if Input.is_action_pressed("move_down"):
		wasd_input.y += 1
	if Input.is_action_pressed("move_up"):
		wasd_input.y -= 1

func _process(delta):
	if not get_window().has_focus():
		return
	
	if production_menu_open:
		return
	
	var camera_move = Vector2.ZERO
	
	# Prioridad 1: Movimiento por teclado (WASD)
	if wasd_input != Vector2.ZERO:
		camera_move = wasd_input.normalized() * scroll_speed * delta
	else:
		# Prioridad 2: Movimiento por bordes de pantalla
		var mouse_pos = get_viewport().get_mouse_position()
		
		if mouse_pos.x < scroll_margin:
			camera_move.x = -1
		elif mouse_pos.x > viewport_size.x - scroll_margin:
			camera_move.x = 1

		if mouse_pos.y < scroll_margin:
			camera_move.y = -1
		elif mouse_pos.y > viewport_size.y - scroll_margin:
			camera_move.y = 1

		if camera_move.length() > 0:
			camera_move = camera_move.normalized() * scroll_speed * delta

	# Aplicar movimiento con límites
	if camera_move != Vector2.ZERO:
		var new_position = camera.global_position + camera_move
		new_position.x = clamp(new_position.x, min_x, move_limit.x)
		new_position.y = clamp(new_position.y, min_y, move_limit.y)
		camera.global_position = new_position
