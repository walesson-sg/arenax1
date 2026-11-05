class_name MobileTouchControls
extends Control

## Controles Virtuais Touchscreen para Mobile / Navegador
## Fornece Analógico Virtual (Polegar Esquerdo) e Botões de Ação Ergonômicos (Polegar Direito)
## Suporta Multi-touch com isolamento de dedos e adaptação a qualquer resolução.

signal pause_requested

# Estado de visibilidade
var is_active: bool = true
var is_touch_device: bool = false
var current_class_id: String = "fighter"
var skill_player: Fighter = null

# Configurações do Analógico Esquerdo
var joystick_center: Vector2 = Vector2.ZERO
var joystick_current_pos: Vector2 = Vector2.ZERO
var joystick_touch_id: int = -1
var joystick_base_radius: float = 72.0
var joystick_knob_radius: float = 30.0
var joystick_max_distance: float = 54.0
var joystick_deadzone: float = 10.0
var is_joystick_active: bool = false

# Definições dos Botões de Combate
var buttons: Dictionary = {}
var button_touch_map: Dictionary = {} # touch_id -> button_name

# Botão de Pausa
var pause_btn_rect: Rect2 = Rect2()
var pause_touch_id: int = -1

# Cores e Estilos
const COLOR_BG_NORMAL: float = 0.38
const COLOR_BG_PRESSED: float = 0.80

func _ready() -> void:
	# Cobrir a tela inteira com passagem de clique transparente
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Detectar dispositivo com touch
	_detect_touch_support()

	# Configurar botões com base no tamanho inicial da tela
	_setup_buttons()
	resized.connect(_on_resized)

func _detect_touch_support() -> void:
	is_touch_device = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	if OS.has_feature("web"):
		var web_touch = JavaScriptBridge.eval("('ontouchstart' in window) || (navigator.maxTouchPoints > 0)")
		if web_touch == true:
			is_touch_device = true

	# Sempre visível em mobile ou em telas touch; se estiver no PC desktop, começa visível se for emulado
	visible = is_active

func set_class_id(class_id: String) -> void:
	current_class_id = class_id
	_setup_buttons()
	queue_redraw()

func set_skill_player(fighter: Fighter) -> void:
	skill_player = fighter

func _on_resized() -> void:
	_setup_buttons()
	queue_redraw()

