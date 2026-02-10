# Slot.gd v2.2 - Fix: tri par index, slot MAIN invisible, layout cohérent

extends Area2D

const SlotIdHelper = preload("res://Client/game/helpers/slot_id.gd")

# ============= EXPORTS =============
@export var slot_id: String = ""
@export var snap_duration := 0.18

# ============= STATE =============
var stacked_cards: Array[Node] = []
var preview_active := false
var _cached_rect: Rect2 = Rect2()
var _rect_cache_dirty := true
var _is_hand_slot := false

# ============= FAN PARAMETERS (HAND layout) =============
const HAND_FAN_X_STEP := 60.0
const HAND_FAN_CENTER_LIFT := 20.0
const HAND_FAN_MAX_ANGLE_DEG := 50.0
const HAND_FAN_MAX_CARDS := 5

# ============= CASCADE PARAMETERS =============
const CASCADE_BANC := Vector2(0, 24)
const CASCADE_TABLE := Vector2(0, 0)
const CASCADE_DEFAULT := Vector2(0, 0)

# ============= PREVIEW COLORS =============
const PREVIEW_HIGHLIGHT_COLOR := Color(1, 1, 0.5)
const PREVIEW_NORMAL_COLOR := Color(1, 1, 1)
const PREVIEW_CARD_SCALE := Vector2(1.03, 1.03)

# ============= LIFECYCLE =============

func _ready() -> void:
	add_to_group("slots")
	modulate = PREVIEW_NORMAL_COLOR
	
	# ✅ Détecter slot HAND et le rendre quasi-invisible
	var parsed := SlotIdHelper.parse_slot_id(SlotIdHelper.normalize_slot_id(String(slot_id)))
	_is_hand_slot = String(parsed.get("type", "")) == "HAND"
	
	if _is_hand_slot:
		modulate = Color(1, 1, 1, 1)  # 10% opacity pour HAND

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

	# ✅ Pas de highlight pour HAND (déjà invisible)
	if not _is_hand_slot:
		$Background.modulate = PREVIEW_HIGHLIGHT_COLOR if active else PREVIEW_NORMAL_COLOR
	else:
		$Background.modulate = PREVIEW_NORMAL_COLOR

	_apply_preview_to_cards(active)

func _apply_preview_to_cards(active: bool) -> void:
	for c in stacked_cards:
		if !is_instance_valid(c):
			continue
		if !(c is Node2D):
			continue

		var n := c as Node2D

		# Modulate (highlight)
		n.modulate = Color(1.0, 1.0, 0.85) if active else Color(1, 1, 1)

		# Scale (petit boost)
		if active:
			if !n.has_meta("_preview_base_scale"):
				n.set_meta("_preview_base_scale", n.scale)
			var base_scale: Vector2 = n.get_meta("_preview_base_scale")
			n.scale = base_scale * PREVIEW_CARD_SCALE
		else:
			if n.has_meta("_preview_base_scale"):
				n.scale = n.get_meta("_preview_base_scale")
				n.remove_meta("_preview_base_scale")
			else:
				n.scale = Vector2(1, 1)

# ============= SNAP (PLACEMENT) =============

func _remove_card_ref(card: Node) -> void:
	if stacked_cards.has(card):
		stacked_cards.erase(card)

func snap_card(card: Node2D, animate: bool = true) -> void:
	# Retirer des slots précédents
	if card.slot != null and card.slot != self and card.slot.has_method("_remove_card_ref"):
		card.slot.call("_remove_card_ref", card)

	# Reparent
	if card.get_parent() != self:
		card.reparent(self, true)

	# Setter
	card.slot = self
	card.set_meta("last_slot_id", get_slot_id())
	card.visible = true	

	# Ajouter
	_remove_card_ref(card)
	stacked_cards.append(card)

	# ✅ CORRECTION #3: TRIER par index serveur si disponible
	_sort_cards_by_server_order()

	# Kill tween précédent
	if card.has_meta("_snap_tween"):
		var old_t := card.get_meta("_snap_tween") as Tween
		if old_t != null and is_instance_valid(old_t):
			old_t.kill()

	_layout_stack(animate)
	_rect_cache_dirty = true

