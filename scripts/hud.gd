extends CanvasLayer
## Player HUD: health, kills and destroyed notice for the tracked car.

@export var car: Car

@onready var _health_bar: ProgressBar = %HealthBar
@onready var _kills: Label = %Kills
@onready var _destroyed: Label = %Destroyed


func _process(_delta: float) -> void:
	visible = is_instance_valid(car)
	if not visible:
		return
	_health_bar.max_value = car.max_health
	_health_bar.value = car.health
	_kills.text = "Kills: %d" % car.kills
	_destroyed.visible = car.is_destroyed
