## res://ui/lobby.gd
## Nodo: CanvasLayer llamado "Lobby", hijo directo de Game.
## Genera su propia UI en código — no necesita hijos en el editor.
class_name Lobby
extends CanvasLayer

@onready var multiplayer_manager = $"../MultiplayerManager"

var _status_label: Label
var _ip_field: LineEdit
var _host_btn: Button
var _join_btn: Button

func _ready() -> void:
	_build_ui()
	multiplayer_manager.connected_as_host.connect(_on_connected_as_host)
	multiplayer_manager.connected_as_client.connect(_on_connected_as_client)
	multiplayer_manager.peer_joined.connect(_on_peer_joined)
	multiplayer_manager.disconnected.connect(_on_disconnected)
	multiplayer_manager.game_ready.connect(_on_game_ready)

func _build_ui() -> void:
	# Fondo semitransparente
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Panel central
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.97)
	style.border_color = Color(0.3, 0.3, 0.5)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.custom_minimum_size = Vector2(240, 0)
	margin.add_child(vbox)

	# Título
	var title = Label.new()
	title.text = "Project Cocoa"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.5))
	vbox.add_child(title)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	# Campo IP
	var ip_label = Label.new()
	ip_label.text = "IP del host:"
	ip_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(ip_label)

	_ip_field = LineEdit.new()
	_ip_field.placeholder_text = "127.0.0.1"
	_ip_field.text = "127.0.0.1"
	_ip_field.custom_minimum_size = Vector2(0, 28)
	vbox.add_child(_ip_field)

	# Botones
	_host_btn = _make_button("Crear partida (Host)", Color(0.15, 0.45, 0.15))
	_host_btn.pressed.connect(_on_host_pressed)
	vbox.add_child(_host_btn)

	_join_btn = _make_button("Unirse (Join)", Color(0.15, 0.25, 0.45))
	_join_btn.pressed.connect(_on_join_pressed)
	vbox.add_child(_join_btn)

	# Estado
	_status_label = Label.new()
	_status_label.text = ""
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 11)
	_status_label.add_theme_color_override("font_color", Color(1, 0.8, 0.2))
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_status_label)

func _make_button(text: String, bg_color: Color) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 30)
	var style = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = bg_color.lightened(0.3)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", style)
	var hover = style.duplicate()
	hover.bg_color = bg_color.lightened(0.1)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	return btn

func _set_status(text: String) -> void:
	_status_label.text = text

func _on_host_pressed() -> void:
	_host_btn.disabled = true
	_join_btn.disabled = true
	var ok = multiplayer_manager.host_game()
	_set_status("Esperando al otro jugador..." if ok else "Error al crear servidor")
	if not ok:
		_host_btn.disabled = false
		_join_btn.disabled = false

func _on_join_pressed() -> void:
	_host_btn.disabled = true
	_join_btn.disabled = true
	var ip = _ip_field.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	var ok = multiplayer_manager.join_game(ip)
	_set_status("Conectando a %s..." % ip if ok else "Error de conexión")
	if not ok:
		_host_btn.disabled = false
		_join_btn.disabled = false

func _on_connected_as_host() -> void:
	_set_status("Servidor activo — esperando jugador...")

func _on_connected_as_client() -> void:
	_set_status("Conectado — esperando estado del host...")

func _on_peer_joined() -> void:
	_set_status("¡Ambos conectados! Iniciando...")
	await get_tree().create_timer(0.6).timeout
	visible = false
	get_parent().start_multiplayer_game()

func _on_disconnected() -> void:
	visible = true
	_set_status("Desconectado")
	_host_btn.disabled = false
	_join_btn.disabled = false

func _on_game_ready() -> void:
	visible = false
	get_parent().start_multiplayer_game()
