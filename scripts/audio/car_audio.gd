class_name CarAudio
extends Node3D
## Per-car looping sounds: engine (pitch follows speed, louder on throttle)
## and tyre scrub (follows sideways slip), plus a thump on hard landings.
## Fed by Car every physics tick on every peer; not created on headless.

const ENGINE := preload("res://assets/audio/engine_loop.wav")
const SKID := preload("res://assets/audio/skid_loop.wav")

@export var idle_pitch := 0.9
@export var top_pitch := 3.2
@export var engine_volume_db := -6.0
@export var skid_volume_db := -6.0
@export var skid_full_slip := 9.0  ## sideways m/s for full scrub volume
@export var landing_min_speed := 4.0  ## vertical m/s that makes a landing audible

var _engine: AudioStreamPlayer3D
var _skid: AudioStreamPlayer3D
var _was_grounded := true
var _fall_speed := 0.0


func _ready() -> void:
	_engine = _make_loop(ENGINE)
	_skid = _make_loop(SKID)
	_skid.volume_db = -80.0


## speed_ratio: |forward speed| / max speed; throttle: 0..1 (or an estimate
## for remote cars); slip: sideways m/s; grounded: any wheel touching.
func update(
	delta: float, speed_ratio: float, throttle: float, slip: float, grounded: bool, vertical: float
) -> void:
	var target_pitch := lerpf(idle_pitch, top_pitch, clampf(speed_ratio, 0.0, 1.0))
	if not grounded:
		target_pitch *= 1.1  # wheels spin up in the air
	_engine.pitch_scale = lerpf(_engine.pitch_scale, target_pitch, clampf(6.0 * delta, 0.0, 1.0))
	var engine_db := engine_volume_db + lerpf(-6.0, 0.0, clampf(throttle, 0.0, 1.0))
	_engine.volume_db = lerpf(_engine.volume_db, engine_db, clampf(8.0 * delta, 0.0, 1.0))

	var scrub := clampf(slip / skid_full_slip, 0.0, 1.0) if grounded else 0.0
	var skid_db := linear_to_db(maxf(scrub, 0.0001)) + skid_volume_db
	_skid.volume_db = lerpf(_skid.volume_db, skid_db, clampf(10.0 * delta, 0.0, 1.0))
	_skid.pitch_scale = 0.8 + scrub * 0.4

	if not grounded:
		_fall_speed = maxf(_fall_speed, -vertical)
	elif not _was_grounded and _fall_speed > landing_min_speed:
		var loudness := clampf((_fall_speed - landing_min_speed) / 10.0, 0.0, 1.0)
		Sfx.play_at(self, "landing", global_position, lerpf(-10.0, 2.0, loudness))
	if grounded:
		_fall_speed = 0.0
	_was_grounded = grounded


func _make_loop(stream: AudioStream) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.bus = Sfx.BUS
	player.unit_size = 10.0
	player.max_db = 0.0
	player.autoplay = true
	add_child(player)
	return player
