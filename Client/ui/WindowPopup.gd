#windowPopup.gd v1.0
extends Window
class_name WindowPopup

enum Mode { NONE, INVITE, INFO, CONFIRM }
var _mode: int = Mode.NONE
var _inviter: String = ""

var _yes_cb: Callable = Callable()
var _no_cb: Callable = Callable()

# --- état "Game" (ex-PauseWindow) ---
var _pending_end_ack: bool = false
var _leave_sent: bool = false
var _sent_leave_spectate: bool = false
var _is_changing_scene: bool = false

@onready var _label: Label = $MarginContainer/VBox/Label
@onready var _btn_accept: Button = $MarginContainer/VBox/Buttons/ButtonAccept
@onready var _btn_refuse: Button = $MarginContainer/VBox/Buttons/ButtonRefuse
@onready var _btn_ok: Button = $MarginContainer/VBox/Buttons/ButtonOK

func _ready() -> void:
	# Les boutons sont déjà connectés via WindowPopup.tscn

	# écoute réseau global (Lobby + Game)
	if not NetworkManager.evt.is_connected(_on_evt):
		NetworkManager.evt.connect(_on_evt)
	if not NetworkManager.response.is_connected(_on_response):
		NetworkManager.response.connect(_on_response)

# -------------------------------------------------------------------
# API publique (Lobby + Game)
# -------------------------------------------------------------------
func show_info(msg: String) -> void:
	_mode = Mode.INFO
	_inviter = ""
	_yes_cb = Callable()
	_no_cb = Callable()

	_label.text = msg
	_btn_accept.visible = false
	_btn_refuse.visible = false
	_btn_ok.visible = true

	popup_centered()

func show_invite_request(from_user: String) -> void:
	_mode = Mode.INVITE
	_inviter = from_user
	_yes_cb = Callable()
	_no_cb = Callable()

	_label.text = "%s t'invite à jouer" % from_user
	_btn_accept.text = "Accepter"
	_btn_refuse.text = "Refuser"
	_btn_accept.visible = true
	_btn_refuse.visible = true
	_btn_ok.visible = false

	popup_centered()

func show_confirm(message: String, yes_text := "Oui", no_text := "Non", yes_cb: Callable = Callable(), no_cb: Callable = Callable()) -> void:
	_mode = Mode.CONFIRM
	_inviter = ""
	_yes_cb = yes_cb
	_no_cb = no_cb

	_label.text = message
	_btn_accept.text = yes_text
	_btn_refuse.text = no_text
	_btn_accept.visible = true
	_btn_refuse.visible = true
	_btn_ok.visible = false

	popup_centered()

# Game : bouton "Quitter"
func confirm_quit_to_lobby() -> void:
	show_confirm(
		"Quitter la partie et revenir au lobby ?",
		"Annuler", "Quitter",
		Callable(), # Annuler -> juste fermer (on ferme déjà après callback)
		Callable(self, "_leave_current_and_go_lobby")
	)
# Game : detach propre sur close / exit (sortie unique)
func ack_game_end_if_needed() -> void:
	if _sent_leave_spectate:
		return
	if String(Global.current_game_id) == "":
		return

	# Idempotent (joueur ou spectateur)
	_sent_leave_spectate = true
	NetworkManager.request("ack_game_end", {"game_id": String(Global.current_game_id)})

