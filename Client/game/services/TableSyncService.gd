# Client/game/services/TableSyncService.gd
extends RefCounted
class_name TableSyncService

# ============= PROPERTIES =============
var context: GameContext = null

# ============= LIFECYCLE =============
func _init(ctx: GameContext) -> void:
	context = ctx

# ============= GUARD =============
func _is_ready() -> bool:
	return context != null and context.card_context != null

# ============= PUBLIC METHODS =============
func sync_table_slots(table: Node, slot_scene: PackedScene, allowed_table_slots: Dictionary, active_slots: Array, spacing: int = 100, start_pos: Vector2 = Vector2.ZERO) -> void:
	"""Synchronise les slots de la table"""
	if not _is_ready():
		return

	var wanted := _collect_wanted_slots(active_slots)
	_sync_allowed_table_slots(allowed_table_slots, wanted)
	_remove_stale_table_slots(table, wanted)
	_upsert_wanted_table_slots(table, slot_scene, wanted)
	update_table_positions(table, spacing, start_pos)

func update_table_positions(table: Node, spacing: int = 100, start_pos: Vector2 = Vector2.ZERO) -> void:
	"""Positionne les slots de la table"""
	if not _is_ready():
		return

	var slots := _collect_live_table_slots(table)
	if slots.is_empty():
		return

	_sort_table_slots_by_index(slots)
	_position_table_slots(slots, spacing, start_pos)

# ============= PRIVATE HELPERS =============
func _collect_wanted_slots(active_slots: Array) -> Dictionary:
	"""Collecte les slots souhaités"""
	var wanted: Dictionary = {}
	for s in active_slots:
		var normalized := SlotIdHelper.normalize_slot_id(String(s))
		if normalized != "":
			wanted[normalized] = true
	return wanted

func _sync_allowed_table_slots(allowed_table_slots: Dictionary, wanted: Dictionary) -> void:
	"""Met à jour la liste des slots autorisés"""
	allowed_table_slots.clear()
	for slot_id in wanted.keys():
		allowed_table_slots[slot_id] = true

func _remove_stale_table_slots(table: Node, wanted: Dictionary) -> void:
	"""Supprime les slots de table qui ne sont plus actifs"""
	if not _is_ready():
		return

	for child in table.get_children():
		if not is_instance_valid(child):
			continue
		var slot_id_val = String(child.slot_id) if "slot_id" in child else ""
		var cid := SlotIdHelper.normalize_slot_id(slot_id_val)
		if not SlotIdHelper.is_table_slot_id(cid):
			continue
		if wanted.has(cid):
			continue

		if child.has_method("clear_slot"):
			child.clear_slot()

		if context.card_context.slots_by_id != null:
			context.card_context.slots_by_id.erase(cid)

		if child.get_parent() == table:
			table.remove_child(child)
		child.queue_free()

func _upsert_wanted_table_slots(table: Node, slot_scene: PackedScene, wanted: Dictionary) -> void:
	"""Crée ou met à jour les slots de table"""
	if not _is_ready() or context.card_context.slots_by_id == null:
		return

	for slot_id in wanted.keys():
		var node_name := SlotIdHelper.slot_node_name(slot_id)
		var existing := table.get_node_or_null(node_name)

		if existing != null and existing is Node and existing.is_queued_for_deletion():
			if existing.get_parent() == table:
				table.remove_child(existing)
			existing = null

		if existing == null:
			var slot := slot_scene.instantiate()
			slot.name = node_name
			slot.slot_id = slot_id
			table.add_child(slot)
			context.card_context.slots_by_id[slot_id] = slot
		else:
			existing.slot_id = slot_id
			context.card_context.slots_by_id[slot_id] = existing

func _collect_live_table_slots(table: Node) -> Array:
	"""Collecte les slots de table actifs"""
	var slots: Array = []
	for child in table.get_children():
		if not is_instance_valid(child) or child.is_queued_for_deletion():
			continue
		var slot_id_val = String(child.slot_id) if "slot_id" in child else ""
		var cid := SlotIdHelper.normalize_slot_id(slot_id_val)
		if SlotIdHelper.is_table_slot_id(cid):
			slots.append(child)
	return slots

func _sort_table_slots_by_index(slots: Array) -> void:
	"""Trie les slots par index"""
	slots.sort_custom(func(a, b):
		var slot_id_a = String(a.slot_id) if is_instance_valid(a) and "slot_id" in a else ""
		var slot_id_b = String(b.slot_id) if is_instance_valid(b) and "slot_id" in b else ""
		var index_a = _extract_table_index(SlotIdHelper.normalize_slot_id(slot_id_a))
		var index_b = _extract_table_index(SlotIdHelper.normalize_slot_id(slot_id_b))
		return index_a < index_b
	)

func _position_table_slots(slots: Array, spacing: int, start_pos: Vector2) -> void:
	"""Positionne les slots sur la table"""
	if slots.is_empty():
		return

	var start_offset := -float(slots.size() - 1) / 2.0 * spacing
	for i in range(slots.size()):
		slots[i].position = start_pos + Vector2(start_offset + i * spacing, 0)
		if slots[i].has_method("invalidate_rect_cache"):
			slots[i].call("invalidate_rect_cache")

func _extract_table_index(slot_id: String) -> int:
	"""Extrait l'index d'un slot de table"""
	var parsed := SlotIdHelper.parse_slot_id(slot_id)
	if parsed.is_empty():
		return 0
	if String(parsed.get("type", "")) != "TABLE":
		return 0
	return int(parsed.get("index", 0))
