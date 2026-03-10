extends AnimatedSprite2D

## DraftingMenu — full-screen animated chassis selector.
##
## Layer order (back → front):
##   drafting_background.png  (Sprite2D, show_behind_parent)
##   self                     (AnimatedSprite2D — idle 60-frame loop, always)
##   _left_pivot / _right_pivot  (Node2D pivots anchored at top of card)
##     └─ hover sprite          (AnimatedSprite2D — idle: frozen frame 00
##                                                  active: frames 23-28 loop)
##
## Non-hovered idle effect is purely procedural:
##   • Pivot anchored at top of sprite (y = -540 local) so rotation swings
##     the bottom more than the top — "hand holding a paper card" physics.
##   • Looping SINE tween oscillates rotation ±JIGGLE_ANGLE degrees.
##   • Left and right cards start out of phase so they feel independent.

# ── Config ──────────────────────────────────────────────────────────────────
const FRAMES_PER_ANIM  := 60
const IDLE_FPS         := 60.0
const IDLE_DELAY       := 0.25

# Jiggle (non-hovered idle)
const JIGGLE_ANGLE  := 1.5   # peak rotation in degrees
const JIGGLE_PERIOD := 1.2   # seconds per half-swing

# Settled sway (after hover animation completes)
const JIGGLE_ANGLE_SETTLED  := 0.3   # very gentle
const JIGGLE_PERIOD_SETTLED := 2.0   # slower, calmer

const BOSS_NAMES  := ["Sewer King", "Worm Queen"]
const FRAME_BASE  := "res://assets/ui/drafting_menu/"
const SHADER_PATH := "res://assets/shaders/label_jitter.gdshader"
const FONT_PATH   := "res://assets/fonts/InkPen.otf"

# ── Paper label layout (sprite-local coords, 1920×1080 space) ────────────────
# Sprite center = (0,0). Adjust these until the text sits on the papers.
const PAPER_LABEL_OFFSET_LEFT:  Vector2 = Vector2(-720.0,  -80.0)
const PAPER_LABEL_OFFSET_RIGHT: Vector2 = Vector2(340.0,  -80.0)
const PAPER_LABEL_SIZE:         Vector2 = Vector2( 340.0,  420.0)
const PAPER_LABEL_FONT_SIZE:    int     = 39

# ── Node refs ───────────────────────────────────────────────────────────────
@onready var _idle_timer: Timer = $IdleTimer

# ── Hover card nodes ─────────────────────────────────────────────────────────
var _left_pivot:        Node2D           = null
var _right_pivot:       Node2D           = null
var _hover_left_sprite: AnimatedSprite2D = null
var _hover_right_sprite:AnimatedSprite2D = null
var _left_tween:        Tween            = null
var _right_tween:       Tween            = null

# ── Loadouts ─────────────────────────────────────────────────────────────────
var _chassis_left:  ChassisData = null
var _chassis_right: ChassisData = null
var _limbs_left:    Array       = []
var _limbs_right:   Array       = []

# ── Paper stat labels ────────────────────────────────────────────────────────
var _left_label:  Label = null
var _right_label: Label = null

# ── State ────────────────────────────────────────────────────────────────────
var _hover_side := ""
var _confirmed  := false
var _hover_gen  := 0   # incremented each hover change; guards stale settled callbacks


# ── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _idle_timer:
		_idle_timer.process_mode = Node.PROCESS_MODE_ALWAYS

	var vp   := get_viewport_rect()
	position  = vp.size * 0.5
	scale     = vp.size / Vector2(1920.0, 1080.0)

	# Background.
	var bg_tex := load(FRAME_BASE + "drafting_background.png") as Texture2D
	if bg_tex:
		var bg := Sprite2D.new()
		bg.texture            = bg_tex
		bg.centered           = true
		bg.show_behind_parent = true
		add_child(bg)
	else:
		push_warning("DraftingMenu: missing drafting_background.png")

	# Build one SpriteFrames shared by both hover sprites.
	var sf := _build_sprite_frames()

	# Self = main idle layer, always looping underneath.
	sprite_frames = sf
	play("idle")

	# Hover cards — pivot at the top of the sprite so rotation swings
	# the bottom. Left starts phase-flipped so both sway independently.
	var lc := _make_hover_card(sf, "hover_left_active")
	_left_pivot         = lc[0]
	_hover_left_sprite  = lc[1]
	var rc := _make_hover_card(sf, "hover_right_active")
	_right_pivot        = rc[0]
	_hover_right_sprite = rc[1]

	_left_tween  = _start_jiggle(_left_pivot,  true)
	_right_tween = _start_jiggle(_right_pivot, false)

	# Stat labels — parented to each sprite so they ride along with card rotation.
	_left_label          = _make_paper_label()
	_left_label.position = PAPER_LABEL_OFFSET_LEFT
	_hover_left_sprite.add_child(_left_label)

	_right_label          = _make_paper_label()
	_right_label.position = PAPER_LABEL_OFFSET_RIGHT
	_hover_right_sprite.add_child(_right_label)

	if _idle_timer:
		_idle_timer.timeout.connect(_on_idle_timer_timeout)
	_generate_loadouts()


