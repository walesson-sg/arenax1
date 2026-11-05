class_name NetworkManagerClass
extends Node

## Gerenciador Central de Rede e Partidas do ArenaX1
## Suporta:
## 1. Modo Treino / Offline (vs Bot)
## 2. Duelo Privado (Host/Client com Código de Sala e Link de WhatsApp via WebRTC)
## 3. Partida Rápida (Matchmaking aleatório via Servidor de Sinalização)
## 4. Testes locais ENet (executar 2 instâncias no mesmo PC)
## 5. WebRTC P2P para Navegador (Web)

enum GameMode {
	OFFLINE_BOT,
	ONLINE_ROOM,
	ONLINE_MATCHMAKING
}

enum ConnectionStatus {
	IDLE,
	CONNECTING,
	SEARCHING_MATCH,
	IN_LOBBY,
	IN_GAME
}

# Sinais de gerenciamento de rede e sala
signal connection_status_changed(status: ConnectionStatus, message: String)
signal room_created(room_code: String)
signal room_joined(room_code: String)
signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal opponent_ready_changed(is_ready: bool)
signal opponent_class_changed(class_id: String)
signal match_start_requested()
signal match_error(message: String)

# Configuração do Servidor de Sinalização (Web / Nuvem)
@export var signaling_server_url: String = "wss://arenax1-server.onrender.com"
@export var use_webrtc_by_default: bool = true # Usa o servidor WebRTC da nuvem para conexão online global

# Estado Global
var game_mode: GameMode = GameMode.OFFLINE_BOT
var status: ConnectionStatus = ConnectionStatus.IDLE
var is_online: bool = false
var is_host: bool = true
var room_code: String = ""
var is_opponent_in_room: bool = false

# Identificação e Classes
var local_player_id: int = 1 # 1 para Host, 2 para Guest
var local_class: String = "fighter"
var remote_class: String = "fighter"
var local_ready: bool = false
var remote_ready: bool = false

# Peers e Conexões
const DEFAULT_PORT: int = 7777
var active_peer: MultiplayerPeer = null

# WebRTC & WebSocket
var ws_client: WebSocketPeer = null
var rtc_multiplayer: WebRTCMultiplayerPeer = null
var rtc_connection: WebRTCPeerConnection = null
var pending_action: String = "" # "create" ou "join" ou "matchmake"
var has_remote_description: bool = false
var pending_ice_candidates: Array = []

func _ready() -> void:
	# Conectar sinais padrão do MultiplayerAPI do Godot 4
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _process(_delta: float) -> void:
	_poll_websocket()
	if rtc_connection:
		rtc_connection.poll()

# ==============================================================================
# MODO OFFLINE / BOT
# ==============================================================================
func start_offline_bot_match(chosen_class: String = "fighter") -> void:
	_cleanup_network()
	game_mode = GameMode.OFFLINE_BOT
	is_online = false
	is_host = true
	is_opponent_in_room = false
	local_player_id = 1
	local_class = chosen_class
	remote_class = "fighter"
	status = ConnectionStatus.IN_GAME
	get_tree().change_scene_to_file("res://scenes/arena.tscn")

# ==============================================================================
# DUELO PRIVADO: CRIAÇÃO E ENTRADA EM SALAS
# ==============================================================================
func generate_room_code() -> String:
	var chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var code = ""
	for i in range(6):
		code += chars[randi() % chars.length()]
	return code

func create_room(custom_code: String = "") -> void:
	_cleanup_network()
	game_mode = GameMode.ONLINE_ROOM
	is_online = true
	is_host = true
	is_opponent_in_room = false
	local_player_id = 1
	room_code = custom_code if custom_code != "" else generate_room_code()
	local_ready = false
	remote_ready = false
	
	_set_status(ConnectionStatus.CONNECTING, "Criando sala de duelo...")

	# Se estiver na Web ou se o usuário ativou WebRTC, conecta no sinalizador
	if OS.has_feature("web") or use_webrtc_by_default:
		pending_action = "create"
		_connect_to_signaling_server()
	else:
		# No Desktop padrão: ENet local para testes rápidos no mesmo PC / LAN
		var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
		var err = peer.create_server(DEFAULT_PORT, 2)
		if err != OK:
			_set_status(ConnectionStatus.IDLE, "Falha ao criar servidor ENet local.")
			emit_signal("match_error", "Não foi possível abrir o servidor local na porta %d." % DEFAULT_PORT)
			return
		active_peer = peer
		multiplayer.multiplayer_peer = active_peer
		_set_status(ConnectionStatus.IN_LOBBY, "Sala criada: %s" % room_code)
		emit_signal("room_created", room_code)

