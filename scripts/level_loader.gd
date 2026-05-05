extends Node

var chunk_start: PackedScene = preload("res://scenes/level_chunks/chunk_start.tscn")
var chunk_scenes: Array[PackedScene] = [
	preload("res://scenes/level_chunks/chunk_01.tscn"),
	preload("res://scenes/level_chunks/chunk_02.tscn"),
	preload("res://scenes/level_chunks/chunk_03.tscn"),
	#preload("res://scenes/level_chunks/chunk_04.tscn") Temporarily disabled due to camera limits
]
var mini_boss_scenes: Array[PackedScene] = [
	preload("res://scenes/level_chunks/chunk_miniboss_01.tscn")
]
var chunk_end: PackedScene = preload("res://scenes/level_chunks/chunk_end.tscn")
var chunk_count: int = 5

# Theme Settings
const ROW_HEIGHT: int = 2
const NUM_THEMES: int = 7

const THEME_TO_DECOR_STYLES := {
	0: [0],        # Brown → white decorations
	1: [0, 2],     # Blue → white or green (or swap to blue later)
	2: [2],        # Green → green only
	3: [1],        # Red → red only
	4: [1],        # Yellow → warm (closest you have)
	5: [0, 1, 2],  # White → all
	6: [0, 1, 2],  # Gray → all
}

func generate_level(level_config: Dictionary = {}) -> Node2D:
	if bool(level_config.get("mini_boss_stage", false)):
		return generate_mini_boss_level(level_config)
	var level_root: Node2D = Node2D.new()
	level_root.name = "GeneratedLevel"
	var total_chunks: int = int(level_config.get("chunk_count", chunk_count))
	total_chunks = clampi(total_chunks, 1, 12)

	var theme_row: int = _resolve_theme_row(level_config)
	var styles: Array = THEME_TO_DECOR_STYLES.get(theme_row, [0])
	var level_style_index: int = styles.pick_random()
	level_root.set_meta("decor_style", level_style_index)

	level_root.set_meta("level_config", level_config.duplicate(true))
	level_root.set_meta("chunk_count", total_chunks)
	level_root.set_meta("theme_row", theme_row)

	var previous_chunk: Node2D = null
	var start: Node2D = chunk_start.instantiate() as Node2D
	level_root.add_child(start)
	start.global_position = Vector2.ZERO
	_apply_theme_to_chunk(start, theme_row)
	_decorate_stage_chunk(start, theme_row, 0)
	previous_chunk = start
	# Generate Chain (Normal Chunks)
	for _i in range(total_chunks):
		var chunk_scene: PackedScene = chunk_scenes.pick_random() as PackedScene
		var new_chunk: Node2D = chunk_scene.instantiate() as Node2D
		level_root.add_child(new_chunk)
		var prev_exit: Marker2D = previous_chunk.get_node("Exit") as Marker2D
		var new_entry: Marker2D = new_chunk.get_node("Entry") as Marker2D
		new_chunk.global_position = prev_exit.global_position - new_entry.position
		_apply_theme_to_chunk(new_chunk, theme_row)
		_decorate_stage_chunk(new_chunk, theme_row, _i + 1)
		previous_chunk = new_chunk
	# End Chunk
	var end_chunk: Node2D = chunk_end.instantiate() as Node2D
	level_root.add_child(end_chunk)
	var prev_exit: Marker2D = previous_chunk.get_node("Exit") as Marker2D
	var end_entry: Marker2D = end_chunk.get_node("Entry") as Marker2D
	end_chunk.global_position = prev_exit.global_position - end_entry.position
	_apply_theme_to_chunk(end_chunk, theme_row)
	_decorate_stage_chunk(end_chunk, theme_row, total_chunks + 1)
	return level_root

func generate_mini_boss_level(level_config: Dictionary) -> Node2D:
	level_config["manual_enemy_spawn"] = true
	var level_root: Node2D = Node2D.new()
	level_root.name = "GeneratedLevel"
	var theme_row: int = _resolve_theme_row(level_config)
	level_root.set_meta("level_config", level_config.duplicate(true))
	level_root.set_meta("theme_row", theme_row)
	var chunk_scene: PackedScene = mini_boss_scenes.pick_random() as PackedScene
	var chunk: Node2D = chunk_scene.instantiate() as Node2D
	level_root.add_child(chunk)
	chunk.global_position = Vector2.ZERO
	_apply_theme_to_chunk(chunk, theme_row)
	_decorate_boss_arena(chunk, level_config)
	return level_root

