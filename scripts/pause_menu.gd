extends CanvasLayer

signal resume_game
signal exit_game

@onready var resume_button = $PausePanel/VBoxContainer/ResumeButton
@onready var save_button = $PausePanel/VBoxContainer/SaveButton
@onready var load_button = $PausePanel/VBoxContainer/LoadButton
@onready var exit_button = $PausePanel/VBoxContainer/ExitButton
@onready var pause_panel = $PausePanel
@onready var save_slots_panel = $SaveSlots
@onready var load_slots_panel = $LoadSlots
@onready var main = get_node("/root/Main")

func _ready():
	hide()
	
	# Botones principales
	resume_button.pressed.connect(_on_resume_pressed)
	save_button.pressed.connect(_on_save_pressed)
	load_button.pressed.connect(_on_load_pressed)
	exit_button.pressed.connect(_on_exit_pressed)
	
	# Botones de slots de guardado
	$SaveSlots/VBoxContainer/SaveSlot1Button.pressed.connect(func(): _on_save_slot_pressed(1))
	$SaveSlots/VBoxContainer/SaveSlot2Button.pressed.connect(func(): _on_save_slot_pressed(2))
	$SaveSlots/VBoxContainer/SaveSlot3Button.pressed.connect(func(): _on_save_slot_pressed(3))

	# Botones de slots de carga
	$LoadSlots/VBoxContainer/LoadSlot1Button.pressed.connect(func(): _on_load_slot_pressed(1))
	$LoadSlots/VBoxContainer/LoadSlot2Button.pressed.connect(func(): _on_load_slot_pressed(2))
	$LoadSlots/VBoxContainer/LoadSlot3Button.pressed.connect(func(): _on_load_slot_pressed(3))

	# Al inicio los paneles de slots deben estar ocultos
	save_slots_panel.hide()
	load_slots_panel.hide()

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		toggle_menu()

func toggle_menu():
	if visible:
		hide()
		# Ocultar también los paneles de save/load cuando se cierra el menú
		save_slots_panel.hide()
		load_slots_panel.hide()
		resume_game.emit()
	else:
		show()
		# Asegurarse de que solo se muestre el panel principal
		pause_panel.show()
		save_slots_panel.hide()
		load_slots_panel.hide()

func toggle_load_menu():
	load_slots_panel.show()

func _on_resume_pressed():
	toggle_menu()

func _on_save_pressed():
	save_slots_panel.show()
	load_slots_panel.hide()
	pause_panel.hide()
	update_save_slot_labels()

func _on_load_pressed():
	load_slots_panel.show()
	save_slots_panel.hide()
	pause_panel.hide()
	update_load_slot_labels()

func _on_exit_pressed():
	exit_game.emit()

# -------- SAVE SLOTS --------

func _on_save_slot_pressed(slot: int):
	var savename = "Turno %d" % [main.turn]
	main.save_game(slot, savename)
	update_save_slot_labels()

func update_save_slot_labels():
	for i in range(1, 4):
		var path = "user://save_slot_%d.save" % i
		var button = save_slots_panel.get_node("VBoxContainer/SaveSlot%dButton" % i)
		if FileAccess.file_exists(path):
			var f = FileAccess.open(path, FileAccess.READ)
			var data = f.get_var()
			f.close()
			button.text = "%s" % [data["name"]]
		else:
			button.text = "Empty Slot %d" % i

# -------- LOAD SLOTS --------

func _on_load_slot_pressed(slot: int):
	main.load_game(slot)
	hide()

func update_load_slot_labels():
	for i in range(1, 4):
		var path = "user://save_slot_%d.save" % i
		var button = load_slots_panel.get_node("VBoxContainer/LoadSlot%dButton" % i)
		if FileAccess.file_exists(path):
			var f = FileAccess.open(path, FileAccess.READ)
			var data = f.get_var()
			f.close()
			button.text = "%s" % [data["name"]]
		else:
			button.text = "Empty Slot %d" % i
