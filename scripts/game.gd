extends Node2D

@onready var hud = $HUD
@onready var player = $Player
@onready var vendor_ui = $VendorUI
@onready var world_map_ui = $WorldMapUI

@onready var level_container: Node = $LevelContainer
@export var enemy_scene: PackedScene
@export var enemy_skirmisher_scene: PackedScene
@export var enemy_ranger_scene: PackedScene
@export var enemy_brute_scene: PackedScene
@export var mini_boss_enemy_scene: PackedScene
@export var boss_blade_scene: PackedScene
@export var boss_pyromancer_scene: PackedScene
@export var boss_guardian_scene: PackedScene
@export var portal_scene: PackedScene
var current_level: Node = null
var active_enemies: Array[Node] = []
var current_stage: int = 1
var player_spawn_position: Vector2 = Vector2.ZERO
var stage_portal_root: Node2D = null
var transitioning_stage: bool = false
var stage_clear_recorded: bool = false
var is_vendor_open: bool = false
var is_world_map_open: bool = false
var current_level_config: Dictionary = {}
var level_enemy_archetype: String = "skirmisher"
var has_cached_player_baselines: bool = false
var base_move_speed: float = 100.0
var base_sprint_speed: float = 160.0
var base_jump_velocity: float = -350.0

@export var respawn_delay: float = 1.0

func _process(_delta: float) -> void:
	if player.has_node("HealthComponent"):
		var hc: HealthComponent = player.get_node("HealthComponent")
		hud.set_hp(hc.current_health, hc.max_health)
		if RunManager.run_data:
			RunManager.run_data.stats["max_health"] = hc.max_health

	if player.has_node("ExperienceComponent"):
		var xp: ExperienceComponent = player.get_node("ExperienceComponent")
		hud.set_exp(xp.experience, xp.exp_to_next)

	_prune_active_enemies()
	_try_spawn_stage_portal()
	_try_manual_stage_advance()

func _ready() -> void:
	add_to_group("game")
	if enemy_scene == null:
		enemy_scene = load("res://scenes/enemies/enemy_grunt.tscn")
	if enemy_skirmisher_scene == null:
		enemy_skirmisher_scene = load("res://scenes/enemies/enemy_skirmisher.tscn")
	if enemy_ranger_scene == null:
		enemy_ranger_scene = load("res://scenes/enemies/enemy_ranger.tscn")
	if enemy_brute_scene == null:
		enemy_brute_scene = load("res://scenes/enemies/enemy_brute.tscn")
	if mini_boss_enemy_scene == null:
		mini_boss_enemy_scene = load("res://scenes/enemies/enemy_mini_boss.tscn")
	if boss_blade_scene == null:
		boss_blade_scene = load("res://scenes/enemies/boss_blade_champion.tscn")
	if boss_pyromancer_scene == null:
		boss_pyromancer_scene = load("res://scenes/enemies/boss_pyromancer.tscn")
	if boss_guardian_scene == null:
		boss_guardian_scene = load("res://scenes/enemies/boss_guardian.tscn")
	if portal_scene == null:
		portal_scene = load("res://scenes/portal_anim.tscn")

	if not RunManager.is_run_active or RunManager.run_data == null:
		RunManager.start_new_run()

	current_stage = RunManager.get_current_stage()
	current_level_config = RunManager.get_current_level_config()

	_bind_player_signals()
	_bind_vendor_signals()
	_bind_world_map_signals()
	_hook_hud_signals()
	_cache_player_baselines()
	_sync_player_stats_from_run_data()
	_load_stage_from_config(current_level_config)

func _load_stage_from_config(level_config: Dictionary) -> void:
	stage_clear_recorded = false
	current_level_config = level_config.duplicate(true)
	level_enemy_archetype = _resolve_level_enemy_archetype(current_level_config)
	current_level_config["enemy_archetype"] = level_enemy_archetype
	var generated_level: Node2D = LevelLoader.generate_level(current_level_config)
	load_generated_level(generated_level)

