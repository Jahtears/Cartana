# Lobby.gd v1.0
extends Control

const Protocol = preload("res://Client/net/Protocol.gd")

const REQ_GET_PLAYERS := "get_players"
const REQ_JOIN_GAME := "join_game"
const REQ_INVITE := "invite"
const REQ_INVITE_RESPONSE := "invite_response"
const REQ_SPECTATE_GAME := "spectate_game"
const REQ_LOGOUT := "logout"

const FLOW_SPECTATE_GAME := REQ_SPECTATE_GAME
const FLOW_LOGOUT := REQ_LOGOUT
const FLOW_INVITE_REQUEST_FALLBACK := "invite_request"
const ACTION_CONFIRM_YES_FALLBACK := "confirm_yes"
const ACTION_NETWORK_RETRY := "network_retry"

var _is_changing_scene := false
var _statuses: Dictionary = {}            # username -> status
var _network_disconnected := false

func _ready() -> void:
	$PlayerNameLabel.text = String(Global.username)

	if not NetworkManager.response.is_connected(_on_response):
		NetworkManager.response.connect(_on_response)
	if not NetworkManager.evt.is_connected(_on_evt):
		NetworkManager.evt.connect(_on_evt)
	if not NetworkManager.connection_lost.is_connected(_on_connection_lost):
		NetworkManager.connection_lost.connect(_on_connection_lost)
	if not NetworkManager.connection_restored.is_connected(_on_connection_restored):
		NetworkManager.connection_restored.connect(_on_connection_restored)
	if not NetworkManager.reconnect_failed.is_connected(_on_reconnect_failed):
		NetworkManager.reconnect_failed.connect(_on_reconnect_failed)
	if not NetworkManager.server_closed.is_connected(_on_server_closed):
		NetworkManager.server_closed.connect(_on_server_closed)
	if not PopupUi.action_selected.is_connected(_on_popup_action):
		PopupUi.action_selected.connect(_on_popup_action)
	PopupUi.hide_and_reset()

	NetworkManager.request(REQ_GET_PLAYERS, {})

# --------------------
# REQ/RES
# --------------------
func _on_response(_rid: String, type: String, ok: bool, data: Dictionary, error: Dictionary) -> void:
	match type:
		REQ_GET_PLAYERS:
			if ok:
				_statuses = data.get("statuses", {}) as Dictionary
				update_games_list(data.get("games", []))
				update_players_list(data.get("players", []))
			else:
				_show_error_popup(error, Protocol.POPUP_LOBBY_GET_PLAYERS_ERROR)

		REQ_JOIN_GAME, REQ_SPECTATE_GAME:
			if not ok:
				_show_error_popup(error, Protocol.POPUP_UI_ACTION_IMPOSSIBLE)

		REQ_INVITE:
			if ok:
				_show_popup_code(Protocol.POPUP_INVITE_SENT)
			else:
				_show_error_popup(error, Protocol.POPUP_INVITE_FAILED)

# --------------------
# EVT (push serveur)
# --------------------
func _on_evt(type: String, data: Dictionary) -> void:
	match type:
		"start_game":
			var game_id: String = String(data.get("game_id", ""))
			var players: Array = data.get("players", [])
			var spectator: bool = bool(data.get("spectator", false))
			PopupUi.hide_and_reset()
			start_game(game_id, players, spectator)

		"players_list":
			_statuses = data.get("statuses", {}) as Dictionary
			update_players_list(data.get("players", []))

		"games_list":
			update_games_list(data.get("games", []))

		"invite_request":
			var from_user := String(data.get("from", ""))
			if from_user != "":
				_show_confirm_code(
					Protocol.POPUP_INVITE_RECEIVED,
					{"from": from_user},
					{
						"flow": Protocol.popup_flow("INVITE_REQUEST", FLOW_INVITE_REQUEST_FALLBACK),
						"from": from_user
					},
					{"yes_label_key": "accept", "no_label_key": "refuse"}
				)

		REQ_INVITE_RESPONSE:
			var ui := Protocol.normalize_invite_response_ui(data)
			if String(ui.get("text", "")) != "":
				_show_popup_normalized(ui)

		"invite_cancelled":
			_handle_invite_cancelled(data)

