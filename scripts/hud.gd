## HUD — Group 4: Inventory UI
## Manages all on-screen UI: demand display, score, durability,
## fuel bar, inventory slots, dump-cargo button, start/game-over panels.
extends CanvasLayer

# ── Top HUD ──────────────────────────────────────────────────────────────
@onready var score_label:     Label       = $ScoreBox/ScoreLabel
@onready var level_label:     Label       = $LevelBox/LevelLabel
@onready var combo_label:     Label       = $ComboLabel
@onready var demand_slots: Array[CanvasItem] = [
	$Panel/DemandContainer/Demand1 as CanvasItem,
	$Panel/DemandContainer/Demand2 as CanvasItem,
	$Panel/DemandContainer/Demand3 as CanvasItem,
]
@onready var durability_bar:  TextureProgressBar = $HPBar
@onready var fuel_bar:        TextureProgressBar = $FuelBar

# ── Bottom HUD ───────────────────────────────────────────────────────────
@onready var inv_buttons: Array[BaseButton] = [
	$Panel/InventoryContainer/Item1 as BaseButton,
	$Panel/InventoryContainer/Item2 as BaseButton,
	$Panel/InventoryContainer/Item3 as BaseButton,
]
@onready var inv_slots: Array[CanvasItem] = [
	$Panel/InventoryContainer/Item1/Item1 as CanvasItem,
	$Panel/InventoryContainer/Item2/Item2 as CanvasItem,
	$Panel/InventoryContainer/Item3/Item3 as CanvasItem,
]
@onready var inv_highlights: Array[CanvasItem] = [
	$Panel/InventoryContainer/Item1/Highlight as CanvasItem,
	$Panel/InventoryContainer/Item2/Highlight as CanvasItem,
	$Panel/InventoryContainer/Item3/Highlight as CanvasItem,
]
@onready var dump_button:   Button = $DumpButton
@onready var pause_button:  TextureButton = $PauseButton
@onready var shield_label:  Label  = $ShieldLabel

# ── Overlays ─────────────────────────────────────────────────────────────
@onready var banner_label:  Label     = $BannerLabel
@onready var hit_flash:     ColorRect = $HitFlash

# ── Panels ───────────────────────────────────────────────────────────────
@onready var start_panel:       Control = $StartPanel
@onready var start_button:      Button  = $StartPanel/StartButton
@onready var game_over_panel:   CanvasLayer   = $GameOver
@onready var reason_label:      Label         = $GameOver/TextureRect/GameOverReason
@onready var final_score_label: Label         = $GameOver/TextureRect/ScoreNumber
@onready var high_score_label:  Label         = $"GameOver/TextureRect/Best Score"
@onready var restart_button:    TextureButton = $GameOver/TextureRect/ReplayButton
@onready var menu_button:       TextureButton = $GameOver/TextureRect/MenuButton
@onready var exit_button:       TextureButton = $GameOver/TextureRect/ExitButton

const RESOURCE_COLORS: Dictionary = {
	"RICE":  Color(1.00, 0.88, 0.18),
	"WATER": Color(0.18, 0.55, 1.00),
	"MEDS":  Color(1.00, 0.22, 0.22),
}

const RESOURCE_TEXTURES: Dictionary = {
	"RICE": preload("res://assets/Item Assets/Rice Icon (Detailed) .png"),
	"WATER": preload("res://assets/Item Assets/water bottle icon.png"),
	"MEDS": preload("res://assets/Item Assets/Medicine Icon (Detailed) .png"),
}

const RESOURCE_TEXTURE_VARIANTS: Dictionary = {
	"RICE": [
		preload("res://assets/Item Assets/Rice Icon w logo 1 (Detailed) .png"),
	],
	"WATER": [
		preload("res://assets/Item Assets/water bottle icon.png"),
	],
	"MEDS": [
		preload("res://assets/Item Assets/Medicine Icon (Detailed) .png"),
	],
}

var _fuel_pulse_tween: Tween = null


