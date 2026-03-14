extends CanvasLayer

# ── VersusScreen ───────────────────────────────────────────────────────────────
# Shown between GambleScreen (draft) and the SewerArena fight.
# Reads player + enemy data from RunManager; Brawl! button unpauses the tree.

const SHADER_PATH: String = "res://assets/shaders/label_jitter.gdshader"
const _FONT: Font = preload("res://assets/fonts/Demon Panic.otf")

const FACTION_DISPLAY: Dictionary = {
	"fat_rats":    "FAT RATS",
	"wiggly_worm": "WIGGLY WORM",
	"croco_loco":  "CROCO LOCO",
}

const FACTION_COLOR: Dictionary = {
	"fat_rats":    Color(0.55, 0.35, 0.18, 1.0),
	"wiggly_worm": Color(0.22, 0.68, 0.10, 1.0),
	"croco_loco":  Color(0.10, 0.55, 0.14, 1.0),
}

const TAUNTS: Array[String] = [
	"It's already inside the walls.",
	"Smells like regret and rust.",
	"Laughed when it saw you coming.",
	"Will not explain what it did last Tuesday.",
	"Has been waiting since last Thursday.",
	"Remembers everything.",
	"Counting the exits.",
	"It knows your limb names.",
	"Something drips. Rhythmically.",
	"Warm to the touch. Very warm.",
]

# ── Sewer-Chic palette ────────────────────────────────────────────────────────
const C_BG:    Color = Color(0.88, 0.82, 0.70, 0.97)  # parchment
const C_PANEL: Color = Color(0.80, 0.72, 0.58, 0.92)  # rusted tan
const C_TEXT:  Color = Color(0.18, 0.12, 0.05, 1.00)  # deep brown
const C_FAINT: Color = Color(0.40, 0.30, 0.16, 0.85)  # muted brown

var _brawl_btn: Button = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer        = 30
	_build_ui()


func _build_ui() -> void:
	var vp: Vector2 = get_tree().root.get_visible_rect().size

	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# ── Run progress badge (top-center) ──────────────────────────────────────
	var badge := Label.new()
	badge.text = "MATCH  %d / %d" % [
		RunManager.current_wins + 1, RunManager.WINS_TO_COMPLETE
	]
	badge.position = Vector2(0.0, vp.y * 0.05)
	badge.size     = Vector2(vp.x, 40.0)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_theme_font_override("font", _FONT)
	badge.add_theme_font_size_override("font_size", 31)
	badge.add_theme_color_override("font_color", C_FAINT)
	root.add_child(badge)

	# ── Left panel — Player ───────────────────────────────────────────────────
	var panel_w: float = vp.x * 0.36
	var panel_h: float = vp.y * 0.62
	var panel_y: float = vp.y * 0.16

	_make_side_panel(
		root,
		Vector2(vp.x * 0.04, panel_y),
		Vector2(panel_w, panel_h),
		"PLAYER",
		Color(0.85, 0.18, 0.18, 1.0),
		_build_player_text()
	)

	# ── Right panel — Enemy ───────────────────────────────────────────────────
	var faction_id: String = RunManager.vs_enemy_faction_id
	var faction_accent: Color = FACTION_COLOR.get(faction_id, Color(0.55, 0.22, 0.80, 1.0))

	_make_side_panel(
		root,
		Vector2(vp.x * 0.60, panel_y),
		Vector2(panel_w, panel_h),
		"ENEMY",
		faction_accent,
		_build_enemy_text(faction_id)
	)

	# ── Center VS label ───────────────────────────────────────────────────────
	var vs := Label.new()
	vs.text     = "VS"
	vs.position = Vector2(vp.x * 0.40, vp.y * 0.30)
	vs.size     = Vector2(vp.x * 0.20, vp.y * 0.22)
	vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vs.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	vs.add_theme_font_override("font", _FONT)
	vs.add_theme_font_size_override("font_size", 123)
	vs.add_theme_color_override("font_color", Color(0.72, 0.32, 0.04, 1.0))
	if ResourceLoader.exists(SHADER_PATH):
		var mat := ShaderMaterial.new()
		mat.shader = load(SHADER_PATH)
		mat.set_shader_parameter("strength", 1.8)
		mat.set_shader_parameter("speed",    10.0)
		vs.material = mat
	root.add_child(vs)

	# ── Brawl! button ─────────────────────────────────────────────────────────
	_brawl_btn = Button.new()
	_brawl_btn.text     = "BRAWL!"
	_brawl_btn.position = Vector2(vp.x * 0.50 - 115.0, vp.y * 0.85)
	_brawl_btn.size     = Vector2(230.0, 56.0)
	_brawl_btn.add_theme_font_override("font", _FONT)
	_brawl_btn.add_theme_font_size_override("font_size", 44)
	_brawl_btn.add_theme_color_override("font_color", Color(0.96, 0.94, 0.88, 1.0))
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color            = Color(0.65, 0.28, 0.05, 1.0)
	btn_style.border_width_bottom = 3
	btn_style.border_width_top    = 3
	btn_style.border_width_left   = 3
	btn_style.border_width_right  = 3
	btn_style.border_color        = Color(0.90, 0.55, 0.10, 1.0)
	_brawl_btn.add_theme_stylebox_override("normal",  btn_style)
	_brawl_btn.add_theme_stylebox_override("focus",   btn_style)
	_brawl_btn.pressed.connect(_on_brawl_pressed)
	root.add_child(_brawl_btn)


