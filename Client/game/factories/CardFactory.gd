# Client/game/factories/CardFactory.gd
extends RefCounted
class_name CardFactory

# ============= CONSTANTS =============
const UNKNOWN_ORDER_SENTINEL := 2147483647
const META_CARD_ID := "card_id"
const META_JUST_CREATED := "just_created"
const META_LAST_SLOT_ID := "last_slot_id"
const META_SERVER_ARRAY_ORDER := "_server_array_order"

# ============= PUBLIC METHODS =============
func get_or_create_card(ctx: CardContext, card_id: String) -> Node2D:
	"""Récupère une carte existante ou en crée une nouvelle"""
	if ctx == null or ctx.cards == null:
		return null

	if ctx.cards.has(card_id):
		return ctx.cards[card_id] as Node2D

	if ctx.card_scene == null or ctx.root == null:
		return null

	var card := ctx.card_scene.instantiate() as Node2D
	ctx.root.add_child(card)
	ctx.cards[card_id] = card
	
	card.set_meta(META_CARD_ID, card_id)
	card.set_meta(META_JUST_CREATED, true)
	card.set_meta(META_LAST_SLOT_ID, "")
	
	return card

func update_card_data(card: Node2D, data: Dictionary) -> void:
	"""Met à jour les données visibles d'une carte"""
	if card == null or not card.has_method("set_card_data"):
		return
	
	var payload := _extract_card_payload(data)
	card.set_card_data(
		String(payload.get("value", "")),
		String(payload.get("suit", "")),
		bool(payload.get("back", false)),
		String(payload.get("deck_source", "")),
		bool(payload.get("draggable", true))
	)

func set_card_server_order(card: Node2D, data: Dictionary) -> void:
	"""Définit l'ordre serveur de la carte"""
	if card == null:
		return
	
	var order := _resolve_order_from_payload(data)
	if order >= 0:
		card.set_meta(META_SERVER_ARRAY_ORDER, order)
	else:
		card.set_meta(META_SERVER_ARRAY_ORDER, UNKNOWN_ORDER_SENTINEL)

func mark_card_synced(card: Node2D) -> void:
	"""Marque la carte comme synchronisée"""
	if card != null:
		card.set_meta(META_JUST_CREATED, false)

func update_card_last_slot(card: Node2D, slot_id: String) -> void:
	"""Met à jour le dernier slot de la carte"""
	if card != null:
		card.set_meta(META_LAST_SLOT_ID, slot_id)

# ============= PRIVATE HELPERS =============
func _extract_card_payload(data: Dictionary) -> Dictionary:
	"""Extrait les données visuelles de la carte"""
	return {
		"value": String(data.get("valeur", "")),
		"suit": String(data.get("couleur", "")),
		"back": bool(data.get("dos", false)),
		"deck_source": String(data.get("source", "")),
		"draggable": bool(data.get("draggable", true)),
	}

func _resolve_order_from_payload(data: Dictionary) -> int:
	"""Résout l'ordre de la carte depuis le payload"""
	var order_from_array := int(data.get("_array_order", -1))
	if order_from_array < 0:
		order_from_array = int(data.get("slot_order", -1))
	return order_from_array
