extends Node

# ── Faction Manager ───────────────────────────────────────────────────────────
# Loads all FactionData resources, tracks per-faction reputation,
# and awards rep via the Event Bus after each match.

const FACTIONS_DIR: String = "res://resources/factions/"

var _factions:   Dictionary = {}   # faction_id → FactionData
var _reputation: Dictionary = {}   # faction_id → int

# Captured from Events.match_started each fight so match_ended knows who was fought.
# Public so SaveManager can read it when capturing a trophy on run_completed.
var current_match_faction_id: String = ""


func _ready() -> void:
	_load_factions()
	Events.match_started.connect(_on_match_started)
	Events.match_ended.connect(_on_match_ended)


func _load_factions() -> void:
	var dir := DirAccess.open(FACTIONS_DIR)
	if not dir:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var res := load(FACTIONS_DIR + fname)
			if res and res.get_script() \
					and res.get_script().get_global_name() == "FactionData":
				_factions[res.faction_id]   = res
				_reputation[res.faction_id] = 0
		fname = dir.get_next()
	dir.list_dir_end()


# ── Event handlers ────────────────────────────────────────────────────────────

func _on_match_started(faction_id: String) -> void:
	current_match_faction_id = faction_id


func _on_match_ended(winner_side: String) -> void:
	if current_match_faction_id.is_empty():
		return
	if not _factions.has(current_match_faction_id):
		return

	var faction: FactionData = _factions[current_match_faction_id]
	var player_won: bool     = (winner_side == RunManager.player_side)
	var rep_gain: int        = faction.rep_per_win if player_won else faction.rep_per_loss

	_reputation[current_match_faction_id] += rep_gain
	Events.reputation_changed.emit(
		current_match_faction_id,
		_reputation[current_match_faction_id]
	)


# ── Public API ────────────────────────────────────────────────────────────────

func get_reputation(faction_id: String) -> int:
	return _reputation.get(faction_id, 0)


func get_faction(faction_id: String) -> FactionData:
	return _factions.get(faction_id, null)


# Returns true if the player has enough rep to fight this faction's boss.
func is_boss_eligible(faction_id: String) -> bool:
	var faction: FactionData = get_faction(faction_id)
	if not faction:
		return false
	return get_reputation(faction_id) >= faction.boss_unlock_threshold


# ── Save / Load support ───────────────────────────────────────────────────────

# Returns a copy of the reputation dict — safe to serialize.
func get_all_reputation() -> Dictionary:
	return _reputation.duplicate()


# Injects saved reputation values; silently skips unknown faction IDs.
func load_reputation(data: Dictionary) -> void:
	for faction_id in data:
		if _reputation.has(faction_id):
			_reputation[faction_id] = int(data[faction_id])


# Zeros out all tracked reputation (used by Reset Progress).
func reset_reputation() -> void:
	for faction_id in _reputation:
		_reputation[faction_id] = 0
