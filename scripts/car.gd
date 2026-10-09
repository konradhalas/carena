class_name Car
extends RigidBody3D
## Raycast-suspension car. Front faces -Z, origin sits on the axle line.
##
## Each wheel is a ray from its axle anchor towards the ground: a spring-damper
## holds the body up, and per-wheel drive/grip forces move it. The body is
## vertically symmetric around the axles and wheels stick out on both sides, so
## when the car lands on its roof the rays simply flip and it keeps driving.

const WHEEL_COUNT := 4
const FRONT_WHEELS: Array[int] = [0, 1]

@export_group("Engine")
@export var max_speed := 32.0
@export var max_reverse_speed := 12.0
@export var engine_acceleration := 20.0  ## m/s² at standstill
@export var brake_deceleration := 30.0
@export var coast_deceleration := 3.0

@export_group("Steering")
@export var max_steer_angle := 0.5  ## rad at low speed
@export var high_speed_steer_angle := 0.18  ## rad at max_speed

@export_group("Tires")
@export var wheel_radius := 0.6
@export var grip := 0.6  ## 0..1, share of sideways slip removed per tick
@export var handbrake_rear_grip := 0.08
@export var tire_friction := 1.6  ## caps grip/drive force at this × load

@export_group("Suspension")
@export var suspension_travel := 0.35
@export var spring_stiffness := 35000.0
@export var spring_damping := 3500.0

@export_group("Recovery")
## Torque that tips a car resting on its side over onto wheels or roof
## (both are drivable), so it doesn't balance on its flat side.
@export var side_tip_torque := 25000.0
@export var auto_flip_delay := 2.0  ## seconds stuck with no wheel on the ground

@export_group("")
## When true, the car reads input from this machine's keyboard/gamepad.
@export var is_locally_controlled := true

var input := CarInput.new()

var _anchors: Array[Vector3] = []  ## local axle points, FL, FR, RL, RR
var _stuck_time := 0.0
var _flip_requested := false

@onready var _wheel_pivots: Array[Node3D] = [
	$Visual/WheelFL, $Visual/WheelFR, $Visual/WheelRL, $Visual/WheelRR
]
@onready var _wheels: Array[Wheel] = [
	$Visual/WheelFL/Wheel, $Visual/WheelFR/Wheel, $Visual/WheelRL/Wheel, $Visual/WheelRR/Wheel
]


func _ready() -> void:
	for pivot in _wheel_pivots:
		_anchors.append(pivot.position)


func _physics_process(delta: float) -> void:
	if is_locally_controlled:
		input = CarInput.from_local_devices()

	# Rays point to whichever side of the car faces the ground.
	var flip_sign := 1.0 if global_basis.y.y >= 0.0 else -1.0
	var wheel_up := global_basis.y * flip_sign
	var forward := -global_basis.z
	var speed := linear_velocity.dot(forward)
	var steer_angle := (
		-input.steer
		* lerpf(max_steer_angle, high_speed_steer_angle, clampf(absf(speed) / max_speed, 0.0, 1.0))
	)
	var mass_per_wheel := mass / WHEEL_COUNT
	var resting_load := mass_per_wheel * get_gravity().length()
	var grounded := 0

	for i in WHEEL_COUNT:
		var is_front := i in FRONT_WHEELS
		var anchor := global_transform * _anchors[i]
		var ray_length := suspension_travel + wheel_radius
		var hit := _cast(anchor, anchor - wheel_up * ray_length)
		var hit_distance := ray_length if hit.is_empty() else anchor.distance_to(hit.position)
		_place_wheel_visual(
			i, flip_sign, hit_distance - wheel_radius, steer_angle if is_front else 0.0, delta
		)
		if hit.is_empty():
			continue
		grounded += 1

		var offset := anchor - global_position
		var point_velocity := linear_velocity + angular_velocity.cross(offset)

		# Suspension: spring pushes along the ground-facing axis, never pulls.
		var compression := ray_length - hit_distance
		var spring := spring_stiffness * compression - spring_damping * point_velocity.dot(wheel_up)
		spring = maxf(spring, 0.0)
		apply_force(wheel_up * spring, offset)

		var wheel_forward := forward.rotated(wheel_up, steer_angle) if is_front else forward
		var wheel_right := wheel_forward.cross(wheel_up)
		var max_tire_force := tire_friction * maxf(spring, resting_load * 0.25)

		# Sideways grip. Applied at the axle (≈ centre of mass), so cornering
		# alone doesn't roll the car — flips come from terrain, not turning.
		var wheel_grip := handbrake_rear_grip if input.handbrake and not is_front else grip
		var lateral := -point_velocity.dot(wheel_right) * wheel_grip * mass_per_wheel / delta
		apply_force(wheel_right * clampf(lateral, -max_tire_force, max_tire_force), offset)

		var longitudinal := _longitudinal_force(
			point_velocity.dot(wheel_forward), speed, mass_per_wheel, delta
		)
		apply_force(wheel_forward * clampf(longitudinal, -max_tire_force, max_tire_force), offset)

	if grounded == 0 and get_contact_count() > 0:
		_tip_off_side()
	_update_recovery(grounded, delta)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not _flip_requested:
		return
	_flip_requested = false
	var heading := -state.transform.basis.z
	heading.y = 0.0
	if heading.length_squared() < 0.01:
		heading = Vector3.FORWARD
	state.transform = Transform3D(
		Basis.looking_at(heading.normalized(), Vector3.UP),
		state.transform.origin + Vector3.UP * 1.5
	)
	state.linear_velocity = Vector3.ZERO
	state.angular_velocity = Vector3.ZERO


func _longitudinal_force(
	wheel_speed: float, car_speed: float, mass_per_wheel: float, delta: float
) -> float:
	if input.handbrake or is_zero_approx(input.throttle):
		var deceleration := brake_deceleration if input.handbrake else coast_deceleration
		# Never push past zero within a tick, or the car jitters at rest.
		var stopping := absf(wheel_speed) * mass_per_wheel / delta
		return -signf(wheel_speed) * minf(deceleration * mass_per_wheel, stopping)

	var is_braking := signf(input.throttle) != signf(wheel_speed) and absf(wheel_speed) > 0.5
	if is_braking:
		return -signf(wheel_speed) * brake_deceleration * mass_per_wheel

	var limit := max_speed if input.throttle > 0.0 else max_reverse_speed
	var headroom := clampf(1.0 - pow(absf(car_speed) / limit, 2.0), 0.0, 1.0)
	return input.throttle * engine_acceleration * mass_per_wheel * headroom


func _tip_off_side() -> void:
	var up := global_basis.y
	var target_up := Vector3.UP if up.y >= 0.0 else Vector3.DOWN
	var axis := up.cross(target_up)
	if axis.length_squared() < 0.0001:
		return
	apply_torque(axis.normalized() * side_tip_torque)


func _update_recovery(grounded_wheels: int, delta: float) -> void:
	var stuck := grounded_wheels == 0 and linear_velocity.length() < 1.0
	_stuck_time = _stuck_time + delta if stuck else 0.0
	if input.reset or _stuck_time > auto_flip_delay:
		_stuck_time = 0.0
		_flip_requested = true


func _cast(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query)


func _place_wheel_visual(
	i: int, flip_sign: float, extension: float, steer_angle: float, delta: float
) -> void:
	var pivot := _wheel_pivots[i]
	pivot.position = _anchors[i] + Vector3.DOWN * flip_sign * extension
	pivot.rotation.y = steer_angle * flip_sign
	_wheels[i].roll(linear_velocity.dot(-global_basis.z) * flip_sign * delta)
