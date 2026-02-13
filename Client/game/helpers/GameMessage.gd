extends Node
class_name GameMessage

# Canonical short gameplay messages rendered inline in Game.gd
const TURN_FLOW_MESSAGES := {
	"START": "A vous de commencer",
	"TIMEOUT": "Temps ecoule.",
	"TURN_START": "A vous de jouer.",
}

const INLINE_GREEN_CODES := [
	"TURN_START",
	"MOVE_OK",
]

const INLINE_RED_CODES := [
	"MOVE_DENIED",
]

const INLINE_GREEN_TEXT_EXACT := [
	TURN_FLOW_MESSAGES.START,
	TURN_FLOW_MESSAGES.TURN_START,
	"Valider",
]

const INLINE_RED_TEXT_EXACT := [
	TURN_FLOW_MESSAGES.TIMEOUT,
]

const INLINE_COLOR_GREEN := Color(0.0, 1.0, 0.0)
const INLINE_COLOR_RED := Color(1.0, 0.2, 0.2)

static func _normalize_text(text: String) -> String:
	return String(text).strip_edges().to_lower()

static func _contains_text(items: Array, text: String) -> bool:
	var norm := _normalize_text(text)
	for item in items:
		if _normalize_text(String(item)) == norm:
			return true
	return false

static func is_inline_message(code: String, text: String) -> bool:
	var c := String(code).strip_edges()
	if INLINE_GREEN_CODES.has(c):
		return true
	if INLINE_RED_CODES.has(c):
		return true
	if _contains_text(INLINE_GREEN_TEXT_EXACT, text):
		return true
	if _contains_text(INLINE_RED_TEXT_EXACT, text):
		return true
	return false

static func inline_color(code: String, text: String) -> Color:
	var c := String(code).strip_edges()
	if INLINE_GREEN_CODES.has(c) or _contains_text(INLINE_GREEN_TEXT_EXACT, text):
		return INLINE_COLOR_GREEN
	return INLINE_COLOR_RED
