extends StaticBody2D

@export var radius: float = 300.0
@export var point_count: int = 32

func _ready() -> void:
	var wall := $WallShape as CollisionPolygon2D
	var pts  := PackedVector2Array()
	for i in point_count:
		var angle := TAU * i / point_count
		pts.append(Vector2(cos(angle) * radius, sin(angle) * radius))
	wall.build_mode = CollisionPolygon2D.BUILD_SEGMENTS
	wall.polygon    = pts
