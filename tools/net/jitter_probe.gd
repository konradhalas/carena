extends SceneTree
## Measures how smoothly a car moves on screen, as a player would see it.
##
## Usage: godot --headless --script res://tools/net/jitter_probe.gd -- MODE PORT
##   own:     join localhost:PORT, auto-drive (no enemies → straight), measure own car
##   remote:  join localhost:PORT and idle; measure the other client's car
##            (start a `--bot` client too, it will drive at us)
##   offline: drive in the sandbox — reference for the probe's own noise
##
## Prints speed variation between rendered frames at 120 FPS ("jitter"; ~1-2%
## is smooth, ~200% means the car stands still every other frame) and, for
## "own", how much prediction correction was pending on average.
## See tools/net/measure.sh for the full scenario.

const FPS := 120
const SETTLE_FRAMES := 90
const SAMPLE_FRAMES := 240

var _mode := ""
var _port := 0
var _started := false
var _frame := 0
var _first_frame := -1
var _positions: Array[Vector3] = []
var _deltas: Array[float] = []
var _corrections: Array[float] = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_mode = args[0]
	_port = int(args[1]) if args.size() > 1 else 0
	Engine.max_fps = FPS


func _process(delta: float) -> bool:
	_frame += 1
	if not _started:
		_start()
		return false
	var car := _measured_car()
	if car == null:
		return _frame > 2000
	if _first_frame < 0:
		_first_frame = _frame
	if _frame - _first_frame > SETTLE_FRAMES:
		_positions.append(car.get_global_transform_interpolated().origin)
		_deltas.append(delta)
		if _mode == "own":
			_corrections.append(car._prediction._offset.length())
	if _positions.size() >= SAMPLE_FRAMES:
		_report()
		return true
	return false


func _start() -> void:
	_started = true
	if _mode == "offline":
		change_scene_to_file("res://scenes/sandbox.tscn")
	else:
		var network: Node = root.get_node("Network")
		network.address = "127.0.0.1"
		network.port = _port
		network.start_game(network.Mode.CLIENT)
	# Set after Network._ready, which resets it from the command line.
	CarInput.bot_mode = _mode != "remote"


func _measured_car() -> Car:
	var scene := current_scene
	if scene == null:
		return null
	if _mode == "offline":
		return scene.get_node_or_null("Car")
	if not scene.has_node("Players"):
		return null
	var my_name := str(scene.multiplayer.get_unique_id())
	for car: Car in scene.get_node("Players").get_children():
		if (car.name == my_name) == (_mode == "own"):
			return car
	return null


func _report() -> void:
	# Speed per rendered frame using the engine's frame delta (what render
	# interpolation uses), so uneven frame pacing doesn't count as jitter.
	var speeds: Array[float] = []
	for i in range(1, _positions.size()):
		speeds.append(_positions[i].distance_to(_positions[i - 1]) / maxf(_deltas[i], 1e-4))
	var mean := 0.0
	for speed in speeds:
		mean += speed
	mean /= speeds.size()
	var variation := 0.0
	var stalls := 0
	for i in range(1, speeds.size()):
		variation += absf(speeds[i] - speeds[i - 1])
		if speeds[i] < mean * 0.2:
			stalls += 1
	variation /= speeds.size() - 1
	if not _corrections.is_empty():
		var total := 0.0
		var largest := 0.0
		for correction in _corrections:
			total += correction
			largest = maxf(largest, correction)
		print(
			(
				"PROBE %s: pending correction mean %.3f m, max %.3f m"
				% [_mode, total / _corrections.size(), largest]
			)
		)
	print(
		(
			"PROBE %s: speed %.1f m/s, jitter %.0f%%, stalled frames %d/%d"
			% [_mode, mean, 100.0 * variation / maxf(mean, 1e-4), stalls, speeds.size()]
		)
	)
