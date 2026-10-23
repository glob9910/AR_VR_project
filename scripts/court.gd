extends Node3D
## Physics of court and net
const ASSETS = preload("res://scripts/assets.gd")
const RIM_CENTER = Vector3(0.0, 3.05, -11.0)
const RIM_RADIUS = 0.225
const COURT_WIDTH = 15.0
const COURT_LENGTH = 28.0


func _ready() -> void:
	_make_lighting()
	_make_collisions()
	_load_custom_models()


func _collision_box(body_name: String, center: Vector3, dimensions: Vector3, restitution: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	add_child(body)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = dimensions
	shape.shape = box
	shape.position = center
	body.add_child(shape)

	var material := PhysicsMaterial.new()
	material.bounce = restitution
	material.friction = 0.65
	body.physics_material_override = material
	return body


func _make_lighting() -> void:
	var world := WorldEnvironment.new()
	world.name = "Atmosphere"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#091725")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#a3c6db")
	env.ambient_light_energy = 0.6
	world.environment = env
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-54.0, -28.0, 0.0)
	sun.light_energy = 1.25
	sun.light_color = Color("#ffebcf")
	sun.shadow_enabled = true
	add_child(sun)

	for x in [-6.5, 6.5]:
		for z in [-9.5, 9.5]:
			var lamp := OmniLight3D.new()
			lamp.position = Vector3(x, 7.8, z)
			lamp.omni_range = 19.0
			lamp.light_energy = 1.4
			lamp.light_color = Color("#a1dfff")
			add_child(lamp)


func _make_collisions() -> void:
	_collision_box("Ground", Vector3(0, -0.24, 0), Vector3(50.0, 0.4, 54.0), 0.80)
	var floor := _collision_box("CourtFloor", Vector3(0, -0.075, 0), Vector3(COURT_WIDTH, 0.15, COURT_LENGTH), 0.84)
	floor.add_to_group("court_floor")

	_collision_box("Backboard", Vector3(0, 3.55, -11.55), Vector3(1.8, 1.05, 0.095), 0.54)
	_collision_box("BasketPole", Vector3(0, 1.82, -12.85), Vector3(0.19, 3.65, 0.19), 0.45)
	_collision_box("BasketBrace", Vector3(0, 3.65, -12.19), Vector3(0.16, 0.15, 1.35), 0.35)

	var rim := StaticBody3D.new()
	rim.name = "RimCollision"
	rim.add_to_group("rim")
	add_child(rim)

	var rim_physics := PhysicsMaterial.new()
	rim_physics.bounce = 0.60
	rim_physics.friction = 0.65
	rim.physics_material_override = rim_physics

	for i in range(40):
		var angle := TAU * float(i) / 40.0
		var collision := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.027
		collision.shape = sphere
		collision.position = RIM_CENTER + Vector3(cos(angle) * RIM_RADIUS, 0, sin(angle) * RIM_RADIUS)
		rim.add_child(collision)

	for x in [-7.85, 7.85]:
		_collision_box("FenceCollider", Vector3(x, 1.5, 0), Vector3(0.08, 3.0, 27.5), 0.45)
	for z in [-14.25, 14.25]:
		_collision_box("EndFenceCollider", Vector3(0, 1.5, z), Vector3(15.8, 3.0, 0.09), 0.45)


func _load_custom_models() -> void:
	ASSETS.add_model(self, ASSETS.COURT_MODEL, "CustomCourt", Vector3.ZERO, ASSETS.COURT_SCALE)

	var complete_basket: bool = ASSETS.add_model(self, ASSETS.BASKET_MODEL, "CustomBasket", RIM_CENTER, ASSETS.BASKET_SCALE)
	if not complete_basket:
		ASSETS.add_model(self, ASSETS.RIM_MODEL, "CustomRim", RIM_CENTER, ASSETS.RIM_SCALE)
		ASSETS.add_model(self, ASSETS.BACKBOARD_MODEL, "CustomBackboard", Vector3(0, 3.55, -11.55), ASSETS.BACKBOARD_SCALE)
		ASSETS.add_model(self, ASSETS.NET_MODEL, "CustomNet", RIM_CENTER, ASSETS.NET_SCALE)
		ASSETS.add_model(self, ASSETS.SUPPORT_MODEL, "CustomSupport", Vector3(0, 0, -12.85), ASSETS.SUPPORT_SCALE)

	ASSETS.add_model(self, ASSETS.FENCE_MODEL, "CustomFence", Vector3.ZERO, ASSETS.FENCE_SCALE)
	ASSETS.add_model(self, ASSETS.ENVIRONMENT_MODEL, "CustomEnvironment", Vector3.ZERO, ASSETS.ENVIRONMENT_SCALE)
