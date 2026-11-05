class_name Lobby
extends Control

@onready var room_code_label: Label = $VBoxMain/TopBar/HBox/RoomCodeLabel
@onready var btn_copy_link: Button = $VBoxMain/TopBar/HBox/BtnCopyLink
@onready var link_copied_label: Label = $VBoxMain/TopBar/HBox/LinkCopiedLabel

# Painel Local (Você)
@onready var local_title: Label = $VBoxMain/PlayersContainer/LocalPlayerPanel/VBox/PlayerTitle
@onready var btn_choose_fighter: Button = $VBoxMain/PlayersContainer/LocalPlayerPanel/VBox/Classes/BtnFighter
@onready var btn_choose_gunslinger: Button = $VBoxMain/PlayersContainer/LocalPlayerPanel/VBox/Classes/BtnGunslinger
@onready var local_class_desc: Label = $VBoxMain/PlayersContainer/LocalPlayerPanel/VBox/ClassDesc
@onready var btn_toggle_ready: Button = $VBoxMain/PlayersContainer/LocalPlayerPanel/VBox/BtnReady

# Painel Remoto (Oponente)
@onready var remote_title: Label = $VBoxMain/PlayersContainer/RemotePlayerPanel/VBox/PlayerTitle
@onready var remote_status_label: Label = $VBoxMain/PlayersContainer/RemotePlayerPanel/VBox/StatusLabel
@onready var remote_class_label: Label = $VBoxMain/PlayersContainer/RemotePlayerPanel/VBox/ClassLabel
@onready var remote_ready_badge: Label = $VBoxMain/PlayersContainer/RemotePlayerPanel/VBox/ReadyBadge

# Rodapé
@onready var start_status_label: Label = $VBoxMain/BottomBar/StartStatusLabel
@onready var btn_leave: Button = $VBoxMain/BottomBar/BtnLeave

var is_local_ready: bool = false
var start_countdown: float = -1.0

func _ready() -> void:
	# Atualizar código da sala
	if room_code_label:
		room_code_label.text = "SALA: %s" % NetworkManager.room_code
	
	if link_copied_label:
		link_copied_label.visible = false

	# Conectar sinais do NetworkManager
	NetworkManager.opponent_class_changed.connect(_on_opponent_class_changed)
	NetworkManager.opponent_ready_changed.connect(_on_opponent_ready_changed)
	NetworkManager.player_connected.connect(_on_opponent_connected)
	NetworkManager.player_disconnected.connect(_on_opponent_disconnected)

	# Conectar botões locais
	if btn_copy_link:
		btn_copy_link.pressed.connect(_on_copy_link_pressed)
	if btn_choose_fighter:
		btn_choose_fighter.pressed.connect(func(): _select_class("fighter"))
	if btn_choose_gunslinger:
		btn_choose_gunslinger.pressed.connect(func(): _select_class("gunslinger"))
	if btn_toggle_ready:
		btn_toggle_ready.pressed.connect(_on_ready_pressed)
	if btn_leave:
		btn_leave.pressed.connect(_on_leave_pressed)

	# Atualizar títulos
	if local_title:
		local_title.text = "VOCÊ (%s)" % ("HOST" if NetworkManager.is_host else "CONVIDADO")
	if remote_title:
		remote_title.text = "OPONENTE (%s)" % ("CONVIDADO" if NetworkManager.is_host else "HOST")

	_select_class("fighter")
	_update_remote_ui()

func _process(delta: float) -> void:
	if start_countdown > 0.0:
		start_countdown -= delta
		var count: int = int(ceil(start_countdown))
		if start_status_label:
			start_status_label.text = "AMBOS PRONTOS! INICIANDO EM %d..." % count
		if start_countdown <= 0.0:
			start_countdown = -1.0
			if NetworkManager.is_host:
				NetworkManager.start_online_match()

func _on_copy_link_pressed() -> void:
	var success = NetworkManager.copy_invite_link_to_clipboard()
	if success and link_copied_label:
		link_copied_label.visible = true
		link_copied_label.text = "✓ Link copiado! Cole no WhatsApp para o seu amigo entrar direto!"
		var tween: Tween = create_tween()
		tween.tween_interval(3.0)
		tween.tween_property(link_copied_label, "modulate:a", 0.0, 0.4)
		tween.tween_callback(func():
			link_copied_label.visible = false
			link_copied_label.modulate.a = 1.0
		)

