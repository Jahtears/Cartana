# card_sync.gd
extends RefCounted
class_name CardSyncHelper

static func get_or_create_card(game_ctx: Dictionary, card_id: String) -> Node2D:
	var cards = game_ctx.get("cards", null)
	var card_scene: PackedScene = game_ctx.get("card_scene", null)
	var root: Node = game_ctx.get("root", null)

	if cards == null:
		return null

	if cards.has(card_id):
		return cards[card_id] as Node2D

	if card_scene == null or root == null:
		return null

	var card := card_scene.instantiate() as Node2D
	root.add_child(card)
	cards[card_id] = card
	card.set_meta("card_id", card_id)
	card.set_meta("just_created", true)
	card.set_meta("last_slot_id", "")
	return card

static func apply_card_update(game_ctx: Dictionary, data: Dictionary) -> void:
	var card_id: String = String(data.get("card_id", ""))
	if card_id == "":
		return

	var card := get_or_create_card(game_ctx, card_id)
	if card == null:
		return

	var valeur: String = String(data.get("valeur", ""))
	var couleur: String = String(data.get("couleur", ""))
	var dos: bool = bool(data.get("dos", false))
	var dos_couleur: String = String(data.get("dos_couleur", ""))
	var draggable: bool = bool(data.get("draggable", false))

	card.set_card_data(valeur, couleur, dos, dos_couleur, draggable)

	var slot_id: String = SlotIdHelper.normalize_slot_id(String(data.get("slot_id", "")))
	var slots_by_id: Dictionary = game_ctx.get("slots_by_id", {})
	var slot = slots_by_id.get(slot_id, null)
	if slot:
		var animate := false

		if not bool(card.get_meta("just_created", false)):
			var prev_slot_id := String(card.get_meta("last_slot_id", ""))
			if prev_slot_id != "" and prev_slot_id != slot_id:
				animate = true
			elif card.slot != null and card.slot != slot:
				animate = true

		card.set_meta("just_created", false)
		slot.snap_card(card, animate)
		card.set_meta("last_slot_id", slot_id)
