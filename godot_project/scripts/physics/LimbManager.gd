extends Node2D

# -- Socket references --------------------------------------------------------
@onready var socket_left_arm:  Marker2D = $Socket_Left_Arm
@onready var socket_right_arm: Marker2D = $Socket_Right_Arm

# -- Part library -------------------------------------------------------------
const CHASSIS_POOL: Array[String] = [
	"res://resources/parts/chassis_bottle_cap.tres",
	"res://resources/parts/chassis_plastic_lid.tres",
	"res://resources/parts/chassis_rusty_manhole.tres",
	"res://resources/parts/chassis_cast_iron_lid.tres",
	"res://resources/parts/chassis_grease_trap.tres",
]
const LIMB_POOL: Array[String] = [
	"res://resources/parts/limb_lead_pipe.tres",
	"res://resources/parts/limb_fleshy_tongue.tres",
	"res://resources/parts/limb_ethereal_vapor.tres",
	"res://resources/parts/limb_twisted_wrench.tres",
	"res://resources/parts/limb_sewer_bone.tres",
	"res://resources/parts/limb_sewer_slapper.tres",
	"res://resources/parts/limb_sewer_harpoon.tres",
	"res://resources/parts/limb_sludge_sponge.tres",
]

# -- VFX scenes ---------------------------------------------------------------
const _SEWER_SPLASH = preload("res://scenes/effects/SewerSplash.tscn")

# -- Config -------------------------------------------------------------------
const LIMB_SIZE:               Vector2 = Vector2(28.0, 28.0)
const CENTRIFUGAL_VISUAL_SCALE: float  = 0.0000005

# -- Health bar ---------------------------------------------------------------
const RPM_BAR_SIZE:           Vector2 = Vector2(80.0, 8.0)
const RPM_BAR_OFFSET:         Vector2 = Vector2(-40.0, 58.0)  # below the base disc
const RPM_BAR_COLOR_HIGH:     Color   = Color(0.2, 0.9, 0.2, 1.0)
const RPM_BAR_COLOR_LOW:      Color   = Color(0.9, 0.1, 0.1, 1.0)

# -- Recovery burst -----------------------------------------------------------
const RECOVERY_BURST_TORQUE:   float  = 20000.0  # bonus torque applied after a limb strike
const RECOVERY_BURST_DURATION: float  = 0.35     # seconds the burst lasts

# -- Critical hit -------------------------------------------------------------
const CRIT_HIT_IMPULSE:      float = 2645.0  # impulse on enemy — truck hit
const CRIT_SELF_IMPULSE:     float =   50.0  # tiny knockback on attacker
const CRIT_SLOWMO_SCALE:     float =   0.02  # near-freeze hit-stop
const CRIT_SLOWMO_DURATION:  float =   0.24  # real seconds (timer ignores time_scale)
const DOM_IMPULSE:           float = 5000.0  # dominant-win fling impulse
const DOM_POWER_RATIO:       float =    1.2  # attacker power must exceed defender by this ratio
const SHIELD_DOT:            float =   0.707 # cos(45°) — within this dot = impact blocked by limb
const BLOCKED_IMPULSE:       float =  200.0  # push applied on a shielded (blocked) contact
const HEAVY_LIMB_THRESHOLD: float =    5.0  # limb mass above this triggers swing bonus
const SWING_HEAVY_MULT:     float =    1.5  # swing component multiplier for heavy attacker/limb
const LAUNCH_PUSH_RATIO:    float =    0.4  # weight of push-out component in launch blend
const LAUNCH_SWING_RATIO:   float =    0.6  # weight of swing component in launch blend
const SNAP_MASS_RATIO:      float =    2.0  # attacker/victim ratio that triggers linear_damp=0
const SNAP_DURATION:        float =    0.3  # seconds of zero damp after a snap launch
const SWING_TRAIL_DEGREES:  float =   60.0  # arc span of the motion trail

# -- Super Spark & Mass Bypass ------------------------------------------------
const SUPER_SPARK_THRESHOLD:    int   = 5       # consecutive deflections before climax blast
const SUPER_SPARK_FLING_FORCE:  float = 2500.0  # raw impulse per bey — must be violent
const LIMB_LOSS_CHANCE:         float =  0.10 # per-bey structural failure probability
const SMALL_LIMB_THRESHOLD:     float =  2.0  # limb mass below which mass bypass applies on crit
const MASS_BYPASS_FACTOR:       float =  0.50 # fraction of target mass resistance bypassed
const MASS_BYPASS_REFERENCE:    float =  8.0  # normalisation baseline for bypass calc

# -- Limb-vs-limb -------------------------------------------------------------
const LVL_WIN_IMPULSE:    float = 250.0  # impulse applied to the weaker limb's bey
const LVL_PENALTY_FACTOR: float =   0.6  # loser keeps 60% angular_velocity (−40% RPM)

# Set by SpinController after _ready() to override resource colours with team tint.
@export var team_color: Color = Color(0, 0, 0, 0)

var chassis:    ChassisData
var limb_left:  LimbData
var limb_right: LimbData

# Full limb mass used by SpinController for damage calc — NOT reduced.
var damage_mass: float = 0.0

var _limbs:     Array[Dictionary] = []
var _spin_body: RigidBody2D
var _base_sprite: ColorRect   # tinted by chassis colour

var _rpm_bar_pivot:    Node2D    = null  # Node2D so global_rotation is available
var _rpm_bar_bg:       ColorRect = null
var _rpm_bar_fill:     ColorRect = null
var _recovery_timer:   float     = 0.0
var _sparkle_timer:    float     = 0.0  # cooldown between peak-stability sparkle bursts
var _victory_mode:     bool      = false
var total_deflections: int = 0  # limb-vs-limb tally; resets after each Super Spark
var _victory_pulse_t:  float     = 0.0

