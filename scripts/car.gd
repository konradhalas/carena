class_name Car
extends RigidBody3D
## Raycast-suspension car. Front faces -Z, origin sits on the axle line.
##
## Each wheel is a ray from its axle anchor towards the ground: a spring-damper
## holds the body up, and per-wheel drive/grip forces move it. The body is
## vertically symmetric around the axles and wheels stick out on both sides, so
## when the car lands on its roof the rays simply flip and it keeps driving.
##
## Networking: the server is authoritative. Each client simulates its own car
## immediately (prediction) and sends numbered inputs to the server; the
## server replicates state (net_* properties via the "Sync" node) tagged with
## its physics tick and the last input it applied. The owning client
## reconciles against that (PredictionReconciler); other clients render the
## car slightly in the past, interpolating between snapshots (SnapshotBuffer).
## Offline (sandbox, tests) the default OfflineMultiplayerPeer makes this peer
## the server, so the same code runs unchanged.

signal destroyed
## Health went down (on every peer, as health replicates). Used for feedback.
signal damaged(amount: float)

const WHEEL_COUNT := 4
const WRECK_COLOR := Color(0.07, 0.07, 0.07)
const BODY_BEVEL := 0.12
const PAINT := preload("res://materials/car_paint.tres")
## Liveries as [base, stripes, accent]; each car picks one from its name.
const LIVERIES: Array[Array] = [
	[Color(0.75, 0.08, 0.06), Color(0.92, 0.92, 0.9), Color(0.05, 0.05, 0.06)],
	[Color(0.06, 0.2, 0.6), Color(0.92, 0.92, 0.9), Color(0.95, 0.45, 0.05)],
	[Color(0.95, 0.68, 0.05), Color(0.05, 0.05, 0.06), Color(0.05, 0.05, 0.06)],
	[Color(0.08, 0.42, 0.2), Color(0.92, 0.92, 0.9), Color(0.05, 0.05, 0.06)],
	[Color(0.95, 0.36, 0.04), Color(0.05, 0.05, 0.06), Color(0.92, 0.92, 0.9)],
	[Color(0.35, 0.1, 0.55), Color(0.95, 0.8, 0.1), Color(0.05, 0.05, 0.06)],
	[Color(0.86, 0.86, 0.85), Color(0.75, 0.06, 0.05), Color(0.05, 0.05, 0.06)],
	[Color(0.05, 0.05, 0.06), Color(0.5, 0.95, 0.1), Color(0.5, 0.95, 0.1)],
	[Color(0.0, 0.48, 0.52), Color(0.92, 0.92, 0.9), Color(0.05, 0.05, 0.06)],
]
## Each input packet also carries this many previous inputs, so a lost packet
## doesn't leave a gap in the server's input sequence.
const INPUT_REDUNDANCY := 3
## The server consumes exactly one queued input per physics tick (so its steps
## line up with the client's prediction); beyond this backlog it skips ahead
## to keep input latency low.
const MAX_INPUT_QUEUE := 4
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

@export_group("Network")
@export var max_extrapolation := 0.25  ## seconds to dead-reckon remote cars past the last snapshot
@export var prediction_correction_rate := 0.15  ## share of own-car error fixed per tick
@export var prediction_snap_distance := 4.0  ## own-car errors above this (m) snap at once

@export_group("")
## When true, the car reads input from this machine's keyboard/gamepad.
@export var is_locally_controlled := true

## Peer that drives this car; only its input is accepted by the server.
var owner_peer_id := 1
var input := CarInput.new()

# Server-authoritative state, replicated to clients by the "Sync" node.
var net_transform := Transform3D()
var net_velocity := Vector3.ZERO
var net_angular_velocity := Vector3.ZERO
var net_steer := 0.0
var net_tick := 0  ## server physics tick the net_* state belongs to
var net_input_seq := 0  ## last owner input the server had applied in that state
var health := max_health:
	set(value):
		var lost := health - value
		health = value
		if lost > 0.0:
			damaged.emit(lost)
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
var _input_seq := 0  ## owning client: sequence number of the input being applied
var _sent_inputs: Array[PackedFloat32Array] = []  ## owning client: newest last
var _last_received_seq := 0  ## server: newest input seq received from the owner
var _applied_seq := 0  ## server: input seq used during the last physics step
var _input_queue: Array[Array] = []  ## server: [seq, CarInput], oldest first
var _reset_pending := false
var _snapshots := SnapshotBuffer.new()
var _prediction := PredictionReconciler.new()
var _fire_cooldown := 0.0
var _respawn_timer := 0.0
var _respawn_requested := false
var _bot: BotDriver
var _effects: CarEffects
var _suspension: CarSuspension
var _paint: ShaderMaterial

@onready var _wheel_pivots: Array[Node3D] = [
	$Visual/WheelFL, $Visual/WheelFR, $Visual/WheelRL, $Visual/WheelRR
]
@onready var _wheels: Array[Wheel] = [
	$Visual/WheelFL/Wheel, $Visual/WheelFR/Wheel, $Visual/WheelRL/Wheel, $Visual/WheelRR/Wheel
]
## On the front bumper at axle height — the car's centre of symmetry, so it
## fires the same whether the car is on its wheels or its roof.
@onready var _muzzle: Marker3D = $Muzzle
@onready var _body_mesh: MeshInstance3D = $Visual/Chassis/Body


