# card_sync.gd
extends RefCounted
class_name CardSyncHelper

const SlotIdHelper = preload("res://Client/game/helpers/slot_id.gd")

const UNKNOWN_ORDER_SENTINEL := 2147483647

const KEY_CARD_ID := "card_id"
const KEY_SLOT_ID := "slot_id"
const KEY_VALUE := "valeur"
const KEY_SUIT := "couleur"
const KEY_BACK := "dos"
const KEY_BACK_COLOR := "dos_couleur"
const KEY_DRAGGABLE := "draggable"

const KEY_ORDER_ARRAY := "_array_order"
const KEY_ORDER_ARRAY_LEGACY := "array_order"
const KEY_ORDER_SLOT := "slot_order"

const META_CARD_ID := "card_id"
const META_JUST_CREATED := "just_created"
const META_LAST_SLOT_ID := "last_slot_id"
const META_SERVER_ARRAY_ORDER := "_server_array_order"

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
	card.set_meta(META_CARD_ID, card_id)
	card.set_meta(META_JUST_CREATED, true)
	card.set_meta(META_LAST_SLOT_ID, "")
	return card

static func apply_card_update(game_ctx: Dictionary, data: Dictionary) -> void:
	var card_id: String = String(data.get(KEY_CARD_ID, ""))
	if card_id == "":
		return

	var card := get_or_create_card(game_ctx, card_id)
	if card == null:
		return

	var payload := _extract_card_payload(data)
	card.set_card_data(
		String(payload.get(KEY_VALUE, "")),
		String(payload.get(KEY_SUIT, "")),
		bool(payload.get(KEY_BACK, false)),
		String(payload.get(KEY_BACK_COLOR, "")),
		bool(payload.get(KEY_DRAGGABLE, false))
	)

	var order_from_payload := _resolve_order_from_payload(data)
	if order_from_payload >= 0:
		card.set_meta(META_SERVER_ARRAY_ORDER, order_from_payload)
	else:
		card.set_meta(META_SERVER_ARRAY_ORDER, UNKNOWN_ORDER_SENTINEL)

	var slot_id: String = SlotIdHelper.normalize_slot_id(String(data.get(KEY_SLOT_ID, "")))
	var slot = _resolve_target_slot(game_ctx, slot_id)
	if slot == null:
		return

	var animate := _should_animate_snap(card, slot, slot_id)
	card.set_meta(META_JUST_CREATED, false)
	slot.snap_card(card, animate)
	card.set_meta(META_LAST_SLOT_ID, slot_id)

static func _extract_card_payload(data: Dictionary) -> Dictionary:
	return {
		KEY_VALUE: String(data.get(KEY_VALUE, "")),
		KEY_SUIT: String(data.get(KEY_SUIT, "")),
		KEY_BACK: bool(data.get(KEY_BACK, false)),
		KEY_BACK_COLOR: String(data.get(KEY_BACK_COLOR, "")),
		KEY_DRAGGABLE: bool(data.get(KEY_DRAGGABLE, false)),
	}

static func _resolve_order_from_payload(data: Dictionary) -> int:
	var order_from_payload := int(data.get(KEY_ORDER_ARRAY, -1))
	if order_from_payload < 0:
		order_from_payload = int(data.get(KEY_ORDER_ARRAY_LEGACY, -1))
	if order_from_payload < 0:
		order_from_payload = int(data.get(KEY_ORDER_SLOT, -1))
	return order_from_payload

static func _resolve_target_slot(game_ctx: Dictionary, slot_id: String):
	if slot_id == "":
		return null
	var slots_by_id: Dictionary = game_ctx.get("slots_by_id", {})
	return slots_by_id.get(slot_id, null)

static func _should_animate_snap(card: Node2D, target_slot, slot_id: String) -> bool:
	if bool(card.get_meta(META_JUST_CREATED, false)):
		return false

	var prev_slot_id := String(card.get_meta(META_LAST_SLOT_ID, ""))
	if prev_slot_id != "" and prev_slot_id != slot_id:
		return true
	if card.slot != null and card.slot != target_slot:
		return true
	return false
