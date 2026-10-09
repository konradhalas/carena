class_name Car
extends RigidBody3D
## Raycast-suspension car. Front faces -Z, origin sits on the axle line.
##
## Each wheel is a ray from its axle anchor towards the ground: a spring-damper
## holds the body up, and per-wheel drive/grip forces move it. The body is
## vertically symmetric around the axles and wheels stick out on both sides, so
## when the car lands on its roof the rays simply flip and it keeps driving.
##
## Networking: only the server simulates physics. The owning client sends its
## input to the server; every client receives the car's state through the
## MultiplayerSynchronizer (net_* properties) and smooths towards it. Offline
## (sandbox, tests) the default OfflineMultiplayerPeer makes this peer the server.

signal destroyed

const WHEEL_COUNT := 4
const WRECK_COLOR := Color(0.07, 0.07, 0.07)
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

@export_group("Combat")
@export var max_health := 100.0
@export var fire_interval := 0.14  ## seconds between shots
@export var respawn_delay := 3.0
@export var explosion_impulse := 7.0  ## upward kick on destruction, m/s

@export_group("Network smoothing")
@export var follow_sharpness := 15.0  ## how fast clients converge on server state
@export var max_extrapolation := 0.25  ## seconds to dead-reckon past the last update

@export_group("")
## When true, the car reads input from this machine's keyboard/gamepad.
@export var is_locally_controlled := true

## Peer that drives this car; only its input is accepted by the server.
var owner_peer_id := 1
var input := CarInput.new()

# Server-authoritative state, replicated to clients by the "Sync" node.
var net_transform := Transform3D()
var net_velocity := Vector3.ZERO
var net_steer := 0.0
var health := max_health
var kills := 0
var is_destroyed := false:
	set(value):
		if value == is_destroyed:
			return
		is_destroyed = value
		_show_destroyed_state()

## Where the car comes back after being destroyed (defaults to where it started).
var spawn_transform := Transform3D()

var _anchors: Array[Vector3] = []  ## local axle points, FL, FR, RL, RR
var _stuck_time := 0.0
var _flip_requested := false
var _since_sync := 0.0
var _fire_cooldown := 0.0
var _respawn_timer := 0.0
var _respawn_requested := false
var _bot: BotDriver

@onready var _wheel_pivots: Array[Node3D] = [
	$Visual/WheelFL, $Visual/WheelFR, $Visual/WheelRL, $Visual/WheelRR
]
@onready var _wheels: Array[Wheel] = [
	$Visual/WheelFL/Wheel, $Visual/WheelFR/Wheel, $Visual/WheelRL/Wheel, $Visual/WheelRR/Wheel
]
## On the front bumper at axle height — the car's centre of symmetry, so it
## fires the same whether the car is on its wheels or its roof.
@onready var _muzzle: Marker3D = $Muzzle
@onready var _body_mesh: MeshInstance3D = $Visual/Body


func _ready() -> void:
	add_to_group("cars")
	for pivot in _wheel_pivots:
		_anchors.append(pivot.position)
	net_transform = global_transform
	health = max_health
	if spawn_transform == Transform3D():
		spawn_transform = global_transform
	if not multiplayer.is_server():
		# Clients never simulate: the body just follows replicated state.
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true
		$Sync.synchronized.connect(func(): _since_sync = 0.0)


func _physics_process(delta: float) -> void:
	if is_locally_controlled:
		input = _read_local_input(delta)
		if not multiplayer.is_server():
			_submit_input.rpc_id(1, input.throttle, input.steer, input.handbrake, input.fire)
			if input.reset:
				_request_reset.rpc_id(1)

	if multiplayer.is_server():
		if is_destroyed:
			input = CarInput.new()  # wrecks don't drive or shoot
			_update_respawn(delta)
		_update_weapon(delta)
		_simulate(delta)
		net_transform = global_transform
		net_velocity = linear_velocity
		net_steer = input.steer
	else:
		_follow_server(delta)
		_update_wheels_visual_only(delta)


func _read_local_input(delta: float) -> CarInput:
	if not CarInput.bot_mode:
		return CarInput.from_local_devices()
	if _bot == null:
		_bot = BotDriver.new()
	return _bot.drive(self, delta)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _submit_input(throttle: float, steer: float, handbrake: bool, fire: bool) -> void:
	if multiplayer.get_remote_sender_id() != owner_peer_id:
		return
	input.throttle = clampf(throttle, -1.0, 1.0)
	input.steer = clampf(steer, -1.0, 1.0)
	input.handbrake = handbrake
	input.fire = fire


@rpc("any_peer", "call_remote", "reliable")
func _request_reset() -> void:
	if multiplayer.get_remote_sender_id() == owner_peer_id:
		input.reset = true


