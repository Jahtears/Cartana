extends RefCounted
class_name GameMessage

const INLINE_PREFIX := "MSG_INLINE_"

const MSG_INLINE_MOVE_OK := "MSG_INLINE_MOVE_OK"
const MSG_INLINE_MOVE_DENIED := "MSG_INLINE_MOVE_DENIED"
const MSG_INLINE_MOVE_INVALID_SLOT := "MSG_INLINE_MOVE_INVALID_SLOT"
const MSG_INLINE_MOVE_REJECTED := "MSG_INLINE_MOVE_REJECTED"
const MSG_INLINE_RULE_CARD_NOT_FOUND := "MSG_INLINE_RULE_CARD_NOT_FOUND"
const MSG_INLINE_RULE_CARD_UNKNOWN := "MSG_INLINE_RULE_CARD_UNKNOWN"
const MSG_INLINE_RULE_SOURCE_SLOT_MISSING_CARD := "MSG_INLINE_RULE_SOURCE_SLOT_MISSING_CARD"
const MSG_INLINE_RULE_UNKNOWN_PLAYER := "MSG_INLINE_RULE_UNKNOWN_PLAYER"
const MSG_INLINE_RULE_SLOT_VALIDATOR_MISSING := "MSG_INLINE_RULE_SLOT_VALIDATOR_MISSING"
const MSG_INLINE_RULE_TABLE_SLOT_NOT_FOUND := "MSG_INLINE_RULE_TABLE_SLOT_NOT_FOUND"
const MSG_INLINE_RULE_DECK_ONLY_TO_TABLE := "MSG_INLINE_RULE_DECK_ONLY_TO_TABLE"
const MSG_INLINE_RULE_NOT_YOUR_TURN := "MSG_INLINE_RULE_NOT_YOUR_TURN"
const MSG_INLINE_RULE_BENCH_ONLY_TO_TABLE := "MSG_INLINE_RULE_BENCH_ONLY_TO_TABLE"
const MSG_INLINE_RULE_ACE_BLOCKS_BENCH_DECK_TOP := "MSG_INLINE_RULE_ACE_BLOCKS_BENCH_DECK_TOP"
const MSG_INLINE_RULE_ACE_BLOCKS_BENCH_HAND := "MSG_INLINE_RULE_ACE_BLOCKS_BENCH_HAND"
const MSG_INLINE_RULE_CARD_NOT_ALLOWED_ON_TABLE := "MSG_INLINE_RULE_CARD_NOT_ALLOWED_ON_TABLE"
const MSG_INLINE_RULE_CANNOT_PLAY_ON_DECK := "MSG_INLINE_RULE_CANNOT_PLAY_ON_DECK"
const MSG_INLINE_RULE_CANNOT_PLAY_ON_HAND := "MSG_INLINE_RULE_CANNOT_PLAY_ON_HAND"
const MSG_INLINE_RULE_CANNOT_PLAY_ON_DRAWPILE := "MSG_INLINE_RULE_CANNOT_PLAY_ON_DRAWPILE"
const MSG_INLINE_RULE_OPPONENT_SLOT_FORBIDDEN := "MSG_INLINE_RULE_OPPONENT_SLOT_FORBIDDEN"
const MSG_INLINE_TURN_START_FIRST := "MSG_INLINE_TURN_START_FIRST"
const MSG_INLINE_TURN_START := "MSG_INLINE_TURN_START"
const MSG_INLINE_TURN_TIMEOUT := "MSG_INLINE_TURN_TIMEOUT"

const TEXT_BY_CODE := {
	MSG_INLINE_MOVE_OK: "Valider",
	MSG_INLINE_MOVE_DENIED: "Deplacement refuse",
	MSG_INLINE_MOVE_INVALID_SLOT: "Slot ID invalide",
	MSG_INLINE_MOVE_REJECTED: "ApplyMove rejected",
	MSG_INLINE_RULE_CARD_NOT_FOUND: "Carte introuvable",
	MSG_INLINE_RULE_CARD_UNKNOWN: "Carte inconnue",
	MSG_INLINE_RULE_SOURCE_SLOT_MISSING_CARD: "Carte absente du slot source",
	MSG_INLINE_RULE_UNKNOWN_PLAYER: "Joueur inconnu pour cette partie",
	MSG_INLINE_RULE_SLOT_VALIDATOR_MISSING: "Aucun validateur pour ce slot",
	MSG_INLINE_RULE_TABLE_SLOT_NOT_FOUND: "Slot Table introuvable",
	MSG_INLINE_RULE_DECK_ONLY_TO_TABLE: "Carte du deck uniquement sur slot Table",
	MSG_INLINE_RULE_NOT_YOUR_TURN: "Pas votre tour",
	MSG_INLINE_RULE_BENCH_ONLY_TO_TABLE: "Carte du banc uniquement sur slot Table",
	MSG_INLINE_RULE_ACE_BLOCKS_BENCH_DECK_TOP: "Banc interdit tant qu'un As est sur le dessus du deck",
	MSG_INLINE_RULE_ACE_BLOCKS_BENCH_HAND: "Banc interdit tant qu'un As est en main",
	MSG_INLINE_RULE_CARD_NOT_ALLOWED_ON_TABLE: "Carte interdite sur Table (attendu: {accepted})",
	MSG_INLINE_RULE_CANNOT_PLAY_ON_DECK: "Interdit de jouer sur un deck",
	MSG_INLINE_RULE_CANNOT_PLAY_ON_HAND: "Interdit de jouer sur la main",
	MSG_INLINE_RULE_CANNOT_PLAY_ON_DRAWPILE: "Interdit de jouer sur la pioche",
	MSG_INLINE_RULE_OPPONENT_SLOT_FORBIDDEN: "Slot adverse interdit",
	MSG_INLINE_TURN_START_FIRST: "A vous de commencer",
	MSG_INLINE_TURN_START: "A vous de jouer",
	MSG_INLINE_TURN_TIMEOUT: "Temps ecoule",
}

