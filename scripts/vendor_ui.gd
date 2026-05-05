extends CanvasLayer
class_name VendorUI

signal vendor_closed

@onready var stage_label: Label = $Root/Panel/Margin/Layout/ShopColumn/Title
@onready var panel: PanelContainer = $Root/Panel
@onready var gold_label: Label = $Root/Panel/Margin/Layout/ShopColumn/Gold
@onready var offers_row: HBoxContainer = $Root/Panel/Margin/Layout/ShopColumn/Offers
@onready var status_label: Label = $Root/Panel/Margin/Layout/ShopColumn/Status
@onready var continue_button: Button = $Root/Panel/Margin/Layout/ShopColumn/Actions/Continue
@onready var map_caption_label: Label = $Root/Panel/Margin/Layout/TravelColumn/MapCaption

const OFFER_POOL: Array[Dictionary] = [
	{
		"id": "offer_heal",
		"title": "Field Rations",
		"description": "Heal 35% max HP.",
		"cost": 22,
	},
	{
		"id": "offer_attack",
		"title": "Sharpening Stone",
		"description": "+3 Attack this run.",
		"cost": 30,
	},
	{
		"id": "offer_max_health",
		"title": "Vital Charm",
		"description": "+12 Max HP and heal 12.",
		"cost": 34,
	},
	{
		"id": "offer_crit",
		"title": "Lucky Charm",
		"description": "+3% Crit Chance.",
		"cost": 28,
	},
	{
		"id": "offer_crit_damage",
		"title": "Keen Edge",
		"description": "+20% Crit Damage.",
		"cost": 36,
	},
	{
		"id": "offer_move_speed",
		"title": "Fleet Boots",
		"description": "+8% Move Speed.",
		"cost": 26,
	},
	{
		"id": "offer_jump_power",
		"title": "Sky Sigil",
		"description": "+8% Jump Power.",
		"cost": 25,
	},
	{
		"id": "offer_full_heal",
		"title": "Blessed Flask",
		"description": "Restore to full HP.",
		"cost": 32,
	},
	{
		"id": "offer_armor",
		"title": "Rune Plating",
		"description": "+2 Defense.",
		"cost": 27,
	},
	{
		"id": "offer_attack_big",
		"title": "War Banner",
		"description": "+5 Attack this run.",
		"cost": 48,
	},
	{
		"id": "offer_crit_big",
		"title": "Hunter's Oath",
		"description": "+6% Crit Chance.",
		"cost": 42,
	},
	{
		"id": "offer_discount_heal",
		"title": "Camp Rest",
		"description": "Heal 20% HP for cheap.",
		"cost": 12,
	},
]
const OFFERS_PER_SHOP: int = 3

var _offers: Array[Dictionary] = []
var _offer_buttons: Array[Button] = []
var _is_open: bool = false
var _current_stage: int = 1
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_rng.randomize()
	_style_panel()
	_style_continue_button()
	if not continue_button.pressed.is_connected(_on_continue_pressed):
		continue_button.pressed.connect(_on_continue_pressed)

func open_vendor(stage: int) -> void:
	_current_stage = max(stage, 1)
	_seed_vendor_rng(_current_stage)
	_offers = _build_offers_for_stage(_current_stage)
	_rebuild_offer_buttons()
	_refresh_header()
	status_label.text = "Restock, patch up, then choose the road ahead."
	map_caption_label.text = "Stage %d cleared. The next fork waits beyond camp." % _current_stage
	visible = true
	_is_open = true
	get_tree().paused = true
	if not _offer_buttons.is_empty():
		_offer_buttons[0].grab_focus()
	else:
		continue_button.grab_focus()

func close_vendor() -> void:
	_is_open = false
	visible = false
	get_tree().paused = false
	emit_signal("vendor_closed")

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		close_vendor()
		get_viewport().set_input_as_handled()

func _on_continue_pressed() -> void:
	close_vendor()

func _build_offers_for_stage(stage: int) -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	var available_indices: Array[int] = []
	for i in range(OFFER_POOL.size()):
		available_indices.append(i)

	var offer_count: int = mini(OFFERS_PER_SHOP, available_indices.size())
	for _slot in range(offer_count):
		var random_pool_index: int = _rng.randi_range(0, available_indices.size() - 1)
		var source_index: int = available_indices[random_pool_index]
		available_indices.remove_at(random_pool_index)
		var source_offer: Dictionary = OFFER_POOL[source_index]
		var offer: Dictionary = source_offer.duplicate(true)
		var stage_markup: int = int(floor(float(max(stage - 1, 0)) * 2.5))
		offer["cost"] = int(source_offer.get("cost", 0)) + stage_markup
		offer["purchased"] = false
		offers.append(offer)
	return offers

