class_name Unit
extends Node2D

@export var team: int = 1
@export var data: UnitData

var unit_id: int = -1
var movement_range: int
var attack_range: int
var vision_range: int
var attack: int
var defense: int
var unit_type: String
var ability_range: int 
var health: int = 100
var original_position: Vector2i
var grid_position: Vector2i:
	get: return Vector2i(position / 32)
	set(value):
		position = Vector2(value) * 32 + Vector2(16, 16)
		moved.emit(value)

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
var muddle2_source_turns: int = 0
var boost2_source_turns: int = 0
var shield2_source_turns: int = 0
var marked2_turns: int = 0
var aura_muddled: bool = false
var aura_boosted: bool = false
var aura_shielded: bool = false

signal moved(new_position: Vector2i)

func _ready() -> void:
	z_index = 7 if is_shade() else 3
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
	if shield_turns > 0 or aura_shielded:
		return (defense * 3) + terrain_bonus
	return base

func tick_buffs(current_team) -> void:
	if team == current_team:
		if boost_turns > 0:  boost_turns -= 1
		if shield_turns > 0: shield_turns -= 1
		if boost2_source_turns > 0:  boost2_source_turns -= 1
		if shield2_source_turns > 0: shield2_source_turns -= 1
	else:
		if marked_turns > 0: marked_turns -= 1
		if marked2_turns > 0: marked2_turns -= 1
		if muddle_turns > 0: muddle_turns -= 1
		if muddle2_source_turns > 0: muddle2_source_turns -= 1

func check_death() -> bool:
	return health <= 0

func update_visual() -> void:
	$HealthLabel.text = str(health)
	match state:
		State.SELECTED: $Sprite2D.modulate = Color(1.5, 1.5, 0.536, 1.0)
		State.MOVED:    $Sprite2D.modulate = Color(0.5, 0.5, 0.5)
		_:              $Sprite2D.modulate = Color(1.0, 1.0, 1.0)
