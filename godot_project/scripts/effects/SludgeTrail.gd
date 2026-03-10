class_name SludgeTrail extends Area2D

## Sludge Sponge — puddle left by the limb tip.
## Enemy beys: linear_damp spiked for 3 s (extended slowdown).
## Owner bey:  no effect (puddles are neutral to their creator).
## Fades out after 4 s. Global cap of 30 simultaneous puddles.

# ── Constants ──────────────────────────────────────────────────────────────────
const MAX_TRAILS:           int   = 30
const LIFE_TOTAL:           float = 4.0   # seconds before fully gone
const FADE_START:           float = 3.0   # opacity starts dropping here
const SLUDGE_DAMP:          float = 7.0   # linear_damp applied to enemy
const SLUDGE_DAMP_DURATION: float = 3.0   # seconds before reverting
const SPLAT_RADIUS:         float = 20.0
const SPLAT_POINTS:         int   = 11
const SPLAT_COLOR: Color = Color(0.06, 0.16, 0.04, 0.85)  # dark sewer green

# ── Global pool ────────────────────────────────────────────────────────────────
static var _all_trails: Array = []

# ── Instance state ─────────────────────────────────────────────────────────────
var _owner_body: RigidBody2D = null

# ── Setup ──────────────────────────────────────────────────────────────────────
func setup(pos: Vector2, owner: RigidBody2D) -> void:
	global_position  = pos
	_owner_body      = owner
	z_index          = -45
	z_as_relative    = false  # absolute z so it's above floor but below beys
	_build_visual()
	_build_collision()
	body_entered.connect(_on_body_entered)
	_start_lifecycle()


func _build_visual() -> void:
	var poly := Polygon2D.new()
	var pts  := PackedVector2Array()
	for i in SPLAT_POINTS:
		var angle: float = i * TAU / SPLAT_POINTS + randf_range(-0.3, 0.3)
		var r:     float = SPLAT_RADIUS + randf_range(-7.0, 7.0)
		pts.append(Vector2(cos(angle), sin(angle)) * r)
	poly.polygon = pts
	poly.color = SPLAT_COLOR
	add_child(poly)


func _build_collision() -> void:
	collision_layer = 0   # puddle doesn't block anything
	collision_mask  = 1   # detects bey chassis (layer 1)
	monitoring      = true
	monitorable     = false
	var cshape       := CollisionShape2D.new()
	var circle       := CircleShape2D.new()
	circle.radius     = SPLAT_RADIUS
	cshape.shape      = circle
	add_child(cshape)


func _start_lifecycle() -> void:
	var tween := create_tween()
	tween.tween_interval(FADE_START)
	tween.tween_property(self, "modulate:a", 0.0, LIFE_TOTAL - FADE_START)
	tween.tween_callback(_die)


# ── Hit response ───────────────────────────────────────────────────────────────
func _on_body_entered(body: Node) -> void:
	if not body is RigidBody2D:
		return
	var rb := body as RigidBody2D
	if rb == _owner_body:
		pass  # puddles are neutral to their creator
	elif rb.has_method("force_ko"):
		# Sludge: spike linear_damp if not already under effect.
		if not rb.has_meta("sludged"):
			var prev_damp: float = rb.linear_damp
			rb.set_meta("sludged", true)
			rb.linear_damp = SLUDGE_DAMP
			get_tree().create_timer(SLUDGE_DAMP_DURATION).timeout.connect(func() -> void:
				if is_instance_valid(rb):
					rb.linear_damp = prev_damp
					rb.remove_meta("sludged")
			)


# ── Lifecycle ──────────────────────────────────────────────────────────────────
func _die() -> void:
	SludgeTrail._all_trails.erase(self)
	queue_free()
