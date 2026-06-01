## GameManager — Global Singleton (Autoload)
## Central hub for game state, signals, and shared logic.
## All groups communicate through this node using signals.
extends Node

# ---------------------------------------------------------------------------
# Signals (standardised interface between groups)
# ---------------------------------------------------------------------------
signal resource_collected(type: String)
signal hazard_hit
signal block_hit
signal powerup_collected(type: String)
signal fuel_collected
signal game_over(reason: String)
signal demand_fulfilled(barangay_id: int)
signal inventory_changed(inventory: Array)
signal score_changed(score: int)
signal durability_changed(durability: int)
signal fuel_changed(fuel: float)
signal speed_changed(speed: float)
signal demand_updated(demand: Array)
signal level_up(level: int)
signal combo_changed(combo: int)
signal game_paused
signal game_resumed
signal dialogue_requested(id: int)
signal hazard_event_changed(event: int)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
const MAX_INVENTORY: int   = 3
const MAX_DURABILITY: int  = 3
const BASE_SPEED: float    = 400.0
const MAX_SPEED: float     = 900.0
const SPEED_INCREMENT: float = 20.0
const FUEL_DRAIN_RATE: float = 4.5   # base value
const FUEL_PICKUP_AMOUNT: float = 40.0
const HAZARD_SPEED_PENALTY: float = 160.0
const HAZARD_PENALTY_DURATION: float = 2.0
const DEMANDS_PER_LEVEL: int = 3
const FUEL_DRAIN_INCREASE: float = 0.4   # added per level

const RESOURCE_TYPES: Array[String] = ["RICE", "WATER", "MEDS"]

# ---------------------------------------------------------------------------
# Runtime state
# ---------------------------------------------------------------------------
var score: int        = 0
var durability: int   = MAX_DURABILITY
var game_running: bool = false
var game_speed: float = BASE_SPEED
var fuel: float       = 100.0
var has_shield: bool  = false
var inventory: Array  = []
var current_demand: Array = []
var current_hazard_event: int = 0

var level: int = 1
var demands_fulfilled_count: int = 0
var combo: int = 0
var high_score: int = 0
var fuel_drain_rate: float = FUEL_DRAIN_RATE
var prologue_seen: bool = false


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	randomize()
	_load_high_score()


func _process(delta: float) -> void:
	if not game_running:
		return
	_drain_fuel(delta)

func _notification(what: int) -> void:
	if not game_running:
		return
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:  # phone / tab switch
			pause()
		NOTIFICATION_WM_WINDOW_FOCUS_OUT:    # desktop window unfocus
			pause()
# ---------------------------------------------------------------------------
# Game flow
# ---------------------------------------------------------------------------
func start_game() -> void:
	score      = 0
	durability = MAX_DURABILITY
	game_speed = BASE_SPEED
	fuel       = 100.0
	has_shield = false
	inventory.clear()
	level                  = 1
	demands_fulfilled_count = 0
	combo                  = 0
	fuel_drain_rate        = FUEL_DRAIN_RATE
	set_hazard_event(0)
	game_running = true
	_generate_demand()
	emit_signal("score_changed",      score)
	emit_signal("durability_changed", durability)
	emit_signal("fuel_changed",       fuel)
	emit_signal("inventory_changed",  inventory)
	emit_signal("level_up",           level)
	emit_signal("combo_changed",      combo)
	# No start-of-game dialogue — the four hazard dialogues (1: Typhoon,
	# 2: Flood, 3: Earthquake, 4: Volcanic) are triggered from hazard_event.gd
	# when the corresponding events first appear.


func end_game(reason: String) -> void:
	game_running = false
	if score > high_score:
		high_score = score
		_save_high_score()
	emit_signal("game_over", reason)


# ---------------------------------------------------------------------------
# Inventory & resources
# ---------------------------------------------------------------------------
func collect_resource(type: String, texture_path: String = "") -> void:
	if inventory.size() >= MAX_INVENTORY:
		return
	inventory.append({
		"type": type,
		"texture_path": texture_path,
	})
	combo += 1
	var points: int = 10 + (min(combo, 5) - 1) * 4   # 10, 14, 18, 22, 26 max
	add_score(points)
	emit_signal("combo_changed", combo)
	emit_signal("inventory_changed", inventory)
	emit_signal("resource_collected", type)
	_check_demand_match()


