extends CanvasLayer

signal restart_clicked
signal menu_clicked

const MobileTouchControlsScript = preload("res://scripts/mobile_touch_controls.gd")

@onready var p1_bar: ProgressBar = $MarginContainer/TopBar/P1Health
@onready var p2_bar: ProgressBar = $MarginContainer/TopBar/P2Health
@onready var timer_label: Label = $MarginContainer/TopBar/TimerLabel
@onready var p1_name: Label = $MarginContainer/TopBar/P1Name
@onready var p2_name: Label = $MarginContainer/TopBar/P2Name

@onready var game_over_panel: Control = $GameOverPanel
@onready var title_label: Label = $GameOverPanel/VBox/TitleLabel
@onready var reason_label: Label = $GameOverPanel/VBox/ReasonLabel
@onready var restart_button: Button = $GameOverPanel/VBox/ButtonsHBox/RestartButton
@onready var menu_button: Button = $GameOverPanel/VBox/ButtonsHBox/MenuButton

@onready var pause_panel: Control = $PausePanel
@onready var btn_resume: Button = $PausePanel/VBox/BtnResume
@onready var btn_pause_menu: Button = $PausePanel/VBox/BtnPauseMenu

var match_time: float = 99.0
var match_ended: bool = false
var match_active: bool = false

# Controles Virtuais Touch para Mobile
var mobile_controls: MobileTouchControls = null
var btn_toggle_touch: Button = null

func set_match_active(active: bool) -> void:
	match_active = active
	visible = active
	if mobile_controls:
		mobile_controls.visible = active and not match_ended

# Barra de habilidades
@onready var skill_bar: HBoxContainer = $SkillBar
var skill_player: Fighter = null
var skill_slots: Array[Dictionary] = []

const SKILL_SLOT_SIZE: float = 72.0

@onready var bottom_hint: Label = $MarginContainer/BottomHint

var current_class_id: String = "fighter"

func _ready() -> void:
	if game_over_panel:
		game_over_panel.visible = false
	if pause_panel:
		pause_panel.visible = false
	if restart_button:
		restart_button.pressed.connect(_on_restart_button_pressed)
	if menu_button:
		menu_button.pressed.connect(_on_menu_button_pressed)
	if btn_resume:
		btn_resume.pressed.connect(toggle_pause)
	if btn_pause_menu:
		btn_pause_menu.pressed.connect(_on_menu_button_pressed)

	# Instanciar e acoplar os Controles Touch Mobile
	mobile_controls = MobileTouchControlsScript.new()
	add_child(mobile_controls)
	mobile_controls.pause_requested.connect(toggle_pause)

	# Adicionar botão de alternar controles touch no menu de pausa
	_setup_pause_touch_toggle()

	setup_class_hud("fighter")

func _setup_pause_touch_toggle() -> void:
	if not pause_panel:
		return
	var vbox: VBoxContainer = pause_panel.get_node_or_null("VBox")
	if vbox:
		btn_toggle_touch = Button.new()
		btn_toggle_touch.text = "📱 CONTROLES TOUCH: ATIVADOS"
		btn_toggle_touch.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn_toggle_touch.add_theme_font_size_override("font_size", 16)
		if btn_resume:
			btn_toggle_touch.theme = btn_resume.theme
		btn_toggle_touch.pressed.connect(_on_toggle_touch_pressed)
		vbox.add_child(btn_toggle_touch)
		vbox.move_child(btn_toggle_touch, 2)

func _on_toggle_touch_pressed() -> void:
	if not mobile_controls:
		return
	mobile_controls.is_active = !mobile_controls.is_active
	mobile_controls.visible = mobile_controls.is_active and match_active and not match_ended
	if btn_toggle_touch:
		btn_toggle_touch.text = "📱 CONTROLES TOUCH: " + ("ATIVADOS" if mobile_controls.is_active else "DESATIVADOS")

