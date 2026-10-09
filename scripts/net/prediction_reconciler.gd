class_name PredictionReconciler
extends RefCounted
## Client-side prediction bookkeeping for the locally controlled car.
##
## The client simulates its own car immediately with its own input and
## remembers the resulting state per input sequence number. The server
## reports its authoritative state together with the last input sequence it
## applied; the difference to what we predicted for that same input is the
## misprediction. It is folded into the body gradually (or at once when
## large, e.g. after a respawn), and the newer history is shifted by it so the
## same error is never corrected twice.
##
## There is no rewind-and-replay: Godot can't step one rigid body on its own.
## Shifting history approximates a replay well for small errors.

const HISTORY_SIZE := 120

## Share of the outstanding error removed per physics tick.
var correction_rate := 0.15
## Errors larger than this (m) snap immediately instead of blending.
var snap_distance := 4.0

var _history := {}  # input seq -> State
var _offset := Vector3.ZERO
var _rotation := Quaternion.IDENTITY
var _linear := Vector3.ZERO
var _angular := Vector3.ZERO
var _snap := false


class State:
	var transform: Transform3D
	var linear: Vector3
	var angular: Vector3


class Step:
	var offset: Vector3
	var rotation: Quaternion
	var linear: Vector3
	var angular: Vector3
	var snapped: bool


func record(seq: int, transform: Transform3D, linear: Vector3, angular: Vector3) -> void:
	var state := State.new()
	state.transform = transform
	state.linear = linear
	state.angular = angular
	_history[seq] = state
	_history.erase(seq - HISTORY_SIZE)


func reconcile(seq: int, transform: Transform3D, linear: Vector3, angular: Vector3) -> void:
	var predicted: State = _history.get(seq)
	if predicted == null:
		return
	var offset := transform.origin - predicted.transform.origin
	var rotation := (
		transform.basis.get_rotation_quaternion()
		* predicted.transform.basis.get_rotation_quaternion().inverse()
	)
	var linear_error := linear - predicted.linear
	var angular_error := angular - predicted.angular

	for key: int in _history.keys():
		if key <= seq:
			_history.erase(key)
			continue
		var later: State = _history[key]
		later.transform.origin += offset
		later.transform.basis = (Basis(rotation) * later.transform.basis).orthonormalized()
		later.linear += linear_error
		later.angular += angular_error

	_offset += offset
	_rotation = (rotation * _rotation).normalized()
	_linear += linear_error
	_angular += angular_error
	if offset.length() > snap_distance:
		_snap = true


## This tick's share of the outstanding correction; consumes it.
func next_step() -> Step:
	var share := 1.0 if _snap else correction_rate
	var step := Step.new()
	step.offset = _offset * share
	step.rotation = Quaternion.IDENTITY.slerp(_rotation, share)
	step.linear = _linear * share
	step.angular = _angular * share
	step.snapped = _snap
	_offset -= step.offset
	_rotation = (step.rotation.inverse() * _rotation).normalized()
	_linear -= step.linear
	_angular -= step.angular
	_snap = false
	return step


## Applies this tick's correction to the body. Returns true when it snapped,
## so the caller can reset render interpolation.
func apply(state: PhysicsDirectBodyState3D) -> bool:
	var step := next_step()
	var transform := state.transform
	transform.origin += step.offset
	transform.basis = (Basis(step.rotation) * transform.basis).orthonormalized()
	state.transform = transform
	state.linear_velocity += step.linear
	state.angular_velocity += step.angular
	return step.snapped
