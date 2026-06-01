## Prologue — shown to first-time players.
##
## Flow:
##   1) Show the loading overlay for 1 second (progress bar fills).
##   2) Hide the overlay and start the prologue video.
##   3) When the video finishes, mark the prologue as seen and load main.tscn.
##
## Skips straight to main if the user taps / clicks / presses any key while
## the video is playing (typical "press anything to skip" pattern).
extends Node2D

const LOAD_DURATION:   float  = 3.0
const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
const MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const PROGRESS_FILL_PATH: String = "res://UI Deliverables/Loading Bar Overlay/LoadingBar.png"

@onready var video:       VideoStreamPlayer  = $VideoStreamPlayer
@onready var hud:         CanvasLayer        = $HUD
@onready var loading_bar: TextureProgressBar = $HUD/LoadingBar

var _video_started:  bool = false
var _scene_changing: bool = false


func _ready() -> void:
	# Silence menu BGM / ambient so the video's own audio isn't fighting it.
	AudioManager.stop_bgm()
	AudioManager.stop_all_ambient()

	# The VideoStreamPlayer is authored with autoplay=true; stop it so the
	# loading phase actually shows before the video begins.
	if video != null:
		video.stop()
		video.finished.connect(_on_video_finished)

	if hud != null:
		hud.visible = true
	if loading_bar != null:
		# The scene only has texture_under / texture_over — no fill texture —
		# so the value tween was invisible. Assign the fill here.
		if loading_bar.texture_progress == null and ResourceLoader.exists(PROGRESS_FILL_PATH):
			loading_bar.texture_progress = load(PROGRESS_FILL_PATH)
		loading_bar.min_value = 0.0
		loading_bar.max_value = 100.0
		loading_bar.value     = 0.0

	var tween := create_tween()
	if loading_bar != null:
		tween.tween_property(loading_bar, "value", 100.0, LOAD_DURATION)
	else:
		tween.tween_interval(LOAD_DURATION)
	tween.tween_callback(_start_video)


func _start_video() -> void:
	if hud != null:
		hud.visible = false
	if video != null:
		video.play()
	_video_started = true


func _unhandled_input(event: InputEvent) -> void:
	# Allow tap / click / any key to skip the video once it's started.
	if not _video_started:
		return
	var skip := false
	if event is InputEventKey and event.pressed and not event.echo:
		skip = true
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		skip = true
	elif event is InputEventScreenTouch and event.pressed:
		skip = true
	if skip:
		get_viewport().set_input_as_handled()
		_finish_prologue()


func _on_video_finished() -> void:
	_finish_prologue()


func _finish_prologue() -> void:
	if _scene_changing:
		return
	_scene_changing = true
	# First viewing → on to main gameplay; replay (already-seen) → back to menu.
	var was_seen := GameManager.prologue_seen
	GameManager.mark_prologue_seen()
	var next_scene := MENU_SCENE_PATH if was_seen else MAIN_SCENE_PATH
	get_tree().change_scene_to_file(next_scene)