func _show_error_popup(error: Dictionary, fallback_message: String) -> void:
	var popup := Protocol.normalize_popup_error(error, fallback_message)
	_show_popup_normalized(popup)

func _on_connection_lost() -> void:
	_network_disconnected = true
	_show_popup_code(Protocol.POPUP_PLAYER_DISCONNECTED)

func _on_connection_restored() -> void:
	if not _network_disconnected:
		return
	_network_disconnected = false
	_show_popup_code(Protocol.POPUP_PLAYER_RECONNECTED)

func _on_reconnect_failed() -> void:
	if not _network_disconnected:
		return
	_show_popup_code(
		Protocol.POPUP_PLAYER_RECONNECT_FAIL,
		{},
		{"ok_action_id": ACTION_NETWORK_RETRY},
		{"ok_label_key": "retry"}
	)

func _on_server_closed(_server_reason: String, _close_code: int, _raw_reason: String) -> void:
	_network_disconnected = false
	_show_popup_code(Protocol.POPUP_TECH_INTERNAL_ERROR)

func _handle_invite_cancelled(data: Dictionary) -> void:
	var ui := Protocol.invite_cancelled_ui(data)
	if String(ui.get("text", "")).strip_edges() == "":
		return
	_show_popup_normalized(ui)

func _show_popup_code(message_code: String, params: Dictionary = {}, payload: Dictionary = {}, options: Dictionary = {}) -> void:
	PopupUi.show_info_code(message_code, params, payload, options)

func _show_confirm_code(message_code: String, params: Dictionary = {}, payload: Dictionary = {}, options: Dictionary = {}) -> void:
	PopupUi.show_confirm_code(message_code, params, payload, options)

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
	_show_popup_code(message_code, params, payload, options)

# --------------------
# UI / LOGIC
# --------------------
func start_game(game_id: String, players: Array, spectator: bool) -> void:
	Global.current_game_id = game_id
	Global.players_in_game = players
	Global.is_spectator = spectator

	if _is_changing_scene:
		return
	_is_changing_scene = true
	call_deferred("_deferred_change_to_game")

func update_players_list(players: Array) -> void:
	var list: Node = $PlayersBox/PlayersList/PlayersItems
	for child in list.get_children():
		child.queue_free()

	for p in players:
		var ps: String = String(p)
		if ps == Global.username:
			continue

		# ✅ status API : filtrer via activity (pas via scan games)
		var st: Dictionary = _statuses.get(ps, {}) as Dictionary
		var activity: Dictionary = st.get("activity", {}) as Dictionary
		var typ := String(activity.get("type", "lobby"))

		if typ != "lobby":
			continue

		list.add_child(create_player_box(ps))

func update_games_list(games: Array) -> void:
	Global.current_games = games

	var list: Node = $GameBox/GameList/GameItems
	for child in list.get_children():
		child.queue_free()

	for game in games:
		list.add_child(create_game_box(game))

func create_game_box(game: Variant) -> Button:
	var g := game as Dictionary
	var game_id := String(g.get("game_id", ""))
	var players: Array = g.get("players", [])

	var btn := Button.new()
	btn.text = str(players) #player vs player
	btn.custom_minimum_size = Vector2(300, 40)
	btn.focus_mode = Control.FOCUS_NONE

	btn.pressed.connect(func() -> void:
		_on_game_clicked(game_id, players)
	)

	return btn

