extends Node2D

# ============= CONSTANTS =============
const DRAG_Z := 3000
const MIN_OVERLAP_AREA := 200.0
const DRAG_SCALE := 1.05
const HOVER_SCALE := 1.08
const PREVIEW_CHECK_INTERVAL := 3
const PREVIEW_CARD_GLOW_COLOR := Color(0.35, 0.95, 0.45, 0.45)
const PREVIEW_CARD_GLOW_SIZE := 6
const BACK_TEXTURE_DECK_A := preload("res://DosA.png")
const BACK_TEXTURE_DECK_B := preload("res://DosB.png")

# ============= EXPORTS =============
@export var valeur: String = ""
@export var couleur: String = ""
@export var dos: bool = false
@export var dos_couleur: String = "bleu"
@export var draggable: bool = true

# ============= STATES =============
enum CardState {
	IDLE,
	HOVER,
	HOVER_TOP,
	DRAG,
	PREVIEW_SLOT,
	DROP
}

var state: CardState = CardState.IDLE

# ============= DRAG STATE =============
var dragging := false
var drag_offset := Vector2.ZERO
var original_position := Vector2.ZERO
var _drag_from_slot: Node2D = null
var _in_drag_layer := false
var _drag_original_parent: Node = null
var _drag_original_z := 0

# ============= PREVIEW & SLOT =============
var _current_preview_slot: Node2D = null
var _current_preview_card: Node2D = null  # ← NOUVEAU : carte en preview
var slot: Node2D = null
var _slot_cache: Array = []
var _slot_cache_valid := false
var _last_preview_frame := -1

# ============= BASE STATE =============
var _base_scale := Vector2.ONE

# ============= LIFECYCLE =============
func _ready() -> void:
	add_to_group("cards")
	_base_scale = scale
	update_card()

func _process(_delta: float) -> void:
	if state == CardState.DRAG or state == CardState.PREVIEW_SLOT:
		global_position = get_global_mouse_position() - drag_offset

		var frame = get_tree().get_frame()
		if frame - _last_preview_frame >= PREVIEW_CHECK_INTERVAL:
			_preview_slot_under_card()
			_preview_card_under_card()  # ← NOUVEAU : détect cartes aussi
			_last_preview_frame = frame
	else:
		# ===== HOVER STATE MANAGEMENT =====
		_update_hover_state()

# ============= PREVIEW CARD (VISUAL FEEDBACK) =============
func _preview_card_under_card() -> void:
	var card_rect = _get_card_rect_global()
	var cards_group = get_tree().get_nodes_in_group("cards")
	
	var best_card: Node2D = null
	var best_overlap := 0.0
	
	for card in cards_group:
		if not (card is Node2D):
			continue
		if card == self:  # Ignore self
			continue
		if not is_instance_valid(card):
			continue
		if not card.has_method("_get_card_rect_global"):
			continue
		
		var other_rect: Rect2 = card.call("_get_card_rect_global")
		var intersection = _rect_intersection(card_rect, other_rect)
		var overlap_area = intersection.get_area()
		
		if overlap_area > best_overlap:
			best_overlap = overlap_area
			best_card = card
	
	# Si overlap suffisant, on highlight
	if best_overlap >= MIN_OVERLAP_AREA:
		_set_preview_card(best_card)
	else:
		_set_preview_card(null)

func _set_preview_card(card: Node2D) -> void:
	# Si c'est la même, rien à faire
	if _current_preview_card == card:
		return
	
	# Reset l'ancienne carte
	if _current_preview_card != null and is_instance_valid(_current_preview_card):
		_current_preview_card._reset_card_preview()
	
	# Set la nouvelle
	_current_preview_card = card
	if _current_preview_card != null and is_instance_valid(_current_preview_card):
		_current_preview_card._highlight_card_preview()

# ============= VISUAL METHODS =============
func _highlight_card_preview() -> void:
	"""Applique un glow léger pendant le drag"""
	_set_border_glow($Front/Bord, true)
	_set_border_glow($Back/Bord, true)

func _reset_card_preview() -> void:
	"""Retire le glow et restaure l'état normal"""
	_set_border_glow($Front/Bord, false)
	_set_border_glow($Back/Bord, false)
	_apply_border_visual(dos_couleur)

