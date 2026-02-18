# slot_id.gd
extends RefCounted
class_name SlotIdHelper

const PART_SEPARATOR := ":"
const PART_COUNT := 3
const PART_INDEX_PLAYER := 0
const PART_INDEX_TYPE := 1
const PART_INDEX_SLOT := 2

static func normalize_slot_id(raw: String) -> String:
	var s := String(raw)
	if s == "":
		return s
	var parts := s.split(PART_SEPARATOR)
	if parts.size() != PART_COUNT:
		return s

	var p := String(parts[PART_INDEX_PLAYER])
	var t := String(parts[PART_INDEX_TYPE])
	var idx := String(parts[PART_INDEX_SLOT])

	if not p.is_valid_int() or not idx.is_valid_int():
		return s

	return "%d%s%s%s%d" % [int(p), PART_SEPARATOR, t, PART_SEPARATOR, int(idx)]

static func parse_slot_id(raw: String) -> Dictionary:
	var s := normalize_slot_id(raw)
	if s.find(PART_SEPARATOR) == -1:
		return {}
	var parts := s.split(PART_SEPARATOR)
	if parts.size() != PART_COUNT:
		return {}
	if not parts[PART_INDEX_PLAYER].is_valid_int() or not parts[PART_INDEX_SLOT].is_valid_int():
		return {}
	return {
		"player": int(parts[PART_INDEX_PLAYER]),
		"type": String(parts[PART_INDEX_TYPE]),
		"index": int(parts[PART_INDEX_SLOT]),
		"raw": s,
	}

static func is_table_slot_id(raw: String) -> bool:
	var parsed := parse_slot_id(raw)
	return String(parsed.get("type", "")) == "TABLE"

static func slot_node_name(slot_id: String) -> String:
	return "slot_%s" % slot_id.replace(":", "_")