func _resolve_theme_row(level_config: Dictionary) -> int:
	var theme_row: int = int(level_config.get("theme_row", -1))
	if theme_row >= 0:
		return clampi(theme_row, 0, NUM_THEMES - 1)
	if bool(level_config.get("boss_stage", false)) or bool(level_config.get("mini_boss_stage", false)):
		var style_index: int = _get_boss_arena_style_index(level_config)
		var boss_theme_rows: Array[int] = [1, 4, 6, 6]
		return boss_theme_rows[style_index]
	return randi() % NUM_THEMES

func _apply_theme_to_chunk(chunk: Node2D, theme_row: int) -> void:
	var tilemaps = [
		chunk.get_node_or_null("Foreground") as TileMapLayer,
		chunk.get_node_or_null("BossEntryWall") as TileMapLayer,
		chunk.get_node_or_null("BossExitWall") as TileMapLayer
	]
	for tilemap in tilemaps:
		if tilemap == null or not (tilemap is TileMapLayer): continue

		var used_cells = tilemap.get_used_cells()

		for cell in used_cells:
			var source_id = tilemap.get_cell_source_id(cell)
			if source_id == -1:
				continue

			var atlas_coords = tilemap.get_cell_atlas_coords(cell)

			# Normalize BEFORE applying theme
			var base_y: int = atlas_coords.y % ROW_HEIGHT

			var new_coords = Vector2i(
				atlas_coords.x,
				base_y + theme_row * ROW_HEIGHT
			)

			tilemap.set_cell(cell, source_id, new_coords)

func _get_boss_arena_style_index(level_config: Dictionary) -> int:
	var stage: int = int(level_config.get("stage", 3))
	return maxi(int(floor(float(stage) / 3.0)) - 1, 0) % 4

func _decorate_stage_chunk(chunk: Node2D, theme_row: int, chunk_index: int) -> void:
	var foreground: TileMapLayer = chunk.get_node_or_null("Foreground") as TileMapLayer
	var level_root := chunk.get_parent()
	var chunk_style_index: int = level_root.get_meta("decor_style", 0)
	if foreground == null:
		return

	var used_cells: Array[Vector2i] = foreground.get_used_cells()
	if used_cells.is_empty():
		return

	var decoration_root: Node2D = Node2D.new()
	decoration_root.name = "StageTextureDressing"
	decoration_root.z_index = 0
	chunk.add_child(decoration_root)

	var occupied_cells: Dictionary = {}
	var min_pos: Vector2 = Vector2(1000000.0, 1000000.0)
	var max_pos: Vector2 = Vector2(-1000000.0, -1000000.0)
	for cell in used_cells:
		occupied_cells[cell] = true
		var cell_pos: Vector2 = foreground.position + foreground.map_to_local(cell)
		min_pos.x = minf(min_pos.x, cell_pos.x)
		min_pos.y = minf(min_pos.y, cell_pos.y)
		max_pos.x = maxf(max_pos.x, cell_pos.x)
		max_pos.y = maxf(max_pos.y, cell_pos.y)

	var backdrop_rect: Rect2 = Rect2(min_pos + Vector2(-44.0, -108.0), (max_pos - min_pos) + Vector2(88.0, 178.0))
	_add_stage_backdrop(decoration_root, backdrop_rect, chunk_style_index, chunk_index)
	_add_stage_tile_dressing(decoration_root, foreground, occupied_cells, used_cells, chunk_style_index, chunk_index)

