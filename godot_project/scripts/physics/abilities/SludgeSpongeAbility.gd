class_name SludgeSpongeAbility extends LimbAbility

## Sludge Sponge — Strategic Area Denial
## Nerf: Dripping costs RPM. 
## Drawback: Extreme lack of friction (sliding risk) while in sludge.

# ── Constants ──────────────────────────────────────────────────────────────────
const SPONGE_COLOR:    Color = Color(0.118, 0.200, 0.102, 1.0) 
const DRIP_INTERVAL:   float = 0.15 # Slightly slower drip
const MIN_RPM:         float = 15.0 # Higher threshold to start dripping
const DRIP_SPIN_COST:  float = 0.4  # Subtract this from angular_velocity every drip

const _TRAIL_SCENE = preload("res://scenes/effects/SludgeTrail.tscn")

# ── State ──────────────────────────────────────────────────────────────────────
var _drip_timer:   float = 0.0
var _owned_trails: Array = []

# ── Init / Teardown ────────────────────────────────────────────────────────────
func initialize(spin_body: RigidBody2D, socket: Marker2D,
				rect: ColorRect, area: Area2D, manager: Node2D) -> void:
	passthrough_hits = true 
	super.initialize(spin_body, socket, rect, area, manager)
	rect.color   = SPONGE_COLOR
	_drip_timer  = LimbAbility.jitter_cooldown(DRIP_INTERVAL)
	
	if not Events.match_ended.is_connected(_on_match_ended):
		Events.match_ended.connect(_on_match_ended)

func _on_match_ended(_winner: String) -> void:
	on_teardown()

func on_teardown() -> void:
	_drip_timer = INF 
	for t in _owned_trails:
		if is_instance_valid(t):
			SludgeTrail._all_trails.erase(t)
			t.queue_free()
	_owned_trails.clear()

# ── Per-frame ──────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if not is_instance_valid(_spin_body):
		return
		
	_drip_timer -= delta
	if _drip_timer <= 0.0:
		_drip_timer = DRIP_INTERVAL
		# Only drip if we are spinning fast enough
		if abs(_spin_body.angular_velocity) > MIN_RPM:
			_drip()

# ── Drip Logic ─────────────────────────────────────────────────────────────────
func _drip() -> void:
	var arena: Node = _spin_body.get_parent()
	if not arena: return

	# NERF: The "Squeeze" Cost
	# Dripping consumes a bit of your current spin
	_spin_body.angular_velocity -= sign(_spin_body.angular_velocity) * DRIP_SPIN_COST

	# Global puddle cap logic
	while SludgeTrail._all_trails.size() >= SludgeTrail.MAX_TRAILS:
		var oldest = SludgeTrail._all_trails.pop_front()
		if is_instance_valid(oldest):
			_owned_trails.erase(oldest)
			oldest.queue_free()

	var trail: SludgeTrail = _TRAIL_SCENE.instantiate() as SludgeTrail
	arena.add_child(trail)
	trail.setup(_area.global_position, _spin_body)
	SludgeTrail._all_trails.append(trail)
	_owned_trails.append(trail)

	_owned_trails = _owned_trails.filter(func(t: Node) -> bool: return is_instance_valid(t))
	