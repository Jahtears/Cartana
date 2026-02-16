# Slot.gd - Refactorisé sans redondances
extends Area2D

const SlotIdHelper = preload("res://Client/game/helpers/slot_id.gd")
const HitboxUtil = preload("res://Client/game/helpers/hitbox.gd")
const GameLayoutConfig = preload("res://Client/game/GameLayoutConfig.gd")

# ============= EXPORTS =============
@export var slot_id: String = ""
@export var snap_duration: float = GameLayoutConfig.SNAP_DURATION

# ============= STATE =============
var stacked_cards: Array[Node] = []
var preview_active: bool = false
var _cached_rect: Rect2 = Rect2()
var _rect_cache_dirty: bool = true
var _is_hand_slot: bool = false

# ============= LIFECYCLE =============

func _ready() -> void:
	add_to_group("slots")
	modulate = GameLayoutConfig.PREVIEW_NORMAL_COLOR

func _process(_delta: float) -> void:
	if _rect_cache_dirty:
		_update_cached_rect()
		_rect_cache_dirty = false

# ============= PUBLIC API =============

func get_slot_id() -> String:
	return SlotIdHelper.normalize_slot_id(String(slot_id))

func get_cached_rect() -> Rect2:
	if _rect_cache_dirty:
		_update_cached_rect()
	return _cached_rect

# ============= PREVIEW (VISUAL FEEDBACK) =============

func on_card_enter_preview() -> void:
	_set_preview(true)

func on_card_exit_preview() -> void:
	_set_preview(false)

func _set_preview(active: bool) -> void:
	if preview_active == active:
		return
	preview_active = active
	$Background.modulate = GameLayoutConfig.PREVIEW_HIGHLIGHT_COLOR if active else GameLayoutConfig.PREVIEW_NORMAL_COLOR

# ============= SNAP (PLACEMENT) =============

func _remove_card_ref(card: Node) -> void:
	if stacked_cards.has(card):
		stacked_cards.erase(card)

func snap_card(card: Node2D, animate: bool = true) -> void:
	if card.slot != null and card.slot != self and card.slot.has_method("_remove_card_ref"):
		card.slot.call("_remove_card_ref", card)

	if card.get_parent() != self:
		card.reparent(self, true)

	card.slot = self
	card.set_meta("last_slot_id", get_slot_id())
	card.visible = true

	_remove_card_ref(card)
	stacked_cards.append(card)
	_sort_stacked_cards_by_server_order()

	if card.has_meta("_snap_tween"):
		var old_t := card.get_meta("_snap_tween") as Tween
		if old_t != null and is_instance_valid(old_t):
			old_t.kill()

	_layout_stack(animate)
	_rect_cache_dirty = true

func _sort_stacked_cards_by_server_order() -> void:
	if stacked_cards.size() <= 1:
		return

	stacked_cards.sort_custom(func(a, b):
		var ao := 2147483647
		var bo := 2147483647
		if a is Node and (a as Node).has_meta("_server_array_order"):
			ao = int((a as Node).get_meta("_server_array_order"))
		if b is Node and (b as Node).has_meta("_server_array_order"):
			bo = int((b as Node).get_meta("_server_array_order"))
		return ao < bo
	)

func finalize_server_sync() -> void:
	_sort_stacked_cards_by_server_order()
	_layout_stack(false)

func clear_slot() -> void:
	if stacked_cards.is_empty():
		_reset_background()
		return

	var root := get_tree().current_scene if is_inside_tree() else null

	for c in stacked_cards:
		if not is_instance_valid(c):
			continue

		if c.has_meta("_snap_tween"):
			var old_t := c.get_meta("_snap_tween") as Tween
			if old_t and is_instance_valid(old_t):
				old_t.kill()

		c.slot = null
		c.set_meta("last_slot_id", get_slot_id())
		c.visible = false

		if root:
			c.reparent(root, true)

	stacked_cards.clear()
	_reset_background()
	_rect_cache_dirty = true

# ============= LAYOUT =============

