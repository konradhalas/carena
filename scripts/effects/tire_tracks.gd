class_name TireTracks
extends Node3D
## Tyre marks left in the dirt (one per level, group "tire_tracks").
##
## Each mark segment is a flat textured quad in a MultiMesh. Segments live in
## a ring buffer split into chunks, so adding one re-uploads only its chunk;
## once full, the oldest marks are overwritten. Each segment stores when it
## was laid and the shader fades it out after `lifetime`. Visual only: skipped
## on headless servers.

const SHADER := preload("res://shaders/tire_tracks.gdshader")

const CHUNK_SIZE := 2048
const CHUNK_COUNT := 16
const LIFT := 0.02  ## above the surface, to avoid z-fighting
const OVERLAP := 0.05  ## extra length so consecutive segments don't gap
const TRACK_COLOR := Color(0.15, 0.1, 0.06)

@export var bounds := AABB(Vector3(-70, -5, -70), Vector3(140, 30, 140))
@export var lifetime := 20.0:  ## seconds a mark stays (including fade)
	set(value):
		lifetime = value
		_update_shader_limits()
@export var fade_time := 6.0:  ## seconds over which a mark fades at the end
	set(value):
		fade_time = value
		_update_shader_limits()

var _chunks: Array[MultiMesh] = []
var _next := 0
var _material: ShaderMaterial


func _ready() -> void:
	# Marks never move. With physics interpolation on, a freshly written
	# MultiMesh instance would render blended with the slot's previous
	# contents for a tick, flashing stray squares around the car.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if DisplayServer.get_name() == "headless":
		return
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("tread", ImageTexture.create_from_image(_tread_image()))
	_update_shader_limits()
	var quad := QuadMesh.new()
	quad.material = _material
	for i in CHUNK_COUNT:
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_custom_data = true
		multimesh.mesh = quad
		multimesh.instance_count = CHUNK_SIZE
		multimesh.visible_instance_count = 0
		multimesh.custom_aabb = bounds
		var instance := MultiMeshInstance3D.new()
		instance.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		instance.multimesh = multimesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		_chunks.append(multimesh)


## Lays one mark segment from `from` to `to` on a surface with `normal`.
func add_segment(from: Vector3, to: Vector3, normal: Vector3, width: float) -> void:
	if _chunks.is_empty():
		return
	var along := to - from
	var length := along.length()
	if length < 0.01:
		return
	var forward := along / length
	var side := forward.cross(normal).normalized()
	# QuadMesh lies in its local XY plane facing +Z: X across, Y along, Z up.
	var basis := Basis(side * width, forward * (length + OVERLAP), normal)
	var origin := (from + to) * 0.5 + normal * LIFT

	var chunk := _chunks[_next / CHUNK_SIZE]
	var index := _next % CHUNK_SIZE
	chunk.set_instance_transform(index, Transform3D(basis, origin))
	chunk.set_instance_custom_data(index, Color(_now(), 0, 0, 0))
	if index >= chunk.visible_instance_count:
		chunk.visible_instance_count = index + 1
	_next = (_next + 1) % (CHUNK_SIZE * CHUNK_COUNT)


func _process(_delta: float) -> void:
	if _material:
		_material.set_shader_parameter("now", _now())


func _update_shader_limits() -> void:
	if _material:
		_material.set_shader_parameter("lifetime", lifetime)
		_material.set_shader_parameter("fade_time", minf(fade_time, lifetime))


## Seconds since the engine started. Shader TIME wraps around after an hour,
## so the clock is passed in explicitly.
static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Tread print: soft edges across the width, alternating blocks along it.
static func _tread_image() -> Image:
	var width := 32
	var height := 32
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in height:
		for x in width:
			var u := (x + 0.5) / width
			var edge := smoothstep(0.0, 0.18, u) * smoothstep(1.0, 0.82, u)
			var left_half := u < 0.5
			var block_row := (y / 8) % 2 == 0
			var groove := absf(u - 0.5) < 0.04
			var depth := 1.0 if (block_row == left_half) else 0.6
			if groove:
				depth = 0.35
			image.set_pixel(x, y, Color(TRACK_COLOR, 0.75 * edge * depth))
	return image
