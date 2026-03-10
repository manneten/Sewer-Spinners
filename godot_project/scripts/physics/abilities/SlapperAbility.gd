class_name SlapperAbility extends LimbAbility

## Sewer Slapper — Calculated Disrespect
## Every SLAPPER_INTERVAL seconds the limb fires a piston extension.
## During the 0.125 s outward phase a per-physics-frame RectangleShape2D shapecast
## detects the first hit: wall → Newtonian recoil, enemy chassis → Chassis Crunch.

# ── Constants ──────────────────────────────────────────────────────────────────
const LIMB_SIZE_Y:              float = 28.0   # must match LimbManager.LIMB_SIZE.y
const SLAPPER_INTERVAL:         float = 4.0
const SLAPPER_EXTEND_DURATION:  float = 0.3    # full cycle; each half = 0.15 s
const SLAPPER_STRETCH_MULT:     float = 19.5
const SLAPPER_CRUNCH_IMPULSE:   float = 6500.0
const SLAPPER_CRUNCH_SLOW_SCALE:    float = 0.10
const SLAPPER_CRUNCH_SLOW_DURATION: float = 1.0   # matches super_spark duration
const SLAPPER_WALL_RECOIL:      float = 2500.0
const SLAPPER_WOBBLE_DURATION:  float = 0.5
const SLAPPER_WOBBLE_STRENGTH:  float = 14.0

# ── State ──────────────────────────────────────────────────────────────────────
var _base_len:        float = 0.0
var _stretched_len:   float = 0.0   # full target length; used by shapecast from frame 1
var _base_radius:     float = 0.0
var _timer:           float = 0.0
var _active:          bool  = false
var _stretching:      bool  = false
var _in_extend_phase: bool  = false
var _wobble_t:        float = 0.0
var _tween:           Tween = null

# ── Init / Teardown ────────────────────────────────────────────────────────────
func initialize(spin_body: RigidBody2D, socket: Marker2D,
				rect: ColorRect, area: Area2D, manager: Node2D) -> void:
	super.initialize(spin_body, socket, rect, area, manager)
	_base_len = rect.size.x
	_timer    = LimbAbility.jitter_cooldown(SLAPPER_INTERVAL * _cooldown_mult())

	area.monitoring  = false
	area.monitorable = false  # ability owns detection; LimbManager never sees this area

	var cshape: CollisionShape2D = area.get_node_or_null("CollisionShape2D")
	if cshape and cshape.shape is CircleShape2D:
		_base_radius = (cshape.shape as CircleShape2D).radius

	# Stop the piston cleanly when the match ends so it doesn't misfire post-KO.
	Events.match_ended.connect(_on_match_ended)


func _on_match_ended(_winner: String) -> void:
	on_teardown()


func on_teardown() -> void:
	if is_instance_valid(_tween):
		_tween.kill()
	_in_extend_phase = false
	_stretching      = false
	_wobble_t        = 0.0
	_active          = false

# ── Per-frame ──────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	# Countdown to next fire.
	if not _active:
		_timer -= delta
		if _timer <= 0.0:
			_active = true
			_extend()

	# Sync visual rect and hitbox position to match the tween'd size.x.
	# This runs after LimbManager's loop (child processes after parent),
	# so it correctly overwrites the normal wobble offset during extension.
	if _stretching:
		var cur_len: float   = _rect.size.x
		var s_out:   Vector2 = _socket.position.normalized()
		_rect.position = Vector2(minf(s_out.x, 0.0) * cur_len, -LIMB_SIZE_Y * 0.5)
		if is_instance_valid(_area):
			_area.position = s_out * cur_len
			var cshape: CollisionShape2D = _area.get_node_or_null("CollisionShape2D")
			if cshape and cshape.shape is CircleShape2D:
				(cshape.shape as CircleShape2D).radius = _base_radius * (cur_len / maxf(_base_len, 0.001))

	# Post-slap recovery wobble — overrides LimbManager's RPM shake for dramatic recovery.
	if _wobble_t > 0.0:
		_wobble_t -= delta
		var w: float = SLAPPER_WOBBLE_STRENGTH * (_wobble_t / SLAPPER_WOBBLE_DURATION)
		_manager.position = Vector2(randf_range(-w, w), randf_range(-w, w))


func _physics_process(_delta: float) -> void:
	if _in_extend_phase:
		_tick_shapecast()

# ── Extension animation ────────────────────────────────────────────────────────
func _extend() -> void:
	if not is_instance_valid(_rect) or not is_instance_valid(_socket):
		_active = false
		_timer  = SLAPPER_INTERVAL
		return

	_rect.z_index    = 200
	_stretching      = true
	_in_extend_phase = true

	_stretched_len     = _base_len * SLAPPER_STRETCH_MULT
	var stretched_len: float = _stretched_len
	var half: float          = SLAPPER_EXTEND_DURATION * 0.5

	if is_instance_valid(_tween):
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_rect, "size:x", stretched_len, half) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_callback(func() -> void: _in_extend_phase = false)
	_tween.tween_property(_rect, "size:x", _base_len, half) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_callback(func() -> void: _retract())


