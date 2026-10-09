class_name Projectiles
extends Node3D
## All projectiles in the scene (one instance per level, group "projectiles").
##
## The server simulates projectiles as plain data (ray segment per tick) and
## alone decides hits and damage. Every peer gets a "shot fired" RPC and
## animates a purely visual shell along the same arc; shells stop on
## whatever they hit locally, which is close enough for visuals.
##
## The weapon is a slow, heavy cannon: few hits kill, shells are visible in
## flight and drop slightly, and every hit shoves the target hard.

@export var speed := 60.0
@export var lifetime := 1.6
@export var damage := 25.0
@export var gravity := Vector3(0, -4.0, 0)  ## shells arc a little
@export var hit_impulse := 2200.0  ## N·s pushed into the hit car
@export var trail_length := 2.6

var _shots: Array[Shot] = []  # server only
var _tracers: Array[Tracer] = []  # every peer with a display

@onready var _is_headless := DisplayServer.get_name() == "headless"


class Shot:
	var position: Vector3
	var velocity: Vector3
	var time_left: float
	var shooter: Car


class Tracer:
	var node: Node3D
	var velocity: Vector3
	var time_left: float
	var exclude: Array[RID]


## Server only: fires a projectile from the car's muzzle.
func fire(shooter: Car, origin: Vector3, direction: Vector3) -> void:
	var shot := Shot.new()
	shot.position = origin
	shot.velocity = direction.normalized() * speed + shooter.linear_velocity
	shot.time_left = lifetime
	shot.shooter = shooter
	_shots.append(shot)
	_show_tracer.rpc(origin, shot.velocity, get_path_to(shooter))


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_step_shots(delta)
	_step_tracers(delta)


func _step_shots(delta: float) -> void:
	for i in range(_shots.size() - 1, -1, -1):
		var shot := _shots[i]
		shot.velocity += gravity * delta
		var next := shot.position + shot.velocity * delta
		var exclude: Array[RID] = []
		if is_instance_valid(shot.shooter):
			exclude.append(shot.shooter.get_rid())
		var hit := _cast(shot.position, next, exclude)
		shot.time_left -= delta
		if hit.is_empty() and shot.time_left > 0.0:
			shot.position = next
			continue
		_shots.remove_at(i)
		if hit.is_empty():
			continue
		var target := hit.collider as Car
		if target:
			var hit_offset: Vector3 = hit.position - target.global_position
			target.apply_impulse(shot.velocity.normalized() * hit_impulse, hit_offset)
			var shooter_id := shot.shooter.owner_peer_id if is_instance_valid(shot.shooter) else 0
			var killed := target.apply_damage(damage, shooter_id)
			if killed and is_instance_valid(shot.shooter):
				shot.shooter.kills += 1


@rpc("authority", "call_local", "unreliable")
func _show_tracer(origin: Vector3, velocity: Vector3, shooter_path: NodePath) -> void:
	var shooter := get_node_or_null(shooter_path) as Car
	if shooter:
		shooter.weapon_fired.emit()
	if _is_headless:
		return
	Effects.muzzle_flash(self, origin, velocity)
	Sfx.play_at(self, "cannon", origin, -2.0, 0.05)
	var tracer := Tracer.new()
	tracer.node = _make_tracer_mesh()
	tracer.velocity = velocity
	tracer.time_left = lifetime
	if shooter:
		tracer.exclude.append(shooter.get_rid())
	add_child(tracer.node)
	tracer.node.global_position = origin
	_orient(tracer.node, velocity)
	tracer.node.reset_physics_interpolation()  # don't streak in from the origin
	_tracers.append(tracer)


func _step_tracers(delta: float) -> void:
	for i in range(_tracers.size() - 1, -1, -1):
		var tracer := _tracers[i]
		tracer.velocity += gravity * delta
		var from := tracer.node.global_position
		var to := from + tracer.velocity * delta
		var hit := _cast(from, to, tracer.exclude)
		tracer.time_left -= delta
		if hit.is_empty() and tracer.time_left > 0.0:
			tracer.node.global_position = to
			_orient(tracer.node, tracer.velocity)
			continue
		if not hit.is_empty():
			Effects.shell_impact(self, hit.position, hit.normal)
			var sound := "impact_metal" if hit.collider is Car else "impact_dirt"
			Sfx.play_at(self, sound, hit.position, 0.0, 0.1)
		tracer.node.queue_free()
		_tracers.remove_at(i)


func _cast(from: Vector3, to: Vector3, exclude: Array[RID]) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, exclude)
	return get_world_3d().direct_space_state.intersect_ray(query)


## A glowing shell: hot core, a fading trail behind it (+Z, since the node's
## -Z points along travel) and a small light so it lights up what it passes.
func _make_tracer_mesh() -> Node3D:
	var root := Node3D.new()

	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.15
	core_mesh.height = 0.3
	core_mesh.material = Effects.glow_material(Color(1.0, 0.72, 0.35), 12.0)
	var core := MeshInstance3D.new()
	core.mesh = core_mesh
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)

	var trail_mesh := CylinderMesh.new()
	trail_mesh.top_radius = 0.0
	trail_mesh.bottom_radius = 0.16
	trail_mesh.height = trail_length
	var trail_material := Effects.glow_material(Color(1.0, 0.5, 0.12, 0.6), 5.0)
	trail_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	trail_mesh.material = trail_material
	var trail := MeshInstance3D.new()
	trail.mesh = trail_mesh
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Cylinder axis is Y (wide end at -Y); lay it along +Z, wide end at the core.
	trail.rotation.x = -PI / 2
	trail.position.z = trail_length * 0.5
	root.add_child(trail)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 2.0
	light.omni_range = 5.0
	root.add_child(light)
	return root


static func _orient(node: Node3D, velocity: Vector3) -> void:
	var up := Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.RIGHT
	node.look_at(node.global_position + velocity, up)
