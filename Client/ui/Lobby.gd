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

const BUTTON_YES := "Oui"
const BUTTON_NO := "Non"
const GAME_ROW_PREFIX := "Partie "

var _is_changing_scene := false
var _statuses: Dictionary = {}            # username -> status

func _ready() -> void:
	$PlayerNameLabel.text = String(Global.username)

	if not NetworkManager.response.is_connected(_on_response):
		NetworkManager.response.connect(_on_response)
	if not NetworkManager.evt.is_connected(_on_evt):
		NetworkManager.evt.connect(_on_evt)
	if not NetworkManager.disconnected.is_connected(_on_network_disconnected):
		NetworkManager.disconnected.connect(_on_network_disconnected)
	if not PopupUi.action_selected.is_connected(_on_popup_action):
		PopupUi.action_selected.connect(_on_popup_action)
	PopupUi.hide()

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
				_show_error_popup(error, Protocol.MSG_POPUP_LOBBY_GET_PLAYERS_ERROR)

		REQ_JOIN_GAME, REQ_SPECTATE_GAME:
			if not ok:
				_show_error_popup(error, Protocol.MSG_POPUP_UI_ACTION_IMPOSSIBLE)

		REQ_INVITE:
			if ok:
				PopupUi.show_ui_message({
					"message_code": Protocol.MSG_POPUP_INVITE_SENT,
				})
			else:
				_show_error_popup(error, Protocol.MSG_POPUP_INVITE_FAILED)

# --------------------
# EVT (push serveur)
# --------------------
func _on_evt(type: String, data: Dictionary) -> void:
	match type:
		"start_game":
			var game_id: String = String(data.get("game_id", ""))
			var players: Array = data.get("players", [])
			var spectator: bool = bool(data.get("spectator", false))
			PopupUi.hide()
			start_game(game_id, players, spectator)

		"players_list":
			_statuses = data.get("statuses", {}) as Dictionary
			update_players_list(data.get("players", []))

		"games_list":
			update_games_list(data.get("games", []))

		"invite_request":
			var from_user := String(data.get("from", ""))
			if from_user != "":
				PopupUi.show_invite_request(from_user, {
					"flow": Protocol.popup_flow("INVITE_REQUEST", FLOW_INVITE_REQUEST_FALLBACK),
					"from": from_user
				})

		REQ_INVITE_RESPONSE:
			var ui := Protocol.normalize_invite_response_ui(data)
			if String(ui.get("text", "")) != "":
				PopupUi.show_ui_message(ui)

		"invite_cancelled":
			_handle_invite_cancelled(data)

func _show_error_popup(error: Dictionary, fallback_message: String) -> void:
	var ui := Protocol.normalize_error_message(error, fallback_message)
	PopupUi.show_ui_message(ui)

func _on_network_disconnected(_code: int, reason: String) -> void:
	if String(reason).strip_edges() == NetworkManager.DISCONNECT_REASON_LOGOUT:
		return
	PopupUi.show_ui_message({
		"message_code": Protocol.MSG_POPUP_AUTH_CONNECTION_ERROR,
	})

func _handle_invite_cancelled(data: Dictionary) -> void:
	var ui := Protocol.invite_cancelled_ui(data)
	if String(ui.get("text", "")).strip_edges() == "":
		return
	PopupUi.show_ui_message(ui)

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
	var list: Node = $PlayersBox/PlayersList
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

	var list: Node = $GameBox/GameList
	for child in list.get_children():
		child.queue_free()

	for game in games:
		list.add_child(create_game_box(game))

func create_game_box(game: Variant) -> Button:
	var g := game as Dictionary
	var game_id := String(g.get("game_id", ""))
	var players: Array = g.get("players", [])

	var btn := Button.new()
	btn.text = GAME_ROW_PREFIX + game_id + " : " + str(players)
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

	PopupUi.show_confirm(
		Protocol.popup_text(
			Protocol.MSG_POPUP_SPECTATE_CONFIRM,
			{
				"game_id": game_id,
				"players": str(players),
			}
		),
		BUTTON_YES,
		BUTTON_NO,
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
	PopupUi.show_confirm(
		Protocol.popup_text(Protocol.MSG_POPUP_LOGOUT_CONFIRM),
		BUTTON_YES,
		BUTTON_NO,
		{"flow": FLOW_LOGOUT}
	)

func _on_popup_action(action_id: String, payload: Dictionary) -> void:
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
	if NetworkManager.disconnected.is_connected(_on_network_disconnected):
		NetworkManager.disconnected.disconnect(_on_network_disconnected)
	if PopupUi.action_selected.is_connected(_on_popup_action):
		PopupUi.action_selected.disconnect(_on_popup_action)