func _add_stage_backdrop(parent: Node2D, rect: Rect2, theme_row: int, chunk_index: int) -> void:
	var backdrop_color: Color = _get_stage_palette_color(theme_row, "backdrop")
	var haze_color: Color = _get_stage_palette_color(theme_row, "haze")
	var accent_color: Color = _get_stage_palette_color(theme_row, "accent")
	var shadow_color: Color = _get_stage_palette_color(theme_row, "shadow")

	_add_rect(parent, "StageBackdrop", backdrop_color, rect, -10)
	_add_rect(parent, "StageHorizon", haze_color, Rect2(Vector2(rect.position.x, rect.position.y + rect.size.y * 0.56), Vector2(rect.size.x, rect.size.y * 0.28)), -9)

	for index in range(4):
		var x: float = rect.position.x + 34.0 + float(index) * 128.0 + float((chunk_index * 19) % 41)
		var y: float = rect.position.y + 28.0 + float((index * 17 + chunk_index * 5) % 36)
		_add_rect(parent, "BackdropBlock%d" % index, shadow_color, Rect2(Vector2(x, y), Vector2(54.0, 8.0)), -8)
		_add_rect(parent, "BackdropTop%d" % index, accent_color, Rect2(Vector2(x + 8.0, y - 8.0), Vector2(30.0, 8.0)), -8)

	for index in range(5):
		var vine_x: float = rect.position.x + 52.0 + float(index) * 96.0 + float((chunk_index * 11) % 29)
		var vine_top: float = rect.position.y + 4.0
		var vine_len: float = 28.0 + float((index * 9 + chunk_index * 7) % 34)
		_add_line(parent, "BackdropVine%d" % index, accent_color.darkened(0.25), PackedVector2Array([Vector2(vine_x, vine_top), Vector2(vine_x + 4.0, vine_top + vine_len * 0.45), Vector2(vine_x - 2.0, vine_top + vine_len)]), 2.0, -7)

func _add_stage_tile_dressing(
	parent: Node2D,
	foreground: TileMapLayer,
	occupied_cells: Dictionary,
	used_cells: Array[Vector2i],
	theme_row: int,
	chunk_index: int
) -> void:
	var cap_color: Color = _get_stage_palette_color(theme_row, "cap")
	var trim_color: Color = _get_stage_palette_color(theme_row, "trim")
	var side_color: Color = _get_stage_palette_color(theme_row, "side")
	var crack_color: Color = _get_stage_palette_color(theme_row, "crack")
	var root_color: Color = _get_stage_palette_color(theme_row, "root")
	var glow_color: Color = _get_stage_palette_color(theme_row, "glow")
	var decoration_count: int = 0

	for cell in used_cells:
		var worldish_pos: Vector2 = foreground.position + foreground.map_to_local(cell)
		var top_left: Vector2 = worldish_pos + Vector2(-8.0, -8.0)
		var hash_value: int = _hash_stage_cell(cell, theme_row, chunk_index)

		var has_above: bool = occupied_cells.has(cell + Vector2i(0, -1))
		var has_below: bool = occupied_cells.has(cell + Vector2i(0, 1))
		var has_left: bool = occupied_cells.has(cell + Vector2i(-1, 0))
		var has_right: bool = occupied_cells.has(cell + Vector2i(1, 0))

		if not has_above:
			_add_rect(parent, "StageCap%d" % decoration_count, cap_color, Rect2(top_left + Vector2(0.0, -2.0), Vector2(16.0, 5.0)), 1)
			_add_rect(parent, "StageTrim%d" % decoration_count, trim_color, Rect2(top_left + Vector2(0.0, 3.0), Vector2(16.0, 2.0)), 1)
			decoration_count += 1

			if hash_value % 3 == 0:
				_add_stage_tuft(parent, worldish_pos + Vector2(float((hash_value % 9) - 4), -10.0), root_color, decoration_count)
				decoration_count += 1
			elif hash_value % 5 == 0:
				_add_rect(parent, "StagePebble%d" % decoration_count, crack_color, Rect2(worldish_pos + Vector2(-2.0, -10.0), Vector2(4.0, 2.0)), 2)
				decoration_count += 1

		if not has_left:
			_add_rect(parent, "StageLeftEdge%d" % decoration_count, side_color, Rect2(top_left + Vector2(-2.0, 2.0), Vector2(3.0, 14.0)), 1)
			decoration_count += 1

		if not has_right:
			_add_rect(parent, "StageRightEdge%d" % decoration_count, side_color.darkened(0.25), Rect2(top_left + Vector2(15.0, 2.0), Vector2(3.0, 14.0)), 1)
			decoration_count += 1

		if not has_below and hash_value % 4 == 0:
			_add_line(parent, "StageHangingRoot%d" % decoration_count, root_color.darkened(0.12), PackedVector2Array([worldish_pos + Vector2(-4.0, 8.0), worldish_pos + Vector2(-2.0, 18.0), worldish_pos + Vector2(-5.0, 28.0)]), 1.0, 1)
			decoration_count += 1

		if hash_value % 11 == 0:
			_add_line(parent, "StageCrack%d" % decoration_count, crack_color, PackedVector2Array([worldish_pos + Vector2(-5.0, -1.0), worldish_pos + Vector2(-1.0, 3.0), worldish_pos + Vector2(4.0, 1.0)]), 1.0, 2)
			decoration_count += 1

		if theme_row == 4 and hash_value % 9 == 0:
			_add_rect(parent, "StageGlow%d" % decoration_count, glow_color, Rect2(top_left + Vector2(3.0, 8.0), Vector2(10.0, 2.0)), 2)
			decoration_count += 1