func _ready() -> void:
	GameManager.score_changed.connect(_on_score_changed)
	GameManager.durability_changed.connect(_on_durability_changed)
	GameManager.fuel_changed.connect(_on_fuel_changed)
	GameManager.inventory_changed.connect(_on_inventory_changed)
	GameManager.game_over.connect(_on_game_over)
	GameManager.powerup_collected.connect(_on_powerup_collected)
	GameManager.demand_updated.connect(_on_demand_updated)
	GameManager.level_up.connect(_on_level_up)
	GameManager.combo_changed.connect(_on_combo_changed)
	GameManager.block_hit.connect(_on_block_hit_flash)
	GameManager.demand_fulfilled.connect(_on_demand_fulfilled)

	start_button.pressed.connect(_on_start_pressed)
	dump_button.pressed.connect(GameManager.dump_cargo)
	pause_button.pressed.connect(GameManager.pause)
	restart_button.pressed.connect(_on_restart_pressed)
	menu_button.pressed.connect(_on_menu_pressed)
	exit_button.pressed.connect(_on_exit_pressed)
	for i in inv_buttons.size():
		inv_buttons[i].pressed.connect(_on_inventory_slot_pressed.bind(i))

	game_over_panel.visible = false
	shield_label.visible    = false
	banner_label.visible    = false
	combo_label.visible     = false
	start_panel.visible     = true
	_refresh_inventory([])
	_on_demand_updated([])


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------
func _on_score_changed(val: int) -> void:
	score_label.text = "Score: %d" % val


func _on_durability_changed(val: int) -> void:
	durability_bar.value = val
	var tw := create_tween()
	tw.tween_property(durability_bar, "modulate", Color(1.8, 0.3, 0.3), 0.07)
	tw.tween_property(durability_bar, "modulate", Color.WHITE, 0.4)


func _on_fuel_changed(val: float) -> void:
	fuel_bar.value = val
	if val < 25.0:
		if _fuel_pulse_tween == null or not _fuel_pulse_tween.is_running():
			_fuel_pulse_tween = create_tween().set_loops()
			_fuel_pulse_tween.tween_property(fuel_bar, "modulate", Color(1.0, 0.1, 0.1), 0.35)
			_fuel_pulse_tween.tween_property(fuel_bar, "modulate", Color(1.0, 0.65, 0.65), 0.35)
	else:
		if _fuel_pulse_tween:
			_fuel_pulse_tween.kill()
			_fuel_pulse_tween = null
		fuel_bar.modulate = Color.WHITE


func _on_inventory_changed(inv: Array) -> void:
	_refresh_inventory(inv)


func _on_demand_updated(demand: Array) -> void:
	for i in demand_slots.size():
		var slot: CanvasItem = demand_slots[i]
		if i < demand.size():
			_set_slot_item(slot, demand[i])
		else:
			_clear_slot_item(slot)
	_refresh_inventory(GameManager.inventory)


func _on_powerup_collected(type: String) -> void:
	match type:
		"SHIELD":
			shield_label.text    = "🛡  SHIELD ACTIVE"
			shield_label.visible = true
		"SPEED_BOOST":
			shield_label.text    = "⚡ SPEED BOOST!"
			shield_label.visible = true
			await get_tree().create_timer(2.0).timeout
			shield_label.visible = false
		"REPAIR_KIT":
			_show_banner("🩵 REPAIRED!", Color(0.10, 0.88, 0.85))


func _on_level_up(lvl: int) -> void:
	level_label.text = "LVL %d" % lvl
	if lvl > 1:
		_show_banner("⬆ LEVEL %d" % lvl, Color(0.6, 1.0, 0.6))


func _on_combo_changed(combo: int) -> void:
	if combo >= 2:
		var heat: float = clampf((combo - 2) / 3.0, 0.0, 1.0)
		combo_label.add_theme_color_override("font_color",
				Color(1.0, 0.85 - heat * 0.5, 0.1))
		combo_label.text    = "x%d COMBO!" % combo
		combo_label.visible = true
	else:
		combo_label.visible = false


func _on_demand_fulfilled(_id: int) -> void:
	_show_banner("✅ DELIVERED! +100", Color(1.0, 0.88, 0.2))


func _on_block_hit_flash() -> void:
	var tw := create_tween()
	tw.tween_property(hit_flash, "color:a", 0.40, 0.06)
	tw.tween_property(hit_flash, "color:a", 0.0,  0.40)


func _on_game_over(reason: String) -> void:
	final_score_label.text = _format_score(GameManager.score)
	high_score_label.text  = "Best: %s" % _format_score(GameManager.high_score)
	match reason:
		"TRUCK_BREAKDOWN":
			reason_label.text = "Truck breakdown..."
		"OUT_OF_FUEL":
			reason_label.text = "Out of fuel..."
		_:
			reason_label.text = "Mission failed..."
	game_over_panel.visible = true


# ---------------------------------------------------------------------------
# Button handlers
# ---------------------------------------------------------------------------
func _on_start_pressed() -> void:
	start_panel.visible = false
	GameManager.start_game()


