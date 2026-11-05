class_name Fighter
extends CharacterBody3D

const CharacterBuilder = preload("res://scripts/character_builder.gd")
const SkillFX = preload("res://scripts/skill_fx.gd")
const BulletScript = preload("res://scripts/bullet.gd")
const TrapScript = preload("res://scripts/trap.gd")

signal health_changed(new_health: float, max_health: float)
signal got_hit(damage: float)
signal died(fighter: Fighter, reason: String)
signal skill_used(skill_index: int, cooldown: float)

enum State { IDLE, MOVE, JUMP, ATTACK, DASH, HITSTUN, BLOCK, DEAD, SKILL, SLAM, SLIDE }

# Índices das habilidades (usados na barra de habilidades do HUD)
const SKILL_Q: int = 0
const SKILL_E: int = 1
const SKILL_F: int = 2

# Ações de Combate Sincronizadas em Rede
enum NetAction {
	COMBO_HIT,
	PISTOL_SHOT,
	GUNSLINGER_Q_SHOT,
	START_BLOCK,
	STOP_BLOCK,
	START_DASH,
	START_SLIDE,
	START_SLAM,
	USE_SKILL,
	LONG_JUMP,
	AIR_DASH_JUMP
}

@export var character_class: String = "fighter" # "fighter" ou "gunslinger"
@export var is_player: bool = true
@export var is_active: bool = true
@export var player_id: int = 1
@export var target: Fighter = null

@export_group("Stats")
@export var max_health: float = 100.0
@export var speed: float = 7.0
@export var jump_velocity: float = 6.5
@export var dash_distance: float = 9.52 # 5.52m anteriores + 4m extras pedidos pelo usuário
@export var dash_duration: float = 0.25 # velocidade ~38 m/s, ágil e responsivo
@export var post_dash_max_speed: float = 4.5 # Velocidade máxima horizontal permitida ao sair do Dash
@export var arena_half_size: float = 50.0 # Arena 100x100

@export_group("Appearance")
@export var skin_color: Color = Color(1.0, 0.84, 0.74)
@export var hair_color: Color = Color(0.98, 0.84, 0.48)
@export var outfit_color: Color = Color(0.98, 0.55, 0.15)
@export var boots_color: Color = Color(0.72, 0.38, 0.14)
@export var belt_color: Color = Color(0.45, 0.40, 0.35)
@export var eye_color: Color = Color(0.36, 0.34, 0.12)

@export_group("Skills")
# Q - Investida (+10m extras, total 16m)
@export var skill_q_distance: float = 16.0
@export var skill_q_duration: float = 0.38
@export var skill_q_damage_percent: float = 0.30
@export var skill_q_blocked_damage_percent: float = 0.15
@export var skill_q_cooldown: float = 5.0
# E - Onda circular / Explosão (+3m extras na área de efeito, raio total 5m)
@export var skill_e_radius: float = 5.0
@export var skill_e_damage_percent: float = 0.40
@export var skill_e_cooldown: float = 10.0
# F - Ultimate (raio)
@export var skill_f_charge_time: float = 2.0
@export var skill_f_radius: float = 1.0
@export var skill_f_length: float = 45.0
@export var skill_f_damage_percent: float = 0.40
@export var skill_f_cooldown: float = 20.0 # valor provisório, ajuste como preferir

# Combat Stats & Combo System
@export_group("Combo System")
@export var combo_hit_1_damage: float = 10.0
@export var combo_hit_2_damage: float = 12.0
@export var combo_hit_3_damage_percent: float = 0.20 # Mesmo dano percentual do slam (20% da vida máx)
@export var combo_lunge_distance: float = 1.0 # Pequeno avanço de 1m para os socos
@export var combo_lunge_duration: float = 0.12 # Duração da arrancada de 1m
@export var combo_window_duration: float = 0.55 # Janela de tolerância para encadear os cliques
@export var attack_duration: float = 0.26 # Duração de cada soco
@export var kick_duration: float = 0.38 # Duração do chute no chão

@export_group("Air Combat")
@export var max_air_dashes: int = 1
@export var slam_speed: float = 24.0
@export var slam_radius: float = 2.5 # Metade do raio da habilidade E (5.0m / 2)
@export var slam_damage_percent: float = 0.20 # Metade do dano da habilidade E (40% / 2)
@export var long_jump_speed: float = 37.0 # Velocidade inicial do Salto à Distância (2x a original)
@export var long_jump_height_mult: float = 1.0 # Proporção do arco vertical no Salto à Distância

@export_group("Slide & Air Mobility")
@export var slide_duration: float = 1.25 # Tempo total de duração do deslize no chão (dobrado para 2x distância)
@export var slide_speed: float = 24.0 # Velocidade inicial do deslize ao tocar no chão
@export var slide_window_duration: float = 0.55 # Janela de tempo após SHIFT+Space no ar para apertar Ctrl
@export var fast_fall_speed: float = 24.0 # Velocidade vertical descendente ao apertar Ctrl no ar

@export_group("AI")
@export var is_bot: bool = false

var ai_action_timer: float = 0.0
var ai_attack_cooldown: float = 0.0
var ai_block_timer: float = 0.0
var ai_strafe_dir: float = 1.0

var current_health: float = 100.0
var current_state: State = State.IDLE
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 18.0)

# Sincronização de Rede (Multiplayer)
var net_sync_timer: float = 0.0
var net_target_pos: Vector3 = Vector3.ZERO
var net_target_rot_y: float = 0.0
var net_target_velocity: Vector3 = Vector3.ZERO

var air_dashes_used: int = 0
var slam_landing: bool = false
var slam_land_timer: float = 0.0
var is_skill_e_slam: bool = false
var is_long_jumping: bool = false
var long_jump_trail_timer: float = 0.0
var dash_jump_buffer_timer: float = 0.0

# Variáveis da mecânica de Deslize (Slide) e Queda Rápida (Fast Fall)
var air_shift_space_window: float = 0.0
var air_dash_jump_buffer_timer: float = 0.0
var dash_slide_buffer_timer: float = 0.0
var is_slide_primed: bool = false
var is_fast_falling: bool = false
var slide_timer: float = 0.0
var slide_direction: Vector3 = Vector3.ZERO
var slide_trail_timer: float = 0.0
var ctrl_prev_pressed: bool = false

var dash_timer: float = 0.0
var dash_direction: Vector3 = Vector3.ZERO
var dash_trail_timer: float = 0.0
var attack_timer: float = 0.0
var hitstun_timer: float = 0.0
var is_blocking: bool = false
var block_fx: Node3D = null

# Estado do Combo de Ataques Básicos
var combo_step: int = 0 # 0 = neutro; 1 = hit 1 (soco direito); 2 = hit 2 (soco esquerdo); 3 = hit 3 (chute no chão)
var combo_reset_timer: float = 0.0
var combo_queued: bool = false
var combo_lunge_timer: float = 0.0
var combo_lunge_dir: Vector3 = Vector3.ZERO
var combo_lunge_speed: float = 0.0
var current_attack_damage: float = 10.0
var attack_tween: Tween = null
var attack_damage: float:
	get:
		return combo_hit_1_damage

# Estado das habilidades
var skill_cooldowns: Array[float] = [0.0, 0.0, 0.0]
var skill_timer: float = 0.0
var skill_dir: Vector3 = Vector3.ZERO
var skill_hit_ids: Array[int] = []
var skill_q_trail_timer: float = 0.0
var active_skill: int = -1
var ult_firing: bool = false # false = carregando, true = já disparou (recuperação)
var charge_fx: MeshInstance3D = null
var ult_aura: Node3D = null

# Procedural animation variables
@onready var visuals: Node3D = $Visuals
@onready var body_mesh: Node3D = $Visuals/Body
@onready var fist_r: Node3D = $Visuals/FistR
@onready var fist_l: Node3D = $Visuals/FistL
@onready var hitbox_area: Area3D = $Visuals/HitboxArea
@onready var hitbox_shape: CollisionShape3D = $Visuals/HitboxArea/CollisionShape3D

var original_fist_r_pos: Vector3
var original_fist_l_pos: Vector3
var punch_alt: bool = false

# Variáveis do Pistoleiro (Gunslinger) & Armadilhas
var pistol_fire_cooldown: float = 0.0
var long_rifle_node: Node3D = null
var root_timer: float = 0.0
var is_rooted: bool:
	get:
		return root_timer > 0.0

var is_focus_aiming: bool = false
var focus_aim_reticle: MeshInstance3D = null

var gunslinger_q_shot_timer: float = 0.0
var gunslinger_q_shots_fired: int = 0
var gunslinger_q_side: float = 1.0

var sniper_laser_line: MeshInstance3D = null
var sniper_reticle: MeshInstance3D = null

# Animação das pernas
var leg_l: Node3D = null
var leg_r: Node3D = null
var walk_phase: float = 0.0
var leg_swing: float = 0.0 # amplitude atual (suavizada)

func _ready() -> void:
	if not is_player and not (NetworkManager and NetworkManager.is_online):
		is_bot = true

	add_to_group("fighters")
	_ensure_input_mappings()

	if fist_r:
		original_fist_r_pos = fist_r.position
	if fist_l:
		original_fist_l_pos = fist_l.position

	setup_class(character_class)

	current_health = max_health
	emit_signal("health_changed", current_health, max_health)

	if hitbox_area:
		hitbox_area.monitoring = false
		hitbox_area.body_entered.connect(_on_hitbox_body_entered)

func setup_class(p_class: String) -> void:
	character_class = p_class

	# Limpar peças procedurais anteriores
	for child in visuals.get_children():
		if child != body_mesh and child != fist_r and child != fist_l and child != hitbox_area:
			child.queue_free()
	for child in body_mesh.get_children():
		child.queue_free()
	for child in fist_r.get_children():
		child.queue_free()
	for child in fist_l.get_children():
		child.queue_free()

	var pal: Dictionary = {
		"skin": skin_color,
		"hair": hair_color,
		"outfit": outfit_color if character_class != "gunslinger" else Color(0.36, 0.25, 0.18),
		"boots": boots_color if character_class != "gunslinger" else Color(0.24, 0.16, 0.12),
		"belt": belt_color if character_class != "gunslinger" else Color(0.32, 0.22, 0.14),
		"eyes": eye_color if character_class != "gunslinger" else Color(0.20, 0.55, 0.85),
	}

	var model: Dictionary = CharacterBuilder.build(visuals, body_mesh, fist_r, fist_l, pal, character_class)
	var built_legs: Array = model.get("legs", [])
	if built_legs.size() == 2:
		leg_l = built_legs[0]
		leg_r = built_legs[1]

	if character_class == "gunslinger":
		if long_rifle_node and is_instance_valid(long_rifle_node):
			long_rifle_node.queue_free()
		long_rifle_node = CharacterBuilder.build_long_rifle()
		visuals.add_child(long_rifle_node)
		long_rifle_node.visible = false
		long_rifle_node.position = Vector3(0.08, 1.14, 0.38)

func apply_root(duration: float) -> void:
	root_timer = maxf(root_timer, duration)
	velocity.x = 0.0
	velocity.z = 0.0
	if current_state == State.DASH:
		_end_dash()
	elif current_state == State.SLAM:
		_on_slam_impact()
	elif current_state == State.SLIDE:
		_end_slide()
	current_state = State.IDLE

func _is_slide_pressed() -> bool:
	return Input.is_action_pressed("slide") \
		or Input.is_key_pressed(KEY_CTRL) \
		or Input.is_physical_key_pressed(KEY_CTRL) \
		or Input.is_key_pressed(KEY_C) \
		or Input.is_physical_key_pressed(KEY_C)

func _is_slide_just_pressed() -> bool:
	var pressed: bool = _is_slide_pressed()
	return (pressed and not ctrl_prev_pressed) or Input.is_action_just_pressed("slide")

func _ensure_input_mappings() -> void:
	var key_mappings: Dictionary = {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"move_forward": [KEY_W, KEY_UP],
		"move_backward": [KEY_S, KEY_DOWN],
		"jump": [KEY_SPACE],
		"attack": [KEY_J],
		"dash": [KEY_SHIFT],
		"slide": [KEY_CTRL, KEY_C],
		"block": [KEY_K],
		"skill_q": [KEY_Q],
		"skill_e": [KEY_E],
		"skill_f": [KEY_F]
	}
	for action: String in key_mappings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key_code: Key in key_mappings[action]:
			var has_ev: bool = false
			for existing in InputMap.action_get_events(action):
				if existing is InputEventKey and (existing.physical_keycode == key_code or existing.keycode == key_code):
					has_ev = true
					break
			if not has_ev:
				var ev: InputEventKey = InputEventKey.new()
				ev.physical_keycode = key_code
				ev.keycode = key_code
				InputMap.action_add_event(action, ev)
		if action == "attack":
			var has_m: bool = false
			for existing in InputMap.action_get_events("attack"):
				if existing is InputEventMouseButton and existing.button_index == MOUSE_BUTTON_LEFT:
					has_m = true
					break
			if not has_m:
				var mouse_attack: InputEventMouseButton = InputEventMouseButton.new()
				mouse_attack.button_index = MOUSE_BUTTON_LEFT
				InputMap.action_add_event("attack", mouse_attack)
		elif action == "block":
			var has_m: bool = false
			for existing in InputMap.action_get_events("block"):
				if existing is InputEventMouseButton and existing.button_index == MOUSE_BUTTON_RIGHT:
					has_m = true
					break
			if not has_m:
				var mouse_block: InputEventMouseButton = InputEventMouseButton.new()
				mouse_block.button_index = MOUSE_BUTTON_RIGHT
				InputMap.action_add_event("block", mouse_block)

