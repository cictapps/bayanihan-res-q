extends CanvasLayer
@onready var camera: Camera2D = $"../Camera2D"

# [CALM=0, TYPHOON=1, FLOODING=2, EARTHQUAKE=3, VOLCANIC=4]
const _INITIAL_EVENT_WEIGHTS: Array[int] = [40, 15, 15, 15, 15]
var _event_weights: Array[int] = _INITIAL_EVENT_WEIGHTS.duplicate()
var event_state: int = 0

# SFX played on each screen-shake tick during quake / volcanic events.
const SHAKE_SFX: Array[String] = [
	"res://Sound Files/Earthquake/Earthquake rumbling.mp3",
	"res://Sound Files/Earthquake/Falling rocks, crumbling building.mp3",
]

# [RICE=0, WATER=1, MEDS=2, HAZARD=3, BLOCK=4, SHIELD=5, SPEED=6, FUEL=7, REPAIR=8]
var _current_event_bonus: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0]

var _anim_timer: float = 0.0
var _next_anim_time: float = 0.0
var _shake_intensity: float = 0.0
var _shake_timer: float = 0.0


func _ready() -> void:
	GameManager.level_up.connect(_on_level_up)
	_roll_next_anim_time()


func _process(delta: float) -> void:
	if not GameManager.game_running:
		return

	# Screen shake
	if _shake_timer > 0.0:
		_shake_timer -= delta
		camera.offset = Vector2(
			randf_range(-_shake_intensity, _shake_intensity),
			randf_range(-_shake_intensity, _shake_intensity)
		)
	else:
		camera.offset = Vector2.ZERO

	# Animation timer
	_anim_timer += delta
	if _anim_timer >= _next_anim_time:
		_roll_next_anim_time()
		if event_state == 3 or event_state == 4:   # EARTHQUAKE / VOLCANIC
			_start_shake(12.0, 0.6)
			AudioManager.play_sfx_random(SHAKE_SFX)


func _start_shake(intensity: float, duration: float) -> void:
	_shake_intensity = intensity
	_shake_timer = duration


# Per-event shake cadence (seconds between ticks).
func _roll_next_anim_time() -> void:
	match event_state:
		3:  # EARTHQUAKE — faster, tighter shakes
			_next_anim_time = randf_range(1.0, 2.0)
		4:  # VOLCANIC — slower, sparser shakes
			_next_anim_time = randf_range(2.0, 5.0)
		_:
			_next_anim_time = randf_range(1.0, 5.0)
	_anim_timer = 0.0


func _on_level_up(lvl: int) -> void:
	if lvl <= 1:
		# Fresh game / restart: wipe leftover state from the previous run so
		# the road resets to CALM (grass) instead of inheriting a flood / quake
		# overlay. Clearing _current_event_bonus first ensures _apply_event
		# doesn't try to subtract last run's bonus from the spawner weights.
		_event_weights = _INITIAL_EVENT_WEIGHTS.duplicate()
		_current_event_bonus = [0, 0, 0, 0, 0, 0, 0, 0, 0]
		event_state = 0
		_shake_intensity = 0.0
		_shake_timer = 0.0
		if camera != null:
			camera.offset = Vector2.ZERO
		_apply_event.call_deferred(0)   # CALM — hides Typhoon/Flooding/etc.
		return
	if lvl >= 8:
		_event_weights[0] = max(_event_weights[0] - 2, 10)
		_event_weights[1] = min(_event_weights[1] + 1, 25)
		_event_weights[2] = min(_event_weights[2] + 1, 25)
		_event_weights[3] = min(_event_weights[3] + 1, 25)
		_event_weights[4] = min(_event_weights[4] + 1, 25)
	if lvl == 1 or lvl == 3 or lvl == 5 or lvl == 6 or lvl == 8 or lvl == 9:
		_apply_event.call_deferred(0) # CALM
	elif lvl == 2:
		_apply_event.call_deferred(1) # TYPHOON
		await get_tree().create_timer(0.5).timeout
		GameManager.play_dialogue(1)
	elif lvl == 4:
		_apply_event.call_deferred(2)   # FLOODING
		await get_tree().create_timer(0.5).timeout
		GameManager.play_dialogue(2)
	elif lvl == 7:
		_apply_event.call_deferred(3)   # EARTHQUAKE
		await get_tree().create_timer(0.5).timeout
		GameManager.play_dialogue(3)
	elif lvl == 10:
		_apply_event.call_deferred(4)   # VOLCANIC
		await get_tree().create_timer(0.5).timeout
		GameManager.play_dialogue(4)
	else:
		_apply_event.call_deferred(_weighted_random())


func _weighted_random() -> int:
	var total: int = 0
	for w in _event_weights:
		total += w
	var roll: int = randi() % total
	var cumulative: int = 0
	for i in _event_weights.size():
		cumulative += _event_weights[i]
		if roll < cumulative:
			return i
	return 0


func _apply_event(idx: int) -> void:
	var spawner = get_tree().get_first_node_in_group("spawner")
	if not spawner:
		return

	# Undo previous event bonus
	for i in _current_event_bonus.size():
		spawner._spawn_weights[i] -= _current_event_bonus[i]

	# Hide all visuals
	$Typhoon.hide()
	$Flooding.hide()
	$Earthquake.hide()
	$Volcanic.hide()

	# Reset
	_current_event_bonus = [0, 0, 0, 0, 0, 0, 0, 0, 0]
	event_state = idx
	GameManager.set_hazard_event(event_state)
	_roll_next_anim_time()

	match idx:
		0:  # CALM
			pass

		1:  # TYPHOON
			_current_event_bonus[4] =  20
			_current_event_bonus[3] =  20
			_current_event_bonus[0] = -6
			_current_event_bonus[1] = -6
			$Typhoon.show()


		2:  # FLOODING
			_current_event_bonus[4] =  20
			_current_event_bonus[3] =  -20
			_current_event_bonus[0] = -5
			_current_event_bonus[2] = -5
			$Flooding.show()

		3:  # EARTHQUAKE
			_current_event_bonus[4] = 30
			_current_event_bonus[3] = -30
			_current_event_bonus[2] =  5
			_current_event_bonus[0] = -5
			$Earthquake.show()

		4:  # VOLCANIC
			_current_event_bonus[4] = 40
			_current_event_bonus[3] = -40
			_current_event_bonus[1] = -5
			_current_event_bonus[2] = -5
			$Volcanic.show()

	# Add new bonus
	for i in _current_event_bonus.size():
		spawner._spawn_weights[i] += _current_event_bonus[i]

	_apply_event_ambient(idx)


# Looped ambient soundscape per hazard. Switching events swaps streams; CALM
# silences everything.
func _apply_event_ambient(idx: int) -> void:
	AudioManager.stop_all_ambient()
	match idx:
		1:  # TYPHOON
			AudioManager.play_ambient("rain",
					"res://Sound Files/Typhoon/Heavy rain and thunder.mp3")
		2:  # FLOODING
			AudioManager.play_ambient("rain",
					"res://Sound Files/Typhoon/Heavy rain and thunder.mp3")
			AudioManager.play_ambient("waves",
					"res://Sound Files/Typhoon/Waves Crash.mp3")
		3, 4:  # EARTHQUAKE / VOLCANIC
			AudioManager.play_ambient("siren",
					"res://Sound Files/Siren.mp3")