# -------------------------------------------------------------------
# Réseau (invites + feedback + pause game)
# -------------------------------------------------------------------
func _on_evt(type: String, data: Dictionary) -> void:
	match type:
		# ----- Lobby/Global -----
		"invite_request":
			show_invite_request(String(data.get("from", "")))

		"invite_response":
			var msg := String(data.get("message", ""))
			if msg != "":
				show_info(msg)

		"start_game":
			_pending_end_ack = false
			_leave_sent = false
			_sent_leave_spectate = false
			_is_changing_scene = false
			hide()
			_mode = Mode.NONE

		"opponent_disconnected":
			var who := String(data.get("username", ""))
			_show_pause_choice("%s s'est déconnecté.\nAttendre ou revenir au lobby ?" % who)

		"opponent_online":
			var who := String(data.get("username", ""))
			var where := String(data.get("where", ""))
			if where == "lobby":
				_show_pause_choice("%s est revenu en ligne (lobby).\nAttends qu'il rejoigne la partie ?" % who)

		"opponent_rejoined":
			var who := String(data.get("username", ""))
			hide()
			_mode = Mode.NONE
			_show_pause_choice("%s a rejoint la partie." % who)

		"game_end":
			_pending_end_ack = true
			var winner := String(data.get("winner", ""))
			var reason := String(data.get("reason", ""))
			var msg := "Partie terminée.\n"
			if winner != "":
				msg += "Winner: %s\n" % winner
			if reason != "":
				msg += "Reason: %s\n" % reason
			msg += "Retour au lobby."
			show_info(msg)
		_:
			pass

func _on_response(_rid: String, type: String, ok: bool, _data: Dictionary, error: Dictionary) -> void:
	if type == "invite":
		if ok:
			show_info("Invitation envoyée.")
		else:
			show_info(String(error.get("error", "Invitation impossible")))

# -------------------------------------------------------------------
# Boutons (connectés dans WindowPopup.tscn)
# -------------------------------------------------------------------
func _on_button_accept_pressed() -> void:
	match _mode:
		Mode.INVITE:
			NetworkManager.request("invite_response", {"to": _inviter, "accepted": true})
		Mode.CONFIRM:
			if _yes_cb.is_valid():
				_yes_cb.call()
	hide()
	_mode = Mode.NONE

func _on_button_refuse_pressed() -> void:
	match _mode:
		Mode.INVITE:
			NetworkManager.request("invite_response", {"to": _inviter, "accepted": false})
		Mode.CONFIRM:
			if _no_cb.is_valid():
				_no_cb.call()
	hide()
	_mode = Mode.NONE

func _on_button_ok_pressed() -> void:
	hide()
	_mode = Mode.NONE

	if _pending_end_ack:
		_pending_end_ack = false
		if String(Global.current_game_id) != "":
			await NetworkManager.request_async("ack_game_end", {"game_id": String(Global.current_game_id)}, 4.0)
		await _go_to_lobby_safe()

# -------------------------------------------------------------------
# Internes "pause game"
# -------------------------------------------------------------------
func _show_pause_choice(msg: String) -> void:
	show_confirm(
		msg,
		"Attendre", "Retour lobby",
		Callable(), # attendre -> fermer
		Callable(self, "_leave_current_and_go_lobby")
	)

func _leave_current_and_go_lobby() -> void:
	if _leave_sent:
		return
	_leave_sent = true

	var gid := String(Global.current_game_id)
	if gid != "":
		var has_result := (Global.result is Dictionary and (Global.result as Dictionary).size() > 0)

		# ✅ Partie finie (result présent) => ACK obligatoire (joueur OU spectateur)
		if has_result:
			await NetworkManager.request_async("ack_game_end", {"game_id": gid}, 4.0)
		else:
			# ✅ Partie en cours
			if Global.is_spectator:
				# sortie unique spectateur
				await NetworkManager.request_async("ack_game_end", {"game_id": gid}, 4.0)
			else:
				# abandon volontaire joueur (ne pas await si ton protocole ne renvoie pas toujours)
				NetworkManager.request("leave_game", {"game_id": gid})

	Global.reset_game_state()
	await _go_to_lobby_safe()

func _go_to_lobby_safe() -> void:
	if _is_changing_scene:
		return
	_is_changing_scene = true

	get_viewport().gui_disable_input = true
	await get_tree().process_frame
	get_viewport().gui_disable_input = false

	get_tree().change_scene_to_file("res://Client/Scenes/Lobby.tscn")
