# Lobby.gd v2.0 — ClientAPI only, NetworkManager supprimé
extends Control

const Protocol = preload("res://net/Protocol.gd")

# ============= FLOW IDs =============
const FLOW_SPECTATE_GAME  := Protocol.REQ_SPECTATE_GAME
const FLOW_LOGOUT         := Protocol.REQ_LOGOUT
const FLOW_INVITE_REQUEST := Protocol.POPUP_FLOW_INVITE_REQUEST

# ============= ACTION ALIASES =============
const ACTION_NETWORK_RETRY := Protocol.ACTION_NETWORK_RETRY

# ============= LEADERBOARD LAYOUT =============
const LEADERBOARD_COL_WIDTH_RANK := 46.0
const LEADERBOARD_COL_WIDTH_NAME := 150.0
const LEADERBOARD_COL_WIDTH_WIN  := 60.0
const LEADERBOARD_COL_WIDTH_LOSE := 60.0
const LEADERBOARD_COL_WIDTH_DRAW := 60.0
const LEADERBOARD_ROW_MIN_WIDTH  := (
  LEADERBOARD_COL_WIDTH_RANK
  + LEADERBOARD_COL_WIDTH_NAME
  + LEADERBOARD_COL_WIDTH_WIN
  + LEADERBOARD_COL_WIDTH_LOSE
  + LEADERBOARD_COL_WIDTH_DRAW
)
const LEADERBOARD_ROW_HEIGHT := 38.0

# ============= LEADERBOARD COLORS =============
const COLOR_HEADER_BG       := Color(0.07, 0.07, 0.11, 1.0)
const COLOR_HEADER_TEXT     := Color(0.60, 0.62, 0.72, 1.0)
const COLOR_HEADER_WIN      := Color(0.30, 0.78, 0.40, 1.0)
const COLOR_HEADER_LOSE     := Color(0.85, 0.32, 0.32, 1.0)
const COLOR_HEADER_DRAW     := Color(0.82, 0.78, 0.28, 1.0)

const COLOR_ROW_ODD         := Color(0.10, 0.10, 0.15, 1.0)
const COLOR_ROW_EVEN        := Color(0.14, 0.14, 0.20, 1.0)
const COLOR_ROW_SELF        := Color(0.14, 0.26, 0.42, 1.0)
const COLOR_ROW_BORDER_SELF := Color(0.30, 0.55, 0.90, 1.0)

const COLOR_TEXT_DEFAULT    := Color(0.88, 0.88, 0.90, 1.0)
const COLOR_TEXT_SELF       := Color(0.85, 0.93, 1.00, 1.0)
const COLOR_RANK_GOLD       := Color(1.00, 0.84, 0.00, 1.0)
const COLOR_RANK_SILVER     := Color(0.78, 0.78, 0.82, 1.0)
const COLOR_RANK_BRONZE     := Color(0.82, 0.52, 0.22, 1.0)

const COLOR_STAT_WIN        := Color(0.35, 0.88, 0.45, 1.0)
const COLOR_STAT_LOSE       := Color(0.92, 0.38, 0.38, 1.0)
const COLOR_STAT_DRAW       := Color(0.88, 0.82, 0.32, 1.0)

# ============= STATE =============
var _is_changing_scene     := false
var _statuses:              Dictionary = {}
var _network_disconnected  := false
var _search_query:          String = ""
var _leader_search_query:   String = ""
var _all_players:           Array = []
var _all_games:             Array = []
var _all_leaderboard:       Array = []

@onready var _tab_container:        TabContainer = $TabContainer
@onready var _search_player_input:  LineEdit     = $TabContainer/LobbyTab/SearchPlayer
@onready var _search_leader_input:  LineEdit     = $TabContainer/LeaderboardTab/SearchLeader
@onready var _logout_button:        Button       = $Deconnexion
@onready var _leader_header_rank:   Label = $TabContainer/LeaderboardTab/LeaderBox/LeaderHeader/HeaderRank
@onready var _leader_header_name:   Label = $TabContainer/LeaderboardTab/LeaderBox/LeaderHeader/HeaderName
@onready var _leader_header_win:    Label = $TabContainer/LeaderboardTab/LeaderBox/LeaderHeader/HeaderWin
@onready var _leader_header_lose:   Label = $TabContainer/LeaderboardTab/LeaderBox/LeaderHeader/HeaderLose
@onready var _leader_header_draw:   Label = $TabContainer/LeaderboardTab/LeaderBox/LeaderHeader/HeaderDraw

# ============= LIFECYCLE =============

