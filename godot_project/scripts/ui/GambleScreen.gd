extends CanvasLayer

# ── Asset paths ───────────────────────────────────────────────────────────────
const BG_IMAGE_PATH:  String = "res://assets/menus/betting_menu.png"
const NAMES_PATH:     String = "res://assets/brainrot_names.txt"
const FONT_PATH:      String = "res://assets/fonts/InkPen.otf"
const SHADER_PATH:    String = "res://assets/shaders/label_jitter.gdshader"

# ── Paper regions (native image pixels, 960 × 540) ────────────────────────────
const IMG_W:       float = 960.0
const IMG_H:       float = 540.0
const LEFT_PAPER:  Rect2 = Rect2( 60, 155, 280, 220)   # RED corner
const RIGHT_PAPER: Rect2 = Rect2(610, 150, 290, 220)   # BLUE corner

# ── Sewer field observations — one is picked per bey each round ───────────────
const SEWER_OBSERVATIONS: Array[String] = [
	"Smells like ozone.",
	"Leaking black bile.",
	"Vibrates aggressively.",
	"Pupils are dilated.",
	"Teeth are too many.",
	"Whispers to itself.",
	"Leaves no shadow.",
	"Sweating mineral oil.",
	"Eyes keep moving.",
	"Smells like burning hair.",
	"Covered in bite marks.",
	"Fingers won't stop twitching.",
	"Neck makes clicking sounds.",
	"Not blinking. Ever.",
	"Licking the arena walls.",
	"Communicates via frequency.",
	"Gills. Possibly.",
	"Distinctly wrong posture.",
	"Radiates mild heat.",
	"Tastes of copper.",
	"Keeps counting to seven.",
	"Shedding, but slowly.",
	"Refuses to face south.",
	"It smiled first.",
]

# ── State ─────────────────────────────────────────────────────────────────────
var _brainrot_names:  Array[String]  = []
var _inkpen_font:     Font           = null
var _jitter_mat:      ShaderMaterial = null

var _scrap_label:      Label     = null   # node name: Scrap_Total
var _trophy_label:     Label     = null   # node name: Trophy_Count
var _float_root:       Control   = null
var _left_paper_root:  Control   = null
var _right_paper_root: Control   = null
var _left_btn:         Button    = null
var _right_btn:        Button    = null
var _left_name_lbl:    Label     = null
var _right_name_lbl:   Label     = null
var _left_stats_lbl:   Label     = null
var _right_stats_lbl:  Label     = null
var _flash_overlay:    ColorRect = null
var _fade_overlay:     ColorRect = null

# Faction reputation display — node names kept plain for Rive swap later.
var _rep_label_rats:  Label = null
var _rep_label_worms: Label = null
var _rep_label_croco: Label = null

# Generated loadouts — set in _generate_scouting_reports, read in _on_draft.
var _left_loadout:  Dictionary = {}   # {chassis: ChassisData, limbs: [LimbData, LimbData]}
var _right_loadout: Dictionary = {}


# ── Entry point ───────────────────────────────────────────────────────────────
func _ready() -> void:
	# A run is already in progress (returning from post-match) — skip the draft.
	if RunManager.run_active:
		queue_free()
		return

	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_brainrot_names = _load_brainrot_names()
	if ResourceLoader.exists(FONT_PATH):
		_inkpen_font = load(FONT_PATH)
	_jitter_mat     = _make_jitter_material()
	_build_ui()
	Events.scrap_changed.connect(_on_scrap_changed)
	Events.reputation_changed.connect(func(_id: String, _rep: int) -> void: _refresh_rep_labels())
	await get_tree().process_frame
	await get_tree().process_frame
	_generate_scouting_reports()
	get_tree().paused = true


# ── Asset loaders ─────────────────────────────────────────────────────────────
func _load_brainrot_names() -> Array[String]:
	var names: Array[String] = []
	var file := FileAccess.open(NAMES_PATH, FileAccess.READ)
	if not file:
		return ["UNKNOWN", "CREATURE"]
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.length() > 0:
			names.append(line)
	return names

# Loads the jitter shader and wraps it in a ShaderMaterial.
func _make_jitter_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	if ResourceLoader.exists(SHADER_PATH):
		mat.shader = load(SHADER_PATH)
	return mat


