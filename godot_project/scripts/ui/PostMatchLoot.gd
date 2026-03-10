extends CanvasLayer

# "SCAVENGE PILE" — Post-match loot screen.
# Shown after every won fight. Player sees the ripped-off enemy limb
# and can swap it onto their rig (left or right arm) or leave it.

const SHADER_PATH: String = "res://assets/shaders/label_jitter.gdshader"

const INK:       Color = Color(0.88, 0.84, 0.72, 0.95)   # warm cream — readable on dark panels
const INK_FAINT: Color = Color(0.65, 0.62, 0.52, 0.82)   # dimmer cream
const SEWER_GREEN: Color = Color(0.059, 0.30, 0.08, 0.70)

const SKIP_QUIPS: Array[String] = [
	"Too slimy for my taste.",
	"Smells like the Croco King's feet.",
	"It's still twitching. Pass.",
	"Left it for the rats — they deserve it.",
	"The sewer spirits reject this offering.",
	"Tried to lick it. Immediately regretted it.",
	"My current arm is MORE rotten and I LIKE it.",
	"Threw it back in the gutter where it belongs.",
	"Cursed. That thing is definitely cursed.",
	"Something bit me when I touched it.",
	"Smells like burning and old regret.",
	"It looked at me funny.",
	"Already decomposing. Respectfully, no.",
	"I have standards. Barely, but I have them.",
	"The rats fought me for it. The rats won.",
	"Tastes of copper and bad decisions.",
]

const FRESH_PREFIX: Array[String]   = ["▓▓▓", "▒▒░", "░░░", "✕✕✕"]
const FRESH_LABELS: Array[String]   = ["FRESH", "WITHERED", "ROTTING", "FALLING OFF"]

var _offered_limb:    LimbData = null
var _swap_lbl_l:      Label    = null
var _swap_lbl_r:      Label    = null
var _skip_quip_lbl:   Label    = null
var _shake_tween_l:   Tween    = null
var _shake_tween_r:   Tween    = null
var _own_particles:   Array    = []   # CPUParticles2D added to root; cleaned up on exit.


# ── Entry ──────────────────────────────────────────────────────────────────────
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 25
	get_tree().paused = true
	_offered_limb = _pick_loot()
	_build_ui()


# ── Loot pick ──────────────────────────────────────────────────────────────────
func _pick_loot() -> LimbData:
	var pool: Array = RunManager.load_all_of_class("LimbData")
	var filtered: Array = []
	for item in pool:
		var l := item as LimbData
		if l and l.name != "Broken Nub":
			filtered.append(l)
	if filtered.is_empty():
		return null
	filtered.shuffle()
	return filtered[0] as LimbData