func load_generated_level(level_node: Node2D) -> void:
	if current_level:
		current_level.queue_free()
		current_level = null

	clear_active_enemies()
	_clear_stage_portal()

	level_container.add_child(level_node)
	current_level = level_node

	var spawn = level_node.find_child("PlayerSpawn", true, false)
	if spawn:
		player.global_position = spawn.global_position
		player_spawn_position = spawn.global_position
		if player is CharacterBody2D:
			(player as CharacterBody2D).velocity = Vector2.ZERO
	_apply_camera_limits()
	$Camera2D.global_position = player.global_position
	$Camera2D.reset_smoothing()
	$Camera2D.reset_camera()

	if portal_scene:
		var portal = portal_scene.instantiate()
		current_level.add_child(portal)
		portal.global_position = player.global_position + Vector2(-2, -24)

	spawn_enemies_for_chunks()

func _apply_camera_limits() -> void:
	if current_level == null:
		return

	var start_chunk: Node = null
	if current_level.get_child_count() > 0:
		start_chunk = current_level.get_child(0)
	if start_chunk and start_chunk.has_node("BottomLeft"):
		var bl_marker: Marker2D = start_chunk.get_node("BottomLeft") as Marker2D
		$Camera2D.limit_left = int(bl_marker.global_position.x)
		$Camera2D.limit_bottom = int(bl_marker.global_position.y + 16)

	var tr_marker: Marker2D = current_level.find_child("TopRight", true, false) as Marker2D
	if tr_marker:
		$Camera2D.limit_right = int(tr_marker.global_position.x)
		$Camera2D.limit_top = int(tr_marker.global_position.y + 16)

func spawn_enemies_for_chunks() -> void:
	if current_level == null: return
	var enemy_multiplier: float = _get_enemy_multiplier_for_level()
	var spawn_entries: Array[Dictionary] = _collect_spawn_entries()
	if spawn_entries.is_empty():
		return

	if _is_mini_boss_level():
		#_spawn_boss_for_level(_extract_markers_from_entries(spawn_entries))
		return

	for entry in spawn_entries:
		_spawn_enemies_from_entry(entry, enemy_multiplier)

func _resolve_level_enemy_archetype(level_config: Dictionary) -> String:
	var explicit_archetype: String = String(level_config.get("enemy_archetype", ""))
	if explicit_archetype == "skirmisher" or explicit_archetype == "ranger" or explicit_archetype == "brute":
		return explicit_archetype

	var node_type: String = String(level_config.get("node_type", "path_combat"))
	match node_type:
		"path_recovery":
			return "skirmisher"
		"path_treasure":
			return "ranger"
		"path_elite":
			return "brute"

	var choice_id: String = String(level_config.get("choice_id", "default"))
	var stage_value: int = int(level_config.get("stage", current_stage))
	var seed_basis: String = "%s|%d|%s" % [choice_id, stage_value, node_type]
	var archetypes: Array[String] = ["skirmisher", "ranger", "brute"]
	var seed_hash: int = int(abs(seed_basis.hash()))
	return archetypes[seed_hash % archetypes.size()]

func _collect_spawn_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if current_level == null:
		return entries

	var combat_chunk_count: int = 0
	for chunk in current_level.get_children():
		if chunk.get_node_or_null("EnemySpawns") != null:
			combat_chunk_count += 1
	if combat_chunk_count <= 0:
		return entries

	var combat_chunk_index: int = 0

	for chunk in current_level.get_children():
		var spawn_container: Node = chunk.get_node_or_null("EnemySpawns")
		if spawn_container == null:
			continue

		var section_index: int = _get_section_index(combat_chunk_index, combat_chunk_count)
		for marker_node in spawn_container.get_children():
			if marker_node is Marker2D:
				entries.append({
					"marker": marker_node as Marker2D,
					"section_index": section_index,
				})
		combat_chunk_index += 1

	return entries

func _extract_markers_from_entries(spawn_entries: Array[Dictionary]) -> Array[Marker2D]:
	var markers: Array[Marker2D] = []
	for entry in spawn_entries:
		var marker_value: Variant = entry.get("marker", null)
		var marker: Marker2D = marker_value as Marker2D
		if marker:
			markers.append(marker)
	return markers

func _get_section_index(combat_chunk_index: int, combat_chunk_count: int) -> int:
	if combat_chunk_count <= 1:
		return 0
	var denominator: float = float(maxi(combat_chunk_count - 1, 1))
	var progress: float = float(combat_chunk_index) / denominator
	if progress < 0.34:
		return 0
	if progress < 0.67:
		return 1
	return 2

