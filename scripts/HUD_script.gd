extends CanvasLayer

@onready var end_turn_button = $EndTurnButton as Button
@onready var background = $BackgroundHUD
@onready var unit_info_panel = $UnitInfoPanel
#@onready var unit_name_label = $UnitInfoPanel/UnitName
@onready var attack_label = $UnitInfoPanel/HBoxContainer/AttackLabel
@onready var defense_label = $UnitInfoPanel/HBoxContainer/DefenseLabel
@onready var funds_label = $UnitInfoPanel2/HBoxContainer/Funds
@onready var income_label = $UnitInfoPanel2/HBoxContainer/Income
#@onready var health_label = $UnitInfoPanel/HealthLabel
#@onready var unit_sprite = $UnitInfoPanel/UnitSprite
@onready var main = get_node("/root/Main")
@onready var turn_label = $UnitInfoPanel3/HBoxContainer/TurnLabel

signal end_turn_requested

func _ready():
	# Initial setup
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	unit_info_panel.visible = false  # Hide by default
	funds_label.text = "Funds: %d" % main.team1_funds
	income_label.text = "Income:%d" % main.team1_income
	turn_label.text = "Turno: Jugador %d" % main.current_player_team

func _on_end_turn_pressed():
	end_turn_requested.emit()


func show_unit_info(unit: MapUnit):
	unit_info_panel.visible = true
	#unit_name_label.text = unit.name if hasattr(unit, "name") else "Unit"
	attack_label.text = "Attack: %d" % unit.attack
	defense_label.text = "Defense: %d" % unit.defense
	#health_label.text = "HP: %d/%d" % [unit.health, unit.max_health]

func hide_unit_info():
	unit_info_panel.visible = false

func update_income_funds():
	funds_label.text = "Funds: %d" % main.team1_funds
	income_label.text = "Income:%d" % main.team1_income
	turn_label.text = "Turno: Jugador %d" % main.current_player_team

func set_end_turn_enabled(enabled: bool):
	$EndTurnButton.disabled = not enabled
