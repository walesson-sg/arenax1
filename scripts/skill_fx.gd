extends RefCounted
## Efeitos visuais das habilidades.
## Só primitivas, materiais aditivos (brilho) e partículas de CPU: leve para a Web.

const COLOR_Q: Color = Color(1.0, 0.55, 0.15) # laranja  (igual ao slot Q)
const COLOR_E: Color = Color(0.62, 0.45, 1.0) # violeta  (igual ao slot E)
const COLOR_F: Color = Color(1.0, 0.25, 0.22) # vermelho (igual ao slot F)
const COLOR_BLOCK: Color = Color(0.18, 0.82, 1.0) # ciano elétrico (bloqueio / defesa)
const COLOR_BLOCK_CORE: Color = Color(0.85, 0.96, 1.0) # brilho central branco-azulado

# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------

static func additive_material(color: Color) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	return mat

static func _glow_mesh(mesh: Mesh, color: Color) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = additive_material(color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

static func _sphere(radius: float, segments: int = 16) -> SphereMesh:
	var m: SphereMesh = SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = segments
	m.rings = maxi(int(segments / 2.0), 4)
	return m

static func shake_camera(from: Node, strength: float, duration: float) -> void:
	var cam: Camera3D = from.get_viewport().get_camera_3d()
	if cam and cam.has_method("shake"):
		cam.call("shake", strength, duration)

# ---------------------------------------------------------------------------
# Efeitos de um disparo (se destroem sozinhos)
# ---------------------------------------------------------------------------

## Anel achatado que se expande no chão.
static func ring(parent: Node, pos: Vector3, radius: float, color: Color, duration: float, delay: float = 0.0) -> void:
	var mesh: TorusMesh = TorusMesh.new()
	mesh.inner_radius = 0.9
	mesh.outer_radius = 1.0
	mesh.rings = 24
	mesh.ring_segments = 6
	var mi: MeshInstance3D = _glow_mesh(mesh, color)
	parent.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3(0.1, 1.0, 0.1)
	mi.visible = delay <= 0.0

	var mat: StandardMaterial3D = mi.material_override as StandardMaterial3D
	var tw: Tween = mi.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
		tw.tween_callback(func() -> void: mi.visible = true)
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius, 1.0, radius), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)

## Esfera que explode e some (flash de impacto).
static func flash(parent: Node, pos: Vector3, radius: float, color: Color, duration: float, y_scale: float = 1.0) -> void:
	var mi: MeshInstance3D = _glow_mesh(_sphere(1.0), color)
	parent.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3(radius * 0.2, radius * 0.2 * y_scale, radius * 0.2)
	var mat: StandardMaterial3D = mi.material_override as StandardMaterial3D
	var tw: Tween = mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius, radius * y_scale, radius), duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration)
	tw.chain().tween_callback(mi.queue_free)

## Rastro (imagem residual) em forma de cápsula.
static func ghost(parent: Node, pos: Vector3, color: Color, duration: float = 0.3) -> void:
	var mesh: CapsuleMesh = CapsuleMesh.new()
	mesh.radius = 0.42
	mesh.height = 1.7
	mesh.radial_segments = 12
	mesh.rings = 3
	var mi: MeshInstance3D = _glow_mesh(mesh, Color(color.r, color.g, color.b, 0.5))
	parent.add_child(mi)
	mi.global_position = pos + Vector3(0, 0.9, 0)
	var mat: StandardMaterial3D = mi.material_override as StandardMaterial3D
	var tw: Tween = mi.create_tween().set_parallel(true)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration)
	tw.tween_property(mi, "scale", Vector3(0.6, 0.9, 0.6), duration)
	tw.chain().tween_callback(mi.queue_free)

## Explosão de faíscas (partículas de CPU, disparo único).
static func burst(parent: Node, pos: Vector3, color: Color, amount: int = 24, speed: float = 6.0,
		lifetime: float = 0.5, size: float = 0.12, upward: bool = false, emit_radius: float = 0.2) -> void:
	var p: CPUParticles3D = _make_particles(color, amount, lifetime, size)
	p.one_shot = true
	p.explosiveness = 1.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = emit_radius
	p.direction = Vector3.UP
	p.spread = 45.0 if upward else 180.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -5.0, 0)
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	parent.get_tree().create_timer(lifetime + 0.6).timeout.connect(p.queue_free)

