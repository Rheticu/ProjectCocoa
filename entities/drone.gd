class_name Drone
extends Shade

func _ready() -> void:
	super._ready()
	max_mana = 0
	mana = 0
	shade_element = ""

func is_drone() -> bool:
	return true

func get_effective_type() -> String:
	return "Drone"
