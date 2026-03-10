class_name SludgeGeyser extends Area2D

## Sludge Geyser — corner launch hazard.
## A pressurized sewer vent blasts any Bey that rolls into the corner toward
## the arena center. While airborne the Bey flies over walls without taking
## RPM penalties (SpinController checks the "airborne" meta). On landing a
## Crush check fires: any enemy within CRUSH_RADIUS gets hit with a heavy
## impulse and loses RPM, triggering slow-mo and screen shake.

# ── Constants ──────────────────────────────────────────────────────────────────
const ARENA_CENTER:        Vector2 = Vector2(576.0, 324.0)
const GEYSER_LAUNCH:       float   = 2000  # launch impulse toward center
const AIRBORNE_DURATION:   float   = 1.6     # seconds before landing
const LAUNCH_DAMP_FREE:    float   = 0.4     # seconds of zero-friction at launch only
const ZONE_COOLDOWN:       float   = 3.0     # zone recharge after firing
const CRUSH_RADIUS:        float   = 250.0   # px — landing crush detection radius
const CRUSH_IMPULSE:       float   = 3900.0  # impulse applied to crushed enemy
const CRUSH_RPM_PENALTY:   float   = 0.22    # fraction of max_angular_velocity drained
const SCALE_PEAK:          float   = 1.65    # bey visual scale at arc apex
const TRAIL_INTERVAL:      float   = 0.10    # seconds between mid-air trail puffs

const _SEWER_SPLASH = preload("res://scenes/effects/SewerSplash.tscn")

# ── State ──────────────────────────────────────────────────────────────────────
var _cooldown: float = 0.0

# ── Setup ──────────────────────────────────────────────────────────────────────
func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)


# ── Trigger ───────────────────────────────────────────────────────────────────
func _on_body_entered(body: Node2D) -> void:
	if _cooldown > 0.0:
		return
	if not body is RigidBody2D or not body.has_method("force_ko"):
		return
	if body.has_meta("airborne"):
		return  # already in the air from another geyser
	_cooldown = ZONE_COOLDOWN
	_launch(body as RigidBody2D)


func _launch(bey: RigidBody2D) -> void:
	# Direction: toward center with a small random tangential arc.
	var to_center: Vector2  = (ARENA_CENTER - bey.global_position).normalized()
	var perp: Vector2       = to_center.orthogonal() * randf_range(-0.18, 0.18)
	var launch_dir: Vector2 = (to_center + perp).normalized()

	# ── Ghost the bey: disable all physics collision while airborne ───────────
	# Stores originals in meta so _land() can restore them exactly.
	# collision_layer = 0 → no one detects us; collision_mask = 0 → we detect no one.
	# This prevents bey-vs-bey and bey-vs-wall collisions during flight entirely.
	bey.set_meta("orig_collision_layer", bey.collision_layer)
	bey.set_meta("orig_collision_mask",  bey.collision_mask)
	bey.collision_layer = 0
	bey.collision_mask  = 0

	# ── Physics launch ────────────────────────────────────────────────────────
	bey.linear_velocity = Vector2.ZERO
	bey.apply_central_impulse(launch_dir * GEYSER_LAUNCH)
	# Only suppress damp for the initial burst — after LAUNCH_DAMP_FREE seconds
	# normal friction resumes and the bey decelerates naturally before landing.
	if "_forced_damp_timer" in bey:
		bey._forced_damp_timer = LAUNCH_DAMP_FREE

	# Mark airborne — SpinController skips wall splat checks via this meta.
	bey.set_meta("airborne", true)
	bey.set_meta("geyser_height", 0.0)

	# ── Visual arc ────────────────────────────────────────────────────────────
	# Scale Ghoul_Base (visual child only) — never scale the RigidBody2D itself
	# or Godot recomputes collision bounds and the bey jumps in position.
	var ghoul := bey.get_node_or_null("Ghoul_Base")
	var half: float = AIRBORNE_DURATION * 0.5
	if ghoul:
		# Elevate above all arena content so the bey visually reads as "above" everything.
		bey.set_meta("orig_ghoul_z",          ghoul.z_index)
		bey.set_meta("orig_ghoul_z_relative", ghoul.z_as_relative)
		ghoul.z_index      = 300
		ghoul.z_as_relative = false

		# Scale arc: up to peak then back.
		var scale_tween := ghoul.create_tween()
		scale_tween.tween_method(
			func(v: float) -> void:
				if is_instance_valid(ghoul):
					ghoul.scale = Vector2(v, v)
					if is_instance_valid(bey):
						bey.set_meta("geyser_height", clampf((v - 1.0) / (SCALE_PEAK - 1.0), 0.0, 1.0)),
			1.0, SCALE_PEAK, half
		).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
		scale_tween.tween_method(
			func(v: float) -> void:
				if is_instance_valid(ghoul):
					ghoul.scale = Vector2(v, v)
					if is_instance_valid(bey):
						bey.set_meta("geyser_height", clampf((v - 1.0) / (SCALE_PEAK - 1.0), 0.0, 1.0)),
			SCALE_PEAK, 1.0, half
		).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)

		# Full spin rotation during flight for a clear "airborne tumble" look.
		var rot_tween := ghoul.create_tween()
		rot_tween.tween_property(ghoul, "rotation", ghoul.rotation + TAU, AIRBORNE_DURATION) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

	# ── Orange/red trail: recurring puffs for the full flight duration ────────
	var trail_steps: int = int(AIRBORNE_DURATION / TRAIL_INTERVAL)
	_trail_tick(bey, trail_steps)

	# ── Launch FX ─────────────────────────────────────────────────────────────
	_spawn_geyser_plume(bey.global_position)
	var arena := _get_arena()
	if arena and arena.has_method("shake_screen"):
		arena.shake_screen(20.0, 0.25)

	# ── Landing callback ───────────────────────────────────────────────────────
	get_tree().create_timer(AIRBORNE_DURATION).timeout.connect(
		func() -> void:
			if is_instance_valid(bey):
				_land(bey)
	)


