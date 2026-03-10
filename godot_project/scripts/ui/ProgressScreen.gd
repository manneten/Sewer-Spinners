extends CanvasLayer

# ── ProgressScreen ─────────────────────────────────────────────────────────────
# Shows 10 pipe icons representing the run's 10 fights.
# Animates the current win pipe (blink → fill), then routes to Shop or PostMatchLoot.

const PIPE_COUNT:     int   = 10
const PIPE_SIZE:      float = 56.0
const PIPE_GAP:       float = 10.0
const ANIM_DELAY:     float = 0.35   # pause before blink begins
const BLINK_PERIOD:   float = 0.11   # on/off half-period
const BLINK_COUNT:    int   = 6      # total blink toggles before final fill
const FILL_DURATION:  float = 0.22   # fade-in time for the fill color
const ROUTE_DELAY:    float = 2.4    # total time on screen before routing

const _POST_MATCH_LOOT = preload("res://scripts/ui/PostMatchLoot.gd")
const _SHOP_SCREEN     = preload("res://scripts/ui/ShopScreen.gd")

var _pipes: Array[ColorRect] = []


func _ready() -> void:
	layer = 25
	_build_ui()
	_start_pipe_animation()


func _build_ui() -> void:
	var vp: Vector2 = get_tree().root.get_visible_rect().size

	# Dark sewer overlay.
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.05, 0.94)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# ── Title ─────────────────────────────────────────────────────────────────
	var title := Label.new()
	title.text     = "RUN PROGRESS"
	title.position = Vector2(0.0, vp.y * 0.12)
	title.size     = Vector2(vp.x, 38.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(0.65, 0.58, 0.35, 0.92))
	root.add_child(title)

	# ── Pipe row ──────────────────────────────────────────────────────────────
	var total_w: float = PIPE_COUNT * PIPE_SIZE + (PIPE_COUNT - 1) * PIPE_GAP
	var start_x: float = (vp.x - total_w) * 0.5
	var row_y:   float = vp.y * 0.38

	_pipes.resize(PIPE_COUNT)

	for i in PIPE_COUNT:
		var x: float = start_x + i * (PIPE_SIZE + PIPE_GAP)
		var is_boss: bool = (i == 9)

		# Boss label above pipe 10.
		if is_boss:
			var boss_lbl := Label.new()
			boss_lbl.text     = "BOSS"
			boss_lbl.position = Vector2(x, row_y - 20.0)
			boss_lbl.size     = Vector2(PIPE_SIZE, 18.0)
			boss_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			boss_lbl.add_theme_font_size_override("font_size", 15)
			boss_lbl.add_theme_color_override("font_color", Color(0.95, 0.35, 0.10, 1.0))
			root.add_child(boss_lbl)

		var pipe := ColorRect.new()
		pipe.position     = Vector2(x, row_y)
		pipe.size         = Vector2(PIPE_SIZE, PIPE_SIZE)
		pipe.color        = _initial_pipe_color(i)
		pipe.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(pipe)
		_pipes[i] = pipe

		# Pipe number label below.
		var num := Label.new()
		num.text     = str(i + 1)
		num.position = Vector2(x, row_y + PIPE_SIZE + 4.0)
		num.size     = Vector2(PIPE_SIZE, 18.0)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.add_theme_font_size_override("font_size", 15)
		num.add_theme_color_override("font_color",
			Color(0.50, 0.35, 0.08, 0.90) if is_boss else Color(0.45, 0.45, 0.45, 0.70))
		root.add_child(num)

	# ── Win / Strike counters ─────────────────────────────────────────────────
	var wins_lbl := Label.new()
	wins_lbl.text     = "WINS    %d / %d" % [
		RunManager.current_wins, RunManager.WINS_TO_COMPLETE
	]
	wins_lbl.position = Vector2(0.0, vp.y * 0.62)
	wins_lbl.size     = Vector2(vp.x, 30.0)
	wins_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wins_lbl.add_theme_font_size_override("font_size", 31)
	wins_lbl.add_theme_color_override("font_color", Color(0.20, 0.90, 0.25, 1.0))
	root.add_child(wins_lbl)

	var strikes_lbl := Label.new()
	strikes_lbl.text     = "STRIKES  %d / %d" % [
		RunManager.current_losses, RunManager.LOSSES_TO_FAIL
	]
	strikes_lbl.position = Vector2(0.0, vp.y * 0.71)
	strikes_lbl.size     = Vector2(vp.x, 30.0)
	strikes_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	strikes_lbl.add_theme_font_size_override("font_size", 31)
	strikes_lbl.add_theme_color_override("font_color", Color(0.88, 0.22, 0.12, 1.0))
	root.add_child(strikes_lbl)

	# ── Hint text ─────────────────────────────────────────────────────────────
	var hint_text: String
	if RunManager.current_wins >= RunManager.WINS_TO_COMPLETE:
		hint_text = "RUN COMPLETE"
	elif RunManager.pending_shop:
		hint_text = "PIT STOP INCOMING..."
	else:
		hint_text = "NEXT FIGHT INCOMING..."

	var hint := Label.new()
	hint.text     = hint_text
	hint.position = Vector2(0.0, vp.y * 0.82)
	hint.size     = Vector2(vp.x, 24.0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 20)
	hint.add_theme_color_override("font_color", Color(0.55, 0.50, 0.30, 0.72))
	root.add_child(hint)


# Returns the initial color for pipe[i] before animation runs.
func _initial_pipe_color(index: int) -> Color:
	var wins: int = RunManager.current_wins
	if index < wins - 1:
		# Already-completed pipes.
		return Color(0.10, 0.45, 0.14, 1.0) if index < 9 else Color(0.80, 0.28, 0.04, 1.0)
	# Current and future pipes start dark.
	return Color(0.08, 0.08, 0.10, 1.0)


func _start_pipe_animation() -> void:
	var current_idx: int = RunManager.current_wins - 1   # 0-indexed
	if current_idx < 0 or current_idx >= PIPE_COUNT:
		# Edge case: no valid current pipe — just route after the delay.
		get_tree().create_timer(ROUTE_DELAY).timeout.connect(_route_to_next)
		return

	var fill_color: Color = Color(0.95, 0.38, 0.06, 1.0) if current_idx == 9 \
		else Color(0.18, 0.88, 0.30, 1.0)

	# Wait ANIM_DELAY, then kick off blink sequence.
	get_tree().create_timer(ANIM_DELAY).timeout.connect(func() -> void:
		_blink(current_idx, fill_color, BLINK_COUNT)
	)

	get_tree().create_timer(ROUTE_DELAY).timeout.connect(_route_to_next)


# Recursive blink: toggles pipe color, decrements counter, then fills.
func _blink(idx: int, fill_color: Color, blinks_left: int) -> void:
	if not is_instance_valid(_pipes[idx]):
		return
	if blinks_left <= 0:
		var tween := _pipes[idx].create_tween()
		tween.tween_property(_pipes[idx], "color", fill_color, FILL_DURATION)
		return
	_pipes[idx].color = fill_color if (blinks_left % 2 == 0) else Color(0.08, 0.08, 0.10, 1.0)
	get_tree().create_timer(BLINK_PERIOD).timeout.connect(func() -> void:
		_blink(idx, fill_color, blinks_left - 1)
	)


func _route_to_next() -> void:
	var arena: Node = get_parent()
	var screen := CanvasLayer.new()
	if RunManager.pending_shop:
		screen.set_script(_SHOP_SCREEN)
	else:
		screen.set_script(_POST_MATCH_LOOT)
	arena.add_child(screen)
	queue_free()
