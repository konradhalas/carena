extends SceneTree
## Renders website screenshots: two bots fight in the sandbox, frames are
## saved at fixed physics ticks. Needs --bot (the Network
## autoload sets CarInput.bot_mode from the command line).
## Usage: godot --path . --resolution 1600x900 \
##   --script res://tools/capture_screenshots.gd -- --bot --out=web/img

const SHOTS := [300, 480, 660, 840, 1020, 1200, 1380, 1560]

var _out := "web/img"
var _scene: Node
var _index := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	_scene = (load("res://scenes/sandbox.tscn") as PackedScene).instantiate()
	(_scene.get_node("Target") as Car).is_locally_controlled = true
	_scene.get_node("HUD").visible = false
	root.add_child(_scene)


func _physics_process(_delta: float) -> bool:
	if _index >= SHOTS.size():
		return true
	if Engine.get_physics_frames() >= SHOTS[_index]:
		var path := "%s/shot_%d.png" % [_out, _index]
		root.get_viewport().get_texture().get_image().save_png(path)
		print("saved ", path)
		_index += 1
	return false
