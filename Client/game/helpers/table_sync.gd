# table_sync.gd
extends RefCounted
class_name TableSyncHelper

const SlotIdHelper = preload("res://Client/game/helpers/slot_id.gd")

static func sync_table_slots(table: Node, slot_scene: PackedScene, slots_by_id: Dictionary, allowed_table_slots: Dictionary, active_slots: Array, spacing: int = 100, start_pos: Vector2 = Vector2.ZERO) -> void:
	var wanted: Dictionary = {}

	for s in active_slots:
		var normalized := SlotIdHelper.normalize_slot_id(String(s))
		if normalized != "":
			wanted[normalized] = true

	allowed_table_slots.clear()
	for slot_id in wanted.keys():
		allowed_table_slots[slot_id] = true

	for slot_id in wanted.keys():
		var node_name := SlotIdHelper.slot_node_name(slot_id)
		if not table.has_node(node_name):
			var slot := slot_scene.instantiate()
			slot.name = node_name
			slot.slot_id = slot_id
			table.add_child(slot)
			slots_by_id[slot_id] = slot

	for child in table.get_children():
		var cid := String(child.slot_id)
		if SlotIdHelper.is_table_slot_id(cid) and not wanted.has(cid):
			if child.has_method("clear_slot"):
				child.clear_slot()
			slots_by_id.erase(cid)
			child.queue_free()

	update_table_positions(table, spacing, start_pos)

static func update_table_positions(table: Node, spacing: int = 100, start_pos: Vector2 = Vector2.ZERO) -> void:
	var slots: Array = []

	for child in table.get_children():
		if SlotIdHelper.is_table_slot_id(String(child.slot_id)):
			slots.append(child)

	if slots.is_empty():
		return

	slots.sort_custom(func(a, b):
		return extract_table_index(String(a.slot_id)) < extract_table_index(String(b.slot_id))
	)

	var start_offset := -float(slots.size() - 1) / 2.0 * spacing
	for i in range(slots.size()):
		slots[i].position = start_pos + Vector2(start_offset + i * spacing, 0)

static func extract_table_index(slot_id: String) -> int:
	var parsed := SlotIdHelper.parse_slot_id(slot_id)
	if parsed.is_empty():
		return 0
	if String(parsed.get("type", "")) != "TABLE":
		return 0
	return int(parsed.get("index", 0))