# -----------------------------------------------------------------------------
func _ready() -> void:
	chassis    = load(CHASSIS_POOL[randi() % CHASSIS_POOL.size()])
	limb_left  = load(LIMB_POOL[randi() % LIMB_POOL.size()])
	limb_right = load(LIMB_POOL[randi() % LIMB_POOL.size()])

	# Tint the Base_Sprite (sibling inside BeybladeBase, two levels up from here).
	var beyblade := get_parent()
	if beyblade:
		_base_sprite = beyblade.get_node_or_null("Base_Sprite")
		if _base_sprite:
			_base_sprite.color = chassis.color

	# Resolve _spin_body BEFORE _plug_limb so ability.initialize() receives the correct reference.
	var p := get_parent()
	while p:
		if p is RigidBody2D:
			_spin_body = p as RigidBody2D
			break
		p = p.get_parent()

	_plug_limb(socket_left_arm,  limb_left)
	_plug_limb(socket_right_arm, limb_right)

	if _spin_body:
		_apply_mass()
		_build_rpm_bar()

	# Apply team colour if already set before _ready() ran.
	if team_color.a > 0.0:
		_tint_to_team()

# Sets mass on the RigidBody2D using 10% of limb mass so spin stays healthy.
# Full limb mass is stored in damage_mass for use in collision penalty.
func _apply_mass() -> void:
	if not _spin_body:
		return
	var left_phys:  float = limb_left.mass  * 0.1
	var right_phys: float = limb_right.mass * 0.1
	_spin_body.mass = chassis.mass + left_phys + right_phys
	damage_mass     = chassis.mass + limb_left.mass + limb_right.mass

	# Centre-of-mass: weighted average of socket positions (10% limb weight).
	var limb_weight_sum: float = left_phys + right_phys
	var weighted: Vector2 = (
		socket_left_arm.position  * left_phys +
		socket_right_arm.position * right_phys
	) / limb_weight_sum
	_spin_body.center_of_mass_mode = RigidBody2D.CENTER_OF_MASS_MODE_CUSTOM
	_spin_body.center_of_mass      = weighted

# Spawns a ColorRect centred on the socket, an Area2D hitbox, and registers for jiggle.
func _plug_limb(socket: Marker2D, data: LimbData) -> void:
	# Visual: stretch the rect along the outward axis by length_multiplier.
	var limb_len: float   = LIMB_SIZE.x * data.length_multiplier
	var outward_dir       := socket.position.normalized()
	var rect              := ColorRect.new()
	rect.size             = Vector2(limb_len, LIMB_SIZE.y)
	# Top-left corner: start at socket origin, extend outward.
	# minf(outward_dir.x, 0) is 0 for rightward sockets, -1 for leftward.
	rect.position = Vector2(minf(outward_dir.x, 0.0) * limb_len, -LIMB_SIZE.y * 0.5)
	rect.color    = data.color
	socket.add_child(rect)

	# Hitbox — tip circle, on layer 4 so limbs can detect each other via area_entered.
	# collision_mask 5 = layer 1 (bey chassis) | layer 4 (other limb areas).
	var area             := Area2D.new()
	area.collision_layer  = 4
	area.collision_mask   = 5
	area.monitoring       = true
	area.monitorable      = true
	area.position         = outward_dir * limb_len
	area.set_meta("limb_mass", data.mass)          # readable by opposing limb in _on_limb_vs_limb
	area.set_meta("length_mult", data.length_multiplier)  # used for Limb Leverage power bonus
	area.set_meta("crit_impulse_bonus", data.crit_impulse_bonus)  # Twisted Wrench passive
	var cshape            := CollisionShape2D.new()
	var circle            := CircleShape2D.new()
	circle.radius         = LIMB_SIZE.x * 0.5 * clampf(data.length_multiplier, 0.75, 2.0)
	cshape.shape          = circle
	area.add_child(cshape)
	socket.add_child(area)
	var total_reach: float = socket.position.length() + limb_len

	if data.ability_scene:
		var ability: LimbAbility = data.ability_scene.instantiate() as LimbAbility
		socket.add_child(ability)
		ability.initialize(_spin_body, socket, rect, area, self)
		if ability.passthrough_hits:
			# Ability augments normal behavior — keep the area active and connect hits.
			area.body_entered.connect(_on_limb_hit.bind(data.mass, area, total_reach))
			area.area_entered.connect(_on_limb_vs_limb.bind(data.mass, area))
		else:
			# Ability fully owns its own detection, so stop it self-detecting (monitoring=false).
			# Keep monitorable=true so ENEMY limb areas can still detect and score deflections
			# against this limb — without this, Slapper/Harpoon contacts give zero deflections.
			area.monitoring  = false
			area.monitorable = true
	else:
		area.body_entered.connect(_on_limb_hit.bind(data.mass, area, total_reach))
		area.area_entered.connect(_on_limb_vs_limb.bind(data.mass, area))

	_limbs.append({
		"rect":   rect,
		"socket": socket,
		"phase":  randf() * TAU,
		"wobble": data.wobble_intensity,
		"length": data.length_multiplier,
	})

# Hot-swaps the chassis and both limbs on an already-initialised Ghoul.
# Frees existing socket children, re-plugs with the new data, and re-applies mass.
# Called by SewerArena after RunManager emits run_started.
func apply_loadout(new_chassis: ChassisData, new_limb_l: LimbData, new_limb_r: LimbData) -> void:
	for socket in [socket_left_arm, socket_right_arm]:
		for child in socket.get_children():
			if child is LimbAbility:
				child.on_teardown()
			child.free()
	_limbs.clear()

	chassis    = new_chassis
	limb_left  = new_limb_l
	limb_right = new_limb_r

	if _base_sprite:
		_base_sprite.color = chassis.color

	_plug_limb(socket_left_arm,  limb_left)
	_plug_limb(socket_right_arm, limb_right)
	_apply_mass()

	if team_color.a > 0.0:
		_tint_to_team()


