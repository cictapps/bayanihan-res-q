## ItemBase - base class for every road item.
class_name ItemBase
extends Area2D

enum ItemType {
	RESOURCE_RICE,
	RESOURCE_WATER,
	RESOURCE_MEDS,
	HAZARD,
	BLOCK,
	POWERUP_SHIELD,
	POWERUP_SPEED,
	FUEL,
	POWERUP_REPAIR,
}

@export var item_type: ItemType = ItemType.RESOURCE_RICE
@export var lane_index: int = 1
## When non-empty ("L" or "R"), this item.tscn instance is a pure visual
## companion: collision is disabled, the main item / block visuals stay
## hidden, and only the matching GrassItems node for that side is shown.
@export var display_side: String = ""

const EVENT_CALM: int = 0
const EVENT_TYPHOON: int = 1
const EVENT_FLOODING: int = 2
const EVENT_EARTHQUAKE: int = 3
const EVENT_VOLCANIC: int = 4

const TEXTURE_PATHS: Dictionary = {
	ItemType.RESOURCE_RICE: ["res://assets/Item Assets/Rice Icon w logo 1 (Detailed) .png",],
	ItemType.RESOURCE_WATER: ["res://assets/Item Assets/water bottle icon.png",],
	ItemType.RESOURCE_MEDS: ["res://assets/Item Assets/Medicine Icon (Detailed) .png"],
	ItemType.POWERUP_SHIELD: ["res://assets/Item Assets/shield-icon.png"],
	ItemType.POWERUP_SPEED: ["res://assets/Item Assets/speedboost-icon.png"],
	ItemType.FUEL: ["res://assets/Item Assets/FuelBar2.png"],
	ItemType.POWERUP_REPAIR: ["res://assets/Item Assets/Repair Icon.png"],
}

const HAZARD_TEXTURE_PATHS: Array[String] = [
	"res://assets/Flood & Typhoon Assets/Environment/Ground/Puddle variations/Puddles Assets1.png",
	"res://assets/Flood & Typhoon Assets/Environment/Ground/Puddle variations/Puddles Assets2.png",
	"res://assets/Flood & Typhoon Assets/Environment/Ground/Puddle variations/Puddles Assets3.png",
	"res://assets/Flood & Typhoon Assets/Environment/Ground/Puddle variations/Puddles Assets4.png",
]

const VEHICLE_ANIMATIONS: Array[StringName] = [&"Car1", &"Car2", &"Car3", &"Tricycle1", &"Tricycle2", &"Tricycle3"]

@onready var item_texture: TextureRect = $Item
@onready var default_collision: CollisionShape2D = $CollisionShape2D
@onready var mr_lane_collision: CollisionShape2D = $"MR-2LaneCollisionShape2D"
@onready var ml_lane_collision: CollisionShape2D = $"ML-2LaneCollisionShape2D"

var collected: bool = false
var _selected_texture_path: String = ""

# Set by _compute_lane_occupancy() once visuals/collisions are picked.
# Read by Spawner to skip grass companions on lanes this item already covers.
var occupies_left:  bool = false
var occupies_right: bool = false

# True if this grass-display item is currently registered with the
# AudioManager spark ambient (electrical post visible during quake/volcanic).
# Used so _exit_tree can release the refcount even if the item is freed early.
var _spark_registered: bool = false


func _ready() -> void:
	if display_side != "":
		_init_as_grass_display()
		return
	collision_layer = 2
	collision_mask = 0
	monitorable = true
	monitoring = false
	_refresh_texture()
	_compute_lane_occupancy()


# Grass-only companion: no collision, no main visuals, just one side prop.
func _init_as_grass_display() -> void:
	monitorable = false
	monitoring = false
	if default_collision != null:
		default_collision.disabled = true
	if mr_lane_collision != null:
		mr_lane_collision.disabled = true
	if ml_lane_collision != null:
		ml_lane_collision.disabled = true
	_hide_visuals()
	_pick_and_show_grass(display_side)


func _process(delta: float) -> void:
	if not GameManager.game_running:
		return
	position.y += GameManager.game_speed * delta
	if position.y > 2050.0:
		queue_free()


