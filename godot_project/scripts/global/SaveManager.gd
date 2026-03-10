extends Node

# ── Save Manager ──────────────────────────────────────────────────────────────
# Serialises Global, FactionManager, and RunManager state to JSON.
# Fail-safe: any read error or schema mismatch silently falls back to defaults.
# Auto-saves on run_completed, run_failed, and reputation_changed.

const SAVE_PATH:    String = "user://sewer_spins_save.json"
const SAVE_VERSION: int    = 1

# Trophy records: Array of Dictionaries, one entry per completed run.
# Public so the future Trophy Gallery screen can read it directly.
var trophies: Array = []


# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	load_game()
	Events.run_completed.connect(_on_run_completed)
	Events.run_failed.connect(save_game)
	Events.reputation_changed.connect(func(_id: String, _rep: int) -> void: save_game())


# ── Auto-save triggers ────────────────────────────────────────────────────────
func _on_run_completed() -> void:
	_capture_trophy()
	save_game()


# ── Save ──────────────────────────────────────────────────────────────────────
func save_game() -> void:
	var data: Dictionary = {
		"version":            SAVE_VERSION,
		"total_scrap":        Global.total_scrap,
		"faction_reputation": FactionManager.get_all_reputation(),
		"unlocked_trophies":  _serialize_trophies(),
		"player_skills":      {},   # reserved for future Skill Point upgrades
	}

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file:
		push_error("SaveManager: could not open '%s' for writing." % SAVE_PATH)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()


# ── Load ──────────────────────────────────────────────────────────────────────
func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return   # First launch — use hardcoded defaults, nothing to inject.

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		push_warning("SaveManager: could not open save file — keeping defaults.")
		return

	var raw: String = file.get_as_text()
	file.close()

	# Parse — null means the file is corrupted or empty.
	var data = JSON.parse_string(raw)
	if not data is Dictionary:
		push_warning("SaveManager: save file is malformed — reverting to defaults.")
		return

	# Version check — incompatible schema triggers a clean slate rather than a crash.
	if data.get("version", 0) != SAVE_VERSION:
		push_warning("SaveManager: save version mismatch — reverting to defaults.")
		return

	# ── Inject: total_scrap ───────────────────────────────────────────────────
	var raw_scrap = data.get("total_scrap", null)
	if raw_scrap != null:
		Global.total_scrap = int(raw_scrap)

	# ── Inject: faction reputation ────────────────────────────────────────────
	var raw_rep = data.get("faction_reputation", null)
	if raw_rep is Dictionary:
		FactionManager.load_reputation(raw_rep)

	# ── Inject: trophies ──────────────────────────────────────────────────────
	var raw_trophies = data.get("unlocked_trophies", null)
	if raw_trophies is Array:
		_load_trophies(raw_trophies)

	# player_skills: injected when the Skill system is implemented.


# ── Reset ─────────────────────────────────────────────────────────────────────
# Wipes all persistent progress and writes a clean save file.
# Scene reload is handled by the caller (GambleScreen reset button).
func reset_and_save() -> void:
	Global.total_scrap = 100
	FactionManager.reset_reputation()
	trophies.clear()

	# Clear in-progress run state so no stale data leaks across resets.
	RunManager.run_active               = false
	RunManager.current_wins             = 0
	RunManager.current_losses           = 0
	RunManager.matches_played           = 0
	RunManager.pending_shop             = false
	RunManager.player_chassis           = null
	RunManager.player_limbs             = []
	RunManager.player_limb_durabilities = []
	RunManager.is_boss_fight            = false

	save_game()


# ── Trophy capture ────────────────────────────────────────────────────────────
func _capture_trophy() -> void:
	if not RunManager.player_chassis:
		return
	if RunManager.player_limbs.size() < 2:
		return

	var limb_l := RunManager.player_limbs[0] as LimbData
	var limb_r := RunManager.player_limbs[1] as LimbData
	if not limb_l or not limb_r:
		return

	trophies.append({
		"chassis_name":    RunManager.player_chassis.name,
		"chassis_color":   _color_to_array(RunManager.player_chassis.color),
		"limb_l_name":     limb_l.name,
		"limb_l_color":    _color_to_array(limb_l.color),
		"limb_r_name":     limb_r.name,
		"limb_r_color":    _color_to_array(limb_r.color),
		"faction_beaten":  FactionManager.current_match_faction_id,
		"wins":            RunManager.current_wins,
		"was_boss_fight":  RunManager.is_boss_fight,
	})


# ── Serialisation helpers ─────────────────────────────────────────────────────
func _serialize_trophies() -> Array:
	# Trophies are already plain Dictionaries with no Resource references.
	return trophies.duplicate(true)


func _load_trophies(raw: Array) -> void:
	trophies.clear()
	for entry in raw:
		if entry is Dictionary:
			trophies.append(entry)


func _color_to_array(c: Color) -> Array:
	return [c.r, c.g, c.b, c.a]


# Convenience helper for future systems that want to reconstruct a Color.
func array_to_color(a: Array) -> Color:
	if a.size() < 4:
		return Color.WHITE
	return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
