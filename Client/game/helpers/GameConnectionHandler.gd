# GameConnectionHandler.gd - Handles connection state and disconnection events
extends RefCounted
class_name GameConnectionHandler

const Protocol = preload("res://Client/net/Protocol.gd")

# ============= CONNECTION STATE HANDLERS =============

static func on_connection_lost(game_ref: Node) -> void:
	"""Handle connection lost event"""
	game_ref._network_disconnected = true
	PopupUi.show_code(PopupUi.MODE_INFO, Protocol.POPUP_PLAYER_DISCONNECTED)


static func on_connection_restored(game_ref: Node) -> void:
	"""Handle connection restored event"""
	if not game_ref._network_disconnected:
		return
	game_ref._network_disconnected = false
	PopupUi.show_code(PopupUi.MODE_INFO, Protocol.POPUP_PLAYER_RECONNECTED)


static func on_reconnect_failed(game_ref: Node) -> void:
	"""Handle reconnection failure"""
	if not game_ref._network_disconnected:
		return
	PopupUi.show_code(
		PopupUi.MODE_INFO,
		Protocol.POPUP_PLAYER_RECONNECT_FAIL,
		{},
		{"ok_action_id": "network_retry"},
		{"ok_label_key": "UI_LABEL_RETRY"}
	)


static func on_server_closed(_server_reason: String, _close_code: int, _raw_reason: String, game_ref: Node) -> void:
	"""Handle server explicitly closing connection"""
	game_ref._network_disconnected = false
	PopupUi.show_code(PopupUi.MODE_INFO, Protocol.POPUP_TECH_INTERNAL_ERROR)


# ============= DISCONNECT CHOICE HANDLING =============

static func show_disconnect_choice(who: String, game_ref: Node) -> void:
	"""Show popup to wait or leave when opponent disconnects"""
	PopupUi.show_code(
		PopupUi.MODE_CONFIRM,
		Protocol.POPUP_OPPONENT_DISCONNECTED_CHOICE,
		{"name": who},
		{
			"yes_action_id": "pause_wait",
			"no_action_id": "pause_leave",
		},
		{"yes_label_key": "UI_LABEL_WAIT", "no_label_key": "UI_LABEL_BACK_LOBBY"}
	)


static func schedule_disconnect_choice(who: String, game_ref: Node) -> void:
	"""Schedule the disconnect choice popup to appear after a delay"""
	game_ref._disconnect_prompt_seq += 1
	var seq := game_ref._disconnect_prompt_seq
	var timer := game_ref.get_tree().create_timer(5.0)
	timer.timeout.connect(func() -> void:
		if seq != game_ref._disconnect_prompt_seq:
			return
		if not game_ref._opponent_disconnected:
			return
		show_disconnect_choice(who, game_ref)
	)
