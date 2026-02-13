# Carte.gd v2.2 - Fix: sélection topmost, hover vs drag preview, validation drops

extends Node2D

# ============= EXPORTS =============
@export var valeur: String = ""
@export var couleur: String = ""
@export var dos: bool = false
@export var dos_couleur: String = "bleu"
@export var draggable: bool = true

# ============= DRAG STATE =============
var dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var original_position: Vector2 = Vector2.ZERO
var _drag_from_slot: Node2D = null
var _in_drag_layer := false
var _drag_original_parent: Node = null
var _drag_original_z: int = 0

# ============= CONSTANTS =============
const DRAG_Z := 3000
const MIN_OVERLAP_AREA := 200.0
const DRAG_SCALE := 1.05
const DRAG_MODULATE := Color(1.0, 1.0, 0.85)
const HOVER_SCALE := 1.08           # Scale au hover SANS drag
const HOVER_MODULATE := Color(1.0, 1.0, 0.9)
const PREVIEW_CHECK_INTERVAL := 3   # frames

# ============= PREVIEW & SLOT =============
var _current_preview_slot: Node2D = null
var slot: Node2D = null
var _slot_cache: Array = []
var _slot_cache_valid := false
var _last_preview_frame := -1
var _is_hovered := false

# ============= BASE STATE (pour reset) =============
var _base_scale := Vector2.ONE
var _base_modulate := Color.WHITE

# ============= LIFECYCLE =============

func _ready() -> void:
	add_to_group("cards")  
	_base_scale = scale
	_base_modulate = modulate
	update_card()

func _process(_delta: float) -> void:
	if not dragging:
		return

	global_position = get_global_mouse_position() - drag_offset
	
	var frame = get_tree().get_frame()
	if frame - _last_preview_frame >= PREVIEW_CHECK_INTERVAL:
		_preview_slot_under_card()
		_last_preview_frame = frame

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			if dragging:
				_end_drag()

# ============= GAME STATE =============

func _is_game_end() -> bool:
	return Global.result.size() > 0

func _can_interact() -> bool:
	if Global.is_spectator:
		return false
	if _is_game_end():
		return false
	return true

func _can_drag() -> bool:
	if not draggable:
		return false
	if not _can_interact():
		return false
	if dragging:
		return false
	return true

# ============= VISUAL UPDATES =============

func set_card_data(v: String, c: String, d: bool, d_couleur: String, can_drag: bool = true) -> void:
	valeur = v
	couleur = c
	dos = d
	if d_couleur != "":
		dos_couleur = d_couleur
	draggable = can_drag
	update_card()

func update_card() -> void:
	if dos:
		_apply_back_visual(dos_couleur)
		_show_back()
		return

	_show_front()

	var symboles: Dictionary = {
		"coeur": "♥",
		"carreau": "♦",
		"pique": "♠",
		"trefle": "♣"
	}

	var texte_couleur: Color = Color.RED if (couleur == "coeur" or couleur == "carreau") else Color.BLACK

	$Front/Top/ValeurT.text = valeur
	$Front/Top/ValeurT.modulate = texte_couleur
	$Front/Top/SymboleT.text = String(symboles.get(couleur, "?"))
	$Front/Top/SymboleT.modulate = texte_couleur

	$Front/Bottom/ValeurB.text = valeur
	$Front/Bottom/ValeurB.modulate = texte_couleur
	$Front/Bottom/SymboleB.text = String(symboles.get(couleur, "?"))
	$Front/Bottom/SymboleB.modulate = texte_couleur

func _apply_back_visual(code: String) -> void:
	var col: Color = Color(0.2, 0.4, 1.0)
	if code == "rouge":
		col = Color(0.77, 0.435, 0.597, 1.0)
	$Back.modulate = col

func _show_front() -> void:
	$Front.visible = true
	$Back.visible = false

func _show_back() -> void:
	$Front.visible = false
	$Back.visible = true

# ============= HOVER PREVIEW (SANS DRAG) =============

func _on_area_2d_mouse_entered() -> void:
	if _can_interact() and not dragging:
		_is_hovered = true
		_apply_hover_visual()

func _on_area_2d_mouse_exited() -> void:
	_is_hovered = false
	_reset_hover_visual()

func _apply_hover_visual() -> void:
	scale = _base_scale * HOVER_SCALE
	modulate = HOVER_MODULATE

func _reset_hover_visual() -> void:
	if not dragging:
		scale = _base_scale
		modulate = _base_modulate

# ============= DRAG INPUT =============

# ✅ CORRECTION #1: Vérifier que C'EST LA TOPMOST carte
func _is_topmost_card_at_mouse() -> bool:
	var mouse_pos = get_global_mouse_position()
	var cards_group = get_tree().get_nodes_in_group("cards")
	var topmost = HitboxUtil.pick_topmost_node_at_point(cards_group, mouse_pos)
	return topmost == self

func _on_area_2d_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			# ✅ Ne draggable que si c'est la topmost
			if not _is_topmost_card_at_mouse():
				return
			
			if not _can_drag():
				return
			
			_start_drag(get_global_mouse_position())

# ============= DRAG LIFECYCLE =============

func _start_drag(mouse_pos: Vector2) -> void:
	dragging = true
	drag_offset = mouse_pos - global_position
	original_position = global_position

	_enter_drag_layer()
	_apply_drag_visual()
	_reset_hover_visual()
	
	if _current_preview_slot != null:
		_set_preview_slot(null)