# ── Shader helper ──────────────────────────────────────────────────────────────
func _jitter(strength: float = 1.5, speed: float = 9.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	if ResourceLoader.exists(SHADER_PATH):
		mat.shader = load(SHADER_PATH)
		mat.set_shader_parameter("strength", strength)
		mat.set_shader_parameter("speed",    speed)
	return mat


# ── Main UI build ──────────────────────────────────────────────────────────────
func _build_ui() -> void:
	var vp: Vector2 = get_tree().root.get_visible_rect().size

	# ── Sewer-floor background ─────────────────────────────────────────────────
	var bg := ColorRect.new()
	bg.color = Color(0.055, 0.10, 0.055, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Subtle grime drips across the upper half — ambient atmosphere.
	for i in 6:
		_spawn_grime_drip(Vector2(randf_range(60.0, vp.x - 60.0),
			randf_range(10.0, vp.y * 0.45)))

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# ── Top banner ─────────────────────────────────────────────────────────────
	var banner := ColorRect.new()
	banner.color = Color(0.07, 0.14, 0.07, 1.0)
	banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	banner.offset_bottom = 68.0
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(banner)

	var banner_line := ColorRect.new()
	banner_line.color = SEWER_GREEN
	banner_line.set_anchors_preset(Control.PRESET_TOP_WIDE)
	banner_line.offset_top    = 66.0
	banner_line.offset_bottom = 69.0
	banner_line.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	root.add_child(banner_line)

	var win_lbl := Label.new()
	win_lbl.text     = "ROUND WON"
	win_lbl.position = Vector2(22, 10)
	win_lbl.add_theme_font_size_override("font_size", 53)
	win_lbl.add_theme_color_override("font_color", Color(0.15, 0.82, 0.28, 1.0))
	win_lbl.material = _jitter(1.3, 9.0)
	root.add_child(win_lbl)

	var state_lbl := Label.new()
	state_lbl.text = "wins  %d / %d        strikes  %d / %d" % [
		RunManager.current_wins,   RunManager.WINS_TO_COMPLETE,
		RunManager.current_losses, RunManager.LOSSES_TO_FAIL,
	]
	state_lbl.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	state_lbl.offset_left   = -380.0
	state_lbl.offset_bottom =  68.0
	state_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	state_lbl.add_theme_font_size_override("font_size", 22)
	state_lbl.add_theme_color_override("font_color", Color(0.42, 0.55, 0.40, 0.82))
	root.add_child(state_lbl)

	# ── Content area ───────────────────────────────────────────────────────────
	var top:    float = 76.0
	var bot:    float = vp.y - 90.0
	var left_w: float = vp.x * 0.44
	var pad:    float = 12.0

	_build_loot_panel(root,
		Vector2(pad, top),
		Vector2(left_w - pad * 2.0, bot - top))

	_build_loadout_panel(root,
		Vector2(left_w + pad, top),
		Vector2(vp.x - left_w - pad * 2.0, bot - top))

	# ── Skip strip ─────────────────────────────────────────────────────────────
	var skip_line := ColorRect.new()
	skip_line.color = SEWER_GREEN
	skip_line.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	skip_line.offset_top    = -90.0
	skip_line.offset_bottom = -87.0
	skip_line.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	root.add_child(skip_line)

	var skip_btn := Button.new()
	skip_btn.text = "▷   LEAVE IT IN THE GUTTER"
	skip_btn.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	skip_btn.offset_left   =  18.0
	skip_btn.offset_right  = 420.0
	skip_btn.offset_top    = -82.0
	skip_btn.offset_bottom = -46.0
	skip_btn.add_theme_font_size_override("font_size", 27)
	skip_btn.add_theme_color_override("font_color", Color(0.52, 0.50, 0.43, 0.88))
	var skip_style := StyleBoxFlat.new()
	skip_style.bg_color = Color(0.03, 0.05, 0.02, 0.0)
	skip_btn.add_theme_stylebox_override("normal", skip_style)
	skip_btn.add_theme_stylebox_override("focus",  skip_style)
	var skip_hover := StyleBoxFlat.new()
	skip_hover.bg_color = Color(0.06, 0.10, 0.05, 0.6)
	skip_btn.add_theme_stylebox_override("hover",   skip_hover)
	skip_btn.add_theme_stylebox_override("pressed", skip_hover)
	skip_btn.pressed.connect(_on_skip)
	skip_btn.mouse_entered.connect(_on_skip_hover)
	root.add_child(skip_btn)

	_skip_quip_lbl = Label.new()
	_skip_quip_lbl.text = ""
	_skip_quip_lbl.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_skip_quip_lbl.offset_left   =  22.0
	_skip_quip_lbl.offset_right  = 740.0
	_skip_quip_lbl.offset_top    = -42.0
	_skip_quip_lbl.offset_bottom = -12.0
	_skip_quip_lbl.add_theme_font_size_override("font_size", 20)
	_skip_quip_lbl.add_theme_color_override("font_color", Color(0.38, 0.36, 0.30, 0.68))
	root.add_child(_skip_quip_lbl)


# ── Left panel: scavenged limb ─────────────────────────────────────────────────
func _build_loot_panel(root: Control, pos: Vector2, size: Vector2) -> void:
	var panel := ColorRect.new()
	panel.position    = pos
	panel.size        = size
	panel.color       = Color(0.07, 0.14, 0.07, 0.92)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)

	# Scratchy border — two thin lines inset slightly.
	for offset in [0, 2]:
		var border := ColorRect.new()
		border.position    = pos + Vector2(offset, offset)
		border.size        = size - Vector2(offset * 2, offset * 2)
		border.color       = Color(0.10, 0.40, 0.12, 0.40 - offset * 0.1)
		border.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(border)

	# Scrawled header.
	var hdr := Label.new()
	hdr.text     = "SCAVENGED FROM THE WRECKAGE"
	hdr.position = pos + Vector2(12, 10)
	hdr.add_theme_font_size_override("font_size", 18)
	hdr.add_theme_color_override("font_color", Color(0.32, 0.48, 0.28, 0.75))
	root.add_child(hdr)

	var sep_lbl := Label.new()
	sep_lbl.text     = "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	sep_lbl.position = pos + Vector2(12, 28)
	sep_lbl.add_theme_font_size_override("font_size", 15)
	sep_lbl.add_theme_color_override("font_color", SEWER_GREEN)
	root.add_child(sep_lbl)

	if not _offered_limb:
		var none_lbl := Label.new()
		none_lbl.text     = "( the pile is empty )"
		none_lbl.position = pos + Vector2(14, 70)
		none_lbl.add_theme_color_override("font_color", INK_FAINT)
		root.add_child(none_lbl)
		return

	# Limb name — big, heavy jitter, ink-bleed.
	var name_lbl := Label.new()
	name_lbl.text     = _offered_limb.name.to_upper()
	name_lbl.position = pos + Vector2(12, 46)
	name_lbl.size     = Vector2(size.x * 0.58, 46)
	name_lbl.add_theme_font_size_override("font_size", 42)
	name_lbl.add_theme_color_override("font_color", INK)
	name_lbl.material = _jitter(2.2, 12.0)
	root.add_child(name_lbl)

	# Freshness — always FRESH for newly looted parts.
	var fresh_lbl := Label.new()
	fresh_lbl.text     = "▓▓▓  FRESH"
	fresh_lbl.position = pos + Vector2(12, 94)
	fresh_lbl.add_theme_font_size_override("font_size", 24)
	fresh_lbl.add_theme_color_override("font_color", Color(0.20, 0.85, 0.30, 1.0))
	fresh_lbl.material = _jitter(0.9, 7.0)
	root.add_child(fresh_lbl)

	# Stats in ink.
	var stats_lbl := Label.new()
	stats_lbl.text = (
		"mass:    %.1f kg\n" +
		"reach:   %.1fx\n"   +
		"wobble:  %.1f"
	) % [_offered_limb.mass, _offered_limb.length_multiplier, _offered_limb.wobble_intensity]
	stats_lbl.position = pos + Vector2(12, 122)
	stats_lbl.add_theme_font_size_override("font_size", 22)
	stats_lbl.add_theme_color_override("font_color", INK)
	stats_lbl.material = _jitter(0.7, 6.0)
	root.add_child(stats_lbl)

	# Colour swatch — physical sample of the limb material.
	var swatch_pos: Vector2  = pos + Vector2(size.x * 0.60, 48)
	var swatch_size: Vector2 = Vector2(size.x * 0.34, size.y * 0.30)
	var swatch := ColorRect.new()
	swatch.position    = swatch_pos
	swatch.size        = swatch_size
	swatch.color       = _offered_limb.color
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(swatch)

	var swatch_lbl := Label.new()
	swatch_lbl.text     = "MATERIAL\nSAMPLE"
	swatch_lbl.position = swatch_pos + Vector2(4, swatch_size.y + 6)
	swatch_lbl.add_theme_font_size_override("font_size", 15)
	swatch_lbl.add_theme_color_override("font_color", Color(0.32, 0.45, 0.28, 0.60))
	root.add_child(swatch_lbl)

	# Sparks — golden, short-burst, looping.
	_spawn_sparks(swatch_pos + Vector2(swatch_size.x * 0.5, swatch_size.y * 0.3))
	# Oil drip — dark viscous drops falling from the swatch edge.
	_spawn_oil_drip(swatch_pos + Vector2(swatch_size.x * 0.65, 0.0))

	# Scrawled call-to-action near the bottom of the panel.
	var cta_lbl := Label.new()
	cta_lbl.text     = "KEEP THE MEAT?"
	cta_lbl.position = pos + Vector2(12, size.y - 48)
	cta_lbl.add_theme_font_size_override("font_size", 28)
	cta_lbl.add_theme_color_override("font_color", Color(0.70, 0.65, 0.48, 0.88))
	cta_lbl.material = _jitter(2.0, 13.0)
	root.add_child(cta_lbl)


# ── Right panel: current loadout + swap buttons ────────────────────────────────
func _build_loadout_panel(root: Control, pos: Vector2, size: Vector2) -> void:
	var panel := ColorRect.new()
	panel.position    = pos
	panel.size        = size
	panel.color       = Color(0.065, 0.12, 0.065, 0.92)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)

	var hdr := Label.new()
	hdr.text     = "YOUR CURRENT MEAT"
	hdr.position = pos + Vector2(12, 10)
	hdr.add_theme_font_size_override("font_size", 18)
	hdr.add_theme_color_override("font_color", Color(0.32, 0.48, 0.28, 0.75))
	root.add_child(hdr)

	var sep_lbl := Label.new()
	sep_lbl.text     = "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	sep_lbl.position = pos + Vector2(12, 28)
	sep_lbl.add_theme_font_size_override("font_size", 15)
	sep_lbl.add_theme_color_override("font_color", SEWER_GREEN)
	root.add_child(sep_lbl)

	var limb_l: LimbData = RunManager.player_limbs[0] if RunManager.player_limbs.size() > 0 else null
	var limb_r: LimbData = RunManager.player_limbs[1] if RunManager.player_limbs.size() > 1 else null

	var slot_w: float = (size.x - 36.0) * 0.5
	var slot_h: float = size.y - 96.0

	_swap_lbl_l = _build_swap_slot(
		root,
		pos + Vector2(12.0, 48.0),
		Vector2(slot_w, slot_h),
		limb_l, 0,
		"▶  SWAP LEFT ARM",
		Color(0.85, 0.18, 0.18, 1.0)
	)
	_swap_lbl_r = _build_swap_slot(
		root,
		pos + Vector2(slot_w + 24.0, 48.0),
		Vector2(slot_w, slot_h),
		limb_r, 1,
		"▶  SWAP RIGHT ARM",
		Color(0.18, 0.48, 0.92, 1.0)
	)

	# "SCRAP THIS?" prompt above the buttons, scrawled.
	var scrap_lbl := Label.new()
	scrap_lbl.text = "SCRAP THIS?"
	scrap_lbl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	scrap_lbl.position = pos + Vector2(size.x - 190.0, size.y - 42.0)
	scrap_lbl.add_theme_font_size_override("font_size", 25)
	scrap_lbl.add_theme_color_override("font_color", Color(0.68, 0.62, 0.44, 0.72))
	scrap_lbl.material = _jitter(1.8, 11.0)
	root.add_child(scrap_lbl)


