class_name Wheel
extends Node3D
## Visual-only wheel. Axle is local X. Radius assumes uniform scale.

## Shared rounded tyre mesh (built once, reused by every wheel).
static var _tyre_mesh: ArrayMesh

@export var radius := 0.6

@onready var _spin: Node3D = $Spin


func _ready() -> void:
	var tyre: MeshInstance3D = $Spin/Tire
	if _tyre_mesh == null:
		var cylinder := tyre.mesh as CylinderMesh
		_tyre_mesh = MeshBuilder.tyre(
			cylinder.top_radius, cylinder.height, 0.38, 0.16, cylinder.material
		)
	tyre.mesh = _tyre_mesh
	tyre.transform = Transform3D.IDENTITY  # lathe is already built around the X axle


## Rolls the wheel by the distance travelled forward (-Z) this frame.
func roll(distance: float) -> void:
	_spin.rotation.x -= distance / (radius * scale.x)