func _land(bey: RigidBody2D) -> void:
	# ── Restore physics collision ──────────────────────────────────────────────
	if bey.has_meta("orig_collision_layer"):
		bey.collision_layer = bey.get_meta("orig_collision_layer")
		bey.remove_meta("orig_collision_layer")
	if bey.has_meta("orig_collision_mask"):
		bey.collision_mask = bey.get_meta("orig_collision_mask")
		bey.remove_meta("orig_collision_mask")

	# ── Clear airborne markers ─────────────────────────────────────────────────
	if bey.has_meta("airborne"):
		bey.remove_meta("airborne")
	if bey.has_meta("geyser_height"):
		bey.remove_meta("geyser_height")

	# ── Reset visual state ────────────────────────────────────────────────────
	var ghoul := bey.get_node_or_null("Ghoul_Base")
	if ghoul:
		ghoul.scale         = Vector2.ONE
		ghoul.rotation      = 0.0
		ghoul.modulate      = Color.WHITE
		ghoul.z_index       = bey.get_meta("orig_ghoul_z",          0)
		ghoul.z_as_relative = bey.get_meta("orig_ghoul_z_relative", true)
	if bey.has_meta("orig_ghoul_z"):          bey.remove_meta("orig_ghoul_z")
	if bey.has_meta("orig_ghoul_z_relative"): bey.remove_meta("orig_ghoul_z_relative")

	# ── Crush check — physics query so scene tree depth doesn't matter ────────
	var arena := _get_arena()
	var circle := CircleShape2D.new()
	circle.radius = CRUSH_RADIUS
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape          = circle
	params.transform      = Transform2D(0.0, bey.global_position)
	params.exclude        = [bey.get_rid()]
	params.collision_mask = bey.collision_layer  # match whatever layer beys live on
	var hits := get_world_2d().direct_space_state.intersect_shape(params, 4)
	for hit in hits:
		var collider = hit["collider"]
		if collider is RigidBody2D and collider.has_method("force_ko"):
			_trigger_crush(bey, collider as RigidBody2D)
			break  # one crush per landing

	# ── Landing FX ────────────────────────────────────────────────────────────
	_spawn_landing_splat(bey.global_position)
	if arena and arena.has_method("shake_screen"):
		arena.shake_screen(22.0, 0.30)


