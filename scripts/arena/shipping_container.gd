@tool
extends StaticBody3D
## 20 ft shipping container obstacle. Origin at the bottom centre, length
## along X, doors at +X. Ribbed walls come from a shared material tinted by
## `color`; the frame is a darker shade of the same colour.

const CORRUGATED := preload("res://materials/container_corrugated.tres")

@export var color := Color(0.6, 0.16, 0.1):
	set(value):
		color = value
		_apply_color()


func _ready() -> void:
	_apply_color()


func _apply_color() -> void:
	if not is_node_ready():
		return
	var walls := CORRUGATED.duplicate() as StandardMaterial3D
	walls.albedo_color = color
	$Body.material_override = walls
	var frame := StandardMaterial3D.new()
	frame.albedo_color = color.darkened(0.45)
	frame.metallic = 0.4
	frame.roughness = 0.6
	for part: MeshInstance3D in $Frame.get_children():
		part.material_override = frame
