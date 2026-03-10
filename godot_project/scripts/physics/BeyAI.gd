extends Node

# ── BeyAI ─────────────────────────────────────────────────────────────────────
# Faction-specific in-arena AI for the enemy Beyblade.
# Attached as a child of the enemy RigidBody2D by SewerArena._apply_enemy_loadout().
# Call initialize() after add_child() so get_tree() is available for timers.

# ── Constants ─────────────────────────────────────────────────────────────────
const PURSUIT_FORCE:                  float = 800.0

# Wiggly Worm — Serpentine Flank + Slippery Eel Skitter
const WORM_ORBIT_INTERVAL:            float = 4.0
const WORM_ORBIT_RADIUS:              float = 120.0
const WORM_ORBIT_ANGLE:               float = PI / 4.0
const WORM_ORBIT_FORCE:               float = 1200.0
const WORM_SKITTER_RANGE:             float = 100.0
const WORM_SKITTER_IMPULSE:           float = 900.0
const WORM_SKITTER_DAMP:              float = 0.5
const WORM_SKITTER_DURATION:          float = 0.5
const WORM_SKITTER_COOLDOWN:          float = 2.0

# Croco Loco — baseline charge + Death Lunge
const CROCO_CHARGE_INTERVAL:          float = 3.5
const CROCO_CHARGE_FORCE:             float = 4500.0  # strong enough to be a visible lunge
const CROCO_BASELINE_SHIVER_DURATION: float = 0.75   # real seconds for the charge wind-up
const CROCO_BASELINE_SHIVER_STRENGTH: float = 5.0   # smaller jitter than Death Lunge
const CROCO_LUNGE_RANGE:              float = 325.0
const CROCO_LUNGE_IMPULSE:            float = 9500.0
const CROCO_SHIVER_DURATION:          float = 0.75   # Death Lunge shiver (real seconds)
const CROCO_SHIVER_STRENGTH:          float = 10.0
const CROCO_SLOW_MO_SCALE:            float = 0.2
const ARENA_CENTER:                   Vector2 = Vector2(576.0, 324.0)

# Fat Rats — Scavenger Pile
const RAT_PILE_INTERVAL:              float = 3.5   # 30% faster than original 5.0
const RAT_PILE_LAUNCH_SPEED:          float = 500.0  # fast initial glide
const RAT_PILE_STOP_DELAY:            float = 0.2    # seconds before pile freezes in place
const RAT_PILE_STATIONARY_DURATION:   float = 5.0    # seconds it stays as a solid obstacle
const RAT_PILE_RADIUS:                float = 20.0

# ── State ─────────────────────────────────────────────────────────────────────
var _faction_id:      String      = ""
var _enemy_body:      RigidBody2D = null
var _player_body:     RigidBody2D = null
var _arena:           Node        = null
var _active:          bool        = false

# Worm
var _worm_orbiting:   bool  = false
var _worm_skittering: bool  = false
var _worm_skitter_cd: bool  = false

# Croco
var _croco_charge_t:  float = 0.0
var _croco_charging:  bool  = false   # true during baseline charge shiver
var _lunge_used:      bool  = false
var _shivering:       bool  = false   # true during Death Lunge shiver


# ── Setup ──────────────────────────────────────────────────────────────────────
func initialize(faction_id: String, player_body: RigidBody2D, arena: Node) -> void:
	_faction_id  = faction_id
	_enemy_body  = get_parent() as RigidBody2D
	_player_body = player_body
	_arena       = arena
	_active      = true
	Events.match_ended.connect(_on_match_ended)

	match faction_id:
		"wiggly_worm": _start_worm_orbit_cycle()
		"fat_rats":    _start_rat_pile_cycle()


func _on_match_ended(_winner_side: String) -> void:
	_active = false
	Events.reset_time()  # safety reset if match ends during a Death Lunge shiver


# ── Per-frame AI forces ────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if not _active:
		return
	if not is_instance_valid(_enemy_body) or not is_instance_valid(_player_body):
		return

	var to_player: Vector2 = _player_body.global_position - _enemy_body.global_position
	var dist:      float   = to_player.length()

	match _faction_id:
		"fat_rats":    _tick_fat_rats(to_player, dist)
		"wiggly_worm": _tick_worm(to_player, dist)
		"croco_loco":  _tick_croco(to_player, dist, delta)


# ── Fat Rats — Scavenger Pile ──────────────────────────────────────────────────
func _tick_fat_rats(to_player: Vector2, dist: float) -> void:
	if dist > 0.0:
		_enemy_body.apply_central_force(to_player.normalized() * PURSUIT_FORCE * 0.7)


func _start_rat_pile_cycle() -> void:
	get_tree().create_timer(RAT_PILE_INTERVAL).timeout.connect(_on_rat_pile_timer)