func _trigger_crush(attacker: RigidBody2D, victim: RigidBody2D) -> void:
	# Guard against near-zero direction (direct landing on top of enemy).
	var raw: Vector2 = victim.global_position - attacker.global_position
	var dir: Vector2 = raw.normalized() if raw.length_squared() > 4.0 \
		else Vector2.RIGHT.rotated(randf() * TAU)

	# Defer the velocity wipe + impulse by two physics frames.
	# The landing collision triggers crit/super_spark in LimbManager one frame later;
	# super_spark zeros velocity and would swallow the crush fling if we fired now.
	# Deferring guarantees crush impulse is the last word on velocity.
	get_tree().create_timer(0.07, true, false, true).timeout.connect(
		func() -> void:
			if not is_instance_valid(victim):
				return
			victim.linear_velocity = Vector2.ZERO
			victim.apply_central_impulse(dir * CRUSH_IMPULSE)
	)

	# RPM bleed on victim.
	if "angular_velocity" in victim and "max_angular_velocity" in victim:
		var bleed: float = victim.max_angular_velocity * CRUSH_RPM_PENALTY
		victim.angular_velocity = signf(victim.angular_velocity) \
			* maxf(abs(victim.angular_velocity) - bleed, 0.0)

	# Ghost trail on victim as they fly across the arena.
	var victim_ghoul: Node = victim.get_node_or_null("Ghoul_Base")
	if victim_ghoul and victim_ghoul.has_method("start_ghost_trail"):
		victim_ghoul.start_ghost_trail()

	# Slow-mo hit-stop — brief freeze to sell the impact.
	Events.set_slow_mo(0.08)
	var session := Events.current_session()
	get_tree().create_timer(0.45, true, false, true).timeout.connect(
		func() -> void:
			if Events.current_session() == session:
				Events.reset_time()
	)

	var arena := _get_arena()
	if arena and arena.has_method("shake_screen"):
		arena.shake_screen(32.0, 0.40)


# ── Particles ──────────────────────────────────────────────────────────────────
func _trail_tick(bey: RigidBody2D, remaining: int) -> void:
	if remaining <= 0 or not is_instance_valid(bey) or not bey.has_meta("airborne"):
		return
	_spawn_trail_puff(bey.global_position)
	get_tree().create_timer(TRAIL_INTERVAL).timeout.connect(
		func() -> void: _trail_tick(bey, remaining - 1)
	)


func _spawn_trail_puff(pos: Vector2) -> void:
	# Small orange-red ember puff that marks where the bey has just been.
	var p := CPUParticles2D.new()
	p.z_index              = 49
	p.z_as_relative        = false
	p.one_shot             = true
	p.lifetime             = 0.35
	p.amount               = 7
	p.explosiveness        = 0.90
	p.direction            = Vector2.ZERO
	p.spread               = 180.0
	p.gravity              = Vector2(0.0, 40.0)
	p.initial_velocity_min = 18.0
	p.initial_velocity_max = 55.0
	p.scale_amount_min     = 2.5
	p.scale_amount_max     = 6.0
	p.color                = Color(1.0, 0.38, 0.05, 0.88)  # orange-red ember
	get_tree().root.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(0.6).timeout.connect(
		func() -> void: if is_instance_valid(p): p.queue_free()
	)


func _spawn_geyser_plume(pos: Vector2) -> void:
	# Pressurised sewer steam: dirty green particles shooting upward.
	var p := CPUParticles2D.new()
	p.z_index              = 50
	p.z_as_relative        = false
	p.one_shot             = true
	p.lifetime             = 0.75
	p.amount               = 32
	p.explosiveness        = 0.95
	p.direction            = Vector2(0.0, -1.0)
	p.spread               = 40.0
	p.gravity              = Vector2(0.0, 90.0)
	p.initial_velocity_min = 140.0
	p.initial_velocity_max = 350.0
	p.scale_amount_min     = 3.0
	p.scale_amount_max     = 9.0
	p.color                = Color(0.12, 0.38, 0.08, 0.90)
	get_tree().root.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(
		func() -> void: if is_instance_valid(p): p.queue_free()
	)


func _spawn_landing_splat(pos: Vector2) -> void:
	# Heavy sludge crash: dark radial splatter + SewerSplash on top.
	var p := CPUParticles2D.new()
	p.z_index              = 50
	p.z_as_relative        = false
	p.one_shot             = true
	p.lifetime             = 0.55
	p.amount               = 24
	p.explosiveness        = 1.0
	p.direction            = Vector2.ZERO
	p.spread               = 180.0
	p.gravity              = Vector2.ZERO
	p.initial_velocity_min = 90.0
	p.initial_velocity_max = 260.0
	p.scale_amount_min     = 4.0
	p.scale_amount_max     = 11.0
	p.color                = Color(0.07, 0.24, 0.04, 0.88)
	get_tree().root.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(
		func() -> void: if is_instance_valid(p): p.queue_free()
	)

	var splash := _SEWER_SPLASH.instantiate()
	get_tree().root.add_child(splash)
	splash.global_position = pos


# ── Helpers ────────────────────────────────────────────────────────────────────
func _get_arena() -> Node:
	# Zone → Zones → SewerArena
	var parent := get_parent()
	return parent.get_parent() if parent else null
