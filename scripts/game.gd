extends Node3D
## Networked match. The server spawns one car per player through the
## MultiplayerSpawner; clients receive them automatically.

const CAR_SCENE := preload("res://scenes/car.tscn")
const SPAWN_RADIUS := 45.0
const SPAWN_HEIGHT := 1.2
const GOLDEN_ANGLE := 2.39996
const STATE_LOG_INTERVAL := 2.0

var _next_spawn_index := 0
var _state_log_timer := 0.0

@onready var _players: Node3D = $Players
@onready var _spawner: MultiplayerSpawner = $PlayerSpawner
@onready var _camera: Camera3D = $Camera
@onready var _status: Label = $HUD/Status


func _ready() -> void:
	_spawner.spawn_function = _create_car
	var error := Network.open_connection()
	if error != OK:
		Network.leave("Could not start network: %s" % error_string(error))
		return
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		if not Network.is_dedicated_server():
			_spawn_car_for(multiplayer.get_unique_id())


func _process(delta: float) -> void:
	if Network.log_state:
		_state_log_timer += delta
		if _state_log_timer >= STATE_LOG_INTERVAL:
			_state_log_timer = 0.0
			_log_state()
	var role: String = Network.Mode.find_key(Network.mode)
	_status.text = (
		"%s | peer %d | players: %d | Esc: leave"
		% [role, multiplayer.get_unique_id(), _players.get_child_count()]
	)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Network.leave()


func _spawn_car_for(peer_id: int) -> void:
	# Spread players around a ring facing the centre; the golden angle keeps
	# consecutive spawns far apart for any number of players.
	var angle := _next_spawn_index * GOLDEN_ANGLE
	_next_spawn_index += 1
	var position := Vector3(cos(angle), 0.0, sin(angle)) * SPAWN_RADIUS
	position.y = SPAWN_HEIGHT
	var yaw := atan2(cos(angle), sin(angle))
	_spawner.spawn({"peer_id": peer_id, "position": position, "yaw": yaw})


func _on_peer_connected(peer_id: int) -> void:
	print("Game: player %d joined" % peer_id)
	_spawn_car_for(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("Game: player %d left" % peer_id)
	var car := _players.get_node_or_null(str(peer_id))
	if car:
		car.queue_free()


func _log_state() -> void:
	var cars: Array[String] = []
	for car: Car in _players.get_children():
		var p := car.global_position
		cars.append("%s(%.1f, %.1f, %.1f)" % [car.name, p.x, p.y, p.z])
	print("[peer %d] %s" % [multiplayer.get_unique_id(), ", ".join(cars)])


## Runs on every peer (server and clients) for each spawned car.
func _create_car(data: Dictionary) -> Node:
	var car: Car = CAR_SCENE.instantiate()
	var peer_id: int = data["peer_id"]
	car.name = str(peer_id)
	car.owner_peer_id = peer_id
	car.is_locally_controlled = peer_id == multiplayer.get_unique_id()
	car.transform = Transform3D(Basis(Vector3.UP, data["yaw"]), data["position"])
	if car.is_locally_controlled:
		_camera.target = car
	return car
