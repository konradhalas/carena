class_name Effects
extends RefCounted
## Short-lived visual effects. Visual only: never call from code whose
## outcome matters, and they no-op on headless servers.

const SPARK_COLOR := Color(1.0, 0.75, 0.3)
const FIRE_COLOR := Color(1.0, 0.5, 0.15)

# Particle setups are built once and shared by every burst.
static var _spark_material: ParticleProcessMaterial
static var _spark_mesh: Mesh
static var _debris_material: ParticleProcessMaterial
static var _debris_mesh: Mesh
static var _smoke_material: ParticleProcessMaterial
static var _smoke_mesh: Mesh


## Car destroyed: fireball, flying debris and a column of dark smoke.
static func explosion(parent: Node, position: Vector3) -> void:
	if not _can_spawn(parent):
		return
	_burst(parent, position, 3.2, FIRE_COLOR, 0.7, 14.0)
	if _debris_material == null:
		_build_debris()
	if _smoke_material == null:
		_build_smoke()
	_one_shot(parent, position, Vector3.UP, _debris_material, _debris_mesh, 18, 1.8)
	_one_shot(parent, position, Vector3.UP, _smoke_material, _smoke_mesh, 26, 3.0)


## Bullet impact: a small flash and sparks bouncing off along the normal.
static func impact(parent: Node, position: Vector3, normal: Vector3) -> void:
	if not _can_spawn(parent):
		return
	_burst(parent, position, 0.3, SPARK_COLOR, 0.12, 2.5)
	if _spark_material == null:
		_build_sparks()
	_one_shot(parent, position, normal, _spark_material, _spark_mesh, 14, 0.6)


## Cannon shell hit: fireball, a spray of sparks and a puff of smoke.
static func shell_impact(parent: Node, position: Vector3, normal: Vector3) -> void:
	if not _can_spawn(parent):
		return
	_burst(parent, position, 1.6, FIRE_COLOR, 0.35, 8.0)
	if _spark_material == null:
		_build_sparks()
	if _smoke_material == null:
		_build_smoke()
	_one_shot(parent, position, normal, _spark_material, _spark_mesh, 26, 0.7)
	_one_shot(parent, position, normal, _smoke_material, _smoke_mesh, 6, 1.6)


## Pickup collected: a quick coloured flash.
static func pickup_flash(parent: Node, position: Vector3, color: Color) -> void:
	if not _can_spawn(parent):
		return
	_burst(parent, position, 2.2, color, 0.3, 5.0)


## Gun firing: a brief elongated flash pointing along `direction`, plus light.
static func muzzle_flash(parent: Node, position: Vector3, direction: Vector3) -> void:
	if not _can_spawn(parent):
		return
	var root := _spawn_root(parent, position)
	var up := Vector3.UP if absf(direction.normalized().y) < 0.99 else Vector3.RIGHT
	root.look_at(position + direction, up)
	root.reset_physics_interpolation()
	var flash := SphereMesh.new()
	flash.radius = 0.32
	flash.height = 0.64
	var material := glow_material(Color(1.0, 0.85, 0.5), 8.0)
	flash.material = material
	var mesh := MeshInstance3D.new()
	mesh.mesh = flash
	mesh.scale = Vector3(1.0, 1.0, 2.6)  # stretched forward (-Z)
	mesh.position = Vector3(0, 0, -0.3)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mesh)
	var omni := OmniLight3D.new()
	omni.light_color = Color(1.0, 0.75, 0.4)
	omni.light_energy = 6.0
	omni.omni_range = 8.0
	root.add_child(omni)
	var tween := root.create_tween().set_parallel()
	tween.tween_property(material, "albedo_color:a", 0.0, 0.1)
	tween.tween_property(omni, "light_energy", 0.0, 0.1)
	tween.chain().tween_callback(root.queue_free)


static func glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


static func _can_spawn(parent: Node) -> bool:
	return DisplayServer.get_name() != "headless" and parent.is_inside_tree()


