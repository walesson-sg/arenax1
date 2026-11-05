class_name Bullet
extends Node3D

const SkillFX = preload("res://scripts/skill_fx.gd")

@export var speed: float = 52.0 # 20% mais lento que 65.0, permitindo esquiva
@export var max_range: float = 50.0

var shooter: Node3D = null
var direction: Vector3 = Vector3.FORWARD
var damage: float = 5.0
var bullet_color: Color = Color(1.0, 0.82, 0.28, 1.0)
var distance_traveled: float = 0.0

var mesh_instance: MeshInstance3D = null

func _ready() -> void:
	# Montar o visual da bala: cápsula afilada brilhante alinhada ao eixo Z
	mesh_instance = MeshInstance3D.new()
	var cap: CapsuleMesh = CapsuleMesh.new()
	cap.radius = 0.045
	cap.height = 0.38
	cap.radial_segments = 8
	cap.rings = 2
	mesh_instance.mesh = cap
	
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = bullet_color
	mat.emission_enabled = true
	mat.emission = bullet_color
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_instance.material_override = mat
	
	# Rotacionar para apontar na direção de movimento (-Z é frente)
	mesh_instance.rotation_degrees.x = 90.0
	add_child(mesh_instance)

func setup(p_shooter: Node3D, p_start_pos: Vector3, p_dir: Vector3, p_damage: float, p_color: Color = Color(1.0, 0.82, 0.28, 1.0)) -> void:
	shooter = p_shooter
	global_position = p_start_pos
	direction = p_dir.normalized()
	damage = p_damage
	bullet_color = p_color
	distance_traveled = 0.0
	
	if direction.length_squared() > 0.001:
		look_at(global_position + direction, Vector3.UP)

func _physics_process(delta: float) -> void:
	var move_step: float = speed * delta
	var start_pos: Vector3 = global_position
	var end_pos: Vector3 = start_pos + direction * move_step
	
	# Raycast do trajeto para colisão 100% confiável sem tunneling
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(start_pos, end_pos)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	# Excluir o próprio atirador
	if shooter:
		query.exclude = [shooter.get_rid()]
		
	var hit: Dictionary = space_state.intersect_ray(query)
	if not hit.is_empty():
		var collider: Object = hit.get("collider")
		var hit_pos: Vector3 = hit.get("position", end_pos)
		
		if collider is Fighter and collider != shooter:
			var target_fighter: Fighter = collider as Fighter
			var knock_dir: Vector3 = (direction * 0.7 + Vector3.UP * 0.15).normalized()
			target_fighter.take_damage(damage, knock_dir * 3.5)
			
			# Efeitos de impacto de projétil
			SkillFX.flash(get_parent(), hit_pos, 0.5, bullet_color, 0.1)
			SkillFX.burst(get_parent(), hit_pos, bullet_color, 8, 3.0, 0.2, 0.05)
			SkillFX.shake_camera(self, 0.04, 0.1)
		else:
			# Impacto no cenário/chão
			SkillFX.burst(get_parent(), hit_pos, Color(0.9, 0.85, 0.7), 4, 2.0, 0.15, 0.04)
			
		queue_free()
		return
		
	global_position = end_pos
	distance_traveled += move_step
	if distance_traveled >= max_range:
		queue_free()

