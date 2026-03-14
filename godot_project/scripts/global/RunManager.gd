extends Node

# ── Signals ───────────────────────────────────────────────────────────────────
# run_started is kept here because GambleScreen listens to it directly.
# run_completed / run_failed are mirrored to Events for external listeners.
signal run_started

# ── Constants ─────────────────────────────────────────────────────────────────
const RUN_ENTRY_COST:    int    = 50
const WINS_TO_COMPLETE:  int    = 10
const LOSSES_TO_FAIL:    int    = 3
const LIMB_MAX_DURABILITY: int  = 3
const PARTS_DIR:         String = "res://resources/parts/"
const BROKEN_NUB_PATH:   String = "res://resources/parts/limb_broken_nub.tres"

# Explicit manifest of all part files — used instead of DirAccess so web exports work.
# DirAccess cannot traverse the virtual PCK filesystem in a browser.
const ALL_PARTS: Array[String] = [
	"res://resources/parts/chassis_bottle_cap.tres",
	"res://resources/parts/chassis_cast_iron_lid.tres",
	"res://resources/parts/chassis_croco_jaw.tres",
	"res://resources/parts/chassis_grease_trap.tres",
	"res://resources/parts/chassis_plastic_lid.tres",
	"res://resources/parts/chassis_rusty_manhole.tres",
	"res://resources/parts/chassis_sewer_king.tres",
	"res://resources/parts/chassis_worm_queen.tres",
	"res://resources/parts/limb_croco_tail.tres",
	"res://resources/parts/limb_ethereal_vapor.tres",
	"res://resources/parts/limb_fleshy_tongue.tres",
	"res://resources/parts/limb_lead_pipe.tres",
	"res://resources/parts/limb_rat_fang.tres",
	"res://resources/parts/limb_rusty_saw.tres",
	"res://resources/parts/limb_sewer_bone.tres",
	"res://resources/parts/limb_sewer_harpoon.tres",
	"res://resources/parts/limb_sewer_slapper.tres",
	"res://resources/parts/limb_sludge_sponge.tres",
	"res://resources/parts/limb_twisted_wrench.tres",
]

# ── Run state ─────────────────────────────────────────────────────────────────
var current_wins:   int      = 0
var current_losses: int      = 0
var player_chassis: Resource = null   # ChassisData
var player_limbs:   Array    = []     # Array[LimbData], always 2 entries during a run
var player_limb_durabilities: Array[int] = []  # parallel to player_limbs

var run_active:    bool   = false
var player_side:   String = "red"    # "red" = Player_Red (left), "blue" = Player_Blue (right)
var is_boss_fight: bool   = false    # set by SewerArena when the final fight triggers a boss
var matches_played: int   = 0        # total matches played this run (wins + losses)
var pending_shop:   bool  = false    # true when a Pit Stop shop should show on next scene load

# ── Versus Screen data (set by GambleScreen before each fight) ─────────────────
var vs_player_name:      String = ""   # brainrot name the player picked
var vs_enemy_name:       String = ""   # brainrot name of the opponent paper
var vs_enemy_faction_id: String = ""   # faction id for the upcoming fight


# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	# Listen on the Event Bus — all match-result logic lives here, not in SewerArena.
	Events.match_ended.connect(_on_match_ended)


# ── Event Bus handler ─────────────────────────────────────────────────────────

# Called synchronously by Events.match_ended when a fight resolves.
# Owns: durability deduction, win/loss counting, scrap reward.
func _on_match_ended(winner_side: String) -> void:
	if not run_active:
		return

	if winner_side == player_side:
		# Limbs only wear down on a win — losses are free in terms of freshness.
		deduct_fight_durability()
		Global.total_scrap = maxi(Global.total_scrap + RUN_ENTRY_COST * 2, 0)
		Events.scrap_changed.emit(Global.total_scrap)
		_record_win()
	elif winner_side != "none":
		_record_loss()


