class_name MultiplayerManager
extends Node

# ── Referencias ───────────────────────────────────────────────────────────────
@onready var game_manager  = $"../GameManager"
@onready var action_system = $"../ActionSystem"
@onready var turn_manager  = $"../TurnManager"
@onready var fog_system    = $"../FogSystem"
@onready var state_hasher = $"../StateHasher"

# ── Config ────────────────────────────────────────────────────────────────────
const PORT      := 9999
const MAX_PEERS := 2

# ── Estado ────────────────────────────────────────────────────────────────────
var player_id:    int  = 0
var is_network_connected: bool = false

# ── Señales ───────────────────────────────────────────────────────────────────
signal connected_as_host
signal connected_as_client
signal peer_joined
signal disconnected
signal game_ready

# ══════════════════════════════════════════════════════════════════════════════
# CONEXIÓN
# ══════════════════════════════════════════════════════════════════════════════

func host_game() -> bool:
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(PORT, MAX_PEERS)
	if err != OK:
		push_error("MultiplayerManager: no se pudo crear servidor (error %d)" % err)
		return false
	multiplayer.set_multiplayer_peer(peer)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	player_id = 1
	game_manager.local_player_id = 1
	is_network_connected = true
	connected_as_host.emit()
	return true

func join_game(ip: String) -> bool:
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(ip, PORT)
	if err != OK:
		push_error("MultiplayerManager: no se pudo conectar a %s:%d" % [ip, PORT])
		return false
	multiplayer.set_multiplayer_peer(peer)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	return true

func is_multiplayer_active() -> bool:
	return multiplayer.multiplayer_peer != null and is_network_connected

# ══════════════════════════════════════════════════════════════════════════════
# CALLBACKS DE CONEXIÓN
# ══════════════════════════════════════════════════════════════════════════════

func _on_peer_connected(_id: int) -> void:
	if player_id == 1:
		await get_tree().create_timer(0.3).timeout
	peer_joined.emit()

func _on_connected_to_server() -> void:
	player_id = 2
	game_manager.local_player_id = 2
	is_network_connected = true
	connected_as_client.emit()

func _on_connection_failed() -> void:
	push_error("MultiplayerManager: falló la conexión")
	is_network_connected = false

func _on_peer_disconnected(_id: int) -> void:
	is_network_connected = false
	disconnected.emit()

# ══════════════════════════════════════════════════════════════════════════════
# SINCRONIZACIÓN DE ESTADO INICIAL (host → cliente)
# ══════════════════════════════════════════════════════════════════════════════

func _send_initial_state(client_id: int) -> void:
	var state = {
		"team1_funds":     game_manager.team1_funds,
		"team2_funds":     game_manager.team2_funds,
		"team1_income":    game_manager.team1_income,
		"team2_income":    game_manager.team2_income,
		"current_element": game_manager.current_element,
		"current_team":    turn_manager.current_team,
	}
	rpc_id(client_id, "receive_initial_state", state)

	for unit in game_manager.all_units:
		var mana_val = 0
		if unit is Shade:
			mana_val = (unit as Shade).mana
		var udata = {
			"id":     unit.unit_id,
			"team":   unit.team,
			"x":      unit.grid_position.x,
			"y":      unit.grid_position.y,
			"health": unit.health,
			"state":  unit.state,
			"mana":   mana_val,
		}
		rpc_id(client_id, "receive_unit_state", udata)

	for building in game_manager.all_buildings:
		var bdata = {
			"x":              building.building_position.x,
			"y":              building.building_position.y,
			"team":           building.team,
			"capture_points": building.capture_points,
		}
		rpc_id(client_id, "receive_building_state", bdata)

	rpc_id(client_id, "receive_initial_state_done", {})

func send_initial_state_to_all() -> void:
	for peer_id in multiplayer.get_peers():
		_send_initial_state(peer_id)