# ── Card construction ─────────────────────────────────────────────────────────
func _make_hover_card(sf: SpriteFrames, active_anim: String) -> Array:
	# Pivot sits at the very top of the sprite in root local space.
	# root.scale (0.6) maps local y = -540 → screen y = 0 (top edge).
	var pivot := Node2D.new()
	pivot.position     = Vector2(0.0, -540.0)
	pivot.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(pivot)

	# Sprite hangs below the pivot so its centre lands at root centre.
	var s := AnimatedSprite2D.new()
	s.sprite_frames = sf
	s.position      = Vector2(0.0, 540.0)
	s.process_mode  = Node.PROCESS_MODE_ALWAYS
	# Rest on frame 00 of the hover sequence (idle pose).
	s.animation = active_anim.replace("_active", "_idle")
	s.frame     = 0
	_apply_shader(s)
	pivot.add_child(s)

	return [pivot, s]


# ── Jiggle tween ─────────────────────────────────────────────────────────────
func _start_jiggle(pivot: Node2D, phase_flip: bool) -> Tween:
	var angle_a :=  JIGGLE_ANGLE if not phase_flip else -JIGGLE_ANGLE
	var angle_b := -JIGGLE_ANGLE if not phase_flip else  JIGGLE_ANGLE
	var t := pivot.create_tween()
	t.set_loops()
	t.set_trans(Tween.TRANS_SINE)
	t.set_ease(Tween.EASE_IN_OUT)
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(pivot, "rotation_degrees", angle_a, JIGGLE_PERIOD)
	t.tween_property(pivot, "rotation_degrees", angle_b, JIGGLE_PERIOD)
	return t


func _kill_tween(t: Tween) -> void:
	if t and is_instance_valid(t):
		t.kill()


# ── SpriteFrames builder ─────────────────────────────────────────────────────
func _build_sprite_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")

	var idle_texs  := _load_textures("idle",        0, FRAMES_PER_ANIM)
	var left_texs  := _load_textures("hover_left",  0, FRAMES_PER_ANIM)
	var right_texs := _load_textures("hover_right", 0, FRAMES_PER_ANIM)

	_add_anim(sf, "idle",               idle_texs,  IDLE_FPS, true)
	# Full 60-frame hover animations — play once, no loop.
	_add_anim(sf, "hover_left_active",  left_texs,  IDLE_FPS, false)
	_add_anim(sf, "hover_right_active", right_texs, IDLE_FPS, false)
	# Single-frame resting poses — frame 00 of each hover sequence.
	_add_anim(sf, "hover_left_idle",  [left_texs[0]],  1.0, false)
	_add_anim(sf, "hover_right_idle", [right_texs[0]], 1.0, false)

	return sf


func _load_textures(folder: String, from: int, count: int) -> Array:
	var out := []
	for i in range(from, from + count):
		var path := "%s%s/%02d.png" % [FRAME_BASE, folder, i]
		var tex  := load(path) as Texture2D
		if tex:
			out.append(tex)
		else:
			push_warning("DraftingMenu: missing frame %s" % path)
	return out


func _add_anim(sf: SpriteFrames, anim_name: String, texs: Array,
		fps: float, loop: bool) -> void:
	sf.add_animation(anim_name)
	sf.set_animation_speed(anim_name, fps)
	sf.set_animation_loop(anim_name, loop)
	for tex in texs:
		sf.add_frame(anim_name, tex)