func _set_border_glow(bord: Panel, enabled: bool) -> void:
	if bord == null:
		return

	var style = bord.get_theme_stylebox("panel")
	if style and style is StyleBoxFlat:
		# Le glow est une ombre diffuse: on garde la couleur du bord inchangée.
		var new_style = style.duplicate()
		new_style.shadow_size = PREVIEW_CARD_GLOW_SIZE if enabled else 0
		new_style.shadow_color = PREVIEW_CARD_GLOW_COLOR if enabled else Color(0, 0, 0, 0)
		new_style.shadow_offset = Vector2.ZERO
		bord.add_theme_stylebox_override("panel", new_style)
		
func _update_hover_state() -> void:
	# Si on ne peut pas interagir, forcer IDLE
	if not _can_interact() or dragging:
		if state != CardState.IDLE:
			set_state(CardState.IDLE)
		return

	# Vérifier si la souris est topmost sur cette carte
	if _is_topmost_card_at_mouse():
		# Passer en HOVER_TOP si on n'y est pas
		if state != CardState.HOVER_TOP:
			set_state(CardState.HOVER_TOP)
	else:
		# Pas topmost → IDLE
		if state == CardState.HOVER_TOP or state == CardState.HOVER:
			set_state(CardState.IDLE)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			if state == CardState.DRAG or state == CardState.PREVIEW_SLOT:
				_end_drag()

# ============= STATE MACHINE =============
func set_state(new_state: CardState) -> void:
	if state == new_state:
		return

	_exit_state(state)
	state = new_state
	_enter_state(state)

func _enter_state(s: CardState) -> void:
	match s:
		CardState.IDLE:
			scale = _base_scale

		CardState.HOVER:
			scale = _base_scale * HOVER_SCALE

		CardState.HOVER_TOP:
			scale = _base_scale * HOVER_SCALE

		CardState.DRAG:
			scale = _base_scale * DRAG_SCALE

		CardState.PREVIEW_SLOT:
			# Preview slot = aucun effet sur la carte
			scale = _base_scale * DRAG_SCALE

		CardState.DROP:
			scale = _base_scale

func _exit_state(_s: CardState) -> void:
	pass

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
	return draggable and _can_interact() and not dragging

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
	_apply_back_visual(dos_couleur)
	_apply_border_visual(dos_couleur)

	if dos:
		_show_back()
		return

	_show_front()

	var symboles := {
		"coeur": "♥",
		"carreau": "♦",
		"pique": "♠",
		"trefle": "♣"
	}

	var texte_couleur := Color.RED if (couleur == "coeur" or couleur == "carreau") else Color.BLACK

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
	var col := Color(0.2, 0.4, 1.0)
	if code == "rouge":
		col = Color(0.77, 0.435, 0.597, 1.0)
	return col

func _get_back_texture(code: String) -> Texture2D:
	if code == "rouge":
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
	var mouse_pos = get_global_mouse_position()
	var cards_group = get_tree().get_nodes_in_group("cards")
	var topmost := _pick_topmost_node_at_point(cards_group, mouse_pos)
	return topmost == self

# ============= DRAG INPUT =============
func _on_area_2d_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
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
	set_state(CardState.DRAG)

	if _current_preview_slot != null:
		_set_preview_slot(null)

func _end_drag() -> void:
	dragging = false
	
	# Reset preview card
	_set_preview_card(null)
	# Recalculer une dernière fois le slot sous la carte au moment du release.
	# Evite les drops ratés si PREVIEW_CHECK_INTERVAL n'a pas encore rafraichi.
	_preview_slot_under_card(true)

	if not _can_interact():
		_rollback_drag()
		return

	if _current_preview_slot != null:
		var to_slot_id := ""
		if _current_preview_slot.has_method("get_slot_id"):
			to_slot_id = String(_current_preview_slot.call("get_slot_id"))
		else:
			to_slot_id = String(_current_preview_slot.get("slot_id"))

		_send_move_if_valid(to_slot_id)
	else:
		_rollback_drag()

	set_state(CardState.DROP)
	_set_preview_slot(null)

