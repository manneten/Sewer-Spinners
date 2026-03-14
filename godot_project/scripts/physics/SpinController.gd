extends RigidBody2D

signal knocked_out(beyblade: RigidBody2D)

@export var max_angular_velocity: float = 120.0
@export var team_color: Color           = Color(0, 0, 0, 0)
@export var chassis: ChassisData        = null   # set at runtime from LimbManager

const WOBBLE_INTERVAL:        float   = 0.5
const WOBBLE_FORCE:           float   = 60.0
const BASE_COLLISION_IMPULSE: float   = 313.0
const KO_THRESHOLD:           float   = 2.0    # rad/s — below this = danger zone
const KO_GRACE_TIME:          float   = 2.0    # must stay below threshold this long to die
const IMPACT_INVULN_TIME:     float   = 0.1    # seconds between penalty hits
const MAX_PENALTY_RATIO:      float   = 0.40   # single hit caps at 40% of max_angular_velocity
const TORQUE_MULTIPLIER:      float   = 14.0   # +20% torque to compensate for long-limb drag
const ARENA_CENTER:           Vector2 = Vector2(576.0, 324.0)
const CENTER_PULL_FORCE:      float   = 2000.0  # constant force drawing beys to the middle
const GRIND_DISTANCE:         float   = 105.0  # px center-to-center; ≈15px edge gap for 45px-radius bodies
const GRIND_TIME:             float   =   0.4  # seconds of continuous proximity before pulse fires
const GRIND_PULSE:            float   = 500.0  # impulse that breaks the friction lock
const MIN_BOUNCE_IMPULSE:     float   = 150.0  # floor so beys never just lean on each other
const WALL_SPLAT_SPEED:       float   = 1200.0  # linear speed threshold for a wall-splat event
const SOFT_START_DURATION:    float   =    1.0  # seconds of soft-start window at match begin
const SOFT_START_SPEED_CAP:   float   =  500.0  # max velocity allowed through a wall-splat in soft-start
const COLLISION_DISABLE_TIME: float   =    0.5  # collision disabled at spawn to prevent overlap explosions
const HIGH_RPM_WOBBLE_MULT:   float   =    5.0  # exponential base for death-wobble scaling at max RPM
const DEATH_WOBBLE_THRESHOLD: float   =   0.85  # RPM ratio above which centrifugal strain kicks in
const MAX_RPM_RECOIL_RATIO:   float   =    0.35 # fraction of hit impulse reflected back onto attacker at max RPM
const COMBO_MAX:              int     =    10    # ceiling for the consecutive-crit streak
const COMBO_BONUS_PER:        float   =    0.15  # +15 % impulse multiplier per combo tier
const COMBO_LABEL_OFFSET:     Vector2 = Vector2(0.0, -80.0)  # world-space offset above bey centre

var bey_name:  String     = ""   # set by GambleScreen from brainrot_names.txt
var is_active: bool       = true
var _wobble_timer: float  = 0.0
var _impact_timer: float  = 0.0  # counts up; penalty blocked while < IMPACT_INVULN_TIME
var _ko_timer:    float   = 0.0  # counts up while below KO_THRESHOLD; resets when above
var _damage_mass: float        = 0.0   # full limb mass used for penalty; set from LimbManager
var _grind_bodies: Dictionary  = {}    # body → accumulated proximity time
var _hit_cooldown: float       = 0.0   # blocks repeated limb hits from the same contact
var _forced_damp_timer: float  = 0.0   # when > 0, skip gyro linear_damp so victim flies freely
var _torque_mult: float        = 1.0   # stamina bonus for heavy setups (currently unused)
var _mass_accel_scale: float   = 1.0   # diminishing returns: heavy builds spin up slower
var target_rpm: float          = 0.0   # equilibrium RPM; stability modifier calculated against this
var _match_timer: float        = 0.0   # seconds since match start; used for soft-start window
var _base_angular_damp: float  = 0.02  # captured after _ready() finishes; drag formula builds on this
var combo_count:    int        = 0     # consecutive limb-on-chassis crits; resets on being crit'd
var _combo_pivot:          Node2D        = null  # counter-rotated each frame so the label stays upright
var _combo_label:          Label         = null
var _combo_label_settings: LabelSettings = null