# Called by SpinController to tint all limbs after the tree is ready.
func set_team_color(color: Color) -> void:
	team_color = color
	_tint_to_team()

func _tint_to_team() -> void:
	if _base_sprite:
		_base_sprite.color = team_color.darkened(0.2)
	var shades: Array[Color] = [
		team_color,
		team_color.lightened(0.3),
	]
	for i in _limbs.size():
		(_limbs[i]["rect"] as ColorRect).color = shades[i % shades.size()]

# -----------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not _spin_body:
		return

	_recovery_timer = maxf(_recovery_timer - delta, 0.0)

	var omega: float = _spin_body.angular_velocity
	var t:     float = Time.get_ticks_msec() / 1000.0

	for entry in _limbs:
		var rect:    ColorRect = entry["rect"]
		var socket:  Marker2D  = entry["socket"]
		var phase:   float     = entry["phase"]
		var wobble_i: float    = entry["wobble"]

		var outward := socket.position.normalized()
		var radius  := socket.position.length()

		# F = m * ω² * r  →  pixel offset
		var centrifugal_force:  float   = LIMB_SIZE.x * (omega * omega) * radius
		var centrifugal_offset: Vector2 = (outward * centrifugal_force * CENTRIFUGAL_VISUAL_SCALE).limit_length(30.0)

		var perp:   Vector2 = Vector2(-outward.y, outward.x)
		var wobble: Vector2 = perp * sin(t * 10.0 + phase) * clampf(abs(omega) * wobble_i * 0.05, 0.0, 12.0)

		# Center on socket first, then apply clamped offset.
		var center_on_socket: Vector2 = -LIMB_SIZE / 2.0
		var offset: Vector2 = (centrifugal_offset + wobble).limit_length(15.0)
		rect.position = center_on_socket + offset

	_update_rpm_bar(omega)

	# Victory lap: pulse gold and skip normal stability visuals.
	if _victory_mode:
		_victory_pulse_t += delta
		var pulse := (sin(_victory_pulse_t * 5.0) * 0.5 + 0.5)
		var gold_color := Color(1.0, 0.85, 0.0, 1.0).lerp(Color.WHITE, pulse * 0.35)
		if _base_sprite:
			_base_sprite.color = gold_color
		for entry in _limbs:
			(entry["rect"] as ColorRect).color = gold_color
		self.position = Vector2.ZERO
		self.scale    = Vector2.ONE
		if _base_sprite:
			_base_sprite.scale = Vector2.ONE
		return

	# Visual instability: shake the ghoul when RPM is low; sparkle when at peak.
	var trpm_vis: float = (_spin_body.target_rpm if "target_rpm" in _spin_body else 150.0)
	var rpm_ratio: float = clampf(abs(omega) / trpm_vis, 0.0, 1.0)
	if rpm_ratio < 0.5:
		var shake: float = (0.5 - rpm_ratio) * 8.0
		self.position = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
	else:
		self.position = Vector2.ZERO

	# ── Death precession: elliptical scale wobble below 25% RPM ──────────────
	# death_t runs 0→1 as RPM drops from 25% to zero.
	# The wobble speeds up and widens as the bey loses control — simulates
	# a spinning disc tilting into a final precession before it falls over.
	if rpm_ratio < 0.25:
		var death_t := 1.0 - (rpm_ratio / 0.25)
		var w_speed := 8.0  + death_t * 14.0   # oscillation accelerates
		var w_amp   := 0.04 + death_t * 0.26   # amplitude widens toward death
		var w       := sin(t * w_speed) * w_amp
		var wobble_scale := Vector2(1.0 + w, 1.0 - absf(w) * 0.5)
		self.scale = wobble_scale
		if _base_sprite:
			_base_sprite.scale = wobble_scale
	else:
		self.scale = Vector2.ONE
		if _base_sprite:
			_base_sprite.scale = Vector2.ONE

	_sparkle_timer = maxf(_sparkle_timer - delta, 0.0)
	if rpm_ratio >= 0.95 and _sparkle_timer <= 0.0:
		_sparkle_timer = 1.0
		_spawn_stability_sparkle(_spin_body.global_position)

# Called by MutationStation — randomises every limb colour.
func mutate_color() -> void:
	for entry in _limbs:
		(entry["rect"] as ColorRect).color = Color(randf(), randf(), randf(), 1.0)

# Public helper for other systems.
func get_limb_centrifugal_force(socket: Marker2D) -> float:
	if not _spin_body:
		return 0.0
	var data: LimbData = limb_left if socket == socket_left_arm else limb_right
	var omega  := _spin_body.angular_velocity
	var radius := socket.position.length()
	return data.mass * (omega * omega) * radius

# -----------------------------------------------------------------------------
# Creates two stacked ColorRects (background + fill) parented to the RigidBody2D
# so the bar hovers below the base disc in world space and rotates with it.
func _build_rpm_bar() -> void:
	if not _spin_body:
		return

	# Node2D pivot — has global_rotation; ColorRects go inside it.
	_rpm_bar_pivot         = Node2D.new()
	_rpm_bar_pivot.z_index = 100

	_rpm_bar_bg          = ColorRect.new()
	_rpm_bar_bg.size     = RPM_BAR_SIZE
	_rpm_bar_bg.position = Vector2(-RPM_BAR_SIZE.x * 0.5, -RPM_BAR_SIZE.y * 0.5)
	_rpm_bar_bg.color    = Color(0.08, 0.08, 0.08, 0.85)

	_rpm_bar_fill          = ColorRect.new()
	_rpm_bar_fill.size     = RPM_BAR_SIZE
	_rpm_bar_fill.position = Vector2.ZERO
	_rpm_bar_fill.color    = RPM_BAR_COLOR_HIGH

	_rpm_bar_bg.add_child(_rpm_bar_fill)
	_rpm_bar_pivot.add_child(_rpm_bar_bg)

	# Deferred so we're safely outside any ongoing _ready() call stack.
	_spin_body.add_child.call_deferred(_rpm_bar_pivot)

