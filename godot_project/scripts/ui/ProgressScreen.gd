extends CanvasLayer

# ── ProgressScreen ─────────────────────────────────────────────────────────────
# Shows 10 pipe icons representing the run's 10 fights.
# Animates the current win pipe (blink → fill), then routes to Shop or PostMatchLoot.

const PIPE_COUNT:     int   = 10
const PIPE_SIZE:      float = 56.0
const PIPE_GAP:       float = 10.0
const ANIM_DELAY:     float = 0.35
const BLINK_PERIOD:   float = 0.11
const BLINK_COUNT:    int   = 6
const FILL_DURATION:  float = 0.22
const ROUTE_DELAY:    float = 2.4

const _POST_MATCH_LOOT = preload("res://scripts/ui/PostMatchLoot.gd")
const _SHOP_SCREEN     = preload("res://scripts/ui/ShopScreen.gd")
const _FONT: Font      = preload("res://assets/fonts/Demon Panic.otf")

# ── Sewer-Chic palette ────────────────────────────────────────────────────────
const C_BG:             Color = Color(0.88, 0.82, 0.70, 0.96)
const C_TEXT:           Color = Color(0.18, 0.12, 0.05, 1.00)
const C_FAINT:          Color = Color(0.40, 0.30, 0.16, 0.85)
const C_PIPE_DONE:      Color = Color(0.10, 0.52, 0.18, 1.00)
const C_PIPE_BOSS_DONE: Color = Color(0.80, 0.28, 0.04, 1.00)
const C_PIPE_IDLE:      Color = Color(0.65, 0.58, 0.46, 1.00)
const C_PIPE_CURR:      Color = Color(0.95, 0.55, 0.08, 1.00)
const C_PIPE_BOSS_IDLE: Color = Color(0.72, 0.40, 0.20, 1.00)

var _pipes: Array[ColorRect] = []


func _ready() -> void:
	layer = 25
	_build_ui()
	_start_pipe_animation()


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

	# ── Title ─────────────────────────────────────────────────────────────────
	var title := Label.new()
	title.text     = "RUN PROGRESS"
	title.position = Vector2(0.0, vp.y * 0.10)
	title.size     = Vector2(vp.x, 62.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", _FONT)
	title.add_theme_font_size_override("font_size", 59)
	title.add_theme_color_override("font_color", C_TEXT)
	root.add_child(title)

	# ── Pipe row ──────────────────────────────────────────────────────────────
	var total_w: float = PIPE_COUNT * PIPE_SIZE + (PIPE_COUNT - 1) * PIPE_GAP
	var start_x: float = (vp.x - total_w) * 0.5
	var row_y:   float = vp.y * 0.36

	_pipes.resize(PIPE_COUNT)

	var current_idx: int = RunManager.current_wins - 1

	for i in PIPE_COUNT:
		var x: float = start_x + i * (PIPE_SIZE + PIPE_GAP)
		var is_boss: bool = (i == 9)

		if is_boss:
			var boss_lbl := Label.new()
			boss_lbl.text     = "BOSS"
			boss_lbl.position = Vector2(x, row_y - 28.0)
			boss_lbl.size     = Vector2(PIPE_SIZE, 26.0)
			boss_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			boss_lbl.add_theme_font_override("font", _FONT)
			boss_lbl.add_theme_font_size_override("font_size", 22)
			boss_lbl.add_theme_color_override("font_color", Color(0.82, 0.28, 0.05, 1.0))
			root.add_child(boss_lbl)

		if i == current_idx:
			var ring := ColorRect.new()
			ring.position     = Vector2(x - 5.0, row_y - 5.0)
			ring.size         = Vector2(PIPE_SIZE + 10.0, PIPE_SIZE + 10.0)
			ring.color        = Color(0.85, 0.50, 0.05, 0.85)
			ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
			root.add_child(ring)

		var pipe := ColorRect.new()
		pipe.position     = Vector2(x, row_y)
		pipe.size         = Vector2(PIPE_SIZE, PIPE_SIZE)
		pipe.color        = _initial_pipe_color(i)
		pipe.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(pipe)
		_pipes[i] = pipe

		var num := Label.new()
		num.text     = str(i + 1)
		num.position = Vector2(x, row_y + PIPE_SIZE + 6.0)
		num.size     = Vector2(PIPE_SIZE, 24.0)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.add_theme_font_override("font", _FONT)
		num.add_theme_font_size_override("font_size", 20)
		num.add_theme_color_override("font_color",
			Color(0.72, 0.32, 0.04, 1.0) if is_boss else C_FAINT)
		root.add_child(num)

	# ── Win / Strike counters ─────────────────────────────────────────────────
	var wins_lbl := Label.new()
	wins_lbl.text     = "WINS    %d / %d" % [
		RunManager.current_wins, RunManager.WINS_TO_COMPLETE
	]
	wins_lbl.position = Vector2(0.0, vp.y * 0.62)
	wins_lbl.size     = Vector2(vp.x, 46.0)
	wins_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wins_lbl.add_theme_font_override("font", _FONT)
	wins_lbl.add_theme_font_size_override("font_size", 44)
	wins_lbl.add_theme_color_override("font_color", Color(0.10, 0.72, 0.20, 1.0))
	root.add_child(wins_lbl)

	var strikes_lbl := Label.new()
	strikes_lbl.text     = "STRIKES  %d / %d" % [
		RunManager.current_losses, RunManager.LOSSES_TO_FAIL
	]
	strikes_lbl.position = Vector2(0.0, vp.y * 0.72)
	strikes_lbl.size     = Vector2(vp.x, 46.0)
	strikes_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	strikes_lbl.add_theme_font_override("font", _FONT)
	strikes_lbl.add_theme_font_size_override("font_size", 44)
	strikes_lbl.add_theme_color_override("font_color", Color(0.82, 0.18, 0.10, 1.0))
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
	hint.position = Vector2(0.0, vp.y * 0.84)
	hint.size     = Vector2(vp.x, 34.0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_override("font", _FONT)
	hint.add_theme_font_size_override("font_size", 29)
	hint.add_theme_color_override("font_color", C_FAINT)
	root.add_child(hint)


func _initial_pipe_color(index: int) -> Color:
	var wins: int = RunManager.current_wins
	if index < wins - 1:
		return C_PIPE_BOSS_DONE if index == 9 else C_PIPE_DONE
	return C_PIPE_BOSS_IDLE if index == 9 else C_PIPE_IDLE


func _start_pipe_animation() -> void:
	var current_idx: int = RunManager.current_wins - 1
	if current_idx < 0 or current_idx >= PIPE_COUNT:
		get_tree().create_timer(ROUTE_DELAY).timeout.connect(_route_to_next)
		return

	var fill_color: Color = C_PIPE_BOSS_DONE if current_idx == 9 else C_PIPE_CURR

	get_tree().create_timer(ANIM_DELAY).timeout.connect(func() -> void:
		_blink(current_idx, fill_color, BLINK_COUNT)
	)

	get_tree().create_timer(ROUTE_DELAY).timeout.connect(_route_to_next)


func _blink(idx: int, fill_color: Color, blinks_left: int) -> void:
	if not is_instance_valid(_pipes[idx]):
		return
	if blinks_left <= 0:
		var tween := _pipes[idx].create_tween()
		tween.tween_property(_pipes[idx], "color", fill_color, FILL_DURATION)
		return
	_pipes[idx].color = fill_color if (blinks_left % 2 == 0) else C_PIPE_IDLE
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