func dump_cargo() -> void:
	if inventory.is_empty():
		return
	inventory.clear()
	emit_signal("inventory_changed", inventory)


func drop_inventory_item(index: int) -> void:
	if index < 0 or index >= inventory.size():
		return
	inventory.remove_at(index)
	emit_signal("inventory_changed", inventory)
	_check_demand_match()


func set_hazard_event(event: int) -> void:
	current_hazard_event = event
	emit_signal("hazard_event_changed", current_hazard_event)

func pause() -> void:
	get_tree().paused = true
	emit_signal("game_paused")

func resume() -> void:
	get_tree().paused = false
	game_running = true
	emit_signal("game_resumed")
	
# ---------------------------------------------------------------------------
# Hazards & blocks
# ---------------------------------------------------------------------------
func on_hazard_hit() -> void:
	combo = 0
	emit_signal("combo_changed", combo)
	emit_signal("hazard_hit")


func on_block_hit() -> void:
	combo = 0
	emit_signal("combo_changed", combo)
	if has_shield:
		has_shield = false
		return
	durability -= 1
	emit_signal("durability_changed", durability)
	emit_signal("block_hit")
	if durability <= 0:
		end_game("TRUCK_BREAKDOWN")


# ---------------------------------------------------------------------------
# Powerups & fuel
# ---------------------------------------------------------------------------
func collect_powerup(type: String) -> void:
	match type:
		"SHIELD":
			has_shield = true
		"SPEED_BOOST":
			game_speed = min(game_speed + 120.0, MAX_SPEED)
			emit_signal("speed_changed", game_speed)
		"REPAIR_KIT":
			durability = min(durability + 1, MAX_DURABILITY)
			emit_signal("durability_changed", durability)
	add_score(25)
	emit_signal("powerup_collected", type)


func collect_fuel() -> void:
	fuel = min(fuel + FUEL_PICKUP_AMOUNT, 100.0)
	add_score(15)
	emit_signal("fuel_changed", fuel)
	emit_signal("fuel_collected")


# ---------------------------------------------------------------------------
# Scoring & speed
# ---------------------------------------------------------------------------
func add_score(amount: int) -> void:
	score += amount
	emit_signal("score_changed", score)


func increase_speed() -> void:
	game_speed = min(game_speed + SPEED_INCREMENT, MAX_SPEED)
	emit_signal("speed_changed", game_speed)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------
func _drain_fuel(delta: float) -> void:
	fuel = max(fuel - fuel_drain_rate * delta, 0.0)
	emit_signal("fuel_changed", fuel)
	if fuel <= 0.0:
		end_game("OUT_OF_FUEL")


func _generate_demand() -> void:
	current_demand.clear()
	var count: int = randi_range(1, 3)
	for _i in count:
		current_demand.append(RESOURCE_TYPES[randi() % RESOURCE_TYPES.size()])
	emit_signal("demand_updated", current_demand)


func _check_demand_match() -> void:
	if inventory.is_empty() or current_demand.is_empty():
		return
	var remaining: Array = current_demand.duplicate()
	for item in inventory:
		remaining.erase(_get_inventory_item_type(item))
	if remaining.is_empty():
		add_score(100)
		demands_fulfilled_count += 1
		emit_signal("demand_fulfilled", 0)
		inventory.clear()
		emit_signal("inventory_changed", inventory)
		if demands_fulfilled_count % DEMANDS_PER_LEVEL == 0:
			level += 1
			fuel_drain_rate += FUEL_DRAIN_INCREASE
			emit_signal("level_up", level)
		_generate_demand()


func _get_inventory_item_type(item: Variant) -> String:
	if item is Dictionary:
		return item.get("type", "")
	return str(item)


func _load_high_score() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://save.cfg") == OK:
		high_score = cfg.get_value("game", "high_score", 0)
		prologue_seen = cfg.get_value("game", "prologue_seen", false)


func _save_high_score() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "high_score", high_score)
	cfg.set_value("game", "prologue_seen", prologue_seen)
	cfg.save("user://save.cfg")


func mark_prologue_seen() -> void:
	if prologue_seen:
		return
	prologue_seen = true
	_save_high_score()


func play_dialogue(id: int) -> void:
	emit_signal("dialogue_requested", id)
