extends RefCounted

const LANG_FR := "fr"
const LANG_EN := "en"

const LangFR = preload("res://Client/Lang/langFR.gd")
const LangEnglish = preload("res://Client/Lang/LangEnglish.gd")

const LOGIN_TEXT_BY_LANG := {
	LANG_FR: {
		"login_username_placeholder": "Identifiant",
		"login_pin_placeholder": "PIN",
		"login_button": "Connexion",
		"login_remember_username": "Retenir l'identifiant",
		"login_language_label": "Langue",
		"language_fr": "Francais",
		"language_en": "English",
	},
	LANG_EN: {
		"login_username_placeholder": "Username",
		"login_pin_placeholder": "PIN",
		"login_button": "Login",
		"login_remember_username": "Remember username",
		"login_language_label": "Language",
		"language_fr": "Francais",
		"language_en": "English",
	},
}

static var _current_language := LANG_FR

static func set_language(language_code: String) -> void:
	_current_language = normalize_language(language_code)

static func get_language() -> String:
	return _current_language

static func normalize_language(language_code: String) -> String:
	var normalized := String(language_code).strip_edges().to_lower()
	if normalized == LANG_EN:
		return LANG_EN
	return LANG_FR

static func popup_text(message_code: String, params: Dictionary = {}) -> String:
	var text := _popup_text_for_language(_current_language, message_code, params)
	if text != "":
		return text
	return LangFR.popup_text(message_code, params)

static func ingame_text(message_code: String, params: Dictionary = {}) -> String:
	var text := _ingame_text_for_language(_current_language, message_code, params)
	if text != "":
		return text
	return LangFR.ingame_text(message_code, params)

static func label(label_key: String, fallback := "") -> String:
	var value := _label_for_language(_current_language, label_key, "")
	if value != "":
		return value
	return LangFR.label(label_key, fallback)

static func ui_text(key: String, fallback := "") -> String:
	var language := _current_language
	var language_pack_val = LOGIN_TEXT_BY_LANG.get(language, {})
	var language_pack: Dictionary = language_pack_val if language_pack_val is Dictionary else {}
	var text := String(language_pack.get(key, ""))
	if text != "":
		return text
	var fr_pack := LOGIN_TEXT_BY_LANG[LANG_FR]
	return String(fr_pack.get(key, fallback))

static func language_display_name(language_code: String) -> String:
	var normalized := normalize_language(language_code)
	var key := "language_%s" % normalized
	return ui_text(key, normalized)

static func _popup_text_for_language(language: String, message_code: String, params: Dictionary) -> String:
	match normalize_language(language):
		LANG_EN:
			return LangEnglish.popup_text(message_code, params)
		_:
			return LangFR.popup_text(message_code, params)

static func _ingame_text_for_language(language: String, message_code: String, params: Dictionary) -> String:
	match normalize_language(language):
		LANG_EN:
			return LangEnglish.ingame_text(message_code, params)
		_:
			return LangFR.ingame_text(message_code, params)

static func _label_for_language(language: String, label_key: String, fallback: String) -> String:
	match normalize_language(language):
		LANG_EN:
			return LangEnglish.label(label_key, fallback)
		_:
			return LangFR.label(label_key, fallback)
