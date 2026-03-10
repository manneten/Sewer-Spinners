extends Area2D

# Pulls every RigidBody2D inside toward this node's global_position (the bowl center).
# Applied as a raw force so it works even when the body's gravity_scale is 0.
@export var gravity_strength: float = 300.0

var _bodies_inside: Array[RigidBody2D] = []

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	if body is RigidBody2D:
		_bodies_inside.append(body as RigidBody2D)

func _on_body_exited(body: Node2D) -> void:
	if body is RigidBody2D:
		_bodies_inside.erase(body)

func _physics_process(_delta: float) -> void:
	for body in _bodies_inside:
		if not is_instance_valid(body):
			continue
		var to_center: Vector2 = global_position - body.global_position
		if to_center.length_squared() > 0.0:
			body.apply_central_force(to_center.normalized() * gravity_strength)
