class_name BearTrap
extends Node3D

const SkillFX = preload("res://scripts/skill_fx.gd")

@export var trigger_radius: float = 1.4
@export var root_duration: float = 2.0
@export var damage_percent: float = 0.10 # 10% da vida máxima
@export var max_duration: float = 30.0

var owner_fighter: Node3D = null
var is_triggered: bool = false
var life_timer: float = 0.0
var trapped_target: Fighter = null

var jaw_left: Node3D = null
var jaw_right: Node3D = null
var indicator_light: MeshInstance3D = null

func _ready() -> void:
	_build_trap_model()

func setup(p_owner: Node3D, p_pos: Vector3) -> void:
	owner_fighter = p_owner
	global_position = p_pos
	global_position.y = 0.02 # Rente ao piso da arena

func _build_trap_model() -> void:
	# Material metálico escuro com contorno
	var mat_metal: StandardMaterial3D = StandardMaterial3D.new()
	mat_metal.albedo_color = Color(0.22, 0.24, 0.28, 1.0)
	mat_metal.metallic = 0.8
	mat_metal.roughness = 0.35

	# Base circular central
	var base_mesh: CylinderMesh = CylinderMesh.new()
	base_mesh.top_radius = 0.45
	base_mesh.bottom_radius = 0.50
	base_mesh.height = 0.04
	base_mesh.radial_segments = 16
	var base_inst: MeshInstance3D = MeshInstance3D.new()
	base_inst.mesh = base_mesh
	base_inst.material_override = mat_metal
	add_child(base_inst)

	# Placa de pressão central
	var plate_mesh: CylinderMesh = CylinderMesh.new()
	plate_mesh.top_radius = 0.22
	plate_mesh.bottom_radius = 0.22
	plate_mesh.height = 0.06
	plate_mesh.radial_segments = 12
	var plate_inst: MeshInstance3D = MeshInstance3D.new()
	plate_inst.mesh = plate_mesh
	plate_inst.material_override = mat_metal
	plate_inst.position = Vector3(0, 0.02, 0)
	add_child(plate_inst)

	# Luz indicadora pulsante no centro
	indicator_light = MeshInstance3D.new()
	var ind_mesh: SphereMesh = SphereMesh.new()
	ind_mesh.radius = 0.08
	ind_mesh.height = 0.16
	indicator_light.mesh = ind_mesh
	var mat_glow: StandardMaterial3D = StandardMaterial3D.new()
	mat_glow.albedo_color = Color(1.0, 0.65, 0.1, 1.0)
	mat_glow.emission_enabled = true
	mat_glow.emission = Color(1.0, 0.65, 0.1, 1.0)
	mat_glow.emission_energy_multiplier = 2.0
	indicator_light.material_override = mat_glow
	indicator_light.position = Vector3(0, 0.06, 0)
	add_child(indicator_light)

	# Mandíbula esquerda (arqueada e dentada)
	jaw_left = Node3D.new()
	jaw_left.position = Vector3(-0.4, 0.03, 0.0)
	add_child(jaw_left)
	_build_jaw_half(jaw_left, mat_metal, -1.0)

	# Mandíbula direita (arqueada e dentada)
	jaw_right = Node3D.new()
	jaw_right.position = Vector3(0.4, 0.03, 0.0)
	add_child(jaw_right)
	_build_jaw_half(jaw_right, mat_metal, 1.0)

	# Leve animação de respiração da luz indicadora
	var tw: Tween = indicator_light.create_tween().set_loops()
	tw.tween_property(indicator_light, "scale", Vector3(1.2, 1.2, 1.2), 0.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(indicator_light, "scale", Vector3(0.8, 0.8, 0.8), 0.6).set_trans(Tween.TRANS_SINE)

func _build_jaw_half(parent: Node3D, mat: StandardMaterial3D, dir: float) -> void:
	# Barra arqueada da mandíbula
	var bar_mesh: BoxMesh = BoxMesh.new()
	bar_mesh.size = Vector3(0.06, 0.06, 0.85)
	var bar: MeshInstance3D = MeshInstance3D.new()
	bar.mesh = bar_mesh
	bar.material_override = mat
	bar.position = Vector3(dir * 0.35, 0.02, 0.0)
	parent.add_child(bar)

	# Dentes afiados de metal
	for z_pos: float in [-0.35, -0.18, 0.0, 0.18, 0.35]:
		var tooth: MeshInstance3D = MeshInstance3D.new()
		var prism: PrismMesh = PrismMesh.new()
		prism.size = Vector3(0.08, 0.14, 0.08)
		tooth.mesh = prism
		tooth.material_override = mat
		tooth.position = Vector3(dir * 0.35, 0.09, z_pos)
		tooth.rotation_degrees.y = 90.0 if dir < 0 else -90.0
		parent.add_child(tooth)

func _physics_process(delta: float) -> void:
	if is_triggered:
		if trapped_target and is_instance_valid(trapped_target):
			global_position.x = trapped_target.global_position.x
			global_position.z = trapped_target.global_position.z
		return

	life_timer += delta
	if life_timer >= max_duration:
		_expire()
		return

	# Checar se algum lutador inimigo pisou na armadilha
	var fighters: Array[Node] = get_tree().get_nodes_in_group("fighters")
	for node in fighters:
		var fighter: Fighter = node as Fighter
		if fighter == null or fighter == owner_fighter or fighter.current_state == Fighter.State.DEAD:
			continue

		var dist_h: float = Vector2(fighter.global_position.x - global_position.x, fighter.global_position.z - global_position.z).length()
		if dist_h <= trigger_radius and fighter.global_position.y <= 1.2:
			_snap_shut(fighter)
			break

func _snap_shut(target: Fighter) -> void:
	is_triggered = true
	trapped_target = target
	global_position.x = target.global_position.x
	global_position.z = target.global_position.z

	# Animação instantânea de fechar as duas mandíbulas no centro
	var tw: Tween = create_tween().set_parallel(true)
	if jaw_left:
		tw.tween_property(jaw_left, "rotation_degrees:z", 75.0, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if jaw_right:
		tw.tween_property(jaw_right, "rotation_degrees:z", -75.0, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Prende o oponente e retira 10% de sua vida
	var damage_amount: float = target.max_health * damage_percent
	target.take_damage(damage_amount, Vector3.ZERO)
	if target.has_method("apply_root"):
		target.apply_root(root_duration)

	# Efeitos visuais de impacto da armadilha
	var snap_pos: Vector3 = global_position + Vector3(0, 0.3, 0)
	SkillFX.flash(get_parent(), snap_pos, 1.2, Color(1.0, 0.6, 0.1), 0.15)
	SkillFX.burst(get_parent(), snap_pos, Color(1.0, 0.8, 0.3), 16, 4.0, 0.3, 0.08)
	SkillFX.ring(get_parent(), global_position + Vector3(0, 0.05, 0), 1.6, Color(1.0, 0.4, 0.1), 0.3)
	SkillFX.shake_camera(self, 0.12, 0.25)

	# Manter presa aos pés do alvo durante os 2 segundos
	var follow_tw: Tween = create_tween()
	follow_tw.tween_interval(root_duration)
	follow_tw.chain().tween_callback(func() -> void:
		_expire()
	)

func _expire() -> void:
	var tw: Tween = create_tween()
	tw.tween_property(self, "scale", Vector3.ZERO, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(queue_free)

