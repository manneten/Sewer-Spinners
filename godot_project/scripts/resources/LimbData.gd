extends PartData
class_name LimbData

@export var wobble_intensity:    float = 1.0
@export var length_multiplier:   float = 1.0
@export var slow_on_hit:         bool        = false  # Sludge Sponge: slows enemy on contact (physics impl pending)
@export var wall_recoil_penalty: float       = 1.0    # Rusty Saw: multiplier on wall-splat RPM loss (1.0 = normal)
@export var crit_impulse_bonus:  float       = 0.0   # Twisted Wrench: fraction added to crit impulse (0.15 = +15%)
@export var ability_scene:       PackedScene = null   # Special ability node instantiated on plug-in (null = none)

# ── Shop ──────────────────────────────────────────────────────────────────────
@export var tier:        int = 1   # 1 = Common, 2 = Rare, 3 = Legendary
@export var scrap_price: int = 30  # base shop cost; override per resource
