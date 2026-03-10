extends Area2D

## Mutation Station — the yellow pocket zone.
## When a Beyblade rolls through with a Broken Nub (lost to Super Spark or
## durability depletion), the zone scraps it and grafts on a random new limb.
## Each bey gets one roll per entry — they must leave and re-enter to try again.

# Common limb pool — no rare abilities; keep the station as a base-limb lifeline.
const MUTATION_POOL: Array[String] = [
	"res://resources/parts/limb_lead_pipe.tres",
	"res://resources/parts/limb_fleshy_tongue.tres",
	"res://resources/parts/limb_ethereal_vapor.tres",
	"res://resources/parts/limb_rat_fang.tres",
	"res://resources/parts/limb_rusty_saw.tres",
	"res://resources/parts/limb_croco_tail.tres",
	"res://resources/parts/limb_twisted_wrench.tres",
	"res://resources/parts/limb_sewer_bone.tres",
]

var _mutated_bodies: Array = []   # tracks who already got their graft this entry


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node2D) -> void:
	# Only react to beys, and only once per entry.
	if _mutated_bodies.has(body):
		return
	if not body.has_method("force_ko"):
		return

	var ghoul := body.get_node_or_null("Ghoul_Base")
	if not ghoul or not ghoul.has_method("try_replace_broken_limb"):
		return

	var chosen: String = MUTATION_POOL[randi() % MUTATION_POOL.size()]
	if ghoul.try_replace_broken_limb(chosen):
		_mutated_bodies.append(body)
		_flash_success()


func _on_body_exited(body: Node2D) -> void:
	# Reset so the bey can get another graft if they re-enter with a fresh break.
	_mutated_bodies.erase(body)


# Brief green flash on the zone to signal a successful graft.
func _flash_success() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(0.2, 3.0, 0.4, 1.0), 0.05)
	tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.5)