func _is_mini_boss_level() -> bool:
	if current_level == null or not current_level.has_meta("level_config"):
		return false
	var cfg: Dictionary = current_level.get_meta("level_config") as Dictionary
	return bool(cfg.get("boss_stage", false)) or bool(cfg.get("mini_boss_stage", false))

func _spawn_mini_boss_for_level(spawn_markers: Array[Marker2D]) -> void:
	_spawn_boss_for_level(spawn_markers)

func _spawn_boss_for_level(spawn_markers: Array[Marker2D]) -> void:
	if spawn_markers.is_empty():
		return

	var boss_marker: Marker2D = spawn_markers[0]
	var max_distance_sq: float = -1.0
	for marker in spawn_markers:
		var dist_sq: float = marker.global_position.distance_squared_to(player_spawn_position)
		if dist_sq > max_distance_sq:
			max_distance_sq = dist_sq
			boss_marker = marker

	var stage_scale: float = 1.0 + (float(max(current_stage - 1, 0)) * 0.18)
	var boss_profile: Dictionary = _get_boss_profile_for_stage()
	var boss_scene_value: Variant = boss_profile.get("scene", mini_boss_enemy_scene)
	var boss_scene: PackedScene = boss_scene_value as PackedScene
	if boss_scene == null:
		boss_scene = mini_boss_enemy_scene

	var boss_config: Dictionary = {
		"mini_boss": true,
		"max_health": int(round(float(boss_profile.get("health", 110.0)) * stage_scale)),
		"attack_damage": int(round(float(boss_profile.get("damage", 16.0)) + float(current_stage) * 2.0)),
		"move_speed": float(boss_profile.get("speed", 48.0)) + (float(current_stage) * 1.4),
		"projectile_damage": int(round(float(boss_profile.get("projectile_damage", 10.0)) + float(current_stage) * 1.8)),
		"xp_reward": int(round(float(boss_profile.get("xp", 130.0)) * stage_scale)),
		"gold_reward": int(round(float(boss_profile.get("gold", 40.0)) * stage_scale)),
	}
	_spawn_single_enemy(boss_marker.global_position, boss_config, boss_scene)

func _get_boss_profile_for_stage() -> Dictionary:
	var boss_cycle_index: int = maxi(int(floor(float(current_stage) / 3.0)) - 1, 0) % 4
	match boss_cycle_index:
		0:
			return {
				"scene": boss_blade_scene,
				"health": 120.0,
				"damage": 18.0,
				"speed": 58.0,
				"projectile_damage": 8.0,
				"xp": 135.0,
				"gold": 42.0,
			}
		1:
			return {
				"scene": boss_pyromancer_scene,
				"health": 105.0,
				"damage": 15.0,
				"speed": 44.0,
				"projectile_damage": 14.0,
				"xp": 145.0,
				"gold": 48.0,
			}
		2:
			return {
				"scene": boss_guardian_scene,
				"health": 155.0,
				"damage": 22.0,
				"speed": 34.0,
				"projectile_damage": 11.0,
				"xp": 160.0,
				"gold": 55.0,
			}
		_:
			return {
				"scene": preload("res://scenes/enemies/boss_swicther.tscn"),
				"health": 160.0,
				"damage": 18.0,
				"speed": 95.0,
				"projectile_damage": 12.0,
				"xp": 300.0,
				"gold": 100.0,
				"ranged_projectile_count": 8,
				"ranged_projectile_spread_degrees": 360.0
			}

func _spawn_enemies_from_entry(entry: Dictionary, enemy_multiplier: float) -> void:
	if enemy_multiplier <= 0.0:
		return

	var marker: Marker2D = entry.get("marker", null) as Marker2D
	if marker == null:
		return
	var section_index: int = int(entry.get("section_index", 0))

	if enemy_multiplier < 1.0 and randf() > enemy_multiplier:
		return

	_spawn_section_enemy(marker.global_position, section_index)

	var guaranteed_extras: int = maxi(int(floor(enemy_multiplier)) - 1, 0)
	for _i in range(guaranteed_extras):
		_spawn_section_enemy(marker.global_position + _random_spawn_jitter(), section_index)

	var fractional: float = enemy_multiplier - float(floor(enemy_multiplier))
	if fractional > 0.0 and randf() < fractional:
		_spawn_section_enemy(marker.global_position + _random_spawn_jitter(), section_index)

