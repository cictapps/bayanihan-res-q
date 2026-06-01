## Road Scroll — Group 2: Map & Intel
## Moves two road panels AND the two background panels in tandem
## for infinite downward scrolling.
##
## Wrap logic (panel height = ROAD_H = 2016):
##   When RoadA scrolls off the bottom (y >= ROAD_H) →
##       RoadA jumps to RoadB.y - ROAD_H   (places it above RoadB)
##   When RoadB scrolls off the bottom (y >= ROAD_H) →
##       RoadB jumps to RoadA.y - ROAD_H   (places it above RoadA)
##
## This is equivalent to: "when RoadB reaches 0, send RoadA to -2016,
## then when RoadA reaches 0, send RoadB to -2016."

extends Node2D

const ROAD_H: float = 2016.0

# Road geometry panels (children of this node, defined in main.tscn)
@onready var road_a: Node2D = $RoadA
@onready var road_b: Node2D = $RoadB

# Background panels (children of the Background instance, sibling of this node)
var bg_a: Node2D = null
var bg_b: Node2D = null


func _ready() -> void:
	# Initialise road panels
	road_a.position.y = 0.0
	road_b.position.y = -ROAD_H

	# Grab background panels from the Background scene
	var bg: Node = get_parent().get_node_or_null("Background")
	if bg:
		bg_a = bg.get_node_or_null("RoadA")
		bg_b = bg.get_node_or_null("RoadB")
		_apply_background_variant(bg_a)
		_apply_background_variant(bg_b)
	else:
		push_warning("RoadScroll: could not find Background node in parent.")

	# Mid-game hazard transitions still happen on panel wrap (smooth). But on
	# a fresh start we force both panels back to plain grass so the player
	# doesn't see last run's flood / typhoon road for a few seconds.
	GameManager.level_up.connect(_on_level_up)


func _on_level_up(lvl: int) -> void:
	if lvl == 1:
		_force_hide_hazard_backgrounds(bg_a)
		_force_hide_hazard_backgrounds(bg_b)


func _force_hide_hazard_backgrounds(panel: Node2D) -> void:
	if panel == null:
		return
	var typhoon_tileset := panel.get_node_or_null("Main/TyphoonTileset") as CanvasItem
	var flood_tileset := panel.get_node_or_null("Main/FloodTileset") as CanvasItem
	if typhoon_tileset != null:
		typhoon_tileset.visible = false
	if flood_tileset != null:
		flood_tileset.visible = false


func _process(delta: float) -> void:
	if not GameManager.game_running:
		return

	var spd: float = GameManager.game_speed

	# ── Move both road panels ──────────────────────────────────────────────
	road_a.position.y += spd * delta
	road_b.position.y += spd * delta

	# ── Move both background panels ────────────────────────────────────────
	if bg_a:
		bg_a.position.y += spd * delta
	if bg_b:
		bg_b.position.y += spd * delta

	# ── Wrap road panels ───────────────────────────────────────────────────
	# When RoadA scrolls off the bottom, place it above RoadB
	if road_a.position.y >= ROAD_H:
		road_a.position.y = road_b.position.y - ROAD_H
	# When RoadB scrolls off the bottom, place it above RoadA
	if road_b.position.y >= ROAD_H:
		road_b.position.y = road_a.position.y - ROAD_H

	# ── Wrap background panels (same logic) ────────────────────────────────
	if bg_a and bg_a.position.y >= ROAD_H:
		bg_a.position.y = bg_b.position.y - ROAD_H
		_apply_background_variant(bg_a)
	if bg_b and bg_b.position.y >= ROAD_H:
		bg_b.position.y = bg_a.position.y - ROAD_H
		_apply_background_variant(bg_b)


func _apply_background_variant(panel: Node2D) -> void:
	if panel == null:
		return

	var typhoon_tileset := panel.get_node_or_null("Main/TyphoonTileset") as CanvasItem
	var flood_tileset := panel.get_node_or_null("Main/FloodTileset") as CanvasItem
	if typhoon_tileset == null or flood_tileset == null:
		return

	match GameManager.current_hazard_event:
		1:
			typhoon_tileset.visible = true
			flood_tileset.visible = false
		2:
			typhoon_tileset.visible = false
			flood_tileset.visible = true
		_:
			typhoon_tileset.visible = false
			flood_tileset.visible = false
