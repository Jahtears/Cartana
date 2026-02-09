# Game.gd V1.2
extends Control 

var slot_scene: PackedScene = preload("res://Client/Scenes/Slot.tscn")
var card_scene: PackedScene = preload("res://Client/Scenes/Carte.tscn")
const Protocol = preload("res://Client/net/Protocol.gd")
const SlotIdHelper = preload("res://Client/game/helpers/slot_id.gd")
const TableSyncHelper = preload("res://Client/game/helpers/table_sync.gd")
const CardSyncHelper = preload("res://Client/game/helpers/card_sync.gd")
const TimebarUtil = preload("res://Client/game/helpers/timebar.gd")

const MAIN_COUNT := 1
const BANC_COUNT := 4
const MIN_SLOT_SPACING := 64.0
const MAX_SLOT_SPACING := 120.0
const SLOT_WIDTH := 80.0
const SIDE_MARGIN := 100.0
const PLAYER_TOP_Y_RATIO := 0.18
const PLAYER_BOTTOM_Y_RATIO := 0.82
const TABLE_Y_RATIO := 0.5
const PIOCHE_RIGHT_MARGIN := 80.0
const START_POS := Vector2.ZERO

static var TIMEBAR_GREEN: Color = Color.from_hsv(0.333, 0.85, 0.95, 1.0)
static var TIMEBAR_YELLOW: Color = Color.from_hsv(0.166, 0.85, 0.95, 1.0)
static var TIMEBAR_ORANGE: Color = Color.from_hsv(0.083, 0.85, 0.95, 1.0)
static var TIMEBAR_RED: Color   = Color.from_hsv(0.000, 0.85, 0.95, 1.0)

const TIMEBAR_SPEC := Color(0.85, 0.85, 0.85)

var slots_ready: bool = false
var slots_by_id: Dictionary = {}                    # slot_id -> Node
var pending_events: Array[Dictionary] = []          # events arrivés avant slots_ready
var cards: Dictionary = {}                          # card_id -> Node
var _is_changing_scene := false
var opponent_name: String = ""
var allowed_table_slots: Dictionary = {}            # IDs table autorisés (format 0:TABLE:index)
var _slot_spacing: float = 100.0
var _table_spacing: int = 100

@onready var time_bar: ProgressBar = $TimeBar
@onready var player1_root: Node2D = $Player1
@onready var player2_root: Node2D = $Player2
@onready var player1_deck: Node2D = $Player1/Deck
@onready var player1_main: Node2D = $Player1/Main
@onready var player1_banc: Node2D = $Player1/Banc
@onready var player2_deck: Node2D = $Player2/Deck
@onready var player2_main: Node2D = $Player2/Main
@onready var player2_banc: Node2D = $Player2/Banc
@onready var pioche_root: Node2D = $Pioche
@onready var table_root: Node2D = $Table

var _card_ctx: Dictionary = {}
var _timebar_state: Dictionary = {
	"turn_current": "",
	"turn_ends_at_ms": 0,
	"turn_duration_ms": 0,
	"timebar_mode": -1,
	"timebar_fill_sb": null,
	"timebar_last_color": Color(-1, -1, -1, -1),
}
var _timebar_colors: Dictionary = {
	"green": TIMEBAR_GREEN,
	"yellow": TIMEBAR_YELLOW,
	"orange": TIMEBAR_ORANGE,
	"red": TIMEBAR_RED,
	"spec": TIMEBAR_SPEC,
}

func _ready() -> void:
	_connect_layout_signals()
	_relayout_board()
	_setup_player($Player1, 1)
	_setup_player($Player2, 2)
	_setup_Pioche($Pioche)
	_card_ctx = {
		"cards": cards,
		"card_scene": card_scene,
		"slots_by_id": slots_by_id,
		"root": self,
	}

	if not NetworkManager.evt.is_connected(_on_evt):
		NetworkManager.evt.connect(_on_evt)
	if not NetworkManager.response.is_connected(_on_response):
		NetworkManager.response.connect(_on_response)

	# ready dès que la scène Game est chargée
	# - joueur: {} suffit
	# - spectateur: {"game_id": ...}
	if String(Global.current_game_id) != "":
		if bool(Global.is_spectator):
			NetworkManager.request("ready_for_game", {"game_id": String(Global.current_game_id)})
		else:
			NetworkManager.request("ready_for_game", {})

	await get_tree().process_frame
	slots_ready = true
	TimebarUtil.update_timebar(_timebar_state, time_bar, Callable(NetworkManager, "server_now_ms"), _timebar_colors)
	# Rejoue les events reçus avant que les slots soient prêts
	for ev in pending_events:
		_on_evt(String(ev.get("type", "")), ev.get("data", {}) as Dictionary)
	pending_events.clear()

