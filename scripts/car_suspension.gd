class_name CarSuspension
extends Node3D
## Visual buggy-style suspension and a sprung chassis. Physics is untouched:
## the wheels already move with the raycast suspension; this draws double
## wishbones and a coil-over from the chassis to each wheel, and lets the
## chassis lean, squat, dive and bounce from the car's acceleration.
## Everything is mirror-symmetric top/bottom about the axle line (the car
## drives on its roof too): wishbones above and below it, the coil-over on it.
## Lives under Car/Visual; Car calls update() every physics tick.

const ARM_COLOR := Color(0.95, 0.72, 0.08)
const ARM_RADIUS := 0.035
const HUB_INSET := 0.33  ## from wheel centre towards the chassis, on the axle
const HUB_SPREAD := 0.14  ## upper/lower wishbone ball joints above/below the axle
const MOUNT_X := 0.55  ## chassis side, where the wishbones pivot
const MOUNT_SPREAD := 0.38  ## fore/aft half-spacing of each wishbone's two pivots
const SHOCK_MOUNT_X := 0.4  ## coil-over's inner end, inside the chassis on the axle line

@export var lean_per_accel := 0.006  ## rad per m/s² of sideways/fore-aft acceleration
@export var heave_per_accel := 0.004  ## m per m/s² of vertical acceleration
@export var max_lean := 0.09  ## rad
@export var max_heave := 0.12  ## m
@export var stiffness := 120.0
@export var damping := 9.0

var _chassis: Node3D
var _wheel_pivots: Array[Node3D] = []
var _rigs: Array[WheelRig] = []
var _previous_velocity := Vector3.ZERO
var _has_previous := false
# Sprung chassis state: x = roll, y = heave, z = pitch.
var _offset := Vector3.ZERO
var _offset_velocity := Vector3.ZERO


class WheelRig:
	var bars: Array[MeshInstance3D] = []
	var damper: MeshInstance3D
	var spring: MeshInstance3D


func setup(chassis: Node3D, wheel_pivots: Array[Node3D]) -> void:
	_chassis = chassis
	_wheel_pivots = wheel_pivots
	var arm := StandardMaterial3D.new()
	arm.albedo_color = ARM_COLOR
	arm.metallic = 0.6
	arm.roughness = 0.35
	var chrome := StandardMaterial3D.new()
	chrome.albedo_color = Color(0.8, 0.8, 0.82)
	chrome.metallic = 1.0
	chrome.roughness = 0.2
	var spring_material := arm.duplicate() as StandardMaterial3D
	spring_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var bar_mesh := CylinderMesh.new()
	bar_mesh.top_radius = ARM_RADIUS
	bar_mesh.bottom_radius = ARM_RADIUS
	bar_mesh.height = 1.0
	bar_mesh.radial_segments = 8
	bar_mesh.material = arm
	var damper_mesh := bar_mesh.duplicate() as CylinderMesh
	damper_mesh.top_radius = 0.04
	damper_mesh.bottom_radius = 0.04
	damper_mesh.material = chrome
	var spring_mesh := MeshBuilder.coil_spring(7.0, 0.085, 0.018, spring_material)

	for pivot in wheel_pivots:
		var rig := WheelRig.new()
		for i in 5:  # 2 upper + 2 lower wishbone arms + upright
			rig.bars.append(_instance(bar_mesh))
		rig.damper = _instance(damper_mesh)
		rig.spring = _instance(spring_mesh)
		_rigs.append(rig)


## velocity: the car's world velocity; basis: its world basis.
func update(delta: float, velocity: Vector3, basis: Basis) -> void:
	_update_chassis(delta, velocity, basis)
	for i in _rigs.size():
		_update_rig(_rigs[i], _wheel_pivots[i])


func _update_chassis(delta: float, velocity: Vector3, basis: Basis) -> void:
	var world_accel := Vector3.ZERO
	if _has_previous and delta > 0.0:
		world_accel = (velocity - _previous_velocity) / delta
	var accel := basis.inverse() * world_accel
	# Only a sudden push up (a landing) makes the chassis sag; free fall
	# doesn't. Sag is towards the ground, whichever side of the car that is.
	var flip_sign := 1.0 if basis.y.y >= 0.0 else -1.0
	var sag := -maxf(world_accel.y, 0.0) * heave_per_accel * flip_sign
	_previous_velocity = velocity
	_has_previous = true

	# Lean out of turns (roll), squat under throttle / dive under braking
	# (pitch), sag on hard landings (heave) — then let a damped spring chase it.
	var target := Vector3(
		clampf(accel.x * lean_per_accel, -max_lean, max_lean),
		clampf(sag, -max_heave, max_heave),
		clampf(-accel.z * lean_per_accel, -max_lean, max_lean)
	)
	_offset_velocity += (target - _offset) * stiffness * delta - _offset_velocity * damping * delta
	_offset += _offset_velocity * delta
	_chassis.transform = Transform3D(
		Basis.from_euler(Vector3(_offset.z, 0.0, _offset.x)), Vector3(0.0, _offset.y, 0.0)
	)


func _update_rig(rig: WheelRig, pivot: Node3D) -> void:
	var wheel := pivot.position
	var side := signf(wheel.x)
	var hub_upper := wheel + Vector3(-side * HUB_INSET, HUB_SPREAD, 0.0)
	var hub_lower := wheel + Vector3(-side * HUB_INSET, -HUB_SPREAD, 0.0)
	var mount := func(y: float, dz: float) -> Vector3:
		return _chassis.transform * Vector3(side * MOUNT_X, y, wheel.z + dz)

	_place_bar(rig.bars[0], mount.call(HUB_SPREAD, -MOUNT_SPREAD), hub_upper)
	_place_bar(rig.bars[1], mount.call(HUB_SPREAD, MOUNT_SPREAD), hub_upper)
	_place_bar(rig.bars[2], mount.call(-HUB_SPREAD, -MOUNT_SPREAD), hub_lower)
	_place_bar(rig.bars[3], mount.call(-HUB_SPREAD, MOUNT_SPREAD), hub_lower)
	_place_bar(rig.bars[4], hub_upper, hub_lower)

	# Coil-over on the axle line between the wishbones: tilts and changes
	# length as the wheel moves, identical whichever side is up.
	var shock_outer := wheel + Vector3(-side * HUB_INSET, 0.0, 0.0)
	var shock_inner: Vector3 = mount.call(0.0, 0.0)
	shock_inner.x = _chassis.transform.origin.x + side * SHOCK_MOUNT_X
	_place_bar(rig.damper, shock_inner, shock_outer)
	_place_bar(rig.spring, shock_inner, shock_outer, false)


## Stretches a unit-length mesh along Y between two points. Centred meshes
## (cylinders) go at the midpoint; meshes starting at y = 0 (the spring) at `from`.
func _place_bar(bar: MeshInstance3D, from: Vector3, to: Vector3, centred := true) -> void:
	var along := to - from
	var length := along.length()
	if length < 0.001:
		return
	var y := along / length
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	bar.transform = Transform3D(Basis(x, y * length, z), (from + to) * 0.5 if centred else from)


func _instance(mesh: Mesh) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	add_child(instance)
	return instance
