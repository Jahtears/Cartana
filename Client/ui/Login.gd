#Login V1.0
extends Control

const Protocol = preload("res://Client/net/Protocol.gd")

var _login_pending := false
var _last_username: String = ""

func _ready() -> void:
	if not NetworkManager.is_open():
		NetworkManager.connect_to_server()
	if not NetworkManager.response.is_connected(_on_response):
		NetworkManager.response.connect(_on_response)
	if not NetworkManager.disconnected.is_connected(_on_network_disconnected):
		NetworkManager.disconnected.connect(_on_network_disconnected)
	PopupUi.hide()

func _on_response(_rid: String, type: String, ok: bool, data: Dictionary, error: Dictionary) -> void:
	if type != "login":
		return

	_login_pending = false

	if ok:
		var u := String(data.get("username", ""))
		if u == "":
			u = _last_username
		Global.username = u
		get_tree().change_scene_to_file("res://Client/Scenes/Lobby.tscn")
	else:
		var ui := Protocol.normalize_error_message(error, Protocol.MSG_POPUP_AUTH_CONNECTION_ERROR)
		PopupUi.show_ui_message(ui)

func _on_network_disconnected(_code: int, reason: String) -> void:
	if String(reason).strip_edges() == NetworkManager.DISCONNECT_REASON_LOGOUT:
		return
	PopupUi.show_ui_message({
		"message_code": Protocol.MSG_POPUP_AUTH_CONNECTION_ERROR,
	})

func _show_message_code(message_code: String, params: Dictionary = {}) -> void:
	PopupUi.show_ui_message({
		"message_code": message_code,
		"message_params": params,
	})

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_on_login_button_pressed()
	
func _on_login_button_pressed() -> void:
	if _login_pending:
		return

	var username: String = $CenterContainer/VBoxContainer/Username_input.text.strip_edges()
	var pin: String = $CenterContainer/VBoxContainer/Pin_input.text.strip_edges()

	if username == "" or pin == "":
		_show_message_code(Protocol.MSG_POPUP_AUTH_MISSING_CREDENTIALS)
		return

	_last_username = username
	_login_pending = true

	NetworkManager.request("login", {
		"username": username,
		"pin": pin
	})

func _exit_tree() -> void:
	if NetworkManager.response.is_connected(_on_response):
		NetworkManager.response.disconnect(_on_response)
	if NetworkManager.disconnected.is_connected(_on_network_disconnected):
		NetworkManager.disconnected.disconnect(_on_network_disconnected)
