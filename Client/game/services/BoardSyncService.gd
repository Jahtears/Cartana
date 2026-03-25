extends RefCounted
class_name BoardSyncService

# ============= PROPERTIES =============
var context: CardContext = null
var _card_factory: CardFactory = null

# ============= LIFECYCLE =============
func _init(ctx: CardContext) -> void:
    context = ctx
    _card_factory = CardFactory.new()

# ============= PUBLIC METHODS =============
func apply_snapshot(data: Array) -> Array:
    """Synchronise plusieurs cartes depuis un snapshot serveur"""
    var synced_cards: Array = []
    for card_data in data:
        var card = apply_slot_state(card_data.get("slot_id", ""), card_data.get("cards", []), card_data.get("count", 0), false)
        if card != null:
            synced_cards.append(card)
    return synced_cards

func apply_slot_state(slot_id: String, cards: Array, count: int, animate: bool) -> Node2D:
    """Synchronise l'état d'un slot (cartes, nombre, animation)"""
    if context == null or context.slots_by_id == null:
        return null
    var slot = context.slots_by_id.get(slot_id)
    if slot == null:
        return null
    var last_card: Node2D = null
    for card_data in cards:
        var card_id: String = String(card_data.get("card_id", ""))
        if card_id == "":
            continue
        var card := _card_factory.get_or_create_card(context, card_id)
        if card == null:
            continue
        _card_factory.update_card_data(card, card_data)
        _card_factory.set_card_server_order(card, card_data)
        _card_factory.mark_card_synced(card)
        if slot.has_method("snap_card"):
            slot.snap_card(card, animate)
            EventDispatcher.emit_card_snapped(card, slot, animate)
        _card_factory.update_card_last_slot(card, slot_id)
        last_card = card
    return last_card

func sync_table_slots(table_node: Node, active_slots: Array, slot_scene: PackedScene = null, spacing: int = 100, start_pos: Vector2 = Vector2.ZERO) -> void:
    if context == null or context.slots_by_id == null:
        return
    var wanted := _collect_wanted_slots(active_slots)
    _remove_stale_table_slots(table_node, wanted)
    _upsert_wanted_table_slots(table_node, slot_scene, wanted)
    _update_table_positions(table_node, spacing, start_pos)

# ============= PRIVATE HELPERS =============
func _collect_wanted_slots(active_slots: Array) -> Dictionary:
    var wanted: Dictionary = {}
    for s in active_slots:
        var normalized := SlotIdHelper.normalize_slot_id(String(s))
        if normalized != "":
            wanted[normalized] = true
    return wanted

func _remove_stale_table_slots(table: Node, wanted: Dictionary) -> void:
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
        context.slots_by_id.erase(cid)
        if child.get_parent() == table:
            table.remove_child(child)
        child.queue_free()

func _upsert_wanted_table_slots(table: Node, slot_scene: PackedScene, wanted: Dictionary) -> void:
    if context.slots_by_id == null:
        return
    for slot_id in wanted.keys():
        var node_name := SlotIdHelper.slot_node_name(slot_id)
        var existing := table.get_node_or_null(node_name)
        if existing != null and existing is Node and existing.is_queued_for_deletion():
            if existing.get_parent() == table:
                table.remove_child(existing)
            existing = null
        if existing == null and slot_scene != null:
            var slot := slot_scene.instantiate()
            slot.name = node_name
            slot.slot_id = slot_id
            table.add_child(slot)
            context.slots_by_id[slot_id] = slot
        elif existing != null:
            existing.slot_id = slot_id
            context.slots_by_id[slot_id] = existing

func _update_table_positions(table: Node, spacing: int, start_pos: Vector2) -> void:
    var slots := _collect_live_table_slots(table)
    if slots.is_empty():
        return
    _sort_table_slots_by_index(slots)
    _position_table_slots(slots, spacing, start_pos)

func _collect_live_table_slots(table: Node) -> Array:
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
    slots.sort_custom(func(a, b):
        var slot_id_a = String(a.slot_id) if is_instance_valid(a) and "slot_id" in a else ""
        var slot_id_b = String(b.slot_id) if is_instance_valid(b) and "slot_id" in b else ""
        var index_a = _extract_table_index(SlotIdHelper.normalize_slot_id(slot_id_a))
        var index_b = _extract_table_index(SlotIdHelper.normalize_slot_id(slot_id_b))
        return index_a < index_b
    )

func _position_table_slots(slots: Array, spacing: int, start_pos: Vector2) -> void:
    if slots.is_empty():
        return
    var start_offset := -float(slots.size() - 1) / 2.0 * spacing
    for i in range(slots.size()):
        slots[i].position = start_pos + Vector2(start_offset + i * spacing, 0)
        if slots[i].has_method("invalidate_rect_cache"):
            slots[i].call("invalidate_rect_cache")

func _extract_table_index(slot_id: String) -> int:
    var parsed := SlotIdHelper.parse_slot_id(slot_id)
    if parsed.is_empty():
        return 0
    if String(parsed.get("type", "")) != "TABLE":
        return 0
    return int(parsed.get("index", 0))
