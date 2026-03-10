extends StaticBody2D

signal wall_broken

@export var start_angle_deg: float = -45.0
@export var end_angle_deg:   float =  45.0
@export var arena_radius:    float = 499.0
@export var wall_thickness:  float = 50.0
@export var max_integrity:   int   = 3
@export var unbreakable:     bool  = false

const ARC_SEGMENTS: int = 14  # polygon resolution per segment

var wall_integrity: int  = 0
var _broken:        bool = false

var _collision_poly: CollisionPolygon2D
var _visual_poly:    Polygon2D
var _wall_sprite:    Sprite2D = null
var _wall_art_base:  String   = ""   # e.g. ".../wall_right/wall_right" (no extension)

func _ready() -> void:
	wall_integrity  = max_integrity
	_collision_poly = get_node_or_null("WallShape")
	_visual_poly    = get_node_or_null("WallVisual")
	_build_arc()

func _build_arc() -> void:
	# Collision: line segments along the outer arc (mirrors BowlWall BUILD_SEGMENTS style).
	if _collision_poly:
		var col_pts := PackedVector2Array()
		for i in ARC_SEGMENTS + 1:
			var t := float(i) / ARC_SEGMENTS
			var a := deg_to_rad(lerpf(start_angle_deg, end_angle_deg, t))
			col_pts.append(Vector2(cos(a), sin(a)) * arena_radius)
		_collision_poly.build_mode = CollisionPolygon2D.BUILD_SEGMENTS
		_collision_poly.polygon    = col_pts

	# Visual: filled arc strip (outer arc forward + inner arc backward).
	if _visual_poly:
		var vis_pts := PackedVector2Array()
		for i in ARC_SEGMENTS + 1:
			var t := float(i) / ARC_SEGMENTS
			var a := deg_to_rad(lerpf(start_angle_deg, end_angle_deg, t))
			vis_pts.append(Vector2(cos(a), sin(a)) * arena_radius)
		for i in ARC_SEGMENTS + 1:
			var t := float(ARC_SEGMENTS - i) / ARC_SEGMENTS
			var a := deg_to_rad(lerpf(start_angle_deg, end_angle_deg, t))
			vis_pts.append(Vector2(cos(a), sin(a)) * (arena_radius - wall_thickness))
		_visual_poly.polygon = vis_pts

## Called by SewerArena when the match time limit expires — instantly destroys this wall.
func shatter() -> void:
	if unbreakable or _broken:
		return
	wall_integrity = 0
	_spawn_chunks()
	_break_wall()

## Called by SewerArena._setup_art_layers() to bind the health-state sprite.
func setup_wall_art(sprite: Sprite2D, art_base: String) -> void:
	_wall_sprite  = sprite
	_wall_art_base = art_base

## Swaps the wall sprite texture to match current integrity (break1 / break2).
func _update_wall_texture() -> void:
	if not is_instance_valid(_wall_sprite) or _wall_art_base.is_empty():
		return
	if wall_integrity <= 0:
		return
	var suffix: String = "_break1.png" if wall_integrity > 1 else "_break2.png"
	var tex := load(_wall_art_base + suffix) as Texture2D
	if tex:
		_wall_sprite.texture = tex

# Called by SpinController when a wall-splat is detected on this segment.
func take_hit() -> void:
	if unbreakable or _broken:
		return
	wall_integrity -= 1
	_update_wall_texture()
	_flash_hit()
	_spawn_chunks()
	Events.take_hit.emit(global_position)
	if wall_integrity <= 0:
		_break_wall()

func _break_wall() -> void:
	_broken = true
	# Disable collision deferred so physics step isn't mid-flight.
	if _collision_poly:
		_collision_poly.set_deferred("disabled", true)
	# Fade out the visual over 0.4 s.
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	if is_instance_valid(_wall_sprite):
		var spr_tw := _wall_sprite.create_tween()
		spr_tw.tween_property(_wall_sprite, "modulate:a", 0.0, 0.4)
	wall_broken.emit()

# Flash white on hit, then tint sprite based on remaining integrity.
# Hit 1 (integrity=2): orange warning. Hit 2 (integrity=1): critical red. Hit 3: broken.
func _flash_hit() -> void:
	if is_instance_valid(_wall_sprite):
		_wall_sprite.modulate = Color.WHITE
	get_tree().create_timer(0.25).timeout.connect(func() -> void:
		if not is_instance_valid(self) or _broken:
			return
		var c: Color
		if wall_integrity <= 1:
			c = Color(1.0, 0.15, 0.05, 1.0)   # critical red — one hit from breaking
		elif wall_integrity <= 2:
			c = Color(1.0, 0.45, 0.05, 1.0)   # warning orange — first hit
		else:
			c = Color(1.0, 1.0, 1.0, 1.0)     # healthy — no tint
		if is_instance_valid(_wall_sprite):
			_wall_sprite.modulate = c
	)

# Spawns 6 physics debris chunks flying outward from the impact point.
func _spawn_chunks() -> void:
	var center_a: float  = deg_to_rad((start_angle_deg + end_angle_deg) * 0.5)
	var outward:  Vector2 = Vector2(cos(center_a), sin(center_a))
	var spawn_pos: Vector2 = global_position + outward * (arena_radius - wall_thickness * 0.5)

	for _i in 6:
		var chunk := RigidBody2D.new()
		chunk.gravity_scale    = 0.0
		chunk.linear_damp      = 0.6
		chunk.collision_layer  = 0   # no interaction with beys
		chunk.collision_mask   = 0

		var sz  := Vector2(randf_range(6.0, 16.0), randf_range(6.0, 16.0))
		var cr  := ColorRect.new()
		cr.size     = sz
		cr.position = -sz * 0.5
		cr.color    = Color(0.42, 0.38, 0.32, 1.0)
		chunk.add_child(cr)

		get_tree().root.add_child(chunk)
		chunk.global_position = (
			spawn_pos + Vector2(randf_range(-30.0, 30.0), randf_range(-30.0, 30.0))
		)
		var fly_dir: Vector2 = (
			outward + Vector2(randf_range(-0.5, 0.5), randf_range(-0.5, 0.5))
		).normalized()
		chunk.linear_velocity  = fly_dir * randf_range(80.0, 220.0)
		chunk.angular_velocity = randf_range(-8.0, 8.0)

		# Fade out and free after 1.5 s.
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			if is_instance_valid(chunk):
				var tw := chunk.create_tween()
				tw.tween_property(chunk, "modulate:a", 0.0, 0.5)
				tw.tween_callback(chunk.queue_free)
		)