func on_collected(player: Node) -> void:
	if collected:
		return
	collected = true

	match item_type:
		ItemType.RESOURCE_RICE:
			GameManager.collect_resource("RICE", _selected_texture_path)
		ItemType.RESOURCE_WATER:
			GameManager.collect_resource("WATER", _selected_texture_path)
		ItemType.RESOURCE_MEDS:
			GameManager.collect_resource("MEDS", _selected_texture_path)
		ItemType.HAZARD:
			GameManager.on_hazard_hit()
		ItemType.BLOCK:
			# Play the impact SFX BEFORE on_block_hit so shield-saves still sound.
			AudioManager.play_sfx_random([
				"res://Sound Files/HitDebris1.MP3",
				"res://Sound Files/HitDebris2.MP3",
				"res://Sound Files/HitDebris3.MP3",
			])
			GameManager.on_block_hit()
		ItemType.POWERUP_SHIELD:
			GameManager.collect_powerup("SHIELD")
			if player.has_method("queue_redraw"):
				player.queue_redraw()
		ItemType.POWERUP_SPEED:
			GameManager.collect_powerup("SPEED_BOOST")
		ItemType.FUEL:
			GameManager.collect_fuel()
		ItemType.POWERUP_REPAIR:
			GameManager.collect_powerup("REPAIR_KIT")
			if player.has_method("queue_redraw"):
				player.queue_redraw()

	queue_free()


func _refresh_texture() -> void:
	_hide_visuals()
	_reset_collision_shapes()
	if item_type == ItemType.BLOCK:
		_show_block_variant()
	else:
		_selected_texture_path = _get_texture_path()
		item_texture.texture = load(_selected_texture_path)
		item_texture.visible = true


func _get_texture_path() -> String:
	match item_type:
		ItemType.HAZARD:
			return _pick(HAZARD_TEXTURE_PATHS)
		ItemType.BLOCK:
			return ""
		_:
			return _pick(TEXTURE_PATHS.get(item_type, TEXTURE_PATHS[ItemType.RESOURCE_RICE]))


func _show_block_variant() -> void:
	var options := _get_block_options()
	if options.is_empty():
		_show_canvas_variant($"Tree branches")
		return

	var option: Dictionary = options.pick_random()
	var node := get_node_or_null(option.get("node", ""))
	if node == null:
		return

	var collision_name: String = option.get("collision", "")
	if collision_name == "MR":
		default_collision.disabled = true
		mr_lane_collision.disabled = false
	elif collision_name == "ML":
		default_collision.disabled = true
		ml_lane_collision.disabled = false

	if node is AnimatedSprite2D:
		_show_animated_variant(node as AnimatedSprite2D, option.get("animation", &""))
	elif node is CanvasItem:
		_show_canvas_variant(node as CanvasItem)


