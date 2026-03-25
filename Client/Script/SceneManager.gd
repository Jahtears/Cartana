# SceneManager.gd — Autoload singleton
# Centralise tous les changements de scène.
extends Node

const SCENE_LOGIN := "res://Scenes/Login.tscn"
const SCENE_LOBBY := "res://Scenes/Lobby.tscn"
const SCENE_GAME  := "res://Scenes/Game.tscn"

var _is_changing := false


func go_to_login() -> void:
    _change_to(SCENE_LOGIN)

func go_to_lobby() -> void:
    _change_to(SCENE_LOBBY)

func go_to_game() -> void:
    _change_to(SCENE_GAME)


func _change_to(path: String) -> void:
    if _is_changing:
        return
    _is_changing = true
    var viewport := get_viewport()
    if viewport:
        viewport.gui_disable_input = true
    get_tree().change_scene_to_file(path)
    await get_tree().process_frame
    if viewport:
        viewport.gui_disable_input = false
    _is_changing = false