# ---------------------------------------------------------
#  EVT (push serveur)
# ---------------------------------------------------------
func _on_evt(type: String, data: Dictionary) -> void:
	print("[EVT]", type, data)

	match type:
		"start_game":
			# 1) Maj globals
			Global.current_game_id = String(data.get("game_id", ""))
			Global.players_in_game = data.get("players", [])
			Global.is_spectator = bool(data.get("spectator", false))

			# ended reset (important)
			Global.result.clear()
			
			# 2) Maj opponent_name
			opponent_name = ""
			for p in Global.players_in_game:
				var ps := String(p)
				if ps != Global.username:
					opponent_name = ps

			# 3) Reset état local si on était déjà en Game
			_reset_board_state()
			slots_ready = true
			pending_events.clear()
			_is_changing_scene = false

			# 4) Ready même sans reload de scène
			if Global.current_game_id != "":
				if Global.is_spectator:
					NetworkManager.request("ready_for_game", {"game_id": Global.current_game_id})
				else:
					NetworkManager.request("ready_for_game", {})

		"table_sync":
			if slots_ready:
				TableSyncHelper.sync_table_slots(table_root, slot_scene, slots_by_id, allowed_table_slots, data.get("slots", []), _table_spacing, START_POS)
			else:
				pending_events.append({"type": type, "data": data})

		"slot_state":
			if slots_ready:
				_on_slot_state(data)
			else:
				pending_events.append({"type": type, "data": data})

		"state_snapshot":
			if slots_ready:
				_apply_state_snapshot(data)
			else:
				pending_events.append({"type": type, "data": data})
		"show_game_message":
			_show_message(data)
		"game_end":
			Global.result = data.duplicate()
		"turn_update":
			# data: { current, turnNumber, endsAt, durationMs, endedBy? }
			_set_turn_timer(data)

# ---------------------------------------------------------
#  RES (réponses à des requêtes)
# ---------------------------------------------------------

func _on_response(_rid: String, type: String, ok: bool, _data: Dictionary, error: Dictionary) -> void:
	if type != "move_request":
		return

	# ✅ NOUVEAU: Reset move pending flag
	var card_id = _data.get("card_id", "")
	if card_id != "":
		var card = cards.get(card_id)
		if card and card.has_method("_reset_move_pending"):
			card._reset_move_pending()

	if ok:
		_show_message({
			"reason": "Valider",
			"color": Protocol.MESSAGE_COLORS[Protocol.GAME_MESSAGE["MOVE_OK"]]
		})
	else:
		_show_message({
			"reason": String(error.get("message", "")),
			"color": Protocol.MESSAGE_COLORS[Protocol.GAME_MESSAGE["MOVE_DENIED"]]
		})

		var details := error.get("details", {}) as Dictionary
		if details.has("card_id") and details.has("from_slot_id"):
			_on_invalid_move({
				"card_id": String(details.get("card_id", "")),
				"from_slot_id": String(details.get("from_slot_id", ""))
			})

# Ajouter cette méthode à Carte.gd pour être appelée depuis Game.gd

