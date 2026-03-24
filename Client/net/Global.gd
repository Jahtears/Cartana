#Golbal.gd v1.0
extends Node

const SETTINGS_PATH := "user://client_settings.cfg"

var username = ""
var current_game_id: String = ""
var players_in_game: Array = []
var current_games: Array = []
var is_spectator: bool = false
var result: Dictionary = {} # {} si pas fini, sinon {winner}

func reset_game_state() -> void:
    current_game_id = ""
    players_in_game.clear()
    is_spectator = false
    result.clear()
