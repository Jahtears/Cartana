
class_name CardDropPreview
extends Node

# CardDropPreview.gd
# Isolates preview logic for slot and card highlighting during drag/preview.

var _current_preview_slot: Node2D = null
var _current_preview_card: Node2D = null
var _slot_cache: Array = []
var _slot_cache_valid := false

const MIN_OVERLAP_AREA := 200.0

func update_slot(card: Node2D, ignore_topmost: bool = false) -> void:
  # 🔥 Only preview if the card is topmost under the mouse
  if not ignore_topmost and not card._is_topmost_card_at_mouse():
    _set_preview_slot(null, card)
    return

  if not _slot_cache_valid:
    _slot_cache = card.get_tree().get_nodes_in_group("slots")
    _slot_cache_valid = true

  var card_rect = CardGeometry.get_card_rect(card)
  var best_slot: Node = null
  var best_area := 0.0

  for s in _slot_cache:
    if s == null or not is_instance_valid(s):
      continue
    if not _is_drop_target_allowed(s):
      continue

    var slot_rect: Rect2
    if s.has_method("get_cached_rect"):
      slot_rect = s.call("get_cached_rect")
    else:
      if s is Node2D:
        slot_rect = CardGeometry.rect_from_collision_shape_node(s as Node2D)
      else:
        slot_rect = Rect2()

    if slot_rect.size == Vector2.ZERO:
      continue

    var inter = CardGeometry.rect_intersection(card_rect, slot_rect)
    var area = inter.size.x * inter.size.y

    if area > best_area:
      best_area = area
      best_slot = s

  if best_area < MIN_OVERLAP_AREA:
    best_slot = null

  _set_preview_slot(best_slot, card)

func _is_drop_target_allowed(slot_node: Node) -> bool:
  if slot_node == null:
    return false

  var target_slot_id := ""
  var target_slot := slot_node as Slot
  if target_slot != null:
    target_slot_id = target_slot.get_slot_id()

  if target_slot_id == "":
    return false

  var parsed := SlotIdHelper.parse_slot_id(target_slot_id)
  var slot_type := String(parsed.get("type", ""))
  if slot_type == "DECK" or slot_type == "PILE":
    return false

  return true

func _set_preview_slot(new_slot: Node, card: Node2D) -> void:
  if _current_preview_slot == new_slot:
    return

  if _current_preview_slot != null:
    if _current_preview_slot.has_method("_set_preview"):
      _current_preview_slot.call("_set_preview", false)
    elif _current_preview_slot.has_method("on_card_exit_preview"):
      _current_preview_slot.call("on_card_exit_preview")

  _current_preview_slot = new_slot

  if _current_preview_slot != null:
    if _current_preview_slot.has_method("_set_preview"):
      _current_preview_slot.call("_set_preview", true)
    elif _current_preview_slot.has_method("on_card_enter_preview"):
      _current_preview_slot.call("on_card_enter_preview")

    card.set_state(CardElement.CardState.PREVIEW_SLOT if new_slot != null else CardElement.CardState.DRAG)

func update_card(card: Node2D) -> void:
  var card_rect = CardGeometry.get_card_rect(card)
  var cards_group = card.get_tree().get_nodes_in_group("cards")

  var best_card: Node2D = null
  var best_overlap := 0.0

  for other_card in cards_group:
    if not (other_card is Node2D):
      continue
    if other_card == card:
      continue
    if not is_instance_valid(other_card):
      continue
    var other_rect: Rect2 = CardGeometry.get_card_rect(other_card)
    var intersection = CardGeometry.rect_intersection(card_rect, other_rect)
    var overlap_area = intersection.get_area()

    if overlap_area > best_overlap:
      best_overlap = overlap_area
      best_card = other_card

  # If overlap is sufficient, highlight
  if best_overlap >= MIN_OVERLAP_AREA:
    _set_preview_card(best_card, card)
  else:
    _set_preview_card(null, card)

func _set_preview_card(new_card: Node2D, card: Node2D) -> void:
  if _current_preview_card == new_card:
    return

  # Reset previous card
  if _current_preview_card != null and is_instance_valid(_current_preview_card):
    _current_preview_card._reset_card_preview()

  _current_preview_card = new_card
  if _current_preview_card != null and is_instance_valid(_current_preview_card):
    _current_preview_card._highlight_card_preview()

# Visual feedback methods (delegated to Card)
# These are called on the card instance, not on the preview manager itself.
# _highlight_card_preview and _reset_card_preview remain on Card.
