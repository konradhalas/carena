class_name BotDriver
extends RefCounted
## Minimal auto-driver: chases the nearest living car and shoots when it is
## lined up; backs out when stuck. Used for unattended clients (--bot) in
## smoke and load tests, and a starting point for AI opponents.

const AIM_TOLERANCE := 0.12  ## rad either side of dead ahead to open fire
const FIRE_RANGE := 70.0
const STUCK_SPEED := 2.0
const STUCK_TIME := 1.0
const REVERSE_TIME := 1.2

var _stuck_time := 0.0
var _reverse_time := 0.0
var _last_steer := 0.0


func drive(car: Car, delta: float) -> CarInput:
	var input := CarInput.new()
	if _reverse_time > 0.0:
		_reverse_time -= delta
		input.throttle = -1.0
		input.steer = -_last_steer
		return input

	_stuck_time = _stuck_time + delta if car.linear_velocity.length() < STUCK_SPEED else 0.0
	if _stuck_time > STUCK_TIME:
		_stuck_time = 0.0
		_reverse_time = REVERSE_TIME

	input.throttle = 1.0
	var target := _nearest_enemy(car)
	if target == null:
		return input

	# Work on the ground plane so the maths holds when the car is upside down
	# (steer +1 always turns right in world space, see Car._simulate).
	var forward := -car.global_basis.z
	forward.y = 0.0
	var to_target := target.global_position - car.global_position
	to_target.y = 0.0
	var angle := forward.signed_angle_to(to_target, Vector3.DOWN)  # > 0: target on the right
	input.steer = clampf(angle * 2.0, -1.0, 1.0)
	input.fire = absf(angle) < AIM_TOLERANCE and to_target.length() < FIRE_RANGE
	if to_target.length() < 10.0:
		input.throttle = 0.4
	_last_steer = input.steer
	return input


func _nearest_enemy(car: Car) -> Car:
	var best: Car = null
	var best_distance := INF
	for node in car.get_tree().get_nodes_in_group("cars"):
		var other := node as Car
		if other == car or other.is_destroyed:
			continue
		var distance := car.global_position.distance_squared_to(other.global_position)
		if distance < best_distance:
			best = other
			best_distance = distance
	return best