func _add_stage_tuft(parent: Node2D, origin: Vector2, color: Color, index: int) -> void:
	_add_rect(parent, "StageTuftStem%d" % index, color.darkened(0.2), Rect2(origin + Vector2(-1.0, 0.0), Vector2(2.0, 5.0)), 2)
	_add_line(parent, "StageTuftA%d" % index, color, PackedVector2Array([origin + Vector2(-5.0, 2.0), origin + Vector2(-1.0, -4.0), origin + Vector2(2.0, 2.0)]), 1.0, 2)
	_add_line(parent, "StageTuftB%d" % index, color.lightened(0.12), PackedVector2Array([origin + Vector2(0.0, 2.0), origin + Vector2(4.0, -5.0), origin + Vector2(6.0, 2.0)]), 1.0, 2)

func _get_stage_palette_color(theme_row: int, role: String) -> Color:
	var style_index: int = theme_row
	match style_index:
		1:
			match role:
				"backdrop":
					return Color(0.16, 0.08, 0.05, 1.0)
				"haze":
					return Color(0.32, 0.12, 0.06, 0.7)
				"accent":
					return Color(0.86, 0.34, 0.12, 0.55)
				"shadow":
					return Color(0.12, 0.06, 0.04, 0.72)
				"cap":
					return Color(0.54, 0.26, 0.12, 1.0)
				"trim":
					return Color(0.82, 0.42, 0.16, 1.0)
				"side":
					return Color(0.22, 0.1, 0.06, 0.88)
				"crack":
					return Color(0.09, 0.04, 0.02, 0.85)
				"root":
					return Color(0.66, 0.3, 0.1, 1.0)
				"glow":
					return Color(1.0, 0.66, 0.18, 0.85)
		2:
			match role:
				"backdrop":
					return Color(0.05, 0.14, 0.14, 1.0)
				"haze":
					return Color(0.08, 0.28, 0.24, 0.68)
				"accent":
					return Color(0.25, 0.78, 0.62, 0.46)
				"shadow":
					return Color(0.03, 0.09, 0.09, 0.75)
				"cap":
					return Color(0.16, 0.42, 0.34, 1.0)
				"trim":
					return Color(0.36, 0.75, 0.56, 1.0)
				"side":
					return Color(0.06, 0.21, 0.19, 0.9)
				"crack":
					return Color(0.03, 0.11, 0.1, 0.86)
				"root":
					return Color(0.38, 0.65, 0.42, 1.0)
				"glow":
					return Color(0.36, 0.95, 0.75, 0.78)
		_:
			match role:
				"backdrop":
					return Color(0.07, 0.09, 0.15, 1.0)
				"haze":
					return Color(0.13, 0.17, 0.25, 0.72)
				"accent":
					return Color(0.45, 0.58, 0.74, 0.46)
				"shadow":
					return Color(0.04, 0.05, 0.09, 0.72)
				"cap":
					return Color(0.26, 0.31, 0.4, 1.0)
				"trim":
					return Color(0.52, 0.59, 0.72, 1.0)
				"side":
					return Color(0.1, 0.13, 0.18, 0.9)
				"crack":
					return Color(0.03, 0.04, 0.07, 0.88)
				"root":
					return Color(0.42, 0.5, 0.58, 1.0)
				"glow":
					return Color(0.42, 0.65, 1.0, 0.65)
	return Color.WHITE

