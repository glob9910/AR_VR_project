extends Node3D
## Outdoor FIBA court in a park on a sunny day: HDRI sky, lawn, fenced court,
## two hoops, floodlight masts and a few CC0 props.

const FIBA = preload("res://scripts/fiba.gd")
const ASSETS = preload("res://scripts/assets.gd")
const HOOP_SCRIPT = preload("res://scripts/hoop.gd")
const COURT_SHADER = preload("res://shaders/court.gdshader")
const GRASS_SHADER = preload("res://shaders/grass.gdshader")
const CHAIN_LINK_SHADER = preload("res://shaders/chain_link.gdshader")

const RUNOFF = Vector2(2.0, 2.5)
const FENCE_HEIGHT = 3.6
const POST_SPACING = 2.5
## Restitution of the court surface for the default FIBA ball (1.8 m drop -> ~1.06 m
## to the bottom of the ball, i.e. ~1.3 m to its top).
const DEFAULT_ELASTICITY = 0.79

var hoops: Array = []
var fence_half := Vector2(FIBA.COURT_WIDTH * 0.5 + RUNOFF.x, FIBA.COURT_LENGTH * 0.5 + RUNOFF.y)
var _surfaces: Array = []
var _environment: Environment
var _sun: DirectionalLight3D


func _ready() -> void:
	_make_sky_and_light()
	_make_ground()
	_make_fence()
	for end_sign in [-1.0, 1.0]:
		var hoop := HOOP_SCRIPT.new()
		hoop.name = "Hoop" + ("Main" if end_sign < 0.0 else "Far")
		hoop.register_surface = register_surface
		hoop.position = FIBA.rim_center(end_sign)
		hoop.rotation.y = 0.0 if end_sign < 0.0 else PI
		add_child(hoop)
		hoops.append(hoop)
	_make_floodlights()
	_place_props()
	set_elasticity(DEFAULT_ELASTICITY)


func register_surface(material: PhysicsMaterial, factor: float) -> void:
	_surfaces.append([material, factor])


## Scales the restitution of every surface (court = 1.0, other materials relative to it).
func set_elasticity(value: float) -> void:
	for entry in _surfaces:
		(entry[0] as PhysicsMaterial).bounce = clampf(value * float(entry[1]), 0.0, 1.0)


func rim_centers() -> Array:
	var result: Array = []
	for hoop in hoops:
		result.append(hoop.global_position)
	return result


func set_quality(high: bool) -> void:
	_environment.ssao_enabled = high
	_environment.glow_enabled = high
	_sun.directional_shadow_max_distance = 70.0 if high else 40.0
	_sun.shadow_blur = 1.0 if high else 0.5
	get_viewport().msaa_3d = Viewport.MSAA_4X if high else Viewport.MSAA_DISABLED


static func panorama_direction(uv: Vector2) -> Vector3:
	# Inverse of Godot's panorama lookup: u = atan2(x, -z) / TAU, v = acos(y) / PI.
	var phi := uv.x * TAU
	var theta := uv.y * PI
	return Vector3(sin(phi) * sin(theta), cos(theta), -cos(phi) * sin(theta)).normalized()


