extends Node2D
## Rat spectators arranged around the arena rim.
## Reacts to Events: super_spark → all jump; limb_damaged → a few ooh;
## match_ended → cheer (player win) or droop (player loss).

const ARENA_CENTER       := Vector2(576.0, 324.0)
const CROWD_COUNT_FRONT  := 26
const CROWD_COUNT_BACK   := 20
const CROWD_RADIUS_FRONT := 713.0
const CROWD_RADIUS_BACK  := 840.0
# sin(50°) ≈ 0.766 — exclusion arc is 100° wide around north and south, clears all 4 corner zones
const NS_EXCLUDE_THRESH  := 0.766

const BEY_SPLAT_RADIUS   := 38.0   # world-px — bey must be this close to squash a rat
const BLOOD_COUNT        := 12     # particles per splat

# Sewer-rat palette — all murky browns / greys
const RAT_COLORS: Array[Color] = [
	Color(0.28, 0.22, 0.18),
	Color(0.40, 0.35, 0.28),
	Color(0.52, 0.47, 0.38),
	Color(0.20, 0.18, 0.16),
	Color(0.36, 0.30, 0.22),
]

var _rats:       Array[Node2D] = []
var _base_y:     Array[float]  = []   # resting Y for each rat (local, parent at 0,0)
var _match_over: bool          = false
var _beys:       Array[Node2D] = []

# ── Setup ─────────────────────────────────────────────────────────────────────
func _ready() -> void:
	z_index        = -25
	z_as_relative  = false
	_spawn_crowd()
	Events.super_spark.connect(_on_super_spark)
	Events.match_ended.connect(_on_match_ended)
	Events.limb_damaged.connect(_on_limb_damaged)
	Events.take_hit.connect(_on_limb_damaged)  # same reaction as damage, just no duration
	_schedule_idle()
	call_deferred("_find_beys")

func _find_beys() -> void:
	var parent := get_parent()
	if not parent:
		return
	for bey_name in ["Player_Red", "Player_Blue"]:
		var b := parent.get_node_or_null(bey_name)
		if b:
			_beys.append(b)

func _process(_delta: float) -> void:
	if _beys.is_empty() or _rats.is_empty():
		return
	for i in range(_rats.size() - 1, -1, -1):
		var rat := _rats[i]
		if not is_instance_valid(rat):
			_rats.remove_at(i)
			_base_y.remove_at(i)
			continue
		for bey in _beys:
			if not is_instance_valid(bey):
				continue
			if rat.global_position.distance_to(bey.global_position) < BEY_SPLAT_RADIUS:
				_explode_rat(i)
				break

func _spawn_crowd() -> void:
	# Back row added first — earlier in scene tree = drawn behind front row at same z-index.
	# Angle offset by half a step so back rats don't stack directly behind front rats.
	var back_step := TAU / CROWD_COUNT_BACK
	for i in CROWD_COUNT_BACK:
		var angle := back_step * i + back_step * 0.5 + randf_range(-0.12, 0.12)
		# Skip rats in the north/south arc (within ~80° of vertical)
		if abs(cos(angle)) < NS_EXCLUDE_THRESH:
			continue
		var dist := CROWD_RADIUS_BACK + randf_range(-30.0, 30.0)
		var pos  := ARENA_CENTER + Vector2(cos(angle), sin(angle)) * dist
		var sz   := randf_range(8.0, 12.0)
		var col  := RAT_COLORS[randi() % RAT_COLORS.size()]
		var rat  := _make_rat(pos, sz, col)
		add_child(rat)
		_rats.append(rat)
		_base_y.append(pos.y)

	# Front row
	var front_step := TAU / CROWD_COUNT_FRONT
	for i in CROWD_COUNT_FRONT:
		var angle := front_step * i + randf_range(-0.12, 0.12)
		if abs(cos(angle)) < NS_EXCLUDE_THRESH:
			continue
		var dist := CROWD_RADIUS_FRONT + randf_range(-28.0, 28.0)
		var pos  := ARENA_CENTER + Vector2(cos(angle), sin(angle)) * dist
		var sz   := randf_range(10.0, 15.0)
		var col  := RAT_COLORS[randi() % RAT_COLORS.size()]
		var rat  := _make_rat(pos, sz, col)
		add_child(rat)
		_rats.append(rat)
		_base_y.append(pos.y)

func _make_rat(pos: Vector2, sz: float, col: Color) -> Node2D:
	var g := Node2D.new()
	g.position = pos   # parent (CrowdManager) is at 0,0 → local == world

	var head := Polygon2D.new()
	head.polygon = _circle_pts(sz, 14)
	head.color   = col
	g.add_child(head)

	for side in [-1, 1]:
		# Ear shell
		var ear     := Polygon2D.new()
		ear.polygon  = _circle_pts(sz * 0.40, 10)
		ear.position = Vector2(side * sz * 0.62, -sz * 0.74)
		ear.color    = col
		g.add_child(ear)
		# Inner ear (pinker)
		var inner     := Polygon2D.new()
		inner.polygon  = _circle_pts(sz * 0.24, 10)
		inner.position = Vector2(side * sz * 0.62, -sz * 0.74)
		inner.color    = Color(
			clampf(col.r + 0.24, 0.0, 1.0),
			col.g * 0.42,
			col.b * 0.42
		)
		g.add_child(inner)
		# Eye
		var eye     := Polygon2D.new()
		eye.polygon  = _circle_pts(sz * 0.13, 8)
		eye.position = Vector2(side * sz * 0.30, -sz * 0.08)
		eye.color    = Color(0.07, 0.03, 0.03)
		g.add_child(eye)

	return g

