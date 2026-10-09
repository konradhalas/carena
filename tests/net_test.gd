extends GdUnitTestSuite
## Unit tests for the client-side networking helpers.


func test_snapshot_buffer_interpolates_between_snapshots() -> void:
	var buffer := SnapshotBuffer.new()
	buffer.push(10, _at(Vector3(0, 0, 0)), Vector3.ZERO)
	buffer.push(12, _at(Vector3(2, 0, 0)), Vector3.ZERO)

	var sampled: Transform3D = buffer.sample(11.0, 15.0)

	assert_vector(sampled.origin).is_equal_approx(Vector3(1, 0, 0), Vector3.ONE * 0.001)


func test_snapshot_buffer_extrapolates_only_up_to_limit() -> void:
	var buffer := SnapshotBuffer.new()
	var velocity := Vector3(Engine.physics_ticks_per_second, 0, 0)  # 1 m per tick
	buffer.push(10, _at(Vector3.ZERO), velocity)

	var sampled: Transform3D = buffer.sample(100.0, 5.0)

	assert_vector(sampled.origin).is_equal_approx(Vector3(5, 0, 0), Vector3.ONE * 0.001)


func test_snapshot_buffer_ignores_out_of_order_snapshots() -> void:
	var buffer := SnapshotBuffer.new()
	buffer.push(10, _at(Vector3(0, 0, 0)), Vector3.ZERO)
	buffer.push(14, _at(Vector3(4, 0, 0)), Vector3.ZERO)
	buffer.push(12, _at(Vector3(100, 0, 0)), Vector3.ZERO)  # late, must be dropped

	var sampled: Transform3D = buffer.sample(12.0, 15.0)

	assert_vector(sampled.origin).is_equal_approx(Vector3(2, 0, 0), Vector3.ONE * 0.001)


func test_snapshot_buffer_is_empty_until_first_snapshot() -> void:
	assert_object(SnapshotBuffer.new().sample(5.0, 5.0)).is_null()


func test_reconciler_does_nothing_when_prediction_was_right() -> void:
	var reconciler := PredictionReconciler.new()
	reconciler.record(1, _at(Vector3(5, 0, 0)), Vector3.ONE, Vector3.ZERO)
	reconciler.reconcile(1, _at(Vector3(5, 0, 0)), Vector3.ONE, Vector3.ZERO)

	var step := reconciler.next_step()

	assert_vector(step.offset).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.0001)
	assert_vector(step.linear).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.0001)


func test_reconciler_blends_small_error_in_over_several_ticks() -> void:
	var reconciler := PredictionReconciler.new()
	reconciler.correction_rate = 0.25
	reconciler.record(1, _at(Vector3.ZERO), Vector3.ZERO, Vector3.ZERO)
	reconciler.reconcile(1, _at(Vector3(1, 0, 0)), Vector3.ZERO, Vector3.ZERO)

	var first := reconciler.next_step()
	var total := first.offset
	for i in 60:
		total += reconciler.next_step().offset

	assert_float(first.offset.x).is_equal_approx(0.25, 0.0001)
	assert_bool(first.snapped).is_false()
	assert_vector(total).is_equal_approx(Vector3(1, 0, 0), Vector3.ONE * 0.001)


func test_reconciler_snaps_large_error_at_once() -> void:
	var reconciler := PredictionReconciler.new()
	reconciler.snap_distance = 4.0
	reconciler.record(1, _at(Vector3.ZERO), Vector3.ZERO, Vector3.ZERO)
	reconciler.reconcile(1, _at(Vector3(30, 0, 0)), Vector3.ZERO, Vector3.ZERO)

	var step := reconciler.next_step()

	assert_bool(step.snapped).is_true()
	assert_float(step.offset.x).is_equal_approx(30.0, 0.0001)


func test_reconciler_does_not_correct_the_same_error_twice() -> void:
	var reconciler := PredictionReconciler.new()
	# Predicted ticks 1 and 2, both 1 m short of where the server will put us.
	reconciler.record(1, _at(Vector3(0, 0, 0)), Vector3.ZERO, Vector3.ZERO)
	reconciler.record(2, _at(Vector3(1, 0, 0)), Vector3.ZERO, Vector3.ZERO)
	reconciler.reconcile(1, _at(Vector3(1, 0, 0)), Vector3.ZERO, Vector3.ZERO)
	# Server's tick 2 agrees with tick 1's correction carried forward.
	reconciler.reconcile(2, _at(Vector3(2, 0, 0)), Vector3.ZERO, Vector3.ZERO)

	var total := Vector3.ZERO
	for i in 120:
		total += reconciler.next_step().offset

	assert_vector(total).is_equal_approx(Vector3(1, 0, 0), Vector3.ONE * 0.001)


func test_car_input_survives_network_encoding() -> void:
	var input := CarInput.new()
	input.throttle = -0.5
	input.steer = 0.25
	input.fire = true

	var decoded := CarInput.decode(input.encode())

	assert_float(decoded.throttle).is_equal(-0.5)
	assert_float(decoded.steer).is_equal(0.25)
	assert_bool(decoded.fire).is_true()
	assert_bool(decoded.handbrake).is_false()


func _at(origin: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, origin)