func _make_sky_and_light() -> void:
	var sky_material := PanoramaSkyMaterial.new()
	sky_material.panorama = ASSETS.texture(ASSETS.SKY_HDRI)
	sky_material.energy_multiplier = 1.0
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_256

	_environment = Environment.new()
	_environment.background_mode = Environment.BG_SKY
	_environment.sky = sky
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_environment.ambient_light_energy = 1.0
	_environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_environment.tonemap_exposure = 1.0
	_environment.tonemap_white = 6.0
	_environment.ssao_enabled = true
	_environment.ssao_radius = 0.8
	_environment.ssao_intensity = 1.6
	_environment.glow_enabled = true
	_environment.glow_intensity = 0.35
	_environment.glow_bloom = 0.04
	_environment.glow_hdr_threshold = 1.4
	_environment.fog_enabled = true
	_environment.fog_light_color = Color(0.72, 0.8, 0.9)
	_environment.fog_density = 0.0016
	_environment.fog_aerial_perspective = 0.85
	_environment.fog_sky_affect = 0.0
	_environment.adjustment_enabled = true
	_environment.adjustment_saturation = 1.08
	var world := WorldEnvironment.new()
	world.name = "ParkEnvironment"
	world.environment = _environment
	add_child(world)

	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	var toward_sun := panorama_direction(ASSETS.SKY_SUN_UV)
	add_child(_sun)
	_sun.look_at_from_position(Vector3.ZERO, -toward_sun, Vector3.UP if absf(toward_sun.y) < 0.99 else Vector3.FORWARD)
	_sun.light_color = Color(1.0, 0.96, 0.88)
	_sun.light_energy = 1.6
	_sun.light_angular_distance = 0.6
	_sun.shadow_enabled = true
	_sun.shadow_bias = 0.03
	_sun.shadow_normal_bias = 1.2
	_sun.shadow_blur = 1.0
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_sun.directional_shadow_max_distance = 70.0


func _surface_body(body_name: String, center: Vector3, size: Vector3, factor: float, friction: float = 0.7) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = center
	body.add_child(shape)
	var material := PhysicsMaterial.new()
	material.friction = friction
	body.physics_material_override = material
	register_surface(material, factor)
	add_child(body)
	return body


func _make_ground() -> void:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	noise.fractal_octaves = 3
	var macro := NoiseTexture2D.new()
	macro.width = 256
	macro.height = 256
	macro.seamless = true
	macro.noise = noise

	var grass_material := ShaderMaterial.new()
	grass_material.shader = GRASS_SHADER
	grass_material.set_shader_parameter("albedo_tex", ASSETS.texture(ASSETS.GRASS_DIFFUSE))
	grass_material.set_shader_parameter("normal_tex", ASSETS.texture(ASSETS.GRASS_NORMAL))
	grass_material.set_shader_parameter("roughness_tex", ASSETS.texture(ASSETS.GRASS_ROUGHNESS))
	grass_material.set_shader_parameter("macro_noise", macro)
	var lawn := MeshInstance3D.new()
	lawn.name = "Lawn"
	var lawn_mesh := PlaneMesh.new()
	lawn_mesh.size = Vector2(400, 400)
	lawn.mesh = lawn_mesh
	lawn.position.y = -0.03
	lawn.material_override = grass_material
	add_child(lawn)

	var court_material := ShaderMaterial.new()
	court_material.shader = COURT_SHADER
	court_material.set_shader_parameter("detail_albedo", ASSETS.texture(ASSETS.COURT_DIFFUSE))
	court_material.set_shader_parameter("detail_normal", ASSETS.texture(ASSETS.COURT_NORMAL))
	court_material.set_shader_parameter("detail_roughness", ASSETS.texture(ASSETS.COURT_ROUGHNESS))
	court_material.set_shader_parameter("wear_albedo", ASSETS.texture(ASSETS.ASPHALT_DIFFUSE))
	court_material.set_shader_parameter("court_half", Vector2(FIBA.COURT_WIDTH, FIBA.COURT_LENGTH) * 0.5)
	court_material.set_shader_parameter("line_width", FIBA.LINE_WIDTH)
	court_material.set_shader_parameter("rim_from_endline", FIBA.RIM_FROM_ENDLINE)
	court_material.set_shader_parameter("three_radius", FIBA.THREE_POINT_RADIUS)
	court_material.set_shader_parameter("three_side", FIBA.THREE_POINT_SIDE)
	court_material.set_shader_parameter("key_half_width", FIBA.KEY_WIDTH * 0.5)
	court_material.set_shader_parameter("free_throw", FIBA.FREE_THROW_DISTANCE)
	court_material.set_shader_parameter("circle_radius", FIBA.CIRCLE_RADIUS)
	court_material.set_shader_parameter("no_charge", FIBA.NO_CHARGE_RADIUS)
	var court := MeshInstance3D.new()
	court.name = "CourtSurface"
	var court_mesh := PlaneMesh.new()
	court_mesh.size = fence_half * 2.0 + Vector2(0.6, 0.6)
	court.mesh = court_mesh
	court.material_override = court_material
	add_child(court)

	# Concrete curb around the court slab.
	var curb := StandardMaterial3D.new()
	curb.albedo_texture = ASSETS.texture(ASSETS.ASPHALT_DIFFUSE)
	curb.albedo_color = Color(0.85, 0.85, 0.82)
	curb.uv1_triplanar = true
	curb.uv1_scale = Vector3(0.5, 0.5, 0.5)
	curb.roughness = 0.9
	var slab := MeshInstance3D.new()
	var slab_mesh := BoxMesh.new()
	slab_mesh.size = Vector3(court_mesh.size.x + 0.3, 0.12, court_mesh.size.y + 0.3)
	slab.mesh = slab_mesh
	slab.position.y = -0.065
	slab.material_override = curb
	add_child(slab)

	var floor_body := _surface_body("CourtFloor", Vector3(0, -0.1, 0), Vector3(court_mesh.size.x + 0.3, 0.2, court_mesh.size.y + 0.3), 1.0)
	floor_body.add_to_group("court_floor")
	_surface_body("Grass", Vector3(0, -0.13, 0), Vector3(400, 0.2, 400), 0.42, 0.9)


