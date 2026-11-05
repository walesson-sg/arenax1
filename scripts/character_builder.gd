extends RefCounted
## Monta o modelo cartoon (chibi) dos personagens usando apenas formas primitivas.
## Suporta as classes LUTADOR e PISTOLEIRO com armas e detalhes únicos.

const BODY_Y: float = 0.9 # altura da origem do nó "Body" (usado nas animações)
const HIP_Y: float = 0.62 # altura do quadril (pivô das pernas)

const OUTLINE_SHADER_CODE: String = """
shader_type spatial;
render_mode cull_front, unshaded;
uniform vec4 outline_color : source_color = vec4(0.09, 0.06, 0.10, 1.0);
uniform float width = 0.022;
void vertex() {
	VERTEX += NORMAL * width;
}
void fragment() {
	ALBEDO = outline_color.rgb;
}
"""

static var _outline_material: ShaderMaterial = null

static func _get_outline_material() -> ShaderMaterial:
	if _outline_material == null:
		var shader: Shader = Shader.new()
		shader.code = OUTLINE_SHADER_CODE
		_outline_material = ShaderMaterial.new()
		_outline_material.shader = shader
	return _outline_material

static func _make_material(color: Color, outline: bool) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if outline:
		mat.next_pass = _get_outline_material()
	return mat

static func _sphere(radius: float) -> SphereMesh:
	var m: SphereMesh = SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 20
	m.rings = 10
	return m

static func _capsule(radius: float, height: float) -> CapsuleMesh:
	var m: CapsuleMesh = CapsuleMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 16
	m.rings = 4
	return m

static func _cylinder(radius: float, height: float) -> CylinderMesh:
	var m: CylinderMesh = CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = 18
	m.rings = 1
	return m

static func _box(size: Vector3) -> BoxMesh:
	var m: BoxMesh = BoxMesh.new()
	m.size = size
	return m

## Cria uma peça. `pos` está em coordenadas do personagem (pés em y = 0).
## Peças filhas de "Body" são deslocadas para a origem do Body.
static func _part(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, outline: bool = true,
		part_scale: Vector3 = Vector3.ONE, rot_deg: Vector3 = Vector3.ZERO, is_body_child: bool = true) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _make_material(color, outline)
	mi.position = pos - Vector3(0.0, BODY_Y if is_body_child else 0.0, 0.0)
	mi.scale = part_scale
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi

## Monta uma pistola estilizada presa à mão
static func _attach_pistol(parent: Node3D, color_metal: Color, color_grip: Color) -> Node3D:
	var gun_pivot: Node3D = Node3D.new()
	gun_pivot.name = "Pistol"
	parent.add_child(gun_pivot)

	# Empunhadura de madeira
	var grip: MeshInstance3D = MeshInstance3D.new()
	grip.mesh = _box(Vector3(0.05, 0.13, 0.07))
	grip.material_override = _make_material(color_grip, false)
	grip.position = Vector3(0.0, -0.06, 0.0)
	grip.rotation_degrees.x = -15.0
	gun_pivot.add_child(grip)

	# Corpo do ferrolho / armação
	var frame: MeshInstance3D = MeshInstance3D.new()
	frame.mesh = _box(Vector3(0.065, 0.08, 0.22))
	frame.material_override = _make_material(color_metal, true)
	frame.position = Vector3(0.0, 0.02, 0.06)
	gun_pivot.add_child(frame)

	# Cano cilíndrico metálico frontal
	var barrel: MeshInstance3D = MeshInstance3D.new()
	barrel.mesh = _cylinder(0.028, 0.18)
	barrel.material_override = _make_material(color_metal.lightened(0.15), true)
	barrel.rotation_degrees.x = 90.0
	barrel.position = Vector3(0.0, 0.03, 0.22)
	gun_pivot.add_child(barrel)

	# Mira superior
	var sight: MeshInstance3D = MeshInstance3D.new()
	sight.mesh = _box(Vector3(0.018, 0.03, 0.03))
	sight.material_override = _make_material(Color(0.85, 0.75, 0.2), false)
	sight.position = Vector3(0.0, 0.075, 0.28)
	gun_pivot.add_child(sight)

	return gun_pivot