func _on_rat_pile_timer() -> void:
	if not _active or not is_instance_valid(_enemy_body):
		return
	_spawn_dirt_pile()
	get_tree().create_timer(RAT_PILE_INTERVAL).timeout.connect(_on_rat_pile_timer)


func _spawn_dirt_pile() -> void:
	var vel:       Vector2 = _enemy_body.linear_velocity
	var behind:    Vector2 = -vel.normalized() if vel.length() > 10.0 else Vector2.DOWN
	var spawn_pos: Vector2 = _enemy_body.global_position + behind * 36.0

	var pile := RigidBody2D.new()
	pile.name          = "DirtPile"
	pile.gravity_scale = 0.0
	pile.freeze_mode   = RigidBody2D.FREEZE_MODE_STATIC
	# Layer 1 / mask 1 — same as beyblades, so all beys collide with it.
	pile.collision_layer = 1
	pile.collision_mask  = 1

	# Collision.
	var shape  := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RAT_PILE_RADIUS
	shape.shape   = circle
	pile.add_child(shape)

	# Bouncy physics material.
	var mat     := PhysicsMaterial.new()
	mat.bounce   = 0.8
	mat.friction = 0.05
	pile.physics_material_override = mat

	# Visual: muddy polygon circle.
	var poly := Polygon2D.new()
	var pts  := PackedVector2Array()
	for i in 16:
		var a: float = i * TAU / 16.0
		pts.append(Vector2(cos(a), sin(a)) * RAT_PILE_RADIUS)
	poly.polygon = pts
	poly.color   = Color(0.22, 0.14, 0.07, 0.88)
	pile.add_child(poly)

	_arena.add_child(pile)
	pile.global_position = spawn_pos

	# Exclude the spawning Rat so the pile doesn't collide with it on launch.
	pile.add_collision_exception_with(_enemy_body)

	# Shoot outward in a slightly randomised direction.
	var launch_dir: Vector2 = (
		behind + Vector2(randf_range(-0.35, 0.35), randf_range(-0.35, 0.35))
	).normalized()
	pile.linear_velocity = launch_dir * RAT_PILE_LAUNCH_SPEED

	# After stop delay: freeze in place → solid static obstacle for beyblades.
	get_tree().create_timer(RAT_PILE_STOP_DELAY).timeout.connect(func() -> void:
		if is_instance_valid(pile):
			pile.linear_velocity = Vector2.ZERO
			pile.freeze          = true
	)

	# Stay for stationary duration, then fade out and free.
	var total_wait: float = RAT_PILE_STOP_DELAY + RAT_PILE_STATIONARY_DURATION - 0.5
	var tween := pile.create_tween()
	tween.tween_interval(total_wait)
	tween.tween_property(pile, "modulate:a", 0.0, 0.5)
	tween.tween_callback(pile.queue_free)


# ── Wiggly Worm — Serpentine Flank + Slippery Eel Skitter ────────────────────
func _tick_worm(to_player: Vector2, dist: float) -> void:
	# Slippery Eel: burst sideways if player gets too close.
	if dist < WORM_SKITTER_RANGE and not _worm_skittering and not _worm_skitter_cd:
		_trigger_worm_skitter(to_player)
		return

	if _worm_orbiting:
		var orbit_offset := Vector2(WORM_ORBIT_RADIUS, 0.0).rotated(
			to_player.angle() + WORM_ORBIT_ANGLE
		)
		var to_target: Vector2 = (_player_body.global_position + orbit_offset) \
			- _enemy_body.global_position
		if to_target.length() > 0.0:
			_enemy_body.apply_central_force(to_target.normalized() * WORM_ORBIT_FORCE)
	else:
		if dist > 0.0:
			_enemy_body.apply_central_force(to_player.normalized() * PURSUIT_FORCE * 1.3)


func _trigger_worm_skitter(to_player: Vector2) -> void:
	_worm_skittering = true
	_worm_skitter_cd = true

	var side:     float   = 1.0 if randf() > 0.5 else -1.0
	var perp:     Vector2 = to_player.rotated(PI * 0.5 * side).normalized()
	_enemy_body.apply_central_impulse(perp * WORM_SKITTER_IMPULSE)

	var original_damp: float = _enemy_body.linear_damp
	_enemy_body.linear_damp  = WORM_SKITTER_DAMP

	get_tree().create_timer(WORM_SKITTER_DURATION).timeout.connect(func() -> void:
		if is_instance_valid(_enemy_body):
			_enemy_body.linear_damp = original_damp
		_worm_skittering = false
	)
	get_tree().create_timer(WORM_SKITTER_COOLDOWN).timeout.connect(func() -> void:
		_worm_skitter_cd = false
	)


func _start_worm_orbit_cycle() -> void:
	get_tree().create_timer(WORM_ORBIT_INTERVAL).timeout.connect(_on_worm_orbit_timer)


