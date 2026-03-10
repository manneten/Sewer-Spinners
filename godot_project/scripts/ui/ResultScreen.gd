extends CanvasLayer

# Set these before add_child() so _ready() can display correct data.
var winner_side:  String = ""   # "Red" or "Blue"
var scrap_delta:  int    = 0    # +50 or -50
var new_scrap:    int    = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 25  # above GambleScreen (layer 20)
	get_tree().paused = true
	_build_ui()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.78)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left   = -300.0
	vbox.offset_right  =  300.0
	vbox.offset_top    = -220.0
	vbox.offset_bottom =  220.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 22)
	add_child(vbox)

	# Winner headline.
	var winner_lbl := Label.new()
	winner_lbl.text = "%s WINS!" % winner_side.to_upper()
	winner_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	winner_lbl.add_theme_font_size_override("font_size", 101)
	winner_lbl.modulate = Color(0.9, 0.85, 0.1, 1.0) if scrap_delta > 0 else Color(0.9, 0.2, 0.2, 1.0)
	vbox.add_child(winner_lbl)

	# Bet result.
	var bet_lbl := Label.new()
	bet_lbl.text = ("YOU WIN  +%d SCRAP" % scrap_delta) if scrap_delta > 0 else ("YOU LOSE  %d SCRAP" % scrap_delta)
	bet_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bet_lbl.add_theme_font_size_override("font_size", 48)
	vbox.add_child(bet_lbl)

	# Total scrap.
	var total_lbl := Label.new()
	total_lbl.text = "TOTAL SCRAP: %d" % new_scrap
	total_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	total_lbl.add_theme_font_size_override("font_size", 39)
	vbox.add_child(total_lbl)

	vbox.add_child(HSeparator.new())

	# NEXT ROUND button.
	var next_btn := Button.new()
	next_btn.text = "[ NEXT ROUND ]"
	next_btn.add_theme_font_size_override("font_size", 50)
	next_btn.pressed.connect(_on_next_round)
	vbox.add_child(next_btn)

	# BEG button — only shown when bankrupt.
	if new_scrap <= 0:
		var beg_btn := Button.new()
		beg_btn.text = "[ BEG FOR SCRAPS ]  (+50)"
		beg_btn.add_theme_font_size_override("font_size", 39)
		beg_btn.pressed.connect(_on_beg)
		vbox.add_child(beg_btn)

func _on_next_round() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_beg() -> void:
	Global.total_scrap = 50
	get_tree().paused  = false
	get_tree().reload_current_scene()