# ── UI construction ───────────────────────────────────────────────────────────
func _build_ui() -> void:
	var vp: Vector2 = get_tree().root.get_visible_rect().size

	# Root control — Full Rect so all children anchor to the viewport.
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Background: Expand + Keep Aspect Covered.
	var bg := TextureRect.new()
	if ResourceLoader.exists(BG_IMAGE_PATH):
		bg.texture = load(BG_IMAGE_PATH)
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bg.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	# Left-side meta panel: Scrap_Total + Trophy_Count with sewer_rat font + jitter.
	_build_left_meta_panel(root)

	# Float root — labels + buttons bob together here.
	_float_root = Control.new()
	_float_root.position     = Vector2.ZERO
	_float_root.size         = vp
	_float_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_float_root)

	var lp := _scale_rect(LEFT_PAPER,  vp)
	var rp := _scale_rect(RIGHT_PAPER, vp)

	_left_paper_root  = _make_paper_panel(lp, "START RUN", Color(0.85, 0.18, 0.18, 1.0), _inkpen_font)
	_right_paper_root = _make_paper_panel(rp, "START RUN", Color(0.18, 0.48, 0.92, 1.0), _inkpen_font)
	_float_root.add_child(_left_paper_root)
	_float_root.add_child(_right_paper_root)

	_left_btn       = _left_paper_root.get_node("StartRun_Button")   as Button
	_left_name_lbl  = _left_paper_root.get_node("Name")  as Label
	_left_stats_lbl = _left_paper_root.get_node("Stats") as Label

	_right_btn       = _right_paper_root.get_node("StartRun_Button")   as Button
	_right_name_lbl  = _right_paper_root.get_node("Name")  as Label
	_right_stats_lbl = _right_paper_root.get_node("Stats") as Label

	_left_btn.pressed.connect(_on_draft.bind("left",  _left_paper_root))
	_right_btn.pressed.connect(_on_draft.bind("right", _right_paper_root))

	# Lock out drafting if the player is broke.
	if Global.total_scrap < RunManager.RUN_ENTRY_COST:
		_left_btn.disabled  = true
		_right_btn.disabled = true

	_left_paper_root.pivot_offset  = _left_paper_root.size  / 2.0
	_right_paper_root.pivot_offset = _right_paper_root.size / 2.0
	_left_paper_root.rotation_degrees  = -3.5
	_right_paper_root.rotation_degrees =  3.5

	# Overlays.
	_flash_overlay = ColorRect.new()
	_flash_overlay.color = Color(1.0, 1.0, 1.0, 0.0)
	_flash_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_flash_overlay)

	_fade_overlay = ColorRect.new()
	_fade_overlay.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade_overlay)

	_build_rep_hud(root)
	_build_reset_button(root)
	_start_float_tween()


# ── Paper panel factory ───────────────────────────────────────────────────────
func _make_paper_panel(rect: Rect2, btn_text: String, btn_color: Color,
					   font: Font = null) -> Control:
	var panel := Control.new()
	panel.position = rect.position
	panel.size     = rect.size

	# Transparent full-paper button.
	var btn := Button.new()
	btn.name     = "StartRun_Button"
	btn.position = Vector2.ZERO
	btn.size     = rect.size
	btn.text     = btn_text
	btn.add_theme_font_size_override("font_size", 27)
	btn.add_theme_color_override("font_color", btn_color)
	var s_empty := StyleBoxFlat.new()
	s_empty.bg_color = Color(0, 0, 0, 0)
	var s_hover := StyleBoxFlat.new()
	s_hover.bg_color                   = Color(1, 1, 1, 0.18)
	s_hover.corner_radius_top_left     = 10
	s_hover.corner_radius_top_right    = 10
	s_hover.corner_radius_bottom_left  = 10
	s_hover.corner_radius_bottom_right = 10
	btn.add_theme_stylebox_override("normal",  s_empty)
	btn.add_theme_stylebox_override("focus",   s_empty)
	btn.add_theme_stylebox_override("hover",   s_hover)
	btn.add_theme_stylebox_override("pressed", s_hover)
	panel.add_child(btn)

	# Name label — large font, dark ink, jitter shader, ink-bleed shadow.
	var name_lbl := Label.new()
	name_lbl.name         = "Name"
	name_lbl.z_index      = 10
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.position     = Vector2(20, 20)
	name_lbl.size         = Vector2(rect.size.x - 36, 36)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_lbl.label_settings = _make_label_settings(31, Color(0.059, 0.102, 0.102, 0.9), font)
	name_lbl.material       = _jitter_mat
	name_lbl.modulate.a     = 0.85
	name_lbl.pivot_offset   = name_lbl.size / 2.0
	name_lbl.rotation_degrees = randf_range(-1.0, 1.0)
	name_lbl.text = "???"
	panel.add_child(name_lbl)

	# Stats label — slightly lighter alpha (ink soaking into damp paper).
	var stats_lbl := Label.new()
	stats_lbl.name         = "Stats"
	stats_lbl.z_index      = 10
	stats_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_lbl.position     = Vector2(20, 60)
	stats_lbl.size         = Vector2(rect.size.x - 36, rect.size.y - 90)
	stats_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	stats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	stats_lbl.label_settings = _make_label_settings(21, Color(0.059, 0.102, 0.102, 0.8), font)
	stats_lbl.material       = _jitter_mat
	stats_lbl.modulate.a     = 0.85
	stats_lbl.pivot_offset   = stats_lbl.size / 2.0
	stats_lbl.rotation_degrees = randf_range(-1.0, 1.0)
	stats_lbl.text = "Loading..."
	panel.add_child(stats_lbl)

	return panel

