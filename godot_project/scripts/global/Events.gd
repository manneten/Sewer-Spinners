extends Node

# ── Sewer Spins Event Bus ─────────────────────────────────────────────────────
#
# Central hub for decoupled communication between systems.
# Emit here; listeners connect here.  No direct cross-system calls needed.
#
# Usage:
#   Emit : Events.match_ended.emit("red")
#   Listen: Events.match_ended.connect(_on_match_ended)

# ── Match ─────────────────────────────────────────────────────────────────────
signal match_started(faction_id: String)      # SewerArena: fight begins; carries enemy faction id
signal match_ended(winner_side: String)       # SewerArena: "red" | "blue" | "none"

# ── Run ───────────────────────────────────────────────────────────────────────
signal run_completed                          # RunManager: player reached 10 wins
signal run_failed                             # RunManager: player hit 3 strikes

# ── Parts ─────────────────────────────────────────────────────────────────────
signal limb_damaged(limb_index: int, durability_remaining: int)  # RunManager: after each fight

# ── Economy ───────────────────────────────────────────────────────────────────
signal scrap_changed(new_total: int)          # RunManager: whenever Global.total_scrap changes

# ── Factions ──────────────────────────────────────────────────────────────────
signal reputation_changed(faction_id: String, new_total: int)  # FactionManager: after each match

# ── Shop ──────────────────────────────────────────────────────────────────────
signal open_shop(faction_id: String)   # RunManager: fired after wins 3, 6, 9
signal part_repaired(arm_slot: int)    # ShopScreen: limb durability restored
signal part_spliced(arm_slot: int)     # ShopScreen: franken-limb created from nub + shop item

# ── Combat FX ─────────────────────────────────────────────────────────────────
signal super_spark(position: Vector2)  # LimbManager: 5-deflection climax blast
signal take_hit(contact_pt: Vector2)	# LimbManager: any limb hit that isn't a block or parry; carries contact point for FX placement
# ── Camera ────────────────────────────────────────────────────────────────────
# Nuclear hard-reset: kills zoom tween, sets zoom=(1,1) offset=(0,0), time_scale=1.
# Emitted at the end of every special effect (Super Spark, Croco Lunge, Sewer Slap).
# SewerArena connects to this in _ready(); no direct arena reference needed.
signal global_camera_reset

# ── Time-Scale Manager ────────────────────────────────────────────────────────
# Centralised Engine.time_scale control with session IDs and a 2-second failsafe.
# Any script wanting slow-mo calls Events.set_slow_mo(); restoring normal speed
# calls Events.reset_time(). The session counter lets stale timer callbacks detect
# they are no longer the current time-scale owner, so they safely skip.
#
# Usage:
#   Engage : Events.set_slow_mo(0.1)
#   Restore: var s := Events.current_session()
#            get_tree().create_timer(1.0, true, false, true).timeout.connect(
#                func() -> void:
#                    if Events.current_session() == s: Events.reset_time()
#            )

var _effect_session: int = 0
var _ts_set_at_ms:   int = 0  # Time.get_ticks_msec() when slow-mo was last engaged

func current_session() -> int:
	return _effect_session

func set_slow_mo(scale: float) -> void:
	_effect_session += 1
	Engine.time_scale = scale
	_ts_set_at_ms     = Time.get_ticks_msec()

func reset_time() -> void:
	_effect_session  += 1
	Engine.time_scale = 1.0
	_ts_set_at_ms     = 0
	global_camera_reset.emit()

# Failsafe: if Engine.time_scale has been < 0.99 for more than 2.0 real seconds,
# force a reset. Guards against stale slow-mo from crashed timer callbacks.
func _process(_delta: float) -> void:
	if Engine.time_scale < 0.99 and _ts_set_at_ms > 0:
		if Time.get_ticks_msec() - _ts_set_at_ms > 2000:
			reset_time()
