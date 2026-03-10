extends Node2D

## Three visual layers beneath the Beyblade:
##   1. Dark oval shadow  — anchors the bey to the floor.
##   2. Team-coloured glow — 4 concentric additive ellipses whose combined alpha
##      pulses and slowly counter-rotates with spin, radiating energy into the metal floor.
##   3. Hot core — tiny bright center ellipse that flares at full spin.

# ── Shadow geometry ────────────────────────────────────────────────────────────
const SHADOW_OFFSET: Vector2 = Vector2(5.0, 8.0)
const SHADOW_HALF_W: float   = 22.0
const SHADOW_HALF_H: float   = 10.0
const RIM_SCALE:     float   = 1.45
const INNER_COLOR:   Color   = Color(0.0, 0.0, 0.0, 0.70)
const RIM_COLOR:     Color   = Color(1.0, 1.0, 1.0, 0.15)

# ── Glow geometry ──────────────────────────────────────────────────────────────
const GLOW_OUTER_W:    float = 95.0   # wider footprint
const GLOW_OUTER_H:    float = 44.0
const GLOW_SHRINK:     float = 0.66   # each inner ring is 66 % the size of the outer
const GLOW_RING_COUNT: int   = 4
# Peak alpha per ring (outer halo → inner core) at full spin.
# Additive blend stacks toward center, creating bright hot-core feel.
const GLOW_PEAK_ALPHAS: Array = [0.12, 0.40, 0.72, 1.00]
# Glow pivot slowly counter-rotates against bey spin for an energy-swirl feel.
const GLOW_ROTATE_SPEED: float = 0.4   # rad/s

# ── Spin reference ─────────────────────────────────────────────────────────────
const FULL_SPIN_REF_FALLBACK: float = 120.0

# ── Pulse (dual-wave for organic breathing feel) ───────────────────────────────
const PULSE_SPEED:  float = 3.0    # Hz — primary throb
const PULSE_DEPTH:  float = 0.35
const PULSE2_SPEED: float = 1.3    # Hz — slower secondary breath
const PULSE2_DEPTH: float = 0.12

# ── Ellipse resolution ─────────────────────────────────────────────────────────
const ELLIPSE_PTS: int = 28   # slightly smoother ellipses for the larger size

# ── Runtime state ──────────────────────────────────────────────────────────────
var _spin_body:  RigidBody2D = null
var _glow_rings: Array       = []   # Array[Polygon2D]
var _glow_pivot: Node2D      = null # child node that rotates for the swirl effect


func _ready() -> void:
	top_level     = true
	z_index       = -50
	z_as_relative = false

	_spin_body = get_parent() as RigidBody2D

	# team_color lives on SpinController (the parent RigidBody2D) as an @export var.
	var team_col := Color(0.85, 0.55, 0.10, 1.0)  # warm amber fallback
	if _spin_body:
		var tc = _spin_body.get("team_color")
		if tc is Color and (tc as Color).a > 0.0:
			team_col = tc as Color

	_build_shadow()
	_build_glow(team_col)


# ── Shadow (rim + dark core) ───────────────────────────────────────────────────
func _build_shadow() -> void:
	var inner_pts := PackedVector2Array()
	var rim_pts   := PackedVector2Array()
	for i in ELLIPSE_PTS:
		var a: float = i * TAU / ELLIPSE_PTS
		inner_pts.append(Vector2(cos(a) * SHADOW_HALF_W,             sin(a) * SHADOW_HALF_H))
		rim_pts.append(  Vector2(cos(a) * SHADOW_HALF_W * RIM_SCALE, sin(a) * SHADOW_HALF_H * RIM_SCALE))

	var rim    := Polygon2D.new()
	rim.polygon = rim_pts
	rim.color   = RIM_COLOR
	add_child(rim)

	var shadow     := Polygon2D.new()
	shadow.polygon  = inner_pts
	shadow.color    = INNER_COLOR
	add_child(shadow)


