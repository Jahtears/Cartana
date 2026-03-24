extends Node

signal language_changed(language_code: String)

const LANG_FR := "fr"
const LANG_EN := "en"
const DEFAULT_LANGUAGE := LANG_FR

const SETTINGS_PATH := "user://client_settings.cfg"
const SETTINGS_SECTION_I18N := "i18n"
const SETTINGS_KEY_LANGUAGE := "language"

const LOCALE_PATH_BY_LANG := {
  LANG_FR: "res://Script/Lang/locales/fr.json",
  LANG_EN: "res://Script/Lang/locales/en.json",
}

var _current_language := DEFAULT_LANGUAGE
var _catalog_by_language: Dictionary = {}

func _ready() -> void:
  _load_catalogs()
  _current_language = _load_saved_language()

func set_language(language_code: String, persist := true) -> void:
  var normalized := normalize_language(language_code)
  if normalized == _current_language:
    if persist:
      _save_language(normalized)
    return
  _current_language = normalized
  if persist:
    _save_language(normalized)
  language_changed.emit(_current_language)

func get_language() -> String:
  return _current_language

func normalize_language(language_code: String) -> String:
  var normalized := String(language_code).strip_edges().to_lower()
  if normalized == LANG_EN:
    return LANG_EN
  return LANG_FR

func t(key: String, params: Dictionary = {}, _fallback := "") -> String:
  var normalized_key := String(key).strip_edges()
  if normalized_key == "":
    return _missing_key_placeholder("EMPTY_KEY")

  var template := _find_template(normalized_key)
  if template == "":
    return _missing_key_placeholder(normalized_key)
  return _format_template(template, params)

func popup_text(message_code: String, params: Dictionary = {}) -> String:
  return t(message_code, params)

func rule_text(message_code: String, params: Dictionary = {}) -> String:
  return t(message_code, params)

func label(label_key: String, fallback := "") -> String:
  var normalized_key := String(label_key).strip_edges()
  return t(normalized_key, {}, fallback)

func ui_text(key: String, fallback := "", params: Dictionary = {}) -> String:
  return t(key, params, fallback)

func language_display_name(language_code: String) -> String:
  var normalized := normalize_language(language_code)
  var key := "UI_LANGUAGE_%s" % normalized.to_upper()
  return ui_text(key, normalized)

func _find_template(key: String) -> String:
  var active_catalog := _catalog_for(_current_language)
  var template := String(active_catalog.get(key, ""))
  if template != "":
    return template
  var fr_catalog := _catalog_for(LANG_FR)
  return String(fr_catalog.get(key, ""))

func _catalog_for(language_code: String) -> Dictionary:
  var normalized := normalize_language(language_code)
  var raw = _catalog_by_language.get(normalized, {})
  return raw if raw is Dictionary else {}

func _load_catalogs() -> void:
  _catalog_by_language.clear()
  for language in LOCALE_PATH_BY_LANG.keys():
    var path := String(LOCALE_PATH_BY_LANG[language])
    _catalog_by_language[language] = _load_catalog(path)

func _load_catalog(path: String) -> Dictionary:
  var file := FileAccess.open(path, FileAccess.READ)
  if file == null:
    push_error("LanguageManager: cannot open locale file %s" % path)
    return {}

  var content := file.get_as_text()
  var json := JSON.new()
  var parse_err := json.parse(content)
  if parse_err != OK:
    push_error("LanguageManager: invalid JSON in %s (line %d)" % [path, json.get_error_line()])
    return {}

  if not (json.data is Dictionary):
    push_error("LanguageManager: locale root must be a Dictionary in %s" % path)
    return {}

  var src: Dictionary = json.data
  var out: Dictionary = {}
  for raw_key in src.keys():
    var normalized_key := String(raw_key).strip_edges()
    if normalized_key == "":
      continue
    out[normalized_key] = String(src[raw_key])
  return out

func _load_saved_language() -> String:
  var config := ConfigFile.new()
  var result := config.load(SETTINGS_PATH)
  if result != OK:
    return DEFAULT_LANGUAGE
  return normalize_language(String(config.get_value(SETTINGS_SECTION_I18N, SETTINGS_KEY_LANGUAGE, DEFAULT_LANGUAGE)))

func _save_language(language_code: String) -> void:
  var config := ConfigFile.new()
  config.load(SETTINGS_PATH)
  config.set_value(SETTINGS_SECTION_I18N, SETTINGS_KEY_LANGUAGE, normalize_language(language_code))
  config.save(SETTINGS_PATH)

func _format_template(template: String, params: Dictionary) -> String:
  var out := String(template)
  for key in params.keys():
    out = out.replace("{%s}" % str(key), str(params[key]))
  return out

func _missing_key_placeholder(key: String) -> String:
  return "[[MISSING:%s]]" % String(key).strip_edges()