## Explosão em área para a habilidade E (Onda de Choque / Detonação):
## Combina flash central, cúpula energética expansiva, anéis de choque duplo no chão,
## disco incandescente no solo, anel de impacto aéreo estilo anime,
## centelhas explosivas em 3D, poeira de choque e clarão dinâmico.
static func shockwave_explosion(parent: Node, pos: Vector3, radius: float = 5.0, color: Color = COLOR_E) -> void:
	if parent == null or not is_instance_valid(parent):
		return

	# 1. Flash central brilhante (núcleo branco quente da detonação)
	var core: MeshInstance3D = _glow_mesh(_sphere(1.0, 14), Color(1.0, 0.95, 1.0, 0.95))
	parent.add_child(core)
	core.global_position = pos + Vector3(0, 0.6, 0)
	core.scale = Vector3.ONE * 0.4
	var core_mat: StandardMaterial3D = core.material_override as StandardMaterial3D
	var tw_core: Tween = core.create_tween().set_parallel(true)
	tw_core.tween_property(core, "scale", Vector3.ONE * (radius * 0.5), 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw_core.tween_property(core_mat, "albedo_color:a", 0.0, 0.14)
	tw_core.chain().tween_callback(core.queue_free)

	# 2. Cúpula / Esfera expansiva volumétrica da explosão
	var dome: MeshInstance3D = _glow_mesh(_sphere(1.0, 20), Color(color.r, color.g, color.b, 0.75))
	parent.add_child(dome)
	dome.global_position = pos + Vector3(0, 0.4, 0)
	dome.scale = Vector3(0.3, 0.2, 0.3)
	var dome_mat: StandardMaterial3D = dome.material_override as StandardMaterial3D
	var tw_dome: Tween = dome.create_tween().set_parallel(true)
	tw_dome.tween_property(dome, "scale", Vector3(radius, radius * 0.85, radius), 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw_dome.tween_property(dome_mat, "albedo_color:a", 0.0, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw_dome.chain().tween_callback(dome.queue_free)

	# 3. Anel primário de choque no chão (cor violeta tema do E)
	ring(parent, pos + Vector3(0, 0.05, 0), radius, color, 0.36)

	# 4. Anel secundário veloz (onda sônica branca/plasma)
	ring(parent, pos + Vector3(0, 0.07, 0), radius * 1.15, Color(1.0, 0.88, 1.0, 0.9), 0.26)

	# 5. Disco de energia no solo (marca incandescente da área de impacto)
	var disc_mesh: CylinderMesh = CylinderMesh.new()
	disc_mesh.top_radius = 1.0
	disc_mesh.bottom_radius = 1.0
	disc_mesh.height = 0.02
	disc_mesh.radial_segments = 24
	disc_mesh.rings = 1
	var disc: MeshInstance3D = _glow_mesh(disc_mesh, Color(color.r * 1.1, color.g * 0.9, color.b * 1.2, 0.55))
	parent.add_child(disc)
	disc.global_position = pos + Vector3(0, 0.03, 0)
	disc.scale = Vector3(0.2, 1.0, 0.2)
	var disc_mat: StandardMaterial3D = disc.material_override as StandardMaterial3D
	var tw_disc: Tween = disc.create_tween().set_parallel(true)
	tw_disc.tween_property(disc, "scale", Vector3(radius * 0.9, 1.0, radius * 0.9), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw_disc.tween_property(disc_mat, "albedo_color:a", 0.0, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw_disc.chain().tween_callback(disc.queue_free)

	# 6. Anel aéreo estilo anime (anel de dispersão horizontal)
	var blast_mesh: TorusMesh = TorusMesh.new()
	blast_mesh.inner_radius = 0.88
	blast_mesh.outer_radius = 1.0
	blast_mesh.rings = 24
	blast_mesh.ring_segments = 6
	var blast_ring: MeshInstance3D = _glow_mesh(blast_mesh, Color(color.r, color.g, color.b, 0.85))
	parent.add_child(blast_ring)
	blast_ring.global_position = pos + Vector3(0, 0.8, 0)
	blast_ring.scale = Vector3(0.2, 1.0, 0.2)
	var blast_mat: StandardMaterial3D = blast_ring.material_override as StandardMaterial3D
	var tw_blast: Tween = blast_ring.create_tween().set_parallel(true)
	tw_blast.tween_property(blast_ring, "scale", Vector3(radius * 0.95, 1.2, radius * 0.95), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw_blast.tween_property(blast_mat, "albedo_color:a", 0.0, 0.3)
	tw_blast.chain().tween_callback(blast_ring.queue_free)

	# 7. Centelhas explosivas de energia em 3D
	var sparks: CPUParticles3D = _make_particles(Color(1.0, 0.85, 1.0, 1.0), 38, 0.5, 0.14)
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 0.35
	sparks.direction = Vector3.UP
	sparks.spread = 160.0
	sparks.initial_velocity_min = 8.0
	sparks.initial_velocity_max = 14.0
	sparks.gravity = Vector3(0, -9.0, 0)
	parent.add_child(sparks)
	sparks.global_position = pos + Vector3(0, 0.4, 0)
	sparks.emitting = true
	parent.get_tree().create_timer(0.7).timeout.connect(sparks.queue_free)

	# 8. Onda de poeira e vento rente ao chão
	var dust: CPUParticles3D = _make_particles(Color(0.85, 0.80, 0.95, 0.5), 22, 0.45, 0.18)
	dust.one_shot = true
	dust.explosiveness = 0.95
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	dust.emission_sphere_radius = 0.5
	dust.direction = Vector3.UP
	dust.spread = 85.0
	dust.initial_velocity_min = 4.0
	dust.initial_velocity_max = 8.0
	dust.gravity = Vector3(0, -2.0, 0)
	parent.add_child(dust)
	dust.global_position = pos + Vector3(0, 0.1, 0)
	dust.emitting = true
	parent.get_tree().create_timer(0.65).timeout.connect(dust.queue_free)

	# 9. Clarão de luz dinâmica temporária (ilumina os lutadores e o cenário)
	var light: OmniLight3D = OmniLight3D.new()
	light.light_color = color
	light.light_energy = 5.0
	light.omni_range = radius * 2.5
	light.shadow_enabled = false
	parent.add_child(light)
	light.global_position = pos + Vector3(0, 1.0, 0)
	var tw_l: Tween = light.create_tween()
	tw_l.tween_property(light, "light_energy", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw_l.chain().tween_callback(light.queue_free)

static func _make_particles(color: Color, amount: int, lifetime: float, size: float) -> CPUParticles3D:
	var p: CPUParticles3D = CPUParticles3D.new()
	var particle_mesh: SphereMesh = _sphere(size, 6)
	particle_mesh.material = additive_material(Color.WHITE)
	p.mesh = particle_mesh
	p.amount = amount
	p.lifetime = lifetime
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var grad: Gradient = Gradient.new()
	grad.set_color(0, color)
	grad.set_color(1, Color(color.r, color.g, color.b, 0.0))
	p.color_ramp = grad
	p.local_coords = false
	return p

# ---------------------------------------------------------------------------
# Efeitos de Dash (Arrancada explosiva, Rastro contínuo e Frenagem)
# ---------------------------------------------------------------------------

## Arrancada explosiva no início do Dash:
## Anel de choque no chão + rajada de vento/poeira para trás + cone sônico à frente + tremor
static func dash_launch(parent: Node, pos: Vector3, dir: Vector3, color: Color) -> void:
	if parent == null or not is_instance_valid(parent):
		return

	# 1. Anel de onda de choque branca/vento expandindo no chão
	ring(parent, pos + Vector3(0, 0.04, 0), 2.4, Color(1.0, 1.0, 1.0, 0.8), 0.2)

	# 2. Rajada de poeira e vento impulsionada para trás (direção oposta ao avanço)
	var back_dir: Vector3 = -dir.normalized() if dir.length() > 0.1 else Vector3.BACK
	back_dir.y = 0.35
	back_dir = back_dir.normalized()

	var dust: CPUParticles3D = _make_particles(Color(0.95, 0.92, 0.85, 0.75), 18, 0.32, 0.13)
	dust.one_shot = true
	dust.explosiveness = 0.95
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	dust.emission_sphere_radius = 0.25
	dust.direction = back_dir
	dust.spread = 42.0
	dust.initial_velocity_min = 5.0
	dust.initial_velocity_max = 8.5
	dust.gravity = Vector3(0, -3.5, 0)
	parent.add_child(dust)
	dust.global_position = pos + Vector3(0, 0.2, 0)
	dust.emitting = true
	parent.get_tree().create_timer(0.5).timeout.connect(dust.queue_free)

	# 3. Flash sônico de vento cônico apontado para frente no sentido do dash
	var cone_mesh: CylinderMesh = CylinderMesh.new()
	cone_mesh.top_radius = 0.85
	cone_mesh.bottom_radius = 0.2
	cone_mesh.height = 1.6
	cone_mesh.radial_segments = 16
	cone_mesh.rings = 1
	var cone: MeshInstance3D = _glow_mesh(cone_mesh, Color(color.r, color.g, color.b, 0.5))
	parent.add_child(cone)
	cone.global_position = pos + Vector3(0, 0.85, 0)
	if dir.length() > 0.1:
		cone.rotation.y = atan2(dir.x, dir.z)
	cone.rotation.x = PI * 0.5
	cone.scale = Vector3(0.5, 0.3, 0.5)

	var cone_mat: StandardMaterial3D = cone.material_override as StandardMaterial3D
	var tw: Tween = cone.create_tween().set_parallel(true)
	tw.tween_property(cone, "scale", Vector3(1.7, 1.5, 1.7), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(cone_mat, "albedo_color:a", 0.0, 0.16)
	tw.chain().tween_callback(cone.queue_free)

	# 4. Micro-impacto na câmera para dar peso à arrancada
	shake_camera(parent, 0.06, 0.14)

## Efeito gerado ao longo da trajetória do Dash (rastro deixado por onde ele passa):
## Silhueta fantasma translúcida + linhas de vento (speed streaks) + nuvem de poeira baixa
static func dash_trail_step(parent: Node, pos: Vector3, rot_y: float, color: Color, dir: Vector3) -> void:
	if parent == null or not is_instance_valid(parent):
		return

	# 1. Silhueta residual (ghost afterimage) do personagem
	var root: Node3D = Node3D.new()
	parent.add_child(root)
	root.global_position = pos
	root.rotation.y = rot_y

	# Tronco inclinado da silhueta
	var body_m: CapsuleMesh = CapsuleMesh.new()
	body_m.radius = 0.32
	body_m.height = 1.05
	body_m.radial_segments = 10
	body_m.rings = 2
	var ghost_body: MeshInstance3D = _glow_mesh(body_m, Color(color.r, color.g, color.b, 0.5))
	ghost_body.position = Vector3(0, 0.65, 0)
	ghost_body.rotation.x = 0.3
	root.add_child(ghost_body)

	# Cabeça da silhueta
	var head_m: SphereMesh = _sphere(0.36, 10)
	var ghost_head: MeshInstance3D = _glow_mesh(head_m, Color(color.r, color.g, color.b, 0.5))
	ghost_head.position = Vector3(0, 1.35, 0.12)
	root.add_child(ghost_head)

	# Desaparecimento suave da silhueta (fade out + encolhe levemente)
	var mat_b: StandardMaterial3D = ghost_body.material_override as StandardMaterial3D
	var mat_h: StandardMaterial3D = ghost_head.material_override as StandardMaterial3D
	var tw: Tween = root.create_tween().set_parallel(true)
	tw.tween_property(root, "scale", Vector3(0.7, 0.85, 0.7), 0.24).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat_b, "albedo_color:a", 0.0, 0.24)
	tw.tween_property(mat_h, "albedo_color:a", 0.0, 0.24)
	tw.chain().tween_callback(root.queue_free)

	# 2. Linhas de velocidade de vento (speed streaks) nas laterais
	var side: Vector3 = Vector3(-dir.z, 0.0, dir.x).normalized() if dir.length() > 0.1 else Vector3.RIGHT
	for offset_sign in [-1.0, 1.0]:
		var streak_pos: Vector3 = pos + side * (0.38 * offset_sign) + Vector3(0, 0.45 + randf_range(-0.12, 0.12), 0)
		var streak: MeshInstance3D = _glow_mesh(_sphere(0.06, 6), Color(1.0, 1.0, 1.0, 0.6))
		parent.add_child(streak)
		streak.global_position = streak_pos
		streak.scale = Vector3(0.5, 0.5, 2.4)
		if dir.length() > 0.1:
			streak.rotation.y = atan2(dir.x, dir.z)
		var s_mat: StandardMaterial3D = streak.material_override as StandardMaterial3D
		var tw_s: Tween = streak.create_tween().set_parallel(true)
		tw_s.tween_property(streak, "scale:z", 0.2, 0.18)
		tw_s.tween_property(s_mat, "albedo_color:a", 0.0, 0.18)
		tw_s.chain().tween_callback(streak.queue_free)

	# 3. Nuvem de poeira levantada no chão
	var puff_m: SphereMesh = _sphere(0.18, 6)
	var puff: MeshInstance3D = _glow_mesh(puff_m, Color(0.92, 0.89, 0.82, 0.4))
	parent.add_child(puff)
	puff.global_position = pos + Vector3(randf_range(-0.15, 0.15), 0.08, randf_range(-0.15, 0.15))
	var p_mat: StandardMaterial3D = puff.material_override as StandardMaterial3D
	var tw_p: Tween = puff.create_tween().set_parallel(true)
	tw_p.tween_property(puff, "scale", Vector3(2.2, 1.2, 2.2), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw_p.tween_property(puff, "position:y", puff.position.y + 0.14, 0.22)
	tw_p.tween_property(p_mat, "albedo_color:a", 0.0, 0.22)
	tw_p.chain().tween_callback(puff.queue_free)

## Frenagem suave ao final do Dash: marquinhas de poeira nas laterais
static func dash_brake(parent: Node, pos: Vector3, dir: Vector3) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var side: Vector3 = Vector3(-dir.z, 0.0, dir.x).normalized() if dir.length() > 0.1 else Vector3.RIGHT
	for offset_sign in [-1.0, 1.0]:
		var puff_pos: Vector3 = pos + side * (0.35 * offset_sign) + Vector3(0, 0.08, 0)
		var puff: MeshInstance3D = _glow_mesh(_sphere(0.2, 6), Color(0.9, 0.88, 0.82, 0.45))
		parent.add_child(puff)
		puff.global_position = puff_pos
		var p_mat: StandardMaterial3D = puff.material_override as StandardMaterial3D
		var tw: Tween = puff.create_tween().set_parallel(true)
		tw.tween_property(puff, "scale", Vector3(1.9, 0.8, 1.9), 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(p_mat, "albedo_color:a", 0.0, 0.2)
		tw.chain().tween_callback(puff.queue_free)

# ---------------------------------------------------------------------------
# Efeitos de Deslize (Slide) e Queda Rápida (Fast Fall)
# ---------------------------------------------------------------------------

## Efeito visual ativado ao pressionar Ctrl no ar após SHIFT+Space (Fast Fall):
## Feixes sônicos ascendentes de vento e anel de compressão no ar
static func fast_fall_fx(parent: Node, pos: Vector3, color: Color) -> void:
	if parent == null or not is_instance_valid(parent):
		return

	# 1. Anel sônico achatado que se dissipa rapidamente
	ring(parent, pos + Vector3(0, 0.2, 0), 1.9, Color(1.0, 1.0, 1.0, 0.8), 0.18)

	# 2. Feixes de ar verticais (speed streaks para cima indicando queda acelerada brusca)
	for i in range(4):
		var angle: float = (PI * 0.5) * float(i) + randf_range(-0.25, 0.25)
		var offset: Vector3 = Vector3(cos(angle) * 0.42, 0.1, sin(angle) * 0.42)
		var streak: MeshInstance3D = _glow_mesh(_sphere(0.06, 6), Color(color.r, color.g, color.b, 0.65))
		parent.add_child(streak)
		streak.global_position = pos + offset
		streak.scale = Vector3(0.4, 3.2, 0.4)
		var s_mat: StandardMaterial3D = streak.material_override as StandardMaterial3D
		var tw: Tween = streak.create_tween().set_parallel(true)
		tw.tween_property(streak, "position:y", streak.position.y + 1.25, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(streak, "scale:y", 0.25, 0.18)
		tw.tween_property(s_mat, "albedo_color:a", 0.0, 0.18)
		tw.chain().tween_callback(streak.queue_free)

	# 3. Pequeno tremor na câmera
	shake_camera(parent, 0.06, 0.14)

## Efeito de impacto e fricção ao tocar no solo deslizando (Slide Start):
## Anel de atrito no solo + rajadas laterais de faíscas e poeira rasteira
static func slide_start_impact(parent: Node, pos: Vector3, dir: Vector3, color: Color) -> void:
	if parent == null or not is_instance_valid(parent):
		return

	# 1. Anel no solo
	ring(parent, pos + Vector3(0, 0.04, 0), 2.3, Color(1.0, 1.0, 1.0, 0.85), 0.22)

	# 2. Rajada de faíscas brilhantes de atrito para trás e laterais
	var back_dir: Vector3 = -dir.normalized() if dir.length() > 0.1 else Vector3.BACK
	back_dir.y = 0.28
	back_dir = back_dir.normalized()

	var sparks: CPUParticles3D = _make_particles(Color(1.0, 0.86, 0.35), 18, 0.32, 0.1)
	sparks.one_shot = true
	sparks.explosiveness = 0.95
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 0.22
	sparks.direction = back_dir
	sparks.spread = 55.0
	sparks.initial_velocity_min = 4.2
	sparks.initial_velocity_max = 8.0
	sparks.gravity = Vector3(0, -5.0, 0)
	parent.add_child(sparks)
	sparks.global_position = pos + Vector3(0, 0.1, 0)
	sparks.emitting = true
	parent.get_tree().create_timer(0.45).timeout.connect(sparks.queue_free)

	# 3. Baforadas de poeira nas laterais
	var side: Vector3 = Vector3(-dir.z, 0.0, dir.x).normalized() if dir.length() > 0.1 else Vector3.RIGHT
	for s_sign in [-1.0, 1.0]:
		var puff_pos: Vector3 = pos + side * (0.42 * s_sign) + Vector3(0, 0.06, 0)
		var puff: MeshInstance3D = _glow_mesh(_sphere(0.24, 6), Color(0.92, 0.89, 0.82, 0.5))
		parent.add_child(puff)
		puff.global_position = puff_pos
		var p_mat: StandardMaterial3D = puff.material_override as StandardMaterial3D
		var tw: Tween = puff.create_tween().set_parallel(true)
		tw.tween_property(puff, "scale", Vector3(2.5, 0.85, 2.5), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(p_mat, "albedo_color:a", 0.0, 0.25)
		tw.chain().tween_callback(puff.queue_free)

## Efeito contínuo a cada passo do Deslize (faíscas de fricção e esteira de poeira):
static func slide_trail_step(parent: Node, pos: Vector3, dir: Vector3, color: Color) -> void:
	if parent == null or not is_instance_valid(parent):
		return

	# 1. Faísca rápida de atrito saindo do contato com o solo
	var spark_mesh: SphereMesh = _sphere(0.08, 5)
	var spark: MeshInstance3D = _glow_mesh(spark_mesh, Color(1.0, 0.82, 0.28, 0.85))
	parent.add_child(spark)
	spark.global_position = pos + Vector3(randf_range(-0.16, 0.16), 0.05, randf_range(-0.16, 0.16))
	spark.scale = Vector3(0.5, 0.5, 1.5)
	if dir.length() > 0.1:
		spark.rotation.y = atan2(dir.x, dir.z)
	var s_mat: StandardMaterial3D = spark.material_override as StandardMaterial3D
	var tw_sp: Tween = spark.create_tween().set_parallel(true)
	tw_sp.tween_property(spark, "position", spark.position - dir * 0.45 + Vector3(0, 0.08, 0), 0.14).set_trans(Tween.TRANS_QUAD)
	tw_sp.tween_property(s_mat, "albedo_color:a", 0.0, 0.14)
	tw_sp.chain().tween_callback(spark.queue_free)

	# 2. Nuvem de poeira baixa e rasteira
	var puff_m: SphereMesh = _sphere(0.16, 5)
	var puff: MeshInstance3D = _glow_mesh(puff_m, Color(0.9, 0.87, 0.8, 0.35))
	parent.add_child(puff)
	puff.global_position = pos + Vector3(randf_range(-0.18, 0.18), 0.06, randf_range(-0.18, 0.18))
	var p_mat: StandardMaterial3D = puff.material_override as StandardMaterial3D
	var tw_p: Tween = puff.create_tween().set_parallel(true)
	tw_p.tween_property(puff, "scale", Vector3(1.9, 0.75, 1.9), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw_p.tween_property(p_mat, "albedo_color:a", 0.0, 0.22)
	tw_p.chain().tween_callback(puff.queue_free)

# ---------------------------------------------------------------------------
# Aura da Ultimate (contínua enquanto canaliza)
# ---------------------------------------------------------------------------

## Cria a aura. A origem do nó fica no centro do corpo (y = 0.9 acima dos pés).
static func create_ult_aura(color: Color = COLOR_F) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "UltAura"

	# Casca externa (elipsoide envolvendo o corpo)
	var shell: MeshInstance3D = _glow_mesh(_sphere(1.0, 20), Color(color.r, color.g, color.b, 0.30))
	shell.scale = Vector3(0.95, 1.35, 0.95)
	root.add_child(shell)
	_pulse(shell, Vector3(0.95, 1.35, 0.95), 1.12, 0.35)

	# Casca interna, mais quente e brilhante
	var core_color: Color = Color(1.0, 0.7, 0.35, 0.28)
	var inner: MeshInstance3D = _glow_mesh(_sphere(1.0, 16), core_color)
	inner.scale = Vector3(0.7, 1.1, 0.7)
	root.add_child(inner)
	_pulse(inner, Vector3(0.7, 1.1, 0.7), 1.2, 0.22)

	# Coluna de energia subindo do chão
	var pillar_mesh: CylinderMesh = CylinderMesh.new()
	pillar_mesh.top_radius = 0.7
	pillar_mesh.bottom_radius = 1.1
	pillar_mesh.height = 6.0
	pillar_mesh.radial_segments = 20
	pillar_mesh.rings = 1
	var pillar: MeshInstance3D = _glow_mesh(pillar_mesh, Color(color.r, color.g, color.b, 0.14))
	pillar.position = Vector3(0, 3.0 - 0.9, 0)
	root.add_child(pillar)
	_pulse(pillar, Vector3.ONE, 1.15, 0.28)

	# Círculo no chão (disco + borda)
	var disc_mesh: CylinderMesh = CylinderMesh.new()
	disc_mesh.top_radius = 1.6
	disc_mesh.bottom_radius = 1.6
	disc_mesh.height = 0.02
	disc_mesh.radial_segments = 28
	disc_mesh.rings = 1
	var disc: MeshInstance3D = _glow_mesh(disc_mesh, Color(color.r, color.g, color.b, 0.35))
	disc.position = Vector3(0, -0.86, 0)
	root.add_child(disc)
	_pulse(disc, Vector3.ONE, 1.18, 0.25)

	var edge_mesh: TorusMesh = TorusMesh.new()
	edge_mesh.inner_radius = 1.52
	edge_mesh.outer_radius = 1.62
	edge_mesh.rings = 28
	edge_mesh.ring_segments = 6
	var edge: MeshInstance3D = _glow_mesh(edge_mesh, Color(1.0, 0.85, 0.6, 0.9))
	edge.position = Vector3(0, -0.85, 0)
	root.add_child(edge)
	_pulse(edge, Vector3.ONE, 1.18, 0.25)

	# Partículas subindo ao redor do corpo
	var sparks: CPUParticles3D = _make_particles(Color(1.0, 0.6, 0.3), 36, 0.9, 0.09)
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	sparks.emission_sphere_radius = 1.0
	sparks.direction = Vector3.UP
	sparks.spread = 12.0
	sparks.initial_velocity_min = 2.0
	sparks.initial_velocity_max = 4.5
	sparks.gravity = Vector3.ZERO
	sparks.position = Vector3(0, -0.6, 0)
	sparks.emitting = true
	root.add_child(sparks)

	# Luz vermelha que ilumina a arena em volta
	var light: OmniLight3D = OmniLight3D.new()
	light.light_color = color
	light.light_energy = 0.0
	light.omni_range = 7.0
	light.shadow_enabled = false
	root.add_child(light)
	root.set_meta("light", light)

	return root

static func _pulse(node: Node3D, base_scale: Vector3, amount: float, half_period: float) -> void:
	var tw: Tween = node.create_tween().set_loops()
	tw.tween_property(node, "scale", base_scale * amount, half_period).set_trans(Tween.TRANS_SINE)
	tw.tween_property(node, "scale", base_scale, half_period).set_trans(Tween.TRANS_SINE)

## Faz a aura crescer e a luz ficar mais forte durante a carga.
static func charge_aura(aura: Node3D, duration: float) -> void:
	aura.scale = Vector3.ONE * 0.45
	var tw: Tween = aura.create_tween().set_parallel(true)
	tw.tween_property(aura, "scale", Vector3.ONE * 1.15, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var light: OmniLight3D = aura.get_meta("light") as OmniLight3D
	if light:
		tw.tween_property(light, "light_energy", 4.5, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

## Explosão final da aura ao disparar (cresce e some).
static func release_aura(aura: Node3D) -> void:
	if aura == null or not is_instance_valid(aura):
		return
	var tw: Tween = aura.create_tween().set_parallel(true)
	tw.tween_property(aura, "scale", aura.scale * 1.9, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var light: OmniLight3D = aura.get_meta("light") as OmniLight3D
	if light:
		tw.tween_property(light, "light_energy", 0.0, 0.25)
	for child: Node in aura.get_children():
		var mi: MeshInstance3D = child as MeshInstance3D
		if mi:
			var mat: StandardMaterial3D = mi.material_override as StandardMaterial3D
			if mat:
				tw.tween_property(mat, "albedo_color:a", 0.0, 0.22)
		var sparks: CPUParticles3D = child as CPUParticles3D
		if sparks:
			sparks.emitting = false
	tw.chain().tween_callback(aura.queue_free)

# ---------------------------------------------------------------------------
# Escudo de Bloqueio (Defesa ativa)
# ---------------------------------------------------------------------------

## Cria o escudo de bloqueio anexado ao nó visuals do lutador.
static func create_block_shield(parent: Node3D) -> Node3D:
	if parent == null or not is_instance_valid(parent):
		return null

	var root: Node3D = Node3D.new()
	root.name = "BlockShield"
	parent.add_child(root)
	root.position = Vector3(0.0, 0.95, 0.55)

	# 1. Cúpula principal de energia frontal (lente convexa de plasma protetor)
	var dome_mesh: SphereMesh = SphereMesh.new()
	dome_mesh.radius = 0.72
	dome_mesh.height = 1.44
	dome_mesh.radial_segments = 20
	dome_mesh.rings = 10
	var dome: MeshInstance3D = _glow_mesh(dome_mesh, Color(COLOR_BLOCK.r, COLOR_BLOCK.g, COLOR_BLOCK.b, 0.35))
	dome.scale = Vector3(1.0, 1.15, 0.22)
	root.add_child(dome)
	root.set_meta("dome", dome)

	# 2. Aro externo reforçado (borda do escudo de energia)
	var rim_mesh: TorusMesh = TorusMesh.new()
	rim_mesh.inner_radius = 0.70
	rim_mesh.outer_radius = 0.78
	rim_mesh.rings = 24
	rim_mesh.ring_segments = 6
	var rim: MeshInstance3D = _glow_mesh(rim_mesh, Color(COLOR_BLOCK.r, COLOR_BLOCK.g, COLOR_BLOCK.b, 0.9))
	rim.rotation_degrees.x = 90.0
	root.add_child(rim)

	# 3. Anel concêntrico interno mais brilhante (núcleo da barreira)
	var inner_rim_mesh: TorusMesh = TorusMesh.new()
	inner_rim_mesh.inner_radius = 0.38
	inner_rim_mesh.outer_radius = 0.44
	inner_rim_mesh.rings = 20
	inner_rim_mesh.ring_segments = 5
	var inner_rim: MeshInstance3D = _glow_mesh(inner_rim_mesh, Color(COLOR_BLOCK_CORE.r, COLOR_BLOCK_CORE.g, COLOR_BLOCK_CORE.b, 0.85))
	inner_rim.rotation_degrees.x = 90.0
	root.add_child(inner_rim)
	root.set_meta("inner_rim", inner_rim)

	# 4. Marcadores geométricos de campo de força nas 4 pontas
	for deg in [0.0, 90.0, 180.0, 270.0]:
		var notch_mesh: BoxMesh = BoxMesh.new()
		notch_mesh.size = Vector3(0.12, 0.045, 0.03)
		var notch: MeshInstance3D = _glow_mesh(notch_mesh, Color(COLOR_BLOCK_CORE.r, COLOR_BLOCK_CORE.g, COLOR_BLOCK_CORE.b, 0.95))
		notch.rotation_degrees.z = deg
		var rad: float = deg_to_rad(deg)
		notch.position = Vector3(cos(rad) * 0.74, sin(rad) * 0.74, 0.0)
		root.add_child(notch)

	# 5. Círculo de ancoragem no solo sob os pés do personagem
	var ground_ring_mesh: TorusMesh = TorusMesh.new()
	ground_ring_mesh.inner_radius = 0.85
	ground_ring_mesh.outer_radius = 0.92
	ground_ring_mesh.rings = 24
	ground_ring_mesh.ring_segments = 6
	var ground_ring: MeshInstance3D = _glow_mesh(ground_ring_mesh, Color(COLOR_BLOCK.r, COLOR_BLOCK.g, COLOR_BLOCK.b, 0.45))
	ground_ring.position = Vector3(0.0, -0.93, -0.25)
	root.add_child(ground_ring)

	# 6. Partículas de energia ascendente pelo escudo
	var motes: CPUParticles3D = _make_particles(COLOR_BLOCK_CORE, 14, 0.4, 0.08)
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents = Vector3(0.5, 0.5, 0.1)
	motes.direction = Vector3.UP
	motes.spread = 20.0
	motes.initial_velocity_min = 1.0
	motes.initial_velocity_max = 2.2
	motes.gravity = Vector3.ZERO
	root.add_child(motes)
	motes.emitting = true
	root.set_meta("motes", motes)

	# 7. Luz suave frontal iluminando o personagem e o chão
	var light: OmniLight3D = OmniLight3D.new()
	light.light_color = COLOR_BLOCK
	light.light_energy = 1.8
	light.omni_range = 3.5
	light.shadow_enabled = false
	root.add_child(light)
	root.set_meta("light", light)

	# Animação contínua sutil de pulso / oscilação energética (idle da defesa)
	var tw_loop: Tween = root.create_tween().set_loops()
	tw_loop.tween_property(dome, "scale", Vector3(1.04, 1.18, 0.23), 0.38).set_trans(Tween.TRANS_SINE)
	tw_loop.tween_property(dome, "scale", Vector3(0.96, 1.12, 0.21), 0.38).set_trans(Tween.TRANS_SINE)

	var tw_inner: Tween = inner_rim.create_tween().set_loops()
	tw_inner.tween_property(inner_rim, "scale", Vector3.ONE * 1.08, 0.3).set_trans(Tween.TRANS_SINE)
	tw_inner.tween_property(inner_rim, "scale", Vector3.ONE * 0.94, 0.3).set_trans(Tween.TRANS_SINE)

	# Animação de ativação explosiva e responsiva (pop-in imediato com flash)
	root.scale = Vector3.ONE * 0.15
	var tw_spawn: Tween = root.create_tween()
	tw_spawn.tween_property(root, "scale", Vector3.ONE * 1.18, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw_spawn.tween_property(root, "scale", Vector3.ONE, 0.06).set_trans(Tween.TRANS_SINE)

	# Micro-flash de impacto no ponto de ativação
	flash(parent, root.global_position, 0.9, COLOR_BLOCK, 0.12)

	return root

## Desativa e remove suavemente o escudo com animação de dissipação.
static func dismiss_block_shield(shield: Node3D) -> void:
	if shield == null or not is_instance_valid(shield):
		return

	var motes: CPUParticles3D = shield.get_meta("motes", null) as CPUParticles3D
	if motes and is_instance_valid(motes):
		motes.emitting = false

	var light: OmniLight3D = shield.get_meta("light", null) as OmniLight3D

	var tw: Tween = shield.create_tween().set_parallel(true)
	tw.tween_property(shield, "scale", Vector3.ONE * 0.1, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if light and is_instance_valid(light):
		tw.tween_property(light, "light_energy", 0.0, 0.09)

	for child: Node in shield.get_children():
		var mi: MeshInstance3D = child as MeshInstance3D
		if mi and mi.material_override is StandardMaterial3D:
			var mat: StandardMaterial3D = mi.material_override as StandardMaterial3D
			tw.tween_property(mat, "albedo_color:a", 0.0, 0.09)

	tw.chain().tween_callback(shield.queue_free)

## Reação visual do escudo ao absorver um impacto / golpe.
static func block_hit_reaction(shield: Node3D, hit_pos: Vector3) -> void:
	if shield == null or not is_instance_valid(shield):
		return

	var parent: Node = shield.get_parent()
	var scene_root: Node = parent.get_parent() if parent else shield

	# 1. Onda sônica de impacto circular que reverbera na superfície do escudo
	ring(scene_root, hit_pos, 1.25, COLOR_BLOCK, 0.18)

	# 2. Explosão de centelhas energéticas concentradas no ponto do impacto
	burst(scene_root, hit_pos, COLOR_BLOCK_CORE, 16, 5.5, 0.28, 0.1, false, 0.15)

	# 3. Deformação elástica do escudo (comprime para trás e rebate)
	var dome: MeshInstance3D = shield.get_meta("dome", null) as MeshInstance3D
	if dome and is_instance_valid(dome):
		var tw_deform: Tween = dome.create_tween()
		tw_deform.tween_property(dome, "scale", Vector3(1.2, 1.25, 0.12), 0.04).set_trans(Tween.TRANS_QUAD)
		tw_deform.tween_property(dome, "scale", Vector3(1.0, 1.15, 0.22), 0.14).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	# 4. Clarão momentâneo de absorção na luz do escudo
	var light: OmniLight3D = shield.get_meta("light", null) as OmniLight3D
	if light and is_instance_valid(light):
		var tw_l: Tween = light.create_tween()
		light.light_energy = 4.2
		tw_l.tween_property(light, "light_energy", 1.8, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 5. Micro-tremor de impacto
	shake_camera(shield, 0.05, 0.12)

# ---------------------------------------------------------------------------
# Efeito de Acerto da Investida (Habilidade Q)
# ---------------------------------------------------------------------------

## Impacto visual épico ao acertar a Investida (Q):
## Combina flash central com duplo núcleo brilhante, anel de choque anime transversal orientado no sentido do golpe,
## anéis sônicos concêntricos no solo, feixes de choque radiais em cruz,
## rajada volumétrica de centelhas/faíscas espirrando para trás do alvo e tremor de tela vigoroso.
static func charge_hit_impact(parent: Node, hit_pos: Vector3, dir: Vector3, blocked: bool = false) -> void:
	if parent == null or not is_instance_valid(parent):
		return

	var main_color: Color = COLOR_BLOCK if blocked else COLOR_Q
	var forward_dir: Vector3 = dir.normalized() if dir.length() > 0.05 else Vector3.FORWARD

	# 1. Flash central de impacto (núcleo super brilhante)
	var core: MeshInstance3D = _glow_mesh(_sphere(0.9, 14), Color.WHITE if not blocked else COLOR_BLOCK_CORE)
	parent.add_child(core)
	core.global_position = hit_pos
	core.scale = Vector3.ONE * 0.3
	var core_mat: StandardMaterial3D = core.material_override as StandardMaterial3D
	var tw_core: Tween = core.create_tween().set_parallel(true)
	tw_core.tween_property(core, "scale", Vector3.ONE * 1.6, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw_core.tween_property(core_mat, "albedo_color:a", 0.0, 0.14)
	tw_core.chain().tween_callback(core.queue_free)

	# 2. Cúpula esférica de energia que expande e dissipa
	var aura_sphere: MeshInstance3D = _glow_mesh(_sphere(1.0, 16), Color(main_color.r, main_color.g, main_color.b, 0.75))
	parent.add_child(aura_sphere)
	aura_sphere.global_position = hit_pos
	aura_sphere.scale = Vector3.ONE * 0.4
	var aura_mat: StandardMaterial3D = aura_sphere.material_override as StandardMaterial3D
	var tw_aura: Tween = aura_sphere.create_tween().set_parallel(true)
	tw_aura.tween_property(aura_sphere, "scale", Vector3.ONE * 2.3, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw_aura.tween_property(aura_mat, "albedo_color:a", 0.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw_aura.chain().tween_callback(aura_sphere.queue_free)

	# 3. Anel de choque frontal estilo anime perpendicular à investida
	var ring_mesh: TorusMesh = TorusMesh.new()
	ring_mesh.inner_radius = 0.86
	ring_mesh.outer_radius = 1.0
	ring_mesh.rings = 24
	ring_mesh.ring_segments = 6
	var shock_ring: MeshInstance3D = _glow_mesh(ring_mesh, Color(1.0, 0.9, 0.4, 0.95) if not blocked else Color(0.85, 0.96, 1.0, 0.95))
	parent.add_child(shock_ring)
	shock_ring.global_position = hit_pos
	shock_ring.scale = Vector3(0.3, 1.2, 0.3)
	if absf(forward_dir.y) < 0.99:
		shock_ring.look_at(hit_pos + forward_dir, Vector3.UP)
		shock_ring.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	var ring_mat: StandardMaterial3D = shock_ring.material_override as StandardMaterial3D
	var tw_ring: Tween = shock_ring.create_tween().set_parallel(true)
	tw_ring.tween_property(shock_ring, "scale", Vector3(2.6, 1.6, 2.6), 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw_ring.tween_property(ring_mat, "albedo_color:a", 0.0, 0.24)
	tw_ring.chain().tween_callback(shock_ring.queue_free)

	# 4. Anéis secundários de choque no chão
	var floor_y: float = 0.05
	ring(parent, Vector3(hit_pos.x, floor_y, hit_pos.z), 2.8, main_color, 0.26)
	ring(parent, Vector3(hit_pos.x, floor_y + 0.02, hit_pos.z), 3.4, Color.WHITE if not blocked else COLOR_BLOCK_CORE, 0.20)

	# 5. Feixes radiais de impacto (estrela/cruz de impacto cartum)
	for i in range(4):
		var beam_mesh: BoxMesh = BoxMesh.new()
		beam_mesh.size = Vector3(0.08, 0.08, 1.4)
		var beam: MeshInstance3D = _glow_mesh(beam_mesh, Color(1.0, 0.85, 0.3, 0.9) if not blocked else COLOR_BLOCK_CORE)
		parent.add_child(beam)
		beam.global_position = hit_pos
		var angle: float = (PI * 0.5) * float(i) + (PI * 0.25)
		if absf(forward_dir.y) < 0.99:
			beam.look_at(hit_pos + forward_dir, Vector3.UP)
			beam.rotate_object_local(Vector3.FORWARD, angle)
		beam.scale = Vector3(0.4, 0.4, 0.3)
		var b_mat: StandardMaterial3D = beam.material_override as StandardMaterial3D
		var tw_b: Tween = beam.create_tween().set_parallel(true)
		tw_b.tween_property(beam, "scale", Vector3(1.2, 1.2, 2.2), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw_b.tween_property(b_mat, "albedo_color:a", 0.0, 0.16)
		tw_b.chain().tween_callback(beam.queue_free)

	# 6. Partículas direcionais: centelhas e faíscas espirrando para trás do alvo
	var blast_dir: Vector3 = (forward_dir * 0.85 + Vector3.UP * 0.25).normalized()
	var sparks_color: Color = Color(1.0, 0.75, 0.2) if not blocked else Color(0.4, 0.9, 1.0)
	var sparks: CPUParticles3D = _make_particles(sparks_color, 28, 0.4, 0.13)
	sparks.one_shot = true
	sparks.explosiveness = 0.95
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 0.22
	sparks.direction = blast_dir
	sparks.spread = 48.0
	sparks.initial_velocity_min = 8.0
	sparks.initial_velocity_max = 15.0
	sparks.gravity = Vector3(0, -6.0, 0)
	parent.add_child(sparks)
	sparks.global_position = hit_pos
	sparks.emitting = true
	parent.get_tree().create_timer(0.6).timeout.connect(sparks.queue_free)

	# Faíscas secundárias brancas no núcleo
	var core_sparks: CPUParticles3D = _make_particles(Color.WHITE, 16, 0.3, 0.10)
	core_sparks.one_shot = true
	core_sparks.explosiveness = 1.0
	core_sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	core_sparks.emission_sphere_radius = 0.15
	core_sparks.direction = Vector3.UP
	core_sparks.spread = 180.0
	core_sparks.initial_velocity_min = 4.0
	core_sparks.initial_velocity_max = 8.0
	core_sparks.gravity = Vector3(0, -8.0, 0)
	parent.add_child(core_sparks)
	core_sparks.global_position = hit_pos
	core_sparks.emitting = true
	parent.get_tree().create_timer(0.5).timeout.connect(core_sparks.queue_free)

	# 7. Tremor de tela na câmera
	if blocked:
		shake_camera(parent, 0.10, 0.16)
	else:
		shake_camera(parent, 0.22, 0.28)

