class_name SnapshotBuffer
extends RefCounted
## Server snapshots of one remote body, tagged with the server physics tick.
##
## Clients render remote bodies slightly in the past (see
## NetClock.render_tick()) and interpolate between the two snapshots around
## that moment, so uneven packet arrival doesn't show as stutter. Only when
## snapshots run out does it extrapolate, briefly, along the last velocity.

const MAX_SNAPSHOTS := 32


class Snapshot:
	var tick: int
	var transform: Transform3D
	var velocity: Vector3


var _snapshots: Array[Snapshot] = []


func push(tick: int, transform: Transform3D, velocity: Vector3) -> void:
	if not _snapshots.is_empty() and tick <= _snapshots[-1].tick:
		return  # duplicate or out of order
	var snapshot := Snapshot.new()
	snapshot.tick = tick
	snapshot.transform = transform
	snapshot.velocity = velocity
	_snapshots.append(snapshot)
	if _snapshots.size() > MAX_SNAPSHOTS:
		_snapshots.pop_front()


func clear() -> void:
	_snapshots.clear()


## Interpolated transform at render_tick, or null when nothing arrived yet.
func sample(render_tick: float, max_extrapolation_ticks: float) -> Variant:
	if _snapshots.is_empty():
		return null
	# Keep only the newest snapshot at or before render_tick and those after it.
	while _snapshots.size() >= 2 and _snapshots[1].tick <= render_tick:
		_snapshots.pop_front()

	var from := _snapshots[0]
	if render_tick <= from.tick:
		return from.transform
	if _snapshots.size() >= 2:
		var to := _snapshots[1]
		var weight := (render_tick - from.tick) / float(to.tick - from.tick)
		return from.transform.interpolate_with(to.transform, weight)

	var ahead := minf(render_tick - from.tick, max_extrapolation_ticks)
	var extrapolated := from.transform
	extrapolated.origin += from.velocity * ahead / Engine.physics_ticks_per_second
	return extrapolated
