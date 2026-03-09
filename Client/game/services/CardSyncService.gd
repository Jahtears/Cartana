# Client/game/services/CardSyncService.gd
extends RefCounted
class_name CardSyncService

# ============= CONSTANTS =============
const META_JUST_CREATED := "just_created"
const META_LAST_SLOT_ID := "last_slot_id"

# ============= PROPERTIES =============
var context: CardContext = null
var _card_factory: CardFactory = null

# ============= LIFECYCLE =============
func _init(ctx: CardContext) -> void:
	context = ctx
	_card_factory = CardFactory.new()

# ============= PUBLIC METHODS =============
func sync_card(data: Dictionary) -> Node2D:
	"""Synchronise une carte depuis les données serveur"""
	if context == null:
		print("[CardSyncService] ERROR: context is null")
		return null
	
	var card_id: String = String(data.get("card_id", ""))
	if card_id == "":
		return null

	print("[CardSyncService] Syncing card: %s" % card_id)

	# Récupérer ou créer la carte
	var card := _card_factory.get_or_create_card(context, card_id)
	if card == null:
		print("[CardSyncService] ERROR: Failed to create card %s" % card_id)
		return null

	# Mettre à jour les données visuelles
	_card_factory.update_card_data(card, data)
	
	# Définir l'ordre serveur
	_card_factory.set_card_server_order(card, data)

	# Trouver le slot cible
	var slot_id: String = SlotIdHelper.normalize_slot_id(String(data.get("slot_id", "")))
	var slot = context.slots_by_id.get(slot_id) if context.slots_by_id else null
	
	print("[CardSyncService] Card %s → Slot %s (found: %s, total_slots: %d)" % [card_id, slot_id, slot != null, context.slots_by_id.size()])
	
	if slot == null:
		return card

	# Déterminer si on doit animer
	var should_animate := _should_animate_snap(card, slot, slot_id)
	
	# Mark la carte comme créée pendant cette sync
	_card_factory.mark_card_synced(card)
	
	# Snap la carte dans le slot
	if slot.has_method("snap_card"):
		slot.snap_card(card, should_animate)
		EventDispatcher.emit_card_snapped(card, slot, should_animate)
	
	# Mettre à jour le dernier slot
	_card_factory.update_card_last_slot(card, slot_id)
	
	return card

func sync_multiple_cards(data_array: Array) -> Array:
	"""Synchronise plusieurs cartes"""
	var synced_cards: Array = []
	for data in data_array:
		var card = sync_card(data)
		if card != null:
			synced_cards.append(card)
	return synced_cards

# ============= PRIVATE HELPERS =============
func _should_animate_snap(card: Node2D, target_slot: Node, slot_id: String) -> bool:
	"""Détermine si le snap de la carte doit être animé"""
	if card.has_meta(META_JUST_CREATED) and bool(card.get_meta(META_JUST_CREATED)):
		return false

	var prev_slot_id := ""
	if card.has_meta(META_LAST_SLOT_ID):
		prev_slot_id = String(card.get_meta(META_LAST_SLOT_ID))
	if prev_slot_id != "" and prev_slot_id != slot_id:
		return true
	
	if card.slot != null and card.slot != target_slot:
		return true
	
	return false