func _layout_stack(animate: bool) -> void:
	var parsed := SlotIdHelper.parse_slot_id(get_slot_id())
	var stype := String(parsed.get("type", ""))
	var player_id := int(parsed.get("player", 0))

	match stype:
		"HAND":
			_layout_hand_fan(animate, player_id)
		"BENCH":
			_layout_cascade(animate, GameLayoutConfig.CASCADE_BANC)
		"TABLE":
			_layout_cascade(animate, GameLayoutConfig.CASCADE_TABLE)
		_:
			_layout_cascade(animate, GameLayoutConfig.CASCADE_DEFAULT)

func _layout_hand_fan(animate: bool, player_id: int) -> void:
	var card_count: int = stacked_cards.size()

	for i in range(card_count):
		var c := stacked_cards[i] as Node2D
		if c == null or !is_instance_valid(c):
			continue
		c.z_index = i

		var target_pos := Vector2.ZERO
		var target_rot := 0.0

		if card_count > 1:
			var t: float = float(i) / float(card_count - 1)
			var centered: float = t * 2.0 - 1.0
			var arc: float = 1.0 - centered * centered

			var fan_count: int = mini(card_count, GameLayoutConfig.HAND_FAN_MAX_CARDS)
			var x_radius: float = GameLayoutConfig.HAND_FAN_X_STEP * float(maxi(1, fan_count - 1)) * 0.5

			var vertical_sign: float = -1.0 if player_id == 1 else 1.0
			var angle_sign: float = 1.0 if player_id == 1 else -1.0

			target_pos = Vector2(
				centered * x_radius,
				vertical_sign * GameLayoutConfig.HAND_FAN_CENTER_LIFT * arc
			)
			target_rot = deg_to_rad(angle_sign * centered * GameLayoutConfig.HAND_FAN_MAX_ANGLE_DEG)
		else:
			target_pos = Vector2.ZERO
			target_rot = 0.0

		_snap_card_position(c, target_pos, target_rot, animate)

func _layout_cascade(animate: bool, cascade_offset: Vector2) -> void:
	var count: int = stacked_cards.size()
	for i in range(count):
		var c := stacked_cards[i] as Node2D
		if c == null or !is_instance_valid(c):
			continue
		c.z_index = i
		var target_pos: Vector2 = cascade_offset * i
		_snap_card_position(c, target_pos, 0.0, animate)

func _snap_card_position(card: Node2D, target_pos: Vector2, target_rot: float, animate: bool) -> void:
	if not animate:
		card.position = target_pos
		card.rotation = target_rot
		card.scale = Vector2.ONE
		return

	if card.has_meta("_snap_tween"):
		var old_t := card.get_meta("_snap_tween") as Tween
		if old_t != null and is_instance_valid(old_t):
			old_t.kill()

	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_parallel(true)
	tween.tween_property(card, "position", target_pos, snap_duration)
	tween.tween_property(card, "rotation", target_rot, snap_duration)
	tween.tween_property(card, "scale", Vector2.ONE, snap_duration)
	card.set_meta("_snap_tween", tween)

# ============= RECT CACHE =============

func _update_cached_rect() -> void:
	var shape_node := $CollisionShape2D as CollisionShape2D
	if shape_node == null:
		_cached_rect = Rect2()
		return

	var shape := shape_node.shape
	if shape is RectangleShape2D:
		var rect_shape := shape as RectangleShape2D
		var size: Vector2 = rect_shape.size
		var scale: Vector2 = shape_node.global_transform.get_scale()
		var scaled: Vector2 = Vector2(size.x * absf(scale.x), size.y * absf(scale.y))
		_cached_rect = Rect2(shape_node.global_position - scaled * 0.5, scaled)
	else:
		_cached_rect = Rect2()

func invalidate_rect_cache() -> void:
	_rect_cache_dirty = true

# ============= HELPERS =============

func _reset_background() -> void:
	if _is_hand_slot:
		$Background.modulate = Color(1, 1, 1, 0.1)
	else:
		$Background.modulate = GameLayoutConfig.PREVIEW_NORMAL_COLOR
