extends "res://game/card/CardElement.gd"

# ============= CONSTANTS =============
const MIN_OVERLAP_AREA := 200.0
const POINTER_ID_NONE := -2
const POINTER_ID_MOUSE := -1
const BACK_TEXTURE_DECK_A := preload("res://assets/Cartes/Dos01.png")
const BACK_TEXTURE_DECK_B := preload("res://assets/Cartes/Dos02.png")

# ============= EXPORTS =============
@export var valeur: String = ""
@export var couleur: String = ""
@export var dos: bool = false
@export var decks_color: String = "B"
@export var draggable: bool = true

# ============= STATES =============

# ============= DRAG STATE =============
var dragging := false
var drag_offset := Vector2.ZERO
var original_position := Vector2.ZERO
var _drag_from_slot: Node2D = null
var _in_drag_layer := false
var _drag_original_parent: Node = null
var _drag_original_z := 0
var _pointer_global_pos := Vector2.ZERO
var _pointer_valid := false
var _active_pointer_id := POINTER_ID_NONE
var _drag_started_frame := -1
var _drag_canceled_frame := -1

# ============= PREVIEW & SLOT =============
var preview: CardDropPreview = null
var slot: Node2D = null
var _slot_cache: Array = []
var _slot_cache_valid := false
var _last_preview_frame := -1


# ============= LIFECYCLE =============
func _ready() -> void:
  add_to_group("cards")
  _base_scale = scale
  _pointer_global_pos = get_global_mouse_position()
  _pointer_valid = true
  update_card()

  # Injection automatique du CardDropPreview comme enfant caché
  if preview == null:
    preview = CardDropPreview.new()
    add_child(preview)
    # preview is a logic node, not a visual node; no need to hide

func _process(_delta: float) -> void:
  if state == CardState.DRAG or state == CardState.PREVIEW_SLOT:
    global_position = _get_pointer_global_position() - drag_offset

    var frame = get_tree().get_frame()
    if frame - _last_preview_frame >= PREVIEW_CHECK_INTERVAL:
      preview.update_slot(self)
      preview.update_card(self)
      _last_preview_frame = frame
  else:
    # ===== HOVER STATE MANAGEMENT =====
    _update_hover_state()

# ============= PREVIEW CARD (VISUAL FEEDBACK) =============
# Preview logic moved to CardDropPreview.gd


# ============= VISUAL METHODS =============
# _highlight_card_preview and _reset_card_preview are called by CardDropPreview
func _highlight_card_preview() -> void:
  """Applique un glow léger pendant le drag"""
  _set_border_glow($Front/Bord, true)
  _set_border_glow($Back/Bord, true)

func _reset_card_preview() -> void:
  """Retire le glow et restaure l'état normal"""
  _set_border_glow($Front/Bord, false)
  _set_border_glow($Back/Bord, false)
  _apply_border_visual(decks_color)

func _set_border_glow(bord: Panel, enabled: bool) -> void:
  if bord == null:
    return

  var style = bord.get_theme_stylebox("panel")
  if style and style is StyleBoxFlat:
    # Le glow est une ombre diffuse: on garde la couleur du bord inchangée.
    var new_style = style.duplicate()
    new_style.shadow_size = CardElement.PREVIEW_CARD_GLOW_SIZE if enabled else 0
    new_style.shadow_color = CardElement.PREVIEW_CARD_GLOW_COLOR if enabled else Color(0, 0, 0, 0)
    new_style.shadow_offset = Vector2.ZERO
    bord.add_theme_stylebox_override("panel", new_style)
    
func _update_hover_state() -> void:
  # Si on ne peut pas interagir, forcer IDLE
  if not _can_interact() or dragging:
    if state != CardElement.CardState.IDLE:
      set_state(CardElement.CardState.IDLE)
    return

  # Vérifier si la souris est topmost sur cette carte
  if _is_topmost_card_at_mouse():
    # Passer en HOVER_TOP si on n'y est pas
    if state != CardElement.CardState.HOVER_TOP:
      set_state(CardElement.CardState.HOVER_TOP)
  else:
    # Pas topmost → IDLE
    if state == CardElement.CardState.HOVER_TOP or state == CardElement.CardState.HOVER:
      set_state(CardElement.CardState.IDLE)

func _input(event: InputEvent) -> void:
  if event is InputEventMouseMotion:
    var mm := event as InputEventMouseMotion
    _update_pointer_from_viewport(mm.position)
    return

  if event is InputEventMouseButton:
    var mb := event as InputEventMouseButton
    _update_pointer_from_viewport(mb.position)
    if mb.pressed and _is_mouse_click_button(mb.button_index) and _try_cancel_drag_on_click(POINTER_ID_MOUSE):
      return
    if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
      if _active_pointer_id == POINTER_ID_MOUSE and _is_drag_in_progress():
        _end_drag()
    return

  if event is InputEventScreenDrag:
    var sd := event as InputEventScreenDrag
    if not dragging or sd.index == _active_pointer_id:
      _update_pointer_from_viewport(sd.position)
    return

  if event is InputEventScreenTouch:
    var st := event as InputEventScreenTouch
    _update_pointer_from_viewport(st.position)
    if st.pressed and _try_cancel_drag_on_click(st.index):
      return
    if not st.pressed and st.index == _active_pointer_id and _is_drag_in_progress():
      _end_drag()