# Builds a LabelSettings with ink-bleed shadow and optional custom font.
func _make_label_settings(font_size: int, color: Color, font: Font = null) -> LabelSettings:
	var s := LabelSettings.new()
	s.font_size  = font_size
	s.font_color = color
	if font:
		s.font = font
	# Ink-bleed: dark-purple shadow, slight spread and offset to fake dampness.
	s.shadow_color  = Color(0.04, 0.02, 0.06, 0.30)
	s.shadow_size   = 2
	s.shadow_offset = Vector2(1.0, 1.5)
	return s


# ── Helpers ───────────────────────────────────────────────────────────────────
func _scale_rect(r: Rect2, vp: Vector2) -> Rect2:
	return Rect2(
		r.position.x / IMG_W * vp.x,
		r.position.y / IMG_H * vp.y,
		r.size.x     / IMG_W * vp.x,
		r.size.y     / IMG_H * vp.y
	)

# ── Left-side meta stats ──────────────────────────────────────────────────────
# Scrap_Total and Trophy_Count — plain Labels; Rive will handle styling later.
func _build_left_meta_panel(root: Control) -> void:
	_scrap_label              = Label.new()
	_scrap_label.name         = "Scrap_Total"
	_scrap_label.text         = "SCRAP:  %d" % Global.total_scrap
	_scrap_label.position     = Vector2(12.0, 12.0)
	_scrap_label.size         = Vector2(230.0, 42.0)
	_scrap_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrap_label.add_theme_font_size_override("font_size", 31)
	_scrap_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.2, 1.0))
	root.add_child(_scrap_label)

	_trophy_label              = Label.new()
	_trophy_label.name         = "Trophy_Count"
	_trophy_label.text         = "TROPHIES:  %d" % SaveManager.trophies.size()
	_trophy_label.position     = Vector2(12.0, 58.0)
	_trophy_label.size         = Vector2(230.0, 32.0)
	_trophy_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trophy_label.add_theme_font_size_override("font_size", 22)
	_trophy_label.add_theme_color_override("font_color", Color(0.22, 0.82, 0.42, 0.90))
	root.add_child(_trophy_label)


# ── Faction Reputation HUD ────────────────────────────────────────────────────
# Plain Labels with clear node names — swap for Rive listeners when ready.
func _build_rep_hud(root: Control) -> void:
	var vp: Vector2 = get_tree().root.get_visible_rect().size

	var FactionRepHUD := Control.new()
	FactionRepHUD.name         = "FactionRepHUD"
	FactionRepHUD.position     = Vector2(vp.x - 190.0, 10.0)
	FactionRepHUD.size         = Vector2(180.0, 90.0)
	FactionRepHUD.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(FactionRepHUD)

	_rep_label_rats  = _make_rep_label("RepLabel_Rats",  Vector2(0.0,  0.0))
	_rep_label_worms = _make_rep_label("RepLabel_Worms", Vector2(0.0, 28.0))
	_rep_label_croco = _make_rep_label("RepLabel_Croco", Vector2(0.0, 56.0))
	FactionRepHUD.add_child(_rep_label_rats)
	FactionRepHUD.add_child(_rep_label_worms)
	FactionRepHUD.add_child(_rep_label_croco)

	_refresh_rep_labels()


func _make_rep_label(label_name: String, pos: Vector2) -> Label:
	var lbl := Label.new()
	lbl.name          = label_name
	lbl.position      = pos
	lbl.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(0.059, 0.102, 0.102, 0.78))
	return lbl


