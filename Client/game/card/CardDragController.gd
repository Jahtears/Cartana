# CardDragController.gd
# Gestion du cycle de vie du drag : démarrage, déplacement, fin, annulation,
# rollback, et gestion de la drag layer.
# Extrait de Carte.gd — Étape 3

class_name CardDragController
extends Node

# ============= CONSTANTS =============
const POINTER_ID_NONE  := -2
const POINTER_ID_MOUSE := -1

# ============= DRAG STATE =============
var dragging              := false
var drag_offset           := Vector2.ZERO
var original_position     := Vector2.ZERO

var _drag_from_slot:      Node2D = null
var _in_drag_layer        := false
var _drag_original_parent: Node = null
var _drag_original_z      := 0
var _active_pointer_id    := POINTER_ID_NONE
var _drag_started_frame   := -1
var _drag_canceled_frame  := -1

# ============= PUBLIC QUERY =============

func get_active_pointer_id() -> int:
  return _active_pointer_id

func is_drag_in_progress(card: Node2D) -> bool:
  return card.state == CardElement.CardState.DRAG \
    or card.state == CardElement.CardState.PREVIEW_SLOT

# ============= ENTRY POINTS =============

## Vérifie les préconditions avant de démarrer le drag.
func try_start_drag(card: Node2D, pointer_id: int) -> void:
  if get_tree().get_frame() == _drag_canceled_frame:
    return
  if not card._is_topmost_card_at_mouse():
    return
  if not card._can_drag():
    return
  _start_drag(card, pointer_id)

## Termine le drag et tente un move réseau.
func end_drag(card: Node2D) -> void:
  if not is_drag_in_progress(card):
    return

  dragging              = false
  _active_pointer_id    = POINTER_ID_NONE
  _drag_started_frame   = -1

  if card.preview:
    card.preview.update_card(card)
    card.preview.update_slot(card, true)

  if not card._can_interact():
    rollback_drag(card)
    return

  var to_slot_id := ""
  if card.preview and card.preview._current_preview_slot != null:
    var target_slot := card.preview._current_preview_slot as Slot
    if target_slot != null:
      to_slot_id = target_slot.get_slot_id()

  if not card._send_move_if_valid(to_slot_id):
    rollback_drag(card)
    return

  card.set_state(CardElement.CardState.DROP)
  if card.preview:
    card.preview.update_slot(card, true)

## Annule le drag en cours (ex. clic secondaire, touch concurrent).
func cancel_drag(card: Node2D) -> void:
  if not is_drag_in_progress(card):
    return
  _drag_canceled_frame = get_tree().get_frame()
  dragging = false
  rollback_drag(card)

## Annule uniquement si le pointer est différent de celui qui a initié le drag.
## Retourne true si le drag a bien été annulé.
func try_cancel_drag_on_click(card: Node2D, pointer_id: int) -> bool:
  if not is_drag_in_progress(card):
    return false
  # Ignore le clic qui vient juste de démarrer le drag (même frame)
  if pointer_id == _active_pointer_id \
      and get_tree().get_frame() == _drag_started_frame:
    return false
  cancel_drag(card)
  return true

## Repositionne la carte à sa position d'origine et remet l'état à IDLE.
func rollback_drag(card: Node2D) -> void:
  dragging           = false
  _active_pointer_id = POINTER_ID_NONE
  _drag_started_frame = -1

  if card.preview:
    card.preview.update_card(card)
    card.preview.update_slot(card, true)

  _leave_drag_layer_to_original(card)
  card.global_position = original_position
  card.set_state(CardElement.CardState.IDLE)

# ============= INTERNAL =============

func _start_drag(card: Node2D, pointer_id: int) -> void:
  var mouse_pos :Variant= card.input_router.get_pointer_global_position(card)

  dragging             = true
  _active_pointer_id   = pointer_id
  _drag_started_frame  = get_tree().get_frame()
  drag_offset          = mouse_pos - card.global_position
  original_position    = card.global_position

  _enter_drag_layer(card)
  card.set_state(CardElement.CardState.DRAG)

  if card.preview:
    card.preview.update_slot(card, true)

func _get_drag_root(card: Node2D) -> Node:
  var nodes = card.get_tree().get_nodes_in_group("drag_root")
  if nodes.size() > 0:
    return nodes[0]
  var scene = card.get_tree().current_scene
  if scene:
    var n = scene.get_node_or_null("DragLayer/DragRoot")
    if n:
      return n
  return null

func _enter_drag_layer(card: Node2D) -> void:
  var drag_root = _get_drag_root(card)
  if drag_root == null:
    card.move_to_front()
    return

  _drag_original_parent = card.get_parent()
  _drag_original_z      = card.z_index
  _drag_from_slot       = card.slot

  if _drag_from_slot != null \
      and _drag_from_slot != card \
      and _drag_from_slot.has_method("_remove_card_ref"):
    _drag_from_slot.call("_remove_card_ref", card)

  var gpos = card.global_position
  card.reparent(drag_root)
  card.global_position = gpos

  drag_root.move_child(card, drag_root.get_child_count() - 1)
  card.z_index  = CardElement.DRAG_Z
  _in_drag_layer = true

  if card.preview:
    card.preview.invalidate_slot_cache()

func _leave_drag_layer_to_original(card: Node2D) -> void:
  if not _in_drag_layer:
    return

  if is_instance_valid(_drag_from_slot):
    _drag_from_slot.snap_card(card, false)
  elif _drag_original_parent != null:
    var gpos = card.global_position
    card.reparent(_drag_original_parent)
    card.global_position = gpos

  card.z_index   = _drag_original_z
  _in_drag_layer = false

  if card.preview:
    card.preview.invalidate_slot_cache()
