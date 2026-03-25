# Global.gd v2.0
extends Node

# Chemin du fichier de configuration utilisateur
const SETTINGS_PATH := "user://client_settings.cfg"
const SETTINGS_SECTION_LOGIN := "login"
const SETTINGS_KEY_USERNAME := "username"
const SETTINGS_SECTION_I18N := "i18n"
const SETTINGS_KEY_LANGUAGE := "language"
const SETTINGS_SECTION_CARDS := "cards"
const SETTINGS_KEY_CARD_BACK_A := "card_back_a"
const SETTINGS_KEY_CARD_BACK_B := "card_back_b"

# Login utilisateur courant
var username: String = ""
# Langue courante
var language: String = "fr"
# Dos de carte courant 
var card_back_a: String = "Dos01"
var card_back_b: String = "Dos02"

# Chargement des settings au démarrage
func load_settings() -> void:
  var config := ConfigFile.new()
  var result := config.load(SETTINGS_PATH)
  if result == OK:
    username = String(config.get_value(SETTINGS_SECTION_LOGIN, SETTINGS_KEY_USERNAME, ""))
    language = String(config.get_value(SETTINGS_SECTION_I18N, SETTINGS_KEY_LANGUAGE, "fr"))
    card_back_a = String(config.get_value(SETTINGS_SECTION_CARDS, SETTINGS_KEY_CARD_BACK_A, "Dos01"))
    card_back_b = String(config.get_value(SETTINGS_SECTION_CARDS, SETTINGS_KEY_CARD_BACK_B, "Dos02"))
# Sauvegarde du login
func save_username(new_username: String) -> void:
  var config := ConfigFile.new()
  config.load(SETTINGS_PATH)
  config.set_value(SETTINGS_SECTION_LOGIN, SETTINGS_KEY_USERNAME, new_username)
  config.save(SETTINGS_PATH)
  username = new_username

# Accès au login



# Chargement auto des settings au démarrage
func _ready() -> void:
  load_settings()

# Sauvegarde du dos de carte source A
func save_card_back_a(new_card_back: String) -> void:
  var config := ConfigFile.new()
  config.load(SETTINGS_PATH)
  config.set_value(SETTINGS_SECTION_CARDS, SETTINGS_KEY_CARD_BACK_A, new_card_back)
  config.save(SETTINGS_PATH)
  card_back_a = new_card_back

# Sauvegarde du dos de carte source B
func save_card_back_b(new_card_back: String) -> void:
  var config := ConfigFile.new()
  config.load(SETTINGS_PATH)
  config.set_value(SETTINGS_SECTION_CARDS, SETTINGS_KEY_CARD_BACK_B, new_card_back)
  config.save(SETTINGS_PATH)
  card_back_b = new_card_back

# Sauvegarde de la langue
func save_language(new_language: String) -> void:
  var config := ConfigFile.new()
  config.load(SETTINGS_PATH)
  config.set_value(SETTINGS_SECTION_I18N, SETTINGS_KEY_LANGUAGE, new_language)
  config.save(SETTINGS_PATH)
  language = new_language

## Utilitaires pour accès global
func get_username() -> String:
  return username

func get_language() -> String:
  return language

func get_card_back_a() -> String:
  return card_back_a

func get_card_back_b() -> String:
  return card_back_b
