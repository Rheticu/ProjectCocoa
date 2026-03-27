class_name BuildingData
extends Resource

@export var building_type: String = ""
@export var income_per_turn: int = 0
@export var can_produce_units: bool = false
@export var producible_units: Array[UnitData] = []
@export var sprite_neutral: Texture2D
@export var sprite_team1: Texture2D
@export var sprite_team2: Texture2D