func _hash_stage_cell(cell: Vector2i, theme_row: int, chunk_index: int) -> int:
	var hash_value: int = cell.x * 73856093
	hash_value = hash_value ^ (cell.y * 19349663)
	hash_value = hash_value ^ (theme_row * 83492791)
	hash_value = hash_value ^ (chunk_index * 265443576)
	return absi(hash_value)

func _decorate_boss_arena(chunk: Node2D, level_config: Dictionary) -> void:
	var style_index: int = _get_boss_arena_style_index(level_config)
	var decoration_root: Node2D = Node2D.new()
	decoration_root.name = "ArenaTextureDressing"
	decoration_root.z_index = -6
	chunk.add_child(decoration_root)

	match style_index:
		0:
			_add_blade_arena_decoration(decoration_root)
		1:
			_add_pyromancer_arena_decoration(decoration_root)
		2:
			_add_guardian_arena_decoration(decoration_root)
		3:
			_add_switcher_arena_decoration(decoration_root)

func _add_blade_arena_decoration(parent: Node2D) -> void:
	_add_polygon(parent, "ColdStoneBack", Color(0.07, 0.08, 0.16, 1.0), PackedVector2Array([Vector2(0, -160), Vector2(720, -160), Vector2(720, 32), Vector2(0, 32)]), -8)
	_add_polygon(parent, "SteelFloorWash", Color(0.13, 0.14, 0.22, 0.72), PackedVector2Array([Vector2(192, -8), Vector2(704, -8), Vector2(704, 32), Vector2(192, 32)]), -5)
	for index in range(7):
		var x: float = 220.0 + float(index) * 68.0
		_add_polygon(parent, "BladePanel%d" % index, Color(0.12, 0.13, 0.24, 0.84), PackedVector2Array([Vector2(x, -136), Vector2(x + 34.0, -148), Vector2(x + 54.0, -32), Vector2(x + 12.0, -28)]), -7)
	for index in range(5):
		var x_start: float = 232.0 + float(index) * 92.0
		_add_line(parent, "BladeCrack%d" % index, Color(0.48, 0.52, 0.72, 0.58), PackedVector2Array([Vector2(x_start, -4), Vector2(x_start + 22.0, -18), Vector2(x_start + 54.0, -10), Vector2(x_start + 84.0, -24)]), 1.0, -4)

func _add_pyromancer_arena_decoration(parent: Node2D) -> void:
	_add_polygon(parent, "AshBack", Color(0.12, 0.04, 0.03, 1.0), PackedVector2Array([Vector2(0, -160), Vector2(720, -160), Vector2(720, 32), Vector2(0, 32)]), -8)
	_add_polygon(parent, "HeatFloorWash", Color(0.26, 0.07, 0.03, 0.78), PackedVector2Array([Vector2(192, -10), Vector2(704, -10), Vector2(704, 34), Vector2(192, 34)]), -5)
	for index in range(6):
		var x: float = 220.0 + float(index) * 78.0
		_add_polygon(parent, "MagmaVent%d" % index, Color(0.95, 0.24, 0.04, 0.82), PackedVector2Array([Vector2(x, 6), Vector2(x + 32.0, -2), Vector2(x + 62.0, 7), Vector2(x + 44.0, 16), Vector2(x + 8.0, 16)]), -4)
		_add_polygon(parent, "MagmaGlow%d" % index, Color(1.0, 0.7, 0.12, 0.42), PackedVector2Array([Vector2(x + 8.0, 5), Vector2(x + 34.0, 1), Vector2(x + 52.0, 7), Vector2(x + 38.0, 11), Vector2(x + 14.0, 11)]), -3)
	for index in range(8):
		var x_base: float = 210.0 + float(index) * 58.0
		_add_line(parent, "AshStreak%d" % index, Color(0.82, 0.36, 0.12, 0.4), PackedVector2Array([Vector2(x_base, -124), Vector2(x_base + 26.0, -96), Vector2(x_base + 14.0, -58)]), 1.0, -6)

