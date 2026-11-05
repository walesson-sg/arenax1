extends Node3D

@onready var player_1: Fighter = $Fighter1
@onready var player_2: Fighter = $Fighter2
@onready var arena_camera: ArenaCamera = $ArenaCamera
@onready var hud: CanvasLayer = $HUD
@onready var class_selection: CanvasLayer = $ClassSelection
@onready var dead_zone: Area3D = $DeadZone
@onready var chessboard_root: Node3D = $Floor/Chessboard

var game_finished: bool = false
var match_started: bool = false
var local_fighter: Fighter = null
var opponent_fighter: Fighter = null

func _ready() -> void:
	# Garantir velocidade normal ao iniciar/reiniciar
	Engine.time_scale = 1.0
	game_finished = false
	match_started = false

	# Montar o piso estilizado em xadrez
	_build_chessboard_floor()

	# Configurar controle e autoridade dos lutadores
	if NetworkManager and NetworkManager.is_online:
		if NetworkManager.is_host:
			player_1.is_player = true
			player_1.is_bot = false
			player_2.is_player = false
			player_2.is_bot = false
			local_fighter = player_1
			opponent_fighter = player_2
		else:
			player_1.is_player = false
			player_1.is_bot = false
			player_2.is_player = true
			player_2.is_bot = false
			local_fighter = player_2
			opponent_fighter = player_1

		# Aplicar classes decididas no Lobby
		player_1.setup_class(NetworkManager.local_class if NetworkManager.is_host else NetworkManager.remote_class)
		player_2.setup_class(NetworkManager.remote_class if NetworkManager.is_host else NetworkManager.local_class)

		if class_selection:
			class_selection.visible = false
	else:
		# Modo Offline / Bot
		player_1.is_player = true
		player_1.is_bot = false
		player_2.is_player = false
		player_2.is_bot = true
		local_fighter = player_1
		opponent_fighter = player_2

	# Configurar alvos mútuos
	if player_1 and player_2:
		player_1.target = player_2
		player_2.target = player_1
		
		# Conectar sinais de morte
		player_1.died.connect(_on_fighter_died)
		player_2.died.connect(_on_fighter_died)

	# Configurar Câmera focada no lutador do jogador local
	if arena_camera and local_fighter and opponent_fighter:
		arena_camera.target_1 = local_fighter
		arena_camera.target_2 = opponent_fighter

	# Conectar HUD
	if hud and hud.has_method("setup") and local_fighter and opponent_fighter:
		hud.setup(local_fighter, opponent_fighter)
		if hud.has_signal("restart_clicked"):
			hud.restart_clicked.connect(_restart_match)
		if hud.has_signal("menu_clicked"):
			hud.menu_clicked.connect(_go_to_main_menu)

	# Conectar Deadline / Deadzone de queda
	if dead_zone:
		dead_zone.body_entered.connect(_on_dead_zone_body_entered)

	# No modo online, o jogo começa direto pois as classes já foram escolhidas
	if NetworkManager and NetworkManager.is_online:
		if hud and hud.has_method("setup_class_hud"):
			hud.setup_class_hud(NetworkManager.local_class)
		_start_match()
	else:
		# Pausar ações dos combatentes e HUD até o jogador escolher a classe
		if player_1:
			player_1.is_active = false
		if player_2:
			player_2.is_active = false

		if hud and hud.has_method("set_match_active"):
			hud.set_match_active(false)

		# Conectar tela de seleção de classe
		if class_selection and class_selection.has_signal("class_selected"):
			class_selection.class_selected.connect(_on_class_selected)
		else:
			_start_match()

func _on_class_selected(class_id: String) -> void:
	if player_1:
		player_1.setup_class(class_id)
	if hud and hud.has_method("setup_class_hud"):
		hud.setup_class_hud(class_id)
	_start_match()

func _start_match() -> void:
	if match_started:
		return
	match_started = true

	if player_1:
		player_1.is_active = true
	if player_2:
		player_2.is_active = true

	if hud and hud.has_method("set_match_active"):
		hud.set_match_active(true)

func _build_chessboard_floor() -> void:
	if not chessboard_root:
		return

	var grid_size: int = 20
	var board_size: float = 100.0
	var tile_size: float = board_size / grid_size # 5 metros por ladrilho (20x20 = 100m x 100m)
	var half_board: float = board_size * 0.5

	# Material dos ladrilhos escuros (Obsidiana / ardósia escura com brilho suave)
	var mat_dark: StandardMaterial3D = StandardMaterial3D.new()
	mat_dark.albedo_color = Color(0.12, 0.13, 0.17, 1.0)
	mat_dark.roughness = 0.25

	# Material dos ladrilhos claros (Mármore marfim estilizado)
	var mat_light: StandardMaterial3D = StandardMaterial3D.new()
	mat_light.albedo_color = Color(0.82, 0.84, 0.88, 1.0)
	mat_light.roughness = 0.2

	var tile_mesh: BoxMesh = BoxMesh.new()
	tile_mesh.size = Vector3(tile_size * 0.98, 0.8, tile_size * 0.98) # Separação sutil entre peças

	for row in range(grid_size):
		for col in range(grid_size):
			var tile: MeshInstance3D = MeshInstance3D.new()
			tile.mesh = tile_mesh
			var is_dark: bool = (row + col) % 2 == 0
			tile.material_override = mat_dark if is_dark else mat_light

			var pos_x: float = -half_board + (col * tile_size) + (tile_size * 0.5)
			var pos_z: float = -half_board + (row * tile_size) + (tile_size * 0.5)
			tile.position = Vector3(pos_x, -0.4, pos_z)
			chessboard_root.add_child(tile)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R and not (NetworkManager and NetworkManager.is_online):
			_restart_match()

func _on_dead_zone_body_entered(body: Node3D) -> void:
	if body is Fighter and body.current_state != Fighter.State.DEAD:
		body.die("RING OUT")

func _on_fighter_died(loser: Fighter, reason: String) -> void:
	if game_finished:
		return
	game_finished = true

	var player_won: bool = (loser != local_fighter)

	# Efeito GTA V: Câmera lenta dramática sustentada
	Engine.time_scale = 0.22

	# Exibir HUD com resultado (WIN ou LOSER) e botão de reiniciar
	if hud and hud.has_method("show_match_result"):
		hud.show_match_result(player_won, reason)

func _restart_match() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	if NetworkManager and NetworkManager.is_online:
		get_tree().change_scene_to_file("res://scenes/lobby.tscn")
	else:
		get_tree().reload_current_scene()

func _go_to_main_menu() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	if NetworkManager:
		NetworkManager._cleanup_network()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
