extends Node2D
## Sewer Weather — cycling Calm / Drizzle / Storm phases.
## Drizzle: cosmetic sludge drops.
## Storm:   drops also spawn SludgeTrail puddles that slow any bey that enters.

const ARENA_CENTER := Vector2(576.0, 324.0)
const ARENA_RADIUS := 420.0

const _SLUDGE_TRAIL = preload("res://scenes/effects/SludgeTrail.tscn")

enum Phase { CALM, DRIZZLE, STORM }

var _phase:       Phase = Phase.CALM
var _phase_timer: float = 0.0
var _drop_timer:  float = 0.0
var _match_over:  bool  = false

const PHASE_DUR: Dictionary = {
	Phase.CALM:    [12.0, 22.0],
	Phase.DRIZZLE: [5.0,   9.0],
	Phase.STORM:   [3.0,   5.5],
}
const DROP_INTERVAL: Dictionary = {
	Phase.DRIZZLE: 1.3,
	Phase.STORM:   0.42,
}
const DROP_COLOR := Color(0.12, 0.26, 0.07, 0.72)

func _ready() -> void:
	_phase_timer = randf_range(8.0, 14.0)
	Events.match_ended.connect(func(_s: String) -> void: _match_over = true)

func _process(delta: float) -> void:
	if _match_over:
		return
	_phase_timer -= delta
	if _phase_timer <= 0.0:
		_advance_phase()
	if _phase == Phase.CALM:
		return
	_drop_timer -= delta
	if _drop_timer <= 0.0:
		_drop_timer = DROP_INTERVAL.get(_phase, 1.0) * randf_range(0.72, 1.28)
		_spawn_drop()

func _advance_phase() -> void:
	match _phase:
		Phase.CALM:
			_phase = Phase.DRIZZLE
		Phase.DRIZZLE:
			_phase = Phase.STORM if randf() < 0.35 else Phase.CALM
		Phase.STORM:
			_phase = Phase.CALM
	var d: Array = PHASE_DUR[_phase]
	_phase_timer = randf_range(d[0], d[1])

func _spawn_drop() -> void:
	var angle := randf() * TAU
	var r     := randf() * ARENA_RADIUS * 0.84
	var land  := ARENA_CENTER + Vector2(cos(angle), sin(angle)) * r
	var start := Vector2(land.x, land.y - randf_range(220.0, 400.0))
	var heavy := (_phase == Phase.STORM) and (randf() < 0.45)

	var w := 4.0 if not heavy else 7.0
	var h := 12.0 if not heavy else 20.0

	var drop               := ColorRect.new()
	drop.size               = Vector2(w, h)
	drop.color              = DROP_COLOR
	drop.z_index            = -20
	drop.z_as_relative      = false
	drop.global_position    = start - Vector2(w * 0.5, 0.0)
	get_parent().add_child(drop)

	var fall_t := clampf((land.y - start.y) / randf_range(650.0, 940.0), 0.18, 1.0)
	var tw := create_tween()
	tw.tween_property(drop, "global_position:y", land.y, fall_t) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func() -> void:
		if is_instance_valid(drop):
			_on_land(land, heavy)
			drop.queue_free()
	)

func _on_land(pos: Vector2, heavy: bool) -> void:
	var p := CPUParticles2D.new()
	p.z_index           = -19
	p.z_as_relative     = false
	p.one_shot          = true
	p.lifetime          = 0.22
	p.amount            = 4 if not heavy else 9
	p.explosiveness     = 0.95
	p.direction         = Vector2.UP
	p.spread            = 65.0
	p.gravity           = Vector2(0.0, 420.0)
	p.initial_velocity_min = 18.0
	p.initial_velocity_max = 55.0 + (35.0 if heavy else 0.0)
	p.scale_amount_min  = 1.5
	p.scale_amount_max  = 3.0
	p.color             = DROP_COLOR
	get_parent().add_child(p)
	p.global_position   = pos
	p.emitting          = true
	get_tree().create_timer(0.5).timeout.connect(func() -> void:
		if is_instance_valid(p): p.queue_free()
	)

	if heavy:
		# Weather puddle: owner = null so it slows ANY bey that enters it.
		var trail: SludgeTrail = _SLUDGE_TRAIL.instantiate() as SludgeTrail
		get_parent().add_child(trail)
		trail.setup(pos, null)
