extends Node3D
## Networked match. The server spawns one car per player through the
## MultiplayerSpawner; clients receive them automatically.

const CAR_SCENE := preload("res://scenes/car.tscn")
const CONNECTING_OVERLAY := preload("res://scenes/connecting_overlay.tscn")
const SPAWN_RADIUS := 85.0
const SPAWN_HEIGHT := 1.2  ## above the terrain at the spawn point
const GOLDEN_ANGLE := 2.39996
## Free space a spawn point needs (a car with some margin), and how many ring
## positions to try before giving up and spawning anyway.
const SPAWN_CLEARANCE := Vector3(3.5, 2.0, 6.0)
const SPAWN_ATTEMPTS := 16
const STATE_LOG_INTERVAL := 2.0
const SPAWN_PROTECTION := 2.0
## Client gives up if it isn't connected (or has no car yet) after this long.
## ENet's own connect timeout is much longer.
const JOIN_TIMEOUT := 10.0

var _next_spawn_index := 0
var _state_log_timer := 0.0
var _overlay: Node  ## clients: covers the screen until our car exists
var _join_time := 0.0

@onready var _players: Node3D = $Players
@onready var _match: MatchState = $MatchState
@onready var _terrain: ArenaTerrain = $Arena/Terrain
@onready var _spawner: MultiplayerSpawner = $PlayerSpawner
@onready var _camera: Camera3D = $Camera
@onready var _hud: CanvasLayer = $HUD
@onready var _status: Label = $StatusLayer/Status


func _ready() -> void:
	_spawner.spawn_function = _create_car
	var error := Network.open_connection()
	if error != OK:
		Network.leave("Could not start network: %s" % error_string(error))
		return
	if Network.match_time > 0.0:
		_match.time_limit = Network.match_time
		_match.time_left = Network.match_time
	if Network.kill_limit > 0:
		_match.kill_limit = Network.kill_limit
	_hud.match_state = _match
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		_match.restart_requested.connect(_restart_match)
		if not Network.is_dedicated_server():
			var me := multiplayer.get_unique_id()
			_match.add_player(me, Network.player_name)
			_spawn_car_for(me)
	else:
		multiplayer.connected_to_server.connect(_on_connected)
		_overlay = CONNECTING_OVERLAY.instantiate()
		add_child(_overlay)
		_overlay.show_step("CONNECTING", "%s:%d" % [Network.address, Network.port])
		_overlay.cancelled.connect(Network.leave)


func _process(delta: float) -> void:
	if _overlay:
		_update_joining(delta)
	if Network.log_state:
		_state_log_timer += delta
		if _state_log_timer >= STATE_LOG_INTERVAL:
			_state_log_timer = 0.0
			_log_state()
	for car: Car in _cars():
		car.display_name = _match.player_name(car.owner_peer_id)
		if multiplayer.is_server():
			car.can_take_damage = _match.is_playing()
	var role: String = Network.Mode.find_key(Network.mode)
	_status.text = (
		"%s | peer %d | players: %d | Esc: leave"
		% [role, multiplayer.get_unique_id(), _players.get_child_count()]
	)


func _on_connected() -> void:
	_register_name.rpc_id(1, Network.player_name)
	_join_time = 0.0
	_overlay.show_step("JOINING MATCH", "%s:%d" % [Network.address, Network.port])


## Client: lift the overlay once our car has arrived; give up after a while.
func _update_joining(delta: float) -> void:
	if _players.has_node(str(multiplayer.get_unique_id())):
		_overlay.dismiss()
		_overlay = null
		return
	_join_time += delta
	if _join_time < JOIN_TIMEOUT:
		return
	_overlay = null
	var server := "%s:%d" % [Network.address, Network.port]
	var status := multiplayer.multiplayer_peer.get_connection_status()
	if status == MultiplayerPeer.CONNECTION_CONNECTED:
		Network.leave("Joined %s, but the match didn't start" % server)
	else:
		Network.leave("Server %s is not responding" % server)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Network.leave()


