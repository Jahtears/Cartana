# ui/WindowPopup.gd
# Rendu popup pur.
# Ne normalise plus les messages lui-même — délègue à MessageCatalog.
extends Window
class_name WindowPopup

const Protocol = preload("res://net/Protocol.gd")

signal action_selected(action_id: String, payload: Dictionary)

const ACTION_CONFIRM_YES := Protocol.POPUP_ACTION_CONFIRM_YES
const ACTION_CONFIRM_NO  := Protocol.POPUP_ACTION_CONFIRM_NO
const ACTION_INFO_OK     := Protocol.POPUP_ACTION_INFO_OK

const MODE_PASSIVE := 0
const MODE_INFO    := 1
const MODE_CONFIRM := 2
const MODE_NONE    := -1

const OPTION_TEXT_OVERRIDE := "text_override"
const OPTION_YES_LABEL_KEY := "yes_label_key"
const OPTION_NO_LABEL_KEY  := "no_label_key"
const OPTION_OK_LABEL_KEY  := "ok_label_key"
const DEFAULT_YES_LABEL_KEY := "UI_LABEL_YES"
const DEFAULT_NO_LABEL_KEY  := "UI_LABEL_NO"
const DEFAULT_OK_LABEL_KEY  := "UI_LABEL_OK"

var _mode: int = MODE_NONE
var _payload: Dictionary = {}
var _options: Dictionary = {}
var _action_accept: String = ACTION_CONFIRM_YES
var _action_refuse: String = ACTION_CONFIRM_NO
var _action_ok:     String = ACTION_INFO_OK

@onready var _label:      Label  = $MarginContainer/VBox/MessageLabel
@onready var _btn_accept: Button = $MarginContainer/VBox/Buttons/ConfirmYesButton
@onready var _btn_refuse: Button = $MarginContainer/VBox/Buttons/ConfirmNoButton
@onready var _btn_ok:     Button = $MarginContainer/VBox/Buttons/InfoOkButton

func _ready() -> void:
  if not close_requested.is_connected(_on_close_requested):
    close_requested.connect(_on_close_requested)
  if not LanguageManager.language_changed.is_connected(_on_language_changed):
    LanguageManager.language_changed.connect(_on_language_changed)
  _apply_language_to_popup()
  hide_and_reset()


# ══════════════════════════════════════════════════════════
# API PUBLIQUE
# ══════════════════════════════════════════════════════════

## Affiche une popup à partir d'un code message + paramètres optionnels.
func show_code(
  p_mode: int,
  message_code: String,
  params: Dictionary = {},
  context: Dictionary = {},
  options: Dictionary = {}
) -> void:
  var safe_mode := _safe_mode(p_mode)
  var normalized := _normalize_payload(message_code, params, options)
  var actions    := _resolve_actions(safe_mode, options)
  _show_mode(safe_mode, normalized, context, options, actions)


## Affiche une popup à partir d'un payload déjà normalisé (via MessageCatalog).
func show_normalized(p_mode: int, normalized: Dictionary, context: Dictionary = {}, options: Dictionary = {}) -> void:
  if normalized.get("message_code", "") == "":
    return
  var actions := _resolve_actions(p_mode, options)
  _show_mode(p_mode, normalized, context, options, actions)


## Cache la popup et remet l'état à zéro.
func hide_and_reset() -> void:
  hide()
  _mode = MODE_NONE
  _payload.clear()
  _options.clear()
  _action_accept = ACTION_CONFIRM_YES
  _action_refuse = ACTION_CONFIRM_NO
  _action_ok     = ACTION_INFO_OK


# ══════════════════════════════════════════════════════════
# INTERNE
# ══════════════════════════════════════════════════════════

