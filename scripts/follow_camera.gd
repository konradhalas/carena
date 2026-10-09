extends Camera3D
## Chase camera that smoothly follows a target from behind.

@export var target: Node3D
@export var offset := Vector3(0.0, 5.0, 10.0)
@export var look_height := 1.5
@export var follow_speed := 6.0

var _heading := Vector3.FORWARD


func _ready() -> void:
	top_level = true
	if target:
		global_position = _desired_position()


func _physics_process(delta: float) -> void:
	if not target:
		return
	global_position = global_position.lerp(_desired_position(), clampf(follow_speed * delta, 0.0, 1.0))
	look_at(target.global_position + Vector3.UP * look_height)


func _desired_position() -> Vector3:
	# Follow the target's heading on the ground plane only, so the camera stays
	# upright and steady while the car pitches, rolls or tumbles.
	var heading := -target.global_basis.z
	heading.y = 0.0
	if heading.length_squared() > 0.01:
		_heading = heading.normalized()
	return target.global_position + Basis.looking_at(_heading) * offset