# ---------------------------------------------------------
#  SNAPSHOT (full resync)
# ---------------------------------------------------------
func _apply_state_snapshot(data: Dictionary) -> void:
	for s in slots_by_id.values():
		if s and s.has_method("clear_slot"):
			s.clear_slot()

	TableSyncHelper.sync_table_slots(table_root, slot_scene, slots_by_id, allowed_table_slots, data.get("table", []), _table_spacing, START_POS)

	var slots_dict: Dictionary = data.get("slots", {})
	for k in slots_dict.keys():
		var slot_id := SlotIdHelper.normalize_slot_id(String(k))
		var slot := _find_slot_by_id(slot_id)

		if slot == null and SlotIdHelper.is_table_slot_id(slot_id):
			slot = _find_slot_by_id(slot_id)

		var arr: Array = slots_dict.get(k, [])
		for payload in arr:
			if payload is Dictionary:
				CardSyncHelper.apply_card_update(_card_ctx, payload)

	# ✅ TURN timer depuis snapshot (hors boucle)
	var turn_val = data.get("turn", null)
	if turn_val is Dictionary:
		_set_turn_timer(turn_val as Dictionary)
	else:
		_set_turn_timer({})

	# ✅ result via snapshot
	var result_val = data.get("result", null)
	if result_val is Dictionary and (result_val as Dictionary).size() > 0:
		var e := result_val as Dictionary
		var merged := {"game_id": String(Global.current_game_id)}
		for kk in e.keys():
			merged[kk] = e[kk]
		_on_game_end(merged)

# ---------------------------------------------------------
#  GAME END (unifié + ack_game_end)
# ---------------------------------------------------------
func _on_game_end(data: Dictionary) -> void:
	if _is_changing_scene:
		return
	_is_changing_scene = true
	Global.ended = data.duplicate()
	var winner := String(data.get("winner", ""))
	var reason := String(data.get("reason", ""))

	var msg := "Partie terminée.\n"
	if winner != "":
		if Global.is_spectator:
			msg += "Winner: %s\n" % winner
		else:
			msg += ("Vous avez gagné.\n" if winner == Global.username else "Vous avez perdu.\n")
	if reason != "":
		msg += "Reason: %s\n" % reason
	msg += "Retour au lobby."

	if typeof(PopupUi) != TYPE_NIL and PopupUi != null and PopupUi.has_method("show_confirm"):
		PopupUi.show_confirm(
			msg,
			"Retour lobby", "Rester",
			Callable(self, "_ack_end_and_go_lobby"),
			Callable()
		)
	else:
		await get_tree().create_timer(0.6).timeout
		await _ack_end_and_go_lobby()

func _ack_end_and_go_lobby() -> void:
	var gid := String(Global.current_game_id)
	if gid != "":
		await NetworkManager.request_async("ack_game_end", {"game_id": gid}, 6.0)

	Global.current_game_id = ""
	Global.players_in_game = []
	Global.is_spectator = false
	Global.result = {}

	get_tree().change_scene_to_file("res://Client/Scenes/Lobby.tscn")

# ---------------------------------------------------------
#  SLOT_STATE (diff granulaire)
# ---------------------------------------------------------
func _on_slot_state(data: Dictionary) -> void:
	var slot_id := SlotIdHelper.normalize_slot_id(String(data.get("slot_id", "")))
	if slot_id == "":
		return

	var slot := _find_slot_by_id(slot_id)

	if slot == null and SlotIdHelper.is_table_slot_id(slot_id):
		if not allowed_table_slots.has(slot_id):
			return
		slot = _find_slot_by_id(slot_id)

	if slot and slot.has_method("clear_slot"):
		slot.clear_slot()

	var arr: Array = data.get("cards", [])
	for payload in arr:
		if payload is Dictionary:
			CardSyncHelper.apply_card_update(_card_ctx, payload)

# ---------------------------------------------------------
#  INVALID MOVE (snap-back)
# ---------------------------------------------------------
func _on_invalid_move(data: Dictionary) -> void:
	print("INVALID MOVE:", data)
	var card_id: String = String(data.get("card_id", ""))
	var from_slot_id: String = SlotIdHelper.normalize_slot_id(String(data.get("from_slot_id", "")))
	if card_id == "" or from_slot_id == "":
		return

	var card = CardSyncHelper.get_or_create_card(_card_ctx, card_id)
	var slot = _find_slot_by_id(from_slot_id)
	if slot:
		slot.snap_card(card, true)
		card.set_meta("last_slot_id", from_slot_id)

