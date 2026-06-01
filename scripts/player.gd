## Player — Group 5: Fleet Group
## Handles 3-lane snapping movement, visuals drawn via _draw(),
## and item pickup via a child Area2D.2
extends CharacterBody2D

const LANE_POSITIONS: Array[float] = [250.0, 540.0, 830.0]
const LANE_SWITCH_SPEED: float     = 18.0   # tween duration divisor

var current_lane: int  = 1
var target_x: float    = 540.0
var is_penalized: bool = false
var penalty_timer: float = 0.0
var is_hit: bool = false
var hit_timer: float = 0.0

const HIT_FLASH_DURATION: float = 0.45

# ── FX anim durations / thresholds ───────────────────────────────────────
const SPEED_FX_DURATION:    float = 3.0
const REPAIRED_FX_DURATION: float = 1.0
const LOW_FUEL_THRESHOLD:   float = 25.0   # fuel <= this turns on LowFuel anim

@onready var speed_anim:    AnimatedSprite2D = $Speed
@onready var lowfuel_anim:  AnimatedSprite2D = $LowFuel
@onready var repaired_anim: AnimatedSprite2D = $Repaired

var _speed_fx_timer:    float = 0.0
var _repaired_fx_timer: float = 0.0

var _tween: Tween = null
var _shake_tween: Tween = null


func _ready() -> void:
	position.x = LANE_POSITIONS[current_lane]
	position.y = 1450.0
	$PickupArea.area_entered.connect(_on_pickup_area_entered)
	GameManager.hazard_hit.connect(_on_hazard_hit)
	GameManager.block_hit.connect(_on_block_hit)
	GameManager.powerup_collected.connect(_on_powerup_collected)
	GameManager.fuel_changed.connect(_on_fuel_changed)
	GameManager.game_over.connect(_on_game_over)
	_stop_all_fx_anims()


func _process(delta: float) -> void:
	if not GameManager.game_running:
		return
	if is_penalized:
		penalty_timer -= delta
		if penalty_timer <= 0.0:
			is_penalized = false
			queue_redraw()
	if is_hit:
		hit_timer -= delta
		if hit_timer <= 0.0:
			is_hit = false
			queue_redraw()

	if _speed_fx_timer > 0.0:
		_speed_fx_timer -= delta
		if _speed_fx_timer <= 0.0:
			_hide_anim(speed_anim)
	if _repaired_fx_timer > 0.0:
		_repaired_fx_timer -= delta
		if _repaired_fx_timer <= 0.0:
			_hide_anim(repaired_anim)


## Input layer.
##  - Keyboard A/Left, D/Right, Space (dump cargo), Esc (pause).
##  - Mobile: swipe horizontally (drag past SWIPE_THRESHOLD px) to switch lanes.
##  - No click / tap-to-move on either mouse or touch — buttons in the HUD
##    should never get hijacked by a stray screen tap, and on desktop the
##    keyboard handles lane switching.
##  - dump_cargo() is NOT bound to a screen-area tap; use the HUD DumpButton
##    on mobile or KEY_SPACE on desktop.
##
## Uses _unhandled_input (not _input) so HUD Buttons with mouse_filter=STOP
## (PauseButton, DumpButton, inventory slots) absorb their own taps first.
const SWIPE_THRESHOLD: float = 80.0

var _touch_start_pos: Vector2 = Vector2.ZERO
var _touch_is_swipe:  bool    = false


func _unhandled_input(event: InputEvent) -> void:
	if not GameManager.game_running:
		return

	# ── Keyboard ──────────────────────────────────────────────────────────
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_A, KEY_LEFT:   switch_lane(-1)
			KEY_D, KEY_RIGHT:  switch_lane(1)
			KEY_SPACE:         GameManager.dump_cargo()
			KEY_ESCAPE:        GameManager.pause()
		return

	# ── Touch press: track start position for swipe detection only ────────
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_start_pos = event.position
			_touch_is_swipe  = false
		# Release intentionally does NOTHING — no tap-to-switch.
		return

	# ── Touch drag: fire once per touch when swipe threshold is crossed ───
	if event is InputEventScreenDrag and not _touch_is_swipe:
		var dx: float = event.position.x - _touch_start_pos.x
		if absf(dx) >= SWIPE_THRESHOLD:
			_touch_is_swipe = true
			switch_lane(1 if dx > 0.0 else -1)


# ---------------------------------------------------------------------------
# Lane switching
# ---------------------------------------------------------------------------
func switch_lane(direction: int) -> void:
	var new_lane: int = clamp(current_lane + direction, 0, 2)
	if new_lane == current_lane:
		return
	current_lane = new_lane
	target_x = LANE_POSITIONS[current_lane]

	if _tween:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "position:x", target_x, 0.14)