func _spawn_section_enemy(position: Vector2, section_index: int) -> void:
	var spawn_plan: Dictionary = _build_section_enemy_spawn(section_index)
	var scene_value: Variant = spawn_plan.get("scene", null)
	var scene_to_spawn: PackedScene = scene_value as PackedScene
	var config_value: Variant = spawn_plan.get("config", {})
	var config: Dictionary = {}
	if config_value is Dictionary:
		config = (config_value as Dictionary).duplicate(true)
	_spawn_single_enemy(position, config, scene_to_spawn)

func _build_section_enemy_spawn(section_index: int) -> Dictionary:
	var stage_scale: float = 1.0 + (float(max(current_stage - 1, 0)) * 0.1)
	var section_scale: float = 1.0
	if section_index <= 0:
		section_scale = 0.92
	elif section_index >= 2:
		section_scale = 1.12

	var total_scale: float = stage_scale * section_scale
	var scene_to_spawn: PackedScene = enemy_scene
	var config: Dictionary = {}

	match level_enemy_archetype:
		"ranger":
			if enemy_ranger_scene != null:
				scene_to_spawn = enemy_ranger_scene
			config = {
				"max_health": int(round(24.0 * total_scale)),
				"attack_damage": int(round(7.0 + float(current_stage) * 1.0)),
				"move_speed": 53.0 + (float(current_stage) * 1.0),
				"projectile_damage": int(round(8.0 + float(current_stage) * 1.15)),
				"xp_reward": int(round(30.0 * total_scale)),
				"gold_reward": int(round(8.0 * total_scale)),
			}
		"brute":
			if enemy_brute_scene != null:
				scene_to_spawn = enemy_brute_scene
			config = {
				"max_health": int(round(50.0 * total_scale)),
				"attack_damage": int(round(13.0 + float(current_stage) * 1.35)),
				"move_speed": 35.0 + (float(current_stage) * 0.9),
				"xp_reward": int(round(43.0 * total_scale)),
				"gold_reward": int(round(11.0 * total_scale)),
			}
		_:
			if enemy_skirmisher_scene != null:
				scene_to_spawn = enemy_skirmisher_scene
			config = {
				"max_health": int(round(28.0 * total_scale)),
				"attack_damage": int(round(8.0 + float(current_stage) * 1.0)),
				"move_speed": 57.0 + (float(current_stage) * 1.25),
				"xp_reward": int(round(27.0 * total_scale)),
				"gold_reward": int(round(7.0 * total_scale)),
			}

	return {
		"scene": scene_to_spawn,
		"config": config,
	}

func _spawn_single_enemy(
	position: Vector2,
	enemy_config: Dictionary = {},
	scene_override: PackedScene = null
) -> void:
	if current_level == null:
		return

	var scene_to_spawn: PackedScene = scene_override if scene_override != null else enemy_scene
	if scene_to_spawn == null:
		return
	print("SPAWN:", scene_to_spawn)
	var enemy: Node = scene_to_spawn.instantiate()
	_configure_enemy(enemy, enemy_config)
	current_level.add_child(enemy)
	if enemy is Node2D:
		(enemy as Node2D).global_position = position
	_style_enemy_visuals(enemy, enemy_config, scene_override != null)
	active_enemies.append(enemy)

func _configure_enemy(enemy: Node, enemy_config: Dictionary) -> void:
	if enemy_config.is_empty():
		return
	_set_enemy_property_if_exists(enemy, "threat_tier", 1 if bool(enemy_config.get("mini_boss", false)) else 0)
	_set_enemy_property_if_exists(enemy, "max_health", int(enemy_config.get("max_health", 30)))
	_set_enemy_property_if_exists(enemy, "attack_damage", int(enemy_config.get("attack_damage", 10)))
	_set_enemy_property_if_exists(enemy, "move_speed", float(enemy_config.get("move_speed", 40.0)))
	_set_enemy_property_if_exists(enemy, "projectile_damage", int(enemy_config.get("projectile_damage", 10)))
	_set_enemy_property_if_exists(enemy, "xp_reward", int(enemy_config.get("xp_reward", -1)))
	_set_enemy_property_if_exists(enemy, "gold_reward", int(enemy_config.get("gold_reward", -1)))