func _physics_process(delta: float) -> void:
	if not is_active:
		if not is_on_floor():
			velocity.y -= gravity * delta
		else:
			velocity.x = 0.0
			velocity.z = 0.0
		move_and_slide()
		_update_visuals(delta)
		return

	# Temporizador de imobilização (Root da Armadilha)
	if root_timer > 0.0:
		root_timer = maxf(root_timer - delta, 0.0)
		velocity.x = 0.0
		velocity.z = 0.0

	# Temporizador do tiro da pistola (Gunslinger)
	if pistol_fire_cooldown > 0.0:
		pistol_fire_cooldown = maxf(pistol_fire_cooldown - delta, 0.0)

	# Ataque padrão do Pistoleiro: pode atirar enquanto anda e enquanto esquiva (4 tiros por segundo)
	if character_class == "gunslinger" and is_player:
		if Input.is_action_pressed("attack"):
			if current_state != State.DEAD and current_state != State.HITSTUN and current_state != State.SKILL:
				if pistol_fire_cooldown <= 0.0:
					pistol_fire_cooldown = 0.25 # 4 tiros por segundo
					_fire_pistol_shot()

	# Gerenciamento de contato com o chão / ar
	if is_on_floor():
		air_dashes_used = 0
		air_shift_space_window = 0.0
		if is_slide_primed:
			is_slide_primed = false
			is_fast_falling = false
			_start_slide()
		elif is_long_jumping:
			is_long_jumping = false
			visuals.rotation.x = 0.0
			SkillFX.dash_brake(get_parent(), global_position, dash_direction)
			var horiz_land: Vector2 = Vector2(velocity.x, velocity.z)
			if horiz_land.length() > speed:
				horiz_land = horiz_land.normalized() * speed
				velocity.x = horiz_land.x
				velocity.z = horiz_land.y
	elif current_state == State.IDLE or current_state == State.MOVE:
		current_state = State.JUMP

	# Gravidade (suspensa durante o Dash, Investida Q e gerenciada no Golpe de Queda / Slam)
	if not is_on_floor() and current_state != State.DASH and current_state != State.SLAM and not (current_state == State.SKILL and active_skill == SKILL_Q):
		var grav_mult: float = 2.6 if is_fast_falling else 1.0
		velocity.y -= gravity * grav_mult * delta

	# Processar temporizadores de estados
	_process_state_timers(delta)

	# Atualizar movimento baseado no estado
	match current_state:
		State.IDLE, State.MOVE:
			if is_player:
				_handle_movement(delta)
				_handle_combat_inputs()
			elif is_bot:
				_handle_bot_ai(delta)
		State.JUMP:
			if is_player:
				_handle_air_movement(delta)
				_handle_combat_inputs()
			elif is_bot:
				_handle_bot_ai(delta)
		State.DASH:
			if is_rooted:
				_end_dash()
			elif is_player and is_on_floor() and _is_slide_just_pressed():
				_start_slide()
			elif is_player and not is_on_floor() and _is_slide_just_pressed():
				_trigger_fast_fall_slide_prime()
			elif is_player and is_on_floor() and Input.is_action_just_pressed("jump"):
				_start_long_jump()
			elif is_bot and is_on_floor() and target and (target.global_position - global_position).length() > 8.0 and randf() < 0.15:
				_start_long_jump()
			elif is_player and not is_on_floor() and Input.is_action_just_pressed("jump"):
				_start_air_dash_jump()
			else:
				var dash_speed: float = dash_distance / dash_duration
				velocity.x = dash_direction.x * dash_speed
				velocity.z = dash_direction.z * dash_speed
				velocity.y = 0.0
				if character_class == "gunslinger" and is_player:
					if Input.is_action_pressed("block"):
						is_focus_aiming = true
						if target and is_instance_valid(target) and target.current_state != State.DEAD:
							_face_target()
						_update_focus_aim_fx()
					elif is_focus_aiming:
						is_focus_aiming = false
						_clear_focus_aim_fx()
		State.SLIDE:
			if is_rooted:
				_end_slide()
			elif is_player and Input.is_action_just_pressed("dash") and not is_rooted:
				# Cancelamento fluido: executa um Dash explosivo (Shift) no meio do Slide!
				var input_dir_dash: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
				var cam_dash: Camera3D = get_viewport().get_camera_3d()
				var next_dash_dir: Vector3 = Vector3.ZERO
				if input_dir_dash.length() > 0.2:
					if cam_dash:
						var cam_fwd_d: Vector3 = -cam_dash.global_transform.basis.z
						var cam_rt_d: Vector3 = cam_dash.global_transform.basis.x
						cam_fwd_d.y = 0.0
						cam_rt_d.y = 0.0
						next_dash_dir = (cam_rt_d.normalized() * input_dir_dash.x + cam_fwd_d.normalized() * -input_dir_dash.y).normalized()
					else:
						next_dash_dir = Vector3(input_dir_dash.x, 0.0, input_dir_dash.y).normalized()
				else:
					next_dash_dir = slide_direction
				_end_slide()
				_start_dash(next_dash_dir)
			elif is_player and Input.is_action_just_pressed("jump"):
				# Slide Jump: cancela em salto ágil mantendo a propulsão horizontal
				_end_slide()
				velocity.y = jump_velocity * 1.05
				current_state = State.JUMP
				is_long_jumping = true
				SkillFX.burst(get_parent(), global_position + Vector3(0, 0.1, 0), outfit_color, 12, 4.5, 0.25, 0.1, true)
			elif not is_on_floor() and slide_timer < slide_duration - 0.1:
				_end_slide()
				current_state = State.JUMP
			else:
				if is_player:
					var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
					if input_dir.length() > 0.2:
						var cam: Camera3D = get_viewport().get_camera_3d()
						var steer_dir: Vector3 = Vector3.ZERO
						if cam:
							var cam_fwd: Vector3 = -cam.global_transform.basis.z
							var cam_rt: Vector3 = cam.global_transform.basis.x
							cam_fwd.y = 0.0
							cam_rt.y = 0.0
							steer_dir = (cam_rt.normalized() * input_dir.x + cam_fwd.normalized() * -input_dir.y).normalized()
						else:
							steer_dir = Vector3(input_dir.x, 0.0, input_dir.y).normalized()
						slide_direction = slide_direction.lerp(steer_dir, 7.5 * delta).normalized()
						visuals.rotation.y = atan2(slide_direction.x, slide_direction.z)

					# Permite ações de combate (ataques, habilidades, defesa) durante o slide
					_handle_combat_inputs()
					if current_state != State.SLIDE:
						return

				# Desaceleração contínua e suave até a velocidade normal de corrida
				var cur_horiz: Vector2 = Vector2(velocity.x, velocity.z)
				var cur_spd: float = cur_horiz.length()
				var target_spd: float = speed
				var decel_amount: float = ((slide_speed - target_spd) / slide_duration) * delta
				var new_spd: float = move_toward(cur_spd, target_spd, decel_amount)
				velocity.x = slide_direction.x * new_spd
				velocity.z = slide_direction.z * new_spd
				velocity.y = -4.0 # Mantém o snap firme no solo durante o deslize

				if character_class == "gunslinger" and is_player:
					if Input.is_action_pressed("block"):
						is_focus_aiming = true
						if target and is_instance_valid(target) and target.current_state != State.DEAD:
							_face_target()
						_update_focus_aim_fx()
					elif is_focus_aiming:
						is_focus_aiming = false
						_clear_focus_aim_fx()
		State.SLAM:
			if not slam_landing:
				velocity.x = move_toward(velocity.x, 0.0, speed * 2.0 * delta)
				velocity.z = move_toward(velocity.z, 0.0, speed * 2.0 * delta)
				var current_fall_speed: float = slam_speed * 1.15 if is_skill_e_slam else slam_speed
				velocity.y = -current_fall_speed
				if is_on_floor():
					_on_slam_impact()
			else:
				velocity = Vector3.ZERO
		State.SKILL:
			_process_active_skill()
		State.ATTACK:
			if combo_lunge_timer > 0.0:
				combo_lunge_timer -= delta
				velocity.x = combo_lunge_dir.x * combo_lunge_speed
				velocity.z = combo_lunge_dir.z * combo_lunge_speed
			else:
				velocity.x = move_toward(velocity.x, 0.0, speed * 6.0 * delta)
				velocity.z = move_toward(velocity.z, 0.0, speed * 6.0 * delta)
			# Bot: chance de encadear o combo se o alvo ainda estiver próximo
			if is_bot and target and is_instance_valid(target) and combo_step < 3 and not combo_queued:
				var to_tgt_b: Vector3 = target.global_position - global_position
				to_tgt_b.y = 0.0
				if to_tgt_b.length() < 2.6 and randf() < 0.08:
					combo_queued = true
		State.HITSTUN:
			velocity.x = move_toward(velocity.x, 0.0, speed * 1.5 * delta)
			velocity.z = move_toward(velocity.z, 0.0, speed * 1.5 * delta)
		State.BLOCK:
			velocity.x = move_toward(velocity.x, 0.0, speed * 3.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, speed * 3.0 * delta)
			if is_player:
				_handle_combat_inputs()
			elif is_bot:
				_handle_bot_ai(delta)
		State.DEAD:
			velocity.x = move_toward(velocity.x, 0.0, speed * 2.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, speed * 2.0 * delta)

	# Se estiver imobilizado pela armadilha, zera velocidade horizontal
	if is_rooted:
		velocity.x = 0.0
		velocity.z = 0.0

	# Se cair abaixo da arena (deadline), morre por Ring Out
	if global_position.y < -12.0 and current_state != State.DEAD:
		die("RING OUT")

	move_and_slide()
	_update_visuals(delta)
	ctrl_prev_pressed = _is_slide_pressed()

	# Sincronização de Rede (Multiplayer)
	if is_player and NetworkManager and NetworkManager.is_online:
		net_sync_timer -= delta
		if net_sync_timer <= 0.0:
			net_sync_timer = 0.05 # ~20 updates por segundo
			_net_call("rpc_sync_transform", [global_position, visuals.rotation.y, velocity, int(current_state)])
	elif not is_player and not is_bot:
		# Interpolação suave do oponente remoto
		if net_target_pos != Vector3.ZERO:
			global_position = global_position.lerp(net_target_pos, clampf(22.0 * delta, 0.0, 1.0))
			visuals.rotation.y = lerp_angle(visuals.rotation.y, net_target_rot_y, clampf(22.0 * delta, 0.0, 1.0))

func _process_state_timers(delta: float) -> void:
	# Recarga das habilidades
	for i in range(skill_cooldowns.size()):
		if skill_cooldowns[i] > 0.0:
			skill_cooldowns[i] = maxf(skill_cooldowns[i] - delta, 0.0)

	# Temporizador da janela do combo de ataques básicos
	if combo_reset_timer > 0.0:
		combo_reset_timer -= delta
		if combo_reset_timer <= 0.0:
			combo_step = 0
			combo_queued = false

	if dash_jump_buffer_timer > 0.0:
		dash_jump_buffer_timer -= delta

	if dash_slide_buffer_timer > 0.0:
		dash_slide_buffer_timer -= delta

	if air_shift_space_window > 0.0:
		air_shift_space_window = maxf(air_shift_space_window - delta, 0.0)

	if air_dash_jump_buffer_timer > 0.0:
		air_dash_jump_buffer_timer = maxf(air_dash_jump_buffer_timer - delta, 0.0)

	if is_long_jumping:
		long_jump_trail_timer -= delta
		if long_jump_trail_timer <= 0.0:
			long_jump_trail_timer = 0.035
			var trail_color: Color = outfit_color.lerp(Color.WHITE, 0.4)
			SkillFX.dash_trail_step(get_parent(), global_position, visuals.rotation.y, trail_color, dash_direction)

	if current_state == State.SKILL:
		skill_timer -= delta
		if skill_timer <= 0.0:
			if active_skill == SKILL_F and not ult_firing:
				if character_class == "gunslinger":
					_fire_gunslinger_f()
				else:
					_fire_ultimate()
			else:
				_end_skill()

	elif current_state == State.DASH:
		dash_timer -= delta
		dash_trail_timer -= delta
		if dash_trail_timer <= 0.0:
			dash_trail_timer = 0.038 # gera rastro a cada ~38ms ao longo do trajeto de 9.5m
			var trail_color: Color = outfit_color.lerp(Color.WHITE, 0.35)
			SkillFX.dash_trail_step(get_parent(), global_position, visuals.rotation.y, trail_color, dash_direction)
		if dash_timer <= 0.0:
			_end_dash()

	elif current_state == State.SLIDE:
		slide_timer -= delta
		slide_trail_timer -= delta
		if slide_trail_timer <= 0.0:
			slide_trail_timer = 0.035
			var trail_color: Color = outfit_color.lerp(Color.WHITE, 0.3)
			SkillFX.slide_trail_step(get_parent(), global_position, slide_direction, trail_color)
		if slide_timer <= 0.0:
			_end_slide()

	elif current_state == State.SLAM:
		if slam_landing:
			slam_land_timer -= delta
			if slam_land_timer <= 0.0:
				slam_landing = false
				_change_state(State.IDLE if is_on_floor() else State.JUMP)
			
	elif current_state == State.ATTACK:
		attack_timer -= delta
		if attack_timer <= 0.0:
			_end_attack()
			if combo_queued and combo_step < 3:
				combo_queued = false
				_start_combo_attack()
			else:
				if combo_step >= 3:
					combo_step = 0
				_change_state(State.IDLE)
			
	elif current_state == State.HITSTUN:
		hitstun_timer -= delta
		if hitstun_timer <= 0.0:
			_change_state(State.IDLE)

func _handle_movement(delta: float) -> void:
	if not is_player:
		return

	if is_rooted:
		velocity.x = 0.0
		velocity.z = 0.0
		if is_on_floor():
			current_state = State.IDLE
		return

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var cam: Camera3D = get_viewport().get_camera_3d()
	var move_vec: Vector3 = Vector3.ZERO

	if cam:
		# Movimento relativo à câmera da arena
		var cam_forward: Vector3 = -cam.global_transform.basis.z
		var cam_right: Vector3 = cam.global_transform.basis.x
		cam_forward.y = 0.0
		cam_right.y = 0.0
		cam_forward = cam_forward.normalized()
		cam_right = cam_right.normalized()
		move_vec = (cam_right * input_dir.x + cam_forward * -input_dir.y).normalized()
	else:
		move_vec = Vector3(input_dir.x, 0.0, input_dir.y).normalized()

	if move_vec.length() > 0.1:
		velocity.x = move_vec.x * speed
		velocity.z = move_vec.z * speed
		
		# Rotação suave em direção ao movimento (ou foco contínuo no alvo se mira focada ativa)
		if character_class == "gunslinger" and is_focus_aiming and target and is_instance_valid(target) and target.current_state != State.DEAD:
			var to_tgt: Vector3 = target.global_position - global_position
			to_tgt.y = 0.0
			if to_tgt.length() > 0.1:
				var target_angle: float = atan2(to_tgt.x, to_tgt.z)
				visuals.rotation.y = lerp_angle(visuals.rotation.y, target_angle, 20.0 * delta)
		else:
			var local_move: Vector3 = to_local(global_position + move_vec)
			local_move.y = 0.0
			var target_angle: float = atan2(local_move.x, local_move.z)
			visuals.rotation.y = lerp_angle(visuals.rotation.y, target_angle, 14.0 * delta)
		
		if is_on_floor() and current_state != State.DASH:
			current_state = State.MOVE
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed * 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, speed * 8.0 * delta)
		if character_class == "gunslinger" and is_focus_aiming and target and is_instance_valid(target) and target.current_state != State.DEAD:
			var to_tgt: Vector3 = target.global_position - global_position
			to_tgt.y = 0.0
			if to_tgt.length() > 0.1:
				var target_angle: float = atan2(to_tgt.x, to_tgt.z)
				visuals.rotation.y = lerp_angle(visuals.rotation.y, target_angle, 20.0 * delta)
		if is_on_floor():
			current_state = State.IDLE

	# Slide no chão: logo após a Esquiva do Shift OU se estiver se movendo
	if _is_slide_just_pressed() and is_on_floor() and not is_rooted:
		if dash_slide_buffer_timer > 0.0 or move_vec.length() > 0.3:
			dash_slide_buffer_timer = 0.0
			_start_slide()
			return

	# Pulo (Pulo normal ou Salto à Distância se usado logo após o Dash no solo)
	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_rooted:
		if dash_jump_buffer_timer > 0.0:
			dash_jump_buffer_timer = 0.0
			_start_long_jump()
		else:
			velocity.y = jump_velocity
			current_state = State.JUMP

	# Dash / Esquiva (chão ou ar)
	if Input.is_action_just_pressed("dash") and not is_rooted:
		if is_on_floor():
			_start_dash(move_vec)
		elif air_dashes_used < max_air_dashes:
			air_dashes_used += 1
			_start_dash(move_vec)

