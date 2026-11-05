class_name ArenaCamera
extends Camera3D

@export var target_1: Node3D # Jogador 1 (foco principal)
@export var target_2: Node3D # Oponente / Bot (alvo de mira)

@export_group("Follow Settings")
@export var distance: float = 5.8
@export var height: float = 2.5
@export var follow_speed: float = 7.5
@export var rotation_speed: float = 9.0

var current_look_target: Vector3 = Vector3.ZERO

# Tremor de câmera (usado pelas habilidades)
var shake_strength: float = 0.0
var shake_duration: float = 0.0
var shake_time_left: float = 0.0

## Faz a câmera tremer. Mantém o tremor mais forte se já houver um em andamento.
func shake(strength: float, duration: float) -> void:
	if strength >= shake_strength * (shake_time_left / maxf(shake_duration, 0.001)):
		shake_strength = strength
		shake_duration = duration
		shake_time_left = duration

func _apply_shake(delta: float) -> void:
	if shake_time_left > 0.0:
		shake_time_left -= delta
		var k: float = clampf(shake_time_left / maxf(shake_duration, 0.001), 0.0, 1.0)
		h_offset = randf_range(-1.0, 1.0) * shake_strength * k
		v_offset = randf_range(-1.0, 1.0) * shake_strength * k
	else:
		h_offset = 0.0
		v_offset = 0.0

func _physics_process(delta: float) -> void:
	_apply_shake(delta)
	if not target_1 or not is_instance_valid(target_1):
		return

	var p_pos: Vector3 = target_1.global_position
	var desired_pos: Vector3 = Vector3.ZERO
	var target_look: Vector3 = p_pos + Vector3(0, 1.3, 0)

	# Se tiver um oponente válido e vivo
	if target_2 and is_instance_valid(target_2):
		var opp_pos: Vector3 = target_2.global_position
		var to_opp: Vector3 = opp_pos - p_pos
		to_opp.y = 0.0

		var opp_dir: Vector3
		if to_opp.length() > 0.4:
			opp_dir = to_opp.normalized()
		else:
			# Fallback se estiver exatamente no mesmo ponto
			opp_dir = -target_1.global_transform.basis.z
			opp_dir.y = 0.0
			opp_dir = opp_dir.normalized()

		# A câmera se posiciona diretamente atrás do jogador, alinhada com o oponente
		desired_pos = p_pos - (opp_dir * distance) + Vector3(0, height, 0)
		
		# Ponto para onde a câmera olha: um pouco à frente do jogador em direção ao oponente
		var look_forward_dist: float = clamp(to_opp.length() * 0.35, 1.2, 4.5)
		target_look = p_pos + (opp_dir * look_forward_dist) + Vector3(0, 1.3, 0)
	else:
		# Sem oponente: segue atrás da orientação do jogador
		var backward: Vector3 = target_1.global_transform.basis.z
		backward.y = 0.0
		desired_pos = p_pos + (backward.normalized() * distance) + Vector3(0, height, 0)
		target_look = p_pos + Vector3(0, 1.3, 0)

	# Interpolação suave de posição
	global_position = global_position.lerp(desired_pos, follow_speed * delta)

	# Interpolação suave do ponto de mira (evita qualquer tremor)
	if current_look_target == Vector3.ZERO:
		current_look_target = target_look
	else:
		current_look_target = current_look_target.lerp(target_look, rotation_speed * delta)

	look_at(current_look_target, Vector3.UP)
