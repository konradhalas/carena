extends Camera3D
## Chase camera that smoothly follows a target from behind.

## Assigning a new target snaps the camera to it on the next physics frame
## (the target may not be in the tree yet, e.g. right after spawning).
@export var target: Node3D:
	set(value):
		if target and target.has_signal("damaged"):
			target.damaged.disconnect(_on_target_damaged)
		target = value
		_snap_pending = true
		_previous_velocity = Vector3.ZERO
		if target and target.has_signal("damaged"):
			target.damaged.connect(_on_target_damaged)
@export var offset := Vector3(0.0, 5.0, 10.0)
@export var look_height := 1.5
@export var follow_speed := 6.0

@export_group("Feel")
@export var base_fov := 70.0
@export var speed_fov := 12.0  ## extra degrees at top speed
@export var top_speed := 32.0
@export var shake_offset := 0.5  ## screen shift at full trauma
@export var shake_roll := 0.06  ## rad
@export var trauma_decay := 1.5  ## per second
## Acceleration above this (m/s²) — landings, crashes, explosions — shakes.
@export var shake_accel_threshold := 30.0
@export var trauma_per_accel := 0.004
@export var trauma_per_damage := 0.02

var _heading := Vector3.FORWARD
var _snap_pending := true
var _trauma := 0.0
var _shake_time := 0.0
var _previous_velocity := Vector3.ZERO
var _noise := FastNoiseLite.new()


func _ready() -> void:
	top_level = true
	fov = base_fov
	_noise.frequency = 1.2


## Adds camera shake (0..1, accumulates, decays over time).
func add_trauma(amount: float) -> void:
	_trauma = minf(_trauma + amount, 1.0)


func _physics_process(delta: float) -> void:
	if not target or not target.is_inside_tree():
		return
	if _snap_pending:
		_snap_pending = false
		global_position = _desired_position()
	global_position = global_position.lerp(
		_desired_position(), clampf(follow_speed * delta, 0.0, 1.0)
	)
	look_at(target.global_position + Vector3.UP * look_height)
	_apply_feel(delta)


func _apply_feel(delta: float) -> void:
	var velocity := Vector3.ZERO
	if target is RigidBody3D:
		velocity = (target as RigidBody3D).linear_velocity
	var accel := (velocity - _previous_velocity).length() / maxf(delta, 0.0001)
	if _previous_velocity != Vector3.ZERO:
		add_trauma(maxf(accel - shake_accel_threshold, 0.0) * trauma_per_accel)
	_previous_velocity = velocity

	var speed_ratio := clampf(velocity.length() / top_speed, 0.0, 1.0)
	fov = lerpf(fov, base_fov + speed_fov * speed_ratio, clampf(3.0 * delta, 0.0, 1.0))

	# Shake strength grows with trauma squared: small knocks stay subtle.
	_trauma = maxf(_trauma - trauma_decay * delta, 0.0)
	_shake_time += delta * 60.0
	var shake := _trauma * _trauma
	h_offset = shake_offset * shake * _noise.get_noise_2d(_shake_time, 0.0)
	v_offset = shake_offset * shake * _noise.get_noise_2d(0.0, _shake_time)
	rotate_object_local(
		Vector3.FORWARD, shake_roll * shake * _noise.get_noise_2d(_shake_time, 50.0)
	)


func _on_target_damaged(amount: float) -> void:
	add_trauma(amount * trauma_per_damage)


func _desired_position() -> Vector3:
	# Follow the target's heading on the ground plane only, so the camera stays
	# upright and steady while the car pitches, rolls or tumbles.
	var heading := -target.global_basis.z
	heading.y = 0.0
	if heading.length_squared() > 0.01:
		_heading = heading.normalized()
	return target.global_position + Basis.looking_at(_heading) * offset