func _setup_buttons() -> void:
	var vp_size: Vector2 = get_viewport_rect().size
	if vp_size.x <= 0 or vp_size.y <= 0:
		return

	# Posição do Analógico Virtual (canto inferior esquerdo com margem segura)
	var joy_margin_left: float = clampf(vp_size.x * 0.12, 100.0, 160.0)
	var joy_margin_bottom: float = clampf(vp_size.y * 0.22, 110.0, 160.0)
	joystick_center = Vector2(joy_margin_left, vp_size.y - joy_margin_bottom)
	if not is_joystick_active:
		joystick_current_pos = joystick_center

	# Cluster de Combate (canto inferior direito)
	var right_center_x: float = vp_size.x - clampf(vp_size.x * 0.11, 100.0, 140.0)
	var right_center_y: float = vp_size.y - clampf(vp_size.y * 0.20, 100.0, 140.0)
	var origin: Vector2 = Vector2(right_center_x, right_center_y)

	buttons.clear()

	# 1. ATAQUE PRINCIPAL (Central, grande, fácil de martelar com o polegar)
	var atk_icon: String = "🔫" if current_class_id == "gunslinger" else "🥊"
	var atk_name: String = "TIRO" if current_class_id == "gunslinger" else "SOCO"
	buttons["attack"] = {
		"action": "attack",
		"pos": origin + Vector2(-10, -5),
		"radius": 44.0,
		"color": Color(0.95, 0.35, 0.15),
		"icon": atk_icon,
		"label": atk_name,
		"is_pressed": false
	}

	# 2. PULO (Posicionado abaixo e à esquerda do ataque)
	buttons["jump"] = {
		"action": "jump",
		"pos": origin + Vector2(-95, 20),
		"radius": 34.0,
		"color": Color(0.18, 0.78, 0.45),
		"icon": "⬆️",
		"label": "PULO",
		"is_pressed": false
	}

	# 3. DASH / ESQUIVA (Acima e à direita do ataque)
	buttons["dash"] = {
		"action": "dash",
		"pos": origin + Vector2(25, -90),
		"radius": 32.0,
		"color": Color(0.15, 0.68, 0.95),
		"icon": "💨",
		"label": "DASH",
		"is_pressed": false
	}

	# 4. DEFESA / MIRA FOCADA
	var def_label: String = "MIRA" if current_class_id == "gunslinger" else "DEFESA"
	var def_icon: String = "🎯" if current_class_id == "gunslinger" else "🛡️"
	buttons["block"] = {
		"action": "block",
		"pos": origin + Vector2(-95, -60),
		"radius": 30.0,
		"color": Color(0.65, 0.35, 0.92),
		"icon": def_icon,
		"label": def_label,
		"is_pressed": false
	}

	# 5. DESLIZAR (SLIDE)
	buttons["slide"] = {
		"action": "slide",
		"pos": origin + Vector2(-165, -10),
		"radius": 26.0,
		"color": Color(0.95, 0.75, 0.15),
		"icon": "⚡",
		"label": "SLIDE",
		"is_pressed": false
	}

	# 6. ARCO DE HABILIDADES (Q, E, F)
	var q_name: String = "CORRIDA" if current_class_id == "gunslinger" else "INVESTIDA"
	buttons["skill_q"] = {
		"action": "skill_q",
		"pos": origin + Vector2(-170, -85),
		"radius": 28.0,
		"color": Color(0.25, 0.82, 1.0) if current_class_id == "gunslinger" else Color(0.95, 0.55, 0.2),
		"icon": "Q",
		"label": q_name,
		"skill_idx": 0,
		"is_pressed": false
	}

	var e_name: String = "ARMADILHA" if current_class_id == "gunslinger" else "ONDA"
	buttons["skill_e"] = {
		"action": "skill_e",
		"pos": origin + Vector2(-120, -150),
		"radius": 28.0,
		"color": Color(1.0, 0.72, 0.2) if current_class_id == "gunslinger" else Color(0.55, 0.45, 0.95),
		"icon": "E",
		"label": e_name,
		"skill_idx": 1,
		"is_pressed": false
	}

	# 7. ULTIMATE (F) - Destacado e imponente
	var f_name: String = "TIRO CERTEIRO" if current_class_id == "gunslinger" else "ULTIMATE"
	buttons["skill_f"] = {
		"action": "skill_f",
		"pos": origin + Vector2(-35, -175),
		"radius": 34.0,
		"color": Color(0.95, 0.22, 0.28),
		"icon": "★ F",
		"label": f_name,
		"skill_idx": 2,
		"is_pressed": false
	}

	# 8. BOTÃO DE PAUSA (Canto Superior Direito)
	pause_btn_rect = Rect2(vp_size.x - 65, 20, 48, 48)

func _process(_delta: float) -> void:
	if not visible:
		return
	queue_redraw()

