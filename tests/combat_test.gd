extends GdUnitTestSuite
## Combat tests in the offline sandbox: the player's car shoots the parked
## "Target" car (at x=12, z=10 in scenes/sandbox.tscn).

const SANDBOX_SCENE := "res://scenes/sandbox.tscn"
const PHYSICS_FPS := 60

var _runner: GdUnitSceneRunner
var _car: Car
var _target: Car


func before_test() -> void:
	_runner = scene_runner(SANDBOX_SCENE)
	_car = _runner.scene().get_node("Car")
	_target = _runner.scene().get_node("Target")
	_car.is_locally_controlled = false
	await _step(seconds(1))  # let both cars settle on their suspension


func test_shots_from_front_bumper_damage_car_ahead() -> void:
	_aim_at_target_from(Vector3(12, 1.2, 30))
	_car.input.fire = true
	await _step(seconds(1))

	assert_float(_target.health).is_less(_target.max_health)
	assert_float(_car.health).is_equal(_car.max_health)


func test_upside_down_car_still_shoots_forward() -> void:
	_aim_at_target_from(Vector3(12, 2.0, 30), PI)
	await _step(seconds(1))
	assert_float(_car.global_basis.y.y).is_less(-0.95)

	_car.input.fire = true
	await _step(seconds(1))

	assert_float(_target.health).is_less(_target.max_health)


func test_destroying_a_car_credits_the_shooter() -> void:
	_target.health = 5.0
	_aim_at_target_from(Vector3(12, 1.2, 30))
	_car.input.fire = true
	await _step(seconds(1))

	assert_bool(_target.is_destroyed).is_true()
	assert_int(_car.kills).is_equal(1)


func test_destroyed_car_respawns_with_full_health() -> void:
	var spawn := _target.spawn_transform.origin
	assert_bool(_target.apply_damage(1000.0)).is_true()
	await _step(seconds(0.5))
	assert_bool(_target.is_destroyed).is_true()

	await _step(seconds(_target.respawn_delay + 1.0))

	assert_bool(_target.is_destroyed).is_false()
	assert_float(_target.health).is_equal(_target.max_health)
	assert_float(_target.global_position.distance_to(spawn)).is_less(1.5)


func test_destroyed_car_cannot_shoot() -> void:
	_car.apply_damage(1000.0)
	_aim_at_target_from(Vector3(12, 1.2, 30))
	_car.input.fire = true
	await _step(seconds(1))

	assert_float(_target.health).is_equal(_target.max_health)


func test_four_hits_destroy_a_car() -> void:
	var projectiles: Projectiles = _runner.scene().get_node("Projectiles")
	for i in 3:
		_target.apply_damage(projectiles.damage)
	assert_bool(_target.is_destroyed).is_false()

	_target.apply_damage(projectiles.damage)

	assert_bool(_target.is_destroyed).is_true()


func test_ammo_runs_out_and_an_empty_cannon_does_not_fire() -> void:
	_aim_at_target_from(Vector3(12, 1.2, 30))
	_car.ammo = 2
	_car.input.fire = true
	await _step(seconds(2))

	assert_int(_car.ammo).is_equal(0)
	var health_after_two := _target.health
	await _step(seconds(1))
	assert_float(_target.health).is_equal(health_after_two)


func test_repair_kit_heals_disappears_and_comes_back() -> void:
	var kit: Pickup = _runner.scene().get_node("Arena/Pickups/RepairS")
	kit.respawn_time = 0.5
	_car.health = 30.0
	_drive_onto(kit)
	await _step(seconds(0.3))

	assert_float(_car.health).is_equal(70.0)
	assert_bool(kit.active).is_false()
	_aim_at_target_from(Vector3(12, 1.2, 30))  # drive off, or it'd be taken again at once
	await _step(seconds(0.6))
	assert_bool(kit.active).is_true()


func test_pickup_stays_when_not_needed() -> void:
	var kit: Pickup = _runner.scene().get_node("Arena/Pickups/RepairS")
	_drive_onto(kit)
	await _step(seconds(0.3))

	assert_bool(kit.active).is_true()


func test_ammo_crate_refills_the_magazine() -> void:
	var crate: Pickup = _runner.scene().get_node("Arena/Pickups/AmmoE")
	_car.ammo = 0
	_drive_onto(crate)
	await _step(seconds(0.3))

	assert_int(_car.ammo).is_equal(crate.ammo_amount)


func seconds(value: float) -> int:
	return roundi(value * PHYSICS_FPS)


func _step(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


## Parks the player's car on a pickup.
func _drive_onto(pickup: Pickup) -> void:
	var at := pickup.global_position + Vector3.UP * 1.0
	_car.global_transform = Transform3D(Basis(), at)
	_car.linear_velocity = Vector3.ZERO


## Places the player's car facing -Z, i.e. straight at the target for x=12.
func _aim_at_target_from(position: Vector3, roll := 0.0) -> void:
	_car.global_transform = Transform3D(Basis.from_euler(Vector3(0, 0, roll)), position)
	_car.linear_velocity = Vector3.ZERO
	_car.angular_velocity = Vector3.ZERO
