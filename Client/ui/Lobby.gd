# Lobby.gd v1.0
extends Control

var _is_changing_scene := false
var _pending_game_action: Dictionary = {} # {game_id:"...", players:[...]}
var _statuses: Dictionary = {}            # username -> status

func _ready() -> void:
	$PlayerNameLabel.text = String(Global.username)

	if not NetworkManager.response.is_connected(_on_response):
		NetworkManager.response.connect(_on_response)
	if not NetworkManager.evt.is_connected(_on_evt):
		NetworkManager.evt.connect(_on_evt)

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
				PopupUi.show_info(String(error.get("message", "Erreur get_players")))

		"join_game", "spectate_game":
			if not ok:
				PopupUi.show_info(String(error.get("message", "Action impossible")))

# --------------------
# EVT (push serveur)
# --------------------
func _on_evt(type: String, data: Dictionary) -> void:
	match type:
		"start_game":
			var game_id: String = String(data.get("game_id", ""))
			var players: Array = data.get("players", [])
			var spectator: bool = bool(data.get("spectator", false))
			start_game(game_id, players, spectator)

		"players_list":
			_statuses = data.get("statuses", {}) as Dictionary
			update_players_list(data.get("players", []))

		"games_list":
			update_games_list(data.get("games", []))

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

	_pending_game_action = {
		"game_id": game_id,
		"players": players
	}

	if Global.username in players:
		PopupUi.show_confirm(
			"Rejoindre ta partie en cours ?\n(game_id: %s)\nJoueurs: %s" % [game_id, str(players)],
			"Oui", "Non",
			Callable(self, "_do_rejoin_game"),
			Callable(self, "_cancel_pending_game_action")
		)
	else:
		PopupUi.show_confirm(
			"Regarder cette partie en spectateur ?\n(game_id: %s)\nJoueurs: %s" % [game_id, str(players)],
			"Oui", "Non",
			Callable(self, "_do_spectate_game"),
			Callable(self, "_cancel_pending_game_action")
		)

func _cancel_pending_game_action() -> void:
	_pending_game_action = {}

# --------------------
# ACTIONS
# --------------------
func send_invite(target: String) -> void:
	NetworkManager.request("invite", { "to": target })

func _do_rejoin_game() -> void:
	if _pending_game_action.is_empty():
		return
	var game_id := String(_pending_game_action.get("game_id", ""))
	if game_id == "":
		return

	NetworkManager.request("join_game", { "game_id": game_id })
	_pending_game_action = {}

func _do_spectate_game() -> void:
	if _pending_game_action.is_empty():
		return
	var game_id := String(_pending_game_action.get("game_id", ""))
	if game_id == "":
		return

	NetworkManager.request("spectate_game", { "game_id": game_id })
	_pending_game_action = {}

# --------------------
# Déconnexion (bouton Lobby)
# --------------------
func _on_deconnexion_pressed() -> void:
	PopupUi.show_confirm(
		"Se déconnecter et revenir à l'écran de connexion ?",
		"Oui", "Non",
		Callable(self, "_do_logout")
	)

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
