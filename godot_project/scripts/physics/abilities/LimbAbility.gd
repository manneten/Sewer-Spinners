class_name LimbAbility extends Node

## Base class for special limb abilities.
## One instance lives as a child of its socket (Socket_Left_Arm / Socket_Right_Arm).
## Subclass this for every item that needs per-frame physics logic beyond normal LimbManager hits.
##
## Lifecycle:
##   LimbManager._plug_limb() → instantiates from LimbData.ability_scene
##                             → add_child(ability)
##                             → ability.initialize(...)
##   LimbManager.apply_loadout() / break_limb() → ability.on_teardown() → child.free()

## References injected by LimbManager.
var _spin_body: RigidBody2D  ## Owning bey's physics body.
var _socket:    Marker2D     ## Socket this limb is mounted on.
var _rect:      ColorRect    ## Visual rect of the limb.
var _area:      Area2D       ## Hitbox Area2D of the limb.
var _manager:   Node2D       ## LimbManager — use for shared VFX calls.

## If true, LimbManager will still connect body_entered and area_entered signals for this limb.
## Use when the ability augments normal limb behavior instead of replacing it entirely.
## Default false (ability fully owns area detection, monitoring disabled by LimbManager).
var passthrough_hits: bool = false

## Called immediately after add_child(). Override to read ability-specific data from the area/rect.
func initialize(spin_body: RigidBody2D, socket: Marker2D,
				rect: ColorRect, area: Area2D, manager: Node2D) -> void:
	_spin_body = spin_body
	_socket    = socket
	_rect      = rect
	_area      = area
	_manager   = manager

## Called by LimbManager before the socket's children are freed.
## Kill tweens and timers here to prevent callbacks firing on freed nodes.
func on_teardown() -> void:
	pass

## Returns an interval with a random ±35% offset applied to the initial cooldown.
## Call this instead of using the raw interval constant so two identical ability limbs
## on the same bey don't fire in sync.
static func jitter_cooldown(interval: float) -> float:
	return interval * randf_range(0.65, 1.00)

## Returns 1.0 − chassis.cooldown_reduction, clamped to [0.25, 1.0].
## Multiply any cooldown interval by this to apply the chassis passive.
func _cooldown_mult() -> float:
	if not is_instance_valid(_spin_body):
		return 1.0
	var ch = _spin_body.get("chassis")
	if ch == null or not "cooldown_reduction" in ch:
		return 1.0
	return clampf(1.0 - float(ch.cooldown_reduction), 0.25, 1.0)