func _ready() -> void:
  $TabContainer/LobbyTab/PlayerNameLabel.text = String(Global.username)

  # --- Réponses ---
  _safe_connect(ClientAPI.players_list_ok,     self, "_on_players_list_ok")
  _safe_connect(ClientAPI.players_list_failed, self, "_on_players_list_failed")
  _safe_connect(ClientAPI.leaderboard_ok,      self, "_on_leaderboard_ok")
  _safe_connect(ClientAPI.leaderboard_failed,  self, "_on_leaderboard_failed")
  _safe_connect(ClientAPI.invite_sent,         self, "_on_invite_sent")
  _safe_connect(ClientAPI.invite_send_failed,  self, "_on_invite_send_failed")
  _safe_connect(ClientAPI.spectate_failed,     self, "_on_spectate_failed")
  _safe_connect(ClientAPI.join_game_failed,    self, "_on_join_game_failed")

  # --- Événements push serveur ---
  _safe_connect(ClientAPI.evt_start_game,      self, "_on_evt_start_game")
  _safe_connect(ClientAPI.evt_players_updated, self, "_on_evt_players_updated")
  _safe_connect(ClientAPI.evt_games_updated,   self, "_on_evt_games_updated")
  _safe_connect(ClientAPI.evt_invite_received, self, "_on_evt_invite_received")
  _safe_connect(ClientAPI.evt_invite_response, self, "_on_evt_invite_response")
  _safe_connect(ClientAPI.evt_invite_cancelled,self, "_on_evt_invite_cancelled")

  # --- Connexion ---
  _safe_connect(ClientAPI.connection_lost,     self, "_on_connection_lost")
  _safe_connect(ClientAPI.connection_restored, self, "_on_connection_restored")
  _safe_connect(ClientAPI.reconnect_failed,    self, "_on_reconnect_failed")
  _safe_connect(ClientAPI.server_closed,       self, "_on_server_closed")

  # --- Popup ---
  if not PopupUi.action_selected.is_connected(_on_popup_action):
    PopupUi.action_selected.connect(_on_popup_action)

  # --- Langue ---
  if not LanguageManager.language_changed.is_connected(_on_language_changed):
    LanguageManager.language_changed.connect(_on_language_changed)

  PopupUi.hide_and_reset()
  _apply_language_to_lobby_ui()
  _style_leaderboard_header()

  ClientAPI.get_players()

# ============= RÉPONSES (ClientAPI signals) =============

func _on_players_list_ok(players: Array, statuses: Dictionary, games: Array) -> void:
  _all_players = players
  _all_games   = games
  _statuses    = statuses
  _refresh_lobby_view()

func _on_players_list_failed(error: Dictionary) -> void:
  PopupRouter.show_error(error, Protocol.POPUP_LOBBY_GET_PLAYERS_ERROR)

func _on_leaderboard_ok(rows: Array) -> void:
  _all_leaderboard = rows
  _refresh_leaderboard_view()

func _on_leaderboard_failed(error: Dictionary) -> void:
  PopupRouter.show_error(error, Protocol.POPUP_UI_ACTION_IMPOSSIBLE)

func _on_invite_sent() -> void:
  PopupRouter.show_info(Protocol.POPUP_INVITE_SENT)

func _on_invite_send_failed(error: Dictionary) -> void:
  PopupRouter.show_error(error, Protocol.POPUP_INVITE_FAILED)

func _on_spectate_failed(error: Dictionary) -> void:
  PopupRouter.show_error(error, Protocol.POPUP_UI_ACTION_IMPOSSIBLE)

func _on_join_game_failed(error: Dictionary) -> void:
  PopupRouter.show_error(error, Protocol.POPUP_UI_ACTION_IMPOSSIBLE)

# ============= ÉVÉNEMENTS PUSH SERVEUR =============

func _on_evt_start_game(game_id: String, players: Array, spectator: bool) -> void:
  PopupUi.hide_and_reset()
  start_game(game_id, players, spectator)

func _on_evt_players_updated(players: Array, statuses: Dictionary) -> void:
  _all_players = players
  _statuses    = statuses
  _refresh_players_view()

func _on_evt_games_updated(games: Array) -> void:
  _all_games = games
  _refresh_games_view()

func _on_evt_invite_received(from_user: String, ctx: String, source_game_id: String) -> void:
  if from_user == "":
    return
  PopupRouter.show_invite_received(from_user, ctx, source_game_id)

func _on_evt_invite_response(data: Dictionary) -> void:
  PopupRouter.show_invite_response(data)