func _on_worm_orbit_timer() -> void:
	if not _active or not is_instance_valid(_enemy_body):
		return
	_worm_orbiting = not _worm_orbiting
	get_tree().create_timer(WORM_ORBIT_INTERVAL).timeout.connect(_on_worm_orbit_timer)


# ── Croco Loco — Baseline Charge + Death Lunge ────────────────────────────────
func _tick_croco(to_player: Vector2, dist: float, delta: float) -> void:
	# Baseline charge: skip timer and force application while a shiver is playing.
	if not _croco_charging and not _shivering:
		_croco_charge_t += delta
		if _croco_charge_t >= CROCO_CHARGE_INTERVAL:
			_croco_charge_t = 0.0
			_croco_charging = true
			_start_croco_baseline_shiver()

	# Death Lunge: one-time, arms when player enters range.
	if not _lunge_used and not _shivering and not _croco_charging \
			and dist < CROCO_LUNGE_RANGE:
		_lunge_used = true
		_shivering  = true
		_start_death_lunge_shiver()
		# Second Wind: reset lunge after 15 real seconds for long stalemates.
		get_tree().create_timer(15.0, true, false, true).timeout.connect(
			func() -> void: _lunge_used = false
		)


# Stops the Croco, shivers the visual for 0.7s, then charges toward the player.
func _start_croco_baseline_shiver() -> void:
	if not is_instance_valid(_enemy_body):
		_croco_charging = false
		return

	_enemy_body.linear_velocity = Vector2.ZERO

	var ghoul: Node = _enemy_body.get_node_or_null("Ghoul_Base")
	if not is_instance_valid(ghoul):
		get_tree().create_timer(CROCO_BASELINE_SHIVER_DURATION).timeout.connect(
			_execute_croco_charge
		)
		return

	var origin: Vector2 = ghoul.position
	var steps:  int     = int(CROCO_BASELINE_SHIVER_DURATION / 0.07)
	var tween          := create_tween()
	for _i in steps:
		var jitter := Vector2(
			randf_range(-CROCO_BASELINE_SHIVER_STRENGTH, CROCO_BASELINE_SHIVER_STRENGTH),
			randf_range(-CROCO_BASELINE_SHIVER_STRENGTH, CROCO_BASELINE_SHIVER_STRENGTH)
		)
		tween.tween_property(ghoul, "position", origin + jitter, 0.035)
		tween.tween_property(ghoul, "position", origin,          0.035)
	tween.tween_callback(_execute_croco_charge)


func _execute_croco_charge() -> void:
	_croco_charging = false
	if not is_instance_valid(_enemy_body) or not is_instance_valid(_player_body):
		return
	var dir := (_player_body.global_position - _enemy_body.global_position).normalized()
	_enemy_body.apply_central_impulse(dir * CROCO_CHARGE_FORCE)


# ── Croco Death Lunge ─────────────────────────────────────────────────────────
func _start_death_lunge_shiver() -> void:
	# Zoom in and enter slow-mo for the Death Lunge wind-up only.
	if is_instance_valid(_arena) and _arena.has_method("zoom_to_point"):
		_arena.zoom_to_point(_enemy_body.global_position, 1.25, 0.4)

	var ghoul: Node = _enemy_body.get_node_or_null("Ghoul_Base")
	if not is_instance_valid(ghoul):
		get_tree().create_timer(CROCO_SHIVER_DURATION / CROCO_SLOW_MO_SCALE).timeout.connect(
			_execute_death_lunge
		)
		return

	var origin: Vector2 = ghoul.position
	var steps:  int     = int(CROCO_SHIVER_DURATION / 0.05)

	# Compensate for slow-mo so the shiver runs in real-time (0.5 real seconds).
	var tween := create_tween().set_speed_scale(1.0 / Engine.time_scale)
	for _i in steps:
		var jitter := Vector2(
			randf_range(-CROCO_SHIVER_STRENGTH, CROCO_SHIVER_STRENGTH),
			randf_range(-CROCO_SHIVER_STRENGTH, CROCO_SHIVER_STRENGTH)
		)
		tween.tween_property(ghoul, "position", origin + jitter, 0.025)
		tween.tween_property(ghoul, "position", origin,          0.025)
	tween.tween_callback(_execute_death_lunge)


func _execute_death_lunge() -> void:
	_shivering = false
	# Reset time-scale and camera via Events so stale slow-mo sessions are invalidated.
	Events.reset_time()
	if not is_instance_valid(_enemy_body) or not is_instance_valid(_player_body):
		return
	var dir := (_player_body.global_position - _enemy_body.global_position).normalized()
	_enemy_body.set_meta("croco_lunge_pending", true)
	_enemy_body.apply_central_impulse(dir * CROCO_LUNGE_IMPULSE)