func setup_class_hud(class_id: String) -> void:
	current_class_id = class_id
	if p1_name:
		p1_name.text = "PISTOLEIRO (P1)" if class_id == "gunslinger" else "LUTADOR (P1)"

	if bottom_hint:
		if class_id == "gunslinger":
			bottom_hint.text = "[W, A, S, D] Mover   |   [ESPAÇO] Pular   |   [J / Botão Esquerdo] Tiros   |   [K] Focar Mira   |   [SHIFT] Esquiva   |   [SHIFT+CTRL / No Ar: CTRL] Deslizar   |   [Q] [E] [F] Habilidades"
		else:
			bottom_hint.text = "[W, A, S, D] Mover   |   [ESPAÇO] Pular   |   [J / Clique Esquerdo] Socar   |   [SHIFT] Esquiva   |   [SHIFT+CTRL / No Ar: CTRL] Deslizar   |   [K] Bloquear   |   [Q] [E] [F] Habilidades"

	if mobile_controls:
		mobile_controls.set_class_id(class_id)

	_build_skill_bar()

func _build_skill_bar() -> void:
	if not skill_bar:
		return

	# Limpar slots anteriores
	for child in skill_bar.get_children():
		child.queue_free()
	skill_slots.clear()

	var defs: Array[Dictionary] = []
	if current_class_id == "gunslinger":
		defs = [
			{"key": "Q", "name": "CORRIDA", "color": Color(0.25, 0.82, 1.0, 1.0)},
			{"key": "E", "name": "ARMADILHA", "color": Color(1.0, 0.72, 0.2, 1.0)},
			{"key": "F", "name": "TIRO CERTEIRO", "color": Color(1.0, 0.28, 0.32, 1.0)},
		]
	else:
		defs = [
			{"key": "Q", "name": "INVESTIDA", "color": Color(0.95, 0.55, 0.2, 1.0)},
			{"key": "E", "name": "ONDA", "color": Color(0.55, 0.45, 0.95, 1.0)},
			{"key": "F", "name": "ULTIMATE", "color": Color(0.95, 0.25, 0.3, 1.0)},
		]
	for def: Dictionary in defs:
		var slot: Panel = Panel.new()
		slot.custom_minimum_size = Vector2(SKILL_SLOT_SIZE, SKILL_SLOT_SIZE)

		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = Color(0.08, 0.09, 0.13, 0.88)
		style.border_width_left = 3
		style.border_width_top = 3
		style.border_width_right = 3
		style.border_width_bottom = 3
		style.border_color = def["color"]
		style.set_corner_radius_all(8)
		slot.add_theme_stylebox_override("panel", style)

		# Nome da habilidade (centro)
		var name_label: Label = Label.new()
		name_label.text = def["name"]
		name_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 11)
		name_label.add_theme_color_override("font_color", Color(0.85, 0.87, 0.92, 1.0))
		slot.add_child(name_label)

		# Camada de recarga (escurece de cima para baixo)
		var overlay: ColorRect = ColorRect.new()
		overlay.color = Color(0, 0, 0, 0.65)
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.position = Vector2(3, 3)
		overlay.size = Vector2(0, 0)
		slot.add_child(overlay)

		# Tecla (canto superior esquerdo)
		var key_label: Label = Label.new()
		key_label.text = def["key"]
		key_label.position = Vector2(7, 2)
		key_label.add_theme_font_size_override("font_size", 18)
		key_label.add_theme_color_override("font_color", def["color"])
		key_label.add_theme_color_override("font_outline_color", Color.BLACK)
		key_label.add_theme_constant_override("outline_size", 4)
		slot.add_child(key_label)

		# Tempo restante (centro, grande)
		var time_label: Label = Label.new()
		time_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		time_label.add_theme_font_size_override("font_size", 28)
		time_label.add_theme_color_override("font_color", Color.WHITE)
		time_label.add_theme_color_override("font_outline_color", Color.BLACK)
		time_label.add_theme_constant_override("outline_size", 6)
		time_label.visible = false
		slot.add_child(time_label)

		skill_bar.add_child(slot)
		skill_slots.append({"overlay": overlay, "time_label": time_label})

