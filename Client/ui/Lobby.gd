# Lobby.gd v1.0
extends Control

const Protocol = preload("res://Client/net/Protocol.gd")

var _is_changing_scene := false
var _statuses: Dictionary = {}            # username -> status

func _ready() -> void:
	$PlayerNameLabel.text = String(Global.username)

	if not NetworkManager.response.is_connected(_on_response):
		NetworkManager.response.connect(_on_response)
	if not NetworkManager.evt.is_connected(_on_evt):
		NetworkManager.evt.connect(_on_evt)
	if typeof(PopupUi) != TYPE_NIL and PopupUi != null and not PopupUi.action_selected.is_connected(_on_popup_action):
		PopupUi.action_selected.connect(_on_popup_action)
	if typeof(PopupUi) != TYPE_NIL and PopupUi != null:
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
				_show_error_popup(error, "Erreur get_players")

		"join_game", "spectate_game":
			if not ok:
				_show_error_popup(error, "Action impossible")

		"invite":
			if ok:
				PopupUi.show_ui_message({
					"text": "Invitation envoyée.",
					"code": Protocol.GAME_MESSAGE["INFO"],
				})
			else:
				_show_error_popup(error, "Invitation impossible")

# --------------------
# EVT (push serveur)
# --------------------
func _on_evt(type: String, data: Dictionary) -> void:
	match type:
		"start_game":
			var game_id: String = String(data.get("game_id", ""))
			var players: Array = data.get("players", [])
			var spectator: bool = bool(data.get("spectator", false))
			if typeof(PopupUi) != TYPE_NIL and PopupUi != null:
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
					"flow": "invite_request",
					"from": from_user
				})

		"invite_response":
			var ui := Protocol.normalize_game_message(data, Protocol.GAME_MESSAGE["INFO"])
			if String(ui.get("text", "")) != "":
				PopupUi.show_ui_message(ui)

func _show_error_popup(error: Dictionary, fallback_text: String) -> void:
	var ui := Protocol.normalize_error_message(error, fallback_text)
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
		"Regarder cette partie en spectateur ?\n(game_id: %s)\nJoueurs: %s" % [game_id, str(players)],
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
		"Se déconnecter et revenir à l'écran de connexion ?",
		"Oui", "Non",
		{"flow": "logout"}
	)

func _on_popup_action(action_id: String, payload: Dictionary) -> void:
	var flow := String(payload.get("flow", ""))
	match flow:
		"spectate_game":
			if action_id == "confirm_yes":
				_do_spectate_game(String(payload.get("game_id", "")))
		"logout":
			if action_id == "confirm_yes":
				await _do_logout()
		"invite_request":
			var from_user := String(payload.get("from", ""))
			if from_user == "":
				return
			if action_id == "confirm_yes":
				NetworkManager.request("invite_response", {"to": from_user, "accepted": true})
			elif action_id == "confirm_no":
				NetworkManager.request("invite_response", {"to": from_user, "accepted": false})

func _do_logout() -> void:
	NetworkManager.request("logout", {})
	NetworkManager.close()

	# ✅ reset "session"
	Global.username = ""

	# ✅ reset "game state" (nouvelle API: result)
	if Global.has_method("reset_game_state"):
		Global.reset_game_state()
	else:
		Global.current_game_id = ""
		Global.players_in_game.clear()
		Global.is_spectator = false
		if Global.has_variable("result"):
			Global.result.clear()
		if Global.has_variable("table_slots"):
			Global.table_slots.clear()
		if Global.has_variable("last_turn"):
			Global.last_turn.clear()
		if Global.has_variable("view"):
			Global.view = ""

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
	if typeof(PopupUi) != TYPE_NIL and PopupUi != null and PopupUi.action_selected.is_connected(_on_popup_action):
		PopupUi.action_selected.disconnect(_on_popup_action)
