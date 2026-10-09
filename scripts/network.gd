extends Node
## Session setup (autoload "Network"): hosting, joining and dedicated server.
##
## The transport (ENet) is created only in open_connection(), so switching to
## WebSocket/WebRTC for a web build should only touch this file.
##
## Command line (after `--`): --server, --host, --join[=ADDRESS], --port=N, --bot,
## --net-log (print every car's state every 2 s, for debugging replication)

enum Mode { OFFLINE, HOST, CLIENT, DEDICATED_SERVER }

const DEFAULT_PORT := 7777
const MAX_PEERS := 64
## ENet drops a silent peer (crash, lost connection) after this long, in ms.
## Default is ~30 s, far too long to leave a ghost car in the arena.
const PEER_TIMEOUT_MIN_MS := 3000
const PEER_TIMEOUT_MAX_MS := 8000
const GAME_SCENE := "res://scenes/game.tscn"
const MENU_SCENE := "res://scenes/menu.tscn"

var mode := Mode.OFFLINE
var address := "127.0.0.1"
var port := DEFAULT_PORT
## Last reason a session ended, shown by the menu.
var last_message := ""
var log_state := false


func _ready() -> void:
	multiplayer.connection_failed.connect(
		func(): leave("Could not connect to %s:%d" % [address, port])
	)
	multiplayer.server_disconnected.connect(func(): leave("Disconnected from server"))
	multiplayer.peer_connected.connect(_shorten_timeout)

	var args := _user_args()
	CarInput.bot_mode = args.has("bot")
	log_state = args.has("net-log")
	port = int(args.get("port", DEFAULT_PORT))
	if args.has("server"):
		start_game.call_deferred(Mode.DEDICATED_SERVER)
	elif args.has("host"):
		start_game.call_deferred(Mode.HOST)
	elif args.has("join"):
		if args["join"] != "":
			address = args["join"]
		start_game.call_deferred(Mode.CLIENT)


func is_dedicated_server() -> bool:
	return mode == Mode.DEDICATED_SERVER


## Switches to the game scene; the scene calls open_connection() once its
## spawner exists, so replicated nodes from the server always have a place
## to land.
func start_game(new_mode: Mode) -> void:
	mode = new_mode
	last_message = ""
	get_tree().change_scene_to_file(GAME_SCENE)


func open_connection() -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := OK
	match mode:
		Mode.HOST, Mode.DEDICATED_SERVER:
			error = peer.create_server(port, MAX_PEERS)
		Mode.CLIENT:
			error = peer.create_client(address, port)
		_:
			return OK
	if error == OK:
		multiplayer.multiplayer_peer = peer
		print("Network: %s on port %d" % [Mode.find_key(mode), port])
	return error


func _notification(what: int) -> void:
	# Disconnect cleanly on quit so other peers see us leave immediately
	# instead of waiting for a timeout.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if is_inside_tree() and multiplayer.multiplayer_peer:
			multiplayer.multiplayer_peer.close()


func _shorten_timeout(peer_id: int) -> void:
	# Only direct links exist: server <-> each client. Clients also get
	# peer_connected for other clients, which they don't connect to.
	if not multiplayer.is_server() and peer_id != 1:
		return
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet:
		enet.get_peer(peer_id).set_timeout(0, PEER_TIMEOUT_MIN_MS, PEER_TIMEOUT_MAX_MS)


func leave(message := "") -> void:
	if message:
		print("Network: ", message)
	last_message = message
	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if is_dedicated_server():
		get_tree().quit(1 if message else 0)
		return
	mode = Mode.OFFLINE
	get_tree().change_scene_to_file.call_deferred(MENU_SCENE)


func _user_args() -> Dictionary:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else ""
	return args