# Updates bar width and colour each visual frame based on current angular_velocity.
func _update_rpm_bar(omega: float) -> void:
	if not _rpm_bar_fill or not _rpm_bar_pivot.is_inside_tree():
		return

	# Undo parent spin: pin the pivot to a fixed world-space position below the bey.
	_rpm_bar_pivot.global_rotation = 0.0
	_rpm_bar_pivot.global_position = _spin_body.global_position + Vector2(0.0, 52.0)

	var eq_rpm: float = (float(_spin_body.get("equilibrium_rpm")) if "equilibrium_rpm" in _spin_body else 48.0)
	# Hardcoded 0.40 ceiling: actual combat RPM sits at ~35-40% of equilibrium_rpm,
	# so scaling the denominator down by 60% maps that range to ~87-100% on the bar.
	# TODO: replace with a proper combat-equilibrium formula once RPM physics are finalised.
	var ratio: float = clampf(abs(omega) / maxf(eq_rpm * 0.40, 1.0), 0.0, 1.0)
	_rpm_bar_fill.size.x = RPM_BAR_SIZE.x * ratio
	_rpm_bar_fill.color  = Color.GREEN.lerp(Color.RED, 1.0 - ratio)

# Applies a short torque burst during the physics step when recovery is active.
func _physics_process(_delta: float) -> void:
	if _recovery_timer > 0.0 and _spin_body:
		# Boost in the direction of current spin so we don't flip the rotation.
		var burst_dir: float = signf(_spin_body.angular_velocity)
		_spin_body.apply_torque(burst_dir * RECOVERY_BURST_TORQUE)

# Engages Events.set_slow_mo hit-stop; real-time timer restores via Events.reset_time().
# Skipped if a heavier slow-mo is already active (session ownership check in the callback).
func _trigger_hit_slow() -> void:
	if Engine.time_scale <= CRIT_SLOWMO_SCALE + 0.01:
		return   # Super Spark sequence owns time_scale right now; don't touch it.
	Events.set_slow_mo(CRIT_SLOWMO_SCALE)
	var session := Events.current_session()
	get_tree().create_timer(CRIT_SLOWMO_DURATION, true, false, true).timeout.connect(
		func() -> void:
			if Events.current_session() == session:
				Events.reset_time()
	)

# Public hit-stop for external callers (e.g. BeyAI Croco Lunge).
# Uses real-time timer so duration is in wall-clock seconds.
# Skipped if a heavier slow-mo is already active.
func trigger_hit_stop(duration: float) -> void:
	const HIT_STOP_SCALE: float = 0.05
	if Engine.time_scale <= HIT_STOP_SCALE + 0.01:
		return
	Events.set_slow_mo(HIT_STOP_SCALE)
	var session := Events.current_session()
	get_tree().create_timer(duration, true, false, true).timeout.connect(
		func() -> void:
			if Events.current_session() == session:
				Events.reset_time()
	)


