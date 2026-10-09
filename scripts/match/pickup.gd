@tool
class_name Pickup
extends Node3D
## Repair kit or ammo crate lying in the arena. The server hands it to the
## first car that drives through it and actually needs it, then brings it
## back after `respawn_time`. `active` replicates through the "Sync" child;
## collection is announced to every peer for the sound and flash.
## Sits on the terrain: its height is taken from the sibling Terrain node.

enum Kind { REPAIR, AMMO }

const HOVER := 1.1  ## m above the ground
const REPAIR_COLOR := Color(0.25, 1.0, 0.45)
const AMMO_COLOR := Color(1.0, 0.75, 0.2)

@export var kind := Kind.REPAIR:
	set(value):
		kind = value
		if is_node_ready():
			_build_visual()
@export var repair_amount := 40.0
@export var ammo_amount := 6
@export var respawn_time := 15.0
@export var radius := 2.8

var active := true:
	set(value):
		active = value
		if _visual:
			_visual.visible = value
			_ground.visible = value

var _respawn_left := 0.0
var _visual: Node3D
var _ground: Node3D
var _spin := 0.0


func _ready() -> void:
	add_to_group("pickups")
	var terrain := get_parent().get_parent().get_node_or_null("Terrain") as ArenaTerrain
	if terrain and not Engine.is_editor_hint():
		position.y = terrain.height_at(position.x, position.z)
	_build_visual()


func _process(delta: float) -> void:
	if _visual:
		_spin += delta
		_visual.rotation.y = _spin * 1.5
		_visual.position.y = HOVER + sin(_spin * 2.0) * 0.15


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not multiplayer.is_server():
		return
	if not active:
		_respawn_left -= delta
		if _respawn_left <= 0.0:
			active = true
		return
	for node in get_tree().get_nodes_in_group("cars"):
		var car := node as Car
		if car == null or car.global_position.distance_to(global_position) > radius:
			continue
		var used := car.repair(repair_amount) if kind == Kind.REPAIR else car.add_ammo(ammo_amount)
		if used:
			active = false
			_respawn_left = respawn_time
			_collected.rpc()
			return


@rpc("authority", "call_local", "reliable")
func _collected() -> void:
	var where := global_position + Vector3.UP * HOVER
	Sfx.play_at(self, "pickup", where, 0.0, 0.0)
	var color := REPAIR_COLOR if kind == Kind.REPAIR else AMMO_COLOR
	Effects.pickup_flash(self, where, color)


func _build_visual() -> void:
	if _visual:
		_visual.queue_free()
		_ground.queue_free()
		_visual = null
	if DisplayServer.get_name() == "headless":
		return
	_ground = Node3D.new()
	_ground.visible = active
	add_child(_ground)
	_visual = Node3D.new()
	_visual.position.y = HOVER
	_visual.visible = active
	add_child(_visual)
	var color := REPAIR_COLOR if kind == Kind.REPAIR else AMMO_COLOR
	if kind == Kind.REPAIR:
		var glow := Effects.glow_material(color, 3.0)
		_visual.add_child(_box(Vector3(0.9, 0.3, 0.3), Vector3.ZERO, glow))
		_visual.add_child(_box(Vector3(0.3, 0.9, 0.3), Vector3.ZERO, glow))
	else:
		var crate := StandardMaterial3D.new()
		crate.albedo_color = Color(0.25, 0.3, 0.18)
		crate.roughness = 0.7
		_visual.add_child(_box(Vector3(1.0, 0.55, 0.6), Vector3.ZERO, crate))
		var stripe := Effects.glow_material(color, 2.0)
		_visual.add_child(_box(Vector3(1.02, 0.1, 0.62), Vector3.ZERO, stripe))
		var brass := StandardMaterial3D.new()
		brass.albedo_color = Color(0.85, 0.65, 0.25)
		brass.metallic = 1.0
		brass.roughness = 0.3
		for x: float in [-0.28, 0.0, 0.28]:
			var shell := CylinderMesh.new()
			shell.top_radius = 0.06
			shell.bottom_radius = 0.09
			shell.height = 0.4
			shell.material = brass
			var instance := MeshInstance3D.new()
			instance.mesh = shell
			instance.position = Vector3(x, 0.47, 0)
			_visual.add_child(instance)
	# Glowing ring projected onto the (bumpy) ground and a coloured light, so
	# pickups read from afar.
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.62, 0.72, 0.86, 1.0])
	gradient.colors = PackedColorArray(
		[
			Color(color, 0.0),
			Color(color, 0.0),
			Color(color, 0.9),
			Color(color, 0.0),
			Color(color, 0.0)
		]
	)
	# Emission ignores alpha, so it needs its own map that is black off the ring.
	var glow := Gradient.new()
	glow.offsets = gradient.offsets
	glow.colors = PackedColorArray([Color.BLACK, Color.BLACK, color, Color.BLACK, Color.BLACK])
	var ring := Decal.new()
	ring.size = Vector3(radius * 2.0, 3.0, radius * 2.0)
	ring.texture_albedo = _radial(gradient)
	ring.texture_emission = _radial(glow)
	ring.emission_energy = 2.0
	_ground.add_child(ring)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.5
	light.omni_range = 5.0
	_visual.add_child(light)


static func _radial(gradient: Gradient) -> GradientTexture2D:
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	return texture


static func _box(size: Vector3, offset: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = offset
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance
