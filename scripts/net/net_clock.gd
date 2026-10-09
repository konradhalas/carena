class_name NetClock
extends RefCounted
## Client-side estimate of the server's physics tick.
##
## Kept as an offset from the local physics frame counter, so it advances
## exactly one tick per local physics frame and needs no processing. Each
## received server tick nudges the offset gently, so render time moves
## smoothly even though packets arrive unevenly.

## Remote bodies are rendered this many server ticks in the past, so there are
## almost always two snapshots to interpolate between (~100 ms at 60 Hz).
const INTERPOLATION_DELAY_TICKS := 6.0
## How strongly each received server tick pulls the estimate.
const CORRECTION := 0.05
## Beyond this disagreement (ticks) the estimate jumps instead of drifting.
const RESYNC_THRESHOLD := 30.0

static var _offset := 0.0
static var _started := false


static func observe_server_tick(tick: int) -> void:
	var sample := float(tick - Engine.get_physics_frames())
	if not _started or absf(sample - _offset) > RESYNC_THRESHOLD:
		_offset = sample
		_started = true
	else:
		_offset += (sample - _offset) * CORRECTION


static func server_tick() -> float:
	return Engine.get_physics_frames() + _offset


## Server tick at which clients render remote bodies.
static func render_tick() -> float:
	return server_tick() - INTERPOLATION_DELAY_TICKS


static func reset() -> void:
	_started = false