## Cria o modelo do Rifle Longo para a habilidade F
static func build_long_rifle() -> Node3D:
	var rifle: Node3D = Node3D.new()
	rifle.name = "LongRifle"

	var metal_dark: Color = Color(0.2, 0.22, 0.26)
	var metal_barrel: Color = Color(0.35, 0.38, 0.44)
	var wood_stock: Color = Color(0.42, 0.24, 0.14)
	var brass: Color = Color(0.88, 0.72, 0.25)

	# Coronha longa de madeira
	var stock: MeshInstance3D = MeshInstance3D.new()
	stock.mesh = _box(Vector3(0.06, 0.12, 0.48))
	stock.material_override = _make_material(wood_stock, true)
	stock.position = Vector3(0.0, -0.04, -0.25)
	stock.rotation_degrees.x = 6.0
	rifle.add_child(stock)

	# Caixa de culatra / corpo mecânico
	var receiver: MeshInstance3D = MeshInstance3D.new()
	receiver.mesh = _box(Vector3(0.07, 0.10, 0.35))
	receiver.material_override = _make_material(metal_dark, true)
	receiver.position = Vector3(0.0, 0.03, 0.12)
	rifle.add_child(receiver)

	# Cano longo de precisão
	var barrel: MeshInstance3D = MeshInstance3D.new()
	barrel.mesh = _cylinder(0.026, 0.95)
	barrel.material_override = _make_material(metal_barrel, true)
	barrel.rotation_degrees.x = 90.0
	barrel.position = Vector3(0.0, 0.04, 0.75)
	rifle.add_child(barrel)

	# Freio de boca / ponta do cano
	var muzzle: MeshInstance3D = MeshInstance3D.new()
	muzzle.mesh = _cylinder(0.035, 0.08)
	muzzle.material_override = _make_material(brass, false)
	muzzle.rotation_degrees.x = 90.0
	muzzle.position = Vector3(0.0, 0.04, 1.25)
	rifle.add_child(muzzle)

	# Luneta telescópica / Mira de sniper no topo
	var scope: MeshInstance3D = MeshInstance3D.new()
	scope.mesh = _cylinder(0.032, 0.28)
	scope.material_override = _make_material(metal_dark.darkened(0.2), true)
	scope.rotation_degrees.x = 90.0
	scope.position = Vector3(0.0, 0.11, 0.14)
	rifle.add_child(scope)

	# Lente da mira telescópica (brilho ciano suave)
	var lens: MeshInstance3D = MeshInstance3D.new()
	lens.mesh = _cylinder(0.028, 0.02)
	var mat_lens: StandardMaterial3D = StandardMaterial3D.new()
	mat_lens.albedo_color = Color(0.2, 0.85, 1.0, 0.9)
	mat_lens.emission_enabled = true
	mat_lens.emission = Color(0.2, 0.85, 1.0)
	mat_lens.emission_energy_multiplier = 1.5
	lens.material_override = mat_lens
	lens.rotation_degrees.x = 90.0
	lens.position = Vector3(0.0, 0.11, 0.28)
	rifle.add_child(lens)

	return rifle

