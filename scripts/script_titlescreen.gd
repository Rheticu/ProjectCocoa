extends Node

func _on_new_game_button_pressed():
	get_tree().change_scene_to_file("res://scenes/Mains/PVEMain1.tscn")  # or whatever your game scene is
