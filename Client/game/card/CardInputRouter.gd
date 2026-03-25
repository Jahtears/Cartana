# CardInputRouter.gd
# Gestion des événements d'entrée bruts et du suivi du pointeur.
# Extrait de Carte.gd — Étape 4

class_name CardInputRouter
extends Node

# ============= POINTER STATE =============
var _pointer_global_pos := Vector2.ZERO
var _pointer_valid       := false

# ============= INIT =============

## À appeler depuis _ready() de la carte pour initialiser la position du pointeur.
func initialize(card: Node2D) -> void:
  _pointer_global_pos = card.get_global_mouse_position()
  _pointer_valid      = true

# ============= PUBLIC QUERY =============

func get_pointer_global_position(card: Node2D) -> Vector2:
  if _pointer_valid:
    return _pointer_global_pos
  return card.get_global_mouse_position()

# ============= INPUT HANDLERS =============

## Gère les événements globaux (_input de Carte.gd).
func handle_input(card: Node2D, event: InputEvent) -> void:
  var dc: CardDragController = card.drag_controller

  if event is InputEventMouseMotion:
    _update_pointer_from_viewport(card, (event as InputEventMouseMotion).position)
    return

  if event is InputEventMouseButton:
    var mb := event as InputEventMouseButton
    _update_pointer_from_viewport(card, mb.position)
    if mb.pressed \
        and _is_mouse_click_button(mb.button_index) \
        and dc.try_cancel_drag_on_click(card, CardDragController.POINTER_ID_MOUSE):
      return
    if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
      if dc.get_active_pointer_id() == CardDragController.POINTER_ID_MOUSE \
          and dc.is_drag_in_progress(card):
        dc.end_drag(card)
    return

  if event is InputEventScreenDrag:
    var sd := event as InputEventScreenDrag
    if not dc.dragging or sd.index == dc.get_active_pointer_id():
      _update_pointer_from_viewport(card, sd.position)
    return

  if event is InputEventScreenTouch:
    var st := event as InputEventScreenTouch
    _update_pointer_from_viewport(card, st.position)
    if st.pressed and dc.try_cancel_drag_on_click(card, st.index):
      return
    if not st.pressed \
        and st.index == dc.get_active_pointer_id() \
        and dc.is_drag_in_progress(card):
      dc.end_drag(card)

## Gère les événements de l'Area2D (_on_area_2d_input_event de Carte.gd).
func handle_area_input(card: Node2D, event: InputEvent) -> void:
  var dc: CardDragController = card.drag_controller

  if event is InputEventMouseButton:
    var mb := event as InputEventMouseButton
    _update_pointer_from_viewport(card, mb.position)
    if mb.pressed \
        and _is_mouse_click_button(mb.button_index) \
        and dc.try_cancel_drag_on_click(card, CardDragController.POINTER_ID_MOUSE):
      return
    if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
      dc.try_start_drag(card, CardDragController.POINTER_ID_MOUSE)
    return

  if event is InputEventScreenTouch:
    var st := event as InputEventScreenTouch
    _update_pointer_from_viewport(card, st.position)
    if st.pressed and dc.try_cancel_drag_on_click(card, st.index):
      return
    if st.pressed:
      dc.try_start_drag(card, st.index)

# ============= INTERNAL =============

func _update_pointer_global(global_pos: Vector2) -> void:
  _pointer_global_pos = global_pos
  _pointer_valid      = true

func _update_pointer_from_viewport(card: Node2D, viewport_pos: Vector2) -> void:
  var local_pos := card.get_global_transform_with_canvas().affine_inverse() * viewport_pos
  _update_pointer_global(card.to_global(local_pos))

func _is_mouse_click_button(button_index: int) -> bool:
  return button_index == MOUSE_BUTTON_LEFT \
    or button_index == MOUSE_BUTTON_RIGHT \
    or button_index == MOUSE_BUTTON_MIDDLE
