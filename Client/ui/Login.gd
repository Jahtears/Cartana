#Login V1.0
extends Control

var _login_pending := false
var _last_username: String = ""

func _ready() -> void:
	if not NetworkManager.is_open():
		NetworkManager.connect_to_server()
	if not NetworkManager.response.is_connected(_on_response):
		NetworkManager.response.connect(_on_response)

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
		show_error(String(error.get("message", "Erreur de connexion")))

func show_error(message: String) -> void:
	$Error_dialog.dialog_text = message
	$Error_dialog.popup_centered()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_on_login_button_pressed()
	
func _on_login_button_pressed() -> void:
	if _login_pending:
		return

	var username: String = $CenterContainer/VBoxContainer/Username_input.text.strip_edges()
	var pin: String = $CenterContainer/VBoxContainer/Pin_input.text.strip_edges()

	if username == "" or pin == "":
		show_error("Identifiant ou PIN manquant.")
		return

	_last_username = username
	_login_pending = true

	NetworkManager.request("login", {
		"username": username,
		"pin": pin
	})
