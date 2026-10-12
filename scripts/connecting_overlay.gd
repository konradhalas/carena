extends CanvasLayer
## Full-screen cover shown on clients while connecting to the server and
## waiting for their own car, so they never stare at an empty arena.

signal cancelled

const SLIDE_SPEED := 0.8  ## bar sweeps per second

var _sweep := 0.0

@onready var _root: Control = %Root
@onready var _title: Label = %Title
@onready var _detail: Label = %Detail
@onready var _bar: Control = %Bar
@onready var _fill: Control = %Fill


func _ready() -> void:
	%Cancel.pressed.connect(cancelled.emit)


func _process(delta: float) -> void:
	# Indeterminate progress: a segment sliding across the track.
	_sweep = fmod(_sweep + delta * SLIDE_SPEED, 1.0)
	var width := _bar.size.x * 0.3
	_fill.size = Vector2(width, _bar.size.y)
	_fill.position.x = lerpf(-width, _bar.size.x, _sweep)


func show_step(title: String, detail: String) -> void:
	_title.text = title
	_detail.text = detail


## Fades out and frees itself.
func dismiss() -> void:
	set_process(false)
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, 0.4)
	tween.tween_callback(queue_free)
