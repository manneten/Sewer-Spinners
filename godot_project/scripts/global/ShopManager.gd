extends Node

# ── Shop Manager ──────────────────────────────────────────────────────────────
# Generates weighted shop inventories for the Faction Pit Stop.
# Register as autoload "ShopManager" in Project → Autoload.
#
# Tier weights (base):
#   Tier 1 Common    → weight 4.0
#   Tier 2 Rare      → weight 2.0
#   Tier 3 Legendary → weight 1.0
#
# Reputation influence:
#   Every 10 rep above REP_TIER2_THRESHOLD boosts Rare   weight by +1.
#   Every 10 rep above REP_TIER3_THRESHOLD boosts Legendary weight by +1.

const BASE_WEIGHTS: Dictionary = { 1: 4.0, 2: 2.0, 3: 1.0 }
const REP_TIER2_THRESHOLD: int = 20
const REP_TIER3_THRESHOLD: int = 40


# Returns an Array of up to 3 LimbData resources, weighted by tier and rep.
func generate_inventory(faction_id: String) -> Array:
	var all_limbs: Array = RunManager.load_all_of_class("LimbData")
	var pool: Array = []
	for item in all_limbs:
		var l := item as LimbData
		if l and l.name != "Broken Nub":
			pool.append(l)

	if pool.is_empty():
		return []

	var rep: int = FactionManager.get_reputation(faction_id)

	# Build weight list parallel to pool.
	var weights: Array[float] = []
	for limb: LimbData in pool:
		var t: int    = clampi(limb.tier if limb.tier > 0 else 1, 1, 3)
		var w: float  = BASE_WEIGHTS.get(t, 1.0)
		# Reputation boosts higher-tier probability linearly.
		if t == 2 and rep > REP_TIER2_THRESHOLD:
			w += float(rep - REP_TIER2_THRESHOLD) / 10.0
		elif t == 3 and rep > REP_TIER3_THRESHOLD:
			w += float(rep - REP_TIER3_THRESHOLD) / 10.0
		weights.append(w)

	# Weighted pick without replacement — up to 3 items.
	var result:            Array        = []
	var avail_pool:        Array        = pool.duplicate()
	var avail_weights:     Array[float] = weights.duplicate()

	while result.size() < 3 and not avail_pool.is_empty():
		var total: float = 0.0
		for w: float in avail_weights:
			total += w
		if total <= 0.0:
			break

		var roll: float      = randf() * total
		var cumulative: float = 0.0
		var picked: int       = avail_pool.size() - 1   # fallback to last
		for i in avail_weights.size():
			cumulative += avail_weights[i]
			if roll <= cumulative:
				picked = i
				break

		result.append(avail_pool[picked])
		avail_pool.remove_at(picked)
		avail_weights.remove_at(picked)

	return result
