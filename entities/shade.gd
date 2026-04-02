class_name Shade
extends Unit

var mana: int = 0
var max_mana: int = 5
var shade_element: String = ""  # "FIRE", "WATER", "EARTH", "WOOD", "METAL"

func _ready() -> void:
	super._ready()
	if data and data.shade_element != "":
		shade_element = data.shade_element

func is_shade() -> bool:
	return true

func get_element() -> String:
	return shade_element

func get_effective_type() -> String:
	return "Shade_" + shade_element
