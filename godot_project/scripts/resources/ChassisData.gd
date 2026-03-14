extends PartData
class_name ChassisData

@export var base_torque:        float    = 13000.0
@export var base_friction:      float    = 0.0
@export var cooldown_reduction: float    = 0.0          # 0.25 = 25% shorter ability cooldowns
@export var sprite_texture:     Texture2D = null        # top-down art; null = fallback ColorRect
