## Loading — quick 1-second fake loading screen between the menu and main.tscn.
## The progress bar fills smoothly across the duration, then the main scene loads.
extends Node2D

const LOAD_DURATION: float = 1.0
const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"

@onready var loading_bar: TextureProgressBar = $HUD/LoadingBar


func _ready() -> void:
	if loading_bar != null:
		loading_bar.max_value = 100.0
		loading_bar.value     = 0.0

	var tween := create_tween()
	if loading_bar != null:
		tween.tween_property(loading_bar, "value", 100.0, LOAD_DURATION)
	else:
		tween.tween_interval(LOAD_DURATION)
	tween.tween_callback(_go_to_main)


func _go_to_main() -> void:
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)
