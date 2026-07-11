# core/signaling_client.gd
class_name SignalingClient
extends Node

enum Message {
	JOIN,
	ID,
	PEER_CONNECT,
	PEER_DISCONNECT,
	OFFER,
	ANSWER,
	CANDIDATE,
	SEAL,
}

@export var autojoin: bool = true
@export var lobby: String = ""
@export var mesh: bool = true

var ws := WebSocketPeer.new()
var code := 1000
var reason: String = "Unknown"
var old_state := WebSocketPeer.STATE_CLOSED

signal lobby_joined(lobby: String)
signal connected(id: int, use_mesh: bool)
signal disconnected()
signal peer_connected(id: int)
signal peer_disconnected(id: int)
signal offer_received(id: int, offer: String)
signal answer_received(id: int, answer: String)
signal candidate_received(id: int, mid: String, index: int, sdp: String)
signal lobby_sealed()

func connect_to_url(url: String) -> void:
	close()
	code = 1000
	reason = "Unknown"
	ws.connect_to_url(url)

func close() -> void:
	ws.close()

func _process(_delta: float) -> void:
	ws.poll()
	var state := ws.get_ready_state()
	if state != old_state and state == WebSocketPeer.STATE_OPEN and autojoin:
		join_lobby(lobby)
	while state == WebSocketPeer.STATE_OPEN and ws.get_available_packet_count():
		if not _parse_msg():
			print("Error parsing message from server.")
	if state != old_state and state == WebSocketPeer.STATE_CLOSED:
		code = ws.get_close_code()
		reason = ws.get_close_reason()
		disconnected.emit()
	old_state = state

func _parse_msg() -> bool:
	var parsed: Dictionary = JSON.parse_string(ws.get_packet().get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("type") or not parsed.has("id") or \
		typeof(parsed.get("data")) != TYPE_STRING:
		return false

	var msg := parsed as Dictionary

	var type := int(msg.type)
	var src_id := int(msg.id)

	if type == Message.ID:
		connected.emit(src_id, msg.data == "true")
	elif type == Message.JOIN:
		lobby_joined.emit(msg.data)
	elif type == Message.SEAL:
		lobby_sealed.emit()
	elif type == Message.PEER_CONNECT:
		peer_connected.emit(src_id)
	elif type == Message.PEER_DISCONNECT:
		peer_disconnected.emit(src_id)
	elif type == Message.OFFER:
		offer_received.emit(src_id, msg.data)
	elif type == Message.ANSWER:
		answer_received.emit(src_id, msg.data)
	elif type == Message.CANDIDATE:
		var candidate: PackedStringArray = msg.data.split("\n", false)
		if candidate.size() != 3:
			return false
		if not candidate[1].is_valid_int():
			return false
		candidate_received.emit(src_id, candidate[0], candidate[1].to_int(), candidate[2])
	else:
		return false

	return true

func join_lobby(lobby_name: String) -> Error:
	print("📤 Enviando JOIN con lobby: ", lobby_name)
	return _send_msg(Message.JOIN, 0, lobby_name)

func seal_lobby() -> Error:
	return _send_msg(Message.SEAL, 0)

func send_candidate(id: int, mid: String, index: int, sdp: String) -> Error:
	return _send_msg(Message.CANDIDATE, id, "\n%s\n%d\n%s" % [mid, index, sdp])

func send_offer(id: int, offer: String) -> Error:
	return _send_msg(Message.OFFER, id, offer)

func send_answer(id: int, answer: String) -> Error:
	return _send_msg(Message.ANSWER, id, answer)

func _send_msg(type: int, id: int, data: String = "") -> Error:
	var msg = JSON.stringify({
		"type": type,
		"id": id,
		"data": data,
	})
	print("📤 Mensaje enviado: ", msg)  # ← Esta línea
	return ws.send_text(msg)
