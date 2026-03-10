extends Node2D

## BeySpeedArcs — four white curved stripes at the rim of the beyblade.
## Uses top_level + Line2D children (same pattern as BeyDropShadow) to
## guarantee rendering. Alpha = angular_velocity / max_angular_velocity,
## matching the stability bar exactly.
##
## Future: counter-rotate + motion-blur trail at full RPM (planned).

# ── Config ────────────────────────────────────────────────────────────────────
const ARC_RADIUS:    float = 40.0
const ARC_SPAN:      float = deg_to_rad(40.0)
const ARC_WIDTH:     float = 4.5
const ARC_MAX_ALPHA: float = 0.85
const ARC_COUNT:     int   = 4
const ARC_PTS:       int   = 12

# ── Runtime ───────────────────────────────────────────────────────────────────
var _spin_body: RigidBody2D = null
var _lines:     Array       = []   # Array[Line2D]


func _ready() -> void:
	_spin_body    = get_parent() as RigidBody2D
	top_level     = true
	z_as_relative = false
	z_index       = 20

	for i in ARC_COUNT:
		var line              := Line2D.new()
		line.width             = ARC_WIDTH
		line.default_color     = Color(1.0, 1.0, 1.0, 0.0)
		line.begin_cap_mode    = Line2D.LINE_CAP_ROUND
		line.end_cap_mode      = Line2D.LINE_CAP_ROUND
		var center_angle: float = i * (TAU / ARC_COUNT)
		for j in ARC_PTS:
			var t: float     = float(j) / (ARC_PTS - 1)
			var angle: float = center_angle - ARC_SPAN * 0.5 + ARC_SPAN * t
			line.add_point(Vector2(cos(angle), sin(angle)) * ARC_RADIUS)
		add_child(line)
		_lines.append(line)


func _process(_delta: float) -> void:
	if not is_instance_valid(_spin_body):
		return

	# Sync world transform manually (required when top_level = true).
	global_position = _spin_body.global_position
	global_rotation = _spin_body.rotation

	var max_av: float = float(_spin_body.get("max_angular_velocity")) \
		if "max_angular_velocity" in _spin_body else 120.0
	var spin_ratio: float = clampf(
		abs(_spin_body.angular_velocity) / maxf(max_av, 1.0), 0.0, 1.0
	)
	var alpha: float = spin_ratio * ARC_MAX_ALPHA
	for line in _lines:
		(line as Line2D).default_color = Color(1.0, 1.0, 1.0, alpha)
