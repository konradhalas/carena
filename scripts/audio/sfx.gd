class_name Sfx
extends RefCounted
## One-shot 3D sound effects on the "World" bus (with the hall reverb).
## Fire-and-forget: the player frees itself when done. No-op on headless.

const BUS := &"World"
const SOUNDS := {
	"cannon": preload("res://assets/audio/cannon.wav"),
	"empty_click": preload("res://assets/audio/empty_click.wav"),
	"pickup": preload("res://assets/audio/pickup.wav"),
	"impact_metal": preload("res://assets/audio/impact_metal.wav"),
	"impact_dirt": preload("res://assets/audio/impact_dirt.wav"),
	"landing": preload("res://assets/audio/landing.wav"),
	"explosion": preload("res://assets/audio/explosion.wav"),
}


static func play_at(
	parent: Node, sound: String, position: Vector3, volume_db := 0.0, pitch_spread := 0.08
) -> void:
	if DisplayServer.get_name() == "headless" or not parent.is_inside_tree():
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = SOUNDS[sound]
	player.bus = BUS
	player.volume_db = volume_db
	player.unit_size = 12.0
	player.max_db = 3.0
	player.pitch_scale = 1.0 + randf_range(-pitch_spread, pitch_spread)
	player.finished.connect(player.queue_free)
	parent.add_child(player)
	player.global_position = position
	player.play()