func _rebuild_offer_buttons() -> void:
	for child in offers_row.get_children():
		child.queue_free()
	_offer_buttons.clear()

	for idx in range(_offers.size()):
		var offer: Dictionary = _offers[idx]
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(64, 70)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.focus_mode = Control.FOCUS_ALL
		button.add_theme_font_size_override("font_size", 8)
		button.text = _format_offer_text(offer)
		_style_offer_button(button)
		button.pressed.connect(_on_offer_pressed.bind(idx))
		offers_row.add_child(button)
		_offer_buttons.append(button)

	_refresh_offer_button_states()

func _on_offer_pressed(index: int) -> void:
	_try_purchase_offer(index)

func _try_purchase_offer(index: int) -> void:
	if index < 0 or index >= _offers.size():
		return
	if RunManager.run_data == null:
		status_label.text = "No active run data."
		return

	var offer: Dictionary = _offers[index]
	if bool(offer.get("purchased", false)):
		status_label.text = "Already purchased."
		return

	var cost: int = int(offer.get("cost", 0))
	var current_gold: int = int(RunManager.run_data.resources.get("gold", 0))
	if current_gold < cost:
		status_label.text = "Not enough gold."
		return

	RunManager.run_data.resources["gold"] = current_gold - cost
	_apply_offer_effect(offer)
	var game = get_tree().get_first_node_in_group("game")
	if game:
		game._sync_player_stats_from_run_data()

	offer["purchased"] = true
	_offers[index] = offer
	status_label.text = "%s purchased." % String(offer.get("title", "Offer"))
	_refresh_header()
	_refresh_offer_button_states()

func _apply_offer_effect(offer: Dictionary) -> void:
	if RunManager.run_data == null:
		return

	var offer_id: String = String(offer.get("id", ""))
	var stats: Dictionary = RunManager.run_data.stats

	match offer_id:
		"offer_heal":
			var max_health: int = int(stats.get("max_health", 100))
			var current_health: int = int(stats.get("health", max_health))
			var heal_amount: int = int(round(float(max_health) * 0.35))
			stats["health"] = min(max_health, current_health + heal_amount)
		"offer_discount_heal":
			var max_health_discount: int = int(stats.get("max_health", 100))
			var current_health_discount: int = int(stats.get("health", max_health_discount))
			var heal_amount_discount: int = int(round(float(max_health_discount) * 0.20))
			stats["health"] = min(max_health_discount, current_health_discount + heal_amount_discount)
		"offer_full_heal":
			var max_health_full: int = int(stats.get("max_health", 100))
			stats["health"] = max_health_full
		"offer_attack":
			stats["attack"] = float(stats.get("attack", 10.0)) + 3.0
		"offer_attack_big":
			stats["attack"] = float(stats.get("attack", 10.0)) + 5.0
		"offer_max_health":
			var boosted_max: int = int(stats.get("max_health", 100)) + 12
			var boosted_health: int = int(stats.get("health", boosted_max)) + 12
			stats["max_health"] = boosted_max
			stats["health"] = min(boosted_max, boosted_health)
		"offer_crit":
			var crit: float = float(stats.get("crit_chance", 0.05))
			stats["crit_chance"] = min(crit + 0.03, 1.0)
		"offer_crit_big":
			var crit_big: float = float(stats.get("crit_chance", 0.05))
			stats["crit_chance"] = min(crit_big + 0.06, 1.0)
		"offer_crit_damage":
			var crit_damage: float = float(stats.get("crit_damage", 1.5))
			stats["crit_damage"] = crit_damage + 0.20
		"offer_move_speed":
			var move_speed: float = float(stats.get("move_speed", 1.0))
			stats["move_speed"] = move_speed + 0.08
		"offer_jump_power":
			var jump_power: float = float(stats.get("jump_power", 1.0))
			stats["jump_power"] = jump_power + 0.08
		"offer_armor":
			var defense: float = float(stats.get("defense", 0.0))
			stats["defense"] = defense + 2.0

func _seed_vendor_rng(stage: int) -> void:
	if RunManager.run_data == null:
		_rng.randomize()
		return
	var seed_value: int = int(RunManager.run_data.run_seed) + stage * 973 + RunManager.run_data.cleared_stages * 197
	_rng.seed = seed_value

func _refresh_header() -> void:
	stage_label.text = "Vendor Camp - Stage %d Clear" % _current_stage
	var gold: int = 0
	if RunManager.run_data != null:
		gold = int(RunManager.run_data.resources.get("gold", 0))
	gold_label.text = "Gold: %d" % gold

