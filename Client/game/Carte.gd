#Carte.gd v1.2

extends Node2D

@export var valeur: String = ""
@export var couleur: String = ""
@export var dos: bool = false
@export var dos_couleur: String = "bleu"
@export var draggable: bool = true

var dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var original_position: Vector2 = Vector2.ZERO

var _drag_from_slot: Node2D = null
var _in_drag_layer := false
var _drag_original_parent: Node = null
var _drag_original_z: int = 0

const DRAG_Z := 3000
const MIN_OVERLAP_AREA := 200.0

var _current_preview_slot: Node2D = null
var slot: Node2D = null

var _slot_cache: Array = []
var _slot_cache_valid := false
var _last_drag_frame := -1

const HitboxUtil = preload("res://Client/game/helpers/hitbox.gd")

func _ready() -> void:
	update_card()

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

func _can_drag() -> bool:
	if not draggable:
		return false
	if not _can_interact():
		return false
	if dragging:
		return false
	return true

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

func _is_game_end() -> bool:
	return Global.result.size() > 0

func _can_interact() -> bool:
	if Global.is_spectator:
		return false
	if _is_game_end():
		return false
	return true


func _on_area_2d_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if not _can_drag():
				return
			_start_drag(get_global_mouse_position())

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			if dragging:
				_end_drag()

func _process(_delta: float) -> void:
	if not dragging:
		return

	global_position = get_global_mouse_position() - drag_offset
	
	var frame = get_tree().get_frame()
	if frame - _last_drag_frame >= 2:
		_preview_slot_under_card()
		_last_drag_frame = frame

func _start_drag(mouse_pos: Vector2) -> void:
	dragging = true
	drag_offset = mouse_pos - global_position
	original_position = global_position

	_enter_drag_layer()

	if _current_preview_slot != null:
		if _current_preview_slot.has_method("_set_preview"):
			_current_preview_slot.call("_set_preview", false)
		elif _current_preview_slot.has_method("on_card_exit_preview"):
			_current_preview_slot.call("on_card_exit_preview")
	_current_preview_slot = null

func _rollback_drag() -> void:
	_leave_drag_layer_to_original()
	global_position = original_position

	if _current_preview_slot != null and _current_preview_slot.has_method("on_card_exit_preview"):
		_current_preview_slot.call("on_card_exit_preview")
	_current_preview_slot = null

func _end_drag() -> void:
	dragging = false

	if not _can_interact():
		_rollback_drag()
		return

	if _current_preview_slot != null:
		var to_slot_id: String = String(_current_preview_slot.get("slot_id"))
		if _current_preview_slot.has_method("get_slot_id"):
			to_slot_id = String(_current_preview_slot.call("get_slot_id"))
		send_move_card_to_server(get_card_id(), to_slot_id)
	else:
		_rollback_drag()

	if _current_preview_slot != null:
		if _current_preview_slot.has_method("on_card_exit_preview"):
			_current_preview_slot.call("on_card_exit_preview")
	_current_preview_slot = null

func get_card_id() -> String:
	if has_meta("card_id"):
		return String(get_meta("card_id"))
	return String(name)

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


func send_move_card_to_server(card_id: String, new_slot_id: String) -> void:
	if _move_pending:
		print("[CARD] Move already pending, ignoring duplicate request")
		return
	
	if not _can_interact():
		_rollback_drag()
		return

	var from_slot_id: String = ""
	if slot != null:
		if slot.has_method("get_slot_id"):
			from_slot_id = String(slot.call("get_slot_id"))
		else:
			from_slot_id = String(slot.slot_id)

	if from_slot_id == "" or new_slot_id == "":
		_rollback_drag()
		return

	_move_pending = true
	_start_move_timeout()

	print("[CARD] Sending move request: %s -> %s" % [from_slot_id, new_slot_id])
	
	NetworkManager.request("move_request", {
		"card_id": card_id,
		"from_slot_id": from_slot_id,
		"to_slot_id": new_slot_id
	})

func _start_move_timeout() -> void:
	_clear_move_timeout()
	_move_request_timeout = Timer.new()
	add_child(_move_request_timeout)
	_move_request_timeout.one_shot = true
	_move_request_timeout.wait_time = 5.0  # 5s timeout
	_move_request_timeout.timeout.connect(_on_move_timeout)
	_move_request_timeout.start()

func _on_move_timeout() -> void:
	print("[CARD] Move request timeout, resetting pending flag")
	_clear_move_timeout()
	_move_pending = false

func _clear_move_timeout() -> void:
	if _move_request_timeout:
		_move_request_timeout.queue_free()
		_move_request_timeout = null

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_clear_move_timeout()
# Ajouter à Carte.gd

func _reset_move_pending() -> void:
	_move_pending = false
	_clear_move_timeout()
	print("[CARD] Move pending flag reset")
