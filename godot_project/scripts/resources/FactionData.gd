extends Resource
class_name FactionData

@export var faction_id:            String = ""
@export var display_name:          String = ""
@export var rep_per_win:           int    = 10   # rep awarded when player beats this faction
@export var rep_per_loss:          int    = 3    # smaller rep even on losses (fought bravely)
@export var boss_unlock_threshold: int    = 50   # total rep needed to trigger boss fight

# Parts available in this faction's shop rotation.
@export var shop_limbs: Array = []     # Array of LimbData

# Used as the enemy chassis when a boss fight triggers.
@export var boss_chassis: Resource = null  # ChassisData