func _spawn_car_for(peer_id: int) -> void:
	# Spread players around a ring facing the centre; the golden angle keeps
	# consecutive spawns far apart for any number of players. Ring positions
	# blocked by containers, ramps or the bridge are skipped.
	var position := Vector3.ZERO
	var yaw := 0.0
	for attempt in SPAWN_ATTEMPTS:
		var angle := _next_spawn_index * GOLDEN_ANGLE
		_next_spawn_index += 1
		position = Vector3(cos(angle), 0.0, sin(angle)) * SPAWN_RADIUS
		position.y = _terrain.height_at(position.x, position.z) + SPAWN_HEIGHT
		yaw = atan2(cos(angle), sin(angle))
		if _is_spawn_clear(position, yaw):
			break
	_spawner.spawn({"peer_id": peer_id, "position": position, "yaw": yaw})


func _is_spawn_clear(position: Vector3, yaw: float) -> bool:
	var box := BoxShape3D.new()
	box.size = SPAWN_CLEARANCE
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.transform = Transform3D(Basis(Vector3.UP, yaw), position)
	query.exclude = [_terrain.get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _on_peer_connected(peer_id: int) -> void:
	print("Game: player %d joined" % peer_id)
	_match.add_player(peer_id)
	_spawn_car_for(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("Game: player %d left" % peer_id)
	_match.remove_player(peer_id)
	var car := _players.get_node_or_null(str(peer_id))
	if car:
		car.queue_free()


## Client tells the server its nickname right after connecting.
@rpc("any_peer", "call_remote", "reliable")
func _register_name(player_name: String) -> void:
	if multiplayer.is_server():
		_match.add_player(multiplayer.get_remote_sender_id(), player_name)


## Server: new match — everyone back to their spawn point, repaired.
func _restart_match() -> void:
	for car: Car in _cars():
		car.kills = 0
		car.respawn_now()


func _on_car_destroyed(killer_peer_id: int, car: Car) -> void:
	_match.record_kill(killer_peer_id, car.owner_peer_id)


## Cars currently in the match (the Players node holds only cars, but be
## defensive about anything else that ends up there).
func _cars() -> Array[Car]:
	var cars: Array[Car] = []
	for node in _players.get_children():
		if node is Car:
			cars.append(node)
	return cars


func _log_state() -> void:
	var cars: Array[String] = []
	for car: Car in _cars():
		var p := car.global_position
		cars.append(
			(
				"%s(%.1f, %.1f, %.1f hp=%d ammo=%d kills=%d)"
				% [car.name, p.x, p.y, p.z, car.health, car.ammo, car.kills]
			)
		)
	print("[peer %d] %s" % [multiplayer.get_unique_id(), ", ".join(cars)])
	var board: Array[String] = []
	for row in _match.standings():
		board.append("%s %d/%d" % [row["name"], row["kills"], row["deaths"]])
	var phase: String = MatchState.Phase.find_key(_match.phase)
	print("  match %s %.0fs left: %s" % [phase, _match.time_left, ", ".join(board)])


## Runs on every peer (server and clients) for each spawned car.
func _create_car(data: Dictionary) -> Node:
	var car: Car = CAR_SCENE.instantiate()
	var peer_id: int = data["peer_id"]
	car.name = str(peer_id)
	car.owner_peer_id = peer_id
	car.is_locally_controlled = peer_id == multiplayer.get_unique_id()
	car.transform = Transform3D(Basis(Vector3.UP, data["yaw"]), data["position"])
	car.spawn_transform = car.transform
	car.spawn_protection = SPAWN_PROTECTION
	if multiplayer.is_server():
		car.destroyed.connect(_on_car_destroyed.bind(car))
	if car.is_locally_controlled:
		_camera.target = car
		_hud.car = car
	return car