func _select_class(class_id: String) -> void:
	NetworkManager.set_local_class(class_id)
	if class_id == "gunslinger":
		if local_class_desc:
			local_class_desc.text = "PISTOLEIRO: Combate tático à média distância, pistolas duplas, armadilhas e tiro certeiro."
		if btn_choose_gunslinger:
			btn_choose_gunslinger.modulate = Color(1.2, 1.2, 1.2)
		if btn_choose_fighter:
			btn_choose_fighter.modulate = Color(0.7, 0.7, 0.7)
	else:
		if local_class_desc:
			local_class_desc.text = "LUTADOR: Combate corpo a corpo devastador, combos de socos rápidos, investida e onda de choque."
		if btn_choose_fighter:
			btn_choose_fighter.modulate = Color(1.2, 1.2, 1.2)
		if btn_choose_gunslinger:
			btn_choose_gunslinger.modulate = Color(0.7, 0.7, 0.7)

func _on_ready_pressed() -> void:
	is_local_ready = !is_local_ready
	NetworkManager.set_local_ready(is_local_ready)

	if btn_toggle_ready:
		if is_local_ready:
			btn_toggle_ready.text = "✓ VOCÊ ESTÁ PRONTO!"
			btn_toggle_ready.modulate = Color(0.4, 1.0, 0.4)
		else:
			btn_toggle_ready.text = "CLIQUE PARA FICAR PRONTO"
			btn_toggle_ready.modulate = Color.WHITE

	_check_start_condition()

func _on_opponent_class_changed(class_id: String) -> void:
	if remote_class_label:
		remote_class_label.text = "CLASSE: " + ("PISTOLEIRO" if class_id == "gunslinger" else "LUTADOR")

func _on_opponent_ready_changed(is_ready: bool) -> void:
	if remote_ready_badge:
		if is_ready:
			remote_ready_badge.text = "✓ PRONTO!"
			remote_ready_badge.modulate = Color(0.4, 1.0, 0.4)
		else:
			remote_ready_badge.text = "AGUARDANDO ESCOLHA..."
			remote_ready_badge.modulate = Color(0.8, 0.8, 0.8)
	_check_start_condition()

func _on_opponent_connected(_peer_id: int) -> void:
	_update_remote_ui()

func _on_opponent_disconnected(_peer_id: int) -> void:
	start_countdown = -1.0
	if start_status_label:
		start_status_label.text = "Oponente desconectou. Aguardando novo amigo..."
	_update_remote_ui()

func _update_remote_ui() -> void:
	var has_peer: bool = NetworkManager.is_opponent_in_room or (multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0)
	if remote_status_label:
		remote_status_label.text = "STATUS: CONECTADO" if has_peer else "STATUS: Aguardando amigo entrar..."
	if remote_class_label and has_peer:
		remote_class_label.text = "CLASSE: " + ("PISTOLEIRO" if NetworkManager.remote_class == "gunslinger" else "LUTADOR")
	if remote_ready_badge:
		remote_ready_badge.visible = has_peer
		if NetworkManager.remote_ready:
			remote_ready_badge.text = "✓ PRONTO!"
			remote_ready_badge.modulate = Color(0.4, 1.0, 0.4)
		else:
			remote_ready_badge.text = "AGUARDANDO ESCOLHA..."
			remote_ready_badge.modulate = Color(0.8, 0.8, 0.8)

func _check_start_condition() -> void:
	if is_local_ready and NetworkManager.remote_ready:
		if start_countdown <= 0.0:
			start_countdown = 3.0 # Contagem regressiva de 3 segundos
			if start_status_label:
				start_status_label.text = "AMBOS PRONTOS! INICIANDO EM 3..."
	else:
		start_countdown = -1.0
		if start_status_label:
			if is_local_ready:
				start_status_label.text = "Você está pronto! Aguardando o oponente..."
			elif NetworkManager.remote_ready:
				start_status_label.text = "Oponente está pronto! Clique em PRONTO para começar!"
			else:
				start_status_label.text = "Aguardando ambos confirmarem 'Pronto'..."

func _on_leave_pressed() -> void:
	NetworkManager._cleanup_network()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
