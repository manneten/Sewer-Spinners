class_name TongueWhipAbility extends LimbAbility

## Fleshy Tongue — Slap & Snap
## Passive ability: when the tongue hits an enemy chassis, the owner gets a small
## angular-velocity burst and the limb retracts briefly like a real tongue recoil.
## passthrough_hits = true — normal LimbManager crit/deflect logic still fires.

# ── Constants ──────────────────────────────────────────────────────────────────
const LIMB_SIZE_Y:          float = 28.0   # must match LimbManager.LIMB_SIZE.y
const TONGUE_SPEED_BOOST:   float = 8.0    # +av added to owner on contact
const TONGUE_RETRACT_RATIO: float = 0.35   # shrink to 35% of base length
const TONGUE_RETRACT_DUR:   float = 0.15   # time to snap inward
const TONGUE_EXTEND_DUR:    float = 0.30   # time to spring back out
const TONGUE_HIT_COOLDOWN:  float = 0.8    # min seconds between boosts

# ── State ──────────────────────────────────────────────────────────────────────
var _base_len:      float = 0.0
var _tween:         Tween = null
var _is_retracting: bool  = false
var _hit_cooldown:  float = 0.0

# ── Init / Teardown ────────────────────────────────────────────────────────────
func initialize(spin_body: RigidBody2D, socket: Marker2D,
				rect: ColorRect, area: Area2D, manager: Node2D) -> void:
	passthrough_hits = true   # must be set before LimbManager reads it
	super.initialize(spin_body, socket, rect, area, manager)
	_base_len = rect.size.x
	area.body_entered.connect(_on_hit)


func on_teardown() -> void:
	if is_instance_valid(_tween):
		_tween.kill()
	_is_retracting = false

# ── Per-frame ──────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if _hit_cooldown > 0.0:
		_hit_cooldown -= delta

	# While retracting: override LimbManager's per-frame rect placement so the
	# visual follows the tween'd size correctly (same pattern as SlapperAbility).
	if _is_retracting and is_instance_valid(_rect) and is_instance_valid(_socket):
		var cur_len: float   = _rect.size.x
		var s_out:   Vector2 = _socket.position.normalized()
		_rect.position = Vector2(minf(s_out.x, 0.0) * cur_len, -LIMB_SIZE_Y * 0.5)
		if is_instance_valid(_area):
			_area.position = s_out * cur_len

# ── Hit detection ──────────────────────────────────────────────────────────────
func _on_hit(body: Node) -> void:
	if not body is RigidBody2D:
		return
	if body == _spin_body:
		return
	if not body.has_method("force_ko"):
		return
	if _hit_cooldown > 0.0:
		return

	_hit_cooldown = TONGUE_HIT_COOLDOWN

	# Speed burst — clamp so we don't overcap.
	var max_av: float = _spin_body.get("max_angular_velocity") if _spin_body.get("max_angular_velocity") else 80.0
	var cur:    float = _spin_body.angular_velocity
	_spin_body.angular_velocity = minf(abs(cur) + TONGUE_SPEED_BOOST, max_av) * signf(cur)

	_do_retract()

# ── Retract animation ──────────────────────────────────────────────────────────
func _do_retract() -> void:
	if not is_instance_valid(_rect):
		return

	_is_retracting = true
	if is_instance_valid(_tween):
		_tween.kill()

	var retract_len: float = _base_len * TONGUE_RETRACT_RATIO
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(_rect, "size:x", retract_len, TONGUE_RETRACT_DUR) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(_rect, "size:x", _base_len, TONGUE_EXTEND_DUR) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_tween.tween_callback(func() -> void:
		_is_retracting = false
		if is_instance_valid(_rect):
			_rect.size.x = _base_len
		if is_instance_valid(_area) and is_instance_valid(_socket):
			_area.position = _socket.position.normalized() * _base_len
	)
