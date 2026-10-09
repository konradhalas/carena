@tool
extends Node3D
## Visual-only stadium around the playing field: spectator stands, a yellow
## cap on the padded walls and overhead floodlights. Nothing here collides or
## affects gameplay; it is skipped entirely on headless servers.

const CONCRETE := preload("res://materials/concrete.tres")

@export var field_half_size := 61.0  ## wall centre line
@export var wall_height := 4.0
@export var wall_thickness := 2.0
@export var tiers := 14
@export var tier_depth := 1.6
@export var tier_rise := 0.85
@export var seat_color := Color(0.1, 0.2, 0.48)
@export var cap_color := Color(0.95, 0.75, 0.1)
@export var floodlight_energy := 12.0
@export var aisle_spacing := 22.0  ## m between stair aisles splitting the seat rows
@export var aisle_width := 1.6

var _generated: Node3D


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_generated = Node3D.new()
	add_child(_generated)
	var seats := _flat_material(seat_color, 0.6)
	var cap := _flat_material(cap_color, 0.4)
	for side in 4:
		var side_root := Node3D.new()
		side_root.rotation.y = side * PI / 2
		_generated.add_child(side_root)
		_build_wall_cap(side_root, cap)
		_build_stand(side_root, seats)
	_build_floodlights()


## Stands rise outward from just behind the wall, one solid concrete tier per
## row with a strip of seats along its back edge.
func _build_stand(side_root: Node3D, seats: Material) -> void:
	var start := field_half_size + wall_thickness * 0.5
	for i in tiers:
		var depth_center := start + (i + 0.5) * tier_depth
		var height := wall_height + 0.5 + i * tier_rise
		var length := 2.0 * (start + (i + 1) * tier_depth)
		var tier_size := Vector3(length, height, tier_depth)
		side_root.add_child(_box(tier_size, Vector3(0, height * 0.5, depth_center), CONCRETE))
		_build_seat_row(side_root, seats, length, height, depth_center + tier_depth * 0.25)


## One row of seats, interrupted by stair aisles at regular intervals.
func _build_seat_row(
	side_root: Node3D, seats: Material, length: float, height: float, depth: float
) -> void:
	var half := length * 0.5
	var x := -half
	while x < half:
		var next_aisle := (floorf(x / aisle_spacing) + 1.0) * aisle_spacing - aisle_width * 0.5
		var end := minf(next_aisle, half)
		if end - x > 0.5:
			var size := Vector3(end - x, 0.45, tier_depth * 0.35)
			side_root.add_child(_box(size, Vector3((x + end) * 0.5, height + 0.225, depth), seats))
		x = next_aisle + aisle_width


func _build_wall_cap(side_root: Node3D, cap: Material) -> void:
	var size := Vector3(2.0 * field_half_size + wall_thickness, 0.3, wall_thickness + 0.1)
	side_root.add_child(_box(size, Vector3(0, wall_height + 0.15, field_half_size), cap))


func _build_floodlights() -> void:
	var corner := field_half_size * 0.9
	for x: float in [-corner, corner]:
		for z: float in [-corner, corner]:
			var light := SpotLight3D.new()
			light.light_color = Color(1.0, 0.95, 0.85)
			light.light_energy = floodlight_energy
			light.spot_range = 160.0
			light.spot_angle = 38.0
			light.spot_attenuation = 0.5
			_generated.add_child(light)
			light.position = Vector3(x, 45.0, z)
			light.look_at_from_position(light.position, Vector3(-x * 0.2, 0, -z * 0.2))


static func _box(size: Vector3, offset: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = offset
	return instance


static func _flat_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material
