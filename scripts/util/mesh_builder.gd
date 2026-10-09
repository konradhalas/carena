class_name MeshBuilder
extends RefCounted
## Procedural meshes with softened edges. Real objects never have perfectly
## sharp corners; a small bevel catches highlights and is one of the cheapest
## ways to stop primitives looking like programmer art.


## Box centred on the origin with every edge cut at 45° by `bevel` (m).
## Flat-shaded, no UVs (use triplanar materials).
static func chamfered_box(size: Vector3, bevel: float, material: Material = null) -> ArrayMesh:
	var half := size * 0.5
	var cut := minf(bevel, minf(half.x, minf(half.y, half.z)) * 0.99)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var signs: Array[float] = [-1.0, 1.0]

	# The 6 main faces.
	for s in signs:
		_add_polygon(
			tool,
			[
				_px(half, cut, s, -1, -1),
				_px(half, cut, s, 1, -1),
				_px(half, cut, s, 1, 1),
				_px(half, cut, s, -1, 1)
			]
		)
		_add_polygon(
			tool,
			[
				_py(half, cut, -1, s, -1),
				_py(half, cut, 1, s, -1),
				_py(half, cut, 1, s, 1),
				_py(half, cut, -1, s, 1)
			]
		)
		_add_polygon(
			tool,
			[
				_pz(half, cut, -1, -1, s),
				_pz(half, cut, 1, -1, s),
				_pz(half, cut, 1, 1, s),
				_pz(half, cut, -1, 1, s)
			]
		)

	# The 12 bevelled edges and 8 corner triangles.
	for a in signs:
		for b in signs:
			_add_polygon(
				tool,
				[
					_px(half, cut, a, b, -1),
					_px(half, cut, a, b, 1),
					_py(half, cut, a, b, 1),
					_py(half, cut, a, b, -1)
				]
			)
			_add_polygon(
				tool,
				[
					_px(half, cut, a, -1, b),
					_px(half, cut, a, 1, b),
					_pz(half, cut, a, 1, b),
					_pz(half, cut, a, -1, b)
				]
			)
			_add_polygon(
				tool,
				[
					_py(half, cut, -1, a, b),
					_py(half, cut, 1, a, b),
					_pz(half, cut, 1, a, b),
					_pz(half, cut, -1, a, b)
				]
			)
			for c in signs:
				_add_polygon(
					tool,
					[_px(half, cut, a, b, c), _py(half, cut, a, b, c), _pz(half, cut, a, b, c)]
				)
	if material:
		tool.set_material(material)
	return tool.commit()


## Tyre: a rounded profile revolved around the X axis (the axle), centred on
## the origin. Smooth-shaded; UV.x runs around the tyre, UV.y across it.
static func tyre(
	radius: float, width: float, rim_radius: float, corner: float, material: Material = null
) -> ArrayMesh:
	# Profile as (distance from axle, position along axle), inner rim edge to
	# inner rim edge over the tread.
	var half := width * 0.5
	var profile := PackedVector2Array()
	profile.append(Vector2(rim_radius, -half))
	for i in 5:  # sidewall -> tread
		var t := PI * 0.5 * i / 4.0
		profile.append(Vector2(radius - corner + corner * sin(t), -half + corner - corner * cos(t)))
	for i in 5:  # tread -> sidewall
		var t := PI * 0.5 * i / 4.0
		profile.append(Vector2(radius - corner + corner * cos(t), half - corner + corner * sin(t)))
	profile.append(Vector2(rim_radius, half))
	return lathe(profile, 32, material)


## Coil spring along +Y from 0 to 1 (scale Y to set length): a round wire
## swept along a helix. Smooth-shaded.
static func coil_spring(
	coils: float, radius: float, wire: float, material: Material = null
) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := int(coils * 16)
	var sides := 6
	for i in steps + 1:
		var t := float(i) / steps
		var angle := TAU * coils * t
		var centre := Vector3(cos(angle) * radius, t, sin(angle) * radius)
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		for j in sides:
			var around := TAU * j / sides
			var offset := (outward * cos(around) + Vector3.UP * sin(around)) * wire
			tool.set_normal(offset.normalized())
			tool.add_vertex(centre + offset)
	for i in steps:
		for j in sides:
			var a := i * sides + j
			var b := i * sides + (j + 1) % sides
			var c := a + sides
			var d := b + sides
			for index in [a, c, b, b, c, d]:
				tool.add_index(index)
	if material:
		tool.set_material(material)
	return tool.commit()


## Revolves a (radius, axial) profile around the X axis.
static func lathe(
	profile: PackedVector2Array, segments: int, material: Material = null
) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := profile.size()
	for s in segments + 1:
		var angle := TAU * s / segments
		for i in rings:
			var point := profile[i]
			tool.set_uv(Vector2(float(s) / segments, float(i) / (rings - 1)))
			tool.add_vertex(Vector3(point.y, point.x * cos(angle), point.x * sin(angle)))
	for s in segments:
		for i in rings - 1:
			var a := s * rings + i
			var b := a + 1
			var c := a + rings
			var d := c + 1
			for index in [a, b, c, b, d, c]:  # clockwise seen from outside
				tool.add_index(index)
	tool.generate_normals()
	if material:
		tool.set_material(material)
	return tool.commit()


## Adds a convex polygon of a shape centred on the origin, flat-shaded, wound
## so it faces outwards (Godot treats clockwise as front-facing).
static func _add_polygon(tool: SurfaceTool, points: Array) -> void:
	var centre := Vector3.ZERO
	for point: Vector3 in points:
		centre += point
	centre /= points.size()
	var normal := ((points[1] - points[0]) as Vector3).cross(points[2] - points[0]).normalized()
	if normal.dot(centre) > 0.0:
		points.reverse()
	else:
		normal = -normal
	for i in range(1, points.size() - 1):
		for point: Vector3 in [points[0], points[i], points[i + 1]]:
			tool.set_normal(normal)
			tool.add_vertex(point)


# Corner points of a chamfered box, one per adjoining face.
static func _px(half: Vector3, cut: float, sx: float, sy: float, sz: float) -> Vector3:
	return Vector3(sx * half.x, sy * (half.y - cut), sz * (half.z - cut))


static func _py(half: Vector3, cut: float, sx: float, sy: float, sz: float) -> Vector3:
	return Vector3(sx * (half.x - cut), sy * half.y, sz * (half.z - cut))


static func _pz(half: Vector3, cut: float, sx: float, sy: float, sz: float) -> Vector3:
	return Vector3(sx * (half.x - cut), sy * (half.y - cut), sz * half.z)
