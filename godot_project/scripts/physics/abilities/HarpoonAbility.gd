class_name HarpoonAbility extends LimbAbility

## Sewer Harpoon — Leap and Link (v2: Sub-Chassis Smart Targeting)
##
## The physical limb is a NORMAL limb (passthrough_hits = true).
## It deflects, crits, and sparks exactly like any other limb between fires.
##
## When the ability timer fires, a ghost projectile (no physics body) launches
## from the bey's CENTER toward the nearest enemy chassis. On contact a tether
## forms, pulling both beys toward each other for 3 seconds. Full tether → climax.

# ── Constants ──────────────────────────────────────────────────────────────────
const HARPOON_INTERVAL:        float = 6.0
const HARPOON_TRAVEL_SPEED:    float = 1200.0  # px/s for the ghost projectile
const HARPOON_MAX_TRAVEL:      float = 650.0   # auto-miss beyond this distance
const HARPOON_CATCH_RADIUS:    float = 40.0    # proximity to enemy center that locks the hook
const HARPOON_TETHER_DURATION: float = 4.0
const HARPOON_PULL_FORCE:      float = 3800   # mutual attraction force per physics step
const HARPOON_MAX_DIST:        float = 900.0   # chain snaps if beys exceed this distance
const HARPOON_SNAP_IMPULSE:    float = 2800  # final closing impulse on both beys at climax
const HARPOON_LIMB_LOSS_CHANCE: float = 0.20

const CHAIN_COLOR: Color = Color(0.38, 0.30, 0.20, 1.0)  # dark rusty brown
const CHAIN_WIDTH: float = 3.5
const PROJ_COLOR:  Color = Color(0.60, 0.45, 0.25, 1.0)  # rusty hook tip
const PROJ_SIZE:   float = 8.0

# ── State ──────────────────────────────────────────────────────────────────────
enum State { IDLE, TRAVELING, TETHERED }

var _state:        State       = State.IDLE
var _timer:        float       = 0.0
var _tether_timer: float       = 0.0
var _target_enemy: RigidBody2D = null

# Ghost projectile — no physics body, tracked in world space.
var _proj_pos:    Vector2  = Vector2.ZERO
var _proj_dir:    Vector2  = Vector2.ZERO
var _proj_origin: Vector2  = Vector2.ZERO  # used to measure total travel distance

# Visuals.
var _chain_line:  Line2D    = null
var _proj_visual: ColorRect = null

# ── Init / Teardown ────────────────────────────────────────────────────────────
func initialize(spin_body: RigidBody2D, socket: Marker2D,
				rect: ColorRect, area: Area2D, manager: Node2D) -> void:
	passthrough_hits = true  # limb acts as normal in combat; ability only manages the projectile
	super.initialize(spin_body, socket, rect, area, manager)
	_timer = LimbAbility.jitter_cooldown(HARPOON_INTERVAL * _cooldown_mult())
	# area monitoring stays true — LimbManager connects signals because passthrough_hits = true.
	if not Events.match_ended.is_connected(_on_match_ended):
		Events.match_ended.connect(_on_match_ended)


func _on_match_ended(_winner: String) -> void:
	on_teardown()


func on_teardown() -> void:
	_state        = State.IDLE
	_target_enemy = null
	_destroy_chain()
	_destroy_proj()

# ── Per-frame (visual + state logic) ──────────────────────────────────────────
func _process(delta: float) -> void:
	match _state:

		State.IDLE:
			_timer -= delta
			if _timer <= 0.0:
				_try_fire()

		State.TRAVELING:
			_proj_pos += _proj_dir * HARPOON_TRAVEL_SPEED * delta
			_update_proj_visual()
			_update_chain_to_proj()

			if not is_instance_valid(_target_enemy):
				_reset_idle()
				return
			# Caught?
			if _proj_pos.distance_to(_target_enemy.global_position) <= HARPOON_CATCH_RADIUS:
				_catch()
				return
			# Overshot / missed?
			if _proj_pos.distance_to(_proj_origin) > HARPOON_MAX_TRAVEL:
				_reset_idle()

		State.TETHERED:
			_tether_timer -= delta
			_update_chain_to_enemy()
			# Snap conditions: enemy freed, or beys drifted too far apart.
			if not is_instance_valid(_target_enemy) \
					or _spin_body.global_position.distance_to(_target_enemy.global_position) > HARPOON_MAX_DIST:
				_snap_fail()
				return
			if _tether_timer <= 0.0:
				_climax()


func _physics_process(_delta: float) -> void:
	if _state == State.TETHERED and is_instance_valid(_target_enemy):
		_apply_mutual_pull()

# ── Firing ─────────────────────────────────────────────────────────────────────
func _try_fire() -> void:
	var enemy := _find_nearest_enemy()
	if not enemy:
		_timer = HARPOON_INTERVAL * _cooldown_mult()  # no target yet, try again next interval
		return
	_target_enemy = enemy
	_proj_pos     = _spin_body.global_position
	_proj_origin  = _proj_pos
	_proj_dir     = (_target_enemy.global_position - _proj_pos).normalized()
	_state        = State.TRAVELING
	_create_chain()
	_create_proj()


func _find_nearest_enemy() -> RigidBody2D:
	var arena := _spin_body.get_parent()
	if not arena:
		return null
	var nearest: RigidBody2D = null
	var min_dist: float      = INF
	for child in arena.get_children():
		if child is RigidBody2D and child != _spin_body and child.has_method("force_ko"):
			var d: float = child.global_position.distance_to(_spin_body.global_position)
			if d < min_dist:
				min_dist = d
				nearest  = child as RigidBody2D
	return nearest

