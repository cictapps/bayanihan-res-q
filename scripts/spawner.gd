## Spawner — Group 3: Events Team
extends Node2D

const LANE_POSITIONS: Array[float] = [250.0, 540.0, 830.0]
const SPAWN_Y: float = -110.0

const SPAWN_INTERVAL_START: float = 1.20
const SPAWN_INTERVAL_MIN:   float = 0.45
const INTERVAL_DECREASE:    float = 0.04
const DIFFICULTY_TICK:      float = 12.0
const FUEL_TYPE_INDEX: int = 7
const FUEL_CHANCE_INCREASE: int = 4
const MAX_FUEL_CHANCE: int = 100

# [RICE=0, WATER=1, MEDS=2, HAZARD=3, BLOCK=4, SHIELD=5, SPEED=6, FUEL=7, REPAIR=8]
var _spawn_weights: Array[int] = [24, 20, 14, 12, 8, 2, 2, 0, 2]

var _item_scene: PackedScene = preload("res://scenes/items/item.tscn")

var _spawn_timer: float    = 0.0
var _diff_timer: float     = 0.0
var _spawn_interval: float = SPAWN_INTERVAL_START
var _fuel_spawn_chance: int = 0


func _ready() -> void:
	add_to_group("spawner")   # so hazard_event can find this node
	GameManager.level_up.connect(_on_level_up)


func _process(delta: float) -> void:
	if not GameManager.game_running:
		return
	_spawn_timer += delta
	_diff_timer  += delta

	if _spawn_timer >= _spawn_interval:
		_spawn_timer = 0.0
		_spawn_item()

	if _diff_timer >= DIFFICULTY_TICK:
		_diff_timer = 0.0
		GameManager.increase_speed()
		_spawn_interval = max(_spawn_interval - INTERVAL_DECREASE, SPAWN_INTERVAL_MIN)


func _spawn_item() -> void:
	var lane: int      = randi() % 3
	var type_idx: int  = _pick_spawn_type()
	var item: ItemBase = _item_scene.instantiate() as ItemBase
	item.item_type     = type_idx as ItemBase.ItemType
	item.lane_index    = lane
	item.position      = Vector2(LANE_POSITIONS[lane], SPAWN_Y)
	add_child(item)
	# item._ready() has already run by this point, so its occupies_*
	# flags reflect the final visual / collision variant.
	_spawn_grass_companions(item)


# Spawns up to two extra item.tscn instances purely for scenery: one on the
# L lane, one on the R lane. They roll 50% independently. Each side is
# skipped when the main item already occupies that lane (L / ML disables
# left, R / MR disables right).
func _spawn_grass_companions(main_item: ItemBase) -> void:
	if not main_item.occupies_left and randi() % 2 == 0:
		_spawn_grass_at("L", LANE_POSITIONS[0])
	if not main_item.occupies_right and randi() % 2 == 0:
		_spawn_grass_at("R", LANE_POSITIONS[2])


func _spawn_grass_at(side: String, x: float) -> void:
	var g: ItemBase = _item_scene.instantiate() as ItemBase
	g.display_side = side
	g.position     = Vector2(x, SPAWN_Y)
	add_child(g)


func _pick_spawn_type() -> int:
	if randi_range(1, 100) <= _fuel_spawn_chance:
		_fuel_spawn_chance = 0
		return FUEL_TYPE_INDEX

	_fuel_spawn_chance = min(_fuel_spawn_chance + FUEL_CHANCE_INCREASE, MAX_FUEL_CHANCE)
	return _weighted_random()


func _weighted_random() -> int:
	var total: int = 0
	for i in _spawn_weights.size():
		if i == FUEL_TYPE_INDEX:
			continue
		total += _spawn_weights[i]
	var roll: int = randi() % total
	var cumulative: int = 0
	for i in _spawn_weights.size():
		if i == FUEL_TYPE_INDEX:
			continue
		cumulative += _spawn_weights[i]
		if roll < cumulative:
			return i
	return 0


func _on_level_up(lvl: int) -> void:
	if lvl <= 1:
		return
	_spawn_weights[3] = min(_spawn_weights[3] + 2, 26)  # HAZARD
	_spawn_weights[4] = min(_spawn_weights[4] + 1, 14)  # BLOCK
	_spawn_weights[0] = max(_spawn_weights[0] - 2, 10)  # RICE
	_spawn_weights[1] = max(_spawn_weights[1] - 1, 10)  # WATER
