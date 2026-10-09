extends GdUnitTestSuite
## Behavioural tests for car physics, run against the offline sandbox scene
## (arena + car). Positions refer to the arena layout in scenes/arena.tscn;
## the floor is bumpy, so heights are measured above the terrain under the car.

const SANDBOX_SCENE := "res://scenes/sandbox.tscn"
const PHYSICS_FPS := 60

var _runner: GdUnitSceneRunner
var _car: Car
var _terrain: ArenaTerrain


func before_test() -> void:
	_runner = scene_runner(SANDBOX_SCENE)
	_car = _runner.scene().get_node("Car")
	_terrain = _runner.scene().get_node("Arena/Terrain")
	_car.is_locally_controlled = false


func test_car_settles_on_suspension_at_rest() -> void:
	await _step(seconds(2))

	assert_float(_height_above_ground()).is_between(0.6, 1.0)
	assert_float(_up()).is_greater(0.99)
	assert_float(_car.linear_velocity.length()).is_less(0.05)


func test_car_accelerates_straight() -> void:
	_car.input.throttle = 1.0
	await _step(seconds(2))

	assert_float(_forward_speed()).is_greater(20.0)
	assert_float(absf(_car.global_position.x)).is_less(0.5)
	assert_float(_up()).is_greater(0.99)


func test_car_jumps_ramp_and_lands_on_wheels() -> void:
	_car.input.throttle = 1.0
	var max_height := [0.0]
	await _step(seconds(5), func(): max_height[0] = maxf(max_height[0], _car.global_position.y))

	assert_float(max_height[0]).is_greater(4.0)
	assert_float(_height_above_ground()).is_less(1.2)
	assert_float(_up()).is_greater(0.8)  # on its wheels (may rest on the sloped wall berm)


func test_car_reaches_high_speed_on_open_ground() -> void:
	_place(Vector3(48, 1.4, 47), PI / 2)  # heading -X along an open lane
	_car.input.throttle = 1.0
	await _step(seconds(4))

	assert_float(_forward_speed()).is_greater(34.0)


func test_rear_steer_gives_tight_low_speed_turns() -> void:
	_place(Vector3(-30, 1.4, 35), 0.0)
	_car.input.steer = 1.0
	var cruise := func(): _car.input.throttle = 1.0 if _forward_speed() < 8.0 else 0.0
	await _step(seconds(1.5), cruise)
	var bounds := AABB(_car.global_position, Vector3.ZERO)
	await _step(
		seconds(4),
		func():
			cruise.call()
			bounds = bounds.expand(_car.global_position)
	)

	assert_float(maxf(bounds.size.x, bounds.size.z)).is_less(16.0)


func test_handbrake_into_a_turn_starts_a_drift_that_recovers() -> void:
	_clear_obstacles()
	_place(Vector3(48, 1.4, 47), PI / 2)
	_car.input.throttle = 1.0
	await _step(seconds(1.5))
	_car.input.steer = 1.0
	_car.input.handbrake = true
	await _step(seconds(0.5))
	_car.input.handbrake = false
	_car.input.steer = -0.3  # countersteer, stay on the throttle
	var max_slip := [0.0]
	await _step(seconds(1), func(): max_slip[0] = maxf(max_slip[0], absf(_slip_degrees())))
	_car.input.steer = 0.0
	await _step(seconds(1.5))

	assert_float(max_slip[0]).is_greater(12.0)  # it actually slid
	assert_float(max_slip[0]).is_less(60.0)  # ...without spinning out
	assert_float(absf(_slip_degrees())).is_less(5.0)  # grip came back
	assert_float(_forward_speed()).is_greater(20.0)


func test_full_lock_launch_does_not_spin() -> void:
	# Standing start, full steering lock, full throttle: a tight stable arc,
	# not a spin.
	_clear_obstacles()
	_place(Vector3(-20, 1.4, 20), 0.0)
	_car.input.throttle = 1.0
	_car.input.steer = 1.0
	var max_slip := [0.0]
	await _step(seconds(3), func(): max_slip[0] = maxf(max_slip[0], absf(_slip_degrees())))

	assert_float(max_slip[0]).is_less(20.0)


func test_fast_cornering_without_handbrake_keeps_grip() -> void:
	_place(Vector3(48, 1.4, 47), PI / 2)
	_car.input.throttle = 1.0
	await _step(seconds(2))
	_car.input.steer = 1.0
	var max_slip := [0.0]
	await _step(seconds(1), func(): max_slip[0] = maxf(max_slip[0], absf(_slip_degrees())))

	assert_float(max_slip[0]).is_less(15.0)
	assert_float(_car._drift).is_equal(0.0)


func test_cornering_on_flat_ground_does_not_roll_car() -> void:
	_place(Vector3(-35, 1.2, 40), -PI / 2)  # heading +X, away from ramp/obstacles
	_car.input.throttle = 1.0
	await _step(seconds(1.5))
	_car.input.steer = -1.0
	var min_up := [1.0]
	await _step(seconds(2), func(): min_up[0] = minf(min_up[0], _up()))

	assert_float(min_up[0]).is_greater(0.9)


func test_car_drives_on_its_roof() -> void:
	_place(Vector3(0, 2, 30), 0.0, PI)
	_car.input.throttle = 1.0
	await _step(seconds(2))

	assert_float(_up()).is_less(-0.95)
	assert_float(_forward_speed()).is_greater(15.0)


func test_car_on_its_side_tips_over() -> void:
	_car.auto_flip_delay = 999.0
	_place(Vector3(0, 1.8, 30), 0.0, deg_to_rad(85))
	await _step(seconds(3))

	assert_float(absf(_up())).is_greater(0.95)


func test_reset_puts_car_back_on_wheels() -> void:
	_place(Vector3(0, 2, 30), 0.0, PI)
	await _step(seconds(1))
	_car.input.reset = true
	await _step(1)
	_car.input.reset = false
	await _step(seconds(1))

	assert_float(_up()).is_greater(0.99)


func seconds(value: float) -> int:
	return roundi(value * PHYSICS_FPS)


func _step(frames: int, on_tick := Callable()) -> void:
	for i in frames:
		await get_tree().physics_frame
		if on_tick.is_valid():
			on_tick.call()


## Removes the container stacks so manoeuvres measured over a wide area don't
## end in a crash.
func _clear_obstacles() -> void:
	for group in ["StackNE", "PairNW", "CornerSE", "TowerSW"]:
		_runner.scene().get_node("Arena/" + group).free()


func _place(position: Vector3, yaw: float, roll := 0.0) -> void:
	_car.global_transform = Transform3D(Basis.from_euler(Vector3(0, yaw, roll)), position)
	_car.linear_velocity = Vector3.ZERO
	_car.angular_velocity = Vector3.ZERO


## Axle height above the terrain directly below the car (~0.8 m at rest).
func _height_above_ground() -> float:
	var p := _car.global_position
	return p.y - _terrain.height_at(p.x, p.z)


func _slip_degrees() -> float:
	var forward := -_car.global_basis.z
	var right := forward.cross(Vector3.UP)
	var along := maxf(absf(_car.linear_velocity.dot(forward)), 0.5)
	return rad_to_deg(atan2(_car.linear_velocity.dot(right), along))


func _up() -> float:
	return _car.global_basis.y.y


func _forward_speed() -> float:
	return _car.linear_velocity.dot(-_car.global_basis.z)