# ==============================================================================
# ENTRADA DE TOQUES / CLIQUES (MULTI-TOUCH)
# ==============================================================================
func _input(event: InputEvent) -> void:
	if not visible:
		return

	# Suporta toque de tela e clique de mouse (para testar no PC)
	if event is InputEventScreenTouch:
		_handle_touch_event(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_handle_drag_event(event.index, event.position)
	elif event is InputEventMouseButton:
		_handle_touch_event(99, event.position, event.pressed)
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_handle_drag_event(99, event.position)

func _handle_touch_event(touch_id: int, pos: Vector2, is_down: bool) -> void:
	var vp_size: Vector2 = get_viewport_rect().size

	if is_down:
		# Revela os controles se o usuário tocou na tela
		if not is_touch_device:
			is_touch_device = true

		# 1. Checar Botão de Pausa
		if pause_btn_rect.has_point(pos):
			pause_touch_id = touch_id
			emit_signal("pause_requested")
			return

		# 2. Checar Botões de Ação da Direita
		var hit_button: bool = false
		for btn_id in buttons:
			var btn: Dictionary = buttons[btn_id]
			if pos.distance_to(btn["pos"]) <= btn["radius"] * 1.25: # Tolerância ergonômica de 25%
				button_touch_map[touch_id] = btn_id
				btn["is_pressed"] = true
				Input.action_press(btn["action"])
				hit_button = true
				queue_redraw()
				break

		if hit_button:
			return

		# 3. Checar Zona do Analógico (Metade Esquerda da tela)
		if pos.x < vp_size.x * 0.48 and pos.y > vp_size.y * 0.25:
			if joystick_touch_id == -1:
				joystick_touch_id = touch_id
				is_joystick_active = true
				# Joystick Dinâmico: ajusta o centro suavemente para onde o polegar tocou
				joystick_center = pos
				_update_joystick_pos(pos)
				queue_redraw()

	else: # Touch Up / Soltura do dedo
		if pause_touch_id == touch_id:
			pause_touch_id = -1

		# Soltura de Botão de Ação
		if button_touch_map.has(touch_id):
			var btn_id: String = button_touch_map[touch_id]
			if buttons.has(btn_id):
				buttons[btn_id]["is_pressed"] = false
				Input.action_release(buttons[btn_id]["action"])
			button_touch_map.erase(touch_id)
			queue_redraw()

		# Soltura do Analógico
		if joystick_touch_id == touch_id:
			joystick_touch_id = -1
			is_joystick_active = false
			_reset_joystick()
			queue_redraw()

func _handle_drag_event(touch_id: int, pos: Vector2) -> void:
	# Arraste no Analógico
	if joystick_touch_id == touch_id:
		_update_joystick_pos(pos)
		queue_redraw()

	# Arraste entre Botões de Ação (deslizar o dedo para outro golpe)
	elif button_touch_map.has(touch_id):
		var current_btn: String = button_touch_map[touch_id]
		var still_in: bool = pos.distance_to(buttons[current_btn]["pos"]) <= buttons[current_btn]["radius"] * 1.35
		if not still_in:
			# Dedo saiu do botão original
			buttons[current_btn]["is_pressed"] = false
			Input.action_release(buttons[current_btn]["action"])
			button_touch_map.erase(touch_id)

			# Verificar se entrou em outro botão vizinho
			for btn_id in buttons:
				var btn: Dictionary = buttons[btn_id]
				if pos.distance_to(btn["pos"]) <= btn["radius"] * 1.2:
					button_touch_map[touch_id] = btn_id
					btn["is_pressed"] = true
					Input.action_press(btn["action"])
					break
			queue_redraw()

func _update_joystick_pos(touch_pos: Vector2) -> void:
	var delta: Vector2 = touch_pos - joystick_center
	var dist: float = delta.length()

	if dist > joystick_max_distance:
		joystick_current_pos = joystick_center + delta.normalized() * joystick_max_distance
	else:
		joystick_current_pos = touch_pos

	var dir: Vector2 = (joystick_current_pos - joystick_center)
	var d_len: float = dir.length()

	if d_len > joystick_deadzone:
		var norm: Vector2 = dir.normalized()
		var strength: float = clampf((d_len - joystick_deadzone) / (joystick_max_distance - joystick_deadzone), 0.0, 1.0)

		# Mapeamento do Vetor de Movimento (Câmera 3D: -Y é para frente, +Y é para trás)
		if norm.y < -0.25:
			Input.action_press("move_forward", abs(norm.y) * strength)
			Input.action_release("move_backward")
		elif norm.y > 0.25:
			Input.action_press("move_backward", abs(norm.y) * strength)
			Input.action_release("move_forward")
		else:
			Input.action_release("move_forward")
			Input.action_release("move_backward")

		if norm.x < -0.25:
			Input.action_press("move_left", abs(norm.x) * strength)
			Input.action_release("move_right")
		elif norm.x > 0.25:
			Input.action_press("move_right", abs(norm.x) * strength)
			Input.action_release("move_left")
		else:
			Input.action_release("move_left")
			Input.action_release("move_right")
	else:
		_release_move_actions()

func _reset_joystick() -> void:
	var vp_size: Vector2 = get_viewport_rect().size
	var joy_margin_left: float = clampf(vp_size.x * 0.12, 100.0, 160.0)
	var joy_margin_bottom: float = clampf(vp_size.y * 0.22, 110.0, 160.0)
	joystick_center = Vector2(joy_margin_left, vp_size.y - joy_margin_bottom)
	joystick_current_pos = joystick_center
	_release_move_actions()

func _release_move_actions() -> void:
	Input.action_release("move_forward")
	Input.action_release("move_backward")
	Input.action_release("move_left")
	Input.action_release("move_right")

# ==============================================================================
# RENDERIZAÇÃO VETORIAL LIMPA E MODERNA (_DRAW)
# ==============================================================================
func _draw() -> void:
	if not visible:
		return

	# 1. DESENHAR ANALÓGICO VIRTUAL (ESQUERDA)
	_draw_joystick()

	# 2. DESENHAR BOTÕES DE COMBATE (DIREITA)
	for btn_id in buttons:
		_draw_action_button(buttons[btn_id])

	# 3. DESENHAR BOTÃO DE PAUSA (TOPO DIREITO)
	_draw_pause_button()

func _draw_joystick() -> void:
	# Base externa translúcida
	var base_alpha: float = 0.45 if is_joystick_active else 0.25
	var base_color: Color = Color(0.08, 0.10, 0.16, base_alpha)
	var ring_color: Color = Color(0.35, 0.65, 0.95, base_alpha + 0.25)

	draw_circle(joystick_center, joystick_base_radius, base_color)
	draw_arc(joystick_center, joystick_base_radius, 0, TAU, 36, ring_color, 2.5, true)
	draw_arc(joystick_center, joystick_deadzone, 0, TAU, 24, Color(1, 1, 1, 0.15), 1.0, true)

	# Setas sutis de direção na base
	var arrow_dist: float = joystick_base_radius * 0.65
	var arrow_col: Color = Color(1, 1, 1, 0.20)
	draw_line(joystick_center + Vector2(0, -arrow_dist), joystick_center + Vector2(0, -arrow_dist + 8), arrow_col, 2.0)
	draw_line(joystick_center + Vector2(0, arrow_dist), joystick_center + Vector2(0, arrow_dist - 8), arrow_col, 2.0)
	draw_line(joystick_center + Vector2(-arrow_dist, 0), joystick_center + Vector2(-arrow_dist + 8, 0), arrow_col, 2.0)
	draw_line(joystick_center + Vector2(arrow_dist, 0), joystick_center + Vector2(arrow_dist - 8, 0), arrow_col, 2.0)

	# Manete central (Knob)
	var knob_alpha: float = 0.85 if is_joystick_active else 0.50
	var knob_fill: Color = Color(0.20, 0.55, 0.95, knob_alpha)
	var knob_border: Color = Color(0.85, 0.95, 1.0, knob_alpha + 0.1)

	# Linha guia elástica quando puxado
	if is_joystick_active and joystick_current_pos != joystick_center:
		draw_line(joystick_center, joystick_current_pos, Color(0.35, 0.65, 0.95, 0.4), 3.0, true)

	draw_circle(joystick_current_pos, joystick_knob_radius, knob_fill)
	draw_arc(joystick_current_pos, joystick_knob_radius, 0, TAU, 28, knob_border, 2.0, true)

func _draw_action_button(btn: Dictionary) -> void:
	var pos: Vector2 = btn["pos"]
	var radius: float = btn["radius"]
	var base_col: Color = btn["color"]
	var is_p: bool = btn["is_pressed"]

	# Cor de preenchimento e borda
	var fill_alpha: float = COLOR_BG_PRESSED if is_p else COLOR_BG_NORMAL
	var fill_col: Color = Color(base_col.r, base_col.g, base_col.b, fill_alpha)
	var border_col: Color = Color(base_col.r * 1.2, base_col.g * 1.2, base_col.b * 1.2, 0.90)

	# Efeito de escala ao pressionar
	var draw_r: float = radius * 0.92 if is_p else radius

	# Sombra sutil
	draw_circle(pos + Vector2(0, 3), draw_r, Color(0, 0, 0, 0.35))

	# Fundo e anel
	draw_circle(pos, draw_r, fill_col)
	draw_arc(pos, draw_r, 0, TAU, 32, border_col, 2.5, true)

	# Ícone e texto central
	var font = ThemeDB.fallback_font
	if font:
		var icon_str: String = btn.get("icon", "")
		var icon_size: int = int(draw_r * 0.70)
		var str_size: Vector2 = font.get_string_size(icon_str, HORIZONTAL_ALIGNMENT_CENTER, -1, icon_size)
		draw_string(font, pos + Vector2(-str_size.x * 0.5, str_size.y * 0.30 - 3), icon_str, HORIZONTAL_ALIGNMENT_CENTER, -1, icon_size, Color.WHITE)

		# Sub-rótulo explicativo (abaixo do ícone)
		var lbl: String = btn.get("label", "")
		if lbl != "":
			var lbl_size: int = int(clampf(draw_r * 0.28, 8.0, 11.0))
			var l_str_size: Vector2 = font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_CENTER, -1, lbl_size)
			draw_string(font, pos + Vector2(-l_str_size.x * 0.5, draw_r * 0.65), lbl, HORIZONTAL_ALIGNMENT_CENTER, -1, lbl_size, Color(0.9, 0.9, 0.9, 0.85))

	# Overlay de Cooldown para Habilidades (Q, E, F)
	if btn.has("skill_idx") and skill_player and is_instance_valid(skill_player):
		var s_idx: int = btn["skill_idx"]
		var cd_rem: float = skill_player.skill_cooldowns[s_idx]
		var cd_total: float = skill_player.get_skill_cooldown_total(s_idx)
		if cd_rem > 0.0 and cd_total > 0.0:
			# Escurecer botão em cooldown
			draw_circle(pos, draw_r, Color(0, 0, 0, 0.65))
			var angle: float = (cd_rem / cd_total) * TAU
			draw_arc(pos, draw_r - 2, -PI * 0.5, -PI * 0.5 + angle, 32, Color(1, 1, 1, 0.85), 3.0, true)

			# Número do tempo restante
			if font:
				var time_str: String = str(int(ceil(cd_rem)))
				var t_size: int = int(draw_r * 0.85)
				var t_str_size: Vector2 = font.get_string_size(time_str, HORIZONTAL_ALIGNMENT_CENTER, -1, t_size)
				draw_string(font, pos + Vector2(-t_str_size.x * 0.5, t_str_size.y * 0.35), time_str, HORIZONTAL_ALIGNMENT_CENTER, -1, t_size, Color(1, 1, 0.4))

func _draw_pause_button() -> void:
	var bg_col: Color = Color(0.12, 0.14, 0.20, 0.60)
	var ring_col: Color = Color(0.65, 0.70, 0.85, 0.80)
	draw_rect(pause_btn_rect, bg_col, true, 8)
	draw_rect(pause_btn_rect, ring_col, false, 2)

	# Desenhar as duas barras clássicas de pausa ❚❚
	var bar_w: float = 4.0
	var bar_h: float = 18.0
	var c_x: float = pause_btn_rect.position.x + pause_btn_rect.size.x * 0.5
	var c_y: float = pause_btn_rect.position.y + pause_btn_rect.size.y * 0.5
	draw_rect(Rect2(c_x - 7, c_y - bar_h * 0.5, bar_w, bar_h), Color.WHITE, true)
	draw_rect(Rect2(c_x + 3, c_y - bar_h * 0.5, bar_w, bar_h), Color.WHITE, true)

