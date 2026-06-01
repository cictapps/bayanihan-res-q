extends CanvasLayer

func _ready() -> void:
	visible = false
	GameManager.game_paused.connect(_on_paused)
	GameManager.game_resumed.connect(_on_resumed)

	# Node names are legacy: the top slider (BGMSlider) is the SFX one in the
	# layout, and the bottom slider (SFXSlider) is the BGM one. We wire the
	# callables to match the visible position, not the node name.
	_wire_slider(get_node_or_null("TextureRect/BGMSlider") as HSlider,
			AudioManager.sfx_volume, Callable(AudioManager, "set_sfx_volume"))
	_wire_slider(get_node_or_null("TextureRect/SFXSlider") as HSlider,
			AudioManager.bgm_volume, Callable(AudioManager, "set_bgm_volume"))


func _wire_slider(slider: HSlider, current_value: float, on_change: Callable) -> void:
	if slider == null:
		return
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step      = 1.0
	slider.value     = current_value
	if not slider.value_changed.is_connected(on_change):
		slider.value_changed.connect(on_change)

func _on_paused() -> void:
	visible = true

func _on_resumed() -> void:
	visible = false

func _on_play_button_pressed() -> void:
	GameManager.resume()


func _on_replay_button_pressed() -> void:
	get_tree().paused = false
	GameManager.end_game("RESTARTED")
	AudioManager.stop_all()
	get_tree().reload_current_scene()


func _on_menu_button_pressed() -> void:
	get_tree().paused = false
	GameManager.end_game("RETURN TO MENU")
	AudioManager.stop_all()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_exit_button_pressed() -> void:
	GameManager.resume()
