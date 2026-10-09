extends Control
## Main menu: host, join or drive offline in the sandbox.

const SANDBOX_SCENE := "res://scenes/sandbox.tscn"
const SETTINGS_PATH := "user://settings.cfg"

@onready var _name: LineEdit = %Name
@onready var _address: LineEdit = %Address
@onready var _status: Label = %Status


func _ready() -> void:
	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH)
	_name.text = settings.get_value("player", "name", Network.player_name)
	_address.text = settings.get_value("player", "address", Network.address)
	_status.text = Network.last_message
	%Host.pressed.connect(func(): _start(Network.Mode.HOST))
	%Join.pressed.connect(_join)
	%Sandbox.pressed.connect(func(): get_tree().change_scene_to_file(SANDBOX_SCENE))
	_address.text_submitted.connect(func(_text): _join())


func _join() -> void:
	var address := _address.text.strip_edges()
	if address.is_empty():
		_status.text = "Enter server address"
		return
	Network.address = address
	_start(Network.Mode.CLIENT)


func _start(mode: Network.Mode) -> void:
	Network.player_name = _name.text.strip_edges()
	var settings := ConfigFile.new()
	settings.set_value("player", "name", Network.player_name)
	settings.set_value("player", "address", Network.address)
	settings.save(SETTINGS_PATH)
	Network.start_game(mode)