func join_room(target_code: String, host_ip: String = "127.0.0.1") -> void:
	_cleanup_network()
	game_mode = GameMode.ONLINE_ROOM
	is_online = true
	is_host = false
	is_opponent_in_room = false
	local_player_id = 2
	room_code = target_code.strip_edges().to_upper()
	local_ready = false
	remote_ready = false

	_set_status(ConnectionStatus.CONNECTING, "Conectando à sala %s..." % room_code)

	if OS.has_feature("web") or use_webrtc_by_default:
		pending_action = "join"
		_connect_to_signaling_server()
	else:
		var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
		var err = peer.create_client(host_ip, DEFAULT_PORT)
		if err != OK:
			_set_status(ConnectionStatus.IDLE, "Falha ao conectar no IP %s." % host_ip)
			emit_signal("match_error", "Erro ao conectar com o oponente.")
			return
		active_peer = peer
		multiplayer.multiplayer_peer = active_peer
		emit_signal("room_joined", room_code)

# ==============================================================================
# PARTIDA RÁPIDA (MATCHMAKING)
# ==============================================================================
func start_matchmaking() -> void:
	_cleanup_network()
	game_mode = GameMode.ONLINE_MATCHMAKING
	is_online = true
	is_opponent_in_room = false
	_set_status(ConnectionStatus.SEARCHING_MATCH, "Conectando ao servidor de matchmaking...")
	pending_action = "matchmake"
	_connect_to_signaling_server()

func cancel_matchmaking() -> void:
	if ws_client and ws_client.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws_client.send_text(JSON.stringify({"type": "leave_queue"}))
	_cleanup_network()
	_set_status(ConnectionStatus.IDLE, "Busca cancelada.")

# ==============================================================================
# CLIENTE WEBSOCKET & SINALIZADOR WEBRTC
# ==============================================================================
func _connect_to_signaling_server() -> void:
	ws_client = WebSocketPeer.new()
	var err = ws_client.connect_to_url(signaling_server_url)
	if err != OK:
		log_error("Falha ao abrir conexão com o servidor de sinalização: %s" % signaling_server_url)
		_set_status(ConnectionStatus.IDLE, "Servidor de sinalização inacessível.")
		emit_signal("match_error", "Não foi possível conectar ao servidor de sinalização.")
		return

func _poll_websocket() -> void:
	if not ws_client:
		return
	ws_client.poll()
	var state = ws_client.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		# Processar ação pendente logo que a conexão abre
		if pending_action != "":
			var act = pending_action
			pending_action = ""
			if act == "create":
				ws_client.send_text(JSON.stringify({"type": "create_room", "code": room_code}))
			elif act == "join":
				ws_client.send_text(JSON.stringify({"type": "join_room", "code": room_code}))
			elif act == "matchmake":
				ws_client.send_text(JSON.stringify({"type": "join_queue"}))

		# Ler pacotes recebidos
		while ws_client.get_available_packet_count() > 0:
			var packet_str = ws_client.get_packet().get_string_from_utf8()
			var msg = JSON.parse_string(packet_str)
			if msg is Dictionary:
				_handle_signaling_message(msg)

	elif state == WebSocketPeer.STATE_CLOSED:
		var code = ws_client.get_close_code()
		var reason = ws_client.get_close_reason()
		log_info("WebSocket fechado: código %d, motivo: %s" % [code, reason])
		ws_client = null

