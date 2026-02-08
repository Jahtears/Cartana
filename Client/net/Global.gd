#Golbal.gd v1.0
extends Node 
var username = ""
var current_game_id : String = ""
var players_in_game : Array = []
var current_games : Array = []
var pending_messages: Array = []
var is_spectator: bool = false
# --- AJOUTS ---
var view: String = ""                 # "player" | "spectator"
var result: Dictionary = {}            # {} si pas fini, sinon {winner,reason,by,at}
var table_slots: Array = []           # (player, type, index)
var last_turn: Dictionary = {}        # {current, turnNumber} (optionnel)
var ended: Dictionary = {}

func reset_game_state() -> void:
	current_game_id = ""
	players_in_game.clear()
	is_spectator = false
	view = ""
	result.clear()
	table_slots.clear()
	last_turn.clear()