# Called when one of our limb hitboxes (Area2D) body-enters an enemy chassis.
# limb_mass, area, total_reach bound via .bind() in _plug_limb.
func _on_limb_hit(body: Node2D, limb_mass: float, area: Area2D, total_reach: float) -> void:
	if not body is RigidBody2D or not body.has_method("force_ko") or body == _spin_body:
		return
	# Airborne beys are ghosts — no limb hits until they land.
	if _spin_body.has_meta("airborne") or body.has_meta("airborne"):
		return
	# Machine-gun guard: if a cooldown is active, this is a duplicate contact — skip it.
	if _spin_body and _spin_body._hit_cooldown > 0.0:
		return

	var enemy       := body as RigidBody2D
	var direction   := (enemy.global_position - _spin_body.global_position).normalized()
	var enemy_ghoul := enemy.get_node_or_null("Ghoul_Base")
	# -- Shield check: is the impact angle within 45° of an enemy limb socket? ----------
	var impact_dir := (area.global_position - enemy.global_position).normalized()
	var is_blocked := false
	if enemy_ghoul:
		for sock_name in ["Socket_Left_Arm", "Socket_Right_Arm"]:
			var sock := enemy_ghoul.get_node_or_null(sock_name) as Marker2D
			if sock:
				var sock_dir := (sock.global_position - enemy.global_position).normalized()
				if impact_dir.dot(sock_dir) > SHIELD_DOT:
					is_blocked = true
					break

	if is_blocked:
		_enemy_impulse(enemy, direction * BLOCKED_IMPULSE)
	else:
		# --- Tangential launch (bat effect) -----------------------------------------
		var r_vec: Vector2     = (area.global_position - _spin_body.global_position).normalized()
		# ±15° random bias on the tangential vector prevents predictable circular orbits.
		var raw_swing: Vector2 = signf(_spin_body.angular_velocity) * Vector2(-r_vec.y, r_vec.x)
		var swing_dir: Vector2 = raw_swing.rotated(randf_range(-deg_to_rad(15.0), deg_to_rad(15.0)))
		var swing_mult: float  = SWING_HEAVY_MULT if (
			(chassis and chassis.mass > 8.0) or limb_mass > HEAVY_LIMB_THRESHOLD
		) else 1.0
		var launch_dir: Vector2 = (
			direction * LAUNCH_PUSH_RATIO + swing_dir * swing_mult * LAUNCH_SWING_RATIO
		).normalized()

		# --- Winner-Takes-All power score -------------------------------------------
		# power = damage_mass × |ω| × reach; defender reach approximated at 75px avg.
		# Limb Leverage: long or heavy limbs get a static 1.25× punch bonus.
		var length_mult_val: float = area.get_meta("length_mult", 1.0)
		var leverage_mult:   float = 1.25 if (limb_mass > 5.0 or length_mult_val > 1.2) else 1.0
		var enemy_dmg_mass:  float = (enemy_ghoul.damage_mass
			if enemy_ghoul and "damage_mass" in enemy_ghoul else enemy.mass)
		var attacker_power: float = damage_mass * abs(_spin_body.angular_velocity) * total_reach * leverage_mult
		var defender_power: float = enemy_dmg_mass * abs(enemy.angular_velocity) * 75.0
		var is_dominant:    bool  = attacker_power > defender_power * DOM_POWER_RATIO

		if is_dominant:
			# Full velocity zero — maximum snap readability.
			enemy.linear_velocity = Vector2.ZERO
			# Wall magnetism: blend launch_dir outward from arena center so hits reach the wall.
			var wall_dir: Vector2 = (enemy.global_position - Vector2(576.0, 324.0)).normalized()
			launch_dir = (launch_dir + wall_dir * 0.5).normalized()
			_enemy_impulse(enemy, launch_dir * DOM_IMPULSE)
			# Attacker refunds 10% RPM, suffers zero knockback.
			var max_av: float = (_spin_body.max_angular_velocity
				if "max_angular_velocity" in _spin_body else 150.0)
			var cur: float = _spin_body.angular_velocity
			_spin_body.angular_velocity = minf(abs(cur) * 1.1, max_av) * signf(cur)
			# Loser: debris trail in the flight direction.
			_spawn_debris_particles(enemy.global_position, launch_dir)
			# Victim flies free — skip gyro damp for 0.4 s so nothing brakes the fling.
			enemy.linear_damp = 0.0
			enemy._forced_damp_timer = 0.6
			# Ghost trail on the victim as they fly toward the wall.
			if enemy_ghoul and enemy_ghoul.has_method("start_ghost_trail"):
				enemy_ghoul.start_ghost_trail()
		else:
			# Normal crit: partial velocity wipe, standard impulse, small self-nudge.
			# Mass-floor: heavier enemies need a minimum push so small beys can still move them.
			enemy.linear_velocity *= 0.2
			var crit_bonus: float   = area.get_meta("crit_impulse_bonus", 0.0)
			var crit_impulse: float = maxf(CRIT_HIT_IMPULSE, enemy.mass * 180.0) * (1.0 + crit_bonus)
			_enemy_impulse(enemy, launch_dir * crit_impulse)
			_spin_body.apply_central_impulse(-launch_dir * CRIT_SELF_IMPULSE)
			# Mass snap for heavy attackers.
			if _spin_body.mass > enemy.mass * SNAP_MASS_RATIO:
				var orig_damp: float = enemy.linear_damp
				enemy.linear_damp    = 0.0
				var enemy_ref: WeakRef = weakref(enemy)
				get_tree().create_timer(SNAP_DURATION).timeout.connect(
					func() -> void:
						var e: RigidBody2D = enemy_ref.get_ref() as RigidBody2D
						if e:
							e.linear_damp = orig_damp
				)

		# Small-limb mass bypass: a precise crit from a light limb punches through tank mass.
		if not is_dominant and limb_mass < SMALL_LIMB_THRESHOLD:
			var bypass_impulse: float = CRIT_HIT_IMPULSE \
				* (enemy.mass / MASS_BYPASS_REFERENCE) * MASS_BYPASS_FACTOR
			_enemy_impulse(enemy, launch_dir * bypass_impulse)

		# Shared FX for all unblocked hits.
		var tip_offset: Vector2 = area.global_position - _spin_body.global_position
		_spawn_swing_trail(
			_spin_body.global_position, tip_offset.length(),
			tip_offset.angle(), signf(_spin_body.angular_velocity)
		)
		_spawn_crit_particles(enemy.global_position)
		_flash_attacker()
		_pulse_winner_scale()
		var arena := _spin_body.get_parent()
		if arena and arena.has_method("shake_screen"):
			arena.shake_screen(15.0, 0.2)
		print("CRITICAL!" if not is_dominant else "DOMINANT!")
		if _spin_body.has_meta("croco_lunge_pending"):
			_spin_body.remove_meta("croco_lunge_pending")
			trigger_hit_stop(0.1)
		else:
			_trigger_hit_slow()
		# Lock out repeat hits for half a second — prevents machine-gun multi-fire.
		_spin_body._hit_cooldown = 0.5

	_recovery_timer = RECOVERY_BURST_DURATION