func _on_evt_invite_cancelled(data: Dictionary) -> void:
  PopupRouter.show_invite_cancelled(data)

# ============= CONNEXION =============

func _on_connection_lost() -> void:
  _network_disconnected = true
  PopupRouter.show_connection_lost()

func _on_connection_restored() -> void:
  if not _network_disconnected:
    return
  _network_disconnected = false
  PopupRouter.show_reconnected()

func _on_reconnect_failed() -> void:
  if not _network_disconnected:
    return
  PopupRouter.show_reconnect_failed()

func _on_server_closed(_reason: String, _code: int) -> void:
  _network_disconnected = false
  PopupRouter.show_info(Protocol.POPUP_TECH_INTERNAL_ERROR)

# ============= UI / LOGIQUE =============

func start_game(game_id: String, players: Array, spectator: bool) -> void:
  GameSession.start_game(game_id, players, spectator)
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

func _apply_language_to_lobby_ui() -> void:
  _logout_button.text = LanguageManager.ui_text("UI_LOBBY_LOGOUT_BUTTON", "Logout")
  _search_player_input.placeholder_text = LanguageManager.ui_text("UI_LOBBY_SEARCH_PLAYER_PLACEHOLDER", "Search player")
  _search_leader_input.placeholder_text = LanguageManager.ui_text("UI_LOBBY_SEARCH_LEADER_PLACEHOLDER", "Search leaderboard")

  if _tab_container.get_tab_count() > 0:
    _tab_container.set_tab_title(0, LanguageManager.ui_text("UI_LOBBY_TAB_LOBBY", "Lobby"))
  if _tab_container.get_tab_count() > 1:
    _tab_container.set_tab_title(1, LanguageManager.ui_text("UI_LOBBY_TAB_LEADERBOARD", "Leaderboard"))
  if _tab_container.get_tab_count() > 2:
    _tab_container.set_tab_title(2, LanguageManager.ui_text("UI_LOBBY_TAB_SHOP", "Shop"))
  _apply_leaderboard_header_language()

func _apply_leaderboard_header_language() -> void:
  _leader_header_rank.text = LanguageManager.ui_text("UI_LOBBY_LEADERBOARD_HEADER_RANK", "#")
  _leader_header_name.text = LanguageManager.ui_text("UI_LOBBY_LEADERBOARD_HEADER_NAME", "Name")
  _leader_header_win.text  = LanguageManager.ui_text("UI_LOBBY_LEADERBOARD_HEADER_WIN",  "Win")
  _leader_header_lose.text = LanguageManager.ui_text("UI_LOBBY_LEADERBOARD_HEADER_LOSE", "Lose")
  _leader_header_draw.text = LanguageManager.ui_text("UI_LOBBY_LEADERBOARD_HEADER_DRAW", "Draw")

func _style_leaderboard_header() -> void:
  var header: HBoxContainer = $TabContainer/LeaderboardTab/LeaderBox/LeaderHeader
  var bg := ColorRect.new()
  bg.color = COLOR_HEADER_BG
  bg.show_behind_parent = true
  bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
  bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
  header.add_child(bg)
  header.move_child(bg, 0)
  _style_header_label(_leader_header_rank, COLOR_HEADER_TEXT, HORIZONTAL_ALIGNMENT_CENTER, true)
  _style_header_label(_leader_header_name, COLOR_HEADER_TEXT, HORIZONTAL_ALIGNMENT_LEFT,   true)
  _style_header_label(_leader_header_win,  COLOR_HEADER_WIN,  HORIZONTAL_ALIGNMENT_RIGHT,  true)
  _style_header_label(_leader_header_lose, COLOR_HEADER_LOSE, HORIZONTAL_ALIGNMENT_RIGHT,  true)
  _style_header_label(_leader_header_draw, COLOR_HEADER_DRAW, HORIZONTAL_ALIGNMENT_RIGHT,  true)

func _style_header_label(lbl: Label, color: Color, align: HorizontalAlignment, uppercase: bool) -> void:
  lbl.horizontal_alignment = align
  lbl.add_theme_color_override("font_color", color)
  lbl.add_theme_font_size_override("font_size", 13)
  if uppercase:
    lbl.text = lbl.text.to_upper()

func _on_language_changed(_language_code: String) -> void:
  _apply_language_to_lobby_ui()

func update_players_list(players: Array) -> void:
  var list: Node = $TabContainer/LobbyTab/PlayersBox/PlayersList/PlayersItems
  for child in list.get_children():
    child.queue_free()

  for p in players:
    var ps: String = String(p)
    if ps == Global.username:
      continue
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
  for game in games:
    if not _game_matches_search(game):
      continue
    list.add_child(create_game_box(game))

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