const INLINE_GREEN_CODES := {
	MSG_INLINE_TURN_START_FIRST: true,
	MSG_INLINE_TURN_START: true,
	MSG_INLINE_MOVE_OK: true,
}

const INLINE_RED_CODES := {
	MSG_INLINE_MOVE_DENIED: true,
	MSG_INLINE_MOVE_INVALID_SLOT: true,
	MSG_INLINE_MOVE_REJECTED: true,
	MSG_INLINE_RULE_CARD_NOT_FOUND: true,
	MSG_INLINE_RULE_CARD_UNKNOWN: true,
	MSG_INLINE_RULE_SOURCE_SLOT_MISSING_CARD: true,
	MSG_INLINE_RULE_UNKNOWN_PLAYER: true,
	MSG_INLINE_RULE_SLOT_VALIDATOR_MISSING: true,
	MSG_INLINE_RULE_TABLE_SLOT_NOT_FOUND: true,
	MSG_INLINE_RULE_DECK_ONLY_TO_TABLE: true,
	MSG_INLINE_RULE_NOT_YOUR_TURN: true,
	MSG_INLINE_RULE_BENCH_ONLY_TO_TABLE: true,
	MSG_INLINE_RULE_ACE_BLOCKS_BENCH_DECK_TOP: true,
	MSG_INLINE_RULE_ACE_BLOCKS_BENCH_HAND: true,
	MSG_INLINE_RULE_CARD_NOT_ALLOWED_ON_TABLE: true,
	MSG_INLINE_RULE_CANNOT_PLAY_ON_DECK: true,
	MSG_INLINE_RULE_CANNOT_PLAY_ON_HAND: true,
	MSG_INLINE_RULE_CANNOT_PLAY_ON_DRAWPILE: true,
	MSG_INLINE_RULE_OPPONENT_SLOT_FORBIDDEN: true,
	MSG_INLINE_TURN_TIMEOUT: true,
}

const INLINE_GREEN_COLOR := Color(0.0, 1.0, 0.0)
const INLINE_RED_COLOR := Color(1.0, 0.2, 0.2)

static func text_for_code(message_code: String, params: Dictionary = {}) -> String:
	var template := String(TEXT_BY_CODE.get(String(message_code).strip_edges(), ""))
	if template == "":
		return ""
	return _format_template(template, params)

static func normalize_inline_message(ui_message: Dictionary) -> Dictionary:
	var text := String(ui_message.get("text", "")).strip_edges()
	if text == "":
		text = String(ui_message.get("message", "")).strip_edges()
	var params_val = ui_message.get("message_params", ui_message.get("params", {}))
	var params: Dictionary = params_val if params_val is Dictionary else {}

	var message_code := infer_message_code({
		"text": text,
		"message_code": String(ui_message.get("message_code", "")),
	})
	if not message_code.begins_with(INLINE_PREFIX):
		return {}

	if text == "" or text == message_code:
		text = text_for_code(message_code, params)

	var color := color_for_payload({
		"message_code": message_code,
		"text": text,
	})
	var color_val = ui_message.get("color", null)
	if color_val is Color:
		color = color_val
	elif color_val is String and String(color_val) != "":
		color = Color.from_string(String(color_val), color)

	return {
		"text": text,
		"message_code": message_code,
		"message_params": params,
		"color": color,
	}

static func show_inline_message(ui_message: Dictionary, inline_label, inline_timer = null) -> void:
	var normalized := normalize_inline_message(ui_message)
	if normalized.is_empty():
		return

	var text := String(normalized.get("text", ""))
	if text == "" or inline_label == null:
		return

	inline_label.bbcode_enabled = true
	inline_label.text = "[center][color=%s]%s[/color][/center]" % [
		inline_color(String(normalized.get("message_code", "")), text).to_html(),
		text
	]
	inline_label.visible = true

	if inline_timer != null and inline_timer.has_method("start"):
		inline_timer.start()

static func infer_message_code(payload: Dictionary) -> String:
	var explicit_code := String(payload.get("message_code", "")).strip_edges()
	if explicit_code.begins_with(INLINE_PREFIX):
		return explicit_code

	var text := String(payload.get("text", "")).strip_edges()
	if text.begins_with(INLINE_PREFIX):
		return text
	return ""

static func is_inline_message(message_code: String, text: String) -> bool:
	return infer_message_code(_payload(message_code, text)) != ""

static func inline_color(message_code: String, text: String) -> Color:
	return color_for_payload(_payload(message_code, text))

static func color_for_payload(payload: Dictionary) -> Color:
	var message_code := infer_message_code(payload)
	if INLINE_GREEN_CODES.has(message_code):
		return INLINE_GREEN_COLOR
	if INLINE_RED_CODES.has(message_code):
		return INLINE_RED_COLOR
	return INLINE_RED_COLOR

static func _payload(message_code: String, text: String) -> Dictionary:
	return {
		"message_code": String(message_code),
		"text": String(text),
	}

static func _format_template(template: String, params: Dictionary) -> String:
	var out := String(template)
	for key in params.keys():
		out = out.replace("{%s}" % String(key), String(params[key]))
	return out