func _handle_signaling_message(msg: Dictionary) -> void:
	var msg_type = msg.get("type", "")

	match msg_type:
		"room_created":
			_set_status(ConnectionStatus.IN_LOBBY, "Sala criada: %s" % room_code)
			emit_signal("room_created", room_code)
			_setup_webrtc_peer(true)

		"room_joined":
			_set_status(ConnectionStatus.IN_LOBBY, "Conectado à sala: %s" % room_code)
			is_opponent_in_room = true
			emit_signal("room_joined", room_code)
			_setup_webrtc_peer(false)
			# Notificar o lobby imediatamente da presença do Host
			emit_signal("player_connected", 1)
			# Sincronizar estado inicial com o Host
			_send_lobby_signal({
				"kind": "lobby_sync",
				"class": local_class,
				"ready": local_ready
			})

		"match_found":
			room_code = msg.get("code", "")
			is_host = msg.get("is_host", false)
			local_player_id = 1 if is_host else 2
			is_opponent_in_room = true
			_set_status(ConnectionStatus.IN_LOBBY, "Oponente encontrado! Sala: %s" % room_code)
			_setup_webrtc_peer(is_host)
			get_tree().change_scene_to_file("res://scenes/lobby.tscn")
			if is_host:
				_start_webrtc_offer(2)
			else:
				emit_signal("player_connected", 1)
				_send_lobby_signal({
					"kind": "lobby_sync",
					"class": local_class,
					"ready": local_ready
				})

		"peer_connected":
			var opp_peer_id = int(msg.get("peer_id", 2))
			is_opponent_in_room = true
			log_info("Oponente conectado via sinalizador (Peer %d)! Iniciando oferta WebRTC..." % opp_peer_id)
			emit_signal("player_connected", opp_peer_id)
			# Sincronizar estado com o Guest recém-chegado
			_send_lobby_signal({
				"kind": "lobby_sync",
				"class": local_class,
				"ready": local_ready
			})
			_start_webrtc_offer(opp_peer_id)

		"webrtc_signal":
			var signal_data = msg.get("data", {})
			_handle_webrtc_signal_data(signal_data)

		"peer_disconnected":
			is_opponent_in_room = false
			remote_ready = false
			var opp_id = int(msg.get("peer_id", 2))
			_on_peer_disconnected(opp_id)

		"error":
			var err_msg = msg.get("message", "Erro de conexão.")
			_set_status(ConnectionStatus.IDLE, err_msg)
			emit_signal("match_error", err_msg)

# ==============================================================================
# SINAIS DE LOBBY VIA WEBSOCKET (INSTANTÂNEO & RESILIENTE)
# ==============================================================================
func _send_lobby_signal(data: Dictionary) -> void:
	if ws_client and ws_client.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws_client.send_text(JSON.stringify({
			"type": "webrtc_signal",
			"data": data
		}))

# ==============================================================================
# RELAY DE JOGO VIA WEBSOCKET (FALLBACK QUANDO O P2P WEBRTC NÃO CONECTA)
# ==============================================================================
func has_p2p_peer() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0

func send_game_msg(node_name: String, method: String, args: Array) -> void:
	_send_lobby_signal({
		"kind": "game",
		"node": node_name,
		"method": method,
		"args": var_to_str(args)
	})

func _receive_game_msg(data: Dictionary) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var node: Node = scene.get_node_or_null(String(data.get("node", "")))
	if node == null:
		return
	var method: String = String(data.get("method", ""))
	# Somente métodos de rede permitidos
	if not method.begins_with("rpc_"):
		return
	var args = str_to_var(String(data.get("args", "[]")))
	if args is Array and node.has_method(method):
		node.callv(method, args)

