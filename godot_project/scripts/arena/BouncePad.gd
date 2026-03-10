extends Area2D

# Reverses and doubles the incoming linear_velocity — "Green Pad" double-momentum effect.
@export var velocity_multiplier: float = 2.5

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if not body is RigidBody2D:
		return
	var rb := body as RigidBody2D
	# Approximate collision normal as the pad→body direction, then reflect and amplify.
	var collision_normal := (rb.global_position - global_position).normalized()
	rb.linear_velocity = rb.linear_velocity.bounce(collision_normal) * velocity_multiplier
