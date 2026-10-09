@tool
extends Node3D
## Visual-only indoor stadium around the playing field: spectator stands, a
## yellow cap on the padded walls, the hall itself (outer walls, roof, truss
## grid), floodlights hung from the truss and a jumbotron over the centre.
## Nothing here collides or affects gameplay; it is skipped entirely on
## headless servers.

const CONCRETE := preload("res://materials/concrete.tres")

@export var field_half_size := 61.0  ## wall centre line
@export var wall_height := 4.0
@export var wall_thickness := 2.0
@export var tiers := 14
@export var tier_depth := 1.6
@export var tier_rise := 0.85
@export var seat_color := Color(0.1, 0.2, 0.48)
@export var cap_color := Color(0.95, 0.75, 0.1)
@export var aisle_spacing := 22.0  ## m between stair aisles splitting the seat rows
@export var aisle_width := 1.6

@export_group("Hall")
@export var roof_height := 38.0
@export var truss_height := 31.0
@export var truss_spacing := 24.0
@export var hall_color := Color(0.09, 0.1, 0.12)
@export var truss_color := Color(0.35, 0.36, 0.38)

@export_group("Lighting")
@export var floodlight_energy := 16.0
@export var floodlight_color := Color(1.0, 0.93, 0.8)
@export var jumbotron_color := Color(0.25, 0.55, 1.0)

var _generated: Node3D


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_generated = Node3D.new()
	add_child(_generated)
	var seats := _material(seat_color, 0.6)
	var cap := _material(cap_color, 0.4)
	for side in 4:
		var side_root := Node3D.new()
		side_root.rotation.y = side * PI / 2
		_generated.add_child(side_root)
		_build_wall_cap(side_root, cap)
		_build_stand(side_root, seats)
	_build_hall()
	_build_truss()
	_build_floodlights()
	_build_jumbotron()


func _stand_outer_edge() -> float:
	return field_half_size + wall_thickness * 0.5 + tiers * tier_depth


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


## Closed hall: four outer walls behind the top row of the stands and a roof.
func _build_hall() -> void:
	var shell := _material(hall_color, 0.8)
	var edge := _stand_outer_edge() + 1.0
	for side in 4:
		var wall := _box(
			Vector3(2.0 * edge + 2.0, roof_height, 1.0),
			Vector3(0, roof_height * 0.5, edge + 0.5),
			shell
		)
		# The shell doesn't cast shadows: the overhead fill light stands in for
		# many ceiling lamps and must reach inside the closed hall.
		wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var side_root := Node3D.new()
		side_root.rotation.y = side * PI / 2
		side_root.add_child(wall)
		_generated.add_child(side_root)
	var roof_size := Vector3(2.0 * edge + 2.0, 1.0, 2.0 * edge + 2.0)
	var roof := _box(roof_size, Vector3(0, roof_height + 0.5, 0), shell)
	roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_generated.add_child(roof)


## Grid of steel trusses under the roof, which the floodlights hang from.
func _build_truss() -> void:
	var steel := _material(truss_color, 0.45)
	steel.metallic = 0.8
	var span := 2.0 * _stand_outer_edge()
	var lines := int(span / truss_spacing) + 1
	for i in lines:
		var offset := -span * 0.5 + i * truss_spacing
		_generated.add_child(_box(Vector3(span, 1.2, 0.8), Vector3(0, truss_height, offset), steel))
		_generated.add_child(_box(Vector3(0.8, 1.2, span), Vector3(offset, truss_height, 0), steel))


## Floodlights on the truss aimed into the arena. Corner ones cast shadows;
## all of them light the volumetric fog, which draws visible beams.
func _build_floodlights() -> void:
	var housing := _material(Color(0.08, 0.08, 0.09), 0.5)
	var lens := _glow_material(floodlight_color, 6.0)
	var ring := field_half_size * 0.8
	var placements := [
		[Vector3(-ring, 0, -ring), true],
		[Vector3(ring, 0, -ring), true],
		[Vector3(-ring, 0, ring), true],
		[Vector3(ring, 0, ring), true],
		[Vector3(0, 0, -ring), false],
		[Vector3(0, 0, ring), false],
		[Vector3(-ring, 0, 0), false],
		[Vector3(ring, 0, 0), false],
	]
	for placement: Array in placements:
		var ground: Vector3 = placement[0]
		var light := SpotLight3D.new()
		light.light_color = floodlight_color
		light.light_energy = floodlight_energy
		light.light_size = 0.6
		light.spot_range = 90.0
		light.spot_angle = 30.0
		light.spot_attenuation = 0.6
		light.shadow_enabled = placement[1]
		light.light_volumetric_fog_energy = 1.5
		_generated.add_child(light)
		var mount := Vector3(ground.x, truss_height - 1.2, ground.z)
		light.look_at_from_position(mount, ground * 0.35)
		# Lamp housing with a glowing lens facing where the light points (-Z).
		light.add_child(_box(Vector3(1.4, 1.4, 1.0), Vector3(0, 0, 0.3), housing))
		var face := _box(Vector3(1.1, 1.1, 0.05), Vector3(0, 0, -0.22), lens)
		face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		light.add_child(face)


## Four-sided screen hanging over the centre; its glow also lights the arena.
func _build_jumbotron() -> void:
	var height := truss_height - 7.0
	var frame := _material(Color(0.05, 0.05, 0.06), 0.5)
	var screen := _glow_material(jumbotron_color, 2.5)
	var root := Node3D.new()
	root.position = Vector3(0, height, 0)
	_generated.add_child(root)
	root.add_child(_box(Vector3(10, 5.5, 10), Vector3.ZERO, frame))
	for side in 4:
		var face := Node3D.new()
		face.rotation.y = side * PI / 2
		face.add_child(_box(Vector3(9, 4.6, 0.1), Vector3(0, 0, 5.02), screen))
		root.add_child(face)
	for x: float in [-4.0, 4.0]:
		for z: float in [-4.0, 4.0]:
			var cable_length := truss_height - height - 2.75
			root.add_child(
				_box(
					Vector3(0.08, cable_length, 0.08),
					Vector3(x, 2.75 + cable_length * 0.5, z),
					frame
				)
			)


static func _box(size: Vector3, offset: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = offset
	return instance


static func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


static func _glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material