# ---------------------------------------------------------
#  RESET LOCAL
# ---------------------------------------------------------
func _reset_board_state() -> void:
	for s in slots_by_id.values():
		if s and s.has_method("clear_slot"):
			s.clear_slot()

	TableSyncHelper.sync_table_slots(table_root, slot_scene, slots_by_id, allowed_table_slots, ["0:TABLE:1"], _table_spacing, START_POS)

	for k in cards.keys():
		var c = cards[k]
		if is_instance_valid(c):
			c.queue_free()
	cards.clear()

	pending_events.clear()
	slots_ready = true
	allowed_table_slots.clear()

# ---------------------------------------------------------
#  SETUP SLOTS (fixes)
# ---------------------------------------------------------
func _setup_player(player: Node, id: int) -> void:
	var deck = player.get_node("Deck")
	var main = player.get_node("Main")
	var banc = player.get_node("Banc")
	_create_slot(deck, "%d:DECK:1" % id, START_POS)
	for i in range(MAIN_COUNT):
		_create_slot(main, "%d:HAND:%d" % [id, i + 1], START_POS + Vector2(i * _slot_spacing, 0))
	for i in range(BANC_COUNT):
		_create_slot(banc, "%d:BENCH:%d" % [id, i + 1], START_POS + Vector2(i * _slot_spacing, 0))

func _setup_Pioche(pioche: Node) -> void:
	_create_slot(pioche, "0:PILE:1", START_POS)

func _slot_node_name(slot_id: String) -> String:
	return SlotIdHelper.slot_node_name(slot_id)

func _find_child_slot_by_id(parent: Node, slot_id: String) -> Node:
	for child in parent.get_children():
		if child != null and child.has_method("get_slot_id"):
			var cid := String(child.call("get_slot_id"))
			if cid == slot_id:
				return child
	return null

func _create_slot(parent: Node, slot_name: String, pos: Vector2) -> void:
	var existing := _find_child_slot_by_id(parent, slot_name)
	if existing != null:
		existing.name = _slot_node_name(slot_name)
		existing.slot_id = slot_name
		slots_by_id[slot_name] = existing
		return

	var node_name := _slot_node_name(slot_name)
	if parent.has_node(node_name):
		var existing2 := parent.get_node(node_name)
		existing2.slot_id = slot_name
		slots_by_id[slot_name] = existing2
		return
	var slot := slot_scene.instantiate()
	slot.name = _slot_node_name(slot_name)
	slot.slot_id = slot_name
	slot.position = pos
	parent.add_child(slot)
	slots_by_id[slot_name] = slot

# ---------------------------------------------------------
#  CARD UPDATE (payload)
# ---------------------------------------------------------
func _find_slot_by_id(slot_id: String) -> Node:
	return slots_by_id.get(slot_id, null)

func _connect_layout_signals() -> void:
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_on_viewport_size_changed):
		vp.size_changed.connect(_on_viewport_size_changed)

func _on_viewport_size_changed() -> void:
	_relayout_board()

func _relayout_board() -> void:
	var view_size := get_viewport_rect().size
	if view_size == Vector2.ZERO:
		return

	var vw := view_size.x
	var vh := view_size.y
	_slot_spacing = clampf(vw * 0.085, MIN_SLOT_SPACING, MAX_SLOT_SPACING)
	var edge_left_center := SIDE_MARGIN + SLOT_WIDTH * 0.5
	var edge_right_center := vw - SIDE_MARGIN - SLOT_WIDTH * 0.5
	var bench_steps: int = maxi(BANC_COUNT - 1, 1)
	var center_keepout := SLOT_WIDTH * 1.2
	var table_center_x: float = vw * 0.5
	var max_spacing_from_edges: float = (edge_right_center - (table_center_x + center_keepout)) / float(bench_steps)
	_slot_spacing = minf(_slot_spacing, maxf(56.0, max_spacing_from_edges))
	_table_spacing = int(round(_slot_spacing))

	var bench_span := float(BANC_COUNT - 1) * _slot_spacing
	var p1_deck_center := edge_left_center
	var p1_bench_start := edge_right_center - bench_span
	var p1_main_center: float = (p1_deck_center + table_center_x) * 0.6

	var p2_bench_start := edge_left_center
	var p2_deck_center := edge_right_center
	var p2_main_center: float = (p2_deck_center + table_center_x) * 0.45

	player1_root.position = Vector2(0, clampf(vh * PLAYER_BOTTOM_Y_RATIO, vh * 0.65, vh - 80.0))
	player2_root.position = Vector2(0, clampf(vh * PLAYER_TOP_Y_RATIO, 80.0, vh * 0.35))
	player1_deck.position = Vector2(p1_deck_center, 0)
	player1_main.position = Vector2(p1_main_center, 0)
	player1_banc.position = Vector2(p1_bench_start, 0)

	player2_banc.position = Vector2(p2_bench_start, 0)
	player2_main.position = Vector2(p2_main_center, 0)
	player2_deck.position = Vector2(p2_deck_center, 0)

	table_root.position = Vector2(table_center_x, vh * TABLE_Y_RATIO)
	pioche_root.position = Vector2(maxf(vw - PIOCHE_RIGHT_MARGIN, edge_right_center), vh * TABLE_Y_RATIO)

	_update_slot_rows()
	TableSyncHelper.update_table_positions(table_root, _table_spacing, START_POS)