func _build_swap_slot(root: Control, pos: Vector2, size: Vector2,
		limb: LimbData, limb_idx: int,
		btn_text: String, btn_color: Color) -> Label:

	var slot_bg := ColorRect.new()
	slot_bg.position    = pos
	slot_bg.size        = size
	slot_bg.color       = Color(0.09, 0.17, 0.08, 0.88)
	slot_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(slot_bg)

	var limb_name: String = limb.name.to_upper() if limb else "???"
	var freshness: String = _freshness_text(limb_idx)
	var frs_col:   Color  = RunManager.get_freshness_color(limb_idx)

	# Limb name — shakes on hover (stored so we can animate it).
	var name_lbl := Label.new()
	name_lbl.text     = limb_name
	name_lbl.position = pos + Vector2(8.0, 8.0)
	name_lbl.size     = Vector2(size.x - 16.0, 34.0)
	name_lbl.add_theme_font_size_override("font_size", 27)
	name_lbl.add_theme_color_override("font_color", INK)
	name_lbl.material = _jitter(0.9, 7.0)
	root.add_child(name_lbl)

	# Freshness state.
	var fresh_lbl := Label.new()
	fresh_lbl.text     = freshness
	fresh_lbl.position = pos + Vector2(8.0, 44.0)
	fresh_lbl.add_theme_font_size_override("font_size", 20)
	fresh_lbl.add_theme_color_override("font_color", frs_col)
	fresh_lbl.material = _jitter(0.6, 6.0)
	root.add_child(fresh_lbl)

	# Compact stats.
	if limb:
		var stats_lbl := Label.new()
		stats_lbl.text     = "%.1fkg  ·  %.1fx  ·  w%.1f" % [
			limb.mass, limb.length_multiplier, limb.wobble_intensity
		]
		stats_lbl.position = pos + Vector2(8.0, 66.0)
		stats_lbl.add_theme_font_size_override("font_size", 18)
		stats_lbl.add_theme_color_override("font_color", INK_FAINT)
		root.add_child(stats_lbl)

	# Colour strip.
	var strip := ColorRect.new()
	strip.color        = limb.color if limb else Color(0.15, 0.10, 0.08, 1.0)
	strip.position     = pos + Vector2(8.0, 86.0)
	strip.size         = Vector2(size.x - 16.0, 10.0)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(strip)

	# Durability pip row: filled squares = remaining fights.
	var dur: int = RunManager.player_limb_durabilities[limb_idx] \
		if limb_idx < RunManager.player_limb_durabilities.size() else RunManager.LIMB_MAX_DURABILITY
	for pip_i in RunManager.LIMB_MAX_DURABILITY:
		var pip := ColorRect.new()
		pip.size        = Vector2(14.0, 10.0)
		pip.position    = pos + Vector2(8.0 + pip_i * 18.0, 100.0)
		pip.color       = frs_col if pip_i < dur else Color(0.12, 0.12, 0.10, 0.6)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(pip)

	# Swap button.
	var btn := Button.new()
	btn.text     = btn_text
	btn.position = pos + Vector2(4.0, size.y - 46.0)
	btn.size     = Vector2(size.x - 8.0, 40.0)
	btn.add_theme_font_size_override("font_size", 21)
	btn.add_theme_color_override("font_color", btn_color)

	var sn := StyleBoxFlat.new()
	sn.bg_color          = Color(0.06, 0.10, 0.06, 0.90)
	sn.border_color      = btn_color.darkened(0.25)
	sn.border_width_top = 1; sn.border_width_bottom = 1
	sn.border_width_left = 1; sn.border_width_right  = 1
	var sh := StyleBoxFlat.new()
	sh.bg_color          = Color(0.10, 0.16, 0.10, 0.95)
	sh.border_color      = btn_color
	sh.border_width_top = 2; sh.border_width_bottom = 2
	sh.border_width_left = 2; sh.border_width_right  = 2
	btn.add_theme_stylebox_override("normal",  sn)
	btn.add_theme_stylebox_override("focus",   sn)
	btn.add_theme_stylebox_override("hover",   sh)
	btn.add_theme_stylebox_override("pressed", sh)

	if limb_idx == 0:
		btn.pressed.connect(_on_take_left)
		btn.mouse_entered.connect(_start_shake.bind(true))
		btn.mouse_exited.connect(_stop_shake.bind(true))
	else:
		btn.pressed.connect(_on_take_right)
		btn.mouse_entered.connect(_start_shake.bind(false))
		btn.mouse_exited.connect(_stop_shake.bind(false))

	root.add_child(btn)
	return name_lbl