func _leader_matches_search(username: String) -> bool:
  if _leader_search_query == "":
    return true
  return String(username).to_lower().contains(_leader_search_query)

func create_game_box(game: Variant) -> Button:
  var g: Dictionary = game if game is Dictionary else {}
  var game_id := String(g.get("game_id", ""))
  var players_val = g.get("players", [])
  var players: Array = players_val if players_val is Array else []
  var btn := Button.new()
  btn.text = str(players)
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
  btn.pressed.connect(func() -> void:
    send_invite(username)
  )
  return btn

func update_leaderboard_list(rows: Array) -> void:
  var list: Node = $TabContainer/LeaderboardTab/LeaderBox/LeaderList/LeaderItems
  for child in list.get_children():
    child.queue_free()
  var display_index := 0
  for row_data in rows:
    if not (row_data is Dictionary):
      continue
    var entry := row_data as Dictionary
    var username := String(entry.get("username", "")).strip_edges()
    if not _leader_matches_search(username):
      continue
    var rank_display := _coerce_non_negative_int(entry.get("rank", 0))
    display_index += 1
    list.add_child(create_leaderboard_row(entry, rank_display, display_index))

func create_leaderboard_row(entry: Dictionary, rank_display: int, row_index: int) -> PanelContainer:
  var username := String(entry.get("username", "")).strip_edges()
  var wins     := _coerce_non_negative_int(entry.get("wins",   0))
  var losses   := _coerce_non_negative_int(entry.get("losses", 0))
  var draws    := _coerce_non_negative_int(entry.get("draws",  0))
  if username == "":
    username = "-"
  var is_self: Variant = username == Global.username

  var panel := PanelContainer.new()
  panel.custom_minimum_size = Vector2(LEADERBOARD_ROW_MIN_WIDTH, LEADERBOARD_ROW_HEIGHT)
  panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

  var style := StyleBoxFlat.new()
  style.content_margin_left   = 6.0
  style.content_margin_right  = 6.0
  style.content_margin_top    = 2.0
  style.content_margin_bottom = 2.0
  if is_self:
    style.bg_color = COLOR_ROW_SELF
    style.border_width_left = 3
    style.border_color = COLOR_ROW_BORDER_SELF
  elif row_index % 2 == 0:
    style.bg_color = COLOR_ROW_EVEN
  else:
    style.bg_color = COLOR_ROW_ODD
  panel.add_theme_stylebox_override("panel", style)

  var row := HBoxContainer.new()
  row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  panel.add_child(row)

  var rank_color := COLOR_TEXT_DEFAULT
  var rank_bold  := false
  match rank_display:
    1: rank_color = COLOR_RANK_GOLD;   rank_bold = true
    2: rank_color = COLOR_RANK_SILVER; rank_bold = true
    3: rank_color = COLOR_RANK_BRONZE; rank_bold = true

  var rank_text := str(rank_display)
  if rank_display == 1:
    rank_text = "1 ★"

  var name_color := COLOR_TEXT_SELF if is_self else COLOR_TEXT_DEFAULT
  row.add_child(_create_leaderboard_label(rank_text, LEADERBOARD_COL_WIDTH_RANK, HORIZONTAL_ALIGNMENT_CENTER, rank_color, rank_bold))
  row.add_child(_create_leaderboard_label(username,  LEADERBOARD_COL_WIDTH_NAME, HORIZONTAL_ALIGNMENT_LEFT,   name_color, is_self))
  row.add_child(_create_leaderboard_label(str(wins),   LEADERBOARD_COL_WIDTH_WIN,  HORIZONTAL_ALIGNMENT_RIGHT, COLOR_STAT_WIN))
  row.add_child(_create_leaderboard_label(str(losses), LEADERBOARD_COL_WIDTH_LOSE, HORIZONTAL_ALIGNMENT_RIGHT, COLOR_STAT_LOSE))
  row.add_child(_create_leaderboard_label(str(draws),  LEADERBOARD_COL_WIDTH_DRAW, HORIZONTAL_ALIGNMENT_RIGHT, COLOR_STAT_DRAW))
  return panel

func _create_leaderboard_label(value: String, min_width: float, align: HorizontalAlignment, color: Color = COLOR_TEXT_DEFAULT, bold: bool = false) -> Label:
  var label := Label.new()
  label.text = value
  label.custom_minimum_size = Vector2(min_width, 0)
  label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  label.horizontal_alignment = align
  label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
  label.add_theme_color_override("font_color", color)
  if bold:
    label.add_theme_font_size_override("font_size", 14)
  return label

