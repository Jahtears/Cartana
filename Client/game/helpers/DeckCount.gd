extends RefCounted
class_name DeckCountUtil

const TOTAL_CARDS := 26
const SOURCE_SLOT_TYPE := "DECK"
const WARN_THRESHOLD := 5

const BADGE_SIZE := Vector2(82, 28)
const CENTER_OFFSET_P1 := Vector2(0, -86)
const CENTER_OFFSET_P2 := Vector2(0, 86)

const BADGE_BG_COLOR := Color(0.03, 0.06, 0.08, 0.5)
const BADGE_BORDER_COLOR := Color(1, 1, 1, 0.14)

const FONT_SIZE := 14
const FONT_COLOR_NORMAL := Color(0.92, 0.97, 1.0, 1.0)
const FONT_COLOR_WARN := Color(1.0, 0.82, 0.45, 1.0)
const FONT_COLOR_EMPTY := Color(1.0, 0.48, 0.45, 1.0)
const FONT_COLOR_UNKNOWN := Color(0.72, 0.78, 0.85, 1.0)

const PULSE_SCALE := Vector2(1.04, 1.04)
const PULSE_HALF_DURATION := 0.45

const PLAYERS := [1, 2]

static func create_state() -> Dictionary:
	return {
		"badges": {},
		"labels": {},
		"pulse_tweens": {},
	}

static func ensure_ui(state: Dictionary, root: Control) -> void:
	if root == null:
		return

	var badges: Dictionary = state.get("badges", {})
	for player_id in PLAYERS:
		if not badges.has(player_id):
			_create_badge(state, root, player_id)

static func update_positions(state: Dictionary, root: Control, player1_root: Node2D, player2_root: Node2D) -> void:
	ensure_ui(state, root)

	var p1_deck := player1_root.get_node_or_null("Deck") as Node2D
	var p2_deck := player2_root.get_node_or_null("Deck") as Node2D

	_position_badge(state, 1, p1_deck, CENTER_OFFSET_P1)
	_position_badge(state, 2, p2_deck, CENTER_OFFSET_P2)

static func reset_counts(state: Dictionary) -> void:
	for player_id in PLAYERS:
		_set_count(state, player_id, -1)

static func update_from_slot(state: Dictionary, slot_id: String, count: int) -> void:
	var player_id := _extract_player_id(slot_id)
	if player_id <= 0:
		return
	_set_count(state, player_id, count)

static func cleanup(state: Dictionary) -> void:
	var pulse_tweens: Dictionary = state.get("pulse_tweens", {})
	for player_id in pulse_tweens.keys():
		var tween := pulse_tweens[player_id] as Tween
		if tween != null and is_instance_valid(tween):
			tween.kill()
	pulse_tweens.clear()

	var badges: Dictionary = state.get("badges", {})
	for badge in badges.values():
		var ctrl := badge as Control
		if ctrl != null:
			ctrl.scale = Vector2.ONE

static func _create_badge(state: Dictionary, root: Control, player_id: int) -> void:
	var badges: Dictionary = state.get("badges", {})
	var labels: Dictionary = state.get("labels", {})

	var badge := PanelContainer.new()
	badge.name = "DeckCountBadgeP%d" % player_id
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.z_index = 3
	badge.custom_minimum_size = BADGE_SIZE
	badge.size = BADGE_SIZE

	var style := StyleBoxFlat.new()
	style.bg_color = BADGE_BG_COLOR
	style.border_color = BADGE_BORDER_COLOR
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	badge.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.name = "Value"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", FONT_COLOR_NORMAL)
	label.add_theme_constant_override("outline_size", 2)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	badge.add_child(label)

	root.add_child(badge)
	badges[player_id] = badge
	labels[player_id] = label

static func _position_badge(state: Dictionary, player_id: int, deck_node: Node2D, center_offset: Vector2) -> void:
	var badges: Dictionary = state.get("badges", {})
	var badge := badges.get(player_id) as Control
	if badge == null or deck_node == null:
		return

	badge.size = BADGE_SIZE
	badge.position = deck_node.global_position + center_offset - BADGE_SIZE * 0.5

static func _extract_player_id(slot_id: String) -> int:
	var parts := slot_id.split(":")
	if parts.size() < 2:
		return 0
	if String(parts[1]) != SOURCE_SLOT_TYPE:
		return 0
	if not String(parts[0]).is_valid_int():
		return 0

	var player_id := int(parts[0])
	return player_id if player_id in PLAYERS else 0

static func _set_count(state: Dictionary, player_id: int, count: int) -> void:
	var labels: Dictionary = state.get("labels", {})
	var label := labels.get(player_id) as Label
	if label == null:
		return

	if count < 0:
		label.text = "--/%d" % TOTAL_CARDS
		label.add_theme_color_override("font_color", FONT_COLOR_UNKNOWN)
		_stop_pulse(state, player_id)
		return

	var current := maxi(0, count)
	label.text = "%d/%d" % [current, TOTAL_CARDS]

	if current <= 0:
		label.add_theme_color_override("font_color", FONT_COLOR_EMPTY)
	elif current <= WARN_THRESHOLD:
		label.add_theme_color_override("font_color", FONT_COLOR_WARN)
	else:
		label.add_theme_color_override("font_color", FONT_COLOR_NORMAL)

	if current > 0 and current <= WARN_THRESHOLD:
		_start_pulse(state, player_id)
	else:
		_stop_pulse(state, player_id)

static func _start_pulse(state: Dictionary, player_id: int) -> void:
	var badges: Dictionary = state.get("badges", {})
	var pulse_tweens: Dictionary = state.get("pulse_tweens", {})
	var badge := badges.get(player_id) as Control
	if badge == null:
		return

	if pulse_tweens.has(player_id):
		var existing := pulse_tweens[player_id] as Tween
		if existing != null and is_instance_valid(existing):
			return

	_stop_pulse(state, player_id)

	var tween := badge.create_tween()
	tween.set_loops()
	tween.tween_property(badge, "scale", PULSE_SCALE, PULSE_HALF_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(badge, "scale", Vector2.ONE, PULSE_HALF_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse_tweens[player_id] = tween

static func _stop_pulse(state: Dictionary, player_id: int) -> void:
	var pulse_tweens: Dictionary = state.get("pulse_tweens", {})
	if pulse_tweens.has(player_id):
		var tween := pulse_tweens[player_id] as Tween
		if tween != null and is_instance_valid(tween):
			tween.kill()
		pulse_tweens.erase(player_id)

	var badges: Dictionary = state.get("badges", {})
	var badge := badges.get(player_id) as Control
	if badge != null:
		badge.scale = Vector2.ONE
