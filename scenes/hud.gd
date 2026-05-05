extends CanvasLayer

@onready var hp_bar: ProgressBar = $Control/ColorRect/HBoxContainer/VBoxContainer/HPBar
@onready var exp_bar: ProgressBar = $Control/ColorRect/HBoxContainer/VBoxContainer2/ExpBar
@onready var hp_label: Label = $Control/ColorRect/HBoxContainer/VBoxContainer/HPLabel
@onready var exp_label: Label = $Control/ColorRect/HBoxContainer/VBoxContainer2/ExpLabel
@onready var crit_label: Label = $Control/ColorRect/HBoxContainer/CritLabel
@onready var pause_menu: Control = $PauseMenu

# Smooth animation targets
var target_hp: float = 0.0
var target_special: float = 0.0
var target_exp: float = 0.0

# How fast bars ease toward the target (bigger = snappier)
@export var bar_lerp_speed: float = 10.0

# Player reference (so we can apply upgrades on level up)
var player_ref: Node = null

# Level up popup UI (created in code)
var levelup_panel: PanelContainer
var levelup_title: Label
var levelup_desc: Label
var levelup_buttons: Array[Button] = []
var levelup_swirl: ColorRect
var pending_level: int = 1

# Optional nicer popup animation bits (if you already added them elsewhere)
var popup_tween: Tween = null
var dimmer: ColorRect = null

func _ready() -> void:
	# Keep HUD updating even if we pause the game for the level-up popup
	add_to_group("hud")	
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_levelup_popup()
	$PauseMenu/SettingsUI.visible = false

func bind_player(p: Node) -> void:
	player_ref = p

# --- Public API called by game.gd ---
func set_hp(value: int, max_value: int) -> void:
	hp_bar.max_value = max_value
	target_hp = float(value)
	hp_label.text = "HP %d / %d" % [value, max_value]

func set_exp(value: int, max_value: int) -> void:
	exp_bar.max_value = max_value
	target_exp = float(value)
	exp_label.text = "EXP %d / %d" % [value, max_value]

