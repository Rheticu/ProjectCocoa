extends Control

signal create_game_pressed
signal join_game_pressed
signal ip_changed(new_ip: String)

@onready var create_button = $Panel/VBoxContainer/CreateButton
@onready var join_button = $Panel/VBoxContainer/JoinButton
@onready var ip_input = $Panel/VBoxContainer/IPInput
@onready var status_label = $Panel/VBoxContainer/StatusLabel

func _ready():
	create_button.pressed.connect(_on_create_pressed)
	join_button.pressed.connect(_on_join_pressed)
	ip_input.text_changed.connect(_on_ip_changed)
	ip_input.text = "127.0.0.1"
	status_label.text = "No conectado"

func _on_create_pressed():
	create_game_pressed.emit()

func _on_join_pressed():
	join_game_pressed.emit()

func _on_ip_changed(new_text: String):
	ip_changed.emit(new_text)

func set_status(text: String):
	status_label.text = text