func _end_drag() -> void:
	dragging = false

	if not _can_interact():
		_rollback_drag()
		return

	if _current_preview_slot != null:
		var to_slot_id: String = String(_current_preview_slot.get("slot_id"))
		if _current_preview_slot.has_method("get_slot_id"):
			to_slot_id = String(_current_preview_slot.call("get_slot_id"))
		
		_send_move_if_valid(to_slot_id)
	else:
		_rollback_drag()

	_reset_drag_visual()
	_set_preview_slot(null)

func _rollback_drag() -> void:
	_leave_drag_layer_to_original()
	global_position = original_position
	_reset_drag_visual()
	_set_preview_slot(null)

# ============= DRAG LAYER =============

func _get_drag_root() -> Node:
	var nodes := get_tree().get_nodes_in_group("drag_root")
	if nodes.size() > 0:
		return nodes[0]

	var scene := get_tree().current_scene
	if scene:
		var n := scene.get_node_or_null("DragLayer/DragRoot")
		if n:
			return n

	return null

func _enter_drag_layer() -> void:
	var drag_root := _get_drag_root()
	if drag_root == null:
		move_to_front()
		return

	_drag_original_parent = get_parent()
	_drag_original_z = z_index
	_drag_from_slot = slot

	if _drag_from_slot != null and _drag_from_slot != self and _drag_from_slot.has_method("_remove_card_ref"):
		_drag_from_slot.call("_remove_card_ref", self)

	var gpos := global_position
	reparent(drag_root)
	global_position = gpos

	drag_root.move_child(self, drag_root.get_child_count() - 1)
	z_index = DRAG_Z

	_in_drag_layer = true
	_slot_cache_valid = false

func _leave_drag_layer_to_original() -> void:
	if not _in_drag_layer:
		return

	if is_instance_valid(_drag_from_slot):
		_drag_from_slot.snap_card(self, false)
	elif _drag_original_parent != null:
		var gpos := global_position
		reparent(_drag_original_parent)
		global_position = gpos

	z_index = _drag_original_z
	_in_drag_layer = false
	_slot_cache_valid = false

# ============= VISUAL EFFECTS =============

func _apply_drag_visual() -> void:
	scale = _base_scale * DRAG_SCALE
	modulate = DRAG_MODULATE

func _reset_drag_visual() -> void:
	scale = _base_scale
	modulate = _base_modulate

# ============= PREVIEW SLOT (DRAG) =============

func _preview_slot_under_card() -> void:
	if not _slot_cache_valid:
		_slot_cache = get_tree().get_nodes_in_group("slots")
		_slot_cache_valid = true
	
	var card_rect := _get_card_rect_global()
	var best_slot: Node = null
	var best_area := 0.0

	for s in _slot_cache:
		if s == null or not is_instance_valid(s):
			continue
		
		var slot_rect: Rect2
		if s.has_method("get_cached_rect"):
			slot_rect = s.call("get_cached_rect")
		else:
			slot_rect = HitboxUtil.rect_from_collision_shape_2d(s)
		
		if slot_rect.size == Vector2.ZERO:
			continue
		
		var inter := _rect_intersection(card_rect, slot_rect)
		var area := inter.size.x * inter.size.y

		if area > best_area:
			best_area = area
			best_slot = s

	if best_area < MIN_OVERLAP_AREA:
		best_slot = null

	_set_preview_slot(best_slot)

func _set_preview_slot(new_slot: Node) -> void:
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

# ============= GEOMETRY =============

func _get_card_rect_global() -> Rect2:
	var size := Vector2(80, 120)
	var shape = $Area2D/CollisionShape2D.shape
	if shape is RectangleShape2D:
		size = (shape as RectangleShape2D).size
	return Rect2(global_position - size * 0.5, size)

func _rect_intersection(a: Rect2, b: Rect2) -> Rect2:
	var x1: float = maxf(a.position.x, b.position.x)
	var y1: float = maxf(a.position.y, b.position.y)
	var x2: float = minf(a.position.x + a.size.x, b.position.x + b.size.x)
	var y2: float = minf(a.position.y + a.size.y, b.position.y + b.size.y)

	var w: float = x2 - x1
	var h: float = y2 - y1
	if w <= 0.0 or h <= 0.0:
		return Rect2()

	return Rect2(Vector2(x1, y1), Vector2(w, h))

# ============= NETWORK =============

func get_card_id() -> String:
	if has_meta("card_id"):
		return String(get_meta("card_id"))
	return String(name)

# ✅ CORRECTION #2: Ne pas envoyer si from == to
func _send_move_if_valid(to_slot_id: String) -> void:
	if not _can_interact():
		_rollback_drag()
		return

	var from_slot_id: String = ""
	if slot != null:
		if slot.has_method("get_slot_id"):
			from_slot_id = String(slot.call("get_slot_id"))
		else:
			from_slot_id = String(slot.slot_id)

	if from_slot_id == "" or to_slot_id == "":
		_rollback_drag()
		return

	# ✅ Ignorer drop sur le même slot
	if from_slot_id == to_slot_id:
		print("[MOVE] Ignoring same slot drop: %s → %s" % [from_slot_id, to_slot_id])
		return

	var card_id: String = get_card_id()
	print("[MOVE] Sending move: %s from %s to %s" % [card_id, from_slot_id, to_slot_id])
	
	NetworkManager.request("move_request", {
		"card_id": card_id,
		"from_slot_id": from_slot_id,
		"to_slot_id": to_slot_id
	})
