# slot_id.gd
extends RefCounted
class_name SlotIdHelper

static func normalize_slot_id(raw: String) -> String:
	var s := String(raw)
	if s == "":
		return s
	var parts := s.split(":")
	if parts.size() != 3:
		return s

	var p := String(parts[0])
	var t := String(parts[1])
	var idx := String(parts[2])

	if not p.is_valid_int() or not idx.is_valid_int():
		return s

	return "%d:%s:%d" % [int(p), t, int(idx)]

static func parse_slot_id(raw: String) -> Dictionary:
	var s := normalize_slot_id(raw)
	if s.find(":") == -1:
		return {}
	var parts := s.split(":")
	if parts.size() != 3:
		return {}
	if not parts[0].is_valid_int() or not parts[2].is_valid_int():
		return {}
	return {
		"player": int(parts[0]),
		"type": String(parts[1]),
		"index": int(parts[2]),
		"raw": s,
	}

static func is_table_slot_id(raw: String) -> bool:
	var parsed := parse_slot_id(raw)
	return String(parsed.get("type", "")) == "TABLE"

static func slot_node_name(slot_id: String) -> String:
	return "slot_%s" % slot_id.replace(":", "_")