func _set_enemy_property_if_exists(enemy: Object, property_name: String, value: Variant) -> void:
	if _object_has_property(enemy, property_name):
		enemy.set(property_name, value)

func _object_has_property(obj: Object, property_name: String) -> bool:
	var properties: Array = obj.get_property_list()
	for raw_prop in properties:
		var prop: Dictionary = raw_prop as Dictionary
		if String(prop.get("name", "")) == property_name:
			return true
	return false

func _style_enemy_visuals(enemy: Node, enemy_config: Dictionary, using_custom_scene: bool) -> void:
	if not bool(enemy_config.get("mini_boss", false)):
		return
	if using_custom_scene:
		return
	var body: Node2D = enemy.get_node_or_null("Body") as Node2D
	if body:
		body.scale = Vector2(1.55, 1.55)
		body.modulate = Color(0.95, 0.72, 0.72, 1.0)

func _random_spawn_jitter() -> Vector2:
	return Vector2(randf_range(-18.0, 18.0), randf_range(-8.0, 8.0))

func _get_enemy_multiplier_for_level() -> float:
	# DISABLED (for now)
	#if current_level and current_level.has_meta("level_config"):
		#var cfg: Dictionary = current_level.get_meta("level_config") as Dictionary
		#return clampf(float(cfg.get("enemy_multiplier", 1.0)), 0.25, 3.0)
	return 1.0

func clear_active_enemies() -> void:
	for enemy in active_enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	active_enemies.clear()

func _prune_active_enemies() -> void:
	var remaining: Array[Node] = []
	for enemy in active_enemies:
		if is_instance_valid(enemy):
			remaining.append(enemy)
	active_enemies = remaining

func _bind_player_signals() -> void:
	if player == null or not player.has_signal("player_died"):
		return
	var died_callable: Callable = Callable(self, "_on_player_died")
	if not player.is_connected("player_died", died_callable):
		player.connect("player_died", died_callable)

func _on_player_died() -> void:
	if transitioning_stage or is_world_map_open or is_vendor_open:
		return
	_handle_death_sequence()

func _handle_death_sequence() -> void:
	transitioning_stage = true
	var hud = get_node_or_null("HUD")
	if hud:
		hud.visible = false
	if player:
		player.set_process(false)
		player.set_physics_process(false)
	# Camera zoom
	var cam: Camera2D = $Camera2D
	var cam_script = $Camera2D
	cam_script.set_process(false)
	var tween = create_tween()
	var target_zoom = cam.zoom * 2
	tween.tween_property(cam, "zoom", target_zoom, 0.4)
	# Center camera on player
	if player:
		cam.global_position = player.global_position
	# Wait for death animation ---
	if player and player.has_signal("animation_finished"):
		await player.animation_finished
	else:
		await get_tree().create_timer(2).timeout
	# Calculate shards before ending run
	var run_data = RunManager.run_data
	var run_gold: int = int(run_data.resources.get("gold", 0))
	var shards_earned: int = int(floor(float(run_gold) * 0.5))
	# Show UI
	$GameOverUI.show_game_over(run_data, shards_earned)
	get_tree().paused = true
	RunManager.end_run()

func _try_spawn_stage_portal() -> void:
	if transitioning_stage or is_world_map_open or is_vendor_open:
		return
	if stage_portal_root != null:
		return
	if current_level == null:
		return
	if active_enemies.is_empty():
		_spawn_stage_portal()
		_mark_stage_cleared_if_needed()

func _mark_stage_cleared_if_needed() -> void:
	if stage_clear_recorded:
		return
	stage_clear_recorded = true
	if RunManager.is_run_active and RunManager.run_data:
		RunManager.mark_current_stage_cleared()

