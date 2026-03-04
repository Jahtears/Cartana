# Lobby.gd v1.0
extends Control

const Protocol = preload("res://Client/net/Protocol.gd")

const REQ_GET_PLAYERS := "get_players"
const REQ_GET_LEADERBOARD := "get_leaderboard"
const REQ_JOIN_GAME := "join_game"
const REQ_INVITE := "invite"
const REQ_INVITE_RESPONSE := "invite_response"
const REQ_SPECTATE_GAME := "spectate_game"
const REQ_LOGOUT := "logout"

const FLOW_SPECTATE_GAME := REQ_SPECTATE_GAME
const FLOW_LOGOUT := REQ_LOGOUT
const FLOW_INVITE_REQUEST := Protocol.POPUP_FLOW_INVITE_REQUEST
const ACTION_NETWORK_RETRY := "network_retry"

var _is_changing_scene := false
var _statuses: Dictionary = {}            # username -> status
var _network_disconnected := false
var _search_query: String = ""
var _all_players: Array = []
var _all_games: Array = []
var _all_leaderboard: Array = []

func _ready() -> void:
	$TabContainer/LobbyTab/PlayerNameLabel.text = String(Global.username)

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
				_all_players = _coerce_array(data.get("players", []))
				_all_games = _coerce_array(data.get("games", []))
				_statuses = _coerce_dictionary(data.get("statuses", {}))
				_refresh_lobby_view()
			else:
				_show_error_popup(error, Protocol.POPUP_LOBBY_GET_PLAYERS_ERROR)

		REQ_GET_LEADERBOARD:
			if ok:
				_all_leaderboard = _coerce_array(data.get("leaderboard", []))
				_refresh_leaderboard_view()
			else:
				_show_error_popup(error, Protocol.POPUP_UI_ACTION_IMPOSSIBLE)
				
		REQ_JOIN_GAME, REQ_SPECTATE_GAME:
			if not ok:
				_show_error_popup(error, Protocol.POPUP_UI_ACTION_IMPOSSIBLE)

		REQ_INVITE:
			if ok:
				PopupUi.show_code(PopupUi.MODE_INFO, Protocol.POPUP_INVITE_SENT)
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
			_all_players = _coerce_array(data.get("players", []))
			_statuses = _coerce_dictionary(data.get("statuses", {}))
			_refresh_players_view()

		"games_list":
			_all_games = _coerce_array(data.get("games", []))
			_refresh_games_view()

		"invite_request":
			var from_user := String(data.get("from", ""))
			if from_user != "":
				var popup_payload := {
					"flow": Protocol.popup_flow("INVITE_REQUEST", FLOW_INVITE_REQUEST),
					"from": from_user
				}
				var context := String(data.get("context", "")).strip_edges()
				var source_game_id := String(data.get("source_game_id", "")).strip_edges()
				if context != "":
					popup_payload["context"] = context
				if source_game_id != "":
					popup_payload["source_game_id"] = source_game_id
				PopupUi.show_code(
					PopupUi.MODE_CONFIRM,
					Protocol.POPUP_INVITE_RECEIVED,
					{"from": from_user},
					popup_payload,
					{"yes_label_key": "accept", "no_label_key": "refuse"}
				)

		REQ_INVITE_RESPONSE:
			var ui := Protocol.normalize_invite_response_ui(data)
			if String(ui.get("text", "")) != "":
				PopupUi.show_normalized(PopupUi.MODE_INFO, ui)

		"invite_cancelled":
			_handle_invite_cancelled(data)

func _show_error_popup(error: Dictionary, fallback_message: String) -> void:
	var popup := Protocol.normalize_popup_error(error, fallback_message)
	PopupUi.show_normalized(PopupUi.MODE_INFO, popup)

func _on_connection_lost() -> void:
	_network_disconnected = true
	PopupUi.show_code(PopupUi.MODE_INFO, Protocol.POPUP_PLAYER_DISCONNECTED)

func _on_connection_restored() -> void:
	if not _network_disconnected:
		return
	_network_disconnected = false
	PopupUi.show_code(PopupUi.MODE_INFO, Protocol.POPUP_PLAYER_RECONNECTED)

func _on_reconnect_failed() -> void:
	if not _network_disconnected:
		return
	PopupUi.show_code(
		PopupUi.MODE_INFO,
		Protocol.POPUP_PLAYER_RECONNECT_FAIL,
		{},
		{"ok_action_id": ACTION_NETWORK_RETRY},
		{"ok_label_key": "retry"}
	)

func _on_server_closed(_server_reason: String, _close_code: int, _raw_reason: String) -> void:
	_network_disconnected = false
	PopupUi.show_code(PopupUi.MODE_INFO, Protocol.POPUP_TECH_INTERNAL_ERROR)