# Called when one of our limb areas overlaps another limb area (area_entered).
# own_limb_mass is bound via .bind() in _plug_limb.
#
# area_entered fires once on EACH bey for the same contact, so this function
# runs twice per clash.  To avoid doubling impulses:
#   • Winner's pass  → launches both beys (tangential swing + recoil).
#   • Loser's pass   → RPM penalty only; no extra impulse.
func _on_limb_vs_limb(other_area: Area2D, own_limb_mass: float, own_area: Area2D) -> void:
	if not other_area.has_meta("limb_mass"):
		return

	var n: Node = other_area.get_parent()
	while n and not (n is RigidBody2D):
		n = n.get_parent()
	if not n or n == _spin_body:
		return

	var enemy_body: RigidBody2D = n as RigidBody2D
	# Airborne beys are ghosts — no limb clashes until they land.
	if _spin_body.has_meta("airborne") or enemy_body.has_meta("airborne"):
		return
	var enemy_limb_mass: float       = other_area.get_meta("limb_mass")
	var own_strength:    float       = own_limb_mass   * abs(_spin_body.angular_velocity)
	var enemy_strength:  float       = enemy_limb_mass * abs(enemy_body.angular_velocity)

	var contact_pt: Vector2 = (own_area.global_position + other_area.global_position) * 0.5
	_spawn_spark_particles(contact_pt)

	if own_strength >= enemy_strength:
		# ── Winner's pass: compute realistic fling directions ─────────────────
		# Our limb tip is moving tangentially to our spin at the contact point.
		# That swing direction is the primary force we impart on the enemy (bat effect).
		var to_contact: Vector2 = (contact_pt - _spin_body.global_position).normalized()
		var swing_dir:  Vector2 = Vector2(-to_contact.y, to_contact.x) \
								  * signf(_spin_body.angular_velocity)

		# Secondary: beys push apart along the centre-to-centre axis.
		var apart: Vector2 = (enemy_body.global_position - _spin_body.global_position).normalized()

		# Enemy launches in a blend of swing + push-apart, with a small random bias
		# to keep outcomes varied without feeling arbitrary.
		var enemy_launch: Vector2 = (swing_dir * 0.6 + apart * 0.4).normalized() \
									.rotated(randf_range(-0.28, 0.28))

		# Winner recoils mildly backwards (Newton's 3rd law), with its own spread.
		var own_recoil: Vector2 = (-apart).rotated(randf_range(-0.4, 0.4))

		# Scale by how dominant the win is: lopsided clashes fling the loser harder.
		var win_ratio: float = clampf(own_strength / (own_strength + enemy_strength), 0.5, 1.0)

		# Combined RPM multiplier: high-speed collisions cause explosive separation.
		# Reference is equilibrium_rpm (the natural combat speed) × 2, so beys fighting
		# at normal speed always produce a full-strength fling (2.0×).
		# Using max_angular_velocity here made flings weak (36+36 = 26% of 120×2 = 0.8×).
		var combined_rpm:   float = abs(_spin_body.angular_velocity) + abs(enemy_body.angular_velocity)
		var eq_ref:         float = (float(_spin_body.get("equilibrium_rpm")) \
			if "equilibrium_rpm" in _spin_body else 48.0)
		var max_combined:   float = eq_ref * 2.0
		var rpm_fling_mult: float = lerpf(0.7, 2.0, clampf(combined_rpm / max_combined, 0.0, 1.0))

		enemy_body.apply_central_impulse(enemy_launch * LVL_WIN_IMPULSE * win_ratio * rpm_fling_mult)
		_spin_body.apply_central_impulse(own_recoil   * LVL_WIN_IMPULSE * (1.0 - win_ratio) * 0.5 * rpm_fling_mult)

		# Deflection total — climax fires every SUPER_SPARK_THRESHOLD parries; counter resets.
		total_deflections += 1
		if total_deflections >= SUPER_SPARK_THRESHOLD:
			total_deflections = 0
			_trigger_super_spark(enemy_body, own_area, other_area)
	else:
		# ── Loser's pass: absorb RPM loss. Impulse already handled above. ─────
		_spin_body.angular_velocity *= LVL_PENALTY_FACTOR

# -----------------------------------------------------------------------------
# Briefly scales the Ghoul_Base (self) to 1.2× to show dominance, then snaps back.
func _pulse_winner_scale() -> void:
	scale = Vector2(1.2, 1.2)
	get_tree().create_timer(0.15, true, false, true).timeout.connect(
		func() -> void:
			if is_instance_valid(self):
				scale = Vector2.ONE
	)