static func build(visuals: Node3D, body: Node3D, fist_r: MeshInstance3D, fist_l: MeshInstance3D, palette: Dictionary, class_id: String = "fighter") -> Dictionary:
	var is_gunslinger: bool = (class_id == "gunslinger")

	var skin: Color = palette.get("skin", Color(1.0, 0.84, 0.74))
	var hair: Color = palette.get("hair", Color(0.98, 0.84, 0.48) if not is_gunslinger else Color(0.28, 0.20, 0.16))
	var hair_dark: Color = hair.darkened(0.35)
	var outfit: Color = palette.get("outfit", Color(0.98, 0.55, 0.15) if not is_gunslinger else Color(0.36, 0.25, 0.18))
	var outfit_dark: Color = outfit.darkened(0.25)
	var boots: Color = palette.get("boots", Color(0.72, 0.38, 0.14) if not is_gunslinger else Color(0.22, 0.15, 0.11))
	var belt: Color = palette.get("belt", Color(0.45, 0.40, 0.35) if not is_gunslinger else Color(0.30, 0.20, 0.12))
	var eye_color: Color = palette.get("eyes", Color(0.36, 0.34, 0.12) if not is_gunslinger else Color(0.2, 0.5, 0.75))
	var dark: Color = Color(0.10, 0.07, 0.09)

	# ---------------- PERNAS E BOTAS ----------------
	var legs: Array[Node3D] = []
	for side: float in [-1.0, 1.0]:
		var hip: Node3D = Node3D.new()
		hip.position = Vector3(side * 0.17, HIP_Y, 0.0)
		visuals.add_child(hip)
		legs.append(hip)

		_part(hip, _cylinder(0.085, 0.34), skin, Vector3(0.0, 0.40 - HIP_Y, 0.0), true, Vector3.ONE, Vector3.ZERO, false)
		_part(hip, _cylinder(0.14, 0.2), outfit if not is_gunslinger else Color(0.16, 0.22, 0.30), Vector3(0.0, 0.56 - HIP_Y, 0.0), true, Vector3.ONE, Vector3.ZERO, false)
		_part(hip, _sphere(0.16), boots, Vector3(0.0, 0.13 - HIP_Y, 0.07), true, Vector3(1.0, 0.85, 1.55), Vector3.ZERO, false)
		_part(hip, _cylinder(0.115, 0.09), boots.lightened(0.15), Vector3(0.0, 0.26 - HIP_Y, 0.0), true, Vector3.ONE, Vector3.ZERO, false)

		# Esporas douradas nas botas do pistoleiro
		if is_gunslinger:
			_part(hip, _box(Vector3(0.04, 0.04, 0.08)), Color(0.85, 0.72, 0.25), Vector3(0.0, 0.12 - HIP_Y, -0.10), false, Vector3.ONE, Vector3.ZERO, false)

	# ---------------- TRONCO ----------------
	_part(body, _capsule(0.30, 0.60), outfit, Vector3(0.0, 0.82, 0.0))

	if is_gunslinger:
		# Colete de pistoleiro aberto sobre camisa clara
		_part(body, _box(Vector3(0.24, 0.40, 0.04)), Color(0.88, 0.85, 0.78), Vector3(0.0, 0.86, 0.28), false) # camisa interna
		# Bordas do colete
		for side: float in [-1.0, 1.0]:
			_part(body, _box(Vector3(0.14, 0.42, 0.05)), outfit_dark, Vector3(side * 0.16, 0.86, 0.29), false)
		# Lenço / Bandana vermelha estilosa no pescoço
		_part(body, _box(Vector3(0.24, 0.14, 0.08)), Color(0.85, 0.22, 0.20), Vector3(0.0, 1.14, 0.30), false, Vector3.ONE, Vector3(20.0, 0.0, 0.0))
		_part(body, _sphere(0.06), Color(0.85, 0.22, 0.20), Vector3(0.0, 1.08, 0.34), false)
	else:
		# Macacão esportivo com zíper e bolsos
		_part(body, _box(Vector3(0.035, 0.34, 0.02)), outfit_dark, Vector3(0.0, 0.86, 0.295), false)
		for side: float in [-1.0, 1.0]:
			_part(body, _box(Vector3(0.12, 0.10, 0.04)), outfit_dark, Vector3(side * 0.13, 0.80, 0.285), false)

	# Cinto + fivela
	_part(body, _cylinder(0.325, 0.08), belt, Vector3(0.0, 0.62, 0.0))
	_part(body, _box(Vector3(0.10, 0.08, 0.04)), Color(0.85, 0.78, 0.55), Vector3(0.0, 0.62, 0.325), false)

	# Coldres laterais para o pistoleiro
	if is_gunslinger:
		for side: float in [-1.0, 1.0]:
			_part(body, _box(Vector3(0.08, 0.22, 0.12)), belt.darkened(0.2), Vector3(side * 0.34, 0.52, 0.02), true, Vector3.ONE, Vector3(0.0, 0.0, side * 8.0))

	# Mangas e braços
	for side: float in [-1.0, 1.0]:
		_part(body, _sphere(0.13), outfit, Vector3(side * 0.34, 0.98, 0.0))
		_part(body, _capsule(0.06, 0.30), skin, Vector3(side * 0.41, 0.82, 0.06), true, Vector3.ONE, Vector3(0.0, 0.0, side * 14.0))

	# ---------------- CABEÇA ----------------
	_part(body, _sphere(0.46), skin, Vector3(0.0, 1.38, 0.0), true, Vector3(1.0, 0.95, 0.97))

	# Rosto
	for side: float in [-1.0, 1.0]:
		var ex: float = side * 0.17
		_part(body, _sphere(0.12), Color.WHITE, Vector3(ex, 1.36, 0.415), false, Vector3(1.0, 1.15, 0.35))
		_part(body, _sphere(0.085), eye_color, Vector3(ex, 1.355, 0.44), false, Vector3(1.0, 1.1, 0.3))
		_part(body, _sphere(0.045), dark, Vector3(ex, 1.355, 0.455), false, Vector3(1.0, 1.1, 0.3))
		_part(body, _sphere(0.026), Color.WHITE, Vector3(ex + 0.03, 1.40, 0.465), false, Vector3(1.0, 1.0, 0.3))
		_part(body, _box(Vector3(0.14, 0.028, 0.02)), hair_dark, Vector3(ex, 1.52, 0.405), false, Vector3.ONE, Vector3(0.0, 0.0, side * -10.0))
		_part(body, _sphere(0.06), Color(1.0, 0.62, 0.62, 0.9), Vector3(side * 0.28, 1.25, 0.34), false, Vector3(1.3, 0.8, 0.3))
	_part(body, _sphere(0.04), Color(0.75, 0.25, 0.25), Vector3(0.0, 1.21, 0.435), false, Vector3(1.6, 0.7, 0.3))

	# ---------------- CABELO E CHAPÉU ----------------
	if is_gunslinger:
		# Cabelo sutil saindo de baixo do chapéu
		_part(body, _sphere(0.48), hair, Vector3(0.0, 1.38, -0.12), true, Vector3(1.02, 0.92, 0.95))
		for side: float in [-1.0, 1.0]:
			_part(body, _capsule(0.09, 0.45), hair, Vector3(side * 0.42, 1.22, -0.02), true)

		# CHAPÉU DE PISTOLEIRO (Cowboy Hat)
		var hat_color: Color = outfit_dark.darkened(0.15)
		var hat_band_color: Color = Color(0.85, 0.72, 0.25) # fita dourada de couro

		# Aba larga curvada
		var brim: MeshInstance3D = _part(body, _cylinder(0.66, 0.035), hat_color, Vector3(0.0, 1.62, 0.0), true, Vector3(1.05, 1.0, 1.2), Vector3(-4.0, 0.0, 0.0))
		# Dobra estilosa nas laterais da aba
		brim.scale.x = 0.92

		# Copa do chapéu com vinco central
		_part(body, _cylinder(0.38, 0.30), hat_color, Vector3(0.0, 1.77, -0.02), true, Vector3(0.95, 1.0, 1.15))
		# Vinco no topo
		_part(body, _cylinder(0.18, 0.08), hat_color.darkened(0.2), Vector3(0.0, 1.91, -0.02), false, Vector3(1.1, 1.0, 1.8))
		# Fita do chapéu + fivela
		_part(body, _cylinder(0.395, 0.05), hat_band_color, Vector3(0.0, 1.66, -0.02), false, Vector3(0.96, 1.0, 1.16))
		_part(body, _box(Vector3(0.08, 0.06, 0.04)), Color(0.95, 0.88, 0.5), Vector3(0.0, 1.66, 0.44), false)
	else:
		# Cabelo do Lutador
		_part(body, _sphere(0.50), hair, Vector3(0.0, 1.43, -0.10), true, Vector3(1.03, 1.0, 0.95))
		_part(body, _capsule(0.20, 0.70), hair, Vector3(0.0, 1.05, -0.32))
		for side: float in [-1.0, 1.0]:
			_part(body, _capsule(0.13, 0.78), hair, Vector3(side * 0.43, 1.10, -0.04), true, Vector3.ONE, Vector3(0.0, 0.0, side * 8.0))
		_part(body, _sphere(0.15), hair, Vector3(-0.20, 1.64, 0.29), true, Vector3(1.25, 0.9, 0.9), Vector3(0.0, 0.0, 20.0))
		_part(body, _sphere(0.16), hair, Vector3(0.02, 1.67, 0.31), true, Vector3(1.2, 0.9, 0.9), Vector3(0.0, 0.0, 8.0))
		_part(body, _sphere(0.15), hair, Vector3(0.22, 1.64, 0.27), true, Vector3(1.2, 0.9, 0.9), Vector3(0.0, 0.0, -25.0))

	# ---------------- MÃOS E ARMAS ----------------
	var pistols: Array[Node3D] = []
	for fist: MeshInstance3D in [fist_r, fist_l]:
		if fist == null:
			continue

		# Limpar filhos anteriores se houver (caso esteja trocando de classe)
		for child in fist.get_children():
			child.queue_free()

		fist.mesh = _sphere(0.14)
		fist.material_override = _make_material(skin if not is_gunslinger else boots, true) # luvas de couro no pistoleiro

		if is_gunslinger:
			# Acopla a pistola estilizada cartoon em cada mão
			var pistol: Node3D = _attach_pistol(fist, Color(0.25, 0.28, 0.32), Color(0.42, 0.25, 0.16))
			pistols.append(pistol)
		else:
			# Munhequeira clássica do lutador
			var band: MeshInstance3D = MeshInstance3D.new()
			band.mesh = _cylinder(0.12, 0.07)
			band.material_override = _make_material(outfit_dark, false)
			band.position = Vector3(0.0, 0.0, -0.12)
			band.rotation_degrees = Vector3(90.0, 0.0, 0.0)
			fist.add_child(band)

	return {
		"legs": legs,
		"pistols": pistols
	}
