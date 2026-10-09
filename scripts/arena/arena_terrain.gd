@tool
class_name ArenaTerrain
extends StaticBody3D
## The arena's dirt floor as a heightmap: gentle bumps everywhere, berms
## banked up against the walls, a few mounds and the jump kicker. Heights are
## generated deterministically from the exports, so the server and every
## client build identical collision. Origin at the arena centre; one height
## sample per metre. The visual mesh is skipped on headless servers.

const MATERIAL := preload("res://materials/dirt_terrain.tres")

@export var half_size := 60  ## m from centre to wall
@export var noise_seed := 7
@export var bump_height := 0.22  ## m, peak-to-mean
@export var bump_frequency := 0.07
@export var berm_height := 1.6
@export var berm_width := 7.0
## Smooth hills: x, z, radius, height.
@export var mounds: Array[Vector4] = [
	Vector4(40, 30, 10, 2.0),
	Vector4(-40, 4, 9, 1.6),
	Vector4(-38, -40, 10, 2.2),
	Vector4(40, -40, 9, 1.5),
]
## Areas kept free of bumps (under containers): x, z, radius.
@export var flat_zones: Array[Vector3] = [
	Vector3(20, 20, 7), Vector3(-20, 20, 7), Vector3(20, -20, 8), Vector3(-20, -20, 6)
]

@export_group("Kicker")
## Jump: a straight dirt slope rising towards -Z, then a short steep drop.
@export var kicker_x := 0.0
@export var kicker_start_z := -8.0
@export var kicker_top_z := -22.0
@export var kicker_end_z := -25.0
@export var kicker_height := 3.6
@export var kicker_half_width := 4.0
@export var kicker_side_falloff := 3.0

var _heights := PackedFloat32Array()
var _samples := 0  ## per side


func _ready() -> void:
	_build()


## Terrain height (m) at a world-space x/z inside the arena.
func height_at(x: float, z: float) -> float:
	var gx := clampf(x + half_size, 0.0, _samples - 1.001)
	var gz := clampf(z + half_size, 0.0, _samples - 1.001)
	var x0 := int(gx)
	var z0 := int(gz)
	var fx := gx - x0
	var fz := gz - z0
	var top := lerpf(_sample(x0, z0), _sample(x0 + 1, z0), fx)
	var bottom := lerpf(_sample(x0, z0 + 1), _sample(x0 + 1, z0 + 1), fx)
	return lerpf(top, bottom, fz)


func _build() -> void:
	for child in get_children():
		child.queue_free()
	_samples = half_size * 2 + 1
	_heights = _generate_heights()

	var shape := HeightMapShape3D.new()
	shape.map_width = _samples
	shape.map_depth = _samples
	shape.map_data = _heights
	var collision := CollisionShape3D.new()
	collision.shape = shape
	add_child(collision)

	if DisplayServer.get_name() != "headless":
		var mesh := MeshInstance3D.new()
		mesh.mesh = _build_mesh()
		add_child(mesh)


func _generate_heights() -> PackedFloat32Array:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = bump_frequency
	noise.fractal_octaves = 3
	var heights := PackedFloat32Array()
	heights.resize(_samples * _samples)
	for iz in _samples:
		for ix in _samples:
			heights[iz * _samples + ix] = _height(ix - half_size, iz - half_size, noise)
	return heights


func _height(x: float, z: float, noise: FastNoiseLite) -> float:
	var kicker := _kicker(x, z)
	var calm := 1.0 - smoothstep(0.0, 0.5, kicker)
	for zone in flat_zones:
		var distance := Vector2(x, z).distance_to(Vector2(zone.x, zone.y))
		calm = minf(calm, smoothstep(zone.z, zone.z + 4.0, distance))
	var height := noise.get_noise_2d(x, z) * bump_height * calm

	var to_wall := half_size - maxf(absf(x), absf(z))
	height += berm_height * pow(1.0 - clampf(to_wall / berm_width, 0.0, 1.0), 2.0)

	for mound in mounds:
		var distance := Vector2(x, z).distance_to(Vector2(mound.x, mound.y))
		if distance < mound.z:
			height += mound.w * (0.5 + 0.5 * cos(PI * distance / mound.z))
	return height + kicker


func _kicker(x: float, z: float) -> float:
	var profile := 0.0
	if z <= kicker_start_z and z >= kicker_top_z:
		profile = (kicker_start_z - z) / (kicker_start_z - kicker_top_z)
	elif z < kicker_top_z and z >= kicker_end_z:
		profile = (z - kicker_end_z) / (kicker_top_z - kicker_end_z)
	var side := smoothstep(
		kicker_half_width + kicker_side_falloff, kicker_half_width, absf(x - kicker_x)
	)
	return kicker_height * profile * side


func _sample(ix: int, iz: int) -> float:
	ix = clampi(ix, 0, _samples - 1)
	iz = clampi(iz, 0, _samples - 1)
	return _heights[iz * _samples + ix]


func _build_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in _samples:
		for ix in _samples:
			# Normal from central differences of neighbouring samples.
			var dx := _sample(ix + 1, iz) - _sample(ix - 1, iz)
			var dz := _sample(ix, iz + 1) - _sample(ix, iz - 1)
			tool.set_normal(Vector3(-dx, 2.0, -dz).normalized())
			tool.set_uv(Vector2(ix, iz) / (_samples - 1))
			tool.add_vertex(Vector3(ix - half_size, _sample(ix, iz), iz - half_size))
	for iz in _samples - 1:
		for ix in _samples - 1:
			var a := iz * _samples + ix
			var b := a + 1
			var c := a + _samples
			var d := c + 1
			tool.add_index(a)
			tool.add_index(b)
			tool.add_index(c)
			tool.add_index(b)
			tool.add_index(d)
			tool.add_index(c)
	tool.generate_tangents()  # UV runs along world X/Z, as the dirt shader expects
	tool.set_material(MATERIAL)
	return tool.commit()