func clear_slot() -> void:
	if stacked_cards.is_empty():
		_apply_preview_to_cards(false)
		_reset_background()
		return

	var root := get_tree().current_scene if is_inside_tree() else null
	
	for c in stacked_cards:
		if not is_instance_valid(c):
			continue
		
		if c.has_meta("_snap_tween"):
			var old_t :Tween= c.get_meta("_snap_tween")
			if old_t and is_instance_valid(old_t):
				old_t.kill()
		
		c.slot = null
		c.set_meta("last_slot_id", get_slot_id())
		c.visible = false
		
		if root:
			c.reparent(root, true)
	
	stacked_cards.clear()
	_apply_preview_to_cards(false)
	_reset_background()
	_rect_cache_dirty = true

# ============= LAYOUT =============

# ✅ CORRECTION #3: Trier par index serveur
func _sort_cards_by_server_order() -> void:
	stacked_cards.sort_custom(func(a, b):
		var idx_a = int(a.get_meta("_array_order", -1))
		var idx_b = int(b.get_meta("_array_order", -1))
		
		# Si l'un n'a pas d'index, garder l'ordre original
		if idx_a < 0 or idx_b < 0:
			return false
		
		return idx_a < idx_b
	)

func _layout_stack(animate: bool) -> void:
	var parsed := SlotIdHelper.parse_slot_id(get_slot_id())
	var stype := String(parsed.get("type", ""))
	var player_id := int(parsed.get("player", 0))

	match stype:
		"HAND":
			_layout_hand_fan(animate, player_id)
		"BENCH":
			_layout_cascade(animate, CASCADE_BANC)
		"TABLE":
			_layout_cascade(animate, CASCADE_TABLE)
		_:
			_layout_cascade(animate, CASCADE_DEFAULT)

# ✅ HAND FAN layout (ordre serveur respecté)
func _layout_hand_fan(animate: bool, player_id: int) -> void:
	var card_count = stacked_cards.size()
	
	for i in range(card_count):
		var c: Node2D = stacked_cards[i]
		if !is_instance_valid(c):
			continue

		var target_pos := Vector2.ZERO
		var target_rot := 0.0

		if card_count > 1:
			# ✅ i = index du serveur (après tri)
			var t: float = float(i) / float(card_count - 1)
			var centered: float = t * 2.0 - 1.0
			var arc: float = 1.0 - centered * centered
			
			var fan_count: int = mini(card_count, HAND_FAN_MAX_CARDS)
			var x_radius: float = HAND_FAN_X_STEP * float(maxi(1, fan_count - 1)) * 0.5
			
			# Vertical/angle sign selon player
			var vertical_sign: float = -1.0 if player_id == 1 else 1.0
			var angle_sign: float = 1.0 if player_id == 1 else -1.0
			
			# Position
			target_pos = Vector2(
				centered * x_radius,
				vertical_sign * HAND_FAN_CENTER_LIFT * arc
			)
			# Rotation
			target_rot = deg_to_rad(angle_sign * centered * HAND_FAN_MAX_ANGLE_DEG)
		else:
			target_pos = Vector2.ZERO
			target_rot = 0.0

		c.z_index = i

		if animate:
			var t := c.create_tween()
			t.set_parallel(true)
			t.tween_property(c, "position", target_pos, 0.15)
			t.tween_property(c, "rotation", target_rot, 0.15)
			c.set_meta("_snap_tween", t)
		else:
			c.position = target_pos
			c.rotation = target_rot

# ============= CASCADE layout (BENCH, TABLE) =============

func _layout_cascade(animate: bool, step: Vector2) -> void:
	for i in range(stacked_cards.size()):
		var c: Node2D = stacked_cards[i]
		if !is_instance_valid(c):
			continue

		var target_pos := step * i
		c.z_index = i

		if animate:
			var t := c.create_tween()
			t.set_parallel(true)
			t.tween_property(c, "position", target_pos, 0.12)
			t.tween_property(c, "rotation", 0.0, 0.12)
			c.set_meta("_snap_tween", t)
		else:
			c.position = target_pos
			c.rotation = 0.0

# ============= HITBOX CACHE =============

func _update_cached_rect() -> void:
	var shape_node := $CollisionShape2D
	if shape_node == null:
		_cached_rect = Rect2()
		return

	var shape = shape_node.shape
	if shape is RectangleShape2D:
		var size: Vector2 = (shape as RectangleShape2D).size
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
		$Background.modulate = PREVIEW_NORMAL_COLOR