func _handle_invite_cancelled(data: Dictionary) -> void:
	var ui := Protocol.invite_cancelled_ui(data)
	if String(ui.get("text", "")).strip_edges() == "":
		return
	PopupUi.show_normalized(PopupUi.MODE_INFO, ui)

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

func _on_search_player_text_changed(new_text: String) -> void:
	_search_query = String(new_text).strip_edges().to_lower()
	_refresh_lobby_view()

func _refresh_lobby_view() -> void:
	_refresh_games_view()
	_refresh_players_view()

func _refresh_players_view() -> void:
	update_players_list(_all_players)

func _refresh_games_view() -> void:
	update_games_list(_all_games)

func _refresh_leaderboard_view() -> void:
	update_leaderboard_list(_all_leaderboard)

func update_players_list(players: Array) -> void:
	var list: Node = $TabContainer/LobbyTab/PlayersBox/PlayersList/PlayersItems
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

		if not _player_matches_search(ps):
			continue

		list.add_child(create_player_box(ps))

func update_games_list(games: Array) -> void:
	var list: Node = $TabContainer/LobbyTab/GameBox/GameList/GameItems
	for child in list.get_children():
		child.queue_free()

	var filtered_games: Array = []
	for game in games:
		if not _game_matches_search(game):
			continue
		filtered_games.append(game)
		list.add_child(create_game_box(game))
	Global.current_games = filtered_games

func _player_matches_search(username: String) -> bool:
	if _search_query == "":
		return true
	return String(username).to_lower().contains(_search_query)

func _game_matches_search(game: Variant) -> bool:
	if _search_query == "":
		return true

	var g: Dictionary = game if game is Dictionary else {}
	var players_val = g.get("players", [])
	var players: Array = players_val if players_val is Array else []
	for p in players:
		if String(p).to_lower().contains(_search_query):
			return true
	return false

func create_game_box(game: Variant) -> Button:
	var g: Dictionary = game if game is Dictionary else {}
	var game_id := String(g.get("game_id", ""))
	var players_val = g.get("players", [])
	var players: Array = players_val if players_val is Array else []

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
func update_leaderboard_list(rows: Array) -> void:
	var list: Node = $TabContainer/LeaderboardTab/LeaderBox/LeaderList/LeaderItems
	for child in list.get_children():
		child.queue_free()
	
	for row_data in rows:
		if row_data is Dictionary:
			list.add_child(create_leaderboard_row(row_data))

func create_leaderboard_row(entry: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(300, 36)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var username := String(entry.get("username", "")).strip_edges()
	var wins := _coerce_non_negative_int(entry.get("wins", 0))
	var losses := _coerce_non_negative_int(entry.get("losses", 0))
	var draws := _coerce_non_negative_int(entry.get("draws", 0))
	
	if username == "":
		username = "-"
	
	row.add_child(_create_leaderboard_label(username, 170.0, HORIZONTAL_ALIGNMENT_LEFT))
	row.add_child(_create_leaderboard_label(str(wins), 60.0, HORIZONTAL_ALIGNMENT_RIGHT))
	row.add_child(_create_leaderboard_label(str(losses), 60.0, HORIZONTAL_ALIGNMENT_RIGHT))
	row.add_child(_create_leaderboard_label(str(draws), 60.0, HORIZONTAL_ALIGNMENT_RIGHT))
	return row

func _create_leaderboard_label(value: String, min_width: float, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = value
	label.custom_minimum_size = Vector2(min_width, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = align
	return label

func _on_game_clicked(game_id: String, players: Array) -> void:
	if game_id == "":
		return

	PopupUi.show_code(
		PopupUi.MODE_CONFIRM,
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

func _request_leaderboard() -> void:
	NetworkManager.request(REQ_GET_LEADERBOARD, {})

# --------------------
# Déconnexion (bouton Lobby)
# --------------------
func _on_deconnexion_pressed() -> void:
	PopupUi.show_code(
		PopupUi.MODE_CONFIRM,
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
			if action_id == Protocol.popup_action("CONFIRM_YES", Protocol.POPUP_ACTION_CONFIRM_YES):
				_do_spectate_game(String(payload.get("game_id", "")))
		FLOW_LOGOUT:
			if action_id == Protocol.popup_action("CONFIRM_YES", Protocol.POPUP_ACTION_CONFIRM_YES):
				await _do_logout()

func _do_logout() -> void:
	await NetworkManager.request_async(REQ_LOGOUT, {}, 3.0)
	NetworkManager.close(1000, "logout")

	# ✅ reset "session"
	Global.username = ""

	# ✅ reset "game state" (API canonique)
	Global.reset_game_state()

	await _go_to_login_safe()

func _coerce_array(value: Variant) -> Array:
	return value if value is Array else []

func _coerce_dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _coerce_non_negative_int(value: Variant) -> int:
	var n := int(value)
	return maxi(n, 0)

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

func _on_tab_container_tab_changed(tab: int) -> void:
	if tab != 1:
		return
	_request_leaderboard()
