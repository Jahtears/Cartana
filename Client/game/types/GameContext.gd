# Client/game/types/GameContext.gd
extends RefCounted
class_name GameContext

# ============= TYPES =============
var card_context: CardContext = null
var ui_manager: RefCounted = null
var layout_manager: RefCounted = null

# ============= EXTRACTED FROM Game.gd =============
var game_node: Node = null

# ============= STATE =============

var pending_events: Array = []
var slots_ready: bool = false

# ============= FLAGS =============
var is_changing_scene: bool = false
var game_end_prompted: bool = false
var leave_sent: bool = false
var opponent_disconnected: bool = false
var network_disconnected: bool = false
var disconnect_prompt_seq: int = 0

# ============= INITIALIZATION =============
func _init(game: Node) -> void:
    game_node = game
    card_context = CardContext.new()
    card_context.root = game
    slots_ready = false
    pending_events = []

# ============= PUBLIC METHODS =============

func reset_flags() -> void:
    is_changing_scene = false
    game_end_prompted = false
    leave_sent = false
    opponent_disconnected = false
    network_disconnected = false
    disconnect_prompt_seq += 1


func is_playing() -> bool:
    # L’état de partie est maintenant dans GameSession
    return false


func is_game_end() -> bool:
    # L’état de fin de partie est maintenant dans GameSession
    return false

# ============= SAFE ACCESSORS =============
func get_card(card_id: String) -> Variant:
    if card_context and card_context.cards:
        return card_context.cards.get(card_id)
    return null

func get_slot(slot_id: String) -> Variant:
    if card_context and card_context.slots_by_id:
        return card_context.slots_by_id.get(slot_id)
    return null
