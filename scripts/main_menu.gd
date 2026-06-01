extends Node2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$HUD2.visible = false

	# Replay button is only available once the player has watched the prologue
	# at least once. (Otherwise they'd see it spoiler-ish from the menu.)
	var replay_btn := get_node_or_null("How to play/ReplayPrologueButton")
	if replay_btn != null:
		(replay_btn as CanvasItem).visible = GameManager.prologue_seen

	AudioManager.stop_all_ambient()
	AudioManager.play_bgm("res://Sound Files/BGM_MainMenu.mp3")

	# Node names are legacy: the top slider (BGMSlider) is the SFX one in the
	# layout, and the bottom slider (SFXSlider) is the BGM one. We wire the
	# callables to match the visible position, not the node name.
	_wire_slider($HUD2/TextureRect/BGMSlider, AudioManager.sfx_volume,
			Callable(AudioManager, "set_sfx_volume"))
	_wire_slider($HUD2/TextureRect/SFXSlider, AudioManager.bgm_volume,
			Callable(AudioManager, "set_bgm_volume"))


func _wire_slider(slider: HSlider, current_value: float, on_change: Callable) -> void:
	if slider == null:
		return
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step      = 1.0
	slider.value     = current_value
	if not slider.value_changed.is_connected(on_change):
		slider.value_changed.connect(on_change)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_play_button_pressed() -> void:
	# First-time players watch the prologue video; returning players go
	# straight to main.tscn (which runs its own 1-second loading overlay).
	if GameManager.prologue_seen:
		get_tree().change_scene_to_file("res://scenes/main.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/prologue.tscn")


func _on_menu_button_pressed() -> void:
	if $HUD2.visible == false:
		$HUD2.visible = true
	else:
		$HUD2.visible = false


func _on_exit_button_pressed() -> void:
	$HUD2.visible = false


func _on_how_button_pressed() -> void:
	if $"How to play".visible == false:
		$"How to play".visible = true
	else:
		$"How to play".visible = false

func _on_exit_htp_button_pressed() -> void:
	$"How to play".visible = false


func _on_replay_prologue_button_pressed() -> void:
	# prologue_seen is already true here (the button is hidden otherwise),
	# so prologue.gd will route back to the main menu when it finishes.
	get_tree().change_scene_to_file("res://scenes/prologue.tscn")