# ---------------------------------------------------------------------------
# Pickup detection
# ---------------------------------------------------------------------------
func _on_pickup_area_entered(area: Area2D) -> void:
	if area.has_method("on_collected"):
		area.on_collected(self)


# ---------------------------------------------------------------------------
# Hazard penalty
# ---------------------------------------------------------------------------
func _on_hazard_hit() -> void:
	is_penalized = true
	penalty_timer = GameManager.HAZARD_PENALTY_DURATION
	queue_redraw()


func _on_block_hit() -> void:
	is_hit = true
	hit_timer = HIT_FLASH_DURATION
	queue_redraw()
	if _shake_tween:
		_shake_tween.kill()
	var origin_x := target_x
	_shake_tween = create_tween()
	_shake_tween.tween_property(self, "position:x", origin_x + 26.0, 0.05)
	_shake_tween.tween_property(self, "position:x", origin_x - 26.0, 0.05)
	_shake_tween.tween_property(self, "position:x", origin_x + 12.0, 0.04)
	_shake_tween.tween_property(self, "position:x", origin_x,         0.04)


# ---------------------------------------------------------------------------
# Drawing — simple truck shape using primitives
# ---------------------------------------------------------------------------
func _draw() -> void:
	var body_color: Color
	if is_penalized or is_hit:
		body_color = Color(0.85, 0.25, 0.10)
	else:
		body_color = Color(0.10, 0.35, 0.75)

	# Truck bed (back)
	draw_rect(Rect2(-50, 0, 100, 80), body_color.darkened(0.25))
	# Cab (front / top in portrait = going upward on screen)
	draw_rect(Rect2(-50, -80, 100, 80), body_color)
	# Windshield
	draw_rect(Rect2(-35, -72, 70, 40), Color(0.65, 0.88, 1.0, 0.85))
	# Headlights
	draw_rect(Rect2(-48, -82, 18, 10), Color(1.0, 0.95, 0.5))
	draw_rect(Rect2(30, -82, 18, 10), Color(1.0, 0.95, 0.5))
	# Wheels
	for pos in [Vector2(-48, -55), Vector2(48, -55), Vector2(-48, 60), Vector2(48, 60)]:
		draw_circle(pos, 16.0, Color(0.12, 0.12, 0.12))
		draw_circle(pos, 8.0, Color(0.35, 0.35, 0.35))
	# Shield indicator
	if GameManager.has_shield:
		draw_rect(Rect2(-54, -86, 108, 170), Color(0.0, 1.0, 0.4, 0.25))
		draw_rect(Rect2(-54, -86, 108, 4), Color(0.0, 1.0, 0.4, 0.8))
		draw_rect(Rect2(-54, 80, 108, 4), Color(0.0, 1.0, 0.4, 0.8))


# ---------------------------------------------------------------------------
# FX animations — Speed (3s after boost), Repaired (1s after repair),
# LowFuel (while fuel <= LOW_FUEL_THRESHOLD).
# ---------------------------------------------------------------------------
func _on_powerup_collected(type: String) -> void:
	match type:
		"SPEED_BOOST":
			_play_anim(speed_anim, &"Speedup")
			_speed_fx_timer = SPEED_FX_DURATION
		"REPAIR_KIT":
			_play_anim(repaired_anim, &"")
			_repaired_fx_timer = REPAIRED_FX_DURATION


func _on_fuel_changed(fuel: float) -> void:
	if fuel > 0.0 and fuel <= LOW_FUEL_THRESHOLD:
		if not lowfuel_anim.visible:
			_play_anim(lowfuel_anim, &"")
	else:
		if lowfuel_anim.visible:
			_hide_anim(lowfuel_anim)


func _on_game_over(_reason: String) -> void:
	_stop_all_fx_anims()


func _play_anim(anim: AnimatedSprite2D, animation_name: StringName) -> void:
	if anim == null:
		return
	anim.visible = true
	if not animation_name.is_empty():
		anim.animation = animation_name
	anim.frame = 0
	anim.play()


func _hide_anim(anim: AnimatedSprite2D) -> void:
	if anim == null:
		return
	anim.visible = false
	anim.stop()


func _stop_all_fx_anims() -> void:
	_speed_fx_timer = 0.0
	_repaired_fx_timer = 0.0
	_hide_anim(speed_anim)
	_hide_anim(lowfuel_anim)
	_hide_anim(repaired_anim)