# ── Reset Progress button ─────────────────────────────────────────────────────
# Named "ResetProgress_Button" so it can be wired to a Rive confirmation later.
func _build_reset_button(root: Control) -> void:
	var vp: Vector2 = get_tree().root.get_visible_rect().size

	var ResetProgress_Button := Button.new()
	ResetProgress_Button.name     = "ResetProgress_Button"
	ResetProgress_Button.text     = "RESET PROGRESS"
	ResetProgress_Button.position = Vector2(vp.x * 0.5 - 80.0, vp.y - 36.0)
	ResetProgress_Button.size     = Vector2(160.0, 28.0)
	ResetProgress_Button.add_theme_font_size_override("font_size", 17)
	ResetProgress_Button.add_theme_color_override("font_color", Color(0.72, 0.22, 0.18, 0.90))
	ResetProgress_Button.pressed.connect(_on_reset_pressed)
	root.add_child(ResetProgress_Button)


func _on_reset_pressed() -> void:
	SaveManager.reset_and_save()
	get_tree().paused = false
	get_tree().reload_current_scene()


func _refresh_rep_labels() -> void:
	var entries: Array = [
		["fat_rats",    "RATS",  _rep_label_rats],
		["wiggly_worm", "WORMS", _rep_label_worms],
		["croco_loco",  "CROCO", _rep_label_croco],
	]
	for entry in entries:
		var lbl := entry[2] as Label
		if not is_instance_valid(lbl):
			continue
		var faction_id: String   = entry[0]
		var short_name: String   = entry[1]
		var rep: int             = FactionManager.get_reputation(faction_id)
		var faction: FactionData = FactionManager.get_faction(faction_id)
		var threshold: int       = faction.boss_unlock_threshold if faction else 50
		var star: String         = " *" if rep >= threshold else ""
		lbl.text = "%s  %d / %d%s" % [short_name, rep, threshold, star]


func _start_float_tween() -> void:
	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(_float_root, "position:y",  8.0, 1.6) \
		 .set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_float_root, "position:y", -8.0, 1.6) \
		 .set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


# Shrinks font_size so the name fits within the label's width.
# Steps down from 31 → 25 → 20 for progressively longer names.
func _fit_name_font(lbl: Label) -> void:
	var text_len := lbl.text.length()
	var size: int = 31
	if text_len > 16:
		size = 20
	elif text_len > 10:
		size = 25
	lbl.label_settings.font_size = size


# ── Scouting reports (loadout draft) ─────────────────────────────────────────
func _generate_scouting_reports() -> void:
	var all_chassis := RunManager.load_all_of_class("ChassisData")
	var all_limbs   := RunManager.load_all_of_class("LimbData")

	if all_chassis.is_empty() or all_limbs.size() < 2:
		_left_stats_lbl.text  = "PARTS MISSING"
		_right_stats_lbl.text = "PARTS MISSING"
		return

	all_chassis.shuffle()
	all_limbs.shuffle()

	# Build loadouts — allow index wrap so we cope with small pools gracefully.
	var n_c := all_chassis.size()
	var n_l := all_limbs.size()
	_left_loadout  = {
		chassis = all_chassis[0 % n_c],
		limbs   = [all_limbs[0 % n_l], all_limbs[1 % n_l]],
	}
	_right_loadout = {
		chassis = all_chassis[1 % n_c],
		limbs   = [all_limbs[2 % n_l], all_limbs[3 % n_l]],
	}

	var left_name:  String = _brainrot_names.pick_random().to_upper() \
		if _brainrot_names.size() > 0 else "LOADOUT A"
	var right_name: String = _brainrot_names.pick_random().to_upper() \
		if _brainrot_names.size() > 0 else "LOADOUT B"

	_left_name_lbl.text  = left_name
	_right_name_lbl.text = right_name
	_fit_name_font(_left_name_lbl)
	_fit_name_font(_right_name_lbl)

	_fill_stats(_left_stats_lbl,  _left_loadout.chassis,
		_left_loadout.limbs[0],  _left_loadout.limbs[1])
	_fill_stats(_right_stats_lbl, _right_loadout.chassis,
		_right_loadout.limbs[0], _right_loadout.limbs[1])

	# Power rating — relative comparison between the two loadouts.
	var lp    := _power_score(_left_loadout.chassis,  _left_loadout.limbs[0],  _left_loadout.limbs[1])
	var rp    := _power_score(_right_loadout.chassis, _right_loadout.limbs[0], _right_loadout.limbs[1])
	var total := lp + rp
	if total > 0.0:
		_left_stats_lbl.text  += "\nPower: %d%%" % roundi(lp / total * 100.0)
		_right_stats_lbl.text += "\nPower: %d%%" % roundi(rp / total * 100.0)