func _ready() -> void:
	gravity_scale         = 0.0
	contact_monitor       = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	angular_velocity = 48.0
	position += Vector2(randf_range(-10.0, 10.0), randf_range(-10.0, 10.0))

	# Let LimbManager._ready() run first (it's a child), then read its chassis.
	await get_tree().process_frame
	var ghoul := get_node_or_null("Ghoul_Base")
	if ghoul and ghoul.has_method("set_team_color") and team_color.a > 0.0:
		ghoul.set_team_color(team_color)
	if ghoul and "chassis" in ghoul:
		chassis = ghoul.chassis
	if ghoul and "damage_mass" in ghoul:
		_damage_mass = ghoul.damage_mass

	# Heavy chassis toughness: near-zero angular_damp so spin bleeds extremely slowly.
	if chassis and chassis.mass > 8.0:
		angular_damp = 0.005

	# ── Diminishing returns on mass ───────────────────────────────────────────
	# Lights spin faster but cap lower (glass cannon).
	# Heavies get a top-speed penalty and a spin-up penalty — they can't simply
	# sit in the centre and grind; they need momentum to win exchanges.
	if self.mass < 2.5:
		max_angular_velocity *= 0.85          # ultra-light only (Worm Queen tier)
	elif self.mass > 10.0:
		# Top-speed shrinks linearly beyond 10 kg: −1.575 % per kg above threshold (−10% from original).
		# At 14 kg: −6.3 %  |  At 20 kg: −15.75 %  |  Hard floor: −31.5 %.
		var rpm_penalty: float = clampf((self.mass - 10.0) * 0.01575, 0.0, 0.315)
		max_angular_velocity *= (1.0 - rpm_penalty)

	# Spin-up rate: halved at 16 kg, floored at 30 % for extreme heavies.
	# Formula: 8 / max(mass, 8) — at 8 kg → 1.0, at 16 kg → 0.5, at 24 kg → 0.33.
	_mass_accel_scale = clampf(8.0 / maxf(self.mass, 8.0), 0.30, 1.0)

	# Ultra-lights bleed spin slightly faster — stamina disadvantage.
	if self.mass < 2.5:
		angular_damp = 1.05

	# Lock in the equilibrium RPM now that all scaling is done.
	target_rpm = max_angular_velocity
	# Capture the final angular_damp so the variable-drag formula has a stable baseline.
	_base_angular_damp = angular_damp

	# RPM-reactive rim arcs — four white curved stripes that brighten with spin.
	var arcs := preload("res://scripts/effects/BeySpeedArcs.gd").new()
	add_child(arcs)

	# Combo counter label — floats above the bey, counter-rotated each frame.
	_build_combo_label()

	# Safety delay: disable collision for the first 0.5 s so spawn-overlap can't fling beys.
	var cshape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cshape:
		cshape.disabled = true
		get_tree().create_timer(COLLISION_DISABLE_TIME).timeout.connect(
			func() -> void: if is_instance_valid(cshape): cshape.disabled = false
		)