func _handle_air_movement(delta: float) -> void:
	if is_on_floor():
		current_state = State.IDLE
		return
		
	if not is_player:
		return

	if is_rooted:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var cam: Camera3D = get_viewport().get_camera_3d()
	var move_vec: Vector3 = Vector3.ZERO
	if cam:
		var cam_forward: Vector3 = -cam.global_transform.basis.z
		var cam_right: Vector3 = cam.global_transform.basis.x
		cam_forward.y = 0.0
		cam_right.y = 0.0
		move_vec = (cam_right.normalized() * input_dir.x + cam_forward.normalized() * -input_dir.y).normalized()
	else:
		move_vec = Vector3(input_dir.x, 0.0, input_dir.y).normalized()

	if is_long_jumping:
		# Durante o Salto à Distância: mantém a propulsão horizontal desacelerando de forma contínua e fluida
		var horiz: Vector2 = Vector2(velocity.x, velocity.z)
		var current_h_speed: float = horiz.length()
		if current_h_speed > speed:
			var new_h_speed: float = move_toward(current_h_speed, speed, speed * 2.2 * delta)
			horiz = horiz.normalized() * new_h_speed
			# Leve controle aéreo de trajetória
			if move_vec.length() > 0.1:
				horiz = horiz.lerp(Vector2(move_vec.x, move_vec.z) * new_h_speed, 2.0 * delta)
				if character_class == "gunslinger" and is_focus_aiming and target and is_instance_valid(target) and target.current_state != State.DEAD:
					var to_tgt: Vector3 = target.global_position - global_position
					to_tgt.y = 0.0
					if to_tgt.length() > 0.1:
						var target_angle: float = atan2(to_tgt.x, to_tgt.z)
						visuals.rotation.y = lerp_angle(visuals.rotation.y, target_angle, 20.0 * delta)
				else:
					var local_move: Vector3 = to_local(global_position + move_vec)
					local_move.y = 0.0
					var target_angle: float = atan2(local_move.x, local_move.z)
					visuals.rotation.y = lerp_angle(visuals.rotation.y, target_angle, 8.0 * delta)
			velocity.x = horiz.x
			velocity.z = horiz.y
		else:
			is_long_jumping = false
	else:
		if move_vec.length() > 0.1:
			velocity.x = move_toward(velocity.x, move_vec.x * speed, speed * 5.0 * delta)
			velocity.z = move_toward(velocity.z, move_vec.z * speed, speed * 5.0 * delta)

			if character_class == "gunslinger" and is_focus_aiming and target and is_instance_valid(target) and target.current_state != State.DEAD:
				var to_tgt: Vector3 = target.global_position - global_position
				to_tgt.y = 0.0
				if to_tgt.length() > 0.1:
					var target_angle: float = atan2(to_tgt.x, to_tgt.z)
					visuals.rotation.y = lerp_angle(visuals.rotation.y, target_angle, 20.0 * delta)
			else:
				var local_move: Vector3 = to_local(global_position + move_vec)
				local_move.y = 0.0
				var target_angle: float = atan2(local_move.x, local_move.z)
				visuals.rotation.y = lerp_angle(visuals.rotation.y, target_angle, 10.0 * delta)
		else:
			# Sem direcional no ar: desacelera a velocidade residual horizontal
			velocity.x = move_toward(velocity.x, 0.0, speed * 4.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, speed * 4.0 * delta)
			if character_class == "gunslinger" and is_focus_aiming and target and is_instance_valid(target) and target.current_state != State.DEAD:
				var to_tgt: Vector3 = target.global_position - global_position
				to_tgt.y = 0.0
				if to_tgt.length() > 0.1:
					var target_angle: float = atan2(to_tgt.x, to_tgt.z)
					visuals.rotation.y = lerp_angle(visuals.rotation.y, target_angle, 20.0 * delta)

	# Qualquer momento no ar: ao apertar Ctrl, cai mais rápido para poder deslizar!
	if _is_slide_just_pressed():
		_trigger_fast_fall_slide_prime()

	# Dash aéreo e combinação SHIFT + Space no ar
	var dash_pressed: bool = Input.is_action_just_pressed("dash")
	var jump_pressed: bool = Input.is_action_just_pressed("jump")

	if jump_pressed and air_dash_jump_buffer_timer > 0.0:
		air_dash_jump_buffer_timer = 0.0
		_start_air_dash_jump(move_vec)
	elif dash_pressed and air_dashes_used < max_air_dashes:
		if jump_pressed or Input.is_action_pressed("jump"):
			# SHIFT + Space juntos no ar!
			is_long_jumping = false
			air_dashes_used += 1
			_start_air_dash_jump(move_vec)
		else:
			is_long_jumping = false
			air_dashes_used += 1
			_start_dash(move_vec)

func _handle_combat_inputs() -> void:
	if not is_player:
		return

	# Habilidades (Q / E / F)
	if is_on_floor():
		if Input.is_action_just_pressed("skill_q"):
			if use_skill(SKILL_Q):
				return
		elif Input.is_action_just_pressed("skill_e"):
			if use_skill(SKILL_E):
				return
		elif Input.is_action_just_pressed("skill_f"):
			if use_skill(SKILL_F):
				return
	elif character_class != "gunslinger":
		# Lutador: Investida (Q) e Queda com Onda de Choque (E) no ar!
		if Input.is_action_just_pressed("skill_q"):
			if use_skill(SKILL_Q):
				return
		elif Input.is_action_just_pressed("skill_e"):
			if use_skill(SKILL_E):
				return

	# Bloqueio / Foco de Mira / Pisão Aéreo
	if character_class == "gunslinger":
		# Pistoleiro não possui bloqueio nem pisão aéreo: foca a mira no alvo
		if Input.is_action_pressed("block") and current_state != State.DEAD and current_state != State.HITSTUN:
			is_focus_aiming = true
			if target and is_instance_valid(target) and target.current_state != State.DEAD:
				_face_target()
			_update_focus_aim_fx()
		else:
			if is_focus_aiming:
				is_focus_aiming = false
				_clear_focus_aim_fx()
	else:
		# Bloqueio (no chão) ou Golpe de Queda / Slam (no ar se pressionar botão direito) - Apenas Lutador
		if Input.is_action_just_pressed("block") and not is_on_floor():
			if current_state != State.SLAM and current_state != State.HITSTUN and current_state != State.SKILL:
				is_long_jumping = false
				_start_slam_attack()
				return

		if Input.is_action_pressed("block") and is_on_floor():
			if not is_blocking:
				_start_block()
			if target:
				_face_target()
			return
		elif is_blocking:
			_stop_block()

	# Ataque: Pistoleiro dispara tiros rápidos; Lutador realiza combo de socos
	if Input.is_action_just_pressed("attack"):
		if character_class == "gunslinger":
			if current_state != State.DEAD and current_state != State.HITSTUN and current_state != State.SKILL:
				if pistol_fire_cooldown <= 0.0:
					pistol_fire_cooldown = 0.25
					_fire_pistol_shot()
		else:
			if is_on_floor():
				if current_state == State.ATTACK:
					# Buffer de clique: se clicou durante um golpe em andamento antes do 3º hit
					if combo_step < 3:
						combo_queued = true
				elif current_state != State.HITSTUN and current_state != State.SLAM \
						and current_state != State.SKILL and current_state != State.DASH:
					_start_combo_attack()
			else:
				if current_state != State.ATTACK and current_state != State.HITSTUN \
						and current_state != State.SLAM and current_state != State.SKILL:
					is_long_jumping = false
					_start_slam_attack()

func _handle_bot_ai(delta: float) -> void:
	if is_rooted:
		velocity.x = 0.0
		velocity.z = 0.0
		current_state = State.IDLE
		if target and is_instance_valid(target) and target.current_state != State.DEAD:
			_face_target()
		return

	if not target or not is_instance_valid(target) or target.current_state == State.DEAD:
		velocity.x = move_toward(velocity.x, 0.0, speed * 4.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, speed * 4.0 * delta)
		current_state = State.IDLE
		return

	# Reduzir temporizadores da IA
	if ai_attack_cooldown > 0.0:
		ai_attack_cooldown -= delta
	if ai_action_timer > 0.0:
		ai_action_timer -= delta
	if ai_block_timer > 0.0:
		ai_block_timer -= delta
		if ai_block_timer <= 0.0:
			_stop_block()

	# Se estiver bloqueando, mantém defesa e encara o jogador
	if is_blocking:
		_face_target()
		velocity.x = move_toward(velocity.x, 0.0, speed * 4.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, speed * 4.0 * delta)
		return

	# Se estiver em ações bloqueantes, não emite novos comandos
	if current_state == State.DASH or current_state == State.ATTACK or current_state == State.HITSTUN or current_state == State.SLAM:
		return

	# Se estiver no ar, chance de desferir golpe de queda no oponente (apenas Lutador)
	if not is_on_floor() and character_class != "gunslinger":
		var to_tgt_air: Vector3 = target.global_position - global_position
		to_tgt_air.y = 0.0
		if to_tgt_air.length() < 3.8 and target.global_position.y < global_position.y:
			if skill_cooldowns[SKILL_E] <= 0.0 and randf() < 0.25:
				use_skill(SKILL_E)
				return
			elif randf() < 0.12:
				_start_slam_attack()
				return
		if to_tgt_air.length() > 4.0 and skill_cooldowns[SKILL_Q] <= 0.0 and randf() < 0.15:
			use_skill(SKILL_Q)
			return

	var to_target: Vector3 = target.global_position - global_position
	to_target.y = 0.0
	var dist: float = to_target.length()
	var target_dir: Vector3 = to_target.normalized() if dist > 0.1 else Vector3.FORWARD

	# Prevenção de Ring Out: se estiver perto da borda da arena quadrada
	var edge_dist: float = maxf(absf(global_position.x), absf(global_position.z))
	var move_dir: Vector3 = Vector3.ZERO

	if edge_dist > arena_half_size - 2.0:
		# Volta para o centro
		var center_dir: Vector3 = (Vector3.ZERO - global_position)
		center_dir.y = 0.0
		move_dir = center_dir.normalized()
	else:
		# Reação inteligente: quando o jogador ataca de perto, chance de defender ou esquivar
		if target.current_state == State.ATTACK and dist < 2.5:
			if character_class != "gunslinger" and randf() < 0.45:
				_start_block()
				ai_block_timer = randf_range(0.3, 0.55)
				_face_target()
				return
			elif randf() < 0.35 and is_on_floor():
				_start_dash(-target_dir)
				return

		# Navegação e ataque
		if dist > 3.2:
			# Perseguir
			move_dir = target_dir
			# Chance de dar dash para frente se estiver muito longe
			if dist > 7.0 and randf() < 0.02 and is_on_floor():
				_start_dash(target_dir)
				return
		elif dist > 1.8:
			# Distância média: aproxima e circula lateralmente
			if ai_action_timer <= 0.0:
				ai_action_timer = randf_range(0.6, 1.3)
				ai_strafe_dir = 1.0 if randf() > 0.5 else -1.0
			
			var strafe: Vector3 = Vector3(-target_dir.z, 0.0, target_dir.x) * ai_strafe_dir
			move_dir = (target_dir * 0.7 + strafe * 0.5).normalized()
		else:
			# Corpo a corpo (dist <= 2.2)
			_face_target()
			if ai_attack_cooldown <= 0.0:
				_face_target()
				_start_combo_attack()
				ai_attack_cooldown = randf_range(0.45, 0.8)
				return
			else:
				# Recua ligeiramente ou circula esperando recarregar, mas mantendo a mira no jogador
				var strafe_back: Vector3 = (-target_dir * 0.4 + Vector3(-target_dir.z, 0.0, target_dir.x) * ai_strafe_dir * 0.5).normalized()
				move_dir = strafe_back

	# Aplicação da velocidade
	if move_dir.length() > 0.1:
		velocity.x = move_dir.x * speed * 0.95
		velocity.z = move_dir.z * speed * 0.95
		if dist <= 2.8:
			# Em curta distância, NUNCA vira de costas para o jogador!
			_face_target()
		else:
			var local_move: Vector3 = to_local(global_position + move_dir)
			local_move.y = 0.0
			var target_angle: float = atan2(local_move.x, local_move.z)
			visuals.rotation.y = lerp_angle(visuals.rotation.y, target_angle, 12.0 * delta)
		if is_on_floor():
			current_state = State.MOVE
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed * 6.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, speed * 6.0 * delta)
		if is_on_floor():
			current_state = State.IDLE
			_face_target()

func _face_target() -> void:
	if target and is_instance_valid(target):
		var to_tgt: Vector3 = target.global_position - global_position
		to_tgt.y = 0.0
		if to_tgt.length() > 0.1:
			visuals.rotation.y = atan2(to_tgt.x, to_tgt.z)

func _start_block(from_rpc: bool = false) -> void:
	if character_class == "gunslinger":
		return
	if is_blocking:
		return
	if not from_rpc:
		_send_net_action(NetAction.START_BLOCK)
	if current_state == State.SLIDE:
		_end_slide()
	_end_attack()
	_reset_combo()
	is_blocking = true
	current_state = State.BLOCK
	_clear_block_fx()
	block_fx = SkillFX.create_block_shield(visuals)

func _stop_block(from_rpc: bool = false) -> void:
	if not is_blocking and block_fx == null:
		return
	if not from_rpc:
		_send_net_action(NetAction.STOP_BLOCK)
	is_blocking = false
	if current_state == State.BLOCK:
		current_state = State.IDLE
	_clear_block_fx()

func _clear_block_fx() -> void:
	if block_fx and is_instance_valid(block_fx):
		SkillFX.dismiss_block_shield(block_fx)
	block_fx = null

