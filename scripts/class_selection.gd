class_name ClassSelection
extends CanvasLayer

signal class_selected(class_id: String)

@onready var root_control: Control = $Control
@onready var notice_label: Label = $Control/MainContainer/NoticeContainer/NoticeLabel
@onready var btn_fighter: Button = $Control/MainContainer/CardsContainer/CardFighter/VBox/SelectButton
@onready var btn_gunslinger: Button = $Control/MainContainer/CardsContainer/CardGunslinger/VBox/SelectButton
@onready var card_fighter: PanelContainer = $Control/MainContainer/CardsContainer/CardFighter
@onready var card_gunslinger: PanelContainer = $Control/MainContainer/CardsContainer/CardGunslinger
@onready var btn_back_to_menu: Button = $Control/MainContainer/BtnBackToMenu

var notice_tween: Tween = null
var is_closing: bool = false

func _ready() -> void:
	visible = true
	is_closing = false

	if notice_label:
		notice_label.modulate.a = 0.0

	# Ajustar pivô dos cards para escala suave caso use animação
	if card_fighter:
		card_fighter.pivot_offset = Vector2(170, 215)
		card_fighter.gui_input.connect(_on_card_fighter_gui_input)
		card_fighter.mouse_entered.connect(_on_card_fighter_hover.bind(true))
		card_fighter.mouse_exited.connect(_on_card_fighter_hover.bind(false))

	if card_gunslinger:
		card_gunslinger.pivot_offset = Vector2(170, 215)
		card_gunslinger.gui_input.connect(_on_card_gunslinger_gui_input)
		card_gunslinger.mouse_entered.connect(_on_card_gunslinger_hover.bind(true))
		card_gunslinger.mouse_exited.connect(_on_card_gunslinger_hover.bind(false))

	# Conectar botões
	if btn_fighter:
		btn_fighter.pressed.connect(_on_fighter_pressed)
		btn_fighter.grab_focus()
	if btn_gunslinger:
		btn_gunslinger.pressed.connect(_on_gunslinger_pressed)
	if btn_back_to_menu:
		btn_back_to_menu.pressed.connect(_on_back_to_menu_pressed)

	# Animação suave de entrada da tela
	if root_control:
		root_control.modulate.a = 0.0
		root_control.pivot_offset = Vector2(640, 360)
		var tween: Tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(root_control, "modulate:a", 1.0, 0.3)

func _unhandled_input(event: InputEvent) -> void:
	if not visible or is_closing:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_on_back_to_menu_pressed()

func _on_back_to_menu_pressed() -> void:
	if is_closing:
		return
	is_closing = true
	set_process_unhandled_input(false)
	if NetworkManager:
		NetworkManager._cleanup_network()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_fighter_pressed() -> void:
	if is_closing:
		return
	is_closing = true
	set_process_unhandled_input(false)

	# Efeito visual de confirmação da escolha
	if card_fighter:
		var punch_tween: Tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		punch_tween.tween_property(card_fighter, "scale", Vector2(1.06, 1.06), 0.1)
		punch_tween.tween_property(card_fighter, "scale", Vector2(1.0, 1.0), 0.1)

	# Transição suave para iniciar a partida
	var tween: Tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(root_control, "modulate:a", 0.0, 0.28)
	tween.chain().tween_callback(func():
		visible = false
		queue_free()
		class_selected.emit("fighter")
	)

func _on_gunslinger_pressed() -> void:
	if is_closing:
		return
	is_closing = true
	set_process_unhandled_input(false)

	# Efeito visual de confirmação da escolha
	if card_gunslinger:
		var punch_tween: Tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		punch_tween.tween_property(card_gunslinger, "scale", Vector2(1.06, 1.06), 0.1)
		punch_tween.tween_property(card_gunslinger, "scale", Vector2(1.0, 1.0), 0.1)

	# Transição suave para iniciar a partida
	var tween: Tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(root_control, "modulate:a", 0.0, 0.28)
	tween.chain().tween_callback(func():
		visible = false
		queue_free()
		class_selected.emit("gunslinger")
	)

func _on_card_fighter_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_on_fighter_pressed()

func _on_card_gunslinger_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_on_gunslinger_pressed()

func _on_card_fighter_hover(is_hovered: bool) -> void:
	if is_closing:
		return
	var target_scale: Vector2 = Vector2(1.025, 1.025) if is_hovered else Vector2.ONE
	var tween: Tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(card_fighter, "scale", target_scale, 0.12)

func _on_card_gunslinger_hover(is_hovered: bool) -> void:
	if is_closing:
		return
	var target_scale: Vector2 = Vector2(1.025, 1.025) if is_hovered else Vector2.ONE
	var tween: Tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(card_gunslinger, "scale", target_scale, 0.12)

func _show_gunslinger_notice() -> void:
	if not notice_label:
		return
	if notice_tween and notice_tween.is_valid():
		notice_tween.kill()

	notice_label.text = "⚡ A classe PISTOLEIRO está em desenvolvimento! Selecione o LUTADOR para iniciar o combate agora."
	notice_label.modulate.a = 1.0

	# Tremor sutil no card do pistoleiro para feedback tátil/visual
	if card_gunslinger:
		var shake_tween: Tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		shake_tween.tween_property(card_gunslinger, "rotation", 0.02, 0.05)
		shake_tween.tween_property(card_gunslinger, "rotation", -0.02, 0.05)
		shake_tween.tween_property(card_gunslinger, "rotation", 0.0, 0.05)

	notice_tween = create_tween()
	notice_tween.tween_interval(3.0)
	notice_tween.tween_property(notice_label, "modulate:a", 0.0, 0.4)

