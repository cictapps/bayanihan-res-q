## Dialogue — displays multi-line dialogue boxes, pauses the game,
## and resumes when all lines are dismissed.
##
## USAGE (from anywhere):
##   GameManager.play_dialogue(4)
##
## LINE FORMAT (Dictionary, all optional except "text"):
##   "speaker": String — name shown above the text
##   "text":    String — body text
##   "img":     String — texture path for Character1 (right portrait)
##   "img2":    String — texture path for Character2 (left portrait)
##
## process_mode must be ALWAYS on the CanvasLayer (.tscn already set).

extends CanvasLayer

# ---------------------------------------------------------------------------
# Character sprite paths (handy aliases for line dictionaries below)
# ---------------------------------------------------------------------------
const CHAR_ASH:    String = "res://Character sprites/Ash.png"
const CHAR_LINNEA: String = "res://Character sprites/Linnea.png"
const CHAR_MAGNUS: String = "res://Character sprites/Magnus.png"
const CHAR_RAINE:  String = "res://Character sprites/Raine.png"
const CHAR_ROCKY:  String = "res://Character sprites/Rocky.png"
const CHAR_WENDY:  String = "res://Character sprites/Wendy.png"

# ---------------------------------------------------------------------------
# Dialogue data
# ---------------------------------------------------------------------------
const DIALOGUES: Dictionary = {
	1: [
		{
			"speaker": "RAINE",
			"text": "According to my calculations, emergency preparedness increases your survival probability by a ton!",
			"img":  CHAR_RAINE,
		},
		{
			"speaker": "WENDY",
			"text": "Nerd translation: pack up your supplies, charge your phones, and don't panic. Typhoon warnings exist for a reason. Evacuate when local authorities said so.",
			"img2":  CHAR_WENDY,
		},
		{
			"speaker": "RAINE",
			"text": "Just like my girl said—stay alert, vigilant, and safe, folks. Always prepare ahead of time!",
			"img":  CHAR_RAINE,
		},
		{
			"speaker": "BOTH",
			"text": "RES-Q Team, Roll out!",
			"img":  CHAR_RAINE,
			"img2": CHAR_WENDY,
		},
	],

	# ── Flood (Raine / Wendy) ────────────────────────────────────────────────
	2: [
		{
			"speaker": "RAINE",
			"text": "Statistically speaking, I think our survival rate has increased after that!",
			"img":  CHAR_RAINE,
		},
		{
			"speaker": "WENDY",
			"text": "Statistically speaking, we almost drove straight into that flood. Maybe avoid deep water next time; even six inches can stall a vehicle.",
			"img2":  CHAR_WENDY,
		},
		{
			"speaker": "RAINE",
			"text": "You heard my girl, folks. Don't drive into flooded roads; turn back and find your nearest evacuation center!",
			"img":  CHAR_RAINE,
		},
		{
			"speaker": "BOTH",
			"text": "RES-Q Team, Roll out!",
			"img":  CHAR_RAINE,
			"img2": CHAR_WENDY,
		},
	],

	# ── Earthquake (Rocky / Linnea) ──────────────────────────────────────────
	3: [
		{
			"speaker": "LINNEA",
			"text": "That shaking was intense… but hey, I didn't panic this time!",
			"img":  CHAR_LINNEA,
		},
		{
			"speaker": "ROCKY",
			"text": "You did great. Just remember to stay away from damaged buildings, trees, and poles after an earthquake, alright?",
			"img2":  CHAR_ROCKY,
		},
		{
			"speaker": "LINNEA",
			"text": "And Drop, Cover, and Hold when you're inside a building, right?",
			"img":  CHAR_LINNEA,
		},
		{
			"speaker": "ROCKY",
			"text": "That's right. Safety first, we'll handle the rest later.",
			"img2":  CHAR_ROCKY,
		},
	],

	# ── Volcanic Eruption (Ash / Magnus) ─────────────────────────────────────
	4: [
		{
			"speaker": "ASH",
			"text": "You saw that explosion too, right!? And that ash cloud looked like the end of the world!",
			"img":  CHAR_ASH,
		},
		{
			"speaker": "MAGNUS",
			"text": "Hard to miss the giant angry mountain, mister hero. People should evacuate immediately or stay indoors whenever there's heavy ashfall.",
			"img2":  CHAR_MAGNUS,
		},
		{
			"speaker": "ASH",
			"text": "Don't forget the masks! Protect your lungs, folks!",
			"img":  CHAR_ASH,
		},
		{
			"speaker": "BOTH",
			"text": "RES-Q Team, Roll out!",
			"img":  CHAR_ASH,
			"img2": CHAR_MAGNUS,
		},
	],
}

# ---------------------------------------------------------------------------
# Node references  (adjust paths if your scene hierarchy differs)
# ---------------------------------------------------------------------------
@onready var name_label:     Label = $Control/TextureRect/NameLabel
@onready var text_label:     Label = $Control/TextureRect/TextLabel
@onready var continue_label: Label = $Control/TextureRect/ContinueLabel
@onready var character1:     Sprite2D = $Character1
@onready var character2:     Sprite2D = $Character2

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------
var _lines:             Array = []
var _line_index:        int   = 0
var _active:            bool  = false
var _accept_input:      bool  = false   # one-frame delay so trigger tap doesn't skip line 0
var _was_running:       bool  = false
var _pause_menu_active: bool  = false   # true while the pause menu is open
var _last_advance_frame: int  = -1      # dedupe: touch + emulated-mouse fire same frame


