class_name CarInput
extends RefCounted
## Snapshot of driver intent for a single physics tick.
## Kept separate from Car so the server can later fill it from network packets.

## When set (--bot), locally controlled cars are driven by BotDriver instead
## of devices. Used for unattended clients: smoke tests and load tests.
static var bot_mode := false

var throttle := 0.0  ## -1 (reverse) .. 1 (forward)
var steer := 0.0  ## -1 (left) .. 1 (right)
var handbrake := false
var reset := false  ## put the car back on its wheels
var fire := false


## Compact network form: [throttle, steer, flags]. Reset travels separately
## (reliable RPC), since it's one-shot.
func encode() -> PackedFloat32Array:
	var flags := (1 if handbrake else 0) | (2 if fire else 0)
	return PackedFloat32Array([throttle, steer, flags])


static func decode(data: PackedFloat32Array, offset := 0) -> CarInput:
	var input := CarInput.new()
	input.throttle = clampf(data[offset], -1.0, 1.0)
	input.steer = clampf(data[offset + 1], -1.0, 1.0)
	var flags := int(data[offset + 2])
	input.handbrake = flags & 1 != 0
	input.fire = flags & 2 != 0
	return input


static func from_local_devices() -> CarInput:
	var input := CarInput.new()
	input.throttle = Input.get_axis("car_reverse", "car_accelerate")
	input.steer = Input.get_axis("car_left", "car_right")
	input.handbrake = Input.is_action_pressed("car_handbrake")
	input.reset = Input.is_action_just_pressed("car_reset")
	input.fire = Input.is_action_pressed("car_fire")
	return input
