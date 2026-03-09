extends RefCounted
class_name GameLayoutManager

# Main nodes
var root: Node = null
var player1_root: Node2D = null
var player2_root: Node2D = null
var table_root: Node2D = null
var pioche_root: Node2D = null
var quitter_button: Button = null

# UI anchor nodes for player-linked UI
var p1_banc_anchor: Node2D = null
var p1_main_anchor: Node2D = null

# Layout state
var positions_cache: Dictionary = {}
var _slot_spacing: float = 0.0
var _table_spacing: int = 0
var config = null

# UI state references
var _timebar_state: Dictionary = {}
var _game_message_state: Dictionary = {}
var _deck_count_state: Dictionary = {}

func setup(root_control: Node, nodes: Dictionary, ui_states: Dictionary = {}, layout_config = null) -> void:
	root = root_control
	config = layout_config if layout_config != null else GameLayoutConfig
	player1_root = nodes.get("player1_root", null)
	player2_root = nodes.get("player2_root", null)
	table_root = nodes.get("table_root", null)
	pioche_root = nodes.get("pioche_root", null)
	quitter_button = nodes.get("quitter_button", null)
	
	# NEW: UI anchor nodes
	p1_banc_anchor = nodes.get("p1_banc_anchor", null)
	p1_main_anchor = nodes.get("p1_main_anchor", null)
	
	# NEW: Store UI state references
	_timebar_state = ui_states.get("timebar", {})
	_game_message_state = ui_states.get("game_message", {})
	_deck_count_state = ui_states.get("deck_count", {})
	
	_table_spacing = config.TABLE_SPACING

func compute_layout() -> Dictionary:
	if root == null:
		return {}
	var view_size := root.get_viewport().get_visible_rect().size
	var vw: float = view_size.x
	var vh: float = view_size.y
	var slot_spacing: float = float(config.DEFAULT_SLOT_SPACING)

	if config.BANC_COUNT > 1:
		var available_width: float = vw - config.SIDE_MARGIN * 2
		slot_spacing = clampf(
			available_width / float(config.BANC_COUNT + 1),
			float(config.MIN_SLOT_SPACING),
			float(config.MAX_SLOT_SPACING)
		)

	return {
		"vw": vw,
		"vh": vh,
		"center_x": vw * 0.5,
		"left_x": config.SIDE_MARGIN,
		"right_x": vw - config.SIDE_MARGIN,
		"slot_spacing": slot_spacing,
	}

func apply_layout(ctx: Dictionary) -> void:
	positions_cache = ctx
	_slot_spacing = float(ctx.get("slot_spacing", config.DEFAULT_SLOT_SPACING))
	_apply_positions(positions_cache)
	_apply_player_linked_ui_layout()  # NEW

func _apply_positions(positions: Dictionary) -> void:
	if table_root != null:
		var vh = positions.get("vh", 0)
		var center_x = positions.get("center_x", 0)
		var _right_x = positions.get("right_x", 0)
		table_root.position = Vector2(center_x, vh * config.TABLE_Y_RATIO)
	if pioche_root != null:
		var vh2 = positions.get("vh", 0)
		var right_x2 = positions.get("right_x", 0)
		pioche_root.position = Vector2(right_x2, vh2 * config.TABLE_Y_RATIO)
	if quitter_button != null:
		_apply_language_to_button()
		quitter_button.size = Vector2(config.QUITTER_WIDTH, config.QUITTER_HEIGHT)
		var right_x3 = positions.get("right_x", 0)
		quitter_button.position = Vector2(right_x3 - config.QUITTER_OFFSET_X, config.QUITTER_OFFSET_Y)

# === NEW: Language updates ===
func _apply_language_to_button() -> void:
	if quitter_button != null:
		quitter_button.text = LanguageManager.ui_text("UI_GAME_QUIT_BUTTON", "Quit")

func apply_language() -> void:
	"""Apply language updates to UI"""
	_apply_language_to_button()

func apply_ui_layout() -> void:
	"""Apply layout for all player-linked UI elements (public interface)"""
	_apply_player_linked_ui_layout()

# === NEW: Player-linked UI positioning ===
func _apply_timebar_layout() -> void:
	print("[GameLayoutManager._apply_timebar_layout] p1_banc_anchor = ", p1_banc_anchor, " _timebar_state.size() = ", _timebar_state.size())
	if p1_banc_anchor != null and _timebar_state.size() > 0:
		print("[GameLayoutManager._apply_timebar_layout] Calling TimebarUtil.apply_layout")
		TimebarUtil.apply_layout(_timebar_state, p1_banc_anchor.global_position)
	else:
		print("[GameLayoutManager._apply_timebar_layout] Skipping timebar layout")

func _apply_game_message_layout() -> void:
	print("[GameLayoutManager._apply_game_message_layout] p1_main_anchor = ", p1_main_anchor, " _game_message_state.size() = ", _game_message_state.size())
	if p1_main_anchor != null and _game_message_state.size() > 0:
		print("[GameLayoutManager._apply_game_message_layout] Calling GameMessage.apply_layout")
		GameMessage.apply_layout(_game_message_state, p1_main_anchor.global_position)
	else:
		print("[GameLayoutManager._apply_game_message_layout] Skipping game message layout")

func _apply_player_linked_ui_layout() -> void:
	"""Apply layout for all player-linked UI elements"""
	_apply_timebar_layout()
	_apply_game_message_layout()
	if _deck_count_state.size() > 0:
		DeckCountUtil.update_positions(_deck_count_state, root, player1_root, player2_root)

func reflow_layout(create_slots: bool, _apply_linked_ui: bool, refresh_slot_rows: bool, apply_players_cb = null) -> void:
	var ctx := compute_layout()
	apply_layout(ctx)

	if apply_players_cb != null:
		# assume callable: call with create_slots
		apply_players_cb.call(create_slots)

	if refresh_slot_rows:
		# TableSyncHelper call remains the responsibility of the scene if needed
		TableSyncHelper.update_table_positions(table_root, _table_spacing, config.START_POS)