func _refresh_offer_button_states() -> void:
	for idx in range(_offer_buttons.size()):
		var offer: Dictionary = _offers[idx]
		var button: Button = _offer_buttons[idx]
		var purchased: bool = bool(offer.get("purchased", false))
		if purchased:
			button.disabled = true
			button.modulate = Color(0.55, 0.75, 0.55, 1.0)
		else:
			button.disabled = false
			button.modulate = Color(1.0, 1.0, 1.0, 1.0)

func _format_offer_text(offer: Dictionary) -> String:
	var title: String = _shorten_title(String(offer.get("title", "Offer")))
	var description: String = _shorten_description(String(offer.get("id", "")), String(offer.get("description", "")))
	var cost: int = int(offer.get("cost", 0))
	return "%s\n%s\n%d Gold" % [title, description, cost]

func _shorten_title(title: String) -> String:
	match title:
		"Field Rations":
			return "Field\nRations"
		"Sharpening Stone":
			return "Sharpen\nStone"
		"Vital Charm":
			return "Vital\nCharm"
		"Lucky Charm":
			return "Lucky\nCharm"
		"Keen Edge":
			return "Keen\nEdge"
		"Fleet Boots":
			return "Fleet\nBoots"
		"Sky Sigil":
			return "Sky\nSigil"
		"Blessed Flask":
			return "Blessed\nFlask"
		"Rune Plating":
			return "Rune\nPlate"
		"War Banner":
			return "War\nBanner"
		"Hunter's Oath":
			return "Hunter\nOath"
		"Camp Rest":
			return "Camp\nRest"
	return title

func _shorten_description(offer_id: String, description: String) -> String:
	match offer_id:
		"offer_heal":
			return "Heal 35%"
		"offer_attack":
			return "+3 ATK"
		"offer_max_health":
			return "+12 Max HP"
		"offer_crit":
			return "+3% Crit"
		"offer_crit_damage":
			return "+20% CDmg"
		"offer_move_speed":
			return "+8% Speed"
		"offer_jump_power":
			return "+8% Jump"
		"offer_full_heal":
			return "Full Heal"
		"offer_armor":
			return "+2 DEF"
		"offer_attack_big":
			return "+5 ATK"
		"offer_crit_big":
			return "+6% Crit"
		"offer_discount_heal":
			return "Heal 20%"
	return description

func _style_panel() -> void:
	panel.add_theme_stylebox_override("panel", _make_panel_style())

func _style_offer_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _make_button_style(Color(0.18, 0.12, 0.08, 0.94), Color(0.72, 0.43, 0.18, 1.0)))
	button.add_theme_stylebox_override("hover", _make_button_style(Color(0.28, 0.18, 0.1, 0.98), Color(0.95, 0.68, 0.3, 1.0)))
	button.add_theme_stylebox_override("pressed", _make_button_style(Color(0.11, 0.08, 0.06, 1.0), Color(1.0, 0.8, 0.36, 1.0)))
	button.add_theme_stylebox_override("focus", _make_button_style(Color(0.22, 0.15, 0.09, 0.98), Color(1.0, 0.84, 0.38, 1.0)))
	button.add_theme_stylebox_override("disabled", _make_button_style(Color(0.12, 0.18, 0.12, 0.9), Color(0.44, 0.72, 0.36, 1.0)))
	button.add_theme_color_override("font_color", Color(0.96, 0.86, 0.63, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.76, 1.0))
	button.add_theme_color_override("font_focus_color", Color(1.0, 0.95, 0.76, 1.0))
	button.add_theme_color_override("font_disabled_color", Color(0.74, 0.92, 0.66, 1.0))

func _style_continue_button() -> void:
	continue_button.add_theme_stylebox_override("normal", _make_button_style(Color(0.16, 0.27, 0.23, 0.96), Color(0.4, 0.76, 0.58, 1.0)))
	continue_button.add_theme_stylebox_override("hover", _make_button_style(Color(0.2, 0.37, 0.31, 1.0), Color(0.65, 0.96, 0.74, 1.0)))
	continue_button.add_theme_stylebox_override("pressed", _make_button_style(Color(0.09, 0.18, 0.16, 1.0), Color(0.83, 1.0, 0.78, 1.0)))
	continue_button.add_theme_stylebox_override("focus", _make_button_style(Color(0.2, 0.37, 0.31, 1.0), Color(0.83, 1.0, 0.78, 1.0)))
	continue_button.add_theme_color_override("font_color", Color(0.9, 1.0, 0.82, 1.0))

func _make_button_style(fill_color: Color, border_color: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = border_color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_left = 3.0
	style.content_margin_top = 3.0
	style.content_margin_right = 3.0
	style.content_margin_bottom = 3.0
	return style

func _make_panel_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.07, 0.055, 0.78)
	style.border_color = Color(0.68, 0.43, 0.2, 1.0)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	return style
