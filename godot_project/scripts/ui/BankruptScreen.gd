extends CanvasLayer

# Shown when the player hits 3 losses. Dramatic repossession sequence,
# then resets the run and returns to the draft screen.

const SHADER_PATH: String = "res://assets/shaders/label_jitter.gdshader"
const AUTO_PROCEED_DELAY: float = 4.0
const RESET_SCRAP: int = 100   # scrap given back so the player can try again


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 30   # above everything
	get_tree().paused = true
	_build_ui()
	# Auto-proceed after a few seconds so the player isn't stuck.
	get_tree().create_timer(AUTO_PROCEED_DELAY, true, false, true).timeout.connect(_proceed)


func _build_ui() -> void:
	var jitter_mat := ShaderMaterial.new()
	if ResourceLoader.exists(SHADER_PATH):
		jitter_mat.shader = load(SHADER_PATH)
		jitter_mat.set_shader_parameter("strength", 3.5)
		jitter_mat.set_shader_parameter("speed",    14.0)
		jitter_mat.set_shader_parameter("glitch_strength", 18.0)
		jitter_mat.set_shader_parameter("glitch_interval",  1.2)

	# Full-black overlay.
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.96)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# ── Main headline ────────────────────────────────────────────────────────
	var headline := Label.new()
	headline.text = "REPOSSESSED"
	headline.set_anchors_preset(Control.PRESET_CENTER)
	headline.offset_left   = -350.0
	headline.offset_right  =  350.0
	headline.offset_top    =  -90.0
	headline.offset_bottom =  -10.0
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	headline.add_theme_font_size_override("font_size", 101)
	headline.add_theme_color_override("font_color", Color(0.82, 0.08, 0.06, 1.0))
	headline.material = jitter_mat
	root.add_child(headline)

	var sub := Label.new()
	sub.text = "The sewer rats took everything."
	sub.set_anchors_preset(Control.PRESET_CENTER)
	sub.offset_left   = -300.0
	sub.offset_right  =  300.0
	sub.offset_top    =    8.0
	sub.offset_bottom =   46.0
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 34)
	sub.add_theme_color_override("font_color", Color(0.48, 0.42, 0.38, 0.85))
	root.add_child(sub)

	var hint := Label.new()
	hint.text = "( continuing... )"
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_left   = -200.0
	hint.offset_right  =  200.0
	hint.offset_top    = -80.0
	hint.offset_bottom = -48.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 22)
	hint.add_theme_color_override("font_color", Color(0.32, 0.30, 0.28, 0.60))
	root.add_child(hint)


func _proceed() -> void:
	# Reset run state so GambleScreen shows the draft again.
	RunManager.run_active                = false
	RunManager.player_chassis            = null
	RunManager.player_limbs              = []
	RunManager.player_limb_durabilities  = []
	RunManager.current_wins              = 0
	RunManager.current_losses            = 0

	# Give the player enough scrap to enter a new run.
	Global.total_scrap = RESET_SCRAP

	get_tree().paused = false
	get_tree().reload_current_scene()