func _make_fence() -> void:
	var post_material := StandardMaterial3D.new()
	post_material.albedo_color = Color("#3b4a3f")
	post_material.metallic = 0.6
	post_material.roughness = 0.5
	var mesh_material := ShaderMaterial.new()
	mesh_material.shader = CHAIN_LINK_SHADER
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.035
	post_mesh.bottom_radius = 0.035
	post_mesh.height = FENCE_HEIGHT
	post_mesh.radial_segments = 10
	var rail_mesh := CylinderMesh.new()
	rail_mesh.top_radius = 0.022
	rail_mesh.bottom_radius = 0.022
	rail_mesh.radial_segments = 8
	rail_mesh.height = 1.0

	var corners := [
		Vector3(-fence_half.x, 0, -fence_half.y), Vector3(fence_half.x, 0, -fence_half.y),
		Vector3(fence_half.x, 0, fence_half.y), Vector3(-fence_half.x, 0, fence_half.y)
	]
	var posts := MultiMesh.new()
	posts.transform_format = MultiMesh.TRANSFORM_3D
	posts.mesh = post_mesh
	var rails := MultiMesh.new()
	rails.transform_format = MultiMesh.TRANSFORM_3D
	rails.mesh = rail_mesh
	var post_transforms: Array = []
	var rail_transforms: Array = []
	for side in range(4):
		var a: Vector3 = corners[side]
		var b: Vector3 = corners[(side + 1) % 4]
		var length := a.distance_to(b)
		var count := int(ceil(length / POST_SPACING))
		for i in range(count):
			post_transforms.append(Transform3D(Basis(), a.lerp(b, float(i) / count) + Vector3.UP * FENCE_HEIGHT * 0.5))
		var along := (b - a).normalized()
		# Cylinder axis is Y - stretch it along the fence side.
		var rail_basis := Basis(along.cross(Vector3.UP).normalized(), along * length, Vector3.UP)
		for height in [0.05, FENCE_HEIGHT * 0.5, FENCE_HEIGHT - 0.03]:
			rail_transforms.append(Transform3D(rail_basis, (a + b) * 0.5 + Vector3.UP * height))

		var panel := MeshInstance3D.new()
		panel.mesh = _fence_panel_mesh(length)
		panel.material_override = mesh_material
		panel.transform = Transform3D(Basis(along, Vector3.UP, along.cross(Vector3.UP)), (a + b) * 0.5)
		add_child(panel)

		var inward := -((a + b) * 0.5).normalized()
		var collider_center := (a + b) * 0.5 + Vector3.UP * FENCE_HEIGHT * 0.5 - inward * 0.05
		var size := Vector3(absf(along.x) * length + 0.1, FENCE_HEIGHT, absf(along.z) * length + 0.1)
		size = Vector3(maxf(size.x, 0.1), size.y, maxf(size.z, 0.1))
		_surface_body("Fence", collider_center, size, 0.35, 0.9)

	posts.instance_count = post_transforms.size()
	for i in range(post_transforms.size()):
		posts.set_instance_transform(i, post_transforms[i])
	rails.instance_count = rail_transforms.size()
	for i in range(rail_transforms.size()):
		rails.set_instance_transform(i, rail_transforms[i])
	for multimesh in [posts, rails]:
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		instance.material_override = post_material
		add_child(instance)