# ============= STATE MACHINE =============

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
  return draggable and _can_interact() and not dragging

func _is_drag_in_progress() -> bool:
  return state == CardElement.CardState.DRAG or state == CardElement.CardState.PREVIEW_SLOT

func _update_pointer_global(global_pos: Vector2) -> void:
  _pointer_global_pos = global_pos
  _pointer_valid = true

func _update_pointer_from_viewport(viewport_pos: Vector2) -> void:
  var local_pos := get_global_transform_with_canvas().affine_inverse() * viewport_pos
  _update_pointer_global(to_global(local_pos))

func _get_pointer_global_position() -> Vector2:
  if _pointer_valid:
    return _pointer_global_pos
  return get_global_mouse_position()

# ============= VISUAL UPDATES =============
func set_card_data(v: String, c: String, d: bool, deck_source: String, can_drag: bool = true) -> void:
  valeur = v
  couleur = c
  dos = d
  if deck_source != "":
    decks_color = deck_source
  draggable = can_drag
  update_card()

func update_card() -> void:
  _apply_back_visual(decks_color)
  _apply_border_visual(decks_color)

  if dos:
    _show_back()
    return

  _show_front()

  var symboles := {
    "H": "♥",
    "C": "♦",
    "P": "♠",
    "S": "♣"
  }

  var texte_couleur := Color.RED if (couleur == "H" or couleur == "C") else Color.BLACK

  $Front/Top/ValeurT.text = valeur
  $Front/Top/ValeurT.modulate = texte_couleur
  $Front/Top/SymboleT.text = String(symboles.get(couleur, "?"))
  $Front/Top/SymboleT.modulate = texte_couleur

  $Front/Bottom/ValeurB.text = valeur
  $Front/Bottom/ValeurB.modulate = texte_couleur
  $Front/Bottom/SymboleB.text = String(symboles.get(couleur, "?"))
  $Front/Bottom/SymboleB.modulate = texte_couleur

func _apply_back_visual(code: String) -> void:
  var back := $Back as TextureRect
  if back == null:
    return

  back.texture = _get_back_texture(code)
  back.modulate = Color(1, 1, 1, 1)

func _apply_border_visual(code: String) -> void:
  var deck_color := _get_back_color(code)
  _set_border_color($Front/Bord, deck_color)
  _set_border_color($Back/Bord, deck_color)

func _set_border_color(bord: Panel, border_color: Color) -> void:
  if bord == null:
    return

  var style = bord.get_theme_stylebox("panel")
  if style and style is StyleBoxFlat:
    var new_style = style.duplicate()
    new_style.border_color = border_color
    bord.add_theme_stylebox_override("panel", new_style)

func _get_back_color(code: String) -> Color:
  if code == "A":
    return Color(0.77, 0.435, 0.597, 1.0)
  return Color(0.2, 0.4, 1.0)

func _get_back_texture(code: String) -> Texture2D:
  var source: String = String(code).strip_edges().to_upper()
  var selected_id: String = CardBackManager.get_selected_back_for_source(source)
  if selected_id == "" and source == "A":
    # Fallback sur le dos global si rien n'est sélectionné
    if "card_back_a" in Global:
      selected_id = Global.card_back_a
  elif selected_id == "" and source == "B":
    if "card_back_b" in Global:
      selected_id = Global.card_back_b
  var selected_texture: Texture2D = CardBackManager.get_back_texture_by_id(selected_id)
  if selected_texture != null:
    return selected_texture
  if source == "A":
    return BACK_TEXTURE_DECK_A
  return BACK_TEXTURE_DECK_B

func _show_front() -> void:
  $Front.visible = true
  $Back.visible = false

func _show_back() -> void:
  $Front.visible = false
  $Back.visible = true

# ============= HOVER =============

func _is_topmost_card_at_mouse() -> bool:
  var mouse_pos = _get_pointer_global_position()
  var cards_group = get_tree().get_nodes_in_group("cards")
  var topmost := CardGeometry.pick_topmost_node_at_point(cards_group, mouse_pos)
  return topmost == self

# ============= DRAG INPUT =============
func _on_area_2d_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
  if event is InputEventMouseButton:
    var mb := event as InputEventMouseButton
    _update_pointer_from_viewport(mb.position)
    if mb.pressed and _is_mouse_click_button(mb.button_index) and _try_cancel_drag_on_click(POINTER_ID_MOUSE):
      return
    if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
      _try_start_drag(POINTER_ID_MOUSE)
    return

  if event is InputEventScreenTouch:
    var st := event as InputEventScreenTouch
    _update_pointer_from_viewport(st.position)
    if st.pressed and _try_cancel_drag_on_click(st.index):
      return
    if st.pressed:
      _try_start_drag(st.index)

