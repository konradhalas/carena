extends SceneTree
## CI smoke check: every project script must compile and every scene must
## load and instantiate without the engine reporting any error (Godot keeps
## loading a scene with a missing dependency and only logs it, so errors are
## collected through a Logger rather than from return values).
## Usage: godot --headless --script res://tools/check_project.gd

const ROOTS: Array[String] = ["res://scenes", "res://scripts", "res://tests", "res://tools"]


class ErrorCollector:
	extends Logger

	var errors: Array[String] = []
	var _mutex := Mutex.new()

	func _log_error(
		_function: String,
		file: String,
		line: int,
		code: String,
		rationale: String,
		_editor_notify: bool,
		_error_type: int,
		_script_backtraces: Array[ScriptBacktrace]
	) -> void:
		_mutex.lock()
		errors.append("%s (%s:%d)" % [rationale if rationale else code, file, line])
		_mutex.unlock()


func _initialize() -> void:
	var collector := ErrorCollector.new()
	OS.add_logger(collector)

	var failures: Array[String] = []
	var checked := 0
	for root_dir in ROOTS:
		for path in _files_in(root_dir):
			if not (path.ends_with(".gd") or path.ends_with(".tscn")):
				continue
			checked += 1
			collector.errors.clear()
			var problem := _check_script(path) if path.ends_with(".gd") else _check_scene(path)
			if problem:
				failures.append("%s: %s" % [path, problem])
			for error in collector.errors:
				failures.append("%s: engine error: %s" % [path, error])

	OS.remove_logger(collector)
	if failures.is_empty():
		print("check_project: OK (%d resources)" % checked)
		quit(0)
	else:
		for failure in failures:
			printerr("check_project: FAIL ", failure)
		quit(1)


func _check_script(path: String) -> String:
	var script := load(path) as Script
	if script == null or not script.can_instantiate():
		return "does not compile"
	return ""


func _check_scene(path: String) -> String:
	var scene := load(path) as PackedScene
	if scene == null or not scene.can_instantiate():
		return "does not load"
	var instance := scene.instantiate()
	if instance == null:
		return "does not instantiate"
	instance.free()
	return ""


func _files_in(dir_path: String) -> Array[String]:
	var files: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return files
	for file in dir.get_files():
		files.append(dir_path.path_join(file))
	for sub_dir in dir.get_directories():
		files.append_array(_files_in(dir_path.path_join(sub_dir)))
	return files
