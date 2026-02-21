extends RefCounted
class_name GameMessage

const LanguageManager = preload("res://Client/Lang/LanguageManager.gd")

const INGAME_PREFIX := "INGAME_"

const INGAME_RULE_OK := "INGAME_RULE_OK"
const INGAME_MOVE_DENIED := "INGAME_MOVE_DENIED"
const INGAME_TURN_START_FIRST := "INGAME_TURN_START_FIRST"
const INGAME_TURN_START := "INGAME_TURN_START"

const INGAME_GREEN_CODES := {
	INGAME_TURN_START_FIRST: true,
	INGAME_TURN_START: true,
	INGAME_RULE_OK: true,
}

const INGAME_GREEN_COLOR := Color(0.0, 1.0, 0.0)
const INGAME_RED_COLOR := Color(1.0, 0.2, 0.2)

const LABEL_NODE_NAME := "GameMessage"
const TIMER_NODE_NAME := "GameMessageTimer"
const DISPLAY_DURATION := 2.0
const FADE_DURATION := 0.3
const CENTER_OFFSET_P1_HAND := Vector2(-40.0, -125.0)
const DEFAULT_LABEL_WIDTH := 420.0
const DEFAULT_LABEL_HEIGHT := 32.0

static func create_ui_state() -> Dictionary:
	return {
		"label": null,
		"timer": null,
		"anchor_position": Vector2.ZERO,
	}

static func text_for_code(message_code: String, params: Dictionary = {}) -> String:
	return LanguageManager.ingame_text(message_code, params)

static func normalize_ingame_message(ui_message: Dictionary) -> Dictionary:
	var message_code := String(ui_message.get("message_code", "")).strip_edges()
	if not message_code.begins_with(INGAME_PREFIX):
		return {}

	var params_val = ui_message.get("message_params", {})
	var params: Dictionary = params_val if params_val is Dictionary else {}
	var text := text_for_code(message_code, params)
	if text == "":
		return {}

	var color := color_for_code(message_code)
	var color_val = ui_message.get("color", null)
	if color_val is Color:
		color = color_val
	elif color_val is String and String(color_val) != "":
		color = Color.from_string(String(color_val), color)

	return {
		"text": text,
		"message_code": message_code,
		"message_params": params,
		"color": color,
	}

static func ensure_ui(state: Dictionary, root: Control, timeout_handler: Callable) -> void:
	if root == null:
		return

	var label := _get_label(state)
	if label == null:
		label = RichTextLabel.new()
		label.name = LABEL_NODE_NAME
		label.z_index = 1
		label.layout_mode = 0
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(label)
		state["label"] = label

	_setup_ingame_label(label)

	var timer := _get_timer(state)
	if timer == null:
		timer = Timer.new()
		timer.name = TIMER_NODE_NAME
		root.add_child(timer)
		state["timer"] = timer

	timer.wait_time = DISPLAY_DURATION
	timer.one_shot = true
	if timeout_handler.is_valid() and not timer.timeout.is_connected(timeout_handler):
		timer.timeout.connect(timeout_handler)

static func apply_layout(state: Dictionary, anchor_position: Vector2) -> void:
	var label := _get_label(state)
	if label == null:
		return
	state["anchor_position"] = anchor_position
	_reposition_label(state)

static func show_ingame_message(ui_message: Dictionary, state: Dictionary) -> void:
	var ingame_label := _get_label(state)
	var ingame_timer := _get_timer(state)

	var normalized := normalize_ingame_message(ui_message)
	if normalized.is_empty():
		return

	var text := String(normalized.get("text", ""))
	if text == "" or ingame_label == null:
		return

	ingame_label.text = "[center][color=%s]%s[/color][/center]" % [
		color_for_code(String(normalized.get("message_code", ""))).to_html(),
		text
	]
	_resize_single_line_label(ingame_label)
	_reposition_label(state)
	ingame_label.visible = true

	if ingame_timer != null and ingame_timer.has_method("start"):
		ingame_timer.start()

static func cleanup(state: Dictionary) -> void:
	state["label"] = null
	state["timer"] = null

static func get_label(state: Dictionary) -> RichTextLabel:
	return _get_label(state)

static func get_fade_duration() -> float:
	return FADE_DURATION

static func color_for_code(message_code: String) -> Color:
	if INGAME_GREEN_CODES.has(message_code):
		return INGAME_GREEN_COLOR
	return INGAME_RED_COLOR

static func _setup_ingame_label(ingame_label: RichTextLabel) -> void:
	if ingame_label == null:
		return
	ingame_label.visible = false
	ingame_label.clear()
	ingame_label.bbcode_enabled = true
	ingame_label.fit_content = true
	ingame_label.scroll_active = false
	ingame_label.custom_minimum_size = Vector2.ZERO
	ingame_label.size = Vector2(DEFAULT_LABEL_WIDTH, DEFAULT_LABEL_HEIGHT)
	ingame_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	ingame_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ingame_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

static func _reposition_label(state: Dictionary) -> void:
	var label := _get_label(state)
	if label == null:
		return
	var anchor :Vector2= state.get("anchor_position", Vector2.ZERO)
	var anchor_position :Vector2= anchor if anchor is Vector2 else Vector2.ZERO
	var label_width := maxf(label.size.x, DEFAULT_LABEL_WIDTH)
	label.position = anchor_position + CENTER_OFFSET_P1_HAND - Vector2(label_width * 0.5, 0.0)

static func _resize_single_line_label(label: RichTextLabel) -> void:
	if label == null:
		return
	label.reset_size()
	var minimum_size := label.get_minimum_size()
	label.size = Vector2(maxf(DEFAULT_LABEL_WIDTH, minimum_size.x), DEFAULT_LABEL_HEIGHT)

static func _get_label(state: Dictionary) -> RichTextLabel:
	var label := state.get("label", null) as RichTextLabel
	if label != null and is_instance_valid(label):
		return label
	return null

static func _get_timer(state: Dictionary) -> Timer:
	var timer := state.get("timer", null) as Timer
	if timer != null and is_instance_valid(timer):
		return timer
	return null
