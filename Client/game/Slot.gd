#slot.gd v1.1
extends Area2D
const SlotIdHelper = preload("res://Client/game/helpers/slot_id.gd")

@export var slot_id: String = ""
@export var snap_duration := 0.18

var stacked_cards: Array[Node] = []

var preview_active := false

const CASCADE_BANC := Vector2(0, 24)
const CASCADE_TABLE := Vector2(0, 0)
const CASCADE_MAIN := Vector2(85, 0)
const CASCADE_DEFAULT := Vector2(0, 0)

func _ready():
	add_to_group("slots")
	modulate = Color(1, 1, 1)

func get_slot_id() -> String:
	return SlotIdHelper.normalize_slot_id(String(slot_id))
# ---------------------------------------------------------
# PREVIEW (sur Background + cartes)
# ---------------------------------------------------------
func on_card_enter_preview() -> void:
	_set_preview(true)

func on_card_exit_preview() -> void:
	_set_preview(false)

func _set_preview(active: bool) -> void:
	if preview_active == active:
		return
	preview_active = active

	# Background
	$Background.modulate = Color(1, 1, 0.5) if active else Color(1, 1, 1)

	# ✅ Appliquer un effet sur les cartes du slot
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

		# Scale (sans casser si la carte avait déjà un scale)
		if active:
			if !n.has_meta("_preview_base_scale"):
				n.set_meta("_preview_base_scale", n.scale)
			var base_scale: Vector2 = n.get_meta("_preview_base_scale")
			n.scale = base_scale * Vector2(1.03, 1.03)
		else:
			if n.has_meta("_preview_base_scale"):
				n.scale = n.get_meta("_preview_base_scale")
				n.remove_meta("_preview_base_scale")
			else:
				n.scale = Vector2(1, 1)

# ---------------------------------------------------------
# SNAP (le serveur décide, le client applique)
# ---------------------------------------------------------
func _remove_card_ref(card: Node) -> void:
	if stacked_cards.has(card):
		stacked_cards.erase(card)

func snap_card(card: Node2D, animate: bool = true) -> void:
	# Retirer des refs du slot précédent (important pour clear_slot)
	if card.slot != null and card.slot != self and card.slot.has_method("_remove_card_ref"):
		card.slot.call("_remove_card_ref", card)

	# Reparent en conservant la position globale => départ d'animation = slot source
	if card.get_parent() != self:
		card.reparent(self, true) # keep_global_transform = true

	# ✅ toujours setter
	card.slot = self
	card.set_meta("last_slot_id", get_slot_id())

	card.visible = true	

	# Maintenir l'ordre de stack en fonction de l'ordre des updates serveur
	_remove_card_ref(card)
	stacked_cards.append(card)

	# Tuer un tween précédent si présent
	if card.has_meta("_snap_tween"):
		var old_t := card.get_meta("_snap_tween") as Tween
		if old_t != null and is_instance_valid(old_t):
			old_t.kill()

	_layout_stack(animate)

func clear_slot() -> void:
	if stacked_cards.is_empty():
		_apply_preview_to_cards(false)
		$Background.modulate = Color(1, 1, 1)
		return
	var root := get_tree().current_scene if is_inside_tree() else null
	for c in stacked_cards:
		if not is_instance_valid(c):
			continue
		if c.has_meta("_snap_tween"):
			var old_t :Tween = c.get_meta("_snap_tween")
			if old_t and is_instance_valid(old_t):
				old_t.kill()
		c.slot = null
		c.set_meta("last_slot_id", get_slot_id()) # slot_id du slot qu'on est en train de clear
		c.slot = null
		c.visible = false
		if root:
			c.reparent(root, true) # keep_global_transform = true
	stacked_cards.clear()
	_apply_preview_to_cards(false)
	$Background.modulate = Color(1, 1, 1)

# ---------------------------------------------------------
# LAYOUT
# ---------------------------------------------------------
func _layout_stack(animate: bool) -> void:
	var step := CASCADE_DEFAULT
	var base_offset := Vector2.ZERO
	var parsed := SlotIdHelper.parse_slot_id(get_slot_id())
	var stype := String(parsed.get("type", ""))

	if stype == "BENCH":
		step = CASCADE_BANC
	elif stype == "HAND":
		step = CASCADE_MAIN
		# Centre la main autour du slot (sinon ça part juste vers la droite)
		var n := stacked_cards.size()
		if n > 1:
			base_offset = -step * float(n - 1) * 0.5
	elif stype == "TABLE":
		step = CASCADE_TABLE

	for i in range(stacked_cards.size()):
		var c: Node2D = stacked_cards[i]
		if !is_instance_valid(c):
			continue

		var target_pos := base_offset + (step * i)
		c.z_index = i

		if animate:
			var t := c.create_tween()
			t.tween_property(c, "position", target_pos, 0.12)
		else:
			c.position = target_pos
