extends RefCounted
## Paths of external assets (all CC0 - see assets/CREDITS.md). Scale: 1 unit = 1 metre.

const BALL_MODEL = "res://assets/models/basketball.gltf"
const BENCH_MODEL = "res://assets/models/props/painted_wooden_bench/painted_wooden_bench_1k.gltf"
const TRASH_CAN_MODEL = "res://assets/models/props/metal_trash_can/metal_trash_can_1k.gltf"
const PICNIC_TABLE_MODEL = "res://assets/models/props/wooden_picnic_table/wooden_picnic_table_1k.gltf"
const SHRUB_MODEL = "res://assets/models/props/shrub_03/shrub_03_1k.gltf"

const SKY_HDRI = "res://assets/hdri/pretoria_gardens_2k.hdr"
## Brightest pixel of the HDRI (the sun), in panorama UV coordinates.
const SKY_SUN_UV = Vector2(0.5999, 0.2095)

const COURT_NORMAL = "res://assets/textures/court/rubberized_track_nor_gl_1k.jpg"
const COURT_ROUGHNESS = "res://assets/textures/court/rubberized_track_rough_1k.jpg"
const COURT_DIFFUSE = "res://assets/textures/court/rubberized_track_diff_1k.jpg"
const ASPHALT_DIFFUSE = "res://assets/textures/asphalt/clean_asphalt_diff_1k.jpg"
const GRASS_DIFFUSE = "res://assets/textures/grass/Grass004_1K-JPG_Color.jpg"
const GRASS_NORMAL = "res://assets/textures/grass/Grass004_1K-JPG_NormalGL.jpg"
const GRASS_ROUGHNESS = "res://assets/textures/grass/Grass004_1K-JPG_Roughness.jpg"


static func texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		push_warning("Brak tekstury: " + path)
		return null
	return load(path) as Texture2D


static func add_model(parent: Node3D, resource_path: String, model_name: String, at: Vector3 = Vector3.ZERO, yaw_degrees: float = 0.0, visual_scale: float = 1.0) -> Node3D:
	if not ResourceLoader.exists(resource_path):
		push_warning("Brak modelu: " + resource_path)
		return null
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
		return null
	visual.name = model_name
	_disable_imported_colliders(visual)
	parent.add_child(visual)
	visual.position = at
	visual.rotation_degrees.y = yaw_degrees
	visual.scale = Vector3.ONE * visual_scale
	return visual


static func _disable_imported_colliders(node: Node) -> void:
	if node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 0
		(node as CollisionObject3D).collision_mask = 0
	for child in node.get_children():
		_disable_imported_colliders(child)
