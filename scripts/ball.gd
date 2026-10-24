extends RigidBody3D
## FIBA ball (size 7): diameter 24 cm, mass 0.6 kg.
## Air drag F = -1/2 rho Cd A |v| v, Magnus force F = S (w x v), S = 1/2 rho A r.
## The ball's own bounce is 0: Godot adds both bodies' bounce values, so the
## restitution of every contact is defined only by the surface material.
signal impact(strength: float, surface_name: String)

const FIBA = preload("res://scripts/fiba.gd")
const ASSETS = preload("res://scripts/assets.gd")
const AIR_DENSITY = 1.225
const CROSS_SECTION = PI * FIBA.BALL_RADIUS * FIBA.BALL_RADIUS
const MAGNUS_FACTOR = 0.5 * AIR_DENSITY * CROSS_SECTION * FIBA.BALL_RADIUS
const ANGULAR_DAMP = 0.05
## The net (visual only) catches a ball that entered the ring from above: it damps the
## horizontal motion, pulls the ball toward the hoop axis and slows the fall a little.
const NET_HORIZONTAL_DAMP = 9.0
const NET_CENTERING = 40.0
const NET_VERTICAL_DAMP = 2.0
const LAYER_WORLD = 1
const LAYER_BALLS = 4

var drag_coefficient := 0.47
var wind := Vector3.ZERO
var magnus_enabled := true
var in_flight := false
var elapsed := 0.0
var launch_foot := Vector3.ZERO
var touched_rim := false
var touched_board := false
var first_contact_time := -1.0
var apex := 0.0
## Hoop rim centres - used to slow the ball down while it passes through a net.
var rims: Array = []
var _net_rim = null
var _last_position := Vector3.ZERO
var _last_impact_ms := -10000
var _last_velocity := Vector3.ZERO


static func air_force(velocity: Vector3, spin: Vector3, wind_velocity: Vector3, drag: float, magnus: bool) -> Vector3:
	var relative := velocity - wind_velocity
	var force := -0.5 * AIR_DENSITY * drag * CROSS_SECTION * relative.length() * relative
	if magnus:
		force += MAGNUS_FACTOR * spin.cross(relative)
	return force


static func backspin(velocity: Vector3, spin_radians: float) -> Vector3:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length_squared() < 0.0001:
		return Vector3.ZERO
	return horizontal.normalized().cross(Vector3.UP) * spin_radians


func _ready() -> void:
	mass = FIBA.BALL_MASS
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 6
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = ANGULAR_DAMP
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.bounce = 0.0
	physics_material_override.friction = 0.7

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = FIBA.BALL_RADIUS
	shape.shape = sphere
	add_child(shape)

	var model: Node3D = ASSETS.add_model(self, ASSETS.BALL_MODEL, "BallModel")
	if model != null:
		_add_leather_grain(model)
	body_entered.connect(_on_body_entered)
	store()


func _add_leather_grain(model: Node) -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.16
	var grain := NoiseTexture2D.new()
	grain.width = 512
	grain.height = 512
	grain.seamless = true
	grain.as_normal_map = true
	grain.bump_strength = 6.0
	grain.noise = noise
	for mesh_instance in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mesh_instance.mesh
		var source := mesh.surface_get_material(0) as StandardMaterial3D
		if source == null:
			continue
		var leather := source.duplicate() as StandardMaterial3D
		if source.resource_name.contains("Leather"):
			leather.albedo_color = Color("#c4561d")
		leather.roughness = 0.72
		leather.normal_enabled = true
		leather.normal_texture = grain
		leather.normal_scale = 0.35
		leather.uv1_triplanar = true
		leather.uv1_scale = Vector3(8, 8, 8)
		mesh_instance.set_surface_override_material(0, leather)


func configure(parameters: Dictionary) -> void:
	mass = float(parameters.get("mass", FIBA.BALL_MASS))
	drag_coefficient = float(parameters.get("drag", 0.47))
	gravity_scale = float(parameters.get("gravity", 9.81)) / 9.81
	wind = Vector3(float(parameters.get("wind", 0.0)), 0.0, float(parameters.get("wind_z", 0.0)))
	magnus_enabled = bool(parameters.get("magnus", true))


func store() -> void:
	freeze = true
	in_flight = false
	elapsed = 0.0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	visible = false
	position = Vector3(0, -100, 0)


func hold_at(at: Vector3) -> void:
	store()
	position = at
	visible = true


func launch(velocity: Vector3, spin: Vector3, foot: Vector3) -> void:
	launch_foot = foot
	elapsed = 0.0
	touched_rim = false
	touched_board = false
	first_contact_time = -1.0
	apex = global_position.y
	in_flight = true
	collision_layer = LAYER_BALLS
	collision_mask = LAYER_WORLD | LAYER_BALLS
	freeze = false
	sleeping = false
	linear_velocity = velocity
	angular_velocity = spin
	_last_velocity = velocity
	_last_position = global_position
	_net_rim = null


func _physics_process(delta: float) -> void:
	if not in_flight or freeze:
		return
	elapsed += delta
	var position_now := global_position
	apex = maxf(apex, position_now.y)
	_last_velocity = linear_velocity
	var force := air_force(linear_velocity, angular_velocity, wind, drag_coefficient, magnus_enabled)
	_update_net(position_now)
	if _net_rim != null:
		var local: Vector3 = position_now - _net_rim
		var v := linear_velocity
		force -= mass * NET_HORIZONTAL_DAMP * Vector3(v.x, 0.0, v.z)
		force -= mass * NET_CENTERING * Vector3(local.x, 0.0, local.z)
		force.y -= mass * NET_VERTICAL_DAMP * v.y
	apply_central_force(force)
	_last_position = position_now


func _update_net(position_now: Vector3) -> void:
	if _net_rim != null:
		var depth: float = _net_rim.y - position_now.y
		if depth < -0.02 or depth > FIBA.NET_LENGTH + FIBA.BALL_RADIUS:
			_net_rim = null
		return
	for rim in rims:
		if _last_position.y >= rim.y and position_now.y < rim.y:
			if Vector2(position_now.x - rim.x, position_now.z - rim.z).length() < FIBA.RIM_RADIUS:
				_net_rim = rim


func _on_body_entered(body: Node) -> void:
	if not in_flight:
		return
	if first_contact_time < 0.0:
		first_contact_time = elapsed
	if body.is_in_group("rim"):
		touched_rim = true
	elif body.is_in_group("backboard"):
		touched_board = true
	var strength := (_last_velocity - linear_velocity).length()
	var now := Time.get_ticks_msec()
	if now - _last_impact_ms < 70 or strength < 0.45:
		return
	_last_impact_ms = now
	impact.emit(strength, body.name)
