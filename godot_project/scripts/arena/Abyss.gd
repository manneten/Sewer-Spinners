extends Area2D

# Emitted so SewerArena (or a GameManager) can react to a Beyblade falling in.
signal body_fallen(body: RigidBody2D)

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if not body is RigidBody2D:
		return
	var rb := body as RigidBody2D
	# Trigger K.O. state before freeing so the KO banner can show.
	if rb.has_method("force_ko"):
		rb.force_ko()
	body_fallen.emit(rb)
	rb.queue_free()
