extends Control

const Protocol = preload("res://Client/net/Protocol.gd")
const LanguageManager = preload("res://Client/Lang/LanguageManager.gd")

var _login_pending := false
var _last_username: String = ""

@onready var _username_input: LineEdit = $CenterContainer/VBoxContainer/Username_input
@onready var _pin_input: LineEdit = $CenterContainer/VBoxContainer/Pin_input
@onready var _login_button: Button = $CenterContainer/VBoxContainer/Login_button
@onready var _language_label: Label = $LanguageRow/LanguageLabel
@onready var _language_option_button: OptionButton = $LanguageRow/LanguageOptionButton

func _ready() -> void:
	if not NetworkManager.is_open():
		NetworkManager.connect_to_server()
	if not NetworkManager.response.is_connected(_on_response):
		NetworkManager.response.connect(_on_response)
	if not NetworkManager.disconnected.is_connected(_on_network_disconnected):
		NetworkManager.disconnected.connect(_on_network_disconnected)
	PopupUi.hide_and_reset()
	_setup_language_option_button()
	_apply_language_to_login_ui()

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
		var popup := Protocol.normalize_popup_error(error, Protocol.POPUP_AUTH_CONNECTION_ERROR)
		_show_popup_normalized(popup)

func _on_network_disconnected(_code: int, reason: String) -> void:
	if String(reason).strip_edges() == NetworkManager.DISCONNECT_REASON_LOGOUT:
		return
	_show_popup_code(Protocol.POPUP_AUTH_CONNECTION_ERROR)

func _show_message_code(message_code: String, params: Dictionary = {}) -> void:
	_show_popup_code(message_code, params)

func _show_popup_code(message_code: String, params: Dictionary = {}, payload: Dictionary = {}, options: Dictionary = {}) -> void:
	PopupUi.show_info_code(message_code, params, payload, options)

func _show_popup_normalized(normalized: Dictionary, payload: Dictionary = {}) -> void:
	var message_code := String(normalized.get("message_code", "")).strip_edges()
	if message_code == "":
		return
	var params_val = normalized.get("message_params", {})
	var params: Dictionary = params_val if params_val is Dictionary else {}
	var options: Dictionary = {}
	var text_override := String(normalized.get("text_override", "")).strip_edges()
	if text_override != "":
		options["text_override"] = text_override
	PopupUi.show_info_code(message_code, params, payload, options)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_on_login_button_pressed()

func _on_login_button_pressed() -> void:
	if _login_pending:
		return

	var username: String = _username_input.text.strip_edges()
	var pin: String = _pin_input.text.strip_edges()

	if username == "" or pin == "":
		_show_message_code(Protocol.POPUP_AUTH_MISSING_CREDENTIALS)
		return

	_last_username = username
	_login_pending = true

	NetworkManager.request("login", {
		"username": username,
		"pin": pin
	})

func _on_username_input_text_submitted(_new_text: String) -> void:
	_on_login_button_pressed()

func _on_pin_input_text_submitted(_new_text: String) -> void:
	_on_login_button_pressed()

func _setup_language_option_button() -> void:
	if _language_option_button == null:
		return
	_language_option_button.clear()
	_add_language_option(LanguageManager.LANG_FR)
	_add_language_option(LanguageManager.LANG_EN)

	var active_language := LanguageManager.get_language()
	_select_language_option(active_language)

func _add_language_option(language_code: String) -> void:
	var display_name := LanguageManager.language_display_name(language_code)
	var item_index := _language_option_button.item_count
	_language_option_button.add_item(display_name)
	_language_option_button.set_item_metadata(item_index, language_code)

func _select_language_option(language_code: String) -> void:
	var normalized := LanguageManager.normalize_language(language_code)
	for index in range(_language_option_button.item_count):
		var item_language := String(_language_option_button.get_item_metadata(index))
		if item_language == normalized:
			_language_option_button.select(index)
			return

func _refresh_language_options_labels() -> void:
	for index in range(_language_option_button.item_count):
		var item_language := String(_language_option_button.get_item_metadata(index))
		_language_option_button.set_item_text(index, LanguageManager.language_display_name(item_language))

func _apply_language_to_login_ui() -> void:
	_username_input.placeholder_text = LanguageManager.ui_text("login_username_placeholder", "Username")
	_pin_input.placeholder_text = LanguageManager.ui_text("login_pin_placeholder", "PIN")
	_login_button.text = LanguageManager.ui_text("login_button", "Login")
	_language_label.text = LanguageManager.ui_text("login_language_label", "Language")
	_refresh_language_options_labels()

func _on_language_option_button_item_selected(index: int) -> void:
	if index < 0 or index >= _language_option_button.item_count:
		return
	var language_code := String(_language_option_button.get_item_metadata(index))
	LanguageManager.set_language(language_code)
	_apply_language_to_login_ui()

func _exit_tree() -> void:
	if NetworkManager.response.is_connected(_on_response):
		NetworkManager.response.disconnect(_on_response)
	if NetworkManager.disconnected.is_connected(_on_network_disconnected):
		NetworkManager.disconnected.disconnect(_on_network_disconnected)