func _try_start_drag(pointer_id: int) -> void:
  if get_tree().get_frame() == _drag_canceled_frame:
    return
  if not _is_topmost_card_at_mouse():
    return
  if not _can_drag():
    return
  _start_drag(_get_pointer_global_position(), pointer_id)

# ============= DRAG LIFECYCLE =============
func _start_drag(mouse_pos: Vector2, pointer_id: int = POINTER_ID_MOUSE) -> void:
  dragging = true
  _active_pointer_id = pointer_id
  _drag_started_frame = get_tree().get_frame()
  _update_pointer_global(mouse_pos)
  drag_offset = mouse_pos - global_position
  original_position = global_position

  _enter_drag_layer()
  set_state(CardElement.CardState.DRAG)

  # Reset preview slot if needed
  if preview:
    preview.update_slot(self, true)

func _end_drag() -> void:
  if not _is_drag_in_progress():
    return

  dragging = false
  _active_pointer_id = POINTER_ID_NONE
  _drag_started_frame = -1
  

  # Reset preview card and slot using preview manager
  if preview:
    preview.update_card(self)
    preview.update_slot(self, true)

  if not _can_interact():
    _rollback_drag()
    return

  # Récupérer le slot cible via le preview manager
  var to_slot_id := ""
  if preview and preview._current_preview_slot != null:
    var target_slot := preview._current_preview_slot as Slot
    if target_slot != null:
      to_slot_id = target_slot.get_slot_id()

  if not _send_move_if_valid(to_slot_id):
    _rollback_drag()
    return

  set_state(CardElement.CardState.DROP)
  if preview:
    preview.update_slot(self, true)

func _cancel_drag() -> void:
  if not _is_drag_in_progress():
    return
  _drag_canceled_frame = get_tree().get_frame()
  dragging = false
  _rollback_drag()

func _try_cancel_drag_on_click(pointer_id: int) -> bool:
  if not _is_drag_in_progress():
    return false
  # Ignore le clic/tap qui vient juste de démarrer le drag.
  if pointer_id == _active_pointer_id and get_tree().get_frame() == _drag_started_frame:
    return false
  _cancel_drag()
  return true

func _is_mouse_click_button(button_index: int) -> bool:
  return button_index == MOUSE_BUTTON_LEFT or button_index == MOUSE_BUTTON_RIGHT or button_index == MOUSE_BUTTON_MIDDLE

func _rollback_drag() -> void:
  dragging = false
  _active_pointer_id = POINTER_ID_NONE
  _drag_started_frame = -1
  if preview:
    preview.update_card(self)
    preview.update_slot(self, true)
  _leave_drag_layer_to_original()
  global_position = original_position
  set_state(CardElement.CardState.IDLE)
  # preview slot reset is now handled by preview instance

# ============= DRAG LAYER =============
func _get_drag_root() -> Node:
  var nodes = get_tree().get_nodes_in_group("drag_root")
  if nodes.size() > 0:
    return nodes[0]

  var scene = get_tree().current_scene
  if scene:
    var n = scene.get_node_or_null("DragLayer/DragRoot")
    if n:
      return n

  return null

func _enter_drag_layer() -> void:
  var drag_root = _get_drag_root()
  if drag_root == null:
    move_to_front()
    return

  _drag_original_parent = get_parent()
  _drag_original_z = z_index
  _drag_from_slot = slot

  if _drag_from_slot != null and _drag_from_slot != self and _drag_from_slot.has_method("_remove_card_ref"):
    _drag_from_slot.call("_remove_card_ref", self)

  var gpos = global_position
  reparent(drag_root)
  global_position = gpos

  drag_root.move_child(self, drag_root.get_child_count() - 1)
  z_index = CardElement.DRAG_Z

  _in_drag_layer = true
  _slot_cache_valid = false

func _leave_drag_layer_to_original() -> void:
  if not _in_drag_layer:
    return

  if is_instance_valid(_drag_from_slot):
    _drag_from_slot.snap_card(self, false)
  elif _drag_original_parent != null:
    var gpos = global_position
    reparent(_drag_original_parent)
    global_position = gpos

  z_index = _drag_original_z
  _in_drag_layer = false
  _slot_cache_valid = false

# ============= PREVIEW SLOT =============
# Preview slot logic moved to CardDropPreview.gd

# ============= GEOMETRY =============

# Utilitaires géométriques extraits dans CardGeometry.gd


# ============= NETWORK =============
func get_card_id() -> String:
  if has_meta("card_id"):
    return String(get_meta("card_id"))
  return String(name)

func _send_move_if_valid(to_slot_id: String) -> bool:
  if not _can_interact():
    return false

  var parsed_to := SlotIdHelper.parse_slot_id(to_slot_id)
  var to_type := String(parsed_to.get("type", ""))
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

  NetworkManager.request("move_request", {
    "card_id": card_id,
    "from_slot_id": from_slot_id,
    "to_slot_id": to_slot_id
  })
  return true