## Server only. Returns true when this hit destroyed the car.
func apply_damage(amount: float) -> bool:
	if is_destroyed:
		return false
	health = maxf(health - amount, 0.0)
	if health > 0.0:
		return false
	is_destroyed = true
	_respawn_timer = respawn_delay
	# Throw the wreck up and spin it a little — it's an explosion after all.
	apply_central_impulse(Vector3.UP * explosion_impulse * mass)
	var spin := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
	apply_torque_impulse(spin * mass * 2.0)
	destroyed.emit()
	return true


func _update_weapon(delta: float) -> void:
	_fire_cooldown -= delta
	if not input.fire or _fire_cooldown > 0.0:
		return
	var projectiles := get_tree().get_first_node_in_group("projectiles") as Projectiles
	if projectiles:
		_fire_cooldown = fire_interval
		projectiles.fire(self, _muzzle.global_position, -global_basis.z)


func _update_respawn(delta: float) -> void:
	_respawn_timer -= delta
	if _respawn_timer <= 0.0:
		_respawn_requested = true
		health = max_health
		is_destroyed = false


func _show_destroyed_state() -> void:
	if not is_inside_tree():
		return
	if is_destroyed:
		var wreck := StandardMaterial3D.new()
		wreck.albedo_color = WRECK_COLOR
		wreck.roughness = 1.0
		_body_mesh.material_override = wreck
		Effects.explosion(get_parent(), global_position)
	else:
		_body_mesh.material_override = null


func _simulate(delta: float) -> void:
	var flip_sign := _flip_sign()
	var wheel_up := global_basis.y * flip_sign
	var forward := -global_basis.z
	var speed := linear_velocity.dot(forward)
	var steer_angle := _steer_angle(input.steer, speed)
	var mass_per_wheel := mass / WHEEL_COUNT
	var resting_load := mass_per_wheel * get_gravity().length()
	var grounded := 0

	for i in WHEEL_COUNT:
		var is_front := i in FRONT_WHEELS
		var anchor := global_transform * _anchors[i]
		var ray_length := suspension_travel + wheel_radius
		var hit_distance := _probe_ground(anchor, wheel_up, ray_length)
		_place_wheel_visual(
			i, flip_sign, hit_distance - wheel_radius, steer_angle if is_front else 0.0, delta
		)
		if hit_distance >= ray_length:
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

	if is_destroyed:
		return
	if grounded == 0 and get_contact_count() > 0:
		_tip_off_side()
	_update_recovery(grounded, delta)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _respawn_requested:
		_respawn_requested = false
		_flip_requested = false
		state.transform = spawn_transform
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		return
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
		input.reset = false  # one-shot; remote input persists between packets


func _follow_server(delta: float) -> void:
	_since_sync += delta
	var target := net_transform
	target.origin += net_velocity * minf(_since_sync, max_extrapolation)
	var weight := clampf(follow_sharpness * delta, 0.0, 1.0)
	global_transform = global_transform.interpolate_with(target, weight)


func _update_wheels_visual_only(delta: float) -> void:
	var flip_sign := _flip_sign()
	var wheel_up := global_basis.y * flip_sign
	var steer := input.steer if is_locally_controlled else net_steer
	var steer_angle := _steer_angle(steer, net_velocity.dot(-global_basis.z))
	var ray_length := suspension_travel + wheel_radius
	for i in WHEEL_COUNT:
		var anchor := global_transform * _anchors[i]
		var hit_distance := _probe_ground(anchor, wheel_up, ray_length)
		var wheel_steer := steer_angle if i in FRONT_WHEELS else 0.0
		_place_wheel_visual(i, flip_sign, hit_distance - wheel_radius, wheel_steer, delta)


## Rays point to whichever side of the car faces the ground.
func _flip_sign() -> float:
	return 1.0 if global_basis.y.y >= 0.0 else -1.0


func _steer_angle(steer: float, speed: float) -> float:
	var speed_ratio := clampf(absf(speed) / max_speed, 0.0, 1.0)
	return -steer * lerpf(max_steer_angle, high_speed_steer_angle, speed_ratio)


## Distance from the anchor to the ground along -wheel_up, or ray_length if
## nothing is within reach.
func _probe_ground(anchor: Vector3, wheel_up: Vector3, ray_length: float) -> float:
	var to := anchor - wheel_up * ray_length
	var query := PhysicsRayQueryParameters3D.create(anchor, to, collision_mask, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return ray_length if hit.is_empty() else anchor.distance_to(hit.position)


func _place_wheel_visual(
	i: int, flip_sign: float, extension: float, steer_angle: float, delta: float
) -> void:
	var pivot := _wheel_pivots[i]
	pivot.position = _anchors[i] + Vector3.DOWN * flip_sign * extension
	pivot.rotation.y = steer_angle * flip_sign
	var velocity := linear_velocity if multiplayer.is_server() else net_velocity
	_wheels[i].roll(velocity.dot(-global_basis.z) * flip_sign * delta)
