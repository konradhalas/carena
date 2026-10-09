extends Control
## Main menu: host, join or drive offline in the sandbox.

const SANDBOX_SCENE := "res://scenes/sandbox.tscn"

@onready var _address: LineEdit = %Address
@onready var _status: Label = %Status


func _ready() -> void:
	_address.text = Network.address
	_status.text = Network.last_message
	%Host.pressed.connect(func(): Network.start_game(Network.Mode.HOST))
	%Join.pressed.connect(_join)
	%Sandbox.pressed.connect(func(): get_tree().change_scene_to_file(SANDBOX_SCENE))
	_address.text_submitted.connect(func(_text): _join())


func _join() -> void:
	var address := _address.text.strip_edges()
	if address.is_empty():
		_status.text = "Enter server address"
		return
	Network.address = address
	Network.start_game(Network.Mode.CLIENT)
