@tool
class_name Bridge
extends StaticBody3D
## Overpass: a concrete deck on steel pillars with a ramp up at each end.
## Origin at the deck centre on the ground; the deck runs along Z. Cars drive
## over it, or underneath between the pillars.

const CONCRETE := preload("res://materials/concrete.tres")

@export var deck_length := 36.0:
	set(value):
		deck_length = value
		_rebuild()
@export var deck_width := 10.0:
	set(value):
		deck_width = value
		_rebuild()
@export var deck_height := 6.0:  ## top surface
	set(value):
		deck_height = value
		_rebuild()
@export var deck_thickness := 0.8:
	set(value):
		deck_thickness = value
		_rebuild()
@export var ramp_length := 30.0:
	set(value):
		ramp_length = value
		_rebuild()
@export var pillar_spacing := 12.0:
	set(value):
		pillar_spacing = value
		_rebuild()
@export var curb_height := 0.5:  ## low kerb along the deck edges
	set(value):
		curb_height = value
		_rebuild()

var _generated: Array[Node] = []


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_node_ready():
		return
	for node in _generated:
		node.queue_free()
	_generated.clear()
	var visual := DisplayServer.get_name() != "headless"
	var steel := _material(Color(0.2, 0.22, 0.25), 0.45, 0.6)
	var hazard := _material(Color(0.95, 0.75, 0.1), 0.5, 0.0)

	# Deck.
	var deck_size := Vector3(deck_width, deck_thickness, deck_length)
	_add_box(deck_size, Vector3(0, deck_height - deck_thickness * 0.5, 0), CONCRETE, visual)
	# Kerbs along both edges, yellow so the drop reads from afar.
	for side: float in [-1.0, 1.0]:
		var curb := Vector3(0.4, curb_height, deck_length)
		var x := side * (deck_width * 0.5 - 0.2)
		_add_box(curb, Vector3(x, deck_height + curb_height * 0.5, 0), hazard, visual)

	# Ramps up to each end of the deck.
	for end: float in [-1.0, 1.0]:
		var ramp := Ramp.new()
		ramp.length = ramp_length
		ramp.height = deck_height
		ramp.width = deck_width
		ramp.edge_stripe = false
		ramp.position = Vector3(0, 0, end * (deck_length * 0.5 + ramp_length))
		ramp.rotation.y = 0.0 if end > 0.0 else PI
		_add(ramp)

	# Pillars under the deck edges.
	var count := maxi(int(deck_length / pillar_spacing), 1)
	var underside := deck_height - deck_thickness
	for i in count + 1:
		var z := -deck_length * 0.5 + 1.0 + (deck_length - 2.0) * i / count
		for side: float in [-1.0, 1.0]:
			var pillar := Vector3(0.7, underside, 0.7)
			var x := side * (deck_width * 0.5 - 0.6)
			_add_box(pillar, Vector3(x, underside * 0.5, z), steel, visual)


func _add_box(size: Vector3, center: Vector3, material: Material, visual: bool) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = center
	_add(collision)
	if visual:
		var mesh := MeshInstance3D.new()
		mesh.mesh = MeshBuilder.chamfered_box(size, minf(0.06, size.y * 0.2), material)
		mesh.position = center
		_add(mesh)


func _add(node: Node) -> void:
	add_child(node)
	_generated.append(node)


static func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material