func _ready() -> void:
	add_to_group("cars")
	var box := _body_mesh.mesh as BoxMesh
	if box:
		_body_mesh.mesh = MeshBuilder.chamfered_box(box.size, BODY_BEVEL, box.material)
	_apply_livery()
	if DisplayServer.get_name() != "headless":
		_effects = CarEffects.new()
		add_child(_effects)
		_suspension = CarSuspension.new()
		$Visual.add_child(_suspension)
		_suspension.setup($Visual/Chassis, _wheel_pivots)
	for pivot in _wheel_pivots:
		_anchors.append(pivot.position)
	net_transform = global_transform
	health = max_health
	if spawn_transform == Transform3D():
		spawn_transform = global_transform
	if not multiplayer.is_server():
		$Sync.synchronized.connect(_on_server_state)
		_prediction.correction_rate = prediction_correction_rate
		_prediction.snap_distance = prediction_snap_distance
		if not _is_predicted():
			# Remote cars on clients never simulate; they replay server snapshots.
			freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			freeze = true


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_server_tick(delta)
	elif _is_predicted():
		_predicted_tick(delta)
	else:
		_follow_snapshots()
		_update_wheels_visual_only(delta)
	if _suspension:
		var velocity := (
			linear_velocity if multiplayer.is_server() or _is_predicted() else net_velocity
		)
		_suspension.update(delta, velocity, global_basis)


func _server_tick(delta: float) -> void:
	# The body now holds the result of the last physics step: publish it with
	# the input that produced it, then apply the newest input for the next step.
	net_transform = global_transform
	net_velocity = linear_velocity
	net_angular_velocity = angular_velocity
	net_tick = Engine.get_physics_frames()
	net_input_seq = _applied_seq

	if is_locally_controlled:
		input = _read_local_input(delta)
	else:
		_consume_queued_input()
	if is_destroyed:
		input = CarInput.new()  # wrecks don't drive or shoot
		_update_respawn(delta)
	_update_weapon(delta)
	_simulate(delta)
	net_steer = input.steer


func _predicted_tick(delta: float) -> void:
	_prediction.record(_input_seq, global_transform, linear_velocity, angular_velocity)
	_input_seq += 1
	input = _read_local_input(delta)
	_sent_inputs.append(input.encode())
	if _sent_inputs.size() > INPUT_REDUNDANCY:
		_sent_inputs.pop_front()
	var packed := PackedFloat32Array()
	for encoded in _sent_inputs:
		packed.append_array(encoded)
	_submit_inputs.rpc_id(1, _input_seq, packed)
	if input.reset:
		_request_reset.rpc_id(1)
	if is_destroyed:
		input = CarInput.new()
	_simulate(delta)


## Owning client simulates its car locally; everyone else only replays it.
func _is_predicted() -> bool:
	return is_locally_controlled and not multiplayer.is_server()


func _on_server_state() -> void:
	NetClock.observe_server_tick(net_tick)
	if _is_predicted():
		_prediction.reconcile(net_input_seq, net_transform, net_velocity, net_angular_velocity)
	else:
		_snapshots.push(net_tick, net_transform, net_velocity)


func _read_local_input(delta: float) -> CarInput:
	if not CarInput.bot_mode:
		return CarInput.from_local_devices()
	if _bot == null:
		_bot = BotDriver.new()
	return _bot.drive(self, delta)


## Owner sends its newest input (seq) plus the ones before it, oldest first.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func _submit_inputs(newest_seq: int, packed: PackedFloat32Array) -> void:
	if multiplayer.get_remote_sender_id() != owner_peer_id or packed.size() % 3 != 0:
		return
	var count := packed.size() / 3
	for i in count:
		var seq := newest_seq - (count - 1 - i)
		if seq > _last_received_seq:
			_last_received_seq = seq
			_input_queue.append([seq, CarInput.decode(packed, i * 3)])


## Server: take the next input in sequence; when starved, keep the last one.
func _consume_queued_input() -> void:
	if _input_queue.is_empty():
		return
	while _input_queue.size() > MAX_INPUT_QUEUE:
		_input_queue.pop_front()
	var entry: Array = _input_queue.pop_front()
	_applied_seq = entry[0]
	input = entry[1]


@rpc("any_peer", "call_remote", "reliable")
func _request_reset() -> void:
	if multiplayer.get_remote_sender_id() == owner_peer_id:
		_reset_pending = true


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


## Picks this car's colours from its name (the peer id in a match), so every
## peer paints it the same without sending anything over the network.
func _apply_livery() -> void:
	var livery: Array = LIVERIES[absi(String(name).hash()) % LIVERIES.size()]
	_paint = PAINT.duplicate() as ShaderMaterial
	_paint.set_shader_parameter("base_color", livery[0])
	_paint.set_shader_parameter("stripe_color", livery[1])
	_paint.set_shader_parameter("accent_color", livery[2])
	if not is_destroyed:
		_body_mesh.material_override = _paint


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
		_body_mesh.material_override = _paint


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
	if _is_predicted() and _prediction.apply(state):
		reset_physics_interpolation.call_deferred()
	if _respawn_requested:
		_respawn_requested = false
		_flip_requested = false
		state.transform = spawn_transform
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		reset_physics_interpolation.call_deferred()
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
	if input.reset or _reset_pending or _stuck_time > auto_flip_delay:
		_stuck_time = 0.0
		_flip_requested = true
		_reset_pending = false


func _follow_snapshots() -> void:
	var max_ticks := max_extrapolation * Engine.physics_ticks_per_second
	var sampled: Variant = _snapshots.sample(NetClock.render_tick(), max_ticks)
	if sampled != null:
		global_transform = sampled


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
	var velocity := linear_velocity if multiplayer.is_server() or _is_predicted() else net_velocity
	_wheels[i].roll(velocity.dot(-global_basis.z) * flip_sign * delta)
	if _effects:
		var wheel_up := global_basis.y * flip_sign
		var contact := global_transform * _anchors[i] - wheel_up * (extension + wheel_radius)
		var grounded := extension < suspension_travel - 0.001
		_effects.wheel_contact(i, grounded, contact, wheel_up, velocity, global_basis.x)
