class_name MainMenu
extends Control

@onready var btn_quick_match: Button = $CenterContainer/MainCard/VBox/BtnQuickMatch
@onready var btn_create_room: Button = $CenterContainer/MainCard/VBox/BtnCreateRoom
@onready var btn_join_room: Button = $CenterContainer/MainCard/VBox/BtnJoinRoom
@onready var btn_bot_match: Button = $CenterContainer/MainCard/VBox/BtnBotMatch

# Modal de Entrar por Código
@onready var join_modal: PanelContainer = $JoinModal
@onready var code_input: LineEdit = $JoinModal/VBox/CodeInput
@onready var ip_input: LineEdit = $JoinModal/VBox/IpInput
@onready var btn_confirm_join: Button = $JoinModal/VBox/HBox/BtnConfirmJoin
@onready var btn_cancel_join: Button = $JoinModal/VBox/HBox/BtnCancelJoin

# Modal de Matchmaking (Partida Rápida)
@onready var match_modal: PanelContainer = $MatchModal
@onready var match_status_label: Label = $MatchModal/VBox/StatusLabel
@onready var match_timer_label: Label = $MatchModal/VBox/TimerLabel
@onready var btn_cancel_match: Button = $MatchModal/VBox/BtnCancelMatch
@onready var bot_fallback_container: VBoxContainer = $MatchModal/VBox/BotFallbackContainer
@onready var btn_accept_bot: Button = $MatchModal/VBox/BotFallbackContainer/BtnAcceptBot

var search_time: float = 0.0
var is_searching: bool = false

func _ready() -> void:
	if join_modal:
		join_modal.visible = false
	if match_modal:
		match_modal.visible = false
	if bot_fallback_container:
		bot_fallback_container.visible = false

	# Conectar botões principais
	if btn_quick_match:
		btn_quick_match.pressed.connect(_on_quick_match_pressed)
	if btn_create_room:
		btn_create_room.pressed.connect(_on_create_room_pressed)
	if btn_join_room:
		btn_join_room.pressed.connect(_on_join_room_pressed)
	if btn_bot_match:
		btn_bot_match.pressed.connect(_on_bot_match_pressed)

	# Conectar modal de entrada
	if btn_confirm_join:
		btn_confirm_join.pressed.connect(_on_confirm_join_pressed)
	if btn_cancel_join:
		btn_cancel_join.pressed.connect(func(): join_modal.visible = false)
	if code_input:
		code_input.text_submitted.connect(func(_text): _on_confirm_join_pressed())

	# Conectar modal de matchmaking
	if btn_cancel_match:
		btn_cancel_match.pressed.connect(_cancel_search)
	if btn_accept_bot:
		btn_accept_bot.pressed.connect(_start_bot_fallback)

	# Verificar se o jogador acessou via Link do WhatsApp (ex: ?sala=ABC123)
	var url_room: String = NetworkManager.get_url_room_code()
	if url_room != "":
		print("[MainMenu] Detectada sala via URL: ", url_room)
		_join_target_room(url_room)

func _process(delta: float) -> void:
	if is_searching:
		search_time += delta
		var sec: int = int(search_time)
		if match_timer_label:
			match_timer_label.text = "Tempo decorrido: %02d:%02d" % [sec / 60, sec % 60]
		
		# Fallback para Bot após 12 segundos de busca
		if search_time >= 12.0 and bot_fallback_container and not bot_fallback_container.visible:
			bot_fallback_container.visible = true

func _on_quick_match_pressed() -> void:
	is_searching = true
	search_time = 0.0
	if match_modal:
		match_modal.visible = true
	if bot_fallback_container:
		bot_fallback_container.visible = false
	if match_status_label:
		match_status_label.text = "Procurando oponente online..."
	NetworkManager.start_matchmaking()

func _cancel_search() -> void:
	is_searching = false
	if match_modal:
		match_modal.visible = false
	NetworkManager.cancel_matchmaking()

func _start_bot_fallback() -> void:
	_cancel_search()
	NetworkManager.start_offline_bot_match("fighter")

func _on_create_room_pressed() -> void:
	NetworkManager.create_room()
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

func _on_join_room_pressed() -> void:
	if join_modal:
		join_modal.visible = true
	if code_input:
		code_input.text = ""
		code_input.grab_focus()

func _on_confirm_join_pressed() -> void:
	if not code_input:
		return
	var code = code_input.text.strip_edges().to_upper()
	if code.length() < 3:
		return
	var host_ip: String = "127.0.0.1"
	if ip_input and ip_input.text.strip_edges() != "":
		host_ip = ip_input.text.strip_edges()
	_join_target_room(code, host_ip)

func _join_target_room(code: String, host_ip: String = "127.0.0.1") -> void:
	NetworkManager.join_room(code, host_ip)
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

func _on_bot_match_pressed() -> void:
	NetworkManager.start_offline_bot_match("fighter")

