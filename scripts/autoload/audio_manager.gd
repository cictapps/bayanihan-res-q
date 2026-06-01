## AudioManager — global BGM + SFX with persisted volume sliders (0–100).
##
## USAGE:
##   AudioManager.play_bgm("res://Sound Files/BGM_MainMenu.mp3")
##   AudioManager.play_sfx("res://Sound Files/HitDebris1.MP3")
##   AudioManager.play_sfx_random([path_a, path_b, ...])
##   AudioManager.play_ambient("rain", "res://Sound Files/Typhoon/...mp3")
##   AudioManager.stop_ambient("rain")
##   AudioManager.stop_all_ambient()
##   AudioManager.set_bgm_volume(75.0)   # 0..100
##   AudioManager.set_sfx_volume(50.0)
##
## SFX-bus volume covers both one-shot SFX and ambient loops.
extends Node

const SETTINGS_PATH:        String = "user://settings.cfg"
const SFX_POOL_SIZE:        int    = 8
const AMBIENT_VOLUME_SCALE: float  = 0.65   # ambient loops sit under one-shots

signal volume_changed(bgm: float, sfx: float)

# ---------------------------------------------------------------------------
# Players
# ---------------------------------------------------------------------------
var _bgm_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _ambient_players: Dictionary = {}   # slot:String -> AudioStreamPlayer
var _stream_cache: Dictionary = {}

# Refcounted ambient sources (e.g. live electrical posts).
# slot_name:String -> Dictionary[source_object -> true]
var _ambient_sources: Dictionary = {}

const SPARK_SLOT: String = "electric_sparks"
const SPARK_PATH: String = "res://Sound Files/Earthquake/Electric sparks.mp3"

# ---------------------------------------------------------------------------
# Settings (0..100)
# ---------------------------------------------------------------------------
var bgm_volume: float = 100.0
var sfx_volume: float = 100.0

var _current_bgm_path: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_bgm_player = _make_player()
	add_child(_bgm_player)

	for i in SFX_POOL_SIZE:
		var p := _make_player()
		add_child(p)
		_sfx_players.append(p)

	_load_settings()
	_apply_all_volumes()


# ---------------------------------------------------------------------------
# BGM
# ---------------------------------------------------------------------------
func play_bgm(path: String, force_restart: bool = false) -> void:
	if path == _current_bgm_path and _bgm_player.playing and not force_restart:
		return
	var stream: AudioStream = _load_stream(path)
	if stream == null:
		return
	_set_loop(stream)
	_current_bgm_path = path
	_bgm_player.stream = stream
	_bgm_player.volume_db = _bgm_db()
	_bgm_player.play()


func stop_bgm() -> void:
	_current_bgm_path = ""
	_bgm_player.stop()


# ---------------------------------------------------------------------------
# One-shot SFX
# ---------------------------------------------------------------------------
func play_sfx(path: String) -> void:
	if path == "":
		return
	var stream: AudioStream = _load_stream(path)
	if stream == null:
		return
	var p := _find_free_sfx_player()
	p.stream = stream
	p.volume_db = _sfx_db(1.0)
	p.play()


func play_sfx_random(paths: Array) -> void:
	if paths.is_empty():
		return
	play_sfx(paths[randi() % paths.size()])


# ---------------------------------------------------------------------------
# Looped ambient SFX (one stream per slot)
# ---------------------------------------------------------------------------
func play_ambient(slot: String, path: String) -> void:
	var p := _get_or_make_ambient(slot)
	var stream: AudioStream = _load_stream(path)
	if stream == null:
		p.stop()
		return
	_set_loop(stream)
	if p.stream == stream and p.playing:
		# Already playing the right thing — just keep going.
		p.volume_db = _sfx_db(AMBIENT_VOLUME_SCALE)
		return
	p.stream = stream
	p.volume_db = _sfx_db(AMBIENT_VOLUME_SCALE)
	p.play()


func stop_ambient(slot: String) -> void:
	if _ambient_players.has(slot):
		(_ambient_players[slot] as AudioStreamPlayer).stop()


func stop_all_ambient() -> void:
	for p in _ambient_players.values():
		(p as AudioStreamPlayer).stop()