# Spawns a cone of debris particles on the loser flying in their launch direction.
func _spawn_debris_particles(pos: Vector2, dir: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.z_index              = 100
	p.one_shot             = true
	p.lifetime             = 0.6
	p.amount               = 24
	p.explosiveness        = 0.85
	p.direction            = dir
	p.spread               = 40.0
	p.gravity              = Vector2.ZERO
	p.initial_velocity_min = 120.0
	p.initial_velocity_max = 300.0
	p.color                = Color(0.65, 0.55, 0.4, 1.0)
	get_tree().root.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(0.8).timeout.connect(func() -> void: p.queue_free())

# Draws a white arc showing the swing path that landed the crit, fades in 0.3s.
func _spawn_swing_trail(center: Vector2, radius: float, tip_angle: float, spin_sign: float) -> void:
	var trail := Line2D.new()
	trail.width          = 5.0
	trail.default_color  = Color(1.0, 1.0, 1.0, 0.85)
	trail.z_index        = 90
	trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	trail.end_cap_mode   = Line2D.LINE_CAP_ROUND

	var arc_span: float = deg_to_rad(SWING_TRAIL_DEGREES)
	for i in 14:
		var t: float     = float(i) / 13.0
		# Sweep from 60° behind the tip to the tip itself.
		var angle: float = tip_angle - spin_sign * arc_span * (1.0 - t)
		trail.add_point(center + Vector2(cos(angle), sin(angle)) * radius)

	get_tree().root.add_child(trail)
	var tween := trail.create_tween()
	tween.tween_property(trail, "modulate:a", 0.0, 0.3)
	tween.tween_callback(trail.queue_free)

# Spawns a burst of golden-yellow star particles on the victim at a crit.
func _spawn_crit_particles(pos: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.z_index              = 100
	p.one_shot             = true
	p.lifetime             = 0.5
	p.amount               = 16
	p.explosiveness        = 1.0
	p.spread               = 180.0
	p.gravity              = Vector2.ZERO
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 180.0
	p.color                = Color(1.0, 0.9, 0.05, 1.0)
	get_tree().root.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(0.8).timeout.connect(func() -> void: p.queue_free())

# Spawns a small burst of grey spark particles at a limb-on-limb contact point.
func _spawn_spark_particles(pos: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.z_index              = 100
	p.one_shot             = true
	p.lifetime             = 0.2
	p.amount               = 8
	p.explosiveness        = 1.0
	p.spread               = 180.0
	p.gravity              = Vector2.ZERO
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 100.0
	p.color                = Color(0.72, 0.72, 0.72, 1.0)
	get_tree().root.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(0.4).timeout.connect(func() -> void: p.queue_free())

# Called by SpinController.start_victory_lap() — enables pulsing gold visuals.
func _start_victory_flash() -> void:
	_victory_mode = true

# Wrapper: scales an impulse by the enemy's current stability modifier before applying it.
# This means low-RPM beys receive more knockback from every hit.
func _enemy_impulse(enemy: RigidBody2D, impulse: Vector2) -> void:
	var mod: float = enemy.get_stability_modifier() if enemy.has_method("get_stability_modifier") else 1.0
	enemy.apply_central_impulse(impulse * mod)

# Small yellow-white sparkle burst to show a bey is at peak stability.
func _spawn_stability_sparkle(pos: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.z_index              = 90
	p.one_shot             = true
	p.lifetime             = 0.6
	p.amount               = 8
	p.explosiveness        = 0.8
	p.spread               = 180.0
	p.gravity              = Vector2.ZERO
	p.initial_velocity_min = 20.0
	p.initial_velocity_max = 60.0
	p.color                = Color(0.9, 1.0, 0.5, 0.8)
	get_tree().root.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(0.8).timeout.connect(func() -> void: p.queue_free())

# Spawns 8 fading white ghost copies of the Ghoul_Base over 0.4 s as the victim flies.
func start_ghost_trail() -> void:
	var trail_count: int   = 8
	var interval:    float = 0.05  # seconds between each ghost snapshot
	for i in trail_count:
		get_tree().create_timer(interval * i, true, false, true).timeout.connect(
			func() -> void:
				if not is_instance_valid(self):
					return
				var ghost := ColorRect.new()
				ghost.size     = Vector2(90.0, 90.0)
				ghost.position = Vector2(-45.0, -45.0)
				ghost.color    = Color(1.0, 1.0, 1.0, 0.55)
				ghost.z_index  = 80
				get_tree().root.add_child(ghost)
				ghost.global_position = global_position + Vector2(-45.0, -45.0)
				var tw := ghost.create_tween()
				tw.tween_property(ghost, "modulate:a", 0.0, 0.25)
				tw.tween_callback(ghost.queue_free)
		)

# Flashes all attacker visuals pure white for 0.1s, then restores original colours.
func _flash_attacker() -> void:
	if _base_sprite:
		_base_sprite.color = Color.WHITE
	for entry in _limbs:
		(entry["rect"] as ColorRect).color = Color.WHITE
	get_tree().create_timer(0.1, true, false, true).timeout.connect(func() -> void:
		if not is_instance_valid(self):
			return
		if team_color.a > 0.0:
			_tint_to_team()
		else:
			if _base_sprite and chassis:
				_base_sprite.color = chassis.color
			var limb_data := [limb_left, limb_right]
			for i in _limbs.size():
				(_limbs[i]["rect"] as ColorRect).color = (limb_data[i] as LimbData).color
	)


# ── Structural failure ────────────────────────────────────────────────────────

# Replaces one limb with the broken nub mid-fight.
# slot: 0 = left arm, 1 = right arm.
func break_limb(slot: int) -> void:
	if not ResourceLoader.exists(RunManager.BROKEN_NUB_PATH):
		return
	var nub: LimbData = load(RunManager.BROKEN_NUB_PATH) as LimbData
	if not nub:
		return

	var socket: Marker2D = socket_left_arm if slot == 0 else socket_right_arm
	for child in socket.get_children():
		if child is LimbAbility:
			child.on_teardown()
		child.queue_free()

	# Remove stale _limbs entry for this socket.
	for i in _limbs.size():
		if _limbs[i]["socket"] == socket:
			_limbs.remove_at(i)
			break

	if slot == 0:
		limb_left  = nub
	else:
		limb_right = nub

	_plug_limb(socket, nub)
	_apply_mass()


# Replaces the first Broken Nub slot with the given limb resource path.
# Returns true if a broken slot was found and replaced, false otherwise.
# Called by MutationStation when a bey rolls through the zone.
func try_replace_broken_limb(new_limb_path: String) -> bool:
	var broken_path: String = RunManager.BROKEN_NUB_PATH
	var slot: int = -1
	if limb_left.resource_path == broken_path:
		slot = 0
	elif limb_right.resource_path == broken_path:
		slot = 1
	if slot == -1:
		return false

	if not ResourceLoader.exists(new_limb_path):
		return false
	var new_limb: LimbData = load(new_limb_path) as LimbData
	if not new_limb:
		return false

	var socket: Marker2D = socket_left_arm if slot == 0 else socket_right_arm
	for child in socket.get_children():
		if child is LimbAbility:
			child.on_teardown()
		child.queue_free()
	for i in _limbs.size():
		if _limbs[i]["socket"] == socket:
			_limbs.remove_at(i)
			break

	if slot == 0:
		limb_left  = new_limb
	else:
		limb_right = new_limb
	_plug_limb(socket, new_limb)
	_apply_mass()
	return true


# ── Super Spark ───────────────────────────────────────────────────────────────

# Fires when consecutive_deflections hits SUPER_SPARK_THRESHOLD.
# Blasts both beys violently apart, emits Events.super_spark, shakes the screen,
# and independently rolls a 20% structural-failure chance for each bey.
func _trigger_super_spark(enemy_body: RigidBody2D, own_area: Area2D, other_area: Area2D) -> void:
	var contact_pt: Vector2 = (own_area.global_position + other_area.global_position) * 0.5

	# ── Violent fling ─────────────────────────────────────────────────────────
	var blast_dir: Vector2 = Vector2.UP.rotated(randf() * TAU)
	var anti_dir:  Vector2 = Vector2.UP.rotated(randf() * TAU)

	_spin_body.linear_velocity    = Vector2.ZERO
	enemy_body.linear_velocity    = Vector2.ZERO
	_spin_body.linear_damp        = 0.0
	enemy_body.linear_damp        = 0.0
	_spin_body._forced_damp_timer = 1.5
	enemy_body._forced_damp_timer = 1.5

	_spin_body.apply_central_impulse(blast_dir * SUPER_SPARK_FLING_FORCE * 3.0)
	enemy_body.apply_central_impulse(anti_dir  * SUPER_SPARK_FLING_FORCE * 3.0)

	# ── Particles + event ─────────────────────────────────────────────────────
	_spawn_super_spark_particles(contact_pt)
	_spawn_sewer_splash(contact_pt)          # oily black splash on top of gold burst
	Events.super_spark.emit(contact_pt)

	var arena: Node = _spin_body.get_parent()

	# ── Short screen shake — must complete BEFORE slow-mo begins ──────────────
	# 0.18 game-seconds runs out naturally at normal speed; slow-mo won't stretch
	# it because we set time_scale after this call.
	if arena and arena.has_method("shake_screen"):
		arena.shake_screen(45.0, 0.18)

	# ── Slow motion — ALWAYS fires, not gated by limb loss ────────────────────
	# Real-time timer restores after exactly 1.0 wall-clock second.
	Events.set_slow_mo(0.1)
	var _ss_session := Events.current_session()
	get_tree().create_timer(1.0, true, false, true).timeout.connect(
		func() -> void:
			if Events.current_session() == _ss_session:
				Events.reset_time()
	)

	# ── Camera zoom toward contact point — ALWAYS fires ───────────────────────
	# At time_scale 0.1, game-time tweens run 10× slower in real time.
	# 0.05 game-s per step → 0.5 real-s per step → 1.0 real-s round-trip.
	var camera: Camera2D = arena.get_node_or_null("Camera2D") as Camera2D if arena else null
	if camera:
		# Kill any in-progress Croco zoom tween before starting Super Spark zoom.
		# Without this, two tweens compete on camera.zoom and the camera gets stuck.
		var old_tween: Tween = arena.get("_zoom_tween") as Tween
		if is_instance_valid(old_tween):
			old_tween.kill()
		var orig_zoom: Vector2 = (arena.get_base_zoom() if arena.has_method("get_base_zoom") else camera.zoom)
		camera.zoom   = orig_zoom
		camera.offset = Vector2.ZERO
		var orig_offset: Vector2 = Vector2.ZERO
		var toward_contact: Vector2 = (contact_pt - Vector2(576.0, 324.0)) * 0.2
		var zoom_tween := camera.create_tween()
		# Register tween so force_camera_reset() can kill it unconditionally.
		arena.set("_zoom_tween", zoom_tween)
		zoom_tween.tween_property(camera, "zoom",   orig_zoom * 1.25, 0.05)
		zoom_tween.parallel().tween_property(camera, "offset", toward_contact, 0.05)
		zoom_tween.tween_property(camera, "zoom",   orig_zoom,        0.05)
		zoom_tween.parallel().tween_property(camera, "offset", orig_offset,    0.05)
		# force_camera_reset() is called by the slow-mo restore timer above.

	# ── Structural failure (20% per bey, independent rolls) ───────────────────
	var enemy_ghoul: Node = enemy_body.get_node_or_null("Ghoul_Base")

	if randf() < LIMB_LOSS_CHANCE:
		_trigger_limb_loss(self)
	if randf() < LIMB_LOSS_CHANCE:
		if enemy_ghoul and enemy_ghoul.has_method("_trigger_limb_loss"):
			enemy_ghoul._trigger_limb_loss(enemy_ghoul)
		elif enemy_ghoul and enemy_ghoul.has_method("break_limb"):
			enemy_ghoul.break_limb(randi() % 2)


# ── Limb Loss Drama ───────────────────────────────────────────────────────────

# Breaks a random limb and flashes the victim red ↔ white.
# Slow-mo and zoom are handled by _trigger_super_spark so they always fire.
# Flash uses game-time Tween: at time_scale 0.1, each 0.0125 game-s = 0.125 real-s.
func _trigger_limb_loss(victim_ghoul: Node) -> void:
	if victim_ghoul and victim_ghoul.has_method("break_limb"):
		victim_ghoul.break_limb(randi() % 2)

	# ── Highlight flash ───────────────────────────────────────────────────────
	var victim_2d := victim_ghoul as Node2D
	if victim_2d and is_instance_valid(victim_2d):
		var flash_tween := victim_2d.create_tween()
		for _i in 4:
			flash_tween.tween_property(victim_2d, "modulate", Color(1.0, 0.05, 0.05, 1.0), 0.0125)
			flash_tween.tween_property(victim_2d, "modulate", Color.WHITE, 0.0125)
		get_tree().create_timer(1.05, true, false, true).timeout.connect(
			func() -> void:
				flash_tween.kill()
				if is_instance_valid(victim_2d):
					victim_2d.modulate = Color.WHITE
		)




# Instances SewerSplash.tscn at a world position — brown/black oil droplet burst.
func _spawn_sewer_splash(pos: Vector2) -> void:
	var s: CPUParticles2D = _SEWER_SPLASH.instantiate()
	get_tree().root.add_child(s)
	s.global_position = pos



# Larger gold-orange particle burst — visually distinct from normal crit sparks.
func _spawn_super_spark_particles(pos: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.z_index              = 110
	p.one_shot             = true
	p.lifetime             = 0.9
	p.amount               = 60
	p.explosiveness        = 1.0
	p.spread               = 180.0
	p.gravity              = Vector2.ZERO
	p.initial_velocity_min = 150.0
	p.initial_velocity_max = 420.0
	p.color                = Color(1.0, 0.6, 0.05, 1.0)
	get_tree().root.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(func() -> void: p.queue_free())
