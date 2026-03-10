extends Area2D

@export var suction_strength: float = 500.0
# 0.98 per frame = angular velocity loses ~2% each physics tick while inside.
# This is the "Health = RPM" drain mechanic from the design doc.
@export var gunk_damping: float = 0.98

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

		# -- Suction: pull toward drain center --------------------------------
		var to_center: Vector2 = global_position - body.global_position
		if to_center.length_squared() > 0.0:
			body.apply_central_force(to_center.normalized() * suction_strength)

		# -- Gunk friction: bleed angular velocity every physics frame --------
		# Simulates the spin slowing as gunk clogs the Beyblade base.
		body.angular_velocity *= gunk_damping