func _get_block_options() -> Array[Dictionary]:
	var event := GameManager.current_hazard_event
	var options: Array[Dictionary] = []

	# ── Normal spawn (all lanes) ──────────────────────────────────────────
	match event:
		EVENT_CALM:
			options.append({"node": "Branches1"})
			options.append({"node": "Branches2"})
			options.append({"node": "DebrisAnim", "animation": &"Debris1"})
			options.append({"node": "DebrisAnim", "animation": &"Debris2"})
		EVENT_TYPHOON:
			options.append({"node": "Branches1"})
			options.append({"node": "Branches2"})
			options.append({"node": "FloodBlockage1"})
			options.append({"node": "FloodBlockage2"})
			options.append({"node": "FloodBlockage3"})
			options.append({"node": "FloodBlockage4"})
		EVENT_FLOODING:
			options.append({"node": "FloodBlockage1"})
			options.append({"node": "FloodBlockage2"})
			options.append({"node": "FloodBlockage3"})
			options.append({"node": "FloodBlockage4"})
		EVENT_EARTHQUAKE:
			options.append_array(_get_shared_vehicle_options())
			options.append({"node": "Crack1"})
			options.append({"node": "Crack2"})
			options.append({"node": "CrackAnim", "animation": &"Crack"})
			options.append({"node": "DebrisAnim", "animation": &"Debris1"})
			options.append({"node": "DebrisAnim", "animation": &"Debris2"})
		EVENT_VOLCANIC:
			options.append_array(_get_shared_vehicle_options())
			options.append({"node": "Crack1"})
			options.append({"node": "Crack2"})
			options.append({"node": "CrackAnim", "animation": &"Crack"})
			options.append({"node": "DebrisAnim", "animation": &"Debris1"})
			options.append({"node": "DebrisAnim", "animation": &"Debris2"})
			options.append({"node": "MagmaBlockage1"})
			options.append({"node": "MagmaBlockage2"})
			options.append({"node": "MagmaBlockage3"})
			options.append({"node": "MagmaBlockage4"})

	# ── Left lane (lane_index == 0) ───────────────────────────────────────
	if lane_index == 0:
		match event:
			EVENT_TYPHOON:
				options.append({"node": "L-LaneTreeAnim", "animation": &"Tree1"})
				options.append({"node": "L-LaneTreeAnim", "animation": &"Tree2"})
				options.append({"node": "L-LaneDebrisAnim", "animation": &"Debris3"})
				options.append({"node": "L-LaneDebrisAnim", "animation": &"Debris4"})
			EVENT_FLOODING:
				options.append({"node": "L-LaneDebrisAnim", "animation": &"Debris3"})
			EVENT_EARTHQUAKE:
				options.append({"node": "L-LaneTreeAnim", "animation": &"Tree1"})
				options.append({"node": "L-LaneTreeAnim", "animation": &"Tree2"})
				options.append({"node": "L-LaneDebrisAnim", "animation": &"Debris3"})
				options.append({"node": "L-LaneDebrisAnim", "animation": &"Debris4"})
			EVENT_VOLCANIC:
				options.append({"node": "L-LaneDebrisAnim", "animation": &"Debris3"})
				options.append({"node": "L-LaneDebrisAnim", "animation": &"Debris4"})
				options.append({"node": "L-LaneLavaAnim", "animation": &"default"})

	# ── Right lane (lane_index == 2) ──────────────────────────────────────
	if lane_index == 2:
		match event:
			EVENT_TYPHOON:
				options.append({"node": "R-LaneTreeAnim", "animation": &"Tree1"})
				options.append({"node": "R-LaneTreeAnim", "animation": &"Tree2"})
				options.append({"node": "R-LaneDebrisAnim", "animation": &"Debris3"})
				options.append({"node": "R-LaneDebrisAnim", "animation": &"Debris4"})
			EVENT_FLOODING:
				options.append({"node": "R-LaneDebrisAnim", "animation": &"Debris3"})
			EVENT_EARTHQUAKE:
				options.append({"node": "R-LaneTreeAnim", "animation": &"Tree1"})
				options.append({"node": "R-LaneTreeAnim", "animation": &"Tree2"})
				options.append({"node": "R-LaneDebrisAnim", "animation": &"Debris3"})
				options.append({"node": "R-LaneDebrisAnim", "animation": &"Debris4"})
			EVENT_VOLCANIC:
				options.append({"node": "R-LaneDebrisAnim", "animation": &"Debris3"})
				options.append({"node": "R-LaneDebrisAnim", "animation": &"Debris4"})
				options.append({"node": "R-LaneLavaAnim", "animation": &"default"})

	# ── Middle lane / two-lane (lane_index == 1) ──────────────────────────
	if lane_index == 1:
		match event:
			EVENT_TYPHOON:
				options.append({"node": "MR-2LaneDebrisAnim", "animation": &"Debris5", "collision": "MR"})
				options.append({"node": "ML-2LaneDebrisAnim", "animation": &"Debris5", "collision": "ML"})
				options.append({"node": "MR-2LaneDebrisAnim", "animation": &"Debris6", "collision": "MR"})
				options.append({"node": "ML-2LaneDebrisAnim", "animation": &"Debris6", "collision": "ML"})
			EVENT_FLOODING:
				options.append({"node": "MR-2LaneDebrisAnim", "animation": &"Debris5", "collision": "MR"})
				options.append({"node": "ML-2LaneDebrisAnim", "animation": &"Debris5", "collision": "ML"})
				options.append({"node": "MR-2LaneDebrisAnim", "animation": &"Debris6", "collision": "MR"})
				options.append({"node": "ML-2LaneDebrisAnim", "animation": &"Debris6", "collision": "ML"})
			EVENT_EARTHQUAKE:
				options.append({"node": "MR-2LaneDebrisAnim", "animation": &"Debris5", "collision": "MR"})
				options.append({"node": "ML-2LaneDebrisAnim", "animation": &"Debris5", "collision": "ML"})
				options.append({"node": "MR-2LaneDebrisAnim", "animation": &"Debris6", "collision": "MR"})
				options.append({"node": "ML-2LaneDebrisAnim", "animation": &"Debris6", "collision": "ML"})
			EVENT_VOLCANIC:
				options.append({"node": "MR-2LaneDebrisAnim", "animation": &"Debris5", "collision": "MR"})
				options.append({"node": "ML-2LaneDebrisAnim", "animation": &"Debris5", "collision": "ML"})
				options.append({"node": "MR-2LaneDebrisAnim", "animation": &"Debris6", "collision": "MR"})
				options.append({"node": "ML-2LaneDebrisAnim", "animation": &"Debris6", "collision": "ML"})

	return options