# ==============================================================================
# HANDSHAKE WEBRTC (P2P NAVEGADOR A NAVEGADOR)
# ==============================================================================
func _setup_webrtc_peer(p_is_host: bool) -> void:
	has_remote_description = false
	pending_ice_candidates.clear()

	rtc_multiplayer = WebRTCMultiplayerPeer.new()

	if p_is_host:
		rtc_multiplayer.create_server()
	else:
		rtc_multiplayer.create_client(local_player_id)

	multiplayer.multiplayer_peer = rtc_multiplayer

	rtc_connection = WebRTCPeerConnection.new()
	rtc_connection.initialize({
		"iceServers": [
			{"urls": ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"]}
		]
	})

	rtc_connection.session_description_created.connect(_on_session_description_created)
	rtc_connection.ice_candidate_created.connect(_on_ice_candidate_created)

	var target_peer_id: int = 2 if p_is_host else 1
	rtc_multiplayer.add_peer(rtc_connection, target_peer_id)
	log_info("WebRTCMultiplayerPeer pronto. Host: %s, Peer alvo: %d" % [str(p_is_host), target_peer_id])

func _start_webrtc_offer(_target_peer_id: int) -> void:
	if rtc_connection:
		log_info("Criando oferta WebRTC (create_offer)...")
		rtc_connection.create_offer()

func _on_session_description_created(type: String, sdp: String) -> void:
	log_info("SDP criado localmente: tipo %s" % type)
	if rtc_connection:
		rtc_connection.set_local_description(type, sdp)
	if ws_client and ws_client.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws_client.send_text(JSON.stringify({
			"type": "webrtc_signal",
			"data": {
				"kind": "sdp",
				"type": type,
				"sdp": sdp
			}
		}))

func _on_ice_candidate_created(media: String, index: int, candidate_name: String) -> void:
	if ws_client and ws_client.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws_client.send_text(JSON.stringify({
			"type": "webrtc_signal",
			"data": {
				"kind": "ice",
				"media": media,
				"index": index,
				"name": candidate_name
			}
		}))

func _handle_webrtc_signal_data(data: Dictionary) -> void:
	var kind = data.get("kind", "")
	
	# Sinais de sincronização de Lobby via WebSocket
	if kind == "lobby_sync":
		is_opponent_in_room = true
		remote_class = data.get("class", remote_class)
		remote_ready = bool(data.get("ready", false))
		log_info("Sincronização de lobby recebida: Classe=%s, Pronto=%s" % [remote_class, str(remote_ready)])
		emit_signal("opponent_class_changed", remote_class)
		emit_signal("opponent_ready_changed", remote_ready)
		return
	elif kind == "lobby_class":
		remote_class = data.get("class", "fighter")
		log_info("Oponente escolheu classe: %s" % remote_class)
		emit_signal("opponent_class_changed", remote_class)
		return
	elif kind == "lobby_ready":
		remote_ready = bool(data.get("ready", false))
		log_info("Oponente mudou status de pronto para: %s" % str(remote_ready))
		emit_signal("opponent_ready_changed", remote_ready)
		return
	elif kind == "lobby_start":
		log_info("Sinal de início de partida recebido!")
		rpc_start_match()
		return

	elif kind == "game":
		_receive_game_msg(data)
		return

	# Sinais WebRTC P2P (SDP / ICE)
	if not rtc_connection:
		return

	if kind == "sdp":
		var sdp_type = data.get("type", "")
		var sdp = data.get("sdp", "")
		log_info("Recebido SDP remoto tipo: %s" % sdp_type)
		var err = rtc_connection.set_remote_description(sdp_type, sdp)
		if err != OK:
			log_error("Falha ao definir remote description: %d" % err)
		else:
			has_remote_description = true
			# Processar ICE candidates que chegaram antes do SDP
			for ice in pending_ice_candidates:
				rtc_connection.add_ice_candidate(ice.media, ice.index, ice.name)
			pending_ice_candidates.clear()

			# Se for uma oferta (o Guest recebendo do Host), responde com create_answer()
			if sdp_type == "offer":
				log_info("Oferta SDP recebida. Gerando resposta (create_answer)...")
				rtc_connection.create_answer()

	elif kind == "ice":
		var media = data.get("media", "")
		var index = int(data.get("index", 0))
		var c_name = data.get("name", "")
		if has_remote_description:
			rtc_connection.add_ice_candidate(media, index, c_name)
		else:
			pending_ice_candidates.append({
				"media": media,
				"index": index,
				"name": c_name
			})

# ==============================================================================
# HELPERS DE LINK E WEB (WHATSAPP / COPIAR LINK)
# ==============================================================================
func get_url_room_code() -> String:
	if OS.has_feature("web"):
		var code = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('sala') || new URLSearchParams(window.location.search).get('room')")
		if code != null and str(code).strip_edges() != "":
			return str(code).strip_edges().to_upper()
	return ""

func get_invite_url() -> String:
	if room_code == "":
		return ""
	if OS.has_feature("web"):
		var base = JavaScriptBridge.eval("window.location.origin + window.location.pathname")
		return str(base) + "?sala=" + room_code
	return "https://arenax1.game/?sala=" + room_code

func copy_invite_link_to_clipboard() -> bool:
	var link: String = get_invite_url()
	if link == "":
		return false
	DisplayServer.clipboard_set(link)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("navigator.clipboard.writeText('" + link + "');")
	return true

# ==============================================================================
# SINCRONIZAÇÃO DE LOBBY (RPCS & WEBSOCKET)
# ==============================================================================
@rpc("any_peer", "call_remote", "reliable")
func rpc_set_opponent_class(class_id: String) -> void:
	remote_class = class_id
	emit_signal("opponent_class_changed", class_id)

@rpc("any_peer", "call_remote", "reliable")
func rpc_set_opponent_ready(is_ready: bool) -> void:
	remote_ready = is_ready
	emit_signal("opponent_ready_changed", is_ready)

func set_local_class(class_id: String) -> void:
	local_class = class_id
	_send_lobby_signal({"kind": "lobby_class", "class": class_id})
	if is_online and multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
		rpc("rpc_set_opponent_class", class_id)

func set_local_ready(is_ready: bool) -> void:
	local_ready = is_ready
	_send_lobby_signal({"kind": "lobby_ready", "ready": is_ready})
	if is_online and multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
		rpc("rpc_set_opponent_ready", is_ready)

func start_online_match() -> void:
	if is_host:
		log_info("Iniciando partida online...")
		_send_lobby_signal({"kind": "lobby_start"})
		if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
			rpc("rpc_start_match")
		rpc_start_match()

@rpc("any_peer", "call_local", "reliable")
func rpc_start_match() -> void:
	if status == ConnectionStatus.IN_GAME:
		return
	_set_status(ConnectionStatus.IN_GAME, "Partida iniciada!")
	emit_signal("match_start_requested")
	get_tree().change_scene_to_file("res://scenes/arena.tscn")

# ==============================================================================
# CALLBACKS DE MULTIPLAYER
# ==============================================================================
func _on_peer_connected(id: int) -> void:
	log_info("Peer multiplayer P2P conectado com sucesso! ID: %d" % id)
	is_opponent_in_room = true
	_set_status(ConnectionStatus.IN_LOBBY, "Oponente conectado (P2P Direto)!")
	emit_signal("player_connected", id)
	if multiplayer.has_multiplayer_peer():
		rpc("rpc_set_opponent_class", local_class)
		if local_ready:
			rpc("rpc_set_opponent_ready", local_ready)

func _on_peer_disconnected(id: int) -> void:
	log_info("Peer multiplayer desconectado: %d" % id)
	is_opponent_in_room = false
	remote_ready = false
	_set_status(ConnectionStatus.IN_LOBBY, "Oponente desconectou.")
	emit_signal("player_disconnected", id)
	emit_signal("opponent_ready_changed", false)

func _on_connected_to_server() -> void:
	log_info("Conectado ao host via P2P!")
	is_opponent_in_room = true
	_set_status(ConnectionStatus.IN_LOBBY, "Conectado à sala!")
	if multiplayer.has_multiplayer_peer():
		rpc("rpc_set_opponent_class", local_class)
		if local_ready:
			rpc("rpc_set_opponent_ready", local_ready)

func _on_connection_failed() -> void:
	log_error("Falha na conexão multiplayer.")
	_cleanup_network()
	_set_status(ConnectionStatus.IDLE, "Falha na conexão.")
	emit_signal("match_error", "Não foi possível conectar à sala.")

func _on_server_disconnected() -> void:
	log_info("Host encerrou a partida.")
	_cleanup_network()
	_set_status(ConnectionStatus.IDLE, "O host encerrou a partida.")
	emit_signal("match_error", "O host encerrou a sala.")

func _cleanup_network() -> void:
	if ws_client:
		ws_client.close()
		ws_client = null
	if rtc_connection:
		rtc_connection.close()
		rtc_connection = null
	if rtc_multiplayer:
		rtc_multiplayer.close()
		rtc_multiplayer = null
	if active_peer:
		active_peer.close()
		active_peer = null
	multiplayer.multiplayer_peer = null
	is_online = false
	is_opponent_in_room = false
	local_ready = false
	remote_ready = false
	has_remote_description = false
	pending_ice_candidates.clear()
	pending_action = ""

func _set_status(new_status: ConnectionStatus, message: String) -> void:
	status = new_status
	emit_signal("connection_status_changed", new_status, message)

func log_info(msg: String) -> void:
	print("[NetworkManager] ", msg)

func log_error(msg: String) -> void:
	printerr("[NetworkManager ERRO] ", msg)