func _start_dash(direction: Vector3, from_rpc: bool = false) -> void:
	if not from_rpc:
		_send_net_action(NetAction.START_DASH, direction)
	_end_attack()
	_reset_combo()
	current_state = State.DASH
	dash_timer = dash_duration
	dash_trail_timer = 0.0 # dispara o primeiro rastro imediatamente

	if direction.length() > 0.1:
		dash_direction = direction.normalized()
		if character_class == "gunslinger" and is_focus_aiming and target and is_instance_valid(target) and target.current_state != State.DEAD:
			_face_target()
		else:
			visuals.rotation.y = atan2(dash_direction.x, dash_direction.z)
	else:
		# Dash para frente onde está olhando
		var forward: Vector3 = Vector3(sin(visuals.rotation.y), 0.0, cos(visuals.rotation.y))
		dash_direction = forward.normalized()

	# Efeito visual de arrancada (anel no chão + rajada de poeira para trás + cone sônico + tremor)
	var dash_color: Color = outfit_color.lerp(Color.WHITE, 0.4)
	SkillFX.dash_launch(get_parent(), global_position, dash_direction, dash_color)

	# Efeito cartum de aceleração: inclina e estica para a frente
	visuals.rotation.x = 0.32
	var tw: Tween = create_tween()
	tw.tween_property(visuals, "scale", Vector3(0.72, 0.85, 1.42), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(visuals, "scale", Vector3.ONE, dash_duration - 0.06).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

func _end_dash() -> void:
	visuals.rotation.x = 0.0
	visuals.scale = Vector3.ONE
	if fist_r:
		fist_r.position = original_fist_r_pos
	if fist_l:
		fist_l.position = original_fist_l_pos
	SkillFX.dash_brake(get_parent(), global_position, dash_direction)

	# Limita e amortece a velocidade horizontal pós-dash para não jogar o personagem longe
	var horiz_vel: Vector2 = Vector2(velocity.x, velocity.z)
	if horiz_vel.length() > post_dash_max_speed:
		horiz_vel = horiz_vel.normalized() * post_dash_max_speed
		velocity.x = horiz_vel.x
		velocity.z = horiz_vel.y

	if is_on_floor():
		dash_jump_buffer_timer = 0.18 # janela de 180ms pós-dash para transição fluida em Salto à Distância
		dash_slide_buffer_timer = 0.25 # janela pós-dash no chão para apertar Ctrl e deslizar
		if is_player and _is_slide_pressed():
			_start_slide()
			return
		_change_state(State.IDLE)
	else:
		air_dash_jump_buffer_timer = 0.22 # janela de 220ms pós-dash no ar para transição em SHIFT+Space
		if is_player and _is_slide_pressed():
			_trigger_fast_fall_slide_prime()
			return
		_change_state(State.JUMP)

## Impulso atlético aéreo disparado ao combinar SHIFT + Space no ar:
## Projeta o lutador com alta velocidade horizontal e abre a janela para o Ctrl (Deslize)
func _start_air_dash_jump(move_dir: Vector3 = Vector3.ZERO, from_rpc: bool = false) -> void:
	if not from_rpc:
		_send_net_action(NetAction.AIR_DASH_JUMP, move_dir)
	current_state = State.JUMP
	is_long_jumping = true
	long_jump_trail_timer = 0.0
	dash_jump_buffer_timer = 0.0
	air_dash_jump_buffer_timer = 0.0

	if move_dir.length() > 0.1:
		dash_direction = move_dir.normalized()
	elif dash_direction.length() < 0.1:
		dash_direction = Vector3(sin(visuals.rotation.y), 0.0, cos(visuals.rotation.y)).normalized()

	visuals.rotation.y = atan2(dash_direction.x, dash_direction.z)

	# Fusão aerodinâmica: alta velocidade horizontal sustentada
	var air_speed: float = long_jump_speed * 0.95
	velocity.x = dash_direction.x * air_speed
	velocity.z = dash_direction.z * air_speed
	velocity.y = maxf(velocity.y, 2.5) # Leve impulso para planar e voar suave

	# Abre a janela de tempo para apertar Ctrl
	air_shift_space_window = slide_window_duration
	is_slide_primed = false
	is_fast_falling = false

	# Efeitos visuais do salto aéreo
	var jump_color: Color = outfit_color.lerp(Color.WHITE, 0.45)
	SkillFX.dash_launch(get_parent(), global_position, dash_direction, jump_color)
	SkillFX.shake_camera(self, 0.07, 0.15)

	# Animação fluida e aerodinâmica no ar
	visuals.rotation.x = 0.28
	var tw: Tween = create_tween()
	tw.tween_property(visuals, "scale", Vector3(0.76, 1.15, 1.28), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(visuals, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_SINE)

## Ativado ao apertar Ctrl no ar:
## Acelera a queda imediatamente para acessar o chão rápido e deslizar com fluidez ao aterrissar
func _trigger_fast_fall_slide_prime() -> void:
	if current_state == State.DASH:
		visuals.rotation.x = 0.0
		visuals.scale = Vector3.ONE
		_change_state(State.JUMP)

	air_shift_space_window = 0.0
	is_slide_primed = true
	is_fast_falling = true

	# Puxa o personagem rapidamente em direção ao solo mantendo a propulsão horizontal
	velocity.y = -fast_fall_speed

	var horiz: Vector2 = Vector2(velocity.x, velocity.z)
	if horiz.length() < speed * 1.4:
		var fwd: Vector3 = dash_direction if dash_direction.length() > 0.1 else Vector3(sin(visuals.rotation.y), 0.0, cos(visuals.rotation.y)).normalized()
		var boost: float = speed * 1.5
		velocity.x = fwd.x * boost
		velocity.z = fwd.z * boost

	# Efeito visual de corte de ar vertical
	SkillFX.fast_fall_fx(get_parent(), global_position, outfit_color)

	# Efeito dinâmico de esticar em direção ao chão
	var tw: Tween = create_tween()
	tw.tween_property(visuals, "scale", Vector3(0.82, 1.25, 0.82), 0.06).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_property(visuals, "scale", Vector3(1.12, 0.88, 1.12), 0.12).set_trans(Tween.TRANS_SINE)

## Inicia o deslize (Slide) no instante do contato com o solo
func _start_slide(from_rpc: bool = false) -> void:
	if not from_rpc:
		_send_net_action(NetAction.START_SLIDE)
	is_long_jumping = false
	is_slide_primed = false
	is_fast_falling = false
	dash_slide_buffer_timer = 0.0
	current_state = State.SLIDE
	slide_timer = slide_duration
	slide_trail_timer = 0.0

	var horiz: Vector2 = Vector2(velocity.x, velocity.z)
	if horiz.length() > 0.5:
		slide_direction = Vector3(horiz.x, 0.0, horiz.y).normalized()
	elif dash_direction.length() > 0.1:
		slide_direction = dash_direction
	else:
		slide_direction = Vector3(sin(visuals.rotation.y), 0.0, cos(visuals.rotation.y)).normalized()

	visuals.rotation.y = atan2(slide_direction.x, slide_direction.z)

	# Velocidade inicial do deslize
	var cur_speed: float = maxf(horiz.length(), slide_speed)
	velocity.x = slide_direction.x * cur_speed
	velocity.z = slide_direction.z * cur_speed
	velocity.y = -4.0 # Mantém fixação no solo

	# Efeitos de fricção e faíscas ao entrar no slide
	var slide_color: Color = outfit_color.lerp(Color.WHITE, 0.3)
	SkillFX.slide_start_impact(get_parent(), global_position, slide_direction, slide_color)
	SkillFX.shake_camera(self, 0.08, 0.16)

## Finaliza o deslize retornando à postura neutra ou corrida fluida
func _end_slide() -> void:
	visuals.position.y = 0.0
	visuals.rotation.x = 0.0
	visuals.scale = Vector3.ONE
	if fist_r:
		fist_r.position = original_fist_r_pos
	if fist_l:
		fist_l.position = original_fist_l_pos
	if leg_l:
		leg_l.rotation.x = 0.0
	if leg_r:
		leg_r.rotation.x = 0.0
	if body_mesh:
		body_mesh.position.y = 0.9

	SkillFX.dash_brake(get_parent(), global_position, slide_direction)

	var horiz_vel: Vector2 = Vector2(velocity.x, velocity.z)
	if horiz_vel.length() > post_dash_max_speed:
		horiz_vel = horiz_vel.normalized() * post_dash_max_speed
		velocity.x = horiz_vel.x
		velocity.z = horiz_vel.y

	if is_on_floor():
		var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward") if is_player else Vector2.ZERO
		if input_dir.length() > 0.1:
			_change_state(State.MOVE)
		else:
			_change_state(State.IDLE)
	else:
		_change_state(State.JUMP)

func _start_long_jump(from_rpc: bool = false) -> void:
	if not from_rpc:
		_send_net_action(NetAction.LONG_JUMP)
	current_state = State.JUMP
	is_long_jumping = true
	long_jump_trail_timer = 0.0
	dash_jump_buffer_timer = 0.0

	# Direção alinhada com o Dash
	if dash_direction.length() < 0.1:
		dash_direction = Vector3(sin(visuals.rotation.y), 0.0, cos(visuals.rotation.y)).normalized()

	# Fusão Dash + Salto: propulsão horizontal combinada em arco de salto à distância
	velocity.x = dash_direction.x * long_jump_speed
	velocity.z = dash_direction.z * long_jump_speed
	velocity.y = jump_velocity * long_jump_height_mult

	# Animação fluida e atlética de salto à distância
	visuals.rotation.x = 0.28
	var tw: Tween = create_tween()
	tw.tween_property(visuals, "scale", Vector3(0.8, 1.15, 1.25), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(visuals, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	# Efeitos visuais da transição: anel expansivo no chão + rajada de vento
	var jump_color: Color = outfit_color.lerp(Color.WHITE, 0.45)
	SkillFX.ring(get_parent(), global_position + Vector3(0, 0.05, 0), 2.2, jump_color, 0.25)
	SkillFX.burst(get_parent(), global_position + Vector3(0, 0.2, 0), jump_color, 16, 5.5, 0.35, 0.15, true)
	SkillFX.shake_camera(self, 0.08, 0.16)

# ---------------------------------------------------------------------------
# SISTEMA DE COMBOS E ATAQUES BÁSICOS
# ---------------------------------------------------------------------------

func _start_combo_attack() -> void:
	if current_state == State.SLIDE:
		_end_slide()
	if combo_step == 0 or combo_reset_timer <= 0.0:
		_start_hit_1()
	elif combo_step == 1:
		_start_hit_2()
	elif combo_step == 2:
		_start_hit_3()
	else:
		_start_hit_1()

## Compatibilidade para chamadas diretas
func _start_attack() -> void:
	_start_combo_attack()

func _start_hit_1(from_rpc: bool = false) -> void:
	if not from_rpc:
		_send_net_action(NetAction.COMBO_HIT, 1)
	combo_step = 1
	combo_queued = false
	combo_reset_timer = combo_window_duration
	current_attack_damage = combo_hit_1_damage
	current_state = State.ATTACK
	attack_timer = attack_duration

	_setup_lunge(combo_lunge_distance, combo_lunge_duration)
	_play_hit_1_animation()

func _start_hit_2(from_rpc: bool = false) -> void:
	if not from_rpc:
		_send_net_action(NetAction.COMBO_HIT, 2)
	combo_step = 2
	combo_queued = false
	combo_reset_timer = combo_window_duration
	current_attack_damage = combo_hit_2_damage
	current_state = State.ATTACK
	attack_timer = attack_duration

	_setup_lunge(combo_lunge_distance, combo_lunge_duration)
	_play_hit_2_animation()

func _start_hit_3(from_rpc: bool = false) -> void:
	if not from_rpc:
		_send_net_action(NetAction.COMBO_HIT, 3)
	combo_step = 3
	combo_queued = false
	combo_reset_timer = 0.0 # Último hit do combo
	current_state = State.ATTACK
	attack_timer = kick_duration

	# Vira em direção ao alvo para o chute descendente
	if target and is_instance_valid(target) and target.current_state != State.DEAD:
		_face_target()

	combo_lunge_timer = 0.0
	velocity.x = 0.0
	velocity.z = 0.0

	_play_hit_3_kick_animation()

func _setup_lunge(dist: float, duration: float) -> void:
	# Ajusta a mira para o alvo se estiver por perto
	if target and is_instance_valid(target) and target.current_state != State.DEAD:
		var to_tgt: Vector3 = target.global_position - global_position
		to_tgt.y = 0.0
		if to_tgt.length() < 4.5:
			_face_target()

	combo_lunge_dir = Vector3(sin(visuals.rotation.y), 0.0, cos(visuals.rotation.y)).normalized()
	combo_lunge_timer = duration
	combo_lunge_speed = dist / duration

	# Ativa a detecção frontal da hitbox
	if hitbox_area:
		hitbox_area.monitoring = true

	# Leve efeito de impulso / poeira nos pés na arrancada de 1m
	var foot_pos: Vector3 = global_position + Vector3(0, 0.05, 0)
	SkillFX.burst(get_parent(), foot_pos, Color(0.9, 0.86, 0.78, 0.45), 5, 2.0, 0.2, 0.05, true)

func _play_hit_1_animation() -> void:
	if attack_tween and attack_tween.is_valid():
		attack_tween.kill()

	attack_tween = create_tween().set_parallel(true)
	# 1° Hit: Soco direito lançado vigorosamente para a frente
	attack_tween.tween_property(fist_r, "position:z", original_fist_r_pos.z + 1.25, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	attack_tween.tween_property(fist_r, "position:x", original_fist_r_pos.x - 0.08, 0.08)
	attack_tween.chain().tween_property(fist_r, "position", original_fist_r_pos, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Torção dinâmica do tronco para o soco direito
	if body_mesh:
		attack_tween.tween_property(body_mesh, "rotation:y", -0.22, 0.08).set_trans(Tween.TRANS_QUAD)
		attack_tween.chain().tween_property(body_mesh, "rotation:y", 0.0, 0.14).set_trans(Tween.TRANS_SINE)

	# Pernas: impulso dinâmico de passo para frente
	if leg_r and leg_l:
		attack_tween.tween_property(leg_r, "rotation:x", -0.35, 0.08)
		attack_tween.tween_property(leg_l, "rotation:x", 0.35, 0.08)
		attack_tween.chain().tween_property(leg_r, "rotation:x", 0.0, 0.14)
		attack_tween.tween_property(leg_l, "rotation:x", 0.0, 0.14)

	# Efeito cartunesco de esticar no avanço rápido
	attack_tween.tween_property(visuals, "scale", Vector3(0.88, 0.95, 1.18), 0.07).set_trans(Tween.TRANS_QUAD)
	attack_tween.chain().tween_property(visuals, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_SINE)

func _play_hit_2_animation() -> void:
	if attack_tween and attack_tween.is_valid():
		attack_tween.kill()

	attack_tween = create_tween().set_parallel(true)
	# 2° Hit: Soco esquerdo lançado com firmeza para a frente
	attack_tween.tween_property(fist_l, "position:z", original_fist_l_pos.z + 1.25, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	attack_tween.tween_property(fist_l, "position:x", original_fist_l_pos.x + 0.08, 0.08)
	attack_tween.chain().tween_property(fist_l, "position", original_fist_l_pos, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Torção dinâmica do tronco para o lado oposto
	if body_mesh:
		attack_tween.tween_property(body_mesh, "rotation:y", 0.22, 0.08).set_trans(Tween.TRANS_QUAD)
		attack_tween.chain().tween_property(body_mesh, "rotation:y", 0.0, 0.14).set_trans(Tween.TRANS_SINE)

	# Pernas invertidas para apoiar o soco esquerdo
	if leg_r and leg_l:
		attack_tween.tween_property(leg_l, "rotation:x", -0.35, 0.08)
		attack_tween.tween_property(leg_r, "rotation:x", 0.35, 0.08)
		attack_tween.chain().tween_property(leg_l, "rotation:x", 0.0, 0.14)
		attack_tween.tween_property(leg_r, "rotation:x", 0.0, 0.14)

	# Efeito cartunesco de esticar no avanço rápido
	attack_tween.tween_property(visuals, "scale", Vector3(0.88, 0.95, 1.18), 0.07).set_trans(Tween.TRANS_QUAD)
	attack_tween.chain().tween_property(visuals, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_SINE)

func _play_hit_3_kick_animation() -> void:
	if attack_tween and attack_tween.is_valid():
		attack_tween.kill()

	attack_tween = create_tween()

	# 3° Hit - Fase 1: Elevação e perna erguida no alto preparando o chute descendente (0.11s)
	var tw_prep: Tween = create_tween().set_parallel(true)
	tw_prep.tween_property(visuals, "position:y", 0.28, 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw_prep.tween_property(visuals, "scale", Vector3(0.82, 1.28, 0.82), 0.11)
	if leg_r:
		tw_prep.tween_property(leg_r, "rotation:x", -1.25, 0.11).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if leg_l:
		tw_prep.tween_property(leg_l, "rotation:x", 0.35, 0.11)
	if fist_r and fist_l:
		tw_prep.tween_property(fist_r, "position:y", original_fist_r_pos.y + 0.35, 0.11)
		tw_prep.tween_property(fist_l, "position:y", original_fist_l_pos.y + 0.35, 0.11)

	# Aos 0.11s: O calcanhar chuta com brutalidade o chão gerando a mesma explosão do Slam
	attack_tween.tween_interval(0.11)
	attack_tween.tween_callback(func() -> void:
		_trigger_ground_slam_impact()

		# Fase 2: Impacto explosivo no chão (Squash & Stretch e recuperação)
		var tw_impact: Tween = create_tween().set_parallel(true)
		tw_impact.tween_property(visuals, "position:y", 0.0, 0.05).set_trans(Tween.TRANS_QUAD)
		tw_impact.tween_property(visuals, "scale", Vector3(1.45, 0.55, 1.45), 0.07).set_trans(Tween.TRANS_BOUNCE)
		if leg_r:
			tw_impact.tween_property(leg_r, "rotation:x", 0.65, 0.05)
		if fist_r and fist_l:
			tw_impact.tween_property(fist_r, "position:y", 0.15, 0.05)
			tw_impact.tween_property(fist_l, "position:y", 0.15, 0.05)

		# Fase 3: Retorno suave à postura neutra
		tw_impact.chain().tween_property(visuals, "scale", Vector3.ONE, 0.20).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		if leg_r:
			tw_impact.tween_property(leg_r, "rotation:x", 0.0, 0.20).set_trans(Tween.TRANS_SINE)
		if leg_l:
			tw_impact.tween_property(leg_l, "rotation:x", 0.0, 0.20).set_trans(Tween.TRANS_SINE)
		if fist_r:
			tw_impact.tween_property(fist_r, "position", original_fist_r_pos, 0.20).set_trans(Tween.TRANS_SINE)
		if fist_l:
			tw_impact.tween_property(fist_l, "position", original_fist_l_pos, 0.20).set_trans(Tween.TRANS_SINE)
	)

func _end_attack() -> void:
	if hitbox_area:
		hitbox_area.monitoring = false
	if fist_r:
		fist_r.position = original_fist_r_pos
	if fist_l:
		fist_l.position = original_fist_l_pos
	if leg_l:
		leg_l.rotation.x = 0.0
	if leg_r:
		leg_r.rotation.x = 0.0
	if body_mesh:
		body_mesh.rotation.y = 0.0
	visuals.position.y = 0.0
	visuals.scale = Vector3.ONE
	combo_lunge_timer = 0.0

func _reset_combo() -> void:
	combo_step = 0
	combo_reset_timer = 0.0
	combo_queued = false
	combo_lunge_timer = 0.0
	if attack_tween and attack_tween.is_valid():
		attack_tween.kill()
		attack_tween = null

## Executa a onda de choque, tremor de câmera e dano em área do Golpe no Solo (Slam e 3° hit do combo)
func _trigger_ground_slam_impact() -> void:
	# Dano em área circular: metade da área (raio 2.5m) e metade do dano (20%) da habilidade E
	for node: Node in get_tree().get_nodes_in_group("fighters"):
		var other: Fighter = node as Fighter
		if other == null or other == self or other.current_state == State.DEAD:
			continue
		var offset: Vector3 = other.global_position - global_position
		offset.y = 0.0
		if offset.length() <= slam_radius:
			var push: Vector3 = offset.normalized() if offset.length() > 0.05 else Vector3.FORWARD
			other.take_damage(other.max_health * slam_damage_percent, Vector3(push.x * 10.0, 4.5, push.z * 10.0))

	# Pequena explosão de impacto: idêntica à do "E", com metade da área (raio = 2.5m)
	SkillFX.shockwave_explosion(get_parent(), global_position, slam_radius, SkillFX.COLOR_E)
	SkillFX.shake_camera(self, 0.14, 0.25)

## Executa a onda de choque, tremor de câmera e dano original da habilidade E quando disparada do ar
func _trigger_skill_e_slam_impact() -> void:
	for node: Node in get_tree().get_nodes_in_group("fighters"):
		var other: Fighter = node as Fighter
		if other == null or other == self or other.current_state == State.DEAD:
			continue
		var offset: Vector3 = other.global_position - global_position
		offset.y = 0.0
		if offset.length() <= skill_e_radius:
			var push: Vector3 = offset.normalized() if offset.length() > 0.05 else Vector3.FORWARD
			other.take_damage(other.max_health * skill_e_damage_percent, Vector3(push.x * 14.0, 6.5, push.z * 14.0))

	_spawn_shockwave_effect()

func _start_slam_attack(from_rpc: bool = false) -> void:
	if character_class == "gunslinger":
		return
	if not from_rpc:
		_send_net_action(NetAction.START_SLAM)
	if current_state == State.DASH or is_long_jumping:
		visuals.rotation.x = 0.0
	is_long_jumping = false
	is_fast_falling = false
	is_slide_primed = false
	is_skill_e_slam = false
	current_state = State.SLAM
	slam_landing = false
	slam_land_timer = 0.0

	# Se tiver um alvo por perto, vira instantaneamente em direção a ele
	if target and is_instance_valid(target) and target.current_state != State.DEAD:
		_face_target()

	# Mergulho vertical acelerado
	velocity.x = 0.0
	velocity.z = 0.0
	velocity.y = -slam_speed

	# Efeito visual de arranque aéreo
	var slam_fx_color: Color = outfit_color.lerp(SkillFX.COLOR_E, 0.45)
	SkillFX.ring(get_parent(), global_position + Vector3(0, 0.4, 0), 1.6, slam_fx_color, 0.22)
	SkillFX.burst(get_parent(), global_position + Vector3(0, 0.6, 0), slam_fx_color, 14, 5.0, 0.3, 0.1, true)

	# Postura cartunesca de mergulho: punhos apontados para baixo e corpo esticado
	visuals.rotation.x = 0.25
	visuals.scale = Vector3(0.72, 1.4, 0.72)
	if fist_r:
		fist_r.position = Vector3(0.22, 0.2, 0.35)
	if fist_l:
		fist_l.position = Vector3(-0.22, 0.2, 0.35)
	if leg_l:
		leg_l.rotation.x = 0.65
	if leg_r:
		leg_r.rotation.x = 0.65

func _on_slam_impact() -> void:
	slam_landing = true
	velocity = Vector3.ZERO

	var was_skill_e: bool = is_skill_e_slam
	is_skill_e_slam = false

	if was_skill_e:
		slam_land_timer = 0.24
		_trigger_skill_e_slam_impact()
	else:
		slam_land_timer = 0.18
		_trigger_ground_slam_impact()

	# Efeito de esmagamento contra o solo (squash & stretch) e retorno suave
	visuals.rotation.x = 0.0
	var squash_scale: Vector3 = Vector3(1.65, 0.48, 1.65) if was_skill_e else Vector3(1.45, 0.55, 1.45)
	visuals.scale = squash_scale
	if fist_r:
		fist_r.position = Vector3(original_fist_r_pos.x, 0.10 if was_skill_e else 0.12, original_fist_r_pos.z)
	if fist_l:
		fist_l.position = Vector3(original_fist_l_pos.x, 0.10 if was_skill_e else 0.12, original_fist_l_pos.z)

	var recover_time: float = 0.22 if was_skill_e else 0.18
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(visuals, "scale", Vector3.ONE, recover_time).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	if fist_r:
		tween.tween_property(fist_r, "position", original_fist_r_pos, recover_time).set_trans(Tween.TRANS_SINE)
	if fist_l:
		tween.tween_property(fist_l, "position", original_fist_l_pos, recover_time).set_trans(Tween.TRANS_SINE)
	if leg_l:
		tween.tween_property(leg_l, "rotation:x", 0.0, recover_time)
	if leg_r:
		tween.tween_property(leg_r, "rotation:x", 0.0, recover_time)

# ---------------------------------------------------------------------------
# HABILIDADES
# ---------------------------------------------------------------------------

func get_skill_cooldown_total(skill_index: int) -> float:
	if character_class == "gunslinger":
		match skill_index:
			SKILL_Q:
				return 4.0 # 4 segundos de recarga conforme especificado
			SKILL_E:
				return 8.0 # Armadilha
			_:
				return 18.0 # Tiro Certeiro de Rifle Longo
	else:
		match skill_index:
			SKILL_Q:
				return skill_q_cooldown
			SKILL_E:
				return skill_e_cooldown
			_:
				return skill_f_cooldown

## Tenta usar a habilidade. Retorna true se foi ativada.
func use_skill(skill_index: int, from_rpc: bool = false) -> bool:
	if current_state == State.DEAD or current_state == State.HITSTUN \
			or current_state == State.SKILL or current_state == State.DASH \
			or current_state == State.ATTACK or current_state == State.SLAM:
		return false
	if is_rooted:
		return false
	if not from_rpc and skill_cooldowns[skill_index] > 0.0:
		return false

	if not from_rpc:
		_send_net_action(NetAction.USE_SKILL, skill_index)

	if current_state == State.SLIDE:
		_end_slide()

	is_blocking = false
	_end_attack()
	_reset_combo()
	skill_cooldowns[skill_index] = get_skill_cooldown_total(skill_index)
	emit_signal("skill_used", skill_index, skill_cooldowns[skill_index])

	if character_class == "gunslinger":
		match skill_index:
			SKILL_Q:
				_start_gunslinger_q()
			SKILL_E:
				_start_gunslinger_e()
			SKILL_F:
				_start_gunslinger_f()
	else:
		match skill_index:
			SKILL_Q:
				_start_skill_q()
			SKILL_E:
				if is_on_floor():
					_start_skill_e()
				else:
					_start_air_skill_e()
			SKILL_F:
				_start_skill_f()
	return true

# ---------------------------------------------------------------------------
# HABILIDADES DO PISTOLEIRO (GUNSLINGER)
# ---------------------------------------------------------------------------

## Disparo padrão de pistola (4 tiros por segundo, tira 5% de vida, atira andando e esquivando)
func _fire_pistol_shot(from_rpc: bool = false) -> void:
	punch_alt = !punch_alt
	var fist: Node3D = fist_r if punch_alt else fist_l
	var orig_pos: Vector3 = original_fist_r_pos if punch_alt else original_fist_l_pos

	# Animação de recuo rápido na mão da pistola
	var tw: Tween = create_tween()
	tw.tween_property(fist, "position:z", orig_pos.z - 0.20, 0.05).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_property(fist, "position:z", orig_pos.z, 0.11).set_trans(Tween.TRANS_SINE)

	# Posição da boca da pistola
	var spawn_pos: Vector3 = fist.global_position + Vector3(0, 0.03, 0)
	# Disparo de projétil linear para frente do personagem (não-telequiado, permitindo esquiva)
	var shoot_dir: Vector3 = Vector3(sin(visuals.rotation.y), 0.0, cos(visuals.rotation.y)).normalized()
	if is_focus_aiming and target and is_instance_valid(target) and target.current_state != State.DEAD:
		var target_center: Vector3 = target.global_position + Vector3(0, 0.9, 0)
		shoot_dir = (target_center - spawn_pos).normalized()

	if not from_rpc:
		_send_net_action(NetAction.PISTOL_SHOT, [spawn_pos, shoot_dir])

	# Dano de 5% da vida máxima do alvo
	var dmg: float = 5.0
	if target and is_instance_valid(target):
		dmg = target.max_health * 0.05

	var bullet: Bullet = BulletScript.new()
	get_parent().add_child(bullet)
	bullet.setup(self, spawn_pos, shoot_dir, dmg, Color(1.0, 0.85, 0.25))

	# Muzzle flash e faíscas
	SkillFX.flash(get_parent(), spawn_pos, 0.35, Color(1.0, 0.88, 0.3), 0.08)
	SkillFX.burst(get_parent(), spawn_pos, Color(1.0, 0.75, 0.2), 5, 2.5, 0.12, 0.04)
	SkillFX.shake_camera(self, 0.025, 0.06)

## Habilidade Q: Corrida lateral com 10 disparos rápidos em 2 segundos (5 balas/segundo, 4s recarga)
func _start_gunslinger_q() -> void:
	active_skill = SKILL_Q
	current_state = State.SKILL
	skill_timer = 2.0 # 2 segundos de duração total
	gunslinger_q_shots_fired = 0
	gunslinger_q_shot_timer = 0.0 # primeiro tiro imediato

	# Direção da corrida lateral: detecta input do jogador ou escolhe lado com mais espaço
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	if input_dir.x < -0.2:
		gunslinger_q_side = -1.0
	elif input_dir.x > 0.2:
		gunslinger_q_side = 1.0
	else:
		gunslinger_q_side = 1.0 if global_position.x < 0 else -1.0

	SkillFX.ghost(get_parent(), global_position, Color(0.2, 0.8, 1.0), 0.3)
	SkillFX.ring(get_parent(), global_position + Vector3(0, 0.05, 0), 1.8, Color(0.25, 0.85, 1.0), 0.3)

func _fire_gunslinger_q_shot(from_rpc: bool = false) -> void:
	punch_alt = !punch_alt
	var fist: Node3D = fist_r if punch_alt else fist_l
	var orig_pos: Vector3 = original_fist_r_pos if punch_alt else original_fist_l_pos

	var tw: Tween = create_tween()
	tw.tween_property(fist, "position:z", orig_pos.z - 0.22, 0.04).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_property(fist, "position:z", orig_pos.z, 0.09).set_trans(Tween.TRANS_SINE)

	var spawn_pos: Vector3 = fist.global_position + Vector3(0, 0.03, 0)
	# Projétil linear disparado para frente do pistoleiro no momento (não-telequiado)
	var shoot_dir: Vector3 = Vector3(sin(visuals.rotation.y), 0.0, cos(visuals.rotation.y)).normalized()

	if not from_rpc:
		_send_net_action(NetAction.GUNSLINGER_Q_SHOT, [spawn_pos, shoot_dir])

	var dmg: float = 5.0
	if target and is_instance_valid(target):
		dmg = target.max_health * 0.05

	var bullet: Bullet = BulletScript.new()
	get_parent().add_child(bullet)
	bullet.setup(self, spawn_pos, shoot_dir, dmg, Color(0.25, 0.85, 1.0))

	SkillFX.flash(get_parent(), spawn_pos, 0.45, Color(0.3, 0.85, 1.0), 0.08)
	SkillFX.burst(get_parent(), spawn_pos, Color(0.3, 0.85, 1.0), 6, 3.2, 0.14, 0.05)
	SkillFX.shake_camera(self, 0.035, 0.08)

## Habilidade E: Solta uma armadilha no chão (prende por 2s e retira 10% de vida)
func _start_gunslinger_e() -> void:
	active_skill = SKILL_E
	current_state = State.SKILL
	skill_timer = 0.22
	velocity.x = 0.0
	velocity.z = 0.0

	var trap: BearTrap = TrapScript.new()
	get_parent().add_child(trap)
	var drop_pos: Vector3 = global_position + Vector3(sin(visuals.rotation.y), 0, cos(visuals.rotation.y)) * 0.85
	trap.setup(self, drop_pos)

	SkillFX.ring(get_parent(), drop_pos + Vector3(0, 0.05, 0), 1.2, Color(1.0, 0.7, 0.2), 0.25)
	SkillFX.burst(get_parent(), drop_pos + Vector3(0, 0.1, 0), Color(0.85, 0.75, 0.6), 8, 2.5, 0.2, 0.05)

	var tw: Tween = create_tween()
	tw.tween_property(visuals, "position:y", -0.28, 0.08).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_property(visuals, "position:y", 0.0, 0.14).set_trans(Tween.TRANS_SINE)

## Habilidade F: Puxa um rifle longo, carrega por 3 segundos e realiza um tiro certeiro (50% de dano)
func _start_gunslinger_f() -> void:
	active_skill = SKILL_F
	current_state = State.SKILL
	ult_firing = false
	skill_timer = 3.0 # Carrega por 3 segundos
	velocity.x = 0.0
	velocity.z = 0.0
	_face_target()

	if long_rifle_node == null or not is_instance_valid(long_rifle_node):
		long_rifle_node = CharacterBuilder.build_long_rifle()
		visuals.add_child(long_rifle_node)
	long_rifle_node.visible = true
	long_rifle_node.position = Vector3(0.08, 1.14, 0.38)
	long_rifle_node.rotation_degrees = Vector3.ZERO

	if fist_r:
		fist_r.position = Vector3(0.12, 1.10, 0.25)
	if fist_l:
		fist_l.position = Vector3(0.06, 1.14, 0.70)

	_create_sniper_aim_fx()
	SkillFX.shake_camera(self, 0.04, 3.0)

func _create_sniper_aim_fx() -> void:
	_clear_sniper_aim_fx()

	sniper_laser_line = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.015
	cyl.bottom_radius = 0.015
	cyl.height = 1.0
	cyl.radial_segments = 8
	cyl.rings = 1
	sniper_laser_line.mesh = cyl

	var mat_laser: StandardMaterial3D = StandardMaterial3D.new()
	mat_laser.albedo_color = Color(1.0, 0.15, 0.15, 0.75)
	mat_laser.emission_enabled = true
	mat_laser.emission = Color(1.0, 0.15, 0.15)
	mat_laser.emission_energy_multiplier = 3.5
	mat_laser.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_laser.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sniper_laser_line.material_override = mat_laser
	get_parent().add_child(sniper_laser_line)

	sniper_reticle = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.45
	torus.outer_radius = 0.50
	torus.rings = 16
	torus.ring_segments = 4
	sniper_reticle.mesh = torus

	var mat_reticle: StandardMaterial3D = StandardMaterial3D.new()
	mat_reticle.albedo_color = Color(1.0, 0.2, 0.2, 0.85)
	mat_reticle.emission_enabled = true
	mat_reticle.emission = Color(1.0, 0.2, 0.2)
	mat_reticle.emission_energy_multiplier = 3.0
	mat_reticle.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_reticle.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sniper_reticle.material_override = mat_reticle
	sniper_reticle.rotation_degrees.x = 90.0
	get_parent().add_child(sniper_reticle)

	sniper_reticle.scale = Vector3(2.5, 2.5, 2.5)
	var tw: Tween = sniper_reticle.create_tween()
	tw.tween_property(sniper_reticle, "scale", Vector3(0.5, 0.5, 0.5), 3.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _update_sniper_aim_fx() -> void:
	if not sniper_laser_line or not is_instance_valid(sniper_laser_line):
		return
	var origin: Vector3 = global_position + Vector3(0, 1.15, 0)
	var shoot_dir: Vector3 = Vector3(sin(visuals.rotation.y), 0, cos(visuals.rotation.y))
	var target_pos: Vector3 = origin + shoot_dir * 40.0
	if target and is_instance_valid(target) and target.current_state != State.DEAD:
		target_pos = target.global_position + Vector3(0, 0.95, 0)

	var dist: float = (target_pos - origin).length()
	sniper_laser_line.global_position = origin.lerp(target_pos, 0.5)
	sniper_laser_line.look_at(target_pos, Vector3.UP)
	sniper_laser_line.rotation_degrees.x += 90.0
	sniper_laser_line.scale = Vector3(1.0, dist, 1.0)

	if sniper_reticle and is_instance_valid(sniper_reticle):
		sniper_reticle.global_position = target_pos

func _clear_sniper_aim_fx() -> void:
	if sniper_laser_line and is_instance_valid(sniper_laser_line):
		sniper_laser_line.queue_free()
	sniper_laser_line = null
	if sniper_reticle and is_instance_valid(sniper_reticle):
		sniper_reticle.queue_free()
	sniper_reticle = null

func _update_focus_aim_fx() -> void:
	if not focus_aim_reticle or not is_instance_valid(focus_aim_reticle):
		focus_aim_reticle = MeshInstance3D.new()
		var torus: TorusMesh = TorusMesh.new()
		torus.inner_radius = 0.52
		torus.outer_radius = 0.62
		torus.rings = 24
		torus.ring_segments = 4
		focus_aim_reticle.mesh = torus

		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(0.25, 0.85, 1.0, 0.85)
		mat.emission_enabled = true
		mat.emission = Color(0.25, 0.85, 1.0)
		mat.emission_energy_multiplier = 3.2
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		focus_aim_reticle.material_override = mat
		get_parent().add_child(focus_aim_reticle)
		if target and is_instance_valid(target):
			focus_aim_reticle.global_position = target.global_position + Vector3(0, 0.9, 0)

	if target and is_instance_valid(target) and target.current_state != State.DEAD:
		var target_pos: Vector3 = target.global_position + Vector3(0, 0.9, 0)
		focus_aim_reticle.global_position = focus_aim_reticle.global_position.lerp(target_pos, 0.35)
		var cam: Camera3D = get_viewport().get_camera_3d()
		if cam:
			focus_aim_reticle.look_at(cam.global_position, Vector3.UP)
		else:
			focus_aim_reticle.look_at(global_position + Vector3(0, 0.9, 0), Vector3.UP)
		focus_aim_reticle.visible = true
	else:
		focus_aim_reticle.visible = false

func _clear_focus_aim_fx() -> void:
	if focus_aim_reticle and is_instance_valid(focus_aim_reticle):
		focus_aim_reticle.queue_free()
	focus_aim_reticle = null

func _spawn_sniper_bullet_trail(origin: Vector3, end_pos: Vector3) -> void:
	var trail: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.08
	cyl.bottom_radius = 0.08
	cyl.height = 1.0
	cyl.radial_segments = 12
	cyl.rings = 1
	trail.mesh = cyl

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.95, 0.8, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.4)
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail.material_override = mat

	var dist: float = (end_pos - origin).length()
	get_parent().add_child(trail)
	trail.global_position = origin.lerp(end_pos, 0.5)
	trail.look_at(end_pos, Vector3.UP)
	trail.rotation_degrees.x += 90.0
	trail.scale = Vector3(1.0, dist, 1.0)

	var tw: Tween = trail.create_tween().set_parallel(true)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(trail, "scale:x", 0.0, 0.35)
	tw.tween_property(trail, "scale:z", 0.0, 0.35)
	tw.chain().tween_callback(trail.queue_free)

func _fire_gunslinger_f() -> void:
	ult_firing = true
	skill_timer = 0.45
	_clear_sniper_aim_fx()

	_face_target()
	var shoot_dir: Vector3 = Vector3(sin(visuals.rotation.y), 0, cos(visuals.rotation.y))
	if target and is_instance_valid(target) and target.current_state != State.DEAD:
		var to_tgt: Vector3 = target.global_position - global_position
		to_tgt.y = 0.0
		if to_tgt.length() > 0.1:
			shoot_dir = to_tgt.normalized()

	var muzzle_pos: Vector3 = global_position + Vector3(0, 1.15, 0) + shoot_dir * 1.55

	# DANO DE 50% DA VIDA DO ALVO (Tiro Certeiro)
	var beam_end: Vector3 = muzzle_pos + shoot_dir * 45.0
	if target and is_instance_valid(target) and target.current_state != State.DEAD:
		var dmg: float = target.max_health * 0.50
		var knock_dir: Vector3 = (shoot_dir * 0.85 + Vector3.UP * 0.25).normalized()
		target.take_damage(dmg, knock_dir * 16.0)

		var hit_pos: Vector3 = target.global_position + Vector3(0, 1.0, 0)
		beam_end = hit_pos
		SkillFX.flash(get_parent(), hit_pos, 2.4, Color(1.0, 0.35, 0.2), 0.3)
		SkillFX.burst(get_parent(), hit_pos, Color(1.0, 0.85, 0.3), 30, 9.0, 0.5, 0.1)
		SkillFX.ring(get_parent(), target.global_position + Vector3(0, 0.05, 0), 3.0, Color(1.0, 0.25, 0.2), 0.35)

	_spawn_sniper_bullet_trail(muzzle_pos, beam_end)

	SkillFX.flash(get_parent(), muzzle_pos, 1.4, Color(1.0, 0.9, 0.5), 0.15)
	SkillFX.burst(get_parent(), muzzle_pos, Color(1.0, 0.7, 0.2), 20, 7.0, 0.3, 0.08)

	velocity = -shoot_dir * 8.5
	var tw_recoil: Tween = create_tween()
	tw_recoil.tween_property(visuals, "position:z", -0.35, 0.08).set_trans(Tween.TRANS_QUAD)
	tw_recoil.chain().tween_property(visuals, "position:z", 0.0, 0.25).set_trans(Tween.TRANS_SINE)

	SkillFX.shake_camera(self, 0.28, 0.45)

func _start_skill_f() -> void:
	active_skill = SKILL_F
	current_state = State.SKILL
	ult_firing = false
	skill_timer = skill_f_charge_time
	velocity.x = 0.0
	velocity.z = 0.0
	_face_target()

	# --- Efeitos de canalização: aura + esfera de energia + faíscas ---
	ult_aura = SkillFX.create_ult_aura()
	add_child(ult_aura)
	ult_aura.position = Vector3(0, 0.9, 0)
	SkillFX.charge_aura(ult_aura, skill_f_charge_time)

	# Esfera de energia que cresce na frente do lutador durante a carga
	charge_fx = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 16
	sphere.rings = 8
	charge_fx.mesh = sphere
	var mat: StandardMaterial3D = SkillFX.additive_material(Color(1.0, 0.45, 0.35, 0.95))
	charge_fx.material_override = mat
	visuals.add_child(charge_fx)
	charge_fx.position = Vector3(0, 1.2, 0.95)
	charge_fx.scale = Vector3.ONE * 0.1
	var tween: Tween = charge_fx.create_tween()
	tween.tween_property(charge_fx, "scale", Vector3.ONE * 1.4, skill_f_charge_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# Anel de energia no chão e leve tremor de câmera ao iniciar a carga
	SkillFX.ring(get_parent(), global_position + Vector3(0, 0.06, 0), 2.6, SkillFX.COLOR_F, 0.5)
	SkillFX.shake_camera(self, 0.04, skill_f_charge_time)

## Retorna 0..1 enquanto a Ultimate está carregando, ou -1 se não estiver.
func get_ult_charge() -> float:
	if current_state == State.SKILL and active_skill == SKILL_F and not ult_firing:
		return clampf(1.0 - skill_timer / skill_f_charge_time, 0.0, 1.0)
	return -1.0

func _clear_charge_fx(released: bool = false) -> void:
	if charge_fx and is_instance_valid(charge_fx):
		charge_fx.queue_free()
	charge_fx = null
	if ult_aura and is_instance_valid(ult_aura):
		if released:
			SkillFX.release_aura(ult_aura)
		else:
			ult_aura.queue_free()
	ult_aura = null

func _fire_ultimate() -> void:
	ult_firing = true
	skill_timer = 0.5 # breve recuperação enquanto o raio fica visível
	_clear_charge_fx(true)

	# Direção travada no momento do disparo (mira no alvo)
	if target and is_instance_valid(target) and target.current_state != State.DEAD:
		var to_tgt: Vector3 = target.global_position - global_position
		to_tgt.y = 0.0
		if to_tgt.length() > 0.1:
			skill_dir = to_tgt.normalized()
			visuals.rotation.y = atan2(skill_dir.x, skill_dir.z)
	else:
		skill_dir = Vector3(sin(visuals.rotation.y), 0.0, cos(visuals.rotation.y))

	var origin: Vector3 = global_position + Vector3(0, 1.2, 0) + skill_dir * 0.6

	# Dano: cilindro de raio 1m e 45m de comprimento à frente
	for node: Node in get_tree().get_nodes_in_group("fighters"):
		var other: Fighter = node as Fighter
		if other == null or other == self or other.current_state == State.DEAD:
			continue
		var rel: Vector3 = (other.global_position + Vector3(0, 0.9, 0)) - origin
		var along: float = rel.dot(skill_dir)
		if along < 0.0 or along > skill_f_length:
			continue
		var perp: float = (rel - skill_dir * along).length()
		if perp <= skill_f_radius:
			other.take_damage(other.max_health * skill_f_damage_percent, Vector3(skill_dir.x * 14.0, 5.0, skill_dir.z * 14.0))
			SkillFX.flash(get_parent(), other.global_position + Vector3(0, 1.0, 0), 2.2, SkillFX.COLOR_F, 0.3)
			SkillFX.burst(get_parent(), other.global_position + Vector3(0, 1.0, 0), SkillFX.COLOR_F, 28, 8.0, 0.5)

	_spawn_beam_effect(origin)
	SkillFX.flash(get_parent(), origin, 2.4, SkillFX.COLOR_F, 0.25)
	SkillFX.shake_camera(self, 0.22, 0.45)

func _spawn_beam_effect(origin: Vector3) -> void:
	var pivot: Node3D = Node3D.new()
	get_parent().add_child(pivot)
	pivot.global_position = origin
	pivot.look_at(origin + skill_dir, Vector3.UP) # -Z aponta para a frente do raio

	# Camada externa (raio de 1m) + núcleo brilhante
	var layers: Array[Dictionary] = [
		{"radius": skill_f_radius, "color": Color(1.0, 0.3, 0.25, 0.35)},
		{"radius": skill_f_radius * 0.4, "color": Color(1.0, 0.95, 0.85, 0.95)},
	]
	var materials: Array[StandardMaterial3D] = []
	for layer: Dictionary in layers:
		var beam: MeshInstance3D = MeshInstance3D.new()
		var cyl: CylinderMesh = CylinderMesh.new()
		cyl.top_radius = layer["radius"]
		cyl.bottom_radius = layer["radius"]
		cyl.height = skill_f_length
		cyl.radial_segments = 16
		cyl.rings = 1
		beam.mesh = cyl
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = layer["color"]
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		beam.material_override = mat
		beam.rotation_degrees.x = 90.0 # cilindro deitado ao longo do eixo Z
		beam.position = Vector3(0, 0, -skill_f_length * 0.5)
		pivot.add_child(beam)
		materials.append(mat)

	var tween: Tween = pivot.create_tween().set_parallel(true)
	for mat: StandardMaterial3D in materials:
		tween.tween_property(mat, "albedo_color:a", 0.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(pivot.queue_free)

func _start_skill_q() -> void:
	active_skill = SKILL_Q
	current_state = State.SKILL
	skill_timer = skill_q_duration
	skill_hit_ids.clear()
	skill_q_trail_timer = 0.0
	is_long_jumping = false
	is_fast_falling = false
	is_slide_primed = false
	velocity.y = 0.0

	# Direção da investida: respeita input de movimento do jogador se houver, ou mira no alvo se estiver no alcance, ou para frente
	var input_vec: Vector3 = Vector3.ZERO
	if is_player:
		var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
		if input_dir.length() > 0.1:
			input_vec = Vector3(input_dir.x, 0.0, input_dir.y).normalized()

	if input_vec.length() > 0.1:
		skill_dir = input_vec
		visuals.rotation.y = atan2(skill_dir.x, skill_dir.z)
	elif target and is_instance_valid(target) and target.current_state != State.DEAD:
		var to_tgt: Vector3 = target.global_position - global_position
		to_tgt.y = 0.0
		if to_tgt.length() > 0.1:
			skill_dir = to_tgt.normalized()
			visuals.rotation.y = atan2(skill_dir.x, skill_dir.z)
		else:
			skill_dir = Vector3(sin(visuals.rotation.y), 0.0, cos(visuals.rotation.y))
	else:
		skill_dir = Vector3(sin(visuals.rotation.y), 0.0, cos(visuals.rotation.y))

	# Arrancada explosiva, ondas de vento e esticada cartunesca durante a investida
	SkillFX.dash_launch(get_parent(), global_position, skill_dir, SkillFX.COLOR_Q)
	SkillFX.ghost(get_parent(), global_position, SkillFX.COLOR_Q, 0.28)
	var tween: Tween = create_tween()
	tween.tween_property(visuals, "scale", Vector3(0.8, 0.9, 1.35), 0.08)
	tween.tween_property(visuals, "scale", Vector3.ONE, skill_q_duration)

func _start_skill_e() -> void:
	active_skill = SKILL_E
	current_state = State.SKILL
	skill_timer = 0.35
	velocity.x = 0.0
	velocity.z = 0.0

	# Dano em área circular (raio aumentado de 2m para 5m) em todos os lutadores dentro dela
	for node: Node in get_tree().get_nodes_in_group("fighters"):
		var other: Fighter = node as Fighter
		if other == null or other == self or other.current_state == State.DEAD:
			continue
		var offset: Vector3 = other.global_position - global_position
		offset.y = 0.0
		if offset.length() <= skill_e_radius:
			var push: Vector3 = offset.normalized() if offset.length() > 0.05 else Vector3.FORWARD
			other.take_damage(other.max_health * skill_e_damage_percent, Vector3(push.x * 12.0, 5.0, push.z * 12.0))

	_spawn_shockwave_effect()

	# Animação cartunesca de impacto no chão:
	# Encolhimento rápido pré-golpe e esmagamento explosivo com rebote (squash & stretch)
	var tween: Tween = create_tween()
	tween.tween_property(visuals, "scale", Vector3(0.85, 1.25, 0.85), 0.06).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(visuals, "scale", Vector3(1.35, 0.65, 1.35), 0.09).set_trans(Tween.TRANS_BOUNCE)
	tween.tween_property(visuals, "scale", Vector3.ONE, 0.20).set_trans(Tween.TRANS_SINE)

	# Punhos descendo juntos ao chão no impacto
	if fist_r and fist_l:
		var tw_fists: Tween = create_tween().set_parallel(true)
		tw_fists.tween_property(fist_r, "position:y", 0.15, 0.08).set_trans(Tween.TRANS_QUAD)
		tw_fists.tween_property(fist_l, "position:y", 0.15, 0.08).set_trans(Tween.TRANS_QUAD)
		tw_fists.chain().tween_property(fist_r, "position:y", original_fist_r_pos.y, 0.22).set_trans(Tween.TRANS_SINE)
		tw_fists.tween_property(fist_l, "position:y", original_fist_l_pos.y, 0.22).set_trans(Tween.TRANS_SINE)

## Habilidade E no Ar: Queda vertical acelerada (Slam) que detona a onda de choque com raio (5m) e dano (40%) originais
func _start_air_skill_e() -> void:
	if character_class == "gunslinger":
		return
	if current_state == State.DASH or is_long_jumping:
		visuals.rotation.x = 0.0
	is_long_jumping = false
	is_fast_falling = false
	is_slide_primed = false
	is_skill_e_slam = true
	active_skill = SKILL_E
	current_state = State.SLAM
	slam_landing = false
	slam_land_timer = 0.0

	# Se tiver um alvo por perto, vira instantaneamente em direção a ele
	if target and is_instance_valid(target) and target.current_state != State.DEAD:
		_face_target()

	# Mergulho vertical acelerado com poder da habilidade E
	velocity.x = 0.0
	velocity.z = 0.0
	velocity.y = -slam_speed * 1.15

	# Efeito visual de arranque e concentração de energia roxa no ar
	SkillFX.ring(get_parent(), global_position + Vector3(0, 0.4, 0), 2.2, SkillFX.COLOR_E, 0.25)
	SkillFX.burst(get_parent(), global_position + Vector3(0, 0.6, 0), SkillFX.COLOR_E, 18, 6.0, 0.35, 0.12, true)

	# Postura cartunesca de mergulho: punhos apontados para baixo e corpo esticado
	visuals.rotation.x = 0.28
	visuals.scale = Vector3(0.70, 1.45, 0.70)
	if fist_r:
		fist_r.position = Vector3(0.25, 0.15, 0.40)
	if fist_l:
		fist_l.position = Vector3(-0.25, 0.15, 0.40)
	if leg_l:
		leg_l.rotation.x = 0.68
	if leg_r:
		leg_r.rotation.x = 0.68

func _spawn_shockwave_effect() -> void:
	SkillFX.shockwave_explosion(get_parent(), global_position, skill_e_radius, SkillFX.COLOR_E)
	SkillFX.shake_camera(self, 0.22, 0.35)

func _process_active_skill() -> void:
	if active_skill == SKILL_Q:
		if character_class == "gunslinger":
			# Corrida lateral dinâmica com 10 disparos rápidos em 2s
			var strafe_dir: Vector3 = Vector3.ZERO
			if target and is_instance_valid(target) and target.current_state != State.DEAD:
				var to_tgt: Vector3 = target.global_position - global_position
				to_tgt.y = 0.0
				to_tgt = to_tgt.normalized()
				strafe_dir = Vector3(-to_tgt.z, 0.0, to_tgt.x) * gunslinger_q_side
				_face_target()
			else:
				var fwd: Vector3 = Vector3(sin(visuals.rotation.y), 0, cos(visuals.rotation.y))
				strafe_dir = Vector3(-fwd.z, 0.0, fwd.x) * gunslinger_q_side

			velocity.x = strafe_dir.x * 23.0 # Velocidade duplicada conforme solicitado
			velocity.z = strafe_dir.z * 23.0

			# Animação de corrida lateral das pernas em alta velocidade
			if leg_l and leg_r:
				walk_phase += 28.0 * get_physics_process_delta_time()
				leg_l.rotation.x = sin(walk_phase) * 0.65
				leg_r.rotation.x = -sin(walk_phase) * 0.65

			# Rastro acrobático ciano
			skill_q_trail_timer -= get_physics_process_delta_time()
			if skill_q_trail_timer <= 0.0:
				skill_q_trail_timer = 0.04
				SkillFX.dash_trail_step(get_parent(), global_position, visuals.rotation.y, Color(0.2, 0.75, 1.0, 0.65), strafe_dir)

			# Disparos da rajada: 10 balas em 2 segundos (5 balas/segundo = a cada 0.20s)
			gunslinger_q_shot_timer -= get_physics_process_delta_time()
			if gunslinger_q_shot_timer <= 0.0 and gunslinger_q_shots_fired < 10:
				gunslinger_q_shot_timer = 0.20
				gunslinger_q_shots_fired += 1
				_fire_gunslinger_q_shot()
		else:
			var q_speed: float = skill_q_distance / skill_q_duration
			velocity.x = skill_dir.x * q_speed
			velocity.z = skill_dir.z * q_speed

			# Rastro visual contínuo ao longo dos 16m da investida
			skill_q_trail_timer -= get_physics_process_delta_time()
			if skill_q_trail_timer <= 0.0:
				skill_q_trail_timer = 0.035
				var trail_color: Color = SkillFX.COLOR_Q.lerp(Color.WHITE, 0.25)
				SkillFX.dash_trail_step(get_parent(), global_position, visuals.rotation.y, trail_color, skill_dir)

			# Detecção de acerto durante a investida
			for node: Node in get_tree().get_nodes_in_group("fighters"):
				var other: Fighter = node as Fighter
				if other == null or other == self or other.current_state == State.DEAD:
					continue
				if skill_hit_ids.has(other.get_instance_id()):
					continue
				var offset: Vector3 = other.global_position - global_position
				offset.y = 0.0
				if offset.length() <= 1.8:
					skill_hit_ids.append(other.get_instance_id())
					var blocked: bool = other.is_blocking
					var percent: float = skill_q_blocked_damage_percent if blocked else skill_q_damage_percent
					var knock_force: float = 7.0 if blocked else 14.0
					var knock_dir: Vector3 = (skill_dir * 0.85 + Vector3.UP * 0.25).normalized()
					other.take_damage(other.max_health * percent, knock_dir * knock_force, true)

					var hit_pos: Vector3 = global_position.lerp(other.global_position, 0.5) + Vector3(0, 0.95, 0)
					SkillFX.charge_hit_impact(get_parent(), hit_pos, skill_dir, blocked)
					_end_skill()
					break
	elif active_skill == SKILL_F:
		velocity.x = 0.0
		velocity.z = 0.0
		if not ult_firing:
			_face_target()
			if character_class == "gunslinger":
				_update_sniper_aim_fx()
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

func _end_skill() -> void:
	if active_skill == SKILL_Q:
		SkillFX.dash_brake(get_parent(), global_position, skill_dir)
	active_skill = -1
	ult_firing = false
	_clear_charge_fx()
	_clear_sniper_aim_fx()
	if long_rifle_node:
		long_rifle_node.visible = false
	if current_state == State.SKILL:
		current_state = State.IDLE if is_on_floor() else State.JUMP
	if fist_r:
		fist_r.position = original_fist_r_pos
	if fist_l:
		fist_l.position = original_fist_l_pos
	if leg_l:
		leg_l.rotation.x = 0.0
	if leg_r:
		leg_r.rotation.x = 0.0
	visuals.scale = Vector3.ONE
	velocity.x *= 0.2
	velocity.z *= 0.2

func _on_hitbox_body_entered(body: Node3D) -> void:
	if body == self:
		return
	if body is Fighter:
		var knock_dir: Vector3 = (body.global_position - global_position).normalized()
		knock_dir.y = 0.35
		var knock_force: float = 7.5 if combo_step == 1 else 9.0
		body.take_damage(current_attack_damage, knock_dir * knock_force)
		# Desliga a hitbox para não dar hit duplo no mesmo golpe
		hitbox_area.set_deferred("monitoring", false)

		# Feedback visual e de impacto do soco
		var hit_pos: Vector3 = global_position.lerp(body.global_position, 0.5) + Vector3(0, 0.9, 0)
		SkillFX.flash(get_parent(), hit_pos, 0.65, Color(1.0, 0.9, 0.5), 0.12)
		SkillFX.burst(get_parent(), hit_pos, Color(1.0, 0.8, 0.3), 8, 3.5, 0.2, 0.06)
		SkillFX.shake_camera(self, 0.05, 0.12)

func take_damage(damage: float, knockback: Vector3 = Vector3.ZERO, pre_reduced: bool = false, from_rpc: bool = false) -> void:
	if current_state == State.DEAD:
		return

	# Sincronização em rede: propaga o dano para o outro jogador se partiu deste cliente
	if not from_rpc and NetworkManager and NetworkManager.is_online:
		_net_call("rpc_take_damage", [damage, knockback, pre_reduced])

	# Ultimate em andamento: ininterrupta (hyper armor). Recebe o dano, mas sem
	# atordoamento nem recuo, então sempre dispara após o tempo de carga.
	var ult_armor: bool = current_state == State.SKILL and active_skill == SKILL_F

	if ult_armor:
		knockback = Vector3.ZERO
	elif is_blocking:
		# Bloqueio reduz 75% do dano (exceto quando o dano já veio reduzido) e reduz recuo
		if not pre_reduced:
			damage *= 0.25
		knockback *= 0.3
		if block_fx and is_instance_valid(block_fx):
			SkillFX.block_hit_reaction(block_fx, global_position + Vector3(0, 1.0, 0))
	else:
		current_state = State.HITSTUN
		hitstun_timer = 0.25
		active_skill = -1
		ult_firing = false
		slam_landing = false
		is_skill_e_slam = false
		is_long_jumping = false
		is_slide_primed = false
		is_fast_falling = false
		air_shift_space_window = 0.0
		_clear_charge_fx()
		_clear_sniper_aim_fx()
		if is_focus_aiming:
			is_focus_aiming = false
			_clear_focus_aim_fx()
		_end_attack()
		_reset_combo()
		visuals.position.y = 0.0
		visuals.rotation.x = 0.0
		if fist_r:
			fist_r.position = original_fist_r_pos
		if fist_l:
			fist_l.position = original_fist_l_pos
		if leg_l:
			leg_l.rotation.x = 0.0
		if leg_r:
			leg_r.rotation.x = 0.0
		
		# Animação de impacto: squish & flash cartum
		var tween: Tween = create_tween()
		tween.tween_property(visuals, "scale", Vector3(1.3, 0.7, 1.3), 0.08).set_trans(Tween.TRANS_SINE)
		tween.tween_property(visuals, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_BOUNCE)

	if ult_armor or is_rooted:
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		velocity = knockback
	current_health = clamp(current_health - damage, 0.0, max_health)
	emit_signal("health_changed", current_health, max_health)
	emit_signal("got_hit", damage)

	if current_health <= 0.0:
		die("K.O.")

func die(reason: String, from_rpc: bool = false) -> void:
	if current_state == State.DEAD:
		return
	if not from_rpc and NetworkManager and NetworkManager.is_online:
		_net_call("rpc_die", [reason])
	is_focus_aiming = false
	_clear_focus_aim_fx()
	_clear_sniper_aim_fx()
	_stop_block()
	_change_state(State.DEAD)
	_end_attack()
	_reset_combo()
	_clear_charge_fx()
	slam_landing = false
	is_skill_e_slam = false
	is_long_jumping = false
	is_slide_primed = false
	is_fast_falling = false
	air_shift_space_window = 0.0
	current_health = 0.0
	emit_signal("health_changed", current_health, max_health)
	emit_signal("died", self, reason)
	
	# Animação de tombo cartunesco ao morrer
	var tween: Tween = create_tween()
	tween.tween_property(visuals, "rotation:x", -PI * 0.5, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(visuals, "position:y", -0.4, 0.35)

func _exit_tree() -> void:
	_clear_focus_aim_fx()
	_clear_sniper_aim_fx()
	_clear_charge_fx()

func _update_visuals(delta: float) -> void:
	if current_state == State.DEAD:
		return
	if current_state == State.SLAM:
		return

	# Postura de Deslize (Slide): agachado rente ao chão, corpo inclinado para trás
	if current_state == State.SLIDE:
		visuals.position.y = lerpf(visuals.position.y, -0.22, clampf(20.0 * delta, 0.0, 1.0))
		visuals.rotation.x = lerp_angle(visuals.rotation.x, -0.28, clampf(18.0 * delta, 0.0, 1.0))
		body_mesh.position.y = lerpf(body_mesh.position.y, 0.62, clampf(20.0 * delta, 0.0, 1.0))
		visuals.scale = visuals.scale.lerp(Vector3(1.12, 0.76, 1.22), clampf(18.0 * delta, 0.0, 1.0))

		if leg_r and leg_l:
			leg_r.rotation.x = lerp_angle(leg_r.rotation.x, -1.2, clampf(20.0 * delta, 0.0, 1.0))
			leg_l.rotation.x = lerp_angle(leg_l.rotation.x, 0.72, clampf(20.0 * delta, 0.0, 1.0))

		if fist_r and fist_l:
			fist_r.position = fist_r.position.lerp(Vector3(0.42, 0.38, 0.1), clampf(18.0 * delta, 0.0, 1.0))
			fist_l.position = fist_l.position.lerp(Vector3(-0.38, 0.65, -0.25), clampf(18.0 * delta, 0.0, 1.0))
		return

	# Postura atlética durante o Salto à Distância (fusão Dash + Pulo)
	if is_long_jumping:
		visuals.rotation.x = lerp_angle(visuals.rotation.x, 0.24, 12.0 * delta)
		if leg_l and leg_r:
			leg_l.rotation.x = lerp_angle(leg_l.rotation.x, -0.68, 14.0 * delta)
			leg_r.rotation.x = lerp_angle(leg_r.rotation.x, 0.58, 14.0 * delta)
		if fist_r and fist_l:
			fist_r.position.z = lerpf(fist_r.position.z, original_fist_r_pos.z - 0.28, 14.0 * delta)
			fist_l.position.z = lerpf(fist_l.position.z, original_fist_l_pos.z - 0.28, 14.0 * delta)
		return

	# --- Postura de Bloqueio / Guarda ---
	if is_blocking:
		# Braços cruzados / punhos erguidos em guarda frontal fechada
		var guard_r: Vector3 = Vector3(0.20, 1.05, 0.38)
		var guard_l: Vector3 = Vector3(-0.20, 1.05, 0.38)
		if fist_r:
			fist_r.position = fist_r.position.lerp(guard_r, clampf(20.0 * delta, 0.0, 1.0))
		if fist_l:
			fist_l.position = fist_l.position.lerp(guard_l, clampf(20.0 * delta, 0.0, 1.0))
		# Base rebaixada e firme (pernas abertas e enraizadas no chão)
		if leg_l and leg_r:
			leg_l.rotation.x = lerp_angle(leg_l.rotation.x, -0.28, 16.0 * delta)
			leg_r.rotation.x = lerp_angle(leg_r.rotation.x, 0.28, 16.0 * delta)
		body_mesh.position.y = lerpf(body_mesh.position.y, 0.82, clampf(18.0 * delta, 0.0, 1.0))
		body_mesh.rotation.z = lerp_angle(body_mesh.rotation.z, 0.0, 14.0 * delta)
		return

	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	var grounded: bool = is_on_floor()
	var is_ult: bool = current_state == State.SKILL and active_skill == SKILL_F
	var can_walk: bool = grounded and horizontal_speed > 0.6 \
			and current_state != State.HITSTUN and current_state != State.ATTACK and not is_ult

	# --- Ciclo de caminhada / corrida ---
	var target_swing: float = 0.0
	if can_walk:
		var speed_ratio: float = clampf(horizontal_speed / speed, 0.0, 1.6)
		target_swing = 0.8 * minf(speed_ratio, 1.0) + 0.2 * maxf(speed_ratio - 1.0, 0.0)
		walk_phase += horizontal_speed * delta * 1.7
	leg_swing = lerpf(leg_swing, target_swing, clampf(14.0 * delta, 0.0, 1.0))

	if leg_l and leg_r:
		if not grounded:
			# No ar: pernas encolhidas, uma à frente da outra
			leg_l.rotation.x = lerp_angle(leg_l.rotation.x, -0.55, 10.0 * delta)
			leg_r.rotation.x = lerp_angle(leg_r.rotation.x, 0.45, 10.0 * delta)
		elif current_state == State.DASH:
			# Postura esportiva de arrancada/velocidade no Dash
			leg_l.rotation.x = -0.75
			leg_r.rotation.x = 0.65
		elif current_state == State.ATTACK:
			pass # Animação do combo controla as pernas
		else:
			var swing: float = sin(walk_phase) * leg_swing
			leg_l.rotation.x = swing
			leg_r.rotation.x = -swing
			# Ao parar, volta suavemente à posição neutra
			if leg_swing < 0.02:
				leg_l.rotation.x = lerp_angle(leg_l.rotation.x, 0.0, 12.0 * delta)
				leg_r.rotation.x = lerp_angle(leg_r.rotation.x, 0.0, 12.0 * delta)

	# Braços puxados para trás durante o dash supersônico estilo ninja/anime
	if current_state == State.DASH:
		if fist_r:
			fist_r.position.z = lerpf(fist_r.position.z, original_fist_r_pos.z - 0.35, clampf(24.0 * delta, 0.0, 1.0))
		if fist_l:
			fist_l.position.z = lerpf(fist_l.position.z, original_fist_l_pos.z - 0.35, clampf(24.0 * delta, 0.0, 1.0))
	elif current_state != State.ATTACK and current_state != State.SKILL and not is_blocking:
		if character_class == "gunslinger" and is_focus_aiming:
			# Postura tática com as pistolas apontadas à frente em direção ao alvo
			var aim_r: Vector3 = Vector3(0.24, 1.02, 0.45)
			var aim_l: Vector3 = Vector3(-0.24, 1.02, 0.45)
			if fist_r:
				fist_r.position = fist_r.position.lerp(aim_r, clampf(18.0 * delta, 0.0, 1.0))
			if fist_l:
				fist_l.position = fist_l.position.lerp(aim_l, clampf(18.0 * delta, 0.0, 1.0))
		else:
			# Retorno suave dos punhos à postura neutra ao sair de bloqueio, esquiva, etc.
			if fist_r:
				fist_r.position = fist_r.position.lerp(original_fist_r_pos, clampf(16.0 * delta, 0.0, 1.0))
			if fist_l:
				fist_l.position = fist_l.position.lerp(original_fist_l_pos, clampf(16.0 * delta, 0.0, 1.0))

	# --- Corpo: respiração parado, quicando e balançando ao andar ---
	if can_walk:
		var bounce: float = absf(sin(walk_phase)) * 0.07 * (leg_swing / 0.8)
		body_mesh.position.y = lerpf(body_mesh.position.y, 0.9 + bounce, clampf(20.0 * delta, 0.0, 1.0))
		body_mesh.rotation.z = lerp_angle(body_mesh.rotation.z, sin(walk_phase) * 0.08, 12.0 * delta)
	else:
		var bob: float = 0.0
		if current_state == State.IDLE:
			bob = sin(Time.get_ticks_msec() * 0.006) * 0.03
		body_mesh.position.y = lerpf(body_mesh.position.y, 0.9 + bob, clampf(12.0 * delta, 0.0, 1.0))
		body_mesh.rotation.z = lerp_angle(body_mesh.rotation.z, 0.0, 10.0 * delta)

func _change_state(new_state: State) -> void:
	if current_state == State.ATTACK and new_state != State.ATTACK:
		_end_attack()
	if current_state == State.BLOCK and new_state != State.BLOCK:
		_stop_block()
	if current_state == State.DASH and new_state != State.DASH:
		visuals.rotation.x = 0.0
		visuals.scale = Vector3.ONE
		if fist_r:
			fist_r.position = original_fist_r_pos
		if fist_l:
			fist_l.position = original_fist_l_pos
	if current_state == State.SLAM and new_state != State.SLAM:
		visuals.rotation.x = 0.0
		visuals.scale = Vector3.ONE
		slam_landing = false
		is_skill_e_slam = false
		if fist_r:
			fist_r.position = original_fist_r_pos
		if fist_l:
			fist_l.position = original_fist_l_pos
		if leg_l:
			leg_l.rotation.x = 0.0
		if leg_r:
			leg_r.rotation.x = 0.0
	if current_state == State.SLIDE and new_state != State.SLIDE:
		visuals.position.y = 0.0
		visuals.rotation.x = 0.0
		visuals.scale = Vector3.ONE
		if fist_r:
			fist_r.position = original_fist_r_pos
		if fist_l:
			fist_l.position = original_fist_l_pos
		if leg_l:
			leg_l.rotation.x = 0.0
		if leg_r:
			leg_r.rotation.x = 0.0
		if body_mesh:
			body_mesh.position.y = 0.9
	if new_state != State.JUMP:
		is_long_jumping = false
		visuals.rotation.x = 0.0
	current_state = new_state

# ==============================================================================
# MÉTODOS DE SINCRONIZAÇÃO DE REDE (RPCS)
# ==============================================================================
func _send_net_action(action: NetAction, data = null) -> void:
	if is_player and NetworkManager and NetworkManager.is_online:
		_net_call("rpc_execute_action", [int(action), data])

## Envia uma chamada remota: via P2P WebRTC quando conectado; caso contrário,
## via relay do servidor de sinalização (WebSocket), que funciona em qualquer rede/plataforma.
func _net_call(method: String, args: Array) -> void:
	if NetworkManager.has_p2p_peer():
		callv("rpc", [method] + args)
	else:
		NetworkManager.send_game_msg(String(name), method, args)

@rpc("any_peer", "call_remote", "reliable")
func rpc_execute_action(action_int: int, data: Variant) -> void:
	if is_player:
		return
	var action: NetAction = action_int as NetAction
	match action:
		NetAction.COMBO_HIT:
			var step: int = int(data) if data != null else 1
			if step == 1:
				_start_hit_1(true)
			elif step == 2:
				_start_hit_2(true)
			elif step == 3:
				_start_hit_3(true)
			else:
				_start_combo_attack()
		NetAction.PISTOL_SHOT:
			if data is Array and data.size() >= 2:
				_remote_fire_bullet(data[0], data[1], Color(1.0, 0.85, 0.25))
			else:
				_fire_pistol_shot(true)
		NetAction.GUNSLINGER_Q_SHOT:
			if data is Array and data.size() >= 2:
				_remote_fire_bullet(data[0], data[1], Color(0.25, 0.85, 1.0))
			else:
				_fire_gunslinger_q_shot(true)
		NetAction.START_BLOCK:
			_start_block(true)
		NetAction.STOP_BLOCK:
			_stop_block(true)
		NetAction.START_DASH:
			var dir: Vector3 = data if data is Vector3 else Vector3.FORWARD
			_start_dash(dir, true)
		NetAction.START_SLIDE:
			_start_slide(true)
		NetAction.START_SLAM:
			_start_slam_attack(true)
		NetAction.USE_SKILL:
			var s_idx: int = int(data)
			use_skill(s_idx, true)
		NetAction.LONG_JUMP:
			_start_long_jump(true)
		NetAction.AIR_DASH_JUMP:
			var move_dir: Vector3 = data if data is Vector3 else Vector3.ZERO
			_start_air_dash_jump(move_dir, true)

func _remote_fire_bullet(spawn_pos: Vector3, shoot_dir: Vector3, color: Color) -> void:
	punch_alt = !punch_alt
	var fist: Node3D = fist_r if punch_alt else fist_l
	var orig_pos: Vector3 = original_fist_r_pos if punch_alt else original_fist_l_pos
	var tw: Tween = create_tween()
	tw.tween_property(fist, "position:z", orig_pos.z - 0.20, 0.05).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_property(fist, "position:z", orig_pos.z, 0.11).set_trans(Tween.TRANS_SINE)

	var dmg: float = 5.0
	if target and is_instance_valid(target):
		dmg = target.max_health * 0.05
	var bullet: Bullet = BulletScript.new()
	get_parent().add_child(bullet)
	bullet.setup(self, spawn_pos, shoot_dir, dmg, color)
	SkillFX.flash(get_parent(), spawn_pos, 0.35, color, 0.08)
	SkillFX.burst(get_parent(), spawn_pos, color, 5, 2.5, 0.12, 0.04)

@rpc("any_peer", "call_remote", "reliable")
func rpc_die(p_reason: String) -> void:
	die(p_reason, true)

@rpc("any_peer", "call_remote", "reliable")
func rpc_take_damage(p_damage: float, p_knockback: Vector3, p_pre_reduced: bool) -> void:
	take_damage(p_damage, p_knockback, p_pre_reduced, true)

@rpc("any_peer", "unreliable")
func rpc_sync_transform(p_pos: Vector3, p_rot_y: float, p_vel: Vector3, p_state: int) -> void:
	if is_player:
		return
	net_target_pos = p_pos
	net_target_rot_y = p_rot_y
	net_target_velocity = p_vel
	if current_state != p_state:
		if p_state == State.DEAD and current_state != State.DEAD:
			die("K.O.", true)
		elif p_state != State.DEAD and current_state != State.DEAD:
			_change_state(p_state)

