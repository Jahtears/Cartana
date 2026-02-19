extends Window
class_name WindowPopup

const Protocol = preload("res://Client/net/Protocol.gd")

signal action_selected(action_id: String, payload: Dictionary)

const ACTION_CONFIRM_YES := "confirm_yes"
const ACTION_CONFIRM_NO := "confirm_no"
const ACTION_INFO_OK := "info_ok"

const OPTION_TEXT_OVERRIDE := "text_override"
const OPTION_YES_LABEL_KEY := "yes_label_key"
const OPTION_NO_LABEL_KEY := "no_label_key"
const OPTION_OK_LABEL_KEY := "ok_label_key"

enum Mode { NONE, INFO, CONFIRM }
var _mode: int = Mode.NONE
var _payload: Dictionary = {}
var _action_accept: String = ACTION_CONFIRM_YES
var _action_refuse: String = ACTION_CONFIRM_NO
var _action_ok: String = ACTION_INFO_OK

@onready var _label: Label = $MarginContainer/VBox/MessageLabel
@onready var _btn_accept: Button = $MarginContainer/VBox/Buttons/ConfirmYesButton
@onready var _btn_refuse: Button = $MarginContainer/VBox/Buttons/ConfirmNoButton
@onready var _btn_ok: Button = $MarginContainer/VBox/Buttons/InfoOkButton

func _ready() -> void:
	if not close_requested.is_connected(_on_close_requested):
		close_requested.connect(_on_close_requested)
	hide_and_reset()

func show_info_code(message_code: String, params: Dictionary = {}, payload: Dictionary = {}, options: Dictionary = {}) -> void:
	var normalized := _normalize_popup_payload(message_code, params, options)
	var actions := {
		"ok": String(payload.get("ok_action_id", ACTION_INFO_OK)),
	}
	_show_mode(Mode.INFO, normalized, payload, options, actions)

func show_confirm_code(message_code: String, params: Dictionary = {}, payload: Dictionary = {}, options: Dictionary = {}) -> void:
	var normalized := _normalize_popup_payload(message_code, params, options)
	var actions := {
		"yes": String(payload.get("yes_action_id", _popup_action_id("CONFIRM_YES", ACTION_CONFIRM_YES))),
		"no": String(payload.get("no_action_id", _popup_action_id("CONFIRM_NO", ACTION_CONFIRM_NO))),
	}
	_show_mode(Mode.CONFIRM, normalized, payload, options, actions)

func hide_and_reset() -> void:
	hide()
	_mode = Mode.NONE
	_payload.clear()
	_action_accept = ACTION_CONFIRM_YES
	_action_refuse = ACTION_CONFIRM_NO
	_action_ok = ACTION_INFO_OK

func _show_mode(mode: int, normalized: Dictionary, payload: Dictionary, options: Dictionary, actions: Dictionary) -> void:
	_mode = mode
	_payload = payload.duplicate(true)
	_payload["message_code"] = String(normalized.get("message_code", ""))
	_payload["message_params"] = normalized.get("message_params", {})

	_label.text = _resolve_message_text(normalized, options)

	if mode == Mode.INFO:
		_action_ok = String(actions.get("ok", ACTION_INFO_OK))
		_btn_ok.text = _resolve_label(options, OPTION_OK_LABEL_KEY, "ok")
		_btn_accept.visible = false
		_btn_refuse.visible = false
		_btn_ok.visible = true
	else:
		_action_accept = String(actions.get("yes", ACTION_CONFIRM_YES))
		_action_refuse = String(actions.get("no", ACTION_CONFIRM_NO))
		_btn_accept.text = _resolve_label(options, OPTION_YES_LABEL_KEY, "yes")
		_btn_refuse.text = _resolve_label(options, OPTION_NO_LABEL_KEY, "no")
		_btn_accept.visible = true
		_btn_refuse.visible = true
		_btn_ok.visible = false

	popup_centered()

func _normalize_popup_payload(message_code: String, params: Dictionary, options: Dictionary) -> Dictionary:
	var payload := {
		"message_code": message_code,
		"message_params": params,
	}
	var text_override := String(options.get(OPTION_TEXT_OVERRIDE, "")).strip_edges()
	if text_override != "":
		payload["text"] = text_override
	return Protocol.normalize_popup_message(payload)

func _resolve_message_text(normalized: Dictionary, options: Dictionary) -> String:
	var text_override := String(options.get(OPTION_TEXT_OVERRIDE, "")).strip_edges()
	if text_override != "":
		return text_override
	return String(normalized.get("text", ""))

func _resolve_label(options: Dictionary, option_key: String, default_label_key: String) -> String:
	var label_key := String(options.get(option_key, default_label_key)).strip_edges()
	return Protocol.popup_label(label_key)

func _popup_action_id(key: String, fallback: String) -> String:
	return String(Protocol.POPUP_ACTION.get(key, fallback))

func _on_button_accept_pressed() -> void:
	if _mode == Mode.CONFIRM:
		action_selected.emit(_action_accept, _payload.duplicate(true))
	hide_and_reset()

func _on_button_refuse_pressed() -> void:
	if _mode == Mode.CONFIRM:
		action_selected.emit(_action_refuse, _payload.duplicate(true))
	hide_and_reset()

func _on_button_ok_pressed() -> void:
	if _mode == Mode.INFO:
		action_selected.emit(_action_ok, _payload.duplicate(true))
	hide_and_reset()

func _on_close_requested() -> void:
	hide_and_reset()