func setup(p1: Fighter, p2: Fighter) -> void:
	skill_player = p1
	if mobile_controls and p1:
		mobile_controls.set_skill_player(p1)

	if p1:
		p1.health_changed.connect(_on_p1_health_changed)
		p1_bar.max_value = p1.max_health
		p1_bar.value = p1.current_health
	if p2:
		p2.health_changed.connect(_on_p2_health_changed)
		p2_bar.max_value = p2.max_health
		p2_bar.value = p2.current_health

	if NetworkManager and NetworkManager.is_online:
		if p1_name:
			p1_name.text = "VOCÊ"
		if p2_name:
			p2_name.text = "OPONENTE"

func _update_skill_bar() -> void:
	if not skill_player or not is_instance_valid(skill_player):
		return
	for i in range(skill_slots.size()):
		var remaining: float = skill_player.skill_cooldowns[i]
		var total: float = skill_player.get_skill_cooldown_total(i)
		var overlay: ColorRect = skill_slots[i]["overlay"]
		var time_label: Label = skill_slots[i]["time_label"]
		if remaining > 0.0:
			var inner: float = SKILL_SLOT_SIZE - 6.0
			overlay.size = Vector2(inner, inner * (remaining / total))
			time_label.text = str(int(ceil(remaining)))
			time_label.visible = true
		else:
			overlay.size = Vector2.ZERO
			time_label.visible = false

func _process(delta: float) -> void:
	if not match_active:
		return
	_update_skill_bar()
	if not match_ended and match_time > 0:
		match_time -= delta
		timer_label.text = str(int(ceil(match_time)))

func _on_p1_health_changed(current: float, _max: float) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(p1_bar, "value", current, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _on_p2_health_changed(current: float, _max: float) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(p2_bar, "value", current, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func show_match_result(player_won: bool, reason: String) -> void:
	match_ended = true
	if mobile_controls:
		mobile_controls.visible = false

	if not game_over_panel:
		return

	if player_won:
		title_label.text = "WIN"
		title_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.15, 1.0)) # Dourado brilhante
		reason_label.text = "VITÓRIA POR " + reason
	else:
		title_label.text = "LOSER"
		title_label.add_theme_color_override("font_color", Color(0.92, 0.15, 0.18, 1.0)) # Vermelho GTA V
		reason_label.text = "DERROTA POR " + reason

	game_over_panel.visible = true
	game_over_panel.modulate.a = 0.0

	if restart_button:
		restart_button.grab_focus()

	# Animação dramática estilo GTA V (fade in suave + expansão de texto)
	var tween: Tween = create_tween().set_parallel(true)
	tween.set_speed_scale(1.0 / max(Engine.time_scale, 0.05))
	tween.tween_property(game_over_panel, "modulate:a", 1.0, 0.35)
	title_label.pivot_offset = title_label.size * 0.5
	tween.tween_property(title_label, "scale", Vector2.ONE, 0.4).from(Vector2(1.3, 1.3))

func _on_restart_button_pressed() -> void:
	emit_signal("restart_clicked")

func _on_menu_button_pressed() -> void:
	if pause_panel:
		pause_panel.visible = false
	emit_signal("menu_clicked")

func toggle_pause() -> void:
	if not pause_panel or match_ended:
		return
	var is_paused: bool = !pause_panel.visible
	pause_panel.visible = is_paused

	if mobile_controls:
		mobile_controls.visible = !is_paused and match_active and not match_ended

	if btn_resume and is_paused:
		btn_resume.grab_focus()
	# No modo offline pausa a física, no modo online apenas abre o menu sem congelar
	if not (NetworkManager and NetworkManager.is_online):
		get_tree().paused = is_paused

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			if match_active and not match_ended:
				toggle_pause()
				get_viewport().set_input_as_handled()
