# table_sync.gd - Refactorisé
extends RefCounted
class_name TableSyncHelper

const SlotIdHelper = preload("res://Client/game/helpers/slot_id.gd")

static func sync_table_slots(table: Node, slot_scene: PackedScene, slots_by_id: Dictionary, allowed_table_slots: Dictionary, active_slots: Array, spacing: int = 100, start_pos: Vector2 = Vector2.ZERO) -> void:
	"""Synchronise les slots de la table"""
	var wanted := _collect_wanted_slots(active_slots)
	_sync_allowed_table_slots(allowed_table_slots, wanted)
	_remove_stale_table_slots(table, slots_by_id, wanted)
	_upsert_wanted_table_slots(table, slot_scene, slots_by_id, wanted)

	update_table_positions(table, spacing, start_pos)

static func update_table_positions(table: Node, spacing: int = 100, start_pos: Vector2 = Vector2.ZERO) -> void:
	"""Positionne les slots de la table"""
	var slots := _collect_live_table_slots(table)
	if slots.is_empty():
		return

	_sort_table_slots_by_index(slots)
	_position_table_slots(slots, spacing, start_pos)

static func extract_table_index(slot_id: String) -> int:
	"""Extrait l'index d'un slot de table"""
	var parsed := SlotIdHelper.parse_slot_id(slot_id)
	if parsed.is_empty():
		return 0
	if String(parsed.get("type", "")) != "TABLE":
		return 0
	return int(parsed.get("index", 0))

static func _collect_wanted_slots(active_slots: Array) -> Dictionary:
	var wanted: Dictionary = {}
	for s in active_slots:
		var normalized := SlotIdHelper.normalize_slot_id(String(s))
		if normalized != "":
			wanted[normalized] = true
	return wanted

static func _sync_allowed_table_slots(allowed_table_slots: Dictionary, wanted: Dictionary) -> void:
	allowed_table_slots.clear()
	for slot_id in wanted.keys():
		allowed_table_slots[slot_id] = true

static func _remove_stale_table_slots(table: Node, slots_by_id: Dictionary, wanted: Dictionary) -> void:
	for child in table.get_children():
		var cid := SlotIdHelper.normalize_slot_id(String(child.get("slot_id")))
		if not SlotIdHelper.is_table_slot_id(cid):
			continue
		if wanted.has(cid):
			continue
		if child.has_method("clear_slot"):
			child.clear_slot()
		slots_by_id.erase(cid)
		if child.get_parent() == table:
			table.remove_child(child)
		child.queue_free()

static func _upsert_wanted_table_slots(table: Node, slot_scene: PackedScene, slots_by_id: Dictionary, wanted: Dictionary) -> void:
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
			slots_by_id[slot_id] = slot
		else:
			existing.slot_id = slot_id
			slots_by_id[slot_id] = existing

static func _collect_live_table_slots(table: Node) -> Array:
	var slots: Array = []
	for child in table.get_children():
		if child is Node and child.is_queued_for_deletion():
			continue
		var cid := SlotIdHelper.normalize_slot_id(String(child.get("slot_id")))
		if SlotIdHelper.is_table_slot_id(cid):
			slots.append(child)
	return slots

static func _sort_table_slots_by_index(slots: Array) -> void:
	slots.sort_custom(func(a, b):
		return extract_table_index(SlotIdHelper.normalize_slot_id(String(a.get("slot_id")))) < extract_table_index(SlotIdHelper.normalize_slot_id(String(b.get("slot_id"))))
	)

static func _position_table_slots(slots: Array, spacing: int, start_pos: Vector2) -> void:
	var start_offset := -float(slots.size() - 1) / 2.0 * spacing
	for i in range(slots.size()):
		slots[i].position = start_pos + Vector2(start_offset + i * spacing, 0)
		if slots[i].has_method("invalidate_rect_cache"):
			slots[i].call("invalidate_rect_cache")
