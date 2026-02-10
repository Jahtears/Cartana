# WindowPopup.gd v2.0
extends Window
class_name WindowPopup

const Protocol = preload("res://Client/net/Protocol.gd")

signal action_selected(action_id: String, payload: Dictionary)

const ACTION_CONFIRM_YES := "confirm_yes"
const ACTION_CONFIRM_NO := "confirm_no"
const ACTION_INFO_OK := "info_ok"

enum Mode { NONE, INFO, CONFIRM }
var _mode: int = Mode.NONE
var _payload: Dictionary = {}
var _action_accept: String = ACTION_CONFIRM_YES
var _action_refuse: String = ACTION_CONFIRM_NO
var _action_ok: String = ACTION_INFO_OK
var _default_label_color: Color = Color.WHITE

@onready var _label: Label = $MarginContainer/VBox/Label
@onready var _btn_accept: Button = $MarginContainer/VBox/Buttons/ButtonAccept
@onready var _btn_refuse: Button = $MarginContainer/VBox/Buttons/ButtonRefuse
@onready var _btn_ok: Button = $MarginContainer/VBox/Buttons/ButtonOK

func _ready() -> void:
	_default_label_color = _label.get_theme_color("font_color")

func _label_color_from_payload(payload: Dictionary) -> Color:
	var color_val = payload.get("message_color", _default_label_color)
	if color_val is Color:
		return color_val
	if color_val is String and String(color_val) != "":
		return Color.from_string(String(color_val), _default_label_color)
	return _default_label_color

func _apply_label_color(color: Color) -> void:
	_label.add_theme_color_override("font_color", color)

func show_info(message: String, payload: Dictionary = {}) -> void:
	_mode = Mode.INFO
	_payload = payload.duplicate(true)
	_action_ok = String(payload.get("ok_action_id", ACTION_INFO_OK))

	_label.text = message
	_apply_label_color(_label_color_from_payload(_payload))
	_btn_accept.visible = false
	_btn_refuse.visible = false
	_btn_ok.visible = true

	popup_centered()

func show_ui_message(ui_message: Dictionary, payload: Dictionary = {}) -> void:
	var normalized := Protocol.normalize_game_message(ui_message)
	var extra := payload.duplicate(true)
	extra["message_code"] = String(normalized.get("code", ""))
	extra["message_color"] = normalized.get("color", _default_label_color)
	show_info(String(normalized.get("text", "")), extra)

func show_confirm(message: String, yes_text := "Oui", no_text := "Non", payload: Dictionary = {}) -> void:
	_mode = Mode.CONFIRM
	_payload = payload.duplicate(true)
	_action_accept = String(payload.get("yes_action_id", ACTION_CONFIRM_YES))
	_action_refuse = String(payload.get("no_action_id", ACTION_CONFIRM_NO))

	_label.text = message
	_apply_label_color(_default_label_color)
	_btn_accept.text = yes_text
	_btn_refuse.text = no_text
	_btn_accept.visible = true
	_btn_refuse.visible = true
	_btn_ok.visible = false

	popup_centered()

func show_invite_request(from_user: String, payload: Dictionary = {}) -> void:
	var invite_payload := payload.duplicate(true)
	invite_payload["flow"] = invite_payload.get("flow", "invite_request")
	invite_payload["from"] = invite_payload.get("from", from_user)
	show_confirm("%s t'invite à jouer" % from_user, "Accepter", "Refuser", invite_payload)

func _on_button_accept_pressed() -> void:
	if _mode == Mode.CONFIRM:
		action_selected.emit(_action_accept, _payload.duplicate(true))
	hide()
	_mode = Mode.NONE

func _on_button_refuse_pressed() -> void:
	if _mode == Mode.CONFIRM:
		action_selected.emit(_action_refuse, _payload.duplicate(true))
	hide()
	_mode = Mode.NONE

func _on_button_ok_pressed() -> void:
	if _mode == Mode.INFO:
		action_selected.emit(_action_ok, _payload.duplicate(true))
	hide()
	_mode = Mode.NONE