func _spawn_stage_portal() -> void:
	if current_level == null:
		return
	stage_portal_root = Node2D.new()
	stage_portal_root.name = "StagePortal"
	current_level.add_child(stage_portal_root)

	var portal_position: Vector2 = _get_stage_portal_position()
	stage_portal_root.global_position = portal_position

	if portal_scene:
		var visuals = portal_scene.instantiate()
		stage_portal_root.add_child(visuals)

	var trigger: Area2D = Area2D.new()
	var collision: CollisionShape2D = CollisionShape2D.new()
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = 22.0
	collision.shape = shape
	trigger.add_child(collision)
	trigger.set_collision_layer_value(6, true)
	trigger.set_collision_mask_value(2, true)
	trigger.monitoring = true
	trigger.monitorable = true
	trigger.body_entered.connect(_on_stage_portal_entered)
	stage_portal_root.add_child(trigger)

func _get_stage_portal_position() -> Vector2:
	if current_level == null: return player_spawn_position + Vector2(220, -24)
	var portal_spawn: Marker2D = current_level.find_child("PortalSpawn", true, false) as Marker2D
	if portal_spawn: return portal_spawn.global_position
	return player_spawn_position + Vector2(220, -24)

func _on_stage_portal_entered(body: Node) -> void:
	if body == null or body != player:
		return
	advance_to_next_stage()

func _try_manual_stage_advance() -> void:
	if transitioning_stage or is_world_map_open or is_vendor_open:
		return
	if stage_portal_root == null or not is_instance_valid(stage_portal_root):
		return
	if player == null or not is_instance_valid(player):
		return
	if not Input.is_action_just_pressed("ui_accept"):
		return
	if player.global_position.distance_to(stage_portal_root.global_position) <= 40.0:
		advance_to_next_stage()

func advance_to_next_stage() -> void:
	if transitioning_stage or is_world_map_open or is_vendor_open:
		return
	_clear_stage_portal()
	_open_vendor_phase()

func _open_vendor_phase() -> void:
	is_vendor_open = true
	if vendor_ui and vendor_ui.has_method("open_vendor"):
		vendor_ui.open_vendor(current_stage)
		return

	_on_vendor_closed()

func _open_world_map_phase() -> void:
	var choices: Array = RunManager.generate_world_map_choices()
	if choices.is_empty():
		return

	is_world_map_open = true
	if world_map_ui and world_map_ui.has_method("open_map"):
		world_map_ui.open_map(current_stage + 1, choices)
		return

	# Fallback if UI is missing.
	var default_choice_id: String = String((choices[0] as Dictionary).get("id", ""))
	_on_world_map_choice_selected(default_choice_id)

func _bind_vendor_signals() -> void:
	if vendor_ui == null:
		return
	if vendor_ui.has_signal("vendor_closed"):
		var close_callable: Callable = Callable(self, "_on_vendor_closed")
		if not vendor_ui.is_connected("vendor_closed", close_callable):
			vendor_ui.connect("vendor_closed", close_callable)

func _on_vendor_closed() -> void:
	is_vendor_open = false
	_open_world_map_phase()

func _bind_world_map_signals() -> void:
	if world_map_ui == null:
		return
	if world_map_ui.has_signal("node_selected"):
		var choose_callable: Callable = Callable(self, "_on_world_map_choice_selected")
		if not world_map_ui.is_connected("node_selected", choose_callable):
			world_map_ui.connect("node_selected", choose_callable)

func _on_world_map_choice_selected(choice_id: String) -> void:
	var level_config: Dictionary = RunManager.choose_world_map_node(choice_id)
	is_world_map_open = false
	if level_config.is_empty():
		return
	_save_player_stats_to_run_data()
	_sync_player_stats_from_run_data()
	transitioning_stage = true
	current_stage = RunManager.get_current_stage()
	_load_stage_from_config(level_config)
	if player.has_method("play_spawn_sequence"):
		player.call("play_spawn_sequence")
	$Camera2D.reset_camera()
	transitioning_stage = false

func _save_player_stats_to_run_data() -> void:
	if RunManager.run_data == null:
		return
	var stats: Dictionary = RunManager.run_data.stats
	var hc: HealthComponent = player.get_node_or_null("HealthComponent")
	if hc == null:
		return
	stats["health"] = hc.current_health
	stats["max_health"] = hc.max_health
	# Movement
	var movement: MovementComponent = player.get_node_or_null("MovementComponent")
	if movement:
		if base_move_speed != 0:
			stats["move_speed"] = movement.speed / base_move_speed
	# Jump
	var jump: JumpComponent = player.get_node_or_null("JumpComponent")
	if jump:
		if base_jump_velocity != 0:
			stats["jump_power"] = jump.jump_velocity / base_jump_velocity
	