func _physics_process(delta: float) -> void:
	if not is_active:
		return

	# Spin recovery: direct velocity step toward target_rpm.
	# Rate is scaled by _mass_accel_scale so heavy builds recover spin more slowly.
	# A 16 kg bey takes ~6 s to recover vs ~3 s for an 8 kg bey.
	if target_rpm > 0.0 and abs(angular_velocity) < target_rpm:
		var spin_sign: float = signf(angular_velocity) if abs(angular_velocity) > 0.5 else 1.0
		angular_velocity = move_toward(
			angular_velocity,
			target_rpm * spin_sign,
			(target_rpm / 3.0) * _mass_accel_scale * delta
		)

	# RPM-based traction loss: high RPM = slippery (low damp), low RPM = sticky (high damp).
	# A centre-locked spinner at full speed can be knocked across the arena;
	# a dying bey hugs the floor and resists being flung.
	# Skipped while _forced_damp_timer is active so a dominant fling doesn't get braked.
	var spin_ratio: float = clampf(abs(angular_velocity) / max_angular_velocity, 0.0, 1.0)
	if _forced_damp_timer > 0.0:
		_forced_damp_timer -= delta
	else:
		linear_damp = lerpf(1.8, 0.15, spin_ratio)

	# Variable drag: angular_damp increases non-linearly with RPM.
	# Formula: base_damp + (rpm * 0.001)^2  — super-high speeds bleed spin faster,
	# making them harder to sustain and giving heavy/slow builds a stamina edge.
	var rpm_drag: float = abs(angular_velocity) * 0.001
	angular_damp = _base_angular_damp + rpm_drag * rpm_drag

	# Advance timers.
	_hit_cooldown  = maxf(_hit_cooldown  - delta, 0.0)
	_impact_timer += delta
	_wobble_timer += delta
	_match_timer  += delta

	# Periodic lurch — low-frequency random jolt to keep all beys slightly unpredictable.
	if _wobble_timer >= WOBBLE_INTERVAL:
		_wobble_timer = 0.0
		var wobble := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized() \
					  * WOBBLE_FORCE
		apply_central_force(wobble)

	# Death wobble — continuous per-frame twitching above DEATH_WOBBLE_THRESHOLD (85% RPM).
	# Scales EXPONENTIALLY so a bey at 100% visibly shivers and veers on any contact.
	# Formula: WOBBLE_FORCE × 0.15 × HIGH_RPM_WOBBLE_MULT ^ instability
	#   85% RPM → ×1.0 (≈9 units/frame)   100% RPM → ×5.0 (≈45 units/frame @ 120 Hz)
	if spin_ratio > DEATH_WOBBLE_THRESHOLD:
		var instability: float  = clampf(
			(spin_ratio - DEATH_WOBBLE_THRESHOLD) / (1.0 - DEATH_WOBBLE_THRESHOLD), 0.0, 1.0
		)
		var twitch_force: float = WOBBLE_FORCE * 0.15 * pow(HIGH_RPM_WOBBLE_MULT, instability)
		var twitch := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized() \
					  * twitch_force
		apply_central_force(twitch)

	# Center pull — draws beys toward the arena middle so they clash.
	_apply_center_pull()

	# K.O. check — must stay below threshold for KO_GRACE_TIME before dying.
	if abs(angular_velocity) < KO_THRESHOLD:
		_ko_timer += delta
		if _ko_timer >= KO_GRACE_TIME:
			force_ko()
	else:
		_ko_timer = 0.0

	# Anti-grind: accumulate time for each body we're pressed against.
	# If we stay within GRIND_DISTANCE for GRIND_TIME, pop apart with an impulse.
	var stale: Array = []
	for body in _grind_bodies:
		if not is_instance_valid(body):
			stale.append(body)
			continue
		if global_position.distance_to(body.global_position) > GRIND_DISTANCE:
			_grind_bodies[body] = 0.0  # separated — reset timer
			continue
		_grind_bodies[body] += delta
		if _grind_bodies[body] >= GRIND_TIME:
			_grind_bodies[body] = 0.0
			var away: Vector2 = (global_position - (body as Node2D).global_position).normalized()
			apply_central_impulse(away * GRIND_PULSE)
	for body in stale:
		_grind_bodies.erase(body)

# Constant force toward the arena center — ensures beys clash rather than drift apart.
func _apply_center_pull() -> void:
	var to_center: Vector2 = ARENA_CENTER - global_position
	if to_center.length_squared() < 1.0:
		return
	# Light beys get up to 30% less centre pull — fast/light builds must fight to hold centre.
	# Clamped at 0.70 floor so even featherweights still feel the bowl gravity.
	var mass_pull_scale: float = clampf(self.mass / 8.0, 0.70, 1.0)
	apply_central_force(to_center.normalized() * CENTER_PULL_FORCE * mass_pull_scale)

# Called by external systems (e.g. Abyss) to trigger K.O. immediately.
func force_ko() -> void:
	if not is_active:
		return
	is_active = false
	knocked_out.emit(self)

