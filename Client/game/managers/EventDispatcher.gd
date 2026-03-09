# Client/game/managers/EventDispatcher.gd
extends RefCounted
class_name EventDispatcher

# ============= SIGNALS =============
var card_started_dragging = Signal()         # emitted(card: Carte)
var card_dropped = Signal()                  # emitted(card: Carte, slot: Slot)
var card_snapped = Signal()                  # emitted(card: Carte, slot: Slot, animate: bool)
var animation_started = Signal()             # emitted(node: Node, type: String)
var animation_finished = Signal()            # emitted(node: Node, type: String)
var turn_updated = Signal()                  # emitted(data: Dictionary)
var game_ended = Signal()                    # emitted(result: Dictionary)
var game_started = Signal()                  # emitted(game_id: String)
var opponent_disconnected = Signal()         # emitted(username: String)
var opponent_rejoined = Signal()             # emitted(username: String)
var network_disconnected = Signal()          # emitted()
var network_restored = Signal()              # emitted()

# ============= SINGLETON PATTERN =============
static var _instance: EventDispatcher = null

static func get_instance() -> EventDispatcher:
	if _instance == null:
		_instance = EventDispatcher.new()
	return _instance

static func reset() -> void:
	if _instance != null:
		_instance = EventDispatcher.new()

# ============= EMIT METHODS (Type-Safe) =============
static func emit_card_started_dragging(card: Node) -> void:
	get_instance().card_started_dragging.emit(card)

static func emit_card_dropped(card: Node, slot: Node) -> void:
	get_instance().card_dropped.emit(card, slot)

static func emit_card_snapped(card: Node, slot: Node, animate: bool) -> void:
	get_instance().card_snapped.emit(card, slot, animate)

static func emit_animation_started(node: Node, type: String) -> void:
	get_instance().animation_started.emit(node, type)

static func emit_animation_finished(node: Node, type: String) -> void:
	get_instance().animation_finished.emit(node, type)

static func emit_turn_updated(data: Dictionary) -> void:
	get_instance().turn_updated.emit(data)

static func emit_game_ended(result: Dictionary) -> void:
	get_instance().game_ended.emit(result)

static func emit_game_started(game_id: String) -> void:
	get_instance().game_started.emit(game_id)

static func emit_opponent_disconnected(username: String) -> void:
	get_instance().opponent_disconnected.emit(username)

static func emit_opponent_rejoined(username: String) -> void:
	get_instance().opponent_rejoined.emit(username)

static func emit_network_disconnected() -> void:
	get_instance().network_disconnected.emit()

static func emit_network_restored() -> void:
	get_instance().network_restored.emit()

# ============= CONNECT METHODS (Type-Safe) =============
static func connect_card_started_dragging(callable: Callable) -> void:
	get_instance().card_started_dragging.connect(callable)

static func connect_card_dropped(callable: Callable) -> void:
	get_instance().card_dropped.connect(callable)

static func connect_card_snapped(callable: Callable) -> void:
	get_instance().card_snapped.connect(callable)

static func connect_animation_finished(callable: Callable) -> void:
	get_instance().animation_finished.connect(callable)

static func connect_turn_updated(callable: Callable) -> void:
	get_instance().turn_updated.connect(callable)

static func connect_game_ended(callable: Callable) -> void:
	get_instance().game_ended.connect(callable)

static func connect_game_started(callable: Callable) -> void:
	get_instance().game_started.connect(callable)

static func connect_opponent_disconnected(callable: Callable) -> void:
	get_instance().opponent_disconnected.connect(callable)

static func connect_opponent_rejoined(callable: Callable) -> void:
	get_instance().opponent_rejoined.connect(callable)

static func connect_network_disconnected(callable: Callable) -> void:
	get_instance().network_disconnected.connect(callable)

static func connect_network_restored(callable: Callable) -> void:
	get_instance().network_restored.connect(callable)
