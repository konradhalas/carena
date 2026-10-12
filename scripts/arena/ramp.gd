@tool
class_name Ramp
extends StaticBody3D
## Solid concrete wedge: origin at the centre of its low edge on the ground,
## rising along -Z to `height` over `length`. Collision is the exact wedge,
## so there is no lip where it meets the floor. Used for jumps and for the
## bridge approaches.

const CONCRETE := preload("res://materials/concrete.tres")
const STRIPE_WIDTH := 0.35

@export var length := 16.0:
	set(value):
		length = value
		_rebuild()
@export var height := 3.0:
	set(value):
		height = value
		_rebuild()
@export var width := 8.0:
	set(value):
		width = value
		_rebuild()
## Yellow strip along the top (high) edge, to read the drop from a distance.
@export var edge_stripe := true:
	set(value):
		edge_stripe = value
		_rebuild()

var _generated: Array[Node] = []


func _ready() -> void:
	_rebuild()


## Top surface height above the ramp's base at a local -Z distance.
func surface_height(distance: float) -> float:
	return height * clampf(distance / length, 0.0, 1.0)


func _rebuild() -> void:
	if not is_node_ready():
		return
	for node in _generated:
		node.queue_free()
	_generated.clear()

	var points := _corners()
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var collision := CollisionShape3D.new()
	collision.shape = shape
	_add(collision)

	if DisplayServer.get_name() == "headless":
		return
	var mesh := MeshInstance3D.new()
	mesh.mesh = _wedge_mesh(points)
	_add(mesh)
	if edge_stripe:
		var stripe := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(width + 0.02, 0.05, STRIPE_WIDTH)
		box.material = _stripe_material()
		stripe.mesh = box
		var slope := atan2(height, length)
		stripe.rotation.x = slope
		stripe.position = Vector3(0, height - STRIPE_WIDTH * 0.5 * sin(slope), -length)
		stripe.position.z += STRIPE_WIDTH * 0.5 * cos(slope)
		_add(stripe)


func _add(node: Node) -> void:
	add_child(node)
	_generated.append(node)


## Low edge (2), high edge on top (2), high edge on the ground (2).
func _corners() -> PackedVector3Array:
	var w := width * 0.5
	return PackedVector3Array(
		[
			Vector3(-w, 0, 0),
			Vector3(w, 0, 0),
			Vector3(-w, height, -length),
			Vector3(w, height, -length),
			Vector3(-w, 0, -length),
			Vector3(w, 0, -length),
		]
	)


func _wedge_mesh(p: PackedVector3Array) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(tool, p[0], p[1], p[3], p[2])  # slope
	_quad(tool, p[2], p[3], p[5], p[4])  # back wall
	_quad(tool, p[4], p[5], p[1], p[0])  # bottom
	_triangle(tool, p[0], p[2], p[4])  # left side
	_triangle(tool, p[1], p[5], p[3])  # right side
	tool.generate_tangents()
	tool.set_material(CONCRETE)
	return tool.commit()


## Counter-clockwise when seen from outside (Godot's front face is clockwise,
## so vertices are emitted reversed).
static func _quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_triangle(tool, a, b, c)
	_triangle(tool, a, c, d)


static func _triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (b - a).cross(c - a).normalized()
	for vertex: Vector3 in [a, c, b]:
		tool.set_normal(normal)
		tool.set_uv(Vector2(vertex.x, vertex.z))
		tool.add_vertex(vertex)


static func _stripe_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.75, 0.1)
	material.roughness = 0.5
	return material
