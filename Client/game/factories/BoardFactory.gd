extends RefCounted
class_name BoardFactory

var slot_scene: PackedScene = null
var slots_by_id: Dictionary = {}
var start_pos: Vector2 = Vector2.ZERO

func setup(p_slot_scene: PackedScene, p_slots_by_id: Dictionary, p_start_pos: Vector2 = GameLayoutConfig.START_POS) -> void:
    slot_scene = p_slot_scene
    slots_by_id = p_slots_by_id
    start_pos = p_start_pos

func create_slot(parent: Node, slot_id: String, pos: Vector2) -> void:
    if slots_by_id.has(slot_id):
        return

    var node_name = SlotIdHelper.slot_node_name(slot_id)
    if parent.has_node(node_name):
        var existing = parent.get_node(node_name)
        slots_by_id[slot_id] = existing
        return

    var slot = slot_scene.instantiate()
    slot.name = node_name
    slot.slot_id = slot_id
    slot.position = pos
    parent.add_child(slot)
    slots_by_id[slot_id] = slot

func create_slots_row(parent: Node, player_id: int, slot_type: String, count: int, slot_spacing: float) -> void:
    for i in range(count):
        var slot_id = "%d:%s:%d" % [player_id, slot_type, i + 1]
        create_slot(parent, slot_id, start_pos + Vector2(i * slot_spacing, 0))

func create_player_slots(player: Node, player_id: int, slot_spacing: float) -> void:
    create_slot(player.get_node("Deck"), "%d:DECK:1" % player_id, start_pos)
    create_slots_row(player.get_node("Main"), player_id, "HAND", GameLayoutConfig.MAIN_COUNT, slot_spacing)
    create_slots_row(player.get_node("Banc"), player_id, "BENCH", GameLayoutConfig.BANC_COUNT, slot_spacing)

func ensure_static_slots_once(pioche_root: Node) -> void:
    create_slot(pioche_root, "0:PILE:1", start_pos)

func update_row_positions(player_id: int, slot_type: String, count: int, slot_spacing: float) -> void:
    for i in range(count):
        var slot_id = "%d:%s:%d" % [player_id, slot_type, i + 1]
        var slot = slots_by_id.get(slot_id)
        if slot:
            slot.position = start_pos + Vector2(i * slot_spacing, 0)
            if slot.has_method("invalidate_rect_cache"):
                slot.call("invalidate_rect_cache")

func update_all_slot_rows(slot_spacing: float) -> void:
    update_row_positions(1, "HAND", GameLayoutConfig.MAIN_COUNT, slot_spacing)
    update_row_positions(2, "HAND", GameLayoutConfig.MAIN_COUNT, slot_spacing)
    update_row_positions(1, "BENCH", GameLayoutConfig.BANC_COUNT, slot_spacing)
    update_row_positions(2, "BENCH", GameLayoutConfig.BANC_COUNT, slot_spacing)
