extends RefCounted

const BALL_MODEL = "res://assets/models/basketball.gltf"
const COURT_MODEL = "res://assets/models/court.gltf"
const BASKET_MODEL = "res://assets/models/basket.gltf"
const RIM_MODEL = "res://assets/models/rim.glb"
const BACKBOARD_MODEL = "res://assets/models/backboard.glb"
const NET_MODEL = "res://assets/models/net.glb"
const SUPPORT_MODEL = "res://assets/models/support.glb"
const FENCE_MODEL = "res://assets/models/fence.gltf"
const ENVIRONMENT_MODEL = "res://assets/models/environment.gltf"

## scale 1 unit = 1 meter
const BALL_SCALE = Vector3.ONE
const COURT_SCALE = Vector3.ONE
const BASKET_SCALE = Vector3.ONE
const RIM_SCALE = Vector3.ONE
const BACKBOARD_SCALE = Vector3.ONE
const NET_SCALE = Vector3.ONE
const SUPPORT_SCALE = Vector3.ONE
const FENCE_SCALE = Vector3.ONE
const ENVIRONMENT_SCALE = Vector3.ONE


static func add_model(parent: Node3D, resource_path: String, model_name: String, at: Vector3 = Vector3.ZERO, visual_scale: Vector3 = Vector3.ONE) -> bool:
	if not ResourceLoader.exists(resource_path):
		return false

	var resource: Resource = ResourceLoader.load(resource_path)
	var visual: Node3D = null

	if resource is PackedScene:
		var instance: Node = (resource as PackedScene).instantiate()
		if instance is Node3D:
			visual = instance as Node3D
		else:
			instance.queue_free()
	elif resource is Mesh:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = resource as Mesh
		visual = mesh_instance

	if visual == null:
		push_warning("Model musi zawierać Node3D/PackedScene lub Mesh: " + resource_path)
		return false

	visual.name = model_name
	
	_remove_imported_colliders(visual)
	parent.add_child(visual)
	visual.position = at
	visual.scale = visual_scale
	return true


static func _remove_imported_colliders(node: Node) -> void:
	if node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 0
		(node as CollisionObject3D).collision_mask = 0
	for child in node.get_children():
		_remove_imported_colliders(child)