func _apply_shader(target: AnimatedSprite2D) -> void:
	if not ResourceLoader.exists(SHADER_PATH):
		return
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH)
	mat.set_shader_parameter("strength",        1.2)
	mat.set_shader_parameter("speed",           9.0)
	mat.set_shader_parameter("glitch_strength", 5.6)
	mat.set_shader_parameter("glitch_interval", 3.5)
	mat.set_shader_parameter("glitch_duration", 0.07)
	target.material = mat


# ── Loadout generation ───────────────────────────────────────────────────────
func _generate_loadouts() -> void:
	var all_chassis: Array = RunManager.load_all_of_class("ChassisData")
	all_chassis = all_chassis.filter(
		func(c: ChassisData) -> bool:
			return c != null and c.name not in BOSS_NAMES
	)
	all_chassis.shuffle()

	var all_limbs: Array = RunManager.load_all_of_class("LimbData")
	all_limbs.shuffle()

	_chassis_left  = all_chassis[0]
	_chassis_right = all_chassis[1 % all_chassis.size()]
	_limbs_left    = [all_limbs[0], all_limbs[1]]
	_limbs_right   = [
		all_limbs[2 % all_limbs.size()],
		all_limbs[3 % all_limbs.size()],
	]

	if _left_label:
		_left_label.text  = _format_build(_chassis_left,  _limbs_left)
	if _right_label:
		_right_label.text = _format_build(_chassis_right, _limbs_right)


# ── Paper stat label helpers ─────────────────────────────────────────────────
func _make_paper_label() -> Label:
	var lbl              := Label.new()
	lbl.size              = PAPER_LABEL_SIZE
	lbl.autowrap_mode     = TextServer.AUTOWRAP_WORD
	lbl.mouse_filter      = Control.MOUSE_FILTER_IGNORE
	var ls               := LabelSettings.new()
	ls.font_size          = PAPER_LABEL_FONT_SIZE
	ls.font_color         = Color(0.06, 0.08, 0.05, 0.90)
	ls.shadow_color       = Color(0.02, 0.04, 0.02, 0.28)
	ls.shadow_size        = 2
	ls.shadow_offset      = Vector2(1.0, 1.5)
	if ResourceLoader.exists(FONT_PATH):
		ls.font = load(FONT_PATH)
	lbl.label_settings    = ls
	return lbl


func _format_build(chassis: ChassisData, limbs: Array) -> String:
	var ll: LimbData = limbs[0]
	var lr: LimbData = limbs[1]
	var total_mass: float = chassis.mass + ll.mass * 0.1 + lr.mass * 0.1
	var avg_reach: float  = (ll.length_multiplier + lr.length_multiplier) * 0.5
	return (
		"[ %s ]\n\n"        +
		"L: %s\n"           +
		"R: %s\n\n"         +
		"Mass:   %.1f\n"    +
		"Torque: %.0f\n"    +
		"Reach:  %.2fx"
	) % [chassis.name, ll.name, lr.name, total_mass, chassis.base_torque, avg_reach]


# ── Per-frame hover tracking ─────────────────────────────────────────────────
func _process(_delta: float) -> void:
	if _confirmed:
		return
	var mouse   := get_viewport().get_mouse_position()
	var vp_rect := get_viewport_rect()
	if vp_rect.has_point(mouse):
		_idle_timer.stop()
		_update_hover(mouse)
	else:
		if _hover_side != "":
			_hover_side = ""
			_idle_timer.start(IDLE_DELAY)


# ── Input ────────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if _confirmed or _hover_side == "":
		return
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		_confirm()


# ── Hover state machine ───────────────────────────────────────────────────────
func _update_hover(mouse_screen: Vector2) -> void:
	var local    := to_local(mouse_screen)
	var new_side := "right" if local.x >= 0.0 else "left"
	if new_side == _hover_side:
		return
	_hover_side = new_side

	if new_side == "left":
		_activate(_left_pivot,  _hover_left_sprite,  "hover_left_active",  true)
		_deactivate(_right_pivot, _hover_right_sprite, false)
	else:
		_activate(_right_pivot, _hover_right_sprite, "hover_right_active", false)
		_deactivate(_left_pivot, _hover_left_sprite,  true)