func create_player_box(username: String) -> Button:
	var btn := Button.new()
	btn.text = username
	btn.custom_minimum_size = Vector2(200, 40)
	btn.focus_mode = Control.FOCUS_NONE

	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_color_hover", Color(0.9, 0.9, 0.9))
	btn.add_theme_color_override("font_color_pressed", Color(0.8, 0.8, 0.8))
	btn.add_theme_color_override("bg_color", Color(0.2, 0.2, 0.2))
	btn.add_theme_color_override("bg_color_hover", Color(0.3, 0.3, 0.3))
	btn.add_theme_color_override("bg_color_pressed", Color(0.15, 0.15, 0.15))

	btn.pressed.connect(func() -> void:
		send_invite(username)
	)

	return btn

func _on_game_clicked(game_id: String, players: Array) -> void:
	if game_id == "":
		return

	_show_confirm_code(
		Protocol.POPUP_SPECTATE_CONFIRM,
		{
			"game_id": game_id,
			"players": str(players),
		},
		{"flow": FLOW_SPECTATE_GAME, "game_id": game_id}
	)

# --------------------
# ACTIONS
# --------------------
func send_invite(target: String) -> void:
	NetworkManager.request(REQ_INVITE, { "to": target })

func _do_spectate_game(game_id: String) -> void:
	if game_id == "":
		return

	NetworkManager.request(REQ_SPECTATE_GAME, { "game_id": game_id })

# --------------------
# Déconnexion (bouton Lobby)
# --------------------
func _on_deconnexion_pressed() -> void:
	_show_confirm_code(
		Protocol.POPUP_LOGOUT_CONFIRM,
		{},
		{"flow": FLOW_LOGOUT}
	)

func _on_popup_action(action_id: String, payload: Dictionary) -> void:
	if action_id == ACTION_NETWORK_RETRY:
		NetworkManager.retry_now()
		return

	var invite_req := Protocol.invite_action_request(action_id, payload)
	if not invite_req.is_empty():
		NetworkManager.request(REQ_INVITE_RESPONSE, invite_req)
		return

	var flow := String(payload.get("flow", ""))
	match flow:
		FLOW_SPECTATE_GAME:
			if action_id == Protocol.popup_action("CONFIRM_YES", ACTION_CONFIRM_YES_FALLBACK):
				_do_spectate_game(String(payload.get("game_id", "")))
		FLOW_LOGOUT:
			if action_id == Protocol.popup_action("CONFIRM_YES", ACTION_CONFIRM_YES_FALLBACK):
				await _do_logout()

func _do_logout() -> void:
	await NetworkManager.request_async(REQ_LOGOUT, {}, 3.0)
	NetworkManager.close(1000, "logout")

	# ✅ reset "session"
	Global.username = ""

	# ✅ reset "game state" (API canonique)
	Global.reset_game_state()

	await _go_to_login_safe()

func _go_to_login_safe() -> void:
	if _is_changing_scene:
		return
	_is_changing_scene = true
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://Client/Scenes/Login.tscn")

func _deferred_change_to_game() -> void:
	if not is_inside_tree():
		return
	get_tree().change_scene_to_file("res://Client/Scenes/Game.tscn")

func _exit_tree() -> void:
	if NetworkManager.evt.is_connected(_on_evt):
		NetworkManager.evt.disconnect(_on_evt)
	if NetworkManager.response.is_connected(_on_response):
		NetworkManager.response.disconnect(_on_response)
	if NetworkManager.connection_lost.is_connected(_on_connection_lost):
		NetworkManager.connection_lost.disconnect(_on_connection_lost)
	if NetworkManager.connection_restored.is_connected(_on_connection_restored):
		NetworkManager.connection_restored.disconnect(_on_connection_restored)
	if NetworkManager.reconnect_failed.is_connected(_on_reconnect_failed):
		NetworkManager.reconnect_failed.disconnect(_on_reconnect_failed)
	if NetworkManager.server_closed.is_connected(_on_server_closed):
		NetworkManager.server_closed.disconnect(_on_server_closed)
	if PopupUi.action_selected.is_connected(_on_popup_action):
		PopupUi.action_selected.disconnect(_on_popup_action)