func _show_mode(
  p_mode: int,
  normalized: Dictionary,
  context: Dictionary,
  options: Dictionary,
  actions: Dictionary
) -> void:
  _mode = p_mode
  _payload = {}
  _payload["message_code"]   = String(normalized.get("message_code", ""))
  _payload["message_params"] = normalized.get("message_params", {})
  for key in context:
    _payload[key] = context[key]
  _options = options.duplicate(true)

  match p_mode:
    MODE_PASSIVE:
      _btn_accept.visible = false
      _btn_refuse.visible = false
      _btn_ok.visible     = false
    MODE_INFO:
      _action_ok = String(actions.get("ok", ACTION_INFO_OK))
      _btn_accept.visible = false
      _btn_refuse.visible = false
      _btn_ok.visible     = true
    _:
      _action_accept = String(actions.get("yes", ACTION_CONFIRM_YES))
      _action_refuse = String(actions.get("no",  ACTION_CONFIRM_NO))
      _btn_accept.visible = true
      _btn_refuse.visible = true
      _btn_ok.visible     = false

  _apply_language_to_popup()
  popup_centered()


## Normalise un code + params en payload affichable via MessageCatalog.
func _normalize_payload(message_code: String, params: Dictionary, options: Dictionary) -> Dictionary:
  var payload: Dictionary = {
    "message_code":   message_code,
    "message_params": params,
  }
  var text_override := String(options.get(OPTION_TEXT_OVERRIDE, "")).strip_edges()
  if text_override != "":
    payload["text"] = text_override
  # Délégation à MessageCatalog — plus de logique de normalisation ici.
  return MessageCatalog.normalize_popup_message(payload)


func _resolve_message_text(normalized: Dictionary, options: Dictionary) -> String:
  var text_override := String(options.get(OPTION_TEXT_OVERRIDE, "")).strip_edges()
  if text_override != "":
    return text_override
  return String(normalized.get("text", ""))


func _resolve_label(options: Dictionary, option_key: String, default_label_key: String) -> String:
  var label_key := String(options.get(option_key, default_label_key)).strip_edges()
  return MessageCatalog.popup_label(label_key)


func _apply_language_to_popup() -> void:
  title = LanguageManager.ui_text("UI_POPUP_WINDOW_TITLE", "Information")
  if _mode == MODE_NONE:
    return

  var msg_code   := String(_payload.get("message_code", "")).strip_edges()
  var params_val  = _payload.get("message_params", {})
  var params: Dictionary = params_val if params_val is Dictionary else {}
  var normalized := _normalize_payload(msg_code, params, _options)
  _label.text = _resolve_message_text(normalized, _options)

  match _mode:
    MODE_INFO:
      _btn_ok.text = _resolve_label(_options, OPTION_OK_LABEL_KEY, DEFAULT_OK_LABEL_KEY)
    MODE_CONFIRM:
      _btn_accept.text = _resolve_label(_options, OPTION_YES_LABEL_KEY, DEFAULT_YES_LABEL_KEY)
      _btn_refuse.text = _resolve_label(_options, OPTION_NO_LABEL_KEY,  DEFAULT_NO_LABEL_KEY)


func _resolve_actions(_p_mode: int, options: Dictionary) -> Dictionary:
  return {
    "ok":  options.get("ok_action_id",  ACTION_INFO_OK),
    "yes": options.get("yes_action_id", ACTION_CONFIRM_YES),
    "no":  options.get("no_action_id",  ACTION_CONFIRM_NO),
  }


func _safe_mode(p_mode: int) -> int:
  if p_mode == MODE_PASSIVE or p_mode == MODE_INFO or p_mode == MODE_CONFIRM:
    return p_mode
  return MODE_INFO


# ══════════════════════════════════════════════════════════
# SIGNAUX
# ══════════════════════════════════════════════════════════

func _on_button_accept_pressed() -> void:
  if _mode == MODE_CONFIRM:
    action_selected.emit(_action_accept, _payload.duplicate(true))
  hide_and_reset()

func _on_button_refuse_pressed() -> void:
  if _mode == MODE_CONFIRM:
    action_selected.emit(_action_refuse, _payload.duplicate(true))
  hide_and_reset()

func _on_button_ok_pressed() -> void:
  if _mode == MODE_INFO:
    action_selected.emit(_action_ok, _payload.duplicate(true))
  hide_and_reset()

func _on_close_requested() -> void:
  hide_and_reset()

func _on_language_changed(_language_code: String) -> void:
  _apply_language_to_popup()

func _exit_tree() -> void:
  if LanguageManager.language_changed.is_connected(_on_language_changed):
    LanguageManager.language_changed.disconnect(_on_language_changed)