# ── Catch ─────────────────────────────────────────────────────────────────────
func _catch() -> void:
	_state        = State.TETHERED
	_tether_timer = HARPOON_TETHER_DURATION
	_destroy_proj()           # hook is "embedded" — no separate tip visual during tether
	# Chain line stays and transitions to bey-center ↔ bey-center in _update_chain_to_enemy.

# ── Tether physics ─────────────────────────────────────────────────────────────
func _apply_mutual_pull() -> void:
	# Both beys attracted toward each other — symmetric force, prevents infinite energy.
	var to_enemy: Vector2 = (_target_enemy.global_position - _spin_body.global_position).normalized()
	_spin_body.apply_central_force(to_enemy  * HARPOON_PULL_FORCE)
	_target_enemy.apply_central_force(-to_enemy * HARPOON_PULL_FORCE)

# ── Chain visual ───────────────────────────────────────────────────────────────
func _create_chain() -> void:
	_destroy_chain()
	_chain_line                = Line2D.new()
	_chain_line.width          = CHAIN_WIDTH
	_chain_line.default_color  = CHAIN_COLOR
	_chain_line.z_index        = 150
	_chain_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_chain_line.end_cap_mode   = Line2D.LINE_CAP_ROUND
	_chain_line.add_point(Vector2.ZERO)
	_chain_line.add_point(Vector2.ZERO)
	get_tree().root.add_child(_chain_line)


func _update_chain_to_proj() -> void:
	if is_instance_valid(_chain_line):
		_chain_line.set_point_position(0, _spin_body.global_position)
		_chain_line.set_point_position(1, _proj_pos)


func _update_chain_to_enemy() -> void:
	if is_instance_valid(_chain_line) and is_instance_valid(_target_enemy):
		_chain_line.set_point_position(0, _spin_body.global_position)
		_chain_line.set_point_position(1, _target_enemy.global_position)


func _destroy_chain() -> void:
	if is_instance_valid(_chain_line):
		_chain_line.queue_free()
	_chain_line = null

# ── Projectile visual ──────────────────────────────────────────────────────────
func _create_proj() -> void:
	_destroy_proj()
	_proj_visual         = ColorRect.new()
	_proj_visual.size    = Vector2(PROJ_SIZE, PROJ_SIZE)
	_proj_visual.color   = PROJ_COLOR
	_proj_visual.z_index = 200
	get_tree().root.add_child(_proj_visual)


func _update_proj_visual() -> void:
	if is_instance_valid(_proj_visual):
		_proj_visual.global_position = _proj_pos - Vector2(PROJ_SIZE * 0.5, PROJ_SIZE * 0.5)


func _destroy_proj() -> void:
	if is_instance_valid(_proj_visual):
		_proj_visual.queue_free()
	_proj_visual = null

# ── Resolution ────────────────────────────────────────────────────────────────
func _snap_fail() -> void:
	# Chain broke early — small splash at the break point.
	if is_instance_valid(_target_enemy):
		var snap_pt: Vector2 = (_spin_body.global_position + _target_enemy.global_position) * 0.5
		_manager._spawn_sewer_splash(snap_pt)
	_reset_idle()


func _climax() -> void:
	var enemy: RigidBody2D = _target_enemy
	_reset_idle()  # clear visuals and state before spawning VFX

	if not is_instance_valid(enemy):
		return

	# Snappy closing pull — both beys yanked toward each other at full physics speed.
	var to_enemy: Vector2 = (enemy.global_position - _spin_body.global_position).normalized()
	_spin_body.apply_central_impulse(to_enemy  * HARPOON_SNAP_IMPULSE)
	enemy.apply_central_impulse(-to_enemy      * HARPOON_SNAP_IMPULSE)

	var mid_pt:    Vector2    = (_spin_body.global_position + enemy.global_position) * 0.5
	var enemy_ref: WeakRef    = weakref(enemy)
	var arena:     Node       = _spin_body.get_parent()

	# Delay VFX + slow-mo so the impulse gets ~3 full-speed frames to play out first.
	get_tree().create_timer(0.12, true, false, true).timeout.connect(func() -> void:
		_manager._spawn_super_spark_particles(mid_pt)
		_manager._spawn_sewer_splash(mid_pt)
		_manager._flash_attacker()
		Events.super_spark.emit(mid_pt)
		if arena and arena.has_method("shake_screen"):
			arena.shake_screen(35.0, 0.18)
		Events.set_slow_mo(0.1)
		var session := Events.current_session()
		get_tree().create_timer(1.0, true, false, true).timeout.connect(
			func() -> void:
				if Events.current_session() == session:
					Events.reset_time()
		)
		# 20% limb loss on enemy only — player is the one who hooked them.
		if randf() < HARPOON_LIMB_LOSS_CHANCE:
			var e: RigidBody2D = enemy_ref.get_ref() as RigidBody2D
			if e:
				var enemy_ghoul: Node = e.get_node_or_null("Ghoul_Base")
				if enemy_ghoul and enemy_ghoul.has_method("break_limb"):
					enemy_ghoul.break_limb(randi() % 2)
	)


func _reset_idle() -> void:
	_state        = State.IDLE
	_timer        = HARPOON_INTERVAL * _cooldown_mult()
	_target_enemy = null
	_destroy_chain()
	_destroy_proj()
