extends CPUParticles2D

# Auto-emits on _ready and frees itself when the burst is done.
func _ready() -> void:
	emitting = true
	get_tree().create_timer(lifetime + 0.3).timeout.connect(queue_free)
