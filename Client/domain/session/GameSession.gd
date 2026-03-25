extends Node

# État global de la partie
var current_game_id: String = ""
var players_in_game: Array = []
var is_spectator: bool = false
var result: Dictionary = {}

func _ready():
    pass

func start_game(game_id: String, players: Array, spectator: bool) -> void:
    current_game_id = game_id
    players_in_game = players.duplicate()
    is_spectator = spectator
    result = {}

func end_game(res: Dictionary) -> void:
    result = res.duplicate()

func reset_game_state() -> void:
    current_game_id = ""
    players_in_game = []
    is_spectator = false
    result = {}

func is_game_ended() -> bool:
    return result is Dictionary and result.size() > 0

func get_opponent_name(self_name: String) -> String:
    var self_name_stripped := String(self_name).strip_edges()
    for player in players_in_game:
        var opponent_name: String = String(player)
        if opponent_name != self_name_stripped:
            return opponent_name
    return ""