func _sync_player_stats_from_run_data() -> void:
	if RunManager.run_data == null:
		return
	_cache_player_baselines()

	var stats: Dictionary = RunManager.run_data.stats
	var hc: HealthComponent = player.get_node_or_null("HealthComponent") as HealthComponent
	if hc == null:
		return
	var run_max_health: int = int(stats.get("max_health", hc.max_health))
	var run_health: int = int(stats.get("health", hc.current_health))
	hc.max_health = max(run_max_health, 1)
	hc.current_health = clampi(run_health, 0, hc.max_health)
	hc.health_changed.emit(hc.current_health, hc.max_health)

	var move_multiplier: float = float(stats.get("move_speed", 1.0))
	var jump_multiplier: float = float(stats.get("jump_power", stats.get("jump_strength", 1.0)))
	var movement_component: MovementComponent = player.get_node_or_null("MovementComponent") as MovementComponent
	if movement_component:
		movement_component.speed = base_move_speed * move_multiplier
		movement_component.sprint_speed = base_sprint_speed * move_multiplier

	var jump_component: JumpComponent = player.get_node_or_null("JumpComponent") as JumpComponent
	if jump_component:
		jump_component.jump_velocity = base_jump_velocity * jump_multiplier

func _cache_player_baselines() -> void:
	if has_cached_player_baselines:
		return
	var movement_component: MovementComponent = player.get_node_or_null("MovementComponent") as MovementComponent
	if movement_component:
		base_move_speed = movement_component.speed
		base_sprint_speed = movement_component.sprint_speed

	var jump_component: JumpComponent = player.get_node_or_null("JumpComponent") as JumpComponent
	if jump_component:
		base_jump_velocity = jump_component.jump_velocity

	has_cached_player_baselines = true

func _clear_stage_portal() -> void:
	if stage_portal_root and is_instance_valid(stage_portal_root):
		stage_portal_root.queue_free()
	stage_portal_root = null

func _hook_hud_signals() -> void:
	# Let the HUD apply upgrades to the player
	if hud and hud.has_method("bind_player"):
		hud.bind_player(player)

	# EXP updates + level up popup
	var xp = player.get_node_or_null("ExperienceComponent")
	if xp:
		# keep the EXP bar accurate without polling (optional but nice)
		if xp.has_signal("exp_changed"):
			xp.exp_changed.connect(func(exp: int, exp_to_next: int, level: int) -> void:
				hud.set_exp(exp, exp_to_next)
				if RunManager.run_data:
					RunManager.run_data.resources["level"] = xp.level
					RunManager.run_data.resources["experience"] = xp.experience
			)

		# Level up popup
		if xp.has_signal("leveled_up"):
			xp.leveled_up.connect(func(new_level: int) -> void:
				hud.show_level_up(new_level)
			)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_L: # press L
		var xp = player.get_node_or_null("ExperienceComponent")
		if xp:
			xp.add_experience(200)
	if event.is_action_pressed("dev_skip_level"):
		_dev_skip_level()


# DEV TOOL
func _dev_skip_level() -> void:
	print("DEV: Skipping level")
	var xp_comp = player.get_node_or_null("ExperienceComponent")
	for enemy in active_enemies:
		if not is_instance_valid(enemy):
			continue
		# Grant XP
		if xp_comp and "xp_reward" in enemy:
			xp_comp.add_experience(enemy.xp_reward)
		# Kill enemy
		if enemy.has_method("receive_damage"):
			enemy.receive_damage(9999)
		else:
			enemy.queue_free()

	_prune_active_enemies()
	RunManager.mark_current_stage_cleared()
	_teleport_player_to_dev_marker()
	

func _teleport_player_to_dev_marker() -> void:
	if current_level == null:
		return
	var dev_marker: Marker2D = current_level.find_child("DevTP", true, false)
	if dev_marker == null:
		print("DEV: DevTP marker not found")
		return
	player.global_position = dev_marker.global_position