## Hard stop: BGM + every ambient loop + every in-flight one-shot.
## Use on hard transitions (restart, return-to-menu) so nothing leaks across.
func stop_all() -> void:
	stop_bgm()
	stop_all_ambient()
	for p in _sfx_players:
		p.stop()
	_ambient_sources.clear()


# ---------------------------------------------------------------------------
# Refcounted ambient — start when first source registers, stop when last
# source unregisters. Used for "as long as any X is on screen" loops.
# ---------------------------------------------------------------------------
func register_ambient_source(slot: String, path: String, source: Object) -> void:
	if source == null:
		return
	var sources: Dictionary = _ambient_sources.get(slot, {})
	var was_empty: bool = sources.is_empty()
	sources[source] = true
	_ambient_sources[slot] = sources
	if was_empty:
		play_ambient(slot, path)


func unregister_ambient_source(slot: String, source: Object) -> void:
	if source == null or not _ambient_sources.has(slot):
		return
	var sources: Dictionary = _ambient_sources[slot]
	sources.erase(source)
	if sources.is_empty():
		_ambient_sources.erase(slot)
		stop_ambient(slot)


# Convenience wrappers for the electrical-post sparks ambient.
func register_spark_source(source: Object) -> void:
	register_ambient_source(SPARK_SLOT, SPARK_PATH, source)


func unregister_spark_source(source: Object) -> void:
	unregister_ambient_source(SPARK_SLOT, source)


# ---------------------------------------------------------------------------
# Volume controls
# ---------------------------------------------------------------------------
func set_bgm_volume(v: float) -> void:
	bgm_volume = clamp(v, 0.0, 100.0)
	_bgm_player.volume_db = _bgm_db()
	_save_settings()
	emit_signal("volume_changed", bgm_volume, sfx_volume)


func set_sfx_volume(v: float) -> void:
	sfx_volume = clamp(v, 0.0, 100.0)
	for p in _sfx_players:
		p.volume_db = _sfx_db(1.0)
	for p in _ambient_players.values():
		(p as AudioStreamPlayer).volume_db = _sfx_db(AMBIENT_VOLUME_SCALE)
	_save_settings()
	emit_signal("volume_changed", bgm_volume, sfx_volume)


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------
func _make_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	return p


func _get_or_make_ambient(slot: String) -> AudioStreamPlayer:
	if _ambient_players.has(slot):
		return _ambient_players[slot]
	var p := _make_player()
	add_child(p)
	_ambient_players[slot] = p
	return p


func _find_free_sfx_player() -> AudioStreamPlayer:
	for p in _sfx_players:
		if not p.playing:
			return p
	# All busy — recycle the first one.
	_sfx_players[0].stop()
	return _sfx_players[0]


func _bgm_db() -> float:
	return _volume_to_db(bgm_volume)


func _sfx_db(scale: float) -> float:
	return _volume_to_db(sfx_volume * scale)


func _volume_to_db(v: float) -> float:
	if v <= 0.0:
		return -80.0
	return linear_to_db(clamp(v, 0.0, 100.0) / 100.0)


func _set_loop(stream: AudioStream) -> void:
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD


func _apply_all_volumes() -> void:
	_bgm_player.volume_db = _bgm_db()
	for p in _sfx_players:
		p.volume_db = _sfx_db(1.0)
	for p in _ambient_players.values():
		(p as AudioStreamPlayer).volume_db = _sfx_db(AMBIENT_VOLUME_SCALE)


func _load_stream(path: String) -> AudioStream:
	if _stream_cache.has(path):
		return _stream_cache[path]
	if not ResourceLoader.exists(path):
		push_warning("AudioManager: missing audio file '%s'" % path)
		return null
	var res: Resource = load(path)
	if res is AudioStream:
		_stream_cache[path] = res
		return res
	push_warning("AudioManager: '%s' is not an AudioStream" % path)
	return null


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------
func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		bgm_volume = cfg.get_value("audio", "bgm", 100.0)
		sfx_volume = cfg.get_value("audio", "sfx", 100.0)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "bgm", bgm_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.save(SETTINGS_PATH)