# ── Freshness helpers ──────────────────────────────────────────────────────────
func _freshness_text(idx: int) -> String:
	var label: String = RunManager.get_limb_freshness(idx)
	match label:
		"FRESH":       return "▓▓▓  FRESH"
		"WITHERED":    return "▒▒░  WITHERED"
		"ROTTING":     return "░░░  ROTTING"
		_:             return "✕✕✕  FALLING OFF"


# ── Hover shake ────────────────────────────────────────────────────────────────
func _start_shake(is_left: bool) -> void:
	var lbl: Label = _swap_lbl_l if is_left else _swap_lbl_r
	if not is_instance_valid(lbl):
		return
	# Capture original x once; reuse on repeated hovers.
	if not lbl.has_meta("orig_x"):
		lbl.set_meta("orig_x", lbl.position.x)
	var base_x: float = lbl.get_meta("orig_x") as float

	if is_left:
		if _shake_tween_l:
			_shake_tween_l.kill()
		_shake_tween_l = create_tween().set_loops()
		_shake_tween_l.tween_property(lbl, "position:x", base_x + 3.5, 0.035)
		_shake_tween_l.tween_property(lbl, "position:x", base_x - 3.5, 0.035)
		_shake_tween_l.tween_property(lbl, "position:x", base_x,       0.035)
	else:
		if _shake_tween_r:
			_shake_tween_r.kill()
		_shake_tween_r = create_tween().set_loops()
		_shake_tween_r.tween_property(lbl, "position:x", base_x + 3.5, 0.035)
		_shake_tween_r.tween_property(lbl, "position:x", base_x - 3.5, 0.035)
		_shake_tween_r.tween_property(lbl, "position:x", base_x,       0.035)


