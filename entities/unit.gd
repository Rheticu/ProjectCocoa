class_name Unit
extends Node2D


@export var unit_id: int = -1
@export var team: int = 1
@export var movement_range: int = 3
@export var attack_range: int = 1
@export var vision_range: int = 2
@export var attack: int = 100
@export var defense: int = 10
@export var unit_type: String = ""
@export var ability_range: int 
@export var data: UnitData

var grid_position: Vector2i:
	get: return Vector2i(position / 32)
	set(value): position = Vector2(value) * 32 + Vector2(16, 16)

var health: int = 100
var original_position: Vector2i

enum State {
	IDLE,
	SELECTED,
	ACTION_MENU,
	MOVED,
}

var state: State = State.IDLE

var marked_turns: int = 0
var shield_turns: int = 0
var muddle_turns: int = 0
var boost_turns: int = 0
var is_in_overwatch: bool = false

func _ready() -> void:
	z_index = 4 if is_shade() else 3
	if data:
		unit_type = data.unit_type
		movement_range = data.movement_range
		attack_range = data.attack_range
		vision_range = data.vision_range
		attack = data.attack
		defense = data.defense
		ability_range = data.ability_range
		if data.sprite_team1 and team == 1:
			$Sprite2D.texture = data.sprite_team1
		elif data.sprite_team2 and team == 2:
			$Sprite2D.texture = data.sprite_team2
	update_visual()

func is_shade() -> bool:
	return false

func get_effective_type() -> String:
	return unit_type

func get_total_defense(terrain_bonus: int) -> int:
	var base = defense + terrain_bonus
	if shield_turns > 0:
		return defense * 3 + terrain_bonus
	return base

func tick_buffs() -> void:
	if marked_turns > 0: marked_turns -= 1
	if shield_turns > 0: shield_turns -= 1
	if muddle_turns > 0: muddle_turns -= 1
	if boost_turns > 0:  boost_turns -= 1

func check_death() -> bool:
	return health <= 0

func update_visual() -> void:
	$HealthLabel.text = str(health)
	match state:
		State.SELECTED: $Sprite2D.modulate = Color(1.5, 1.5, 0.536, 1.0)
		State.MOVED:    $Sprite2D.modulate = Color(0.5, 0.5, 0.5)
		_:              $Sprite2D.modulate = Color(1.0, 1.0, 1.0)