func _on_restart_pressed() -> void:
	AudioManager.stop_all()
	get_tree().reload_current_scene()


func _on_menu_pressed() -> void:
	AudioManager.stop_all()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_exit_pressed() -> void:
	get_tree().quit()


func _on_inventory_slot_pressed(index: int) -> void:
	GameManager.drop_inventory_item(index)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _refresh_inventory(inv: Array) -> void:
	var extra_slots := _get_extra_inventory_slots(inv, GameManager.current_demand)
	for i in inv_slots.size():
		var slot: CanvasItem = inv_slots[i]
		if i < inv.size():
			_set_slot_item(slot, inv[i])
			inv_highlights[i].visible = extra_slots[i]
			inv_buttons[i].disabled = false
		else:
			_clear_slot_item(slot)
			inv_highlights[i].visible = false
			inv_buttons[i].disabled = true

	shield_label.visible = GameManager.has_shield


func _get_extra_inventory_slots(inv: Array, demand: Array) -> Array[bool]:
	var demand_counts: Dictionary = {}
	for item in demand:
		demand_counts[item] = demand_counts.get(item, 0) + 1

	var extra_slots: Array[bool] = []
	for item in inv:
		var item_type := _get_item_type(item)
		var remaining: int = demand_counts.get(item_type, 0)
		if remaining > 0:
			demand_counts[item_type] = remaining - 1
			extra_slots.append(false)
		else:
			extra_slots.append(true)
	return extra_slots


func _set_slot_item(slot: CanvasItem, item: Variant) -> void:
	var item_type := _get_item_type(item)
	slot.visible = true
	slot.modulate = Color.WHITE
	if slot is TextureRect:
		var texture_path := _get_item_texture_path(item)
		(slot as TextureRect).texture = load(texture_path) if not texture_path.is_empty() else RESOURCE_TEXTURES.get(item_type)
	elif slot is HBoxContainer:
		_set_demand_slot(slot as HBoxContainer, item_type)
	elif slot is Label:
		var label := slot as Label
		label.text = item_type
		label.add_theme_color_override("font_color", RESOURCE_COLORS.get(item_type, Color.WHITE))


func _clear_slot_item(slot: CanvasItem) -> void:
	slot.visible = false
	slot.modulate = Color(0.5, 0.5, 0.5, 1)
	if slot is TextureRect:
		(slot as TextureRect).texture = null
	elif slot is HBoxContainer:
		_clear_demand_slot(slot as HBoxContainer)
	elif slot is Label:
		var label := slot as Label
		label.text = ""
		label.remove_theme_color_override("font_color")


func _set_demand_slot(slot: HBoxContainer, item: String) -> void:
	var label := slot.get_node_or_null("Text") as Label
	if label:
		label.text = item
		label.add_theme_color_override("font_color", RESOURCE_COLORS.get(item, Color.WHITE))

	var variants: Array = RESOURCE_TEXTURE_VARIANTS.get(item, [])
	for i in 2:
		var icon := slot.get_node_or_null("Icon%d" % (i + 1)) as TextureRect
		if icon:
			icon.visible = i < variants.size()
			icon.texture = variants[i] if i < variants.size() else null


func _clear_demand_slot(slot: HBoxContainer) -> void:
	var label := slot.get_node_or_null("Text") as Label
	if label:
		label.text = ""
		label.remove_theme_color_override("font_color")

	for i in 2:
		var icon := slot.get_node_or_null("Icon%d" % (i + 1)) as TextureRect
		if icon:
			icon.visible = false
			icon.texture = null


func _get_item_type(item: Variant) -> String:
	if item is Dictionary:
		return item.get("type", "")
	return str(item)


func _get_item_texture_path(item: Variant) -> String:
	if item is Dictionary:
		return item.get("texture_path", "")
	return ""


func _format_score(value: int) -> String:
	var digits := str(value)
	var result := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = ", " + result
		result = digits.substr(i, 1) + result
		count += 1
	return result


func _show_banner(text: String, color: Color = Color.WHITE) -> void:
	banner_label.text    = text
	banner_label.modulate = Color(color.r, color.g, color.b, 0.0)
	banner_label.visible = true
	var tw := create_tween()
	tw.tween_property(banner_label, "modulate:a", 1.0, 0.25)
	tw.tween_interval(1.4)
	tw.tween_property(banner_label, "modulate:a", 0.0, 0.45)
	tw.tween_callback(func() -> void: banner_label.visible = false)