func _power_score(c: ChassisData, ll: LimbData, lr: LimbData) -> float:
	var mass:  float = c.mass + ll.mass * 0.1 + lr.mass * 0.1
	var reach: float = (ll.length_multiplier + lr.length_multiplier) * 0.5
	return mass * 0.5 + (c.base_torque / 15000.0) * 0.3 + reach * 0.2

func _fill_stats(lbl: Label, c: ChassisData, ll: LimbData, lr: LimbData) -> void:
	var mass:  float  = c.mass + ll.mass * 0.1 + lr.mass * 0.1
	var reach: float  = (ll.length_multiplier + lr.length_multiplier) * 0.5
	var obs:   String = SEWER_OBSERVATIONS[randi() % SEWER_OBSERVATIONS.size()]
	lbl.text = (
		"%s\n"                        +
		"%s\n"                        +
		"\"%s\"\n"                    +
		"Mass: %.1f | Torque: %.0f\n" +
		"Reach: %.1fx"
	) % [ll.name, lr.name, obs, mass, c.base_torque, reach]


# ── Draft confirmed sequence ──────────────────────────────────────────────────
func _on_draft(side: String, chosen_paper: Control) -> void:
	var loadout: Dictionary = _left_loadout if side == "left" else _right_loadout
	if loadout.is_empty():
		return

	_left_btn.disabled  = true
	_right_btn.disabled = true

	chosen_paper.pivot_offset = chosen_paper.size / 2.0
	var shove := create_tween()
	shove.tween_property(chosen_paper, "scale", Vector2(1.2, 1.2), 0.15) \
		 .set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	shove.tween_property(chosen_paper, "scale", Vector2(1.0, 1.0), 0.12) \
		 .set_ease(Tween.EASE_IN)

	var flash_color := Color(0.85, 0.18, 0.18, 0.45) if side == "left" \
					else Color(0.18, 0.48, 0.92, 0.45)
	_flash_overlay.color = flash_color
	var flash := create_tween()
	flash.tween_property(_flash_overlay, "modulate:a", 1.0, 0.07)
	flash.tween_property(_flash_overlay, "modulate:a", 0.0, 0.35) \
		 .set_ease(Tween.EASE_OUT)

	# Deduct entry cost, store loadout + side in RunManager, trigger run_started signal.
	# "left" paper = Player_Red node ("red"), "right" paper = Player_Blue node ("blue").
	var chosen_side: String = "red" if side == "left" else "blue"

	# Pre-select enemy faction and capture names for the Versus Screen.
	var _faction_pool := ["fat_rats", "wiggly_worm", "croco_loco"]
	RunManager.vs_enemy_faction_id = _faction_pool[randi() % 3]
	RunManager.vs_player_name = _left_name_lbl.text  if side == "left" else _right_name_lbl.text
	RunManager.vs_enemy_name  = _right_name_lbl.text if side == "left" else _left_name_lbl.text

	RunManager.start_run_with_loadout(loadout.chassis, loadout.limbs, chosen_side)
	if is_instance_valid(_scrap_label):
		_scrap_label.text = "SCRAP:  %d" % Global.total_scrap
	_shake_scrap_label()

	await get_tree().create_timer(0.5, true, false, true).timeout
	var fade := create_tween()
	fade.tween_property(_fade_overlay, "color:a", 1.0, 0.45) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	await fade.finished
	_show_versus_screen()


func _show_versus_screen() -> void:
	var screen := CanvasLayer.new()
	screen.layer        = 30
	screen.process_mode = Node.PROCESS_MODE_ALWAYS
	screen.set_script(preload("res://scripts/ui/VersusScreen.gd"))
	get_tree().root.add_child(screen)
	queue_free()

# Fires whenever RunManager or any system emits Events.scrap_changed.
# Keeps the Scrap_Total label in sync without needing a polling loop.
func _on_scrap_changed(new_total: int) -> void:
	if is_instance_valid(_scrap_label):
		_scrap_label.text = "SCRAP:  %d" % new_total
		_shake_scrap_label()


func _shake_scrap_label() -> void:
	var orig_x: float = _scrap_label.position.x
	var tween := create_tween()
	for i in 4:
		tween.tween_property(_scrap_label, "position:x",
				orig_x + (6.0 if i % 2 == 0 else -6.0), 0.05)
	tween.tween_property(_scrap_label, "position:x", orig_x, 0.05)
