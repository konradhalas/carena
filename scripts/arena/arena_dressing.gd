@tool
extends Node3D
## Visual-only indoor hall around the playing field: concrete hall floor, a
## yellow cap on the padded arena walls, the hall shell (walls, roof),
## floodlights hung from the roof and a jumbotron over the centre. Nothing
## here collides or affects gameplay; it is skipped on headless servers.

const CONCRETE := preload("res://materials/concrete.tres")

@export var field_half_size := 61.0  ## arena wall centre line
@export var wall_height := 4.0
@export var wall_thickness := 2.0
@export var cap_color := Color(0.95, 0.75, 0.1)

@export_group("Hall")
@export var hall_margin := 14.0  ## m of concrete floor between arena wall and hall wall
@export var roof_height := 28.0
@export var hall_color := Color(0.09, 0.1, 0.12)

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
	var cap := _material(cap_color, 0.4)
	for side in 4:
		var side_root := Node3D.new()
		side_root.rotation.y = side * PI / 2
		_generated.add_child(side_root)
		_build_wall_cap(side_root, cap)
	_build_hall()
	_build_floodlights()
	_build_jumbotron()


func _hall_half_size() -> float:
	return field_half_size + wall_thickness * 0.5 + hall_margin


func _build_wall_cap(side_root: Node3D, cap: Material) -> void:
	var size := Vector3(2.0 * field_half_size + wall_thickness, 0.3, wall_thickness + 0.1)
	side_root.add_child(_box(size, Vector3(0, wall_height + 0.15, field_half_size), cap))


## Closed hall: concrete floor strips around the arena (not under it — the
## dirt dips below zero in places), four walls and a roof.
func _build_hall() -> void:
	var edge := _hall_half_size()
	var span := 2.0 * edge + 2.0
	var strip_depth := edge - field_half_size + 1.0
	var shell := _material(hall_color, 0.8)
	for side in 4:
		var floor_root := Node3D.new()
		floor_root.rotation.y = side * PI / 2
		var strip_center := Vector3(0, -0.1, field_half_size + strip_depth * 0.5)
		floor_root.add_child(_box(Vector3(span, 0.2, strip_depth), strip_center, CONCRETE))
		_generated.add_child(floor_root)
		var wall := _box(
			Vector3(span, roof_height, 1.0), Vector3(0, roof_height * 0.5, edge + 0.5), shell
		)
		# The shell doesn't cast shadows: the overhead fill light stands in for
		# many ceiling lamps and must reach inside the closed hall.
		wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var side_root := Node3D.new()
		side_root.rotation.y = side * PI / 2
		side_root.add_child(wall)
		_generated.add_child(side_root)
	var roof := _box(Vector3(span, 1.0, span), Vector3(0, roof_height + 0.5, 0), shell)
	roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_generated.add_child(roof)


## Floodlights hung from the roof on short rods, aimed into the arena. Corner
## ones cast shadows; all of them light the volumetric fog (visible beams).
func _build_floodlights() -> void:
	var housing := _material(Color(0.08, 0.08, 0.09), 0.5)
	var lens := _glow_material(floodlight_color, 6.0)
	var mount_height := roof_height - 3.0
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
		var mount := Vector3(ground.x, mount_height, ground.z)
		var rod_length := roof_height - mount_height
		var rod := _box(
			Vector3(0.15, rod_length, 0.15), mount + Vector3.UP * rod_length * 0.5, housing
		)
		rod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_generated.add_child(rod)

		var light := SpotLight3D.new()
		light.light_color = floodlight_color
		light.light_energy = floodlight_energy
		light.light_size = 0.6
		light.spot_range = 80.0
		light.spot_angle = 32.0
		light.spot_attenuation = 0.6
		light.shadow_enabled = placement[1]
		light.light_volumetric_fog_energy = 1.5
		_generated.add_child(light)
		light.look_at_from_position(mount, ground * 0.35)
		# Lamp housing with a glowing lens facing where the light points (-Z).
		var body := _box(Vector3(1.4, 1.4, 1.0), Vector3(0, 0, 0.3), housing)
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		light.add_child(body)
		var face := _box(Vector3(1.1, 1.1, 0.05), Vector3(0, 0, -0.22), lens)
		face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		light.add_child(face)


## Four-sided screen hanging from the roof over the centre; its glow also
## lights the arena.
func _build_jumbotron() -> void:
	var height := roof_height - 9.0
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
	var cable_length := roof_height - height - 2.75
	for x: float in [-4.0, 4.0]:
		for z: float in [-4.0, 4.0]:
			var cable := _box(
				Vector3(0.08, cable_length, 0.08), Vector3(x, 2.75 + cable_length * 0.5, z), frame
			)
			cable.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(cable)


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