func _activate(pivot: Node2D, sprite: AnimatedSprite2D,
		anim: String, is_left: bool) -> void:
	# Kill jiggle/settled tween, snap pivot upright, play full hover animation.
	_kill_tween(_left_tween if is_left else _right_tween)
	var snap := pivot.create_tween()
	snap.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	snap.set_trans(Tween.TRANS_SINE)
	snap.tween_property(pivot, "rotation_degrees", 0.0, 0.25)
	sprite.play(anim)
	# When animation finishes, switch to gentle settled sway.
	_hover_gen += 1
	var gen := _hover_gen
	sprite.animation_finished.connect(
		func(): _on_hover_settled(pivot, sprite, is_left, gen),
		CONNECT_ONE_SHOT
	)


func _deactivate(pivot: Node2D, sprite: AnimatedSprite2D,
		is_left: bool) -> void:
	# Return to resting pose (frame 00), restart jiggle.
	sprite.stop()
	sprite.animation = "hover_left_idle" if is_left else "hover_right_idle"
	sprite.frame = 0
	_kill_tween(_left_tween if is_left else _right_tween)
	var t := _start_jiggle(pivot, is_left)
	if is_left:
		_left_tween = t
	else:
		_right_tween = t


func _on_hover_settled(pivot: Node2D, sprite: AnimatedSprite2D,
		is_left: bool, gen: int) -> void:
	# Ignore if hover changed before animation finished.
	if gen != _hover_gen:
		return
	# Freeze on last frame of the hover animation.
	sprite.stop()
	sprite.frame = FRAMES_PER_ANIM - 1
	# Start very gentle sway.
	_kill_tween(_left_tween if is_left else _right_tween)
	var t := _start_settled_jiggle(pivot, is_left)
	if is_left:
		_left_tween = t
	else:
		_right_tween = t


func _start_settled_jiggle(pivot: Node2D, phase_flip: bool) -> Tween:
	var angle_a :=  JIGGLE_ANGLE_SETTLED if not phase_flip else -JIGGLE_ANGLE_SETTLED
	var angle_b := -JIGGLE_ANGLE_SETTLED if not phase_flip else  JIGGLE_ANGLE_SETTLED
	var t := pivot.create_tween()
	t.set_loops()
	t.set_trans(Tween.TRANS_SINE)
	t.set_ease(Tween.EASE_IN_OUT)
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(pivot, "rotation_degrees", angle_a, JIGGLE_PERIOD_SETTLED)
	t.tween_property(pivot, "rotation_degrees", angle_b, JIGGLE_PERIOD_SETTLED)
	return t


func _on_idle_timer_timeout() -> void:
	_hover_side = ""
	_kill_tween(_left_tween)
	_kill_tween(_right_tween)
	_hover_left_sprite.stop()
	_hover_left_sprite.animation = "hover_left_idle"
	_hover_left_sprite.frame     = 0
	_hover_right_sprite.stop()
	_hover_right_sprite.animation = "hover_right_idle"
	_hover_right_sprite.frame     = 0
	_left_tween  = _start_jiggle(_left_pivot,  true)
	_right_tween = _start_jiggle(_right_pivot, false)


# ── Confirm ───────────────────────────────────────────────────────────────────
func _confirm() -> void:
	_confirmed = true

	var chassis := _chassis_left  if _hover_side == "left" else _chassis_right
	var limbs   := _limbs_left    if _hover_side == "left" else _limbs_right

	var faction_pool := ["fat_rats", "wiggly_worm", "croco_loco"]
	RunManager.vs_enemy_faction_id = faction_pool[randi() % faction_pool.size()]
	RunManager.vs_player_name      = "PLAYER"
	RunManager.vs_enemy_name       = "SEWER GOON"

	RunManager.start_run_with_loadout(chassis, limbs, "red")

	var fade  := _make_fade_rect()
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(fade, "color:a", 1.0, 0.45).set_ease(Tween.EASE_IN)
	await tween.finished

	var versus := CanvasLayer.new()
	versus.layer        = 30
	versus.process_mode = Node.PROCESS_MODE_ALWAYS
	versus.set_script(preload("res://scripts/ui/VersusScreen.gd"))
	get_tree().root.add_child(versus)

	fade.get_parent().queue_free()
	queue_free()


func _make_fade_rect() -> ColorRect:
	var cl := CanvasLayer.new()
	cl.layer        = 99
	cl.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(cl)
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.color        = Color(0.0, 0.0, 0.0, 0.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(rect)
	return rect