# ── Glow (4 concentric additive rings on a rotating pivot) ───────────────────
func _build_glow(team_col: Color) -> void:
	var add_mat        := CanvasItemMaterial.new()
	add_mat.blend_mode  = CanvasItemMaterial.BLEND_MODE_ADD

	# Pivot node so we can rotate all rings together for the energy-swirl effect.
	_glow_pivot = Node2D.new()
	add_child(_glow_pivot)

	for i in GLOW_RING_COUNT:
		var ring_scale: float = pow(GLOW_SHRINK, i)   # 1.0 → 0.66 → 0.44 → 0.29
		var pts               := PackedVector2Array()
		for j in ELLIPSE_PTS:
			var a: float = j * TAU / ELLIPSE_PTS
			pts.append(Vector2(cos(a) * GLOW_OUTER_W * ring_scale,
			                   sin(a) * GLOW_OUTER_H * ring_scale))

		var ring      := Polygon2D.new()
		ring.polygon   = pts
		# Start at zero alpha; _process drives it each frame.
		ring.color     = Color(team_col.r, team_col.g, team_col.b, 0.0)
		ring.material  = add_mat
		_glow_pivot.add_child(ring)
		_glow_rings.append(ring)


# ── Per-frame ──────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if not is_instance_valid(_spin_body):
		return

	# ── Geyser height simulation ───────────────────────────────────────────────
	# While a Bey is airborne (launched by SludgeGeyser), the shadow stays near
	# the ground while the bey's scale grows — visually separating them to sell height.
	# geyser_height is a 0–1 float set by SludgeGeyser on the bey's meta.
	var height: float = float(_spin_body.get_meta("geyser_height", 0.0))
	# Drop the shadow downward and slightly expand its perceived distance from the bey.
	var height_drop: Vector2 = Vector2(0.0, 45.0) * height
	global_position = _spin_body.global_position + SHADOW_OFFSET + height_drop
	# Fade the shadow strongly as the bey rises — a high bey casts almost no shadow.
	modulate.a = lerpf(1.0, 0.08, height)

	# spin_ratio mirrors the stability bar: uses equilibrium_rpm so glow hits 100% at sustainable combat speed.
	var eq_rpm: float = (float(_spin_body.get("equilibrium_rpm")) if "equilibrium_rpm" in _spin_body else FULL_SPIN_REF_FALLBACK)
	var spin_ratio: float = clampf(abs(_spin_body.angular_velocity) / maxf(eq_rpm, 1.0), 0.0, 1.0)

	# Counter-rotate the glow pivot against bey spin — gives a swirling energy-field look.
	# At zero spin the pivot stays still; at full spin it rotates at GLOW_ROTATE_SPEED.
	var spin_sign: float = signf(_spin_body.angular_velocity) if abs(_spin_body.angular_velocity) > 0.5 else 1.0
	_glow_pivot.rotation -= spin_sign * GLOW_ROTATE_SPEED * spin_ratio * delta

	# Dual-wave pulse: primary throb + slower secondary breath, amplitude scales with spin.
	var t:          float = Time.get_ticks_msec() * 0.001
	var pulse_mod:  float = 1.0 \
		+ sin(t * TAU * PULSE_SPEED)  * PULSE_DEPTH  * spin_ratio \
		+ sin(t * TAU * PULSE2_SPEED) * PULSE2_DEPTH * spin_ratio

	# At high spin the innermost rings get a subtle white-hot tint toward white.
	var heat: float = spin_ratio * spin_ratio   # quadratic — only visible at top speeds

	for i in _glow_rings.size():
		var ring: Polygon2D = _glow_rings[i]
		# float() required — 'as float' is an object cast in GDScript 4 and returns null on primitives.
		var peak:       float = float(GLOW_PEAK_ALPHAS[i])
		var base_alpha: float = peak * spin_ratio * pulse_mod
		var c:          Color = ring.color
		# Inner rings (higher i) heat toward white at full spin.
		var heat_blend: float = heat * (float(i) / float(GLOW_RING_COUNT - 1)) * 0.4
		ring.color = Color(
			lerpf(c.r, 1.0, heat_blend),
			lerpf(c.g, 1.0, heat_blend),
			lerpf(c.b, 1.0, heat_blend),
			clampf(base_alpha, 0.0, 1.0)
		)
