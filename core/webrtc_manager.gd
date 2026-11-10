# core/webrtc_manager.gd
class_name WebRTCManager
extends Node

signal connected_to_signaling(id: int, use_mesh: bool)
signal disconnected_from_signaling()
signal peer_connected(id: int)
signal peer_disconnected(id: int)

var signaling_client: SignalingClient
var rtc_mp := WebRTCMultiplayerPeer.new()

func _init():
	signaling_client = SignalingClient.new()
	signaling_client.autojoin = false
	add_child(signaling_client)
	
	signaling_client.connected.connect(_on_signaling_connected)
	signaling_client.disconnected.connect(_on_signaling_disconnected)
	signaling_client.offer_received.connect(_on_offer_received)
	signaling_client.answer_received.connect(_on_answer_received)
	signaling_client.candidate_received.connect(_on_candidate_received)
	signaling_client.peer_connected.connect(_on_peer_connected)
	signaling_client.peer_disconnected.connect(_on_peer_disconnected)

func start_connection(url: String, room_secret: String = "") -> void:
	print("🔗 Conectando al servidor: ", url)
	print("🔑 Room secret a enviar: ", room_secret)  # ← Esta línea
	signaling_client.connect_to_url(url)
	while signaling_client.ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		await get_tree().process_frame
		if signaling_client.ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			print("❌ No se pudo conectar al servidor de señalización")
			return
	signaling_client.join_lobby(room_secret)

func _on_signaling_connected(id: int, use_mesh: bool):
	if use_mesh:
		rtc_mp.create_mesh(id)
	elif id == 1:
		rtc_mp.create_server()
	else:
		rtc_mp.create_client(id)
	multiplayer.multiplayer_peer = rtc_mp
	connected_to_signaling.emit(id, use_mesh)

func _on_signaling_disconnected():
	multiplayer.multiplayer_peer = null
	disconnected_from_signaling.emit()

func _on_peer_connected(id: int):
	_create_peer(id)
	peer_connected.emit(id)

func _on_peer_disconnected(id: int):
	if rtc_mp.has_peer(id):
		rtc_mp.remove_peer(id)
	peer_disconnected.emit(id)

func _create_peer(id: int):
	var peer = WebRTCPeerConnection.new()
	peer.initialize({
		"iceServers": [
			{
				"urls": [
					"stun:stun.l.google.com:19302",
					"stun:stun1.l.google.com:19302"
				]
			},
			{
				"urls": [
					"turn:global.turn.metered.ca:80?transport=udp",
					"turn:global.turn.metered.ca:443?transport=tcp",
					"turns:global.turn.metered.ca:443?transport=tcp"
				],
				"username": "68b6144f5b046c3cf5350e8d",
				"credential": "Hyxc2ec/pBUekQ5e"
			}
		]
	})
	peer.session_description_created.connect(_on_offer_created.bind(id))
	peer.ice_candidate_created.connect(_on_ice_candidate.bind(id))
	rtc_mp.add_peer(peer, id)
	if id < rtc_mp.get_unique_id():
		peer.create_offer()

func _on_offer_created(type: String, data: String, id: int):
	if not rtc_mp.has_peer(id):
		return
	rtc_mp.get_peer(id).connection.set_local_description(type, data)
	if type == "offer":
		signaling_client.send_offer(id, data)
	else:
		signaling_client.send_answer(id, data)

func _on_ice_candidate(mid: String, index: int, sdp: String, id: int):
	signaling_client.send_candidate(id, mid, index, sdp)

func _on_offer_received(id: int, offer: String):
	if rtc_mp.has_peer(id):
		rtc_mp.get_peer(id).connection.set_remote_description("offer", offer)

func _on_answer_received(id: int, answer: String):
	if rtc_mp.has_peer(id):
		rtc_mp.get_peer(id).connection.set_remote_description("answer", answer)

func _on_candidate_received(id: int, mid: String, index: int, sdp: String):
	if rtc_mp.has_peer(id):
		rtc_mp.get_peer(id).connection.add_ice_candidate(mid, index, sdp)

func stop():
	rtc_mp.close()
	signaling_client.close()