func _on_game_clicked(game_id: String, players: Array) -> void:
  if game_id == "":
    return
  PopupRouter.show_spectate_confirm(game_id, players)

# ============= ACTIONS =============

func send_invite(target: String) -> void:
  ClientAPI.send_invite(target)

func _do_spectate_game(game_id: String) -> void:
  if game_id == "":
    return
  ClientAPI.spectate_game(game_id)

func _request_leaderboard() -> void:
  ClientAPI.get_leaderboard()

# ============= DÉCONNEXION =============

func _on_deconnexion_pressed() -> void:
  PopupRouter.show_logout_confirm()

func _on_popup_action(action_id: String, payload: Dictionary) -> void:
  if action_id == ACTION_NETWORK_RETRY:
    ClientAPI.retry_connection()
    return

  var invite_req := MessageCatalog.invite_action_request(action_id, payload)
  if not invite_req.is_empty():
    ClientAPI.respond_to_invite(
      String(invite_req.get("to", "")),
      bool(invite_req.get("accepted", false)),
      String(invite_req.get("context", "")),
      String(invite_req.get("source_game_id", ""))
    )
    return

  var flow := String(payload.get("flow", ""))
  match flow:
    FLOW_SPECTATE_GAME:
      if action_id == Protocol.POPUP_ACTION_CONFIRM_YES:
        _do_spectate_game(String(payload.get("game_id", "")))
    FLOW_LOGOUT:
      if action_id == Protocol.POPUP_ACTION_CONFIRM_YES:
        await _do_logout()

func _do_logout() -> void:
  await ClientAPI.logout()
  Global.username = ""
  GameSession.reset_game_state()
  SceneManager.go_to_login()

# ============= UTILITAIRES =============

func _safe_connect(sig: Signal, target: Object, method: String) -> void:
  var c := Callable(target, method)
  if not sig.is_connected(c):
    sig.connect(c)

func _coerce_non_negative_int(value: Variant) -> int:
  return maxi(int(value), 0)

func _deferred_change_to_game() -> void:
  if not is_inside_tree():
    return
  SceneManager.go_to_game()

# ============= CLEANUP =============

func _exit_tree() -> void:
  var signals_to_disconnect: Array = [
    [ClientAPI.players_list_ok,      "_on_players_list_ok"],
    [ClientAPI.players_list_failed,  "_on_players_list_failed"],
    [ClientAPI.leaderboard_ok,       "_on_leaderboard_ok"],
    [ClientAPI.leaderboard_failed,   "_on_leaderboard_failed"],
    [ClientAPI.invite_sent,          "_on_invite_sent"],
    [ClientAPI.invite_send_failed,   "_on_invite_send_failed"],
    [ClientAPI.spectate_failed,      "_on_spectate_failed"],
    [ClientAPI.join_game_failed,     "_on_join_game_failed"],
    [ClientAPI.evt_start_game,       "_on_evt_start_game"],
    [ClientAPI.evt_players_updated,  "_on_evt_players_updated"],
    [ClientAPI.evt_games_updated,    "_on_evt_games_updated"],
    [ClientAPI.evt_invite_received,  "_on_evt_invite_received"],
    [ClientAPI.evt_invite_response,  "_on_evt_invite_response"],
    [ClientAPI.evt_invite_cancelled, "_on_evt_invite_cancelled"],
    [ClientAPI.connection_lost,      "_on_connection_lost"],
    [ClientAPI.connection_restored,  "_on_connection_restored"],
    [ClientAPI.reconnect_failed,     "_on_reconnect_failed"],
    [ClientAPI.server_closed,        "_on_server_closed"],
  ]
  for pair in signals_to_disconnect:
    var c := Callable(self, pair[1])
    if (pair[0] as Signal).is_connected(c):
      (pair[0] as Signal).disconnect(c)

  if PopupUi.action_selected.is_connected(_on_popup_action):
    PopupUi.action_selected.disconnect(_on_popup_action)
  if LanguageManager.language_changed.is_connected(_on_language_changed):
    LanguageManager.language_changed.disconnect(_on_language_changed)

# ============= TABS =============

func _on_tab_container_tab_changed(tab: int) -> void:
  if tab == 1:
    _request_leaderboard()

func _on_search_leader_text_changed(new_text: String) -> void:
  _leader_search_query = String(new_text).strip_edges().to_lower()
  _refresh_leaderboard_view()
