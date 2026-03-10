extends StaticBody2D

# ── Pocket Wall ────────────────────────────────────────────────────────────────
# A smooth outward dent in the arena boundary centred on a corner hazard.
# The arc radius follows a sine bell curve:
#   r(t) = outer_radius + dent_depth * sin(t * PI)
# so both endpoints sit flush with the adjacent WallSegments (outer_radius) and
# the peak of the dent sits dent_depth units behind the normal ring — letting a
# Beyblade park behind the normal circle with the hazard between it and centre.
#
# Node layout expected:
#   PocketWall (StaticBody2D, position = arena centre)
#   ├── WallVisual  (Polygon2D)
#   └── WallShape   (CollisionPolygon2D)

@export var pocket_center_deg : float = 45.0    # angle of hazard from arena centre
@export var half_span_deg     : float = 15.0    # half arc span (15 = 30° total, same as corners)
@export var outer_radius      : float = 499.0   # base radius — must match adjacent WallSegments
@export var dent_depth        : float = 175.0   # how far the peak bows outward past outer_radius

const ARC_SEGS      : int   = 18    # polygon resolution — enough for a smooth curve
const WALL_THICKNESS: float = 40.0  # visual strip depth, extending outward from collision face

var _collision_poly : CollisionPolygon2D
var _visual_poly    : Polygon2D


func _ready() -> void:
	_collision_poly = get_node_or_null("WallShape")
	_visual_poly    = get_node_or_null("WallVisual")
	_build_dent()


func _build_dent() -> void:
	var c  := deg_to_rad(pocket_center_deg)
	var hs := deg_to_rad(half_span_deg)

	var col_pts := PackedVector2Array()

	for i in ARC_SEGS + 1:
		var t := float(i) / ARC_SEGS          # 0 → 1 across the arc
		var a := lerpf(c - hs, c + hs, t)     # angle for this point
		var r := outer_radius + dent_depth * sin(t * PI)   # sine bell: 0 at edges, peak at centre
		col_pts.append(Vector2(cos(a), sin(a)) * r)

	# ── Collision polyline ────────────────────────────────────────────────────
	if _collision_poly:
		_collision_poly.build_mode = CollisionPolygon2D.BUILD_SEGMENTS
		_collision_poly.polygon    = col_pts

	# ── Visual strip ─────────────────────────────────────────────────────────
	# Inner face = collision surface (col_pts).
	# Outer face = each point pushed further outward by WALL_THICKNESS.
	# Forward + reversed outer = closed filled polygon.
	if _visual_poly:
		var vis_pts := PackedVector2Array()
		for p in col_pts:
			vis_pts.append(p)
		for i in col_pts.size():
			var p := col_pts[col_pts.size() - 1 - i]
			vis_pts.append(p.normalized() * (p.length() + WALL_THICKNESS))
		_visual_poly.polygon = vis_pts