@rpc("authority", "reliable")
func receive_initial_state(state: Dictionary) -> void:
	game_manager.team1_funds     = state["team1_funds"]
	game_manager.team2_funds     = state["team2_funds"]
	game_manager.team1_income    = state["team1_income"]
	game_manager.team2_income    = state["team2_income"]
	game_manager.current_element = state["current_element"] as GameManager.Element

@rpc("authority", "reliable")
func receive_unit_state(udata: Dictionary) -> void:
	var pos = Vector2i(udata["x"], udata["y"])
	var unit: Unit = null
	for u in game_manager.all_units:
		if u.grid_position == pos and u.team == udata["team"]:
			unit = u
			break
	if not unit:
		return
	unit.unit_id = udata["id"]  # ← adoptar el ID del host
	unit.health  = udata["health"]
	unit.state   = udata["state"] as Unit.State
	if unit is Shade:
		(unit as Shade).mana = udata.get("mana", 0)
	unit.update_visual()

@rpc("authority", "reliable")
func receive_building_state(bdata: Dictionary) -> void:
	var building = game_manager.get_building_at(Vector2i(bdata["x"], bdata["y"]))
	if building:
		building.team           = bdata["team"]
		building.capture_points = bdata["capture_points"]
		building.update_visual()

@rpc("authority", "reliable")
func receive_initial_state_done(_data: Dictionary) -> void:
	#print("INITIAL STATE [player %d]:\n" % game_manager.local_player_id, state_hasher.compute_state_string())
	fog_system.recalculate(player_id)
	game_ready.emit()

# ══════════════════════════════════════════════════════════════════════════════
# SINCRONIZACIÓN DE ACCIONES
# ══════════════════════════════════════════════════════════════════════════════

func send_action(action_dict: Dictionary) -> void:
	if not is_multiplayer_active():
		return
	rpc("receive_action", action_dict)

@rpc("any_peer", "reliable")
func receive_action(action_dict: Dictionary) -> void:
	var sender = multiplayer.get_remote_sender_id()
	var sender_player = 1 if sender == 1 else 2
	if sender_player == player_id:
		return
	var action = _deserialize_action(action_dict)
	if action:
		await action_system.execute_remote(action)
		if action_dict.get("show_ambush_effect", false):
			var unit = (action as MoveAction).actor
			if is_instance_valid(unit):
				get_node("../UILayer")._show_ambush_effect(unit.global_position)
		send_checksum(action_dict.get("type", "unknown"))
	else:
		push_error("MultiplayerManager: no se pudo deserializar la acción: " + str(action_dict))
# ══════════════════════════════════════════════════════════════════════════════
# SERIALIZACIÓN / DESERIALIZACIÓN
# ══════════════════════════════════════════════════════════════════════════════

func serialize_action(action: BaseAction) -> Dictionary:
	var d = action.to_dict()
	d["type_int"] = action.type
	return d