func _explode_rat(idx: int) -> void:
	var rat := _rats[idx]
	var pos := rat.global_position if is_instance_valid(rat) else ARENA_CENTER
	if is_instance_valid(rat):
		rat.queue_free()
	_rats.remove_at(idx)
	_base_y.remove_at(idx)
	_spawn_blood(pos)

func _spawn_blood(pos: Vector2) -> void:
	var parent := get_parent()
	if not parent:
		return
	for _i in BLOOD_COUNT:
		var dot     := Polygon2D.new()
		dot.polygon  = _circle_pts(randf_range(2.5, 5.5), 8)
		dot.color    = Color(
			randf_range(0.55, 0.80),
			randf_range(0.0,  0.07),
			randf_range(0.0,  0.05)
		)
		dot.z_index       = 5
		dot.z_as_relative = false
		parent.add_child(dot)
		dot.global_position = pos + Vector2(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0))
		var dir := (
			(pos - ARENA_CENTER).normalized()
			+ Vector2(randf_range(-0.9, 0.9), randf_range(-0.9, 0.9))
		).normalized()
		var tw := dot.create_tween()
		tw.tween_property(dot, "global_position",
				dot.global_position + dir * randf_range(55.0, 170.0), 0.55) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(dot, "modulate:a", 0.0, 0.55) \
			.set_delay(0.18)
		tw.tween_callback(dot.queue_free)

func _circle_pts(r: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts

# ── Event reactions ───────────────────────────────────────────────────────────
func _on_super_spark(_contact_pt: Vector2) -> void:
	if _match_over:
		return
	for i in _rats.size():
		var rat := _rats[i]
		if not is_instance_valid(rat):
			continue
		var jump_h := randf_range(20.0, 42.0)
		var delay  := randf_range(0.0, 0.14)
		var by     := _base_y[i]
		var tw := rat.create_tween()
		tw.tween_interval(delay)
		tw.tween_property(rat, "position:y", by - jump_h, 0.11) \
			.set_ease(Tween.EASE_OUT)
		tw.tween_property(rat, "position:y", by, 0.17) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BOUNCE)
		tw.parallel().tween_property(rat, "scale", Vector2(1.22, 1.22), 0.11)
		tw.tween_property(rat, "scale", Vector2.ONE, 0.14)

func _on_limb_damaged(_idx: int, _dur: int) -> void:
	if _match_over:
		return
	var reactions := randi_range(2, 4)
	var order := range(_rats.size())
	order.shuffle()
	for i in mini(reactions, order.size()):
		var idx := order[i] as int
		var rat := _rats[idx]
		if not is_instance_valid(rat):
			continue
		var by    := _base_y[idx]
		var delay := randf_range(0.0, 0.09)
		var tw := rat.create_tween()
		tw.tween_interval(delay)
		tw.tween_property(rat, "position:y", by - 10.0, 0.08).set_ease(Tween.EASE_OUT)
		tw.tween_property(rat, "position:y", by, 0.12).set_ease(Tween.EASE_IN)

func _on_match_ended(winner_side: String) -> void:
	_match_over = true
	var player_won := (winner_side == RunManager.player_side)
	for i in _rats.size():
		var rat := _rats[i]
		if not is_instance_valid(rat):
			continue
		if player_won:
			_celebrate(rat, _base_y[i], i * 0.06)
		else:
			_droop(rat, _base_y[i])

func _celebrate(rat: Node2D, by: float, delay: float) -> void:
	# Initial delay, then 3 bounce-jumps
	var tw := rat.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func() -> void:
		if not is_instance_valid(rat):
			return
		var inner := rat.create_tween()
		inner.set_loops(3)
		inner.tween_property(rat, "position:y", by - 30.0, 0.13).set_ease(Tween.EASE_OUT)
		inner.tween_property(rat, "position:y", by, 0.17) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BOUNCE)
	)

func _droop(rat: Node2D, by: float) -> void:
	var tw := rat.create_tween()
	tw.tween_interval(randf_range(0.0, 0.35))
	tw.tween_property(rat, "position:y", by + 9.0, 0.40).set_ease(Tween.EASE_OUT)
	tw.tween_property(rat, "scale", Vector2(0.82, 0.82), 0.40)

# ── Idle chatter ──────────────────────────────────────────────────────────────
func _schedule_idle() -> void:
	var delay := randf_range(2.0, 5.5)
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		if not is_instance_valid(self):
			return
		if not _match_over and not _rats.is_empty():
			var idx := randi() % _rats.size()
			var rat := _rats[idx]
			if is_instance_valid(rat):
				var by  := _base_y[idx]
				var bob := randf_range(5.0, 12.0)
				var tw  := rat.create_tween()
				tw.tween_property(rat, "position:y", by - bob, 0.09).set_ease(Tween.EASE_OUT)
				tw.tween_property(rat, "position:y", by, 0.13).set_ease(Tween.EASE_IN)
		_schedule_idle()
	)
