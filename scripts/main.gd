## Main — starts the gameplay BGM and stops any leftover ambient loops from
## a previous scene. (Loading overlay was removed from main.tscn, so there's
## nothing to fade out here anymore.)
extends Node2D


func _ready() -> void:
	AudioManager.stop_all_ambient()
	AudioManager.play_bgm("res://Sound Files/BGM_Gameplay.mp3")
