extends Control
## Main menu: join a server (the main path) or host a game.
## F9 opens the offline sandbox — a developer shortcut, not shown in the UI.

const SANDBOX_SCENE := "res://scenes/sandbox.tscn"
const SETTINGS_PATH := "user://settings.cfg"
const BACKGROUND_ZOOM := 1.08  ## slow push-in on the background screenshot
const BACKGROUND_ZOOM_TIME := 24.0

@onready var _name: LineEdit = %Name
@onready var _address: LineEdit = %Address
@onready var _status: Label = %Status
@onready var _background: TextureRect = %Background


func _ready() -> void:
	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH)
	_name.text = settings.get_value("player", "name", Network.player_name)
	_address.text = settings.get_value("player", "address", Network.address)
	_show_status(Network.last_message)
	%Host.pressed.connect(func(): _start(Network.Mode.HOST))
	%Join.pressed.connect(_join)
	_address.text_submitted.connect(func(_text): _join())
	%Join.grab_focus.call_deferred()
	_animate_background()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == KEY_F9:
		get_tree().change_scene_to_file(SANDBOX_SCENE)


func _animate_background() -> void:
	_background.resized.connect(func(): _background.pivot_offset = _background.size / 2.0)
	_background.pivot_offset = _background.size / 2.0
	var tween := create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	tween.tween_property(_background, "scale", Vector2.ONE * BACKGROUND_ZOOM, BACKGROUND_ZOOM_TIME)
	tween.tween_property(_background, "scale", Vector2.ONE, BACKGROUND_ZOOM_TIME)


func _show_status(message: String) -> void:
	_status.text = message
	_status.visible = not message.is_empty()


func _join() -> void:
	var address := _address.text.strip_edges()
	if address.is_empty():
		_show_status("Enter server address")
		_address.grab_focus()
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