func show_level_up(new_level: int) -> void:
	pending_level = new_level
	levelup_title.text = "RIFT SURGE"
	levelup_desc.text = "Level %d reached. Choose a blessing." % new_level
	levelup_panel.visible = true
	if dimmer:
		dimmer.visible = true

	# Pause gameplay, keep UI responsive
	get_tree().paused = true

	if popup_tween and popup_tween.is_running():
		popup_tween.kill()
	levelup_panel.modulate = Color(1, 1, 1, 0)
	levelup_panel.pivot_offset = Vector2(142.0, 69.0)
	levelup_panel.scale = Vector2(0.9, 0.9)
	if dimmer:
		dimmer.color = Color(0.01, 0.01, 0.04, 0.0)

	popup_tween = create_tween()
	popup_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	popup_tween.tween_property(levelup_panel, "modulate", Color(1, 1, 1, 1), 0.16)
	popup_tween.parallel().tween_property(levelup_panel, "scale", Vector2(1, 1), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if dimmer:
		popup_tween.parallel().tween_property(dimmer, "color", Color(0.01, 0.01, 0.04, 0.66), 0.16)

# --- Smooth bar fill ---
func _process(delta: float) -> void:
	hp_bar.value = lerp(float(hp_bar.value), target_hp, bar_lerp_speed * delta)
	exp_bar.value = lerp(float(exp_bar.value), target_exp, bar_lerp_speed * delta)

# --- Popup UI creation (no .tscn changes needed) ---
func _build_levelup_popup() -> void:
	dimmer = ColorRect.new()
	dimmer.visible = false
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	dimmer.color = Color(0.01, 0.01, 0.04, 0.0)
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dimmer)

	levelup_panel = PanelContainer.new()
	levelup_panel.visible = false
	levelup_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	levelup_panel.add_theme_stylebox_override("panel", _make_levelup_panel_style())
	add_child(levelup_panel)

	levelup_panel.anchor_left = 0.5
	levelup_panel.anchor_right = 0.5
	levelup_panel.anchor_top = 0.5
	levelup_panel.anchor_bottom = 0.5
	levelup_panel.offset_left = -148
	levelup_panel.offset_right = 148
	levelup_panel.offset_top = -72
	levelup_panel.offset_bottom = 72
	levelup_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	levelup_panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	var content_root: Control = Control.new()
	content_root.clip_contents = true
	levelup_panel.add_child(content_root)

	levelup_swirl = ColorRect.new()
	levelup_swirl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	levelup_swirl.color = Color(1, 1, 1, 1)
	levelup_swirl.material = _make_levelup_swirl_material()
	levelup_swirl.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_root.add_child(levelup_swirl)

	var veil: ColorRect = ColorRect.new()
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.color = Color(0.0, 0.0, 0.06, 0.42)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_root.add_child(veil)

	var top_glow: ColorRect = ColorRect.new()
	top_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_glow.color = Color(0.24, 0.78, 1.0, 0.22)
	top_glow.anchor_right = 1.0
	top_glow.offset_bottom = 3.0
	content_root.add_child(top_glow)

	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	content_root.add_child(margin)

	var root_vbox: VBoxContainer = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 5)
	margin.add_child(root_vbox)

	var font: FontFile = load("res://assets/fonts/04B_03__.TTF") as FontFile

	levelup_title = Label.new()
	levelup_title.text = "RIFT SURGE"
	levelup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	levelup_title.add_theme_font_override("font", font)
	levelup_title.add_theme_font_size_override("font_size", 16)
	levelup_title.add_theme_color_override("font_color", Color(0.74, 0.94, 1.0, 1.0))
	levelup_title.add_theme_color_override("font_shadow_color", Color(0.0, 0.03, 0.16, 1.0))
	levelup_title.add_theme_constant_override("shadow_offset_x", 1)
	levelup_title.add_theme_constant_override("shadow_offset_y", 2)
	root_vbox.add_child(levelup_title)

	levelup_desc = Label.new()
	levelup_desc.text = "Choose a blessing."
	levelup_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	levelup_desc.add_theme_font_override("font", font)
	levelup_desc.add_theme_font_size_override("font_size", 8)
	levelup_desc.add_theme_color_override("font_color", Color(0.89, 0.96, 1.0, 1.0))
	root_vbox.add_child(levelup_desc)

	var divider: ColorRect = ColorRect.new()
	divider.color = Color(0.18, 0.66, 1.0, 0.72)
	divider.custom_minimum_size = Vector2(0, 2)
	root_vbox.add_child(divider)

	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root_vbox.add_child(btn_row)

	for i in range(3):
		var b: Button = Button.new()
		b.custom_minimum_size = Vector2(82, 48)
		b.add_theme_font_override("font", font)
		b.add_theme_font_size_override("font_size", 8)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		_style_levelup_button(b)
		btn_row.add_child(b)
		levelup_buttons.append(b)

		var idx: int = i
		b.pressed.connect(func(): _on_upgrade_chosen(idx))

	_refresh_upgrade_text()

func _refresh_upgrade_text() -> void:
	levelup_buttons[0].text = "VITAL\n+10 Max HP"
	levelup_buttons[1].text = "SWIFT\n+10% Speed"
	levelup_buttons[2].text = "LUCK\n+5% Crit"

func _make_levelup_swirl_material() -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	var shader_resource: Shader = load("res://assets/art/ui/swirl_bg.gdshader") as Shader
	if shader_resource != null:
		material.shader = shader_resource
		material.set_shader_parameter("spin_speed", 4.0)
		material.set_shader_parameter("spin_amount", 0.58)
		material.set_shader_parameter("contrast", 2.4)
		material.set_shader_parameter("pixel_filter", 520.0)
		material.set_shader_parameter("colour_1", Color(0.02, 0.05, 0.55, 1.0))
		material.set_shader_parameter("colour_2", Color(0.0, 0.0, 0.035, 1.0))
		material.set_shader_parameter("colour_3", Color(0.28, 0.78, 1.0, 1.0))
	return material

func _make_levelup_panel_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.01, 0.02, 0.09, 0.96)
	style.border_color = Color(0.28, 0.78, 1.0, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 4)
	style.content_margin_left = 0
	style.content_margin_top = 0
	style.content_margin_right = 0
	style.content_margin_bottom = 0
	return style

