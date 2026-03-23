class_name Shade
extends Unit

var mana: int = 0
var max_mana: int = 5
var shade_element: String = ""  # "FIRE", "WATER", "EARTH", "WOOD", "METAL"

func is_shade() -> bool:
	return true

func get_element() -> String:
	return shade_element

func get_effective_type() -> String:
	return "Shade_" + shade_element
