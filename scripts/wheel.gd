class_name Wheel
extends Node3D
## Visual-only wheel. Axle is local X. Radius assumes uniform scale.

@export var radius := 0.6

@onready var _spin: Node3D = $Spin


## Rolls the wheel by the distance travelled forward (-Z) this frame.
func roll(distance: float) -> void:
	_spin.rotation.x -= distance / (radius * scale.x)
