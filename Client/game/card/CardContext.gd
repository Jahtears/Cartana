extends RefCounted
class_name CardContext

## Typed context for card management - replaces untyped _card_ctx Dictionary
## Provides type-safe access to cards, scenes, slots, and root node

var cards: Dictionary = {}
var card_scene: PackedScene = null
var slots_by_id: Dictionary = {}
var root: Node = null

func _init(p_cards: Dictionary = {}, p_card_scene: PackedScene = null, 
           p_slots_by_id: Dictionary = {}, p_root: Node = null) -> void:
    """Initialize CardContext with typed parameters"""
    cards = p_cards
    card_scene = p_card_scene
    slots_by_id = p_slots_by_id
    root = p_root