func _rollback_drag() -> void:
	_set_preview_card(null)  # ← Reset card preview aussi
	_leave_drag_layer_to_original()
	global_position = original_position
	set_state(CardState.IDLE)
	_set_preview_slot(null)

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
	z_index = DRAG_Z

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
func _preview_slot_under_card(ignore_topmost: bool = false) -> void:
	# 🔥 Ne preview que si la carte est topmost sous la souris
	if not ignore_topmost and not _is_topmost_card_at_mouse():
		_set_preview_slot(null)
		return

	if not _slot_cache_valid:
		_slot_cache = get_tree().get_nodes_in_group("slots")
		_slot_cache_valid = true

	var card_rect = _get_card_rect_global()
	var best_slot: Node = null
	var best_area := 0.0

	for s in _slot_cache:
		if s == null or not is_instance_valid(s):
			continue

		var slot_rect: Rect2
		if s.has_method("get_cached_rect"):
			slot_rect = s.call("get_cached_rect")
		else:
			if s is Node2D:
				slot_rect = _rect_from_collision_shape_node(s as Node2D)
			else:
				slot_rect = Rect2()

		if slot_rect.size == Vector2.ZERO:
			continue

		var inter = _rect_intersection(card_rect, slot_rect)
		var area = inter.size.x * inter.size.y

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

		set_state(CardState.PREVIEW_SLOT if new_slot != null else CardState.DRAG)

# ============= GEOMETRY =============
func _get_card_rect_global() -> Rect2:
	var size := Vector2(80, 120)
	var shape = $Area2D/CollisionShape2D.shape
	if shape is RectangleShape2D:
		size = (shape as RectangleShape2D).size
	return Rect2(global_position - size * 0.5, size)

func _rect_intersection(a: Rect2, b: Rect2) -> Rect2:
	var x1 = maxf(a.position.x, b.position.x)
	var y1 = maxf(a.position.y, b.position.y)
	var x2 = minf(a.position.x + a.size.x, b.position.x + b.size.x)
	var y2 = minf(a.position.y + a.size.y, b.position.y + b.size.y)

	var w = x2 - x1
	var h = y2 - y1
	if w <= 0.0 or h <= 0.0:
		return Rect2()

	return Rect2(Vector2(x1, y1), Vector2(w, h))

func _rect_from_collision_shape_node(node: Node2D) -> Rect2:
	if node == null:
		return Rect2()

	var shape_node := node.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null:
		shape_node = node.find_child("CollisionShape2D", true, false) as CollisionShape2D
	if shape_node == null:
		return Rect2()

	var shape := shape_node.shape
	if shape is RectangleShape2D:
		var size := (shape as RectangleShape2D).size
		var scale := shape_node.global_transform.get_scale()
		var scaled := Vector2(size.x * absf(scale.x), size.y * absf(scale.y))
		return Rect2(shape_node.global_position - scaled * 0.5, scaled)
	return Rect2()

func _contains_global_point(node: Node2D, global_point: Vector2) -> bool:
	var rect := _rect_from_collision_shape_node(node)
	if rect.size == Vector2.ZERO:
		return false
	return rect.has_point(global_point)

func _pick_topmost_node_at_point(candidates: Array, global_point: Vector2) -> Node2D:
	var best: Node2D = null
	var best_z := -2147483648
	var best_order := -2147483648

	for item in candidates:
		if not (item is Node2D):
			continue
		var node := item as Node2D
		if not is_instance_valid(node):
			continue
		if not _contains_global_point(node, global_point):
			continue

		var node_z := node.z_index
		var node_order := node.get_index()
		if best == null:
			best = node
			best_z = node_z
			best_order = node_order
			continue

		if node_z > best_z or (node_z == best_z and node_order > best_order):
			best = node
			best_z = node_z
			best_order = node_order

	return best

# ============= NETWORK =============
func get_card_id() -> String:
	if has_meta("card_id"):
		return String(get_meta("card_id"))
	return String(name)

func _send_move_if_valid(to_slot_id: String) -> void:
	if not _can_interact():
		_rollback_drag()
		return

	var from_slot_id := ""
	if slot != null:
		if slot.has_method("get_slot_id"):
			from_slot_id = String(slot.call("get_slot_id"))
		else:
			from_slot_id = String(slot.slot_id)

	if from_slot_id == "" or to_slot_id == "":
		_rollback_drag()
		return

	if from_slot_id == to_slot_id:
		print("[MOVE] Ignoring same slot drop: %s → %s" % [from_slot_id, to_slot_id])
		_rollback_drag()
		return

	var card_id := get_card_id()
	print("[MOVE] Sending move: %s from %s to %s" % [card_id, from_slot_id, to_slot_id])

	NetworkManager.request("move_request", {
		"card_id": card_id,
		"from_slot_id": from_slot_id,
		"to_slot_id": to_slot_id
	})