func _ready() -> void:
	visible = false
	_clear_portraits()
	GameManager.dialogue_requested.connect(_on_dialogue_requested)

	# Track whether the pause menu is open so we can block dialogue clicks
	GameManager.game_paused.connect(_on_game_paused)
	GameManager.game_resumed.connect(_on_game_resumed)


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------
func _on_dialogue_requested(id: int) -> void:
	if not DIALOGUES.has(id):
		push_warning("Dialogue: no entry for id %d" % id)
		return
	if _active:
		return   # don't stack dialogues

	_lines        = DIALOGUES[id]
	_line_index   = 0
	_active       = true
	_accept_input = false
	_was_running  = GameManager.game_running

	get_tree().paused        = true
	GameManager.game_running = false

	visible = true
	_show_line()

	# Wait one frame before accepting input so the tap that opened dialogue
	# doesn't immediately advance past the first line
	await get_tree().process_frame
	_accept_input = true


# ---------------------------------------------------------------------------
# Show current line
# ---------------------------------------------------------------------------
func _show_line() -> void:
	var line = _lines[_line_index]

	var speaker: String = ""
	var text:    String = ""
	var img:     String = ""
	var img2:    String = ""

	if line is Dictionary:
		speaker = line.get("speaker", "")
		text    = line.get("text", "")
		img     = line.get("img", "")
		img2    = line.get("img2", "")
	else:
		text = str(line)

	name_label.text    = speaker
	name_label.visible = speaker != ""
	text_label.text    = text

	_apply_portrait(character1, img)
	_apply_portrait(character2, img2)

	var is_last: bool = (_line_index >= _lines.size() - 1)
	continue_label.text = "▼  tap / Enter to close" if is_last else "▼  tap / Enter"


func _apply_portrait(sprite: Sprite2D, path: String) -> void:
	if sprite == null:
		return
	if path == "":
		sprite.texture = null
		sprite.visible = false
		return
	var tex := load(path)
	if tex is Texture2D:
		sprite.texture = tex
		sprite.visible = true
	else:
		sprite.texture = null
		sprite.visible = false


func _clear_portraits() -> void:
	if character1 != null:
		character1.texture = null
		character1.visible = false
	if character2 != null:
		character2.texture = null
		character2.visible = false


# ---------------------------------------------------------------------------
# Input — advance or close.
# Uses _input (not _unhandled_input) so the overlay ColorRect / Panel
# can't swallow the click before it reaches us. Advance triggers:
#   - Mouse left-click
#   - Enter / KP Enter
#   - Space
# (Screen-touch is also accepted so tap-to-advance keeps working on mobile.)
# Only fires when dialogue is active, input is unlocked, AND pause menu
# is NOT open (so the dialogue box is frozen while pause menu is showing).
# ---------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if not _active or not _accept_input:
		return

	# ← KEY FIX: ignore taps/clicks while the pause menu is open
	if _pause_menu_active:
		return

	var advance: bool = false

	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				advance = true
			KEY_ESCAPE:
				# Forward ESC to pause system; dialogue will freeze via _on_game_paused
				get_viewport().set_input_as_handled()
				GameManager.pause()
				return

	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		advance = true

	elif event is InputEventScreenTouch and event.pressed:
		advance = true

	if advance:
		# Dedupe: with "Emulate Mouse From Touch" enabled (Godot default), a
		# single mobile tap fires both an InputEventScreenTouch AND an
		# InputEventMouseButton in the same frame — without this we'd skip
		# every other line and a 4-line dialogue would end after 2.
		var frame: int = Engine.get_process_frames()
		if frame == _last_advance_frame:
			get_viewport().set_input_as_handled()
			return
		_last_advance_frame = frame
		get_viewport().set_input_as_handled()
		_next_line()


# ---------------------------------------------------------------------------
# Pause menu opened — freeze dialogue input
# ---------------------------------------------------------------------------
func _on_game_paused() -> void:
	_pause_menu_active = true


# ---------------------------------------------------------------------------
# Pause menu closed — if dialogue is still active, re-pause the tree
# so the world stays frozen and dialogue resumes normally
# ---------------------------------------------------------------------------
func _on_game_resumed() -> void:
	_pause_menu_active = false
	if _active:
		# Pause menu handed control back but dialogue isn't done yet
		get_tree().paused        = true
		GameManager.game_running = false


# ---------------------------------------------------------------------------
# Advance lines
# ---------------------------------------------------------------------------
func _next_line() -> void:
	_line_index += 1
	if _line_index < _lines.size():
		_show_line()
	else:
		_end_dialogue()


# ---------------------------------------------------------------------------
# End: hide, unpause, resume game
# ---------------------------------------------------------------------------
func _end_dialogue() -> void:
	_active  = false
	visible  = false
	_clear_portraits()
	get_tree().paused = false
	if _was_running:
		GameManager.game_running = true
		GameManager.emit_signal("game_resumed")