func _deserialize_action(d: Dictionary) -> BaseAction:
	var type_int = d.get("type_int", -1) as BaseAction.Type

	match type_int:
		BaseAction.Type.MOVE:
			var actor = game_manager.get_unit_by_id(d["actor_id"])
			if not actor: return null
			var action = MoveAction.new(actor, _unpack_path(d), d.get("is_wrapped", false))
			return action

		BaseAction.Type.ATTACK:
			var actor  = game_manager.get_unit_by_id(d["actor_id"])
			var target = game_manager.get_unit_by_id(d["target_id"])
			if not actor or not target: return null
			return AttackAction.new(actor, target, _unpack_path(d), d.get("is_wrapped", false))

		BaseAction.Type.ABILITY:
			var actor  = game_manager.get_unit_by_id(d["actor_id"])
			var target = game_manager.get_unit_by_id(d["target_id"])
			if not actor or not target: return null
			var shade = actor as Shade
			if not shade: return null
			return AbilityAction.new(shade, d["ability"], target, _unpack_path(d))

		BaseAction.Type.CAPTURE:
			var actor    = game_manager.get_unit_by_id(d["actor_id"])
			var building = game_manager.get_building_at(Vector2i(d["building_x"], d["building_y"]))
			if not actor or not building: return null
			return CaptureAction.new(actor, building, _unpack_path(d))

		BaseAction.Type.PRODUCE:
			var building = game_manager.get_building_at(Vector2i(d["building_x"], d["building_y"]))
			if not building: return null
			var unit_data: UnitData = null
			if d.get("is_shade", false) and d.get("shade_element", "") != "":
				var element = d["shade_element"].to_lower()
				unit_data = load("res://data/units/shade_%s_data.tres" % element)
			elif d.get("unit_type", "") == "Drone":
				unit_data = load("res://data/units/drone_data.tres")
			else:
				if building.data:
					for ud in building.data.producible_units:
						if ud.unit_type == d["unit_type"]:
							unit_data = ud
							break
			if not unit_data:
				unit_data = UnitData.new()
				unit_data.unit_type     = d["unit_type"]
				unit_data.is_shade      = d.get("is_shade", false)
				unit_data.shade_element = d.get("shade_element", "")
			var produce = ProduceAction.new(building, unit_data, d["cost"], d["team"])
			produce.unit_id = d.get("unit_id", -1)
			return produce

		BaseAction.Type.SPECIAL:
			var actor = game_manager.get_unit_by_id(d["actor_id"])
			if not actor: return null
			var targets: Array[Unit] = []
			for tid in d.get("target_ids", []):
				var t = game_manager.get_unit_by_id(tid)
				if t: targets.append(t)
			var dir = Vector2i(d.get("dir_x", 0), d.get("dir_y", 0))
			return SpecialAction.new(actor, d["ability_type"], targets, dir, _unpack_path(d))

		BaseAction.Type.OVERWATCH:
			var actor = game_manager.get_unit_by_id(d["actor_id"])
			if not actor: return null
			return OverwatchAction.new(actor)

		BaseAction.Type.DIVIDE:
			var actor = game_manager.get_unit_by_id(d["actor_id"])
			if not actor: return null
			var div_action = DivideAction.new(actor as Drone, Vector2i(d["target_x"], d["target_y"]), _unpack_path(d))
			div_action.new_unit_id = d.get("new_unit_id", -1)
			return div_action

		BaseAction.Type.END_TURN:
			return EndTurnAction.new(d["team"])

	push_error("MultiplayerManager: tipo desconocido type_int=%d" % type_int)
	return null

func _unpack_path(d: Dictionary) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var px: Array = d.get("path_x", [])
	var py: Array = d.get("path_y", [])
	for i in range(px.size()):
		path.append(Vector2i(px[i], py[i]))
	return path

# ══════════════════════════════════════════════════════════════════════════════
# SYNC DE IDs DE UNIDADES PRODUCIDAS
# ══════════════════════════════════════════════════════════════════════════════

@rpc("authority", "reliable")
func receive_new_unit_id(new_id: int, gx: int, gy: int, team: int) -> void:
	for unit in game_manager.all_units:
		if unit.grid_position == Vector2i(gx, gy) and unit.team == team and unit.unit_id == -1:
			unit.unit_id = new_id
			return

func send_checksum(action_name: String) -> void:
	if not is_multiplayer_active():
		return
	var checksum = state_hasher.compute_checksum()
	#print("LOCAL STATE después de '%s':\n" % action_name, state_hasher.compute_state_string())
	rpc("receive_checksum", checksum, action_name)

@rpc("any_peer", "reliable")
func receive_checksum(remote_checksum: int, action_name: String) -> void:
	var sender = multiplayer.get_remote_sender_id()
	var sender_player = 1 if sender == 1 else 2
	if sender_player == player_id:
		return
	var local_checksum = state_hasher.compute_checksum()
	if local_checksum != remote_checksum:
		push_error("DESYNC después de '%s': local=%d remote=%d" % [action_name, local_checksum, remote_checksum])
		#print("DESYNC STATE:\n", state_hasher.compute_state_string())
	else:
		return
		#print("OK checksum después de '%s'" % action_name)
