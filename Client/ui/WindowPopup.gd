# WindowPopup.gd v2.0
extends Window
class_name WindowPopup

const Protocol = preload("res://Client/net/Protocol.gd")
const POPUP_PREFIX := "MSG_POPUP_"

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

@onready var _label: Label = $MarginContainer/VBox/Label
@onready var _btn_accept: Button = $MarginContainer/VBox/Buttons/ButtonAccept
@onready var _btn_refuse: Button = $MarginContainer/VBox/Buttons/ButtonRefuse
@onready var _btn_ok: Button = $MarginContainer/VBox/Buttons/ButtonOK

func show_info(message: String, payload: Dictionary = {}) -> void:
	_mode = Mode.INFO
	_payload = payload.duplicate(true)
	_action_ok = String(payload.get("ok_action_id", ACTION_INFO_OK))

	_label.text = message
	_btn_accept.visible = false
	_btn_refuse.visible = false
	_btn_ok.visible = true

	popup_centered()

func show_ui_message(ui_message: Dictionary, payload: Dictionary = {}) -> void:
	var normalized := Protocol.normalize_game_message(ui_message)
	var message_code := String(normalized.get("message_code", "")).strip_edges()
	if not message_code.begins_with(POPUP_PREFIX):
		return
	_show_normalized_ui_message(normalized, payload)

func show_confirm(message: String, yes_text := "Oui", no_text := "Non", payload: Dictionary = {}) -> void:
	_mode = Mode.CONFIRM
	_payload = payload.duplicate(true)
	_action_accept = String(payload.get("yes_action_id", _popup_action_id("CONFIRM_YES", ACTION_CONFIRM_YES)))
	_action_refuse = String(payload.get("no_action_id", _popup_action_id("CONFIRM_NO", ACTION_CONFIRM_NO)))

	_label.text = message
	_btn_accept.text = yes_text
	_btn_refuse.text = no_text
	_btn_accept.visible = true
	_btn_refuse.visible = true
	_btn_ok.visible = false

	popup_centered()

func show_invite_request(from_user: String, payload: Dictionary = {}) -> void:
	var invite_payload := payload.duplicate(true)
	invite_payload["flow"] = invite_payload.get("flow", String(Protocol.POPUP_FLOW["INVITE_REQUEST"]))
	invite_payload["from"] = invite_payload.get("from", from_user)
	show_confirm(
		Protocol.popup_text(Protocol.MSG_POPUP_INVITE_RECEIVED, { "from": from_user }),
		"Accepter",
		"Refuser",
		invite_payload
	)

func _show_normalized_ui_message(normalized: Dictionary, payload: Dictionary = {}) -> void:
	var extra := payload.duplicate(true)
	extra["message_code"] = String(normalized.get("message_code", ""))
	show_info(String(normalized.get("text", "")), extra)

func _popup_action_id(key: String, fallback: String) -> String:
	return String(Protocol.POPUP_ACTION.get(key, fallback))

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
