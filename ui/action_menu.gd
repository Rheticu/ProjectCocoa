class_name ActionMenu
extends VBoxContainer

signal move_pressed()
signal attack_pressed()
signal cancel_pressed()
signal capture_pressed()
signal ability_pressed(ability: String)
signal end_turn_pressed()
signal load_pressed()
signal unload_pressed()

@onready var move_btn = $Move
@onready var attack_btn = $Attack
@onready var cancel_btn = $Cancel
@onready var capture_btn = $Capture
@onready var thrust_btn = $Thrust
@onready var bash_btn = $Bash
@onready var volley_btn = $Volley
@onready var overwatch_btn = $Overwatch
@onready var mark_btn = $Mark
@onready var scorch_btn = $Scorch
@onready var shield_btn = $Shield
@onready var muddle_btn = $Muddle
@onready var boost_btn = $Boost
@onready var mark2_btn = $Mark2
@onready var scorch2_btn = $Scorch2
@onready var shield2_btn = $Shield2
@onready var muddle2_btn = $Muddle2
@onready var boost2_btn = $Boost2
@onready var divide_btn = $Divide
@onready var options_btn = $Options
@onready var end_turn_btn = $EndTurn
@onready var load_btn = $Load
@onready var unload_btn = $Unload


func _ready() -> void:
	move_btn.pressed.connect(func(): move_pressed.emit())
	attack_btn.pressed.connect(func(): attack_pressed.emit())
	cancel_btn.pressed.connect(func(): cancel_pressed.emit())
	capture_btn.pressed.connect(func(): capture_pressed.emit())
	thrust_btn.pressed.connect(func(): ability_pressed.emit("THRUST"))
	bash_btn.pressed.connect(func(): ability_pressed.emit("BASH"))
	volley_btn.pressed.connect(func(): ability_pressed.emit("VOLLEY"))
	overwatch_btn.pressed.connect(func(): ability_pressed.emit("OVERWATCH"))
	mark_btn.pressed.connect(func(): ability_pressed.emit("MARK"))
	scorch_btn.pressed.connect(func(): ability_pressed.emit("SCORCH"))
	shield_btn.pressed.connect(func(): ability_pressed.emit("SHIELD"))
	muddle_btn.pressed.connect(func(): ability_pressed.emit("MUDDLE"))
	boost_btn.pressed.connect(func(): ability_pressed.emit("BOOST"))
	mark2_btn.pressed.connect(func(): ability_pressed.emit("MARK2"))
	scorch2_btn.pressed.connect(func(): ability_pressed.emit("SCORCH2"))
	shield2_btn.pressed.connect(func(): ability_pressed.emit("SHIELD2"))
	muddle2_btn.pressed.connect(func(): ability_pressed.emit("MUDDLE2"))
	boost2_btn.pressed.connect(func(): ability_pressed.emit("BOOST2"))
	divide_btn.pressed.connect(func(): ability_pressed.emit("DIVIDE"))
	end_turn_btn.pressed.connect(func(): end_turn_pressed.emit())
	load_btn.pressed.connect(func(): load_pressed.emit())
	unload_btn.pressed.connect(func(): unload_pressed.emit())

func show_for_unit(
	unit: Unit,
	building: Building,
	has_targets: bool = false,
	has_thrust_targets: bool = false,
	has_bash_targets: bool = false,
	has_volley_targets: bool = false,
	has_overwatch: bool = false,
	has_mark_targets: bool = false,
	has_scorch_targets: bool = false,
	has_shield_targets: bool = false,
	has_muddle_targets: bool = false,
	has_boost_targets: bool = false,
	can_load: bool = false,
	can_unload: bool = false
) -> void:
	# Por defecto ocultar todo
	attack_btn.visible = has_targets
	capture_btn.visible = false
	thrust_btn.visible = false
	bash_btn.visible = false
	volley_btn.visible = false
	overwatch_btn.visible = false
	mark_btn.visible = false
	scorch_btn.visible = false
	shield_btn.visible = false
	muddle_btn.visible = false
	boost_btn.visible = false
	mark2_btn.visible = false
	scorch2_btn.visible = false
	shield2_btn.visible = false
	muddle2_btn.visible = false
	boost2_btn.visible = false
	divide_btn.visible = unit is Drone and unit.health >= 40
	options_btn.visible = false
	end_turn_btn.visible = false
	load_btn.visible = can_load
	unload_btn.visible = can_unload

	# Siempre visibles
	move_btn.visible = not can_load
	cancel_btn.visible = true

	# Según tipo de unidad
	if not unit.is_shade():
		match unit.unit_type:
			"Sword":   thrust_btn.visible = has_thrust_targets
			"Spear":   bash_btn.visible = has_bash_targets
			"Archer":  volley_btn.visible = has_volley_targets
			"Cannon":  overwatch_btn.visible = has_overwatch

	# Shade habilidades
	if unit.is_shade():
		var shade = unit as Shade
		match shade.shade_element:
			"WATER":
				mark_btn.visible = has_mark_targets and shade.mana >= 2
				mark2_btn.visible = has_mark_targets and shade.mana >= 3
			"FIRE":
				scorch_btn.visible = has_scorch_targets and shade.mana >= 2
				scorch2_btn.visible = has_scorch_targets and shade.mana >= 3
			"METAL":
				shield_btn.visible = has_shield_targets and shade.mana >= 2
				shield2_btn.visible = has_shield_targets and shade.mana >= 3
			"EARTH":
				muddle_btn.visible = has_muddle_targets and shade.mana >= 2
				muddle2_btn.visible = has_muddle_targets and shade.mana >= 3
			"WOOD":
				boost_btn.visible = has_boost_targets and shade.mana >= 2
				boost2_btn.visible = has_boost_targets and shade.mana >= 3


	# Captura
	if building != null and building.team != unit.team:
		if unit.unit_type in ["Sword", "Archer", "Spear"]:
			capture_btn.visible = true

func show_for_empty_tile() -> void:
	attack_btn.visible = false
	capture_btn.visible = false
	thrust_btn.visible = false
	bash_btn.visible = false
	volley_btn.visible = false
	overwatch_btn.visible = false
	mark_btn.visible = false
	scorch_btn.visible = false
	shield_btn.visible = false
	muddle_btn.visible = false
	boost_btn.visible = false
	mark2_btn.visible = false
	scorch2_btn.visible = false
	shield2_btn.visible = false
	muddle2_btn.visible = false
	boost2_btn.visible = false
	divide_btn.visible = false
	move_btn.visible = false
	options_btn.visible = true
	cancel_btn.visible = true
	end_turn_btn.visible = true
	load_btn.visible = false
	unload_btn.visible = false