func _add_guardian_arena_decoration(parent: Node2D) -> void:
	_add_polygon(parent, "AncientBack", Color(0.04, 0.13, 0.13, 1.0), PackedVector2Array([Vector2(0, -160), Vector2(720, -160), Vector2(720, 32), Vector2(0, 32)]), -8)
	_add_polygon(parent, "MossFloorWash", Color(0.07, 0.25, 0.2, 0.72), PackedVector2Array([Vector2(192, -10), Vector2(704, -10), Vector2(704, 34), Vector2(192, 34)]), -5)
	for index in range(6):
		var x: float = 214.0 + float(index) * 82.0
		_add_polygon(parent, "TempleBlock%d" % index, Color(0.12, 0.34, 0.31, 0.9), PackedVector2Array([Vector2(x, -132), Vector2(x + 58.0, -132), Vector2(x + 50.0, -42), Vector2(x + 8.0, -42)]), -7)
		_add_polygon(parent, "CrystalInset%d" % index, Color(0.36, 0.96, 0.82, 0.46), PackedVector2Array([Vector2(x + 22.0, -112), Vector2(x + 36.0, -92), Vector2(x + 26.0, -70), Vector2(x + 12.0, -91)]), -6)
	for index in range(7):
		var x_start: float = 206.0 + float(index) * 70.0
		_add_line(parent, "RootCrack%d" % index, Color(0.34, 0.58, 0.44, 0.5), PackedVector2Array([Vector2(x_start, 4), Vector2(x_start + 18.0, -12), Vector2(x_start + 48.0, -8), Vector2(x_start + 70.0, -22)]), 1.0, -4)

func _add_switcher_arena_decoration(parent: Node2D) -> void:
	_add_polygon(parent, "SwitcherBack", Color(0.06, 0.06, 0.08, 1.0), PackedVector2Array([Vector2(0, -160), Vector2(720, -160), Vector2(720, 32), Vector2(0, 32)]), -8)
	_add_polygon(parent, "SwitcherFloorWash", Color(0.12, 0.13, 0.16, 0.78), PackedVector2Array([Vector2(192, -10), Vector2(704, -10), Vector2(704, 34), Vector2(192, 34)]), -5)

	for index in range(8):
		var x: float = 210.0 + float(index) * 58.0
		_add_polygon(parent, "SwitcherPanel%d" % index, Color(0.16, 0.17, 0.22, 0.9), PackedVector2Array([
			Vector2(x, -128),
			Vector2(x + 42.0, -128),
			Vector2(x + 42.0, -86),
			Vector2(x, -86)
		]), -7)

		_add_polygon(parent, "SwitcherButton%d" % index, Color(0.55, 0.65, 0.95, 0.42), PackedVector2Array([
			Vector2(x + 8.0, -118),
			Vector2(x + 34.0, -118),
			Vector2(x + 34.0, -96),
			Vector2(x + 8.0, -96)
		]), -6)

	for index in range(6):
		var x_start: float = 204.0 + float(index) * 82.0
		_add_line(parent, "SwitcherCable%d" % index, Color(0.62, 0.68, 0.88, 0.48), PackedVector2Array([
			Vector2(x_start, -20),
			Vector2(x_start + 24.0, -44),
			Vector2(x_start + 58.0, -28),
			Vector2(x_start + 86.0, -54)
		]), 1.5, -4)


func _add_polygon(parent: Node2D, node_name: String, color: Color, points: PackedVector2Array, z: int) -> void:
	var poly: Polygon2D = Polygon2D.new()
	poly.name = node_name
	poly.color = color
	poly.polygon = points
	poly.z_index = z
	parent.add_child(poly)

func _add_line(parent: Node2D, node_name: String, color: Color, points: PackedVector2Array, width: float, z: int) -> void:
	var line: Line2D = Line2D.new()
	line.name = node_name
	line.default_color = color
	line.points = points
	line.width = width
	line.z_index = z
	parent.add_child(line)

func _add_rect(parent: Node2D, node_name: String, color: Color, rect: Rect2, z: int) -> void:
	_add_polygon(parent, node_name, color, PackedVector2Array([
		rect.position,
		rect.position + Vector2(rect.size.x, 0.0),
		rect.position + rect.size,
		rect.position + Vector2(0.0, rect.size.y),
	]), z)
