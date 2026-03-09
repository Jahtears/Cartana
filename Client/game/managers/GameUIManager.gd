# GameUIManager.gd
# Responsabilité: Gestion de l'affichage UI dans Game.tscn
# - Messages de jeu (règles, feedbacks)
# - Timebar (affichage, update)
# - Deck count (affichage, update)
# - Animations (fade, tweens)
#
# Utilisé par: Game.gd
# Dépendances: GameMessage, TimebarUtil, DeckCountUtil

extends RefCounted
class_name GameUIManager

const Protocol = preload("res://Client/net/Protocol.gd")

# === STATE REFERENCES ===
var root: Node = null
var game_message_state: Dictionary = {}
var timebar_state: Dictionary = {}
var deck_count_state: Dictionary = {}

var _message_tween: Tween = null

# === SETUP ===
func setup(game_root: Node, ui_states: Dictionary) -> void:
	"""Initialize UI manager with game root and UI states"""
	root = game_root
	game_message_state = ui_states.get("game_message", {})
	timebar_state = ui_states.get("timebar", {})
	deck_count_state = ui_states.get("deck_count", {})

# === INITIALIZATION ===
func init_ui_components(message_timeout_callback: Callable) -> void:
	"""Initialize all UI components"""
	GameMessage.ensure_ui(game_message_state, root, message_timeout_callback)
	TimebarUtil.ensure_ui(timebar_state, root)
	DeckCountUtil.ensure_ui(deck_count_state, root)
	DeckCountUtil.reset_counts(deck_count_state)

# === MESSAGES ===
func show_game_feedback(ui_message: Dictionary) -> void:
	"""Display game feedback (RULE_ messages only)"""
	var rule_msg := GameMessage.normalize_rule_message(ui_message)
	if not rule_msg.is_empty():
		display_rule_message(rule_msg)
		return

func display_rule_message(ui_message: Dictionary) -> void:
	"""Display and animate rule message"""
	if _message_tween and is_instance_valid(_message_tween):
		_message_tween.kill()

	GameMessage.show_rule_message(ui_message, game_message_state)
	var label := GameMessage.get_label(game_message_state)
	if label != null:
		label.modulate.a = 1.0

func on_message_timeout() -> void:
	"""Called when message timer expires"""
	hide_message_with_fade()

func hide_message_with_fade() -> void:
	"""Fade out the message"""
	var label := GameMessage.get_label(game_message_state)
	if label == null or not label.visible:
		return

	if _message_tween and is_instance_valid(_message_tween):
		_message_tween.kill()

	if root != null:
		_message_tween = root.create_tween()
		_message_tween.tween_property(label, "modulate:a", 0.0, GameMessage.get_fade_duration())
		await _message_tween.finished

	label.visible = false
	label.modulate.a = 1.0

# === TIMEBAR ===
func update_timebar(server_now_callable: Callable) -> void:
	"""Update timebar display (called from _process)"""
	TimebarUtil.update_timebar(timebar_state, server_now_callable)

func set_turn_timer(turn: Dictionary, sync_server_clock_callable: Callable, is_spectator: bool, username: String) -> void:
	"""Set turn timer from server data"""
	TimebarUtil.set_turn_timer(timebar_state, turn, sync_server_clock_callable)
	TimebarUtil.update_timebar_mode(timebar_state, is_spectator, username)
	TimebarUtil.update_timebar(timebar_state, Callable(NetworkManager, "server_now_ms"))

# === CLEANUP ===
func cleanup() -> void:
	"""Clean up UI resources"""
	GameMessage.cleanup(game_message_state)
	TimebarUtil.cleanup(timebar_state)
	DeckCountUtil.cleanup(deck_count_state)

	if _message_tween and is_instance_valid(_message_tween):
		_message_tween.kill()
		_message_tween = null
