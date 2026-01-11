extends CanvasLayer

@onready var unit_info_panel = $UnitInfoPanel
@onready var funds_panel = $FundsPanel
#@onready var unit_name_label = $UnitInfoPanel/UnitName
@onready var health_label = $UnitInfoPanel/VBoxContainer/HealthLabel
@onready var attack_label = $UnitInfoPanel/VBoxContainer/AttackLabel
@onready var defense_label = $UnitInfoPanel/VBoxContainer/DefenseLabel
@onready var movement_label = $UnitInfoPanel/VBoxContainer/MovementLabel
@onready var strong_label = $UnitInfoPanel/VBoxContainer/StrongLabel
#@onready var weak_label = $UnitInfoPanel/VBoxContainer/WeakLabel
@onready var funds_label = $FundsPanel/VBoxContainer/FundsLabel
@onready var income_label = $FundsPanel/VBoxContainer/IncomeLabel
#@onready var health_label = $UnitInfoPanel/HealthLabel
#@onready var unit_sprite = $UnitInfoPanel/UnitSprite
@onready var main = get_node("/root/Main")
var original_position: Vector2

func _ready():
	# Initial setup

	unit_info_panel.visible = false 
	update_income_funds()

func show_unit_info(unit: MapUnit):
	unit_info_panel.visible = true
	#unit_name_label.text = unit.name if hasattr(unit, "name") else "Unit"
	health_label.text = "HP: %d" % unit.health
	attack_label.text = "Att: %d" % unit.attack
	defense_label.text = "Def: %d" % unit.defense
	movement_label.text = "Mov: %d" % unit.movement_range
	if unit.unit_type == "Sword":
		strong_label.text = "+vs: Archer"
	elif unit.unit_type == "Spear":
		strong_label.text = "+vs: Sword"
	elif unit.unit_type == "Archer":
		strong_label.text = "+vs: Spear"
	elif unit.unit_type == "Raider":
		strong_label.text = "+vs: Raider"
	elif unit.unit_type == "Junker":
		strong_label.text = "+vs: "

func hide_unit_info():
	unit_info_panel.visible = false

func update_income_funds():
	var team = main.player_id

	if team == 1:
		funds_label.text = "Funds: %d" % main.team1_funds
		income_label.text = "Income: %d" % main.team1_income
	elif team == 2:
		funds_label.text = "Funds: %d" % main.team2_funds
		income_label.text = "Income: %d" % main.team2_income

func _on_unit_info_panel_mouse_entered() -> void:
	if unit_info_panel.position.x < 100:
		unit_info_panel.position.x = 560
	else:
		unit_info_panel.position.x = 16.0

func _on_funds_panel_mouse_entered() -> void:
	if funds_panel.position.x < 100:
		funds_panel.position.x = 560
	else:
		funds_panel.position.x = 16.0