# ── Public API ────────────────────────────────────────────────────────────────

# Deducts entry scrap, stores the chosen loadout, and begins the run.
# Returns false (and does nothing) if the player can't afford entry.
func start_run_with_loadout(chosen_chassis: Resource, chosen_limbs: Array,
		side: String = "red") -> bool:
	if Global.total_scrap < RUN_ENTRY_COST:
		return false

	Global.total_scrap -= RUN_ENTRY_COST
	Events.scrap_changed.emit(Global.total_scrap)

	current_wins   = 0
	current_losses = 0
	matches_played = 0
	pending_shop   = false
	player_chassis             = chosen_chassis
	player_limbs               = chosen_limbs.duplicate()
	player_limb_durabilities   = [LIMB_MAX_DURABILITY, LIMB_MAX_DURABILITY]
	player_side                = side
	run_active                 = true

	run_started.emit()
	return true


# ── Internal win/loss counters ────────────────────────────────────────────────

func _record_win() -> void:
	current_wins   += 1
	matches_played += 1
	# Pit Stop: shop appears after wins 3, 6, and 9.
	if current_wins in [3, 6, 9]:
		pending_shop = true
		Events.open_shop.emit(FactionManager.current_match_faction_id)
	if current_wins >= WINS_TO_COMPLETE:
		run_active = false
		Events.run_completed.emit()


func _record_loss() -> void:
	current_losses += 1
	matches_played += 1
	if current_losses >= LOSSES_TO_FAIL:
		run_active = false
		Events.run_failed.emit()


# ── Durability ────────────────────────────────────────────────────────────────

# Ticks each limb down by 1; replaces a limb at 0 durability with a Broken Nub.
# Called internally by _on_match_ended — not by external systems.
func deduct_fight_durability() -> void:
	if not run_active:
		return
	var nub: LimbData = null
	for i in player_limbs.size():
		while player_limb_durabilities.size() <= i:
			player_limb_durabilities.append(LIMB_MAX_DURABILITY)
		player_limb_durabilities[i] = maxi(player_limb_durabilities[i] - 1, 0)
		Events.limb_damaged.emit(i, player_limb_durabilities[i])
		if player_limb_durabilities[i] == 0:
			if nub == null and ResourceLoader.exists(BROKEN_NUB_PATH):
				nub = load(BROKEN_NUB_PATH) as LimbData
			if nub:
				player_limbs[i] = nub

# Returns a descriptive freshness label for a player limb slot.
func get_limb_freshness(index: int) -> String:
	if index >= player_limb_durabilities.size():
		return "FRESH"
	match player_limb_durabilities[index]:
		3: return "FRESH"
		2: return "WITHERED"
		1: return "ROTTING"
		_: return "FALLING OFF"

# Returns a colour matching the freshness state.
func get_freshness_color(index: int) -> Color:
	if index >= player_limb_durabilities.size():
		return Color(0.2, 0.85, 0.3, 1.0)
	match player_limb_durabilities[index]:
		3: return Color(0.20, 0.85, 0.30, 1.0)   # green
		2: return Color(0.85, 0.78, 0.08, 1.0)   # amber
		1: return Color(0.88, 0.38, 0.05, 1.0)   # orange-red
		_: return Color(0.88, 0.10, 0.06, 1.0)   # critical red


# ── Resource helpers ───────────────────────────────────────────────────────────

# Returns all part resources whose script class matches class_name_filter.
# Uses a hardcoded manifest instead of DirAccess — DirAccess cannot traverse
# the virtual PCK filesystem in web exports.
func load_all_of_class(class_name_filter: String) -> Array:
	var result := []
	for full_path: String in ALL_PARTS:
		if full_path == BROKEN_NUB_PATH:
			continue
		var res := load(full_path)
		if res and res.get_script() \
				and res.get_script().get_global_name() == class_name_filter:
			result.append(res)
	return result