static func _spawn_root(parent: Node, position: Vector3) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = position
	root.reset_physics_interpolation()  # don't streak in from the origin
	return root


## Expanding glowing sphere with a light that fades out.
static func _burst(
	parent: Node, position: Vector3, size: float, color: Color, duration: float, light: float
) -> void:
	var root := _spawn_root(parent, position)
	var sphere := SphereMesh.new()
	sphere.radius = size * 0.5
	sphere.height = size
	var material := glow_material(color, 4.0)
	sphere.material = material
	var mesh := MeshInstance3D.new()
	mesh.mesh = sphere
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mesh)

	var omni := OmniLight3D.new()
	omni.light_color = color
	omni.light_energy = light
	omni.omni_range = size * 4.0
	root.add_child(omni)

	mesh.scale = Vector3.ONE * 0.3
	var tween := root.create_tween().set_parallel()
	tween.tween_property(mesh, "scale", Vector3.ONE, duration).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, duration)
	tween.tween_property(omni, "light_energy", 0.0, duration)
	tween.chain().tween_callback(root.queue_free)


## Fire-and-forget particle burst, aimed so local +Y points along `direction`.
static func _one_shot(
	parent: Node,
	position: Vector3,
	direction: Vector3,
	process: ParticleProcessMaterial,
	mesh: Mesh,
	amount: int,
	lifetime: float
) -> void:
	var particles := GPUParticles3D.new()
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.amount = amount
	particles.lifetime = lifetime
	particles.process_material = process
	particles.draw_pass_1 = mesh
	particles.local_coords = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-20, -5, -20), Vector3(40, 30, 40))
	parent.add_child(particles)
	var up := direction.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	particles.global_transform = Transform3D(Basis(side, up, side.cross(up)), position)
	particles.reset_physics_interpolation()
	particles.finished.connect(particles.queue_free)
	particles.emitting = true


static func _build_sparks() -> void:
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 55.0
	process.initial_velocity_min = 4.0
	process.initial_velocity_max = 10.0
	process.gravity = Vector3(0, -18, 0)
	process.scale_min = 0.6
	process.scale_max = 1.2
	_spark_material = process
	var mesh := SphereMesh.new()
	mesh.radius = 0.035
	mesh.height = 0.07
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.material = glow_material(SPARK_COLOR, 10.0)
	_spark_mesh = mesh


static func _build_debris() -> void:
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 65.0
	process.initial_velocity_min = 7.0
	process.initial_velocity_max = 14.0
	process.gravity = Vector3(0, -20, 0)
	process.angular_velocity_min = -720.0
	process.angular_velocity_max = 720.0
	process.scale_min = 0.5
	process.scale_max = 1.3
	_debris_material = process
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.3, 0.12, 0.22)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.08, 0.08, 0.09)
	material.roughness = 0.8
	mesh.material = material
	_debris_mesh = mesh


static func _build_smoke() -> void:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 1.0
	process.direction = Vector3.UP
	process.spread = 30.0
	process.initial_velocity_min = 1.5
	process.initial_velocity_max = 4.0
	process.gravity = Vector3(0, 0.8, 0)
	process.damping_min = 0.8
	process.damping_max = 1.5
	process.angle_min = -180.0
	process.angle_max = 180.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.6))
	grow.add_point(Vector2(1.0, 3.0))
	var scale_curve := CurveTexture.new()
	scale_curve.curve = grow
	process.scale_curve = scale_curve
	var fade := Gradient.new()
	fade.set_color(0, Color(0.12, 0.11, 0.1, 0.8))
	fade.set_color(1, Color(0.2, 0.19, 0.18, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	_smoke_material = process

	var puff := Gradient.new()
	puff.set_color(0, Color(1, 1, 1, 1))
	puff.set_color(1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = puff
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.proximity_fade_enabled = true
	material.proximity_fade_distance = 1.0
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2.2, 2.2)
	mesh.material = material
	_smoke_mesh = mesh