func _stop_shake(is_left: bool) -> void:
	var lbl: Label = _swap_lbl_l if is_left else _swap_lbl_r
	if is_left:
		if _shake_tween_l:
			_shake_tween_l.kill()
			_shake_tween_l = null
	else:
		if _shake_tween_r:
			_shake_tween_r.kill()
			_shake_tween_r = null
	if is_instance_valid(lbl) and lbl.has_meta("orig_x"):
		lbl.position.x = lbl.get_meta("orig_x") as float


# ── Skip quip ──────────────────────────────────────────────────────────────────
func _on_skip_hover() -> void:
	if _skip_quip_lbl:
		_skip_quip_lbl.text = "\"%s\"" % \
			SKIP_QUIPS[randi() % SKIP_QUIPS.size()]


# ── Particle spawners ──────────────────────────────────────────────────────────
func _spawn_sparks(pos: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.z_index              = 200
	p.one_shot             = false
	p.lifetime             = 0.55
	p.amount               = 10
	p.explosiveness        = 0.25
	p.direction            = Vector2.UP
	p.spread               = 60.0
	p.gravity              = Vector2(0.0, 50.0)
	p.initial_velocity_min = 35.0
	p.initial_velocity_max = 100.0
	p.scale_amount_min     = 2.0
	p.scale_amount_max     = 4.5
	p.color                = Color(1.0, 0.82, 0.05, 1.0)
	get_tree().root.add_child(p)
	p.global_position = pos
	p.emitting = true
	_own_particles.append(p)


func _spawn_oil_drip(pos: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.z_index              = 200
	p.one_shot             = false
	p.lifetime             = 1.4
	p.amount               = 5
	p.explosiveness        = 0.0
	p.direction            = Vector2.DOWN
	p.spread               = 6.0
	p.gravity              = Vector2(0.0, 60.0)
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 28.0
	p.scale_amount_min     = 3.0
	p.scale_amount_max     = 6.0
	p.color                = Color(0.06, 0.03, 0.10, 0.88)
	get_tree().root.add_child(p)
	p.global_position = pos
	p.emitting = true
	_own_particles.append(p)


func _spawn_grime_drip(pos: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.z_index              = 8
	p.one_shot             = false
	p.lifetime             = 3.0
	p.amount               = 2
	p.explosiveness        = 0.0
	p.direction            = Vector2.DOWN
	p.spread               = 4.0
	p.gravity              = Vector2(0.0, 12.0)
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 10.0
	p.scale_amount_min     = 2.0
	p.scale_amount_max     = 3.5
	p.color                = Color(0.04, 0.08, 0.03, 0.42)
	get_tree().root.add_child(p)
	p.global_position = pos
	p.emitting = true
	_own_particles.append(p)


# ── Actions ────────────────────────────────────────────────────────────────────
func _on_take_left() -> void:
	if _offered_limb and RunManager.player_limbs.size() >= 1:
		RunManager.player_limbs[0]             = _offered_limb
		RunManager.player_limb_durabilities[0] = RunManager.LIMB_MAX_DURABILITY
	_proceed()


func _on_take_right() -> void:
	if _offered_limb and RunManager.player_limbs.size() >= 2:
		RunManager.player_limbs[1]             = _offered_limb
		RunManager.player_limb_durabilities[1] = RunManager.LIMB_MAX_DURABILITY
	_proceed()


func _on_skip() -> void:
	_proceed()


func _proceed() -> void:
	for p in _own_particles:
		if is_instance_valid(p):
			p.queue_free()
	_own_particles.clear()
	get_tree().paused = false
	get_tree().reload_current_scene()