func _get_shared_vehicle_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for animation in VEHICLE_ANIMATIONS:
		options.append({"node": "CrackAnim", "animation": animation})
	return options


func _show_canvas_variant(node: CanvasItem) -> void:
	node.visible = true


func _show_animated_variant(node: AnimatedSprite2D, animation: StringName) -> void:
	node.visible = true
	if not animation.is_empty():
		node.animation = animation
	node.frame = 0
	node.play()


func _hide_visuals() -> void:
	for node_name in [
		"Item",
		"Crack1",
		"Crack2",
		"CrackAnim",
		"DebrisAnim",
		"R-LaneDebrisAnim",
		"L-LaneDebrisAnim",
		"MR-2LaneDebrisAnim",
		"ML-2LaneDebrisAnim",
		"R-LaneTreeAnim",
		"L-LaneTreeAnim",
		"R-LaneLavaAnim",
		"L-LaneLavaAnim",
		"Branches1",
		"Branches2",
		"FloodBlockage1",
		"FloodBlockage2",
		"FloodBlockage3",
		"FloodBlockage4",
		"LavaBlockage",
		"MagmaBlockage1",
		"MagmaBlockage2",
		"MagmaBlockage3",
		"MagmaBlockage4",
	]:
		var node := get_node_or_null(node_name)
		if node is CanvasItem:
			(node as CanvasItem).visible = false
	_hide_grass()


func _hide_grass() -> void:
	var grass := get_node_or_null("GrassItems")
	if grass == null:
		return
	for child in grass.get_children():
		if child is CanvasItem:
			(child as CanvasItem).visible = false


func _reset_collision_shapes() -> void:
	default_collision.disabled = false
	mr_lane_collision.disabled = true
	ml_lane_collision.disabled = true


func _compute_lane_occupancy() -> void:
	occupies_left  = (lane_index == 0)
	occupies_right = (lane_index == 2)
	# A middle-lane BLOCK can extend into the left (ML) or right (MR) lane.
	if lane_index == 1 and item_type == ItemType.BLOCK:
		if not ml_lane_collision.disabled:
			occupies_left = true
		if not mr_lane_collision.disabled:
			occupies_right = true