# RPM-scaled collision bounce + impact penalty.
# Higher mass / higher RPM wins the exchange; lighter / slower body loses more spin.
func _on_body_entered(body: Node2D) -> void:
	# Wall splat: high-speed contact with an arena wall segment.
	if body is StaticBody2D:
		_check_wall_splat(body as StaticBody2D)
		return
	# Only react to other Beyblade chassis — ignore zones and limb bodies.
	if not body is RigidBody2D or not body.has_method("force_ko"):
		return
	var rb := body as RigidBody2D

	# Outward impulse scaled by own RPM, with a minimum floor so beys always separate.
	# Also multiplied by own stability modifier: low-RPM beys get thrown further.
	var direction   := (global_position - body.global_position).normalized()
	var spin_ratio: float = clampf(abs(angular_velocity) / max_angular_velocity, 0.0, 1.0)
	var base_impulse: float = maxf(BASE_COLLISION_IMPULSE * (1.3 + spin_ratio * 0.7), MIN_BOUNCE_IMPULSE)

	# Mass-ratio fling: a heavier bey sends the lighter target farther.
	# sqrt keeps scaling sane — 4× mass ratio → 2× fling (not 4×).
	var mass_ratio: float = clampf(self.mass / maxf(rb.mass, 0.5), 0.5, 4.0)
	var impulse: float = base_impulse * sqrt(mass_ratio)
	apply_central_impulse(direction * impulse * get_stability_modifier())

	# Heavy-bey recoil: when mass is lopsided, the heavier bey gets pushed back.
	# Prevents a tank from sitting motionless in the centre and grinding lighter beys.
	# Scales linearly with how much heavier self is; capped so it stays readable.
	var recoil_ratio: float = clampf((self.mass / maxf(rb.mass, 0.5)) - 1.0, 0.0, 1.5)
	if recoil_ratio > 0.0:
		apply_central_impulse(-direction * BASE_COLLISION_IMPULSE * recoil_ratio * 0.28)

	# High-speed recoil: at max RPM the hit energy partially kicks back onto the attacker.
	# Risks sending a fast spinner into the Drain or a wall, making speed a two-edged sword.
	if spin_ratio > 0.9:
		var rpm_recoil: float = clampf((spin_ratio - 0.9) / 0.1, 0.0, 1.0)
		apply_central_impulse(-direction * impulse * MAX_RPM_RECOIL_RATIO * rpm_recoil)

	# Register for anti-grind tracking.
	if not _grind_bodies.has(rb):
		_grind_bodies[rb] = 0.0

	# Impact penalty — gated by invulnerability window.
	if _impact_timer < IMPACT_INVULN_TIME:
		return
	_impact_timer = 0.0

	var impact_force: float = (linear_velocity - rb.linear_velocity).length()
	# Use full damage_mass (not reduced physics mass) so Lead Pipe still hits hard.
	var effective_mass: float = _damage_mass if _damage_mass > 0.0 else mass
	var penalty: float = clampf(
		log(1.0 + (impact_force / (effective_mass + 0.1))) * 2.0,
		0.0,
		max_angular_velocity * MAX_PENALTY_RATIO
	)
	# Heavy chassis shrugs off 20% of every impact penalty.
	var refund: float = penalty * 0.2 if (chassis and chassis.mass > 8.0) else 0.0
	angular_velocity = maxf(angular_velocity - penalty + refund, 0.0)

func _on_body_exited(body: Node2D) -> void:
	_grind_bodies.erase(body)

# ── Combo counter ─────────────────────────────────────────────────────────────

# Increments the streak by one, capped at COMBO_MAX.
# Called by LimbManager when one of our limbs lands a clean chassis hit.
func increment_combo() -> void:
	combo_count = mini(combo_count + 1, COMBO_MAX)

# Resets the streak to zero.
# Called by LimbManager on the ENEMY when our limb hits their chassis.
func reset_combo() -> void:
	combo_count = 0

# Returns the impulse multiplier for the current streak.
# 0 hits → 1.00×   1 hit → 1.05×   10 hits → 1.50×
func get_combo_multiplier() -> float:
	return 1.0 + combo_count * COMBO_BONUS_PER

# Builds a Node2D pivot (counter-rotated each frame) containing a background rect
# and a Label showing the current streak as "Nx".
func _build_combo_label() -> void:
	_combo_pivot         = Node2D.new()
	_combo_pivot.z_index = 120
	_combo_pivot.visible = false

	# Fully transparent background — the outline handles readability against any surface.
	_combo_label                      = Label.new()
	_combo_label.size                 = Vector2(80.0, 42.0)
	_combo_label.position             = Vector2(-40.0, -21.0)
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combo_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER

	_combo_label_settings              = LabelSettings.new()
	_combo_label_settings.font         = load("res://assets/fonts/Demon Panic.otf")
	_combo_label_settings.font_size    = 32
	_combo_label_settings.font_color   = Color(1.0, 0.50, 0.06, 1.0)  # bright rust orange
	_combo_label_settings.outline_size  = 4
	_combo_label_settings.outline_color = Color(0.06, 0.03, 0.01, 1.0)  # near-black
	_combo_label.label_settings = _combo_label_settings

	_combo_pivot.add_child(_combo_label)
	add_child.call_deferred(_combo_pivot)

