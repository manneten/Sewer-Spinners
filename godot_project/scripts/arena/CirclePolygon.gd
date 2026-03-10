extends Polygon2D

# Generates a regular polygon approximating a circle at runtime.
# Set colour on the Polygon2D node; set radius here.
@export var radius: float = 70.0
@export var point_count: int = 24

func _ready() -> void:
	var pts := PackedVector2Array()
	for i in point_count:
		var angle := TAU * i / point_count
		pts.append(Vector2(cos(angle) * radius, sin(angle) * radius))
	polygon = pts