func _update_slot_rows() -> void:
	_update_row_positions(1, "HAND", MAIN_COUNT)
	_update_row_positions(1, "BENCH", BANC_COUNT)
	_update_row_positions(2, "HAND", MAIN_COUNT)
	_update_row_positions(2, "BENCH", BANC_COUNT)

func _update_row_positions(player_id: int, slot_type: String, count: int) -> void:
	for i in range(count):
		var slot_id := "%d:%s:%d" % [player_id, slot_type, i + 1]
		var slot := _find_slot_by_id(slot_id)
		if slot != null:
			slot.position = START_POS + Vector2(i * _slot_spacing, 0)

# ---------------------------------------------------------
#  UI MESSAGE
# ---------------------------------------------------------
func show_game_message(text: String, color: Color) -> void:
	var label := $VBoxContainer/CenterContainer/GameMessage
	label.bbcode_enabled = true
	label.text = "[center][color=%s]%s[/color][/center]" % [color.to_html(), text]
	label.visible = true
	$VBoxContainer/Timer.start()

func _show_message(data: Dictionary) -> void:
	if data.is_empty():
		return
	var msg := String(data.get("reason", ""))
	if msg == "":
		return

	var c: Color = Color.WHITE
	var color_val = data.get("color", "")
	if color_val is Color:
		c = color_val
	elif color_val is String and String(color_val) != "":
		c = Color.from_string(String(color_val), Color.WHITE)

	show_game_message(msg, c)
func _on_timer_timeout() -> void:
	$VBoxContainer/CenterContainer/GameMessage.visible = false

# ---------------------------------------------------------
#  TimerBar
# ---------------------------------------------------------
func _process(_delta: float) -> void:
	# Affichage uniquement: la source de vérité est le serveur (endsAt + durationMs)
	if time_bar.visible:
		TimebarUtil.update_timebar(_timebar_state, time_bar, Callable(NetworkManager, "server_now_ms"), _timebar_colors)

func _set_turn_timer(turn: Dictionary) -> void:
	TimebarUtil.set_turn_timer(_timebar_state, turn, Callable(NetworkManager, "sync_server_clock"))
	TimebarUtil.update_timebar_mode(_timebar_state, bool(Global.is_spectator), String(Global.username))
	TimebarUtil.update_timebar(_timebar_state, time_bar, Callable(NetworkManager, "server_now_ms"), _timebar_colors)

# ---------------------------------------------------------
#  Quitter (bouton Game)
# ---------------------------------------------------------
func _on_quitter_pressed() -> void:
	if typeof(PopupUi) != TYPE_NIL and PopupUi != null and PopupUi.has_method("confirm_quit_to_lobby"):
		PopupUi.confirm_quit_to_lobby()
	else:
		get_tree().change_scene_to_file("res://Scenes/Lobby.tscn")

func _exit_tree() -> void:
	if String(Global.current_game_id) != "":
		NetworkManager.request("ack_game_end", {"game_id": String(Global.current_game_id)})

	if NetworkManager.evt.is_connected(_on_evt):
		NetworkManager.evt.disconnect(_on_evt)
	if NetworkManager.response.is_connected(_on_response):
		NetworkManager.response.disconnect(_on_response)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if String(Global.current_game_id) != "":
			NetworkManager.request("ack_game_end", {"game_id": String(Global.current_game_id)})