# Keeps the combo label pinned above the bey in world-space and upright.
func _process(_delta: float) -> void:
	if not is_instance_valid(_combo_pivot) or not _combo_pivot.is_inside_tree():
		return
	# Pin to world position so the label doesn't orbit as the RigidBody2D rotates.
	_combo_pivot.global_position = global_position + COMBO_LABEL_OFFSET
	_combo_pivot.global_rotation = 0.0

	var show: bool = (combo_count > 0 and is_active)
	_combo_pivot.visible = show
	if show and _combo_label:
		_combo_label.text = "%dx" % combo_count
		# Colour shifts from bright rust toward deep red as the streak climbs.
		if _combo_label_settings:
			var heat: float = clampf(float(combo_count) / float(COMBO_MAX), 0.0, 1.0)
			_combo_label_settings.font_color = \
				Color(1.0, 0.55, 0.08, 1.0).lerp(Color(1.0, 0.18, 0.03, 1.0), heat)

# stability_modifier: at full RPM = 1.0 (normal knockback); at 0 RPM = 2.0 (double knockback).
# Clamped to [1.0, 3.0] as a safety cap.
func get_stability_modifier() -> float:
	if target_rpm <= 0.0:
		return 1.0
	var ratio: float = clampf(abs(angular_velocity) / target_rpm, 0.0, 1.0)
	return clampf(2.0 - ratio, 1.0, 3.0)

# Called by SewerArena when this bey wins — doubles speed cap and flashes gold.
func start_victory_lap() -> void:
	max_angular_velocity *= 2.0
	target_rpm            = max_angular_velocity
	var ghoul := get_node_or_null("Ghoul_Base")
	if ghoul and ghoul.has_method("_start_victory_flash"):
		ghoul._start_victory_flash()

# F = m * ω² * r
func get_centrifugal_force(mass_kg: float, radius_px: float) -> float:
	return mass_kg * (angular_velocity * angular_velocity) * radius_px

# Checks if this body just slammed a wall at high speed; applies RPM penalty + FX.
# Also notifies the wall segment so it can lose integrity.
func _check_wall_splat(wall: StaticBody2D) -> void:
	# Airborne beys fly over walls — no splat damage while launched by Geyser.
	if has_meta("airborne"):
		return
	if linear_velocity.length() < WALL_SPLAT_SPEED:
		return

	# Soft-start window: clamp velocity instead of applying full penalty or wall damage.
	if _match_timer < SOFT_START_DURATION:
		if linear_velocity.length() > SOFT_START_SPEED_CAP:
			linear_velocity = linear_velocity.normalized() * SOFT_START_SPEED_CAP
		return

	# 20% immediate RPM penalty + 50% velocity bleed — concrete absorbs energy.
	angular_velocity  *= 0.8
	linear_velocity   *= 0.5
	# Heavy screen shake.
	var arena := get_parent()
	if arena and arena.has_method("shake_screen"):
		arena.shake_screen(25.0, 0.35)
	# Dust cloud roughly at the wall contact point.
	_spawn_wall_dust(global_position + linear_velocity.normalized() * 45.0)
	# Tell the wall segment it took a hit — triggers integrity loss + chunk FX.
	if wall.has_method("take_hit"):
		wall.take_hit()

# Spawns a burst of concrete-dust CPUParticles2D at the given world position.
func _spawn_wall_dust(pos: Vector2) -> void:
	var dust_dir: Vector2 = -linear_velocity.normalized()
	var p := CPUParticles2D.new()
	p.z_index              = 100
	p.one_shot             = true
	p.lifetime             = 0.5
	p.amount               = 20
	p.explosiveness        = 0.9
	p.direction            = dust_dir
	p.spread               = 50.0
	p.gravity              = Vector2.ZERO
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 200.0
	p.color                = Color(0.75, 0.72, 0.65, 1.0)
	get_tree().root.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(0.8).timeout.connect(func() -> void: p.queue_free())