func _make_side_panel(root: Control, pos: Vector2, size: Vector2,
		role: String, accent: Color, body: String) -> void:
	var panel := ColorRect.new()
	panel.position     = pos
	panel.size         = size
	panel.color        = C_PANEL
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)

	var stripe := ColorRect.new()
	stripe.position     = Vector2.ZERO
	stripe.size         = Vector2(size.x, 5.0)
	stripe.color        = accent
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(stripe)

	var role_lbl := Label.new()
	role_lbl.text     = role
	role_lbl.position = Vector2(10.0, 12.0)
	role_lbl.size     = Vector2(size.x - 20.0, 32.0)
	role_lbl.add_theme_font_override("font", _FONT)
	role_lbl.add_theme_font_size_override("font_size", 26)
	role_lbl.add_theme_color_override("font_color", accent)
	role_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(role_lbl)

	var body_lbl := Label.new()
	body_lbl.text          = body
	body_lbl.position      = Vector2(12.0, 48.0)
	body_lbl.size          = Vector2(size.x - 24.0, size.y - 58.0)
	body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	body_lbl.add_theme_font_override("font", _FONT)
	body_lbl.add_theme_font_size_override("font_size", 29)
	body_lbl.add_theme_color_override("font_color", C_TEXT)
	body_lbl.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	panel.add_child(body_lbl)


func _build_player_text() -> String:
	var pname:   String = RunManager.vs_player_name if RunManager.vs_player_name != "" else "FIGHTER"
	var chassis: String = RunManager.player_chassis.name \
		if RunManager.player_chassis else "???"
	var l0: String = RunManager.player_limbs[0].name \
		if RunManager.player_limbs.size() > 0 else "???"
	var l1: String = RunManager.player_limbs[1].name \
		if RunManager.player_limbs.size() > 1 else "???"
	var dur0: String = RunManager.get_limb_freshness(0)
	var dur1: String = RunManager.get_limb_freshness(1)
	return "%s\n\nChassis:  %s\nArm L:    %s  [%s]\nArm R:    %s  [%s]" % [
		pname, chassis, l0, dur0, l1, dur1
	]


func _build_enemy_text(faction_id: String) -> String:
	var ename:   String = RunManager.vs_enemy_name if RunManager.vs_enemy_name != "" else "OPPONENT"
	var faction: String = FACTION_DISPLAY.get(faction_id, "UNKNOWN FACTION")
	var taunt:   String = TAUNTS[randi() % TAUNTS.size()]
	return "%s\n\nFaction:  %s\n\n\"%s\"" % [ename, faction, taunt]


func _on_brawl_pressed() -> void:
	_brawl_btn.disabled = true
	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.0)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	var fade := create_tween()
	fade.tween_property(overlay, "color:a", 1.0, 0.35).set_ease(Tween.EASE_IN)
	get_tree().create_timer(0.40, true, false, true).timeout.connect(func() -> void:
		get_tree().paused = false
		queue_free()
	)
