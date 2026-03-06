#Golbal.gd v1.0
extends Node

const SETTINGS_PATH := "user://client_settings.cfg"
const SETTINGS_SECTION_CARD_BACKS := "card_backs"
const SETTINGS_KEY_SOURCE_A := "source_a_back_id"
const SETTINGS_KEY_SOURCE_B := "source_b_back_id"

const CARD_BACKS_DIR := "res://Client/Resource/Cartes"
const CARD_BACKS_PREFIX := "Dos"
const CARD_BACKS_EXTENSION := ".png"
const CARD_BACK_CANDIDATE_LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
const CARD_BACK_MAX_NUMERIC_CANDIDATE := 99

const SOURCE_A := "A"
const SOURCE_B := "B"
const DEFAULT_BACK_A := "DosA"
const DEFAULT_BACK_B := "DosB"

var username = ""
var current_game_id: String = ""
var players_in_game: Array = []
var current_games: Array = []
var is_spectator: bool = false
var result: Dictionary = {} # {} si pas fini, sinon {winner}

# Card back management
var _available_back_ids: Array[String] = []
var _back_path_by_id: Dictionary = {}
var _back_texture_cache: Dictionary = {}
var _selected_back_by_source: Dictionary = {
	SOURCE_A: "",
	SOURCE_B: "",
}

func _ready() -> void:
	_load_back_preferences()
	_discover_available_backs()
	_sanitize_selected_back_mapping()
	_save_back_preferences()

func reset_game_state() -> void:
	current_game_id = ""
	players_in_game.clear()
	is_spectator = false
	result.clear()

func get_available_back_ids() -> Array[String]:
	var out: Array[String] = []
	for back_id in _available_back_ids:
		out.append(back_id)
	return out

func get_back_texture_by_id(back_id: String) -> Texture2D:
	var resolved_id := _resolve_existing_back_id(back_id)
	if resolved_id == "":
		resolved_id = _fallback_back_id()
	return _load_back_texture_by_id(resolved_id)

func get_selected_back_for_source(source: String) -> String:
	var normalized_source := _normalize_source(source)
	var selected := String(_selected_back_by_source.get(normalized_source, ""))
	if _has_back_id(selected):
		return selected
	_sanitize_selected_back_mapping()
	return String(_selected_back_by_source.get(normalized_source, ""))

func assign_back_to_source(source: String, back_id: String) -> void:
	var normalized_source := _normalize_source(source)
	var normalized_back_id := _resolve_existing_back_id(back_id)
	if normalized_back_id == "":
		return

	var other_source := SOURCE_B if normalized_source == SOURCE_A else SOURCE_A
	var current_source_back := get_selected_back_for_source(normalized_source)
	var current_other_back := get_selected_back_for_source(other_source)

	if current_source_back == normalized_back_id:
		return

	if _available_back_ids.size() > 1 and current_other_back == normalized_back_id:
		var replacement := current_source_back
		if replacement == "" or replacement == normalized_back_id or not _has_back_id(replacement):
			replacement = _find_alternative_back_id(normalized_back_id)
		_selected_back_by_source[normalized_source] = normalized_back_id
		_selected_back_by_source[other_source] = replacement
	else:
		_selected_back_by_source[normalized_source] = normalized_back_id

	_sanitize_selected_back_mapping()
	_save_back_preferences()

func get_back_texture_for_source(source: String) -> Texture2D:
	var selected_back_id := get_selected_back_for_source(source)
	return get_back_texture_by_id(selected_back_id)

func _discover_available_backs() -> void:
	_available_back_ids.clear()
	_back_path_by_id.clear()
	_back_texture_cache.clear()

	var dir := DirAccess.open(CARD_BACKS_DIR)
	if dir != null:
		dir.list_dir_begin()
		while true:
			var file_name := dir.get_next()
			if file_name == "":
				break
			if dir.current_is_dir():
				continue
			if not _is_card_back_file(file_name):
				continue
			_register_back_candidate(file_name.get_basename())
		dir.list_dir_end()

	# Export-safe fallback: la liste de fichiers res:// peut être incomplète dans le pck/web.
	_register_back_candidate(DEFAULT_BACK_A)
	_register_back_candidate(DEFAULT_BACK_B)
	_register_back_candidate(String(_selected_back_by_source.get(SOURCE_A, "")))
	_register_back_candidate(String(_selected_back_by_source.get(SOURCE_B, "")))

	for i in range(CARD_BACK_CANDIDATE_LETTERS.length()):
		var suffix := CARD_BACK_CANDIDATE_LETTERS.substr(i, 1)
		_register_back_candidate("%s%s" % [CARD_BACKS_PREFIX, suffix])

	for i in range(1, CARD_BACK_MAX_NUMERIC_CANDIDATE + 1):
		_register_back_candidate("%s%d" % [CARD_BACKS_PREFIX, i])

	_available_back_ids.sort()
	if _available_back_ids.is_empty():
		push_warning("Global: no card backs discovered in %s" % CARD_BACKS_DIR)