# ---------------------------------------------------------------------------
# Side grass — picks one GrassItems child for the given side ("L" / "R").
# Called either from grass-display init (this item.tscn is itself the
# decoration) or, in the future, by any other caller that needs a side prop
# shown on an item.
# ---------------------------------------------------------------------------
func _pick_and_show_grass(side: String) -> void:
	var options := _get_grass_options(side)
	if options.is_empty():
		return
	var grass := get_node_or_null("GrassItems")
	if grass == null:
		return
	var option: Dictionary = options.pick_random()
	var node_name: String = str(option.get("node", ""))
	var node := grass.get_node_or_null(node_name)
	if node == null:
		return
	# GrassItems is authored as visible=false so it doesn't bleed onto normal
	# items. A grass-display companion needs the parent flipped on, otherwise
	# the chosen child stays hidden by the cascading invisibility.
	if grass is CanvasItem:
		(grass as CanvasItem).visible = true
	if node is AnimatedSprite2D:
		_show_animated_variant(node as AnimatedSprite2D, option.get("animation", &""))
	elif node is CanvasItem:
		_show_canvas_variant(node as CanvasItem)

	# Electrical posts spark only during seismic / volcanic events. The
	# sparks ambient is refcounted: it plays as long as at least one live
	# Electrical Post item is on screen and stops as soon as the last one
	# despawns (handled in _exit_tree below).
	if node_name.ends_with("Electrical Post"):
		var event := GameManager.current_hazard_event
		if event == EVENT_EARTHQUAKE or event == EVENT_VOLCANIC:
			AudioManager.register_spark_source(self)
			_spark_registered = true


func _exit_tree() -> void:
	if _spark_registered:
		AudioManager.unregister_spark_source(self)
		_spark_registered = false


# Matches the GrassItems node names in item.tscn. One match block per event,
# same shape as _get_block_options so it's easy to tweak any single event.
func _get_grass_options(side: String) -> Array[Dictionary]:
	var event := GameManager.current_hazard_event
	var tree_node:         String = "%s-Tree" % side
	var post_node:         String = "%s - Electrical Post" % side
	var poster1_node:      String = "%s - Political Poster 1" % side
	var poster2_node:      String = "%s - Political Poster 2" % side
	var poster3_node:      String = "%s - Political Poster 3" % side
	var evac_node:         String = "%s - Evacuation Sign" % side
	var coconut_node:      String = "%s - Coconut Tree" % side
	var burned_coco_node:  String = "%s - Burned Coconut Tree" % side
	var bahay_node:        String = "%s - Bahay Kubo" % side
	var burned_bahay_node: String = "%s - Burned Bahay Kubo" % side
	var options: Array[Dictionary] = []

	match event:
		EVENT_CALM:
			options.append({"node": tree_node, "animation": &"Tree1"})
			options.append({"node": tree_node, "animation": &"Tree2"})
			options.append({"node": post_node})
			options.append({"node": poster1_node})
			options.append({"node": poster2_node})
			options.append({"node": poster3_node})
			options.append({"node": coconut_node})
			options.append({"node": bahay_node})
		EVENT_TYPHOON:
			options.append({"node": tree_node, "animation": &"Tree1"})
			options.append({"node": tree_node, "animation": &"Tree2"})
			options.append({"node": post_node})
			options.append({"node": poster1_node})
			options.append({"node": poster2_node})
			options.append({"node": poster3_node})
			options.append({"node": evac_node})
			options.append({"node": coconut_node})
			options.append({"node": bahay_node})
		EVENT_FLOODING:
			options.append({"node": poster1_node})
			options.append({"node": poster2_node})
			options.append({"node": poster3_node})
			options.append({"node": evac_node})
			options.append({"node": coconut_node})
			options.append({"node": bahay_node})
		EVENT_EARTHQUAKE:
			options.append({"node": tree_node, "animation": &"Tree1"})
			options.append({"node": tree_node, "animation": &"Tree2"})
			options.append({"node": post_node})
			options.append({"node": poster1_node})
			options.append({"node": poster2_node})
			options.append({"node": poster3_node})
			options.append({"node": evac_node})
			options.append({"node": coconut_node})
			options.append({"node": bahay_node})
		EVENT_VOLCANIC:
			options.append({"node": post_node})
			options.append({"node": poster1_node})
			options.append({"node": poster2_node})
			options.append({"node": poster3_node})
			options.append({"node": evac_node})
			options.append({"node": burned_coco_node})
			options.append({"node": burned_bahay_node})

	return options


func _pick(paths: Array) -> String:
	if paths.is_empty():
		return ""
	return paths[randi() % paths.size()]
