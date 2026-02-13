# Lobby.gd v1.0
extends Control

const Protocol = preload("res://Client/net/Protocol.gd")
const PopupMessages = preload("res://Client/game/messages/PopupMessages.gd")

var _is_changing_scene := false
var _statuses: Dictionary = {}            # username -> status

func _ready() -> void:
	$PlayerNameLabel.text = String(Global.username)

	if not NetworkManager.response.is_connected(_on_response):
		NetworkManager.response.connect(_on_response)
	if not NetworkManager.evt.is_connected(_on_evt):
		NetworkManager.evt.connect(_on_evt)
	if not PopupUi.action_selected.is_connected(_on_popup_action):
		PopupUi.action_selected.connect(_on_popup_action)
	PopupUi.hide()

	NetworkManager.request("get_players", {})

# --------------------
# REQ/RES
# --------------------
func _on_response(_rid: String, type: String, ok: bool, data: Dictionary, error: Dictionary) -> void:
	match type:
		"get_players":
			if ok:
				_statuses = data.get("statuses", {}) as Dictionary
				update_games_list(data.get("games", []))
				update_players_list(data.get("players", []))
			else:
				_show_error_popup(error, PopupMessages.MSG_POPUP_LOBBY_GET_PLAYERS_ERROR)

		"join_game", "spectate_game":
			if not ok:
				_show_error_popup(error, PopupMessages.MSG_POPUP_UI_ACTION_IMPOSSIBLE)

		"invite":
			if ok:
				PopupUi.show_ui_message({
					"text": PopupMessages.MSG_POPUP_INVITE_SENT,
					"code": Protocol.GAME_MESSAGE["INFO"],
				})
			else:
				_show_error_popup(error, PopupMessages.MSG_POPUP_INVITE_FAILED)

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
					"flow": String(Protocol.POPUP_FLOW["INVITE_REQUEST"]),
					"from": from_user
				})

		"invite_response":
			var ui := Protocol.normalize_invite_response_ui(data)
			if String(ui.get("text", "")) != "":
				PopupUi.show_ui_message(ui)

func _show_error_popup(error: Dictionary, fallback_message: String) -> void:
	var ui := Protocol.normalize_error_message(error, fallback_message)
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
	btn.text = "Partie " + game_id + " : " + str(players)
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
			PopupMessages.MSG_POPUP_SPECTATE_CONFIRM,
			{
				"game_id": game_id,
				"players": str(players),
			}
		),
		"Oui", "Non",
		{"flow": "spectate_game", "game_id": game_id}
	)

# --------------------
# ACTIONS
# --------------------
func send_invite(target: String) -> void:
	NetworkManager.request("invite", { "to": target })

func _do_spectate_game(game_id: String) -> void:
	if game_id == "":
		return

	NetworkManager.request("spectate_game", { "game_id": game_id })

# --------------------
# Déconnexion (bouton Lobby)
# --------------------
func _on_deconnexion_pressed() -> void:
	PopupUi.show_confirm(
		Protocol.popup_text(PopupMessages.MSG_POPUP_LOGOUT_CONFIRM),
		"Oui", "Non",
		{"flow": "logout"}
	)

func _on_popup_action(action_id: String, payload: Dictionary) -> void:
	var invite_req := Protocol.invite_action_request(action_id, payload)
	if not invite_req.is_empty():
		NetworkManager.request("invite_response", invite_req)
		return

	var flow := String(payload.get("flow", ""))
	match flow:
		"spectate_game":
			if action_id == String(Protocol.POPUP_ACTION["CONFIRM_YES"]):
				_do_spectate_game(String(payload.get("game_id", "")))
		"logout":
			if action_id == String(Protocol.POPUP_ACTION["CONFIRM_YES"]):
				await _do_logout()

func _do_logout() -> void:
	NetworkManager.request("logout", {})
	NetworkManager.close()

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
	if PopupUi.action_selected.is_connected(_on_popup_action):
		PopupUi.action_selected.disconnect(_on_popup_action)
