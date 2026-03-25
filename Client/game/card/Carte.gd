extends "res://game/card/CardElement.gd"

# ============= EXPORTS =============
@export var valeur:      String = ""
@export var couleur:     String = ""
@export var dos:         bool   = false
@export var decks_color: String = "B"
@export var draggable:   bool   = true

# ============= MODULES =============
var preview:         CardDropPreview    = null
var drag_controller: CardDragController = null
var input_router:    CardInputRouter    = null
var visual:          CardVisual         = null

# ============= SLOT =============
var slot: Node2D = null

# ============= PRIVATE =============
var _last_preview_frame := -1

# ============= LIFECYCLE =============
func _ready() -> void:
  add_to_group("cards")
  _base_scale = scale

  preview = CardDropPreview.new()
  add_child(preview)

  drag_controller = CardDragController.new()
  add_child(drag_controller)

  input_router = CardInputRouter.new()
  add_child(input_router)
  input_router.initialize(self)

  visual = CardVisual.new()
  add_child(visual)
  visual.update(self)

func _process(_delta: float) -> void:
  if drag_controller.is_drag_in_progress(self):
    global_position = input_router.get_pointer_global_position(self) \
      - drag_controller.drag_offset

    var frame = get_tree().get_frame()
    if frame - _last_preview_frame >= PREVIEW_CHECK_INTERVAL:
      preview.update_slot(self)
      preview.update_card(self)
      _last_preview_frame = frame
  else:
    _update_hover_state()

# ============= INPUT DELEGATION =============
func _input(event: InputEvent) -> void:
  input_router.handle_input(self, event)

func _on_area_2d_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
  input_router.handle_area_input(self, event)

# ============= GAME STATE =============
func _is_game_end() -> bool:
  return GameSession.is_game_ended()

func _can_interact() -> bool:
  if GameSession.is_spectator:
    return false
  if _is_game_end():
    return false
  return true

func _can_drag() -> bool:
  return draggable and _can_interact() and not drag_controller.dragging

# ============= HOVER =============
func _update_hover_state() -> void:
  if not _can_interact() or drag_controller.dragging:
    if state != CardElement.CardState.IDLE:
      set_state(CardElement.CardState.IDLE)
    return

  if _is_topmost_card_at_mouse():
    if state != CardElement.CardState.HOVER_TOP:
      set_state(CardElement.CardState.HOVER_TOP)
  else:
    if state == CardElement.CardState.HOVER_TOP or state == CardElement.CardState.HOVER:
      set_state(CardElement.CardState.IDLE)

func _is_topmost_card_at_mouse() -> bool:
  var mouse_pos  = input_router.get_pointer_global_position(self)
  var cards_group = get_tree().get_nodes_in_group("cards")
  var topmost    := CardGeometry.pick_topmost_node_at_point(cards_group, mouse_pos)
  return topmost == self

# ============= VISUAL =============
func set_card_data(v: String, c: String, d: bool, deck_source: String, can_drag: bool = true) -> void:
  valeur  = v
  couleur = c
  dos     = d
  if deck_source != "":
    decks_color = deck_source
  draggable = can_drag
  visual.update(self)

func update_card() -> void:
  visual.update(self)

# Thin delegates so CardDropPreview n'a pas besoin de connaître CardVisual
func _highlight_card_preview() -> void:
  visual.highlight_preview(self)

func _reset_card_preview() -> void:
  visual.reset_preview(self)

# ============= NETWORK =============
func get_card_id() -> String:
  if has_meta("card_id"):
    return String(get_meta("card_id"))
  return String(name)

func _send_move_if_valid(to_slot_id: String) -> bool:
  if not _can_interact():
    return false

  var parsed_to := SlotIdHelper.parse_slot_id(to_slot_id)
  var to_type   := String(parsed_to.get("type", ""))
  if to_type == "DECK" or to_type == "PILE":
    print("[MOVE] Ignoring forbidden target slot type: %s" % to_type)
    return false

  var from_slot_id := ""
  if slot != null:
    var slot_ref := slot as Slot
    if slot_ref != null:
      from_slot_id = slot_ref.get_slot_id()

  if from_slot_id == "" or to_slot_id == "":
    return false

  if from_slot_id == to_slot_id:
    print("[MOVE] Ignoring same slot drop: %s → %s" % [from_slot_id, to_slot_id])
    return false

  var card_id := get_card_id()
  print("[MOVE] Sending move: %s from %s to %s" % [card_id, from_slot_id, to_slot_id])
  ClientAPI.move_card(card_id, from_slot_id, to_slot_id)
  return true