func _retract() -> void:
	_in_extend_phase = false
	_stretching      = false
	_tween           = null

	if is_instance_valid(_rect):
		_rect.size.x  = _base_len
		_rect.z_index = 0
	if is_instance_valid(_area) and is_instance_valid(_socket):
		_area.position = _socket.position.normalized() * _base_len
		var cshape: CollisionShape2D = _area.get_node_or_null("CollisionShape2D")
		if cshape and cshape.shape is CircleShape2D:
			(cshape.shape as CircleShape2D).radius = _base_radius

	_wobble_t = SLAPPER_WOBBLE_DURATION
	_active   = false
	_timer    = SLAPPER_INTERVAL * _cooldown_mult()

# ── Shapecast detection (physics frame) ───────────────────────────────────────
func _tick_shapecast() -> void:
	if not is_instance_valid(_spin_body) or not is_instance_valid(_socket) \
			or not is_instance_valid(_rect):
		return

	var space_state  := _spin_body.get_world_2d().direct_space_state
	var outward_dir: Vector2 = (_socket.global_position - _spin_body.global_position).normalized()
	# Use the full stretched length so detection is active at full reach from the first frame,
	# regardless of where the visual tween currently sits.
	var reach: float = _stretched_len if _stretched_len > 0.0 else _rect.size.x

	var rect_shape     := RectangleShape2D.new()
	rect_shape.size     = Vector2(reach, LIMB_SIZE_Y * 0.8)
	var shape_params   := PhysicsShapeQueryParameters2D.new()
	shape_params.shape  = rect_shape
	shape_params.collision_mask = 1
	shape_params.exclude        = [_spin_body]
	var center: Vector2 = _socket.global_position + outward_dir * (reach * 0.5)
	shape_params.transform = Transform2D(outward_dir.angle(), center)

	var hits: Array = space_state.intersect_shape(shape_params, 8)
	for hit in hits:
		var collider = hit["collider"]
		if collider is StaticBody2D:
			_trigger_wall_recoil(outward_dir, reach)
			return
		if collider is RigidBody2D and collider.has_method("force_ko") and collider != _spin_body:
			if not (_spin_body._hit_cooldown > 0.0):
				_trigger_chassis_crunch(collider as RigidBody2D, outward_dir, reach)
			return

# ── Hit resolution ─────────────────────────────────────────────────────────────
func _trigger_chassis_crunch(enemy: RigidBody2D, outward_dir: Vector2, current_len: float) -> void:
	_in_extend_phase = false
	if is_instance_valid(_tween):
		_tween.kill()
		_tween = null

	var tip_world: Vector2 = _socket.global_position + outward_dir * current_len
	enemy.global_position  = tip_world
	enemy.linear_velocity  = Vector2.ZERO
	enemy.apply_central_impulse(outward_dir * SLAPPER_CRUNCH_IMPULSE)

	_manager._spawn_crit_particles(tip_world)
	_manager._spawn_sewer_splash(tip_world)
	_manager._flash_attacker()
	_manager._pulse_winner_scale()

	var enemy_ghoul: Node = enemy.get_node_or_null("Ghoul_Base")
	if enemy_ghoul and enemy_ghoul.has_method("start_ghost_trail"):
		enemy_ghoul.start_ghost_trail()

	var arena := _spin_body.get_parent()
	if arena and arena.has_method("shake_screen"):
		arena.shake_screen(20.0, 0.15)

	_spin_body._hit_cooldown = 0.5

	Events.super_spark.emit(tip_world)   # triggers camera zoom toward contact point
	Events.set_slow_mo(SLAPPER_CRUNCH_SLOW_SCALE)
	var session := Events.current_session()
	get_tree().create_timer(SLAPPER_CRUNCH_SLOW_DURATION, true, false, true).timeout.connect(
		func() -> void:
			_retract()   # always retract regardless of session — prevents permanent extension
			if Events.current_session() == session:
				Events.reset_time()
	)


func _trigger_wall_recoil(outward_dir: Vector2, current_len: float) -> void:
	_in_extend_phase = false
	if is_instance_valid(_tween):
		_tween.kill()
		_tween = null

	var stretched_len: float = _base_len * SLAPPER_STRETCH_MULT
	var fraction_used: float = clampf(current_len / maxf(stretched_len, 0.001), 0.0, 1.0)
	_spin_body.apply_central_impulse(-outward_dir * SLAPPER_WALL_RECOIL * (1.0 - fraction_used))

	_manager._spawn_sewer_splash(_socket.global_position + outward_dir * current_len)
	_retract()