func _is_card_back_file(file_name: String) -> bool:
	var normalized := String(file_name).strip_edges()
	return (
		normalized.length() > CARD_BACKS_PREFIX.length()
		and normalized.to_lower().begins_with(CARD_BACKS_PREFIX.to_lower())
		and normalized.to_lower().ends_with(CARD_BACKS_EXTENSION)
	)

func _register_back_candidate(back_id: String) -> void:
	var normalized_back_id := String(back_id).strip_edges()
	if normalized_back_id == "":
		return
	if not normalized_back_id.begins_with(CARD_BACKS_PREFIX):
		return
	if _back_path_by_id.has(normalized_back_id):
		return

	var path := _back_path_for_id(normalized_back_id)
	if not ResourceLoader.exists(path):
		return

	_back_path_by_id[normalized_back_id] = path
	_available_back_ids.append(normalized_back_id)

func _back_path_for_id(back_id: String) -> String:
	return "%s/%s%s" % [CARD_BACKS_DIR, back_id, CARD_BACKS_EXTENSION]

func _load_back_preferences() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		_selected_back_by_source[SOURCE_A] = ""
		_selected_back_by_source[SOURCE_B] = ""
		return

	_selected_back_by_source[SOURCE_A] = String(config.get_value(SETTINGS_SECTION_CARD_BACKS, SETTINGS_KEY_SOURCE_A, ""))
	_selected_back_by_source[SOURCE_B] = String(config.get_value(SETTINGS_SECTION_CARD_BACKS, SETTINGS_KEY_SOURCE_B, ""))

func _save_back_preferences() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value(SETTINGS_SECTION_CARD_BACKS, SETTINGS_KEY_SOURCE_A, get_selected_back_for_source(SOURCE_A))
	config.set_value(SETTINGS_SECTION_CARD_BACKS, SETTINGS_KEY_SOURCE_B, get_selected_back_for_source(SOURCE_B))
	config.save(SETTINGS_PATH)

func _sanitize_selected_back_mapping() -> void:
	if _available_back_ids.is_empty():
		_selected_back_by_source[SOURCE_A] = ""
		_selected_back_by_source[SOURCE_B] = ""
		return

	var selected_a := _resolve_existing_back_id(String(_selected_back_by_source.get(SOURCE_A, "")))
	var selected_b := _resolve_existing_back_id(String(_selected_back_by_source.get(SOURCE_B, "")))

	if selected_a == "":
		selected_a = _default_back_for_source(SOURCE_A)
	if selected_b == "":
		selected_b = _default_back_for_source(SOURCE_B)

	if _available_back_ids.size() > 1 and selected_a == selected_b:
		selected_b = _find_alternative_back_id(selected_a)

	_selected_back_by_source[SOURCE_A] = selected_a
	_selected_back_by_source[SOURCE_B] = selected_b

func _default_back_for_source(source: String) -> String:
	var normalized_source := _normalize_source(source)
	if normalized_source == SOURCE_A:
		return _default_back_for_source_a()
	return _default_back_for_source_b()

func _default_back_for_source_a() -> String:
	if _available_back_ids.is_empty():
		return ""
	if _has_back_id(DEFAULT_BACK_A):
		return DEFAULT_BACK_A
	return _available_back_ids[0]

func _default_back_for_source_b() -> String:
	if _available_back_ids.is_empty():
		return ""
	if _has_back_id(DEFAULT_BACK_B):
		return DEFAULT_BACK_B

	var selected_a := _default_back_for_source_a()
	if _available_back_ids.size() > 1:
		for back_id in _available_back_ids:
			if back_id != selected_a:
				return back_id
	return selected_a

func _find_alternative_back_id(excluded_back_id: String) -> String:
	for back_id in _available_back_ids:
		if back_id != excluded_back_id:
			return back_id
	return excluded_back_id

func _resolve_existing_back_id(back_id: String) -> String:
	var normalized_back_id := String(back_id).strip_edges()
	if _has_back_id(normalized_back_id):
		return normalized_back_id
	return ""

func _fallback_back_id() -> String:
	if _available_back_ids.is_empty():
		return ""

	var source_b_back := String(_selected_back_by_source.get(SOURCE_B, ""))
	if _has_back_id(source_b_back):
		return source_b_back

	var source_a_back := String(_selected_back_by_source.get(SOURCE_A, ""))
	if _has_back_id(source_a_back):
		return source_a_back

	return _available_back_ids[0]

func _load_back_texture_by_id(back_id: String) -> Texture2D:
	if back_id == "":
		return null

	if _back_texture_cache.has(back_id):
		var cached = _back_texture_cache.get(back_id)
		if cached is Texture2D:
			return cached

	var path := String(_back_path_by_id.get(back_id, ""))
	if path == "":
		return null

	var loaded = load(path)
	if loaded is Texture2D:
		_back_texture_cache[back_id] = loaded
		return loaded

	push_warning("Global: failed to load card back texture %s (%s)" % [back_id, path])
	return null

func _has_back_id(back_id: String) -> bool:
	return _back_path_by_id.has(back_id)

func _normalize_source(source: String) -> String:
	var normalized := String(source).strip_edges().to_upper()
	if normalized == SOURCE_A:
		return SOURCE_A
	return SOURCE_B
