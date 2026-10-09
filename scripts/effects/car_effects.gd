class_name CarEffects
extends Node3D
## Per-car ground effects: tyre marks under every wheel and dust behind the
## rear wheels. Fed each physics tick by Car with wheel contact data, on every
## peer (remote cars included). Visual only; Car doesn't create it headless.

const TRACK_SEGMENT := 0.6  ## m between mark segments
const TRACK_WIDTH := 0.55
const TELEPORT_DISTANCE := 3.0  ## longer jumps (respawn, reset) break the trail
const DUST_WHEELS: Array[int] = [2, 3]  ## rear
const DUST_MIN_SPEED := 4.0
const DUST_FULL_SPEED := 28.0
const DUST_MIN_SLIP := 1.5  ## sideways m/s that starts dust on its own (drifts)
const DUST_SLIP_FULL := 6.0  ## sideways m/s that alone gives full dust
const DUST_COLOR := Color(0.62, 0.52, 0.4)

var _tracks: TireTracks
var _last_marks: Array = [null, null, null, null]  # Vector3 or null per wheel
var _dust := {}  # wheel index -> GPUParticles3D


func _ready() -> void:
	_tracks = get_tree().get_first_node_in_group("tire_tracks") as TireTracks
	var dust_material := _make_dust_process_material()
	var dust_mesh := _make_dust_mesh()
	for wheel in DUST_WHEELS:
		var particles := GPUParticles3D.new()
		particles.amount = 72
		particles.lifetime = 2.2
		particles.local_coords = false
		particles.process_material = dust_material
		particles.draw_pass_1 = dust_mesh
		particles.emitting = false
		particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		particles.visibility_aabb = AABB(Vector3(-15, -5, -15), Vector3(30, 15, 30))
		add_child(particles)
		_dust[wheel] = particles


## Called by Car for each wheel every physics tick.
func wheel_contact(
	wheel: int, grounded: bool, point: Vector3, normal: Vector3, velocity: Vector3, right: Vector3
) -> void:
	_update_tracks(wheel, grounded, point, normal)
	if _dust.has(wheel):
		_update_dust(_dust[wheel], grounded, point, velocity, right)


func _update_tracks(wheel: int, grounded: bool, point: Vector3, normal: Vector3) -> void:
	if _tracks == null:
		return
	var last: Variant = _last_marks[wheel]
	if not grounded or last == null:
		_last_marks[wheel] = point if grounded else null
		return
	var distance := point.distance_to(last)
	if distance > TELEPORT_DISTANCE:
		_last_marks[wheel] = point
	elif distance >= TRACK_SEGMENT:
		_tracks.add_segment(last, point, normal, TRACK_WIDTH)
		_last_marks[wheel] = point


func _update_dust(
	particles: GPUParticles3D, grounded: bool, point: Vector3, velocity: Vector3, right: Vector3
) -> void:
	var speed := velocity.length()
	var slip := absf(velocity.dot(right))
	# Only real motion kicks up dust: suspension jitter at rest gives tiny
	# but non-zero speeds, which must not count.
	var moving := speed >= DUST_MIN_SPEED or slip >= DUST_MIN_SLIP
	var strength := maxf(
		inverse_lerp(DUST_MIN_SPEED, DUST_FULL_SPEED, speed), slip / DUST_SLIP_FULL
	)
	particles.emitting = grounded and moving
	particles.amount_ratio = clampf(strength, 0.15, 1.0)
	particles.global_position = point


static func _make_dust_process_material() -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.3
	material.direction = Vector3.UP
	material.spread = 70.0
	material.initial_velocity_min = 1.0
	material.initial_velocity_max = 3.0
	material.gravity = Vector3(0, 0.15, 0)  # fine dust hangs and drifts up
	material.damping_min = 1.5
	material.damping_max = 2.5
	material.angle_min = -180.0
	material.angle_max = 180.0
	material.scale_min = 0.8
	material.scale_max = 1.4

	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 3.5))
	var scale_curve := CurveTexture.new()
	scale_curve.curve = grow
	material.scale_curve = scale_curve

	var fade := Gradient.new()
	fade.set_color(0, Color(DUST_COLOR, 0.7))
	fade.set_color(1, Color(DUST_COLOR, 0.0))
	var color_ramp := GradientTexture1D.new()
	color_ramp.gradient = fade
	material.color_ramp = color_ramp
	return material


static func _make_dust_mesh() -> QuadMesh:
	var puff := Gradient.new()
	puff.set_color(0, Color(1, 1, 1, 1))
	puff.set_color(1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = puff
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 64
	texture.height = 64

	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	# Soft particles: fade where puffs cut into the ground, no hard edges.
	material.proximity_fade_enabled = true
	material.proximity_fade_distance = 1.0
	material.roughness = 1.0
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.8, 1.8)
	mesh.material = material
	return mesh
