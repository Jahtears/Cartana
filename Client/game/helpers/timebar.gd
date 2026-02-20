# timebar.gd
extends RefCounted
class_name TimebarUtil

const NODE_NAME := "TimeBar"

const SIZE := Vector2(420.0, 10.0)
const SHOW_PERCENTAGE := false
const CENTER_OFFSET_P1_BANC := Vector2(-30.0, -100.0)

static func create_state() -> Dictionary:
	return {
		"bar": null,
		"turn_current": "",
		"turn_ends_at_ms": 0,
		"turn_duration_ms": 0,
		"turn_paused": false,
		"turn_remaining_ms": 0,
		"timebar_mode": -1,
		"timebar_bg_sb": null,
		"timebar_fill_sb": null,
		"timebar_last_color": Color(-1, -1, -1, -1),
	}

static func ensure_ui(state: Dictionary, root: Control) -> void:
	if root == null:
		return

	var bar := _get_bar(state)
	if bar != null:
		return

	bar = ProgressBar.new()
	bar.name = NODE_NAME
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	state["bar"] = bar

static func apply_layout(state: Dictionary, anchor_position: Vector2) -> void:
	var time_bar := _get_bar(state)
	if time_bar == null:
		return

	time_bar.show_percentage = SHOW_PERCENTAGE
	time_bar.custom_minimum_size = Vector2.ZERO
	time_bar.custom_minimum_size = SIZE
	time_bar.size = SIZE
	time_bar.position = anchor_position + CENTER_OFFSET_P1_BANC

static func set_turn_timer(state: Dictionary, turn: Dictionary, sync_server_clock: Callable) -> void:
	state["turn_current"] = String(turn.get("current", ""))
	state["turn_ends_at_ms"] = int(turn.get("endsAt", 0))
	state["turn_duration_ms"] = int(turn.get("durationMs", 0))
	state["turn_paused"] = bool(turn.get("paused", false))
	state["turn_remaining_ms"] = int(turn.get("remainingMs", 0))

	var server_epoch := int(turn.get("serverNow", 0))
	if server_epoch > 0 and sync_server_clock.is_valid():
		sync_server_clock.call(server_epoch)

static func update_timebar_mode(state: Dictionary, is_spectator: bool, username: String) -> void:
	var ends_at := int(state.get("turn_ends_at_ms", 0))
	var duration := int(state.get("turn_duration_ms", 0))
	if ends_at <= 0 or duration <= 0:
		state["timebar_mode"] = -1
		return
	if is_spectator:
		state["timebar_mode"] = 2
		return
	if String(state.get("turn_current", "")) == username:
		state["timebar_mode"] = 0
	else:
		state["timebar_mode"] = 1

static func update_timebar(state: Dictionary, server_now_ms: Callable) -> void:
	var time_bar := _get_bar(state)
	if time_bar == null:
		return

	var ends_at := int(state.get("turn_ends_at_ms", 0))
	var duration := int(state.get("turn_duration_ms", 0))
	if ends_at <= 0 or duration <= 0:
		time_bar.visible = false
		state["timebar_mode"] = -1
		state["timebar_last_color"] = Color(-1, -1, -1, -1)
		return

	time_bar.visible = true

	var remaining := 0.0
	if bool(state.get("turn_paused", false)):
		remaining = maxf(float(state.get("turn_remaining_ms", 0)), 0.0)
	else:
		var now := 0
		if server_now_ms.is_valid():
			now = int(server_now_ms.call())
		remaining = float(ends_at - now)
		if remaining < 0.0:
			remaining = 0.0

	var ratio := clampf(remaining / float(duration), 0.0, 1.0)

	time_bar.min_value = 0.0
	time_bar.max_value = 1.0
	time_bar.value = ratio

	_ensure_timebar_style_overrides(state, time_bar)
	_update_timebar_fill_by_ratio(state, time_bar, ratio)

static func _ensure_timebar_style_overrides(state: Dictionary, time_bar: ProgressBar) -> void:
	if state.get("timebar_bg_sb", null) == null:
		var background := _new_rounded_style(Color(0.02, 0.16, 0.09, 0.55))
		state["timebar_bg_sb"] = background
		time_bar.add_theme_stylebox_override("background", background)

	if state.get("timebar_fill_sb", null) == null:
		var fill := _new_rounded_style(Color(0.22, 0.95, 0.28, 1.0))
		state["timebar_fill_sb"] = fill
		time_bar.add_theme_stylebox_override("fill", fill)

	time_bar.self_modulate = Color(1, 1, 1, 1)

static func _update_timebar_fill_by_ratio(state: Dictionary, time_bar: ProgressBar, ratio: float) -> void:
	var mode := int(state.get("timebar_mode", -1))
	var last_color: Color = state.get("timebar_last_color", Color(-1, -1, -1, -1))

	var c: Color
	match mode:
		2:
			c = _timebar_gradient(1.0)
		0:
			c = _timebar_gradient(ratio)
		1:
			c = _timebar_gradient(0.0)
		_:
			return

	if c == last_color:
		return
	state["timebar_last_color"] = c

	var fill_sb: StyleBoxFlat = state.get("timebar_fill_sb", null)
	if fill_sb != null:
		fill_sb.bg_color = c
		time_bar.self_modulate = Color(1, 1, 1, 1)
	else:
		time_bar.self_modulate = c

static func cleanup(state: Dictionary) -> void:
	state["bar"] = null

static func _timebar_gradient(ratio: float) -> Color:
	ratio = clampf(ratio, 0.0, 1.0)

	var green: Color = Color.from_hsv(0.333, 0.85, 0.95, 1.0)
	var orange: Color = Color.from_hsv(0.083, 0.85, 0.95, 1.0)
	var red: Color = Color.from_hsv(0.000, 0.85, 0.95, 1.0)

	if ratio > 0.66:
		return green
	elif ratio > 0.33:
		var t := (ratio - 0.33) / 0.33
		return _hsv_lerp(orange, green, t)
	else:
		var t := ratio / 0.33
		return _hsv_lerp(red, orange, t)

static func _hsv_lerp(a: Color, b: Color, t: float) -> Color:
	var h1 := a.h
	var h2 := b.h
	var dh := fposmod(h2 - h1, 1.0)
	if dh > 0.5:
		dh -= 1.0
	var h := fposmod(h1 + dh * t, 1.0)

	var s := lerpf(a.s, b.s, t)
	var v := lerpf(a.v, b.v, t)
	var alpha := lerpf(a.a, b.a, t)
	return Color.from_hsv(h, s, v, alpha)

static func _new_rounded_style(bg_color: Color, radius: int = 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_right = radius
	style.corner_radius_bottom_left = radius
	return style

static func _get_bar(state: Dictionary) -> ProgressBar:
	var bar := state.get("bar", null) as ProgressBar
	if bar != null and is_instance_valid(bar):
		return bar
	return null
