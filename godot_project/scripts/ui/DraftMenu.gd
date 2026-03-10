extends CanvasLayer

## DraftMenu — chassis selection screen.
## Replaces GambleScreen for the initial chassis pick.
##
## Scene setup (wire in editor):
##   DraftMenu (CanvasLayer, layer 20)
##   ├── RiveViewer            — load draft_menu.riv here in the Inspector
##   ├── StatsLeft  (Label)    — anchored to lower-left quadrant
##   └── StatsRight (Label)    — anchored to lower-right quadrant
##
## Rive state machine must expose two boolean inputs:
##   "Hover Left"  → true while mouse is on left half
##   "Hover Right" → true while mouse is on right half
##
## RiveViewer is optional: the menu works as a plain click-left/click-right
## selector when the GDExtension is unavailable (e.g. Windows without the DLL).

# ── Chassis ───────────────────────────────────────────────────────────────────
const LEFT_CHASSIS_PATH:  String = "res://resources/parts/chassis_plastic_lid.tres"
const RIGHT_CHASSIS_PATH: String = "res://resources/parts/chassis_rusty_manhole.tres"

# ── Nodes (set names in editor to match these) ────────────────────────────────
# Typed as Node so the script parses even when the RiveViewer GDExtension
# is not loaded (no Windows DLL). All Rive calls are guarded by has_method().
@onready var _rive:        Node  = get_node_or_null("RiveViewer")
@onready var _stats_left:  Label = get_node_or_null("StatsLeft")
@onready var _stats_right: Label = get_node_or_null("StatsRight")

# ── Runtime state ─────────────────────────────────────────────────────────────
var _hover_side:   String = ""     # "left" | "right"
var _confirmed:    bool   = false

# Cached Rive input handles — populated once the viewer scene is ready.
var _input_left:  Object = null
var _input_right: Object = null

# Loaded resources.
var _chassis_left:  ChassisData = null
var _chassis_right: ChassisData = null


# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	# Replaced by DraftingMenu (AnimatedSprite2D-based selector).
	# This node still lives in SewerArena.tscn but must not run.
	queue_free()
	return

	_chassis_left  = load(LEFT_CHASSIS_PATH)  as ChassisData
	_chassis_right = load(RIGHT_CHASSIS_PATH) as ChassisData

	_build_stat_labels()

	# RiveViewer may finish loading on the next frame — defer input caching.
	await get_tree().process_frame
	_cache_inputs()


func _cache_inputs() -> void:
	if not is_instance_valid(_rive):
		return
	# Duck-type: only use Rive API if the GDExtension is loaded and the node
	# exposes get_scene() (RiveViewer from kibble-cabal/godot-rive).
	if not _rive.has_method("get_scene"):
		return
	var scene = _rive.get_scene()
	if scene == null:
		return
	if scene.has_method("find_input"):
		_input_left  = scene.find_input("Hover Left")
		_input_right = scene.find_input("Hover Right")


# ── Per-frame: mouse → Rive ───────────────────────────────────────────────────
func _process(_delta: float) -> void:
	if _confirmed:
		return

	# Retry caching if the viewer wasn't ready on the first frame.
	if _input_left == null or _input_right == null:
		_cache_inputs()

	var mid_x:    float = get_viewport().get_visible_rect().size.x * 0.5
	var mouse_x:  float = get_viewport().get_mouse_position().x
	var new_side: String = "left" if mouse_x < mid_x else "right"

	if new_side == _hover_side:
		return

	_hover_side = new_side
	var on_left: bool = (_hover_side == "left")

	# Drive Rive inputs only when they were successfully cached.
	if _input_left != null and _input_left.has_method("set_value"):
		_input_left.set_value(on_left)
	if _input_right != null and _input_right.has_method("set_value"):
		_input_right.set_value(not on_left)


# ── Click → confirm ───────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if _confirmed or _hover_side == "":
		return
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		_confirm()


func _confirm() -> void:
	_confirmed = true

	var chassis: ChassisData = \
		_chassis_left if _hover_side == "left" else _chassis_right

	# Two random common limbs — Broken Nub is excluded by RunManager.load_all_of_class.
	var all_limbs: Array = RunManager.load_all_of_class("LimbData")
	all_limbs.shuffle()
	var limbs: Array = [all_limbs[0], all_limbs[1]]

	# Enemy assignment.
	var faction_pool := ["fat_rats", "wiggly_worm", "croco_loco"]
	RunManager.vs_enemy_faction_id = faction_pool[randi() % faction_pool.size()]
	RunManager.vs_player_name      = "PLAYER"
	RunManager.vs_enemy_name       = "SEWER GOON"

	RunManager.start_run_with_loadout(chassis, limbs, "red")

	# Fade to black then hand off to VersusScreen.
	var fade := _make_fade_rect()
	var tween := create_tween()
	tween.tween_property(fade, "color:a", 1.0, 0.45).set_ease(Tween.EASE_IN)
	await tween.finished

	var versus        := CanvasLayer.new()
	versus.layer       = 30
	versus.process_mode = Node.PROCESS_MODE_ALWAYS
	versus.set_script(preload("res://scripts/ui/VersusScreen.gd"))
	get_tree().root.add_child(versus)

	fade.get_parent().queue_free()   # removes the temporary fade CanvasLayer
	queue_free()


# ── Stats labels ──────────────────────────────────────────────────────────────
func _build_stat_labels() -> void:
	if is_instance_valid(_stats_left) and _chassis_left:
		_stats_left.text = _format_stats(
			"SPEEDSTER",
			_chassis_left,
			"No RPM penalty\nHigh damp"
		)
	if is_instance_valid(_stats_right) and _chassis_right:
		_stats_right.text = _format_stats(
			"TANK",
			_chassis_right,
			"Heavy resistance\nUltra stable"
		)


func _format_stats(title: String, c: ChassisData, flavour: String) -> String:
	return "%s\n\nTorque  %d\nMass    %.1f kg\n%s" % [
		title,
		int(c.base_torque),
		c.mass,
		flavour,
	]


# ── Helpers ───────────────────────────────────────────────────────────────────
func _make_fade_rect() -> ColorRect:
	var cl  := CanvasLayer.new()
	cl.layer = 99
	get_tree().root.add_child(cl)
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.color         = Color(0.0, 0.0, 0.0, 0.0)
	rect.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	cl.add_child(rect)
	return rect
