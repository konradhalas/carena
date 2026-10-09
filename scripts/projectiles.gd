class_name Projectiles
extends Node3D
## All projectiles in the scene (one instance per level, group "projectiles").
##
## The server simulates projectiles as plain data (ray segment per tick) and
## alone decides hits and damage. Every peer gets a "shot fired" RPC and
## animates a purely visual tracer along the same line; tracers stop on
## whatever they hit locally, which is close enough for visuals.

@export var speed := 90.0
@export var lifetime := 1.2
@export var damage := 8.0
@export var hit_impulse := 400.0  ## N·s pushed into the hit car
@export var tracer_length := 1.6

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
			var killed := target.apply_damage(damage)
			if killed and is_instance_valid(shot.shooter):
				shot.shooter.kills += 1


@rpc("authority", "call_local", "unreliable")
func _show_tracer(origin: Vector3, velocity: Vector3, shooter_path: NodePath) -> void:
	if _is_headless:
		return
	Effects.muzzle_flash(self, origin, velocity)
	var tracer := Tracer.new()
	tracer.node = _make_tracer_mesh()
	tracer.velocity = velocity
	tracer.time_left = lifetime
	var shooter := get_node_or_null(shooter_path) as CollisionObject3D
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
		var from := tracer.node.global_position
		var to := from + tracer.velocity * delta
		var hit := _cast(from, to, tracer.exclude)
		tracer.time_left -= delta
		if hit.is_empty() and tracer.time_left > 0.0:
			tracer.node.global_position = to
			continue
		if not hit.is_empty():
			Effects.impact(self, hit.position, hit.normal)
		tracer.node.queue_free()
		_tracers.remove_at(i)


func _cast(from: Vector3, to: Vector3, exclude: Array[RID]) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, exclude)
	return get_world_3d().direct_space_state.intersect_ray(query)


func _make_tracer_mesh() -> Node3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.07
	mesh.height = tracer_length
	mesh.material = Effects.glow_material(Color(1.0, 0.85, 0.3), 6.0)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Capsule's long axis is Y; pivot it so the node's -Z points along travel.
	instance.rotation.x = PI / 2
	var root := Node3D.new()
	root.add_child(instance)
	return root


static func _orient(node: Node3D, velocity: Vector3) -> void:
	var up := Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.RIGHT
	node.look_at(node.global_position + velocity, up)
