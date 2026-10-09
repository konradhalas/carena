class_name Effects
extends RefCounted
## Short-lived visual effects built from primitives. Visual only: never call
## from code whose outcome matters, and they no-op on headless servers.


static func explosion(parent: Node, position: Vector3) -> void:
	_burst(parent, position, 2.5, Color(1.0, 0.5, 0.15), 0.6, 8.0)


static func spark(parent: Node, position: Vector3) -> void:
	_burst(parent, position, 0.35, Color(1.0, 0.85, 0.4), 0.15, 2.0)


static func glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


static func _burst(
	parent: Node, position: Vector3, size: float, color: Color, duration: float, light: float
) -> void:
	if DisplayServer.get_name() == "headless" or not parent.is_inside_tree():
		return
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = position
	root.reset_physics_interpolation()  # don't streak in from the origin

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