func _style_levelup_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _make_levelup_button_style(Color(0.02, 0.08, 0.20, 0.90), Color(0.25, 0.66, 1.0, 0.80)))
	button.add_theme_stylebox_override("hover", _make_levelup_button_style(Color(0.06, 0.18, 0.36, 0.96), Color(0.82, 0.94, 1.0, 1.0)))
	button.add_theme_stylebox_override("pressed", _make_levelup_button_style(Color(0.03, 0.10, 0.24, 1.0), Color(1.0, 0.82, 0.36, 1.0)))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", Color(0.88, 0.97, 1.0, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.96, 0.72, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(0.76, 0.93, 1.0, 1.0))
	button.add_theme_color_override("font_shadow_color", Color(0.0, 0.02, 0.08, 1.0))
	button.add_theme_constant_override("shadow_offset_x", 1)
	button.add_theme_constant_override("shadow_offset_y", 1)

func _make_levelup_button_style(fill_color: Color, border_color: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 5
	style.content_margin_top = 5
	style.content_margin_right = 5
	style.content_margin_bottom = 5
	return style

# --- Apply upgrades ---
func _on_upgrade_chosen(choice: int) -> void:
	_apply_upgrade(choice)

	# Animate out
	if popup_tween and popup_tween.is_running():
		popup_tween.kill()

	popup_tween = create_tween()
	popup_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)

	popup_tween.tween_property(levelup_panel, "modulate", Color(1, 1, 1, 0), 0.12)
	popup_tween.parallel().tween_property(levelup_panel, "scale", Vector2(0.9, 0.9), 0.12)
	if dimmer:
		popup_tween.parallel().tween_property(dimmer, "color", Color(0.01, 0.01, 0.04, 0.0), 0.12)

	popup_tween.finished.connect(func():
		levelup_panel.visible = false
		if dimmer:
			dimmer.visible = false
		get_tree().paused = false
	)

func _apply_upgrade(choice: int) -> void:
	if player_ref == null:
		return

	match choice:
		0:
			# +10 Max HP (and heal +10)
			var hc = player_ref.get_node_or_null("HealthComponent")
			if hc:
				hc.max_health += 10
				hc.current_health = min(hc.current_health + 10, hc.max_health)

				# Update HUD immediately if signal exists
				if hc.has_signal("health_changed"):
					hc.health_changed.emit(hc.current_health, hc.max_health)

		1:
			# +10% Move Speed
			var mv = player_ref.get_node_or_null("MovementComponent")
			if mv != null:
				# MovementComponent.gd has "speed"
				mv.speed *= 1.10

		2:
			# +5% Critical Chance
			var current: float = 0.0
			if player_ref.has_meta("crit_chance"):
				current = float(player_ref.get_meta("crit_chance"))

			current = min(current + 0.05, 1.0)
			player_ref.set_meta("crit_chance", current)
			RunManager.run_data.stats["crit_chance"] = current

			# Update HUD label
			if crit_label:
				crit_label.text = "CRIT %d%%" % int(current * 100)


func _on_main_menu_pressed() -> void:
	get_tree().paused = false
	if RunManager.is_run_active:
		RunManager.end_run()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"): # ESC by default
		_toggle_pause_menu()
	

func _toggle_pause_menu() -> void:
	var is_open = pause_menu.visible
	pause_menu.visible = not is_open
	get_tree().paused = not is_open
	if dimmer:
		dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _on_resume_pressed() -> void:
	pause_menu.visible = false
	get_tree().paused = false

func _on_settings_pressed() -> void:
	$PauseMenu/SettingsUI.visible = true
	$PauseMenu/SettingsUI.is_overlay = true

func hide_settings():
	$PauseMenu/SettingsUI.visible = false

func _on_save_exit_pressed() -> void:
	get_tree().paused = false
	RunManager.save_current_run()
	await TransitionLayer.play_out()
	await get_tree().create_timer(0.3).timeout
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	await TransitionLayer.play_in()

func _on_quit_run_pressed() -> void:
	get_tree().paused = false
	if RunManager.is_run_active:
		RunManager.end_run()
	await TransitionLayer.play_out()
	await get_tree().create_timer(0.3).timeout
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	await TransitionLayer.play_in()