## Chain-link shader expects UV in metres, so the quad UV (0..1) is rescaled.
func _fence_panel_mesh(length: float) -> ArrayMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(length, FENCE_HEIGHT)
	quad.center_offset = Vector3(0, FENCE_HEIGHT * 0.5, 0)
	var arrays := quad.get_mesh_arrays()
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	for i in range(uvs.size()):
		uvs[i] = Vector2(uvs[i].x * length, uvs[i].y * FENCE_HEIGHT)
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_floodlights() -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("#6d747a")
	steel.metallic = 0.8
	steel.roughness = 0.4
	var lamp_glass := StandardMaterial3D.new()
	lamp_glass.albedo_color = Color("#e8eef2")
	lamp_glass.emission_enabled = true
	lamp_glass.emission = Color("#fff6e0")
	lamp_glass.emission_energy_multiplier = 0.3
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var base := Vector3(sx * (fence_half.x + 0.8), 0, sz * (fence_half.y - 4.0))
			var pole := MeshInstance3D.new()
			var pole_mesh := CylinderMesh.new()
			pole_mesh.top_radius = 0.07
			pole_mesh.bottom_radius = 0.12
			pole_mesh.height = 9.0
			pole.mesh = pole_mesh
			pole.material_override = steel
			pole.position = base + Vector3.UP * 4.5
			add_child(pole)
			var head := MeshInstance3D.new()
			var head_mesh := BoxMesh.new()
			head_mesh.size = Vector3(0.9, 0.45, 0.18)
			head.mesh = head_mesh
			head.material_override = lamp_glass
			add_child(head)
			head.look_at_from_position(base + Vector3(-sx * 0.35, 9.1, 0), Vector3(0, 0, sz * 6.0))


func _place_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	for sx in [-1.0, 1.0]:
		for z in [-7.0, 0.0, 7.0]:
			ASSETS.add_model(self, ASSETS.BENCH_MODEL, "Bench", Vector3(sx * (fence_half.x + 1.6), 0, z), 90.0 * sx)
	var trash := ASSETS.add_model(self, ASSETS.TRASH_CAN_MODEL, "TrashCan", Vector3(fence_half.x + 1.5, 0, 3.6))
	if trash != null:
		for child in trash.get_children():
			if String(child.name).contains("rust"):
				child.queue_free()
	ASSETS.add_model(self, ASSETS.PICNIC_TABLE_MODEL, "PicnicTable", Vector3(-(fence_half.x + 6.5), 0, -4.0), 12.0)
	ASSETS.add_model(self, ASSETS.PICNIC_TABLE_MODEL, "PicnicTable", Vector3(fence_half.x + 7.0, 0, 9.0), -20.0)
	for i in range(28):
		var side := rng.randi_range(0, 3)
		var along := rng.randf_range(-1.0, 1.0)
		var offset := rng.randf_range(0.6, 2.4)
		var at: Vector3
		match side:
			0: at = Vector3(along * fence_half.x, 0, -fence_half.y - offset)
			1: at = Vector3(along * fence_half.x, 0, fence_half.y + offset)
			2: at = Vector3(-fence_half.x - offset, 0, along * fence_half.y)
			_: at = Vector3(fence_half.x + offset, 0, along * fence_half.y)
		ASSETS.add_model(self, ASSETS.SHRUB_MODEL, "Shrub", at, rng.randf_range(0, 360), rng.randf_range(1.6, 2.8))
