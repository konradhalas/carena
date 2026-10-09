extends CanvasLayer
## Player HUD: health, kills and destroyed notice for the tracked car.

@export var car: Car:
	set(value):
		if car:
			car.damaged.disconnect(_on_damaged)
		car = value
		if car:
			car.damaged.connect(_on_damaged)

var _flash_tween: Tween

@onready var _health_bar: ProgressBar = %HealthBar
@onready var _kills: Label = %Kills
@onready var _destroyed: Label = %Destroyed
@onready var _damage_flash: ColorRect = %DamageFlash


func _process(_delta: float) -> void:
	visible = is_instance_valid(car)
	if not visible:
		return
	_health_bar.max_value = car.max_health
	_health_bar.value = car.health
	_kills.text = "Kills: %d" % car.kills
	_destroyed.visible = car.is_destroyed


func _on_damaged(amount: float) -> void:
	if not is_node_ready():
		return
	if _flash_tween:
		_flash_tween.kill()
	_damage_flash.color.a = clampf(0.12 + amount * 0.02, 0.0, 0.45)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_damage_flash, "color:a", 0.0, 0.35)
