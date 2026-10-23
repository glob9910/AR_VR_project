extends RigidBody3D
## FIBA ball: diamater 24 cm, mass 0,6 kg, squared resistance + Magnus.
signal impact(speed: float, surface_name: String)

const ASSETS = preload("res://scripts/assets.gd")
const RADIUS = 0.12
const AIR_DENSITY = 1.225
const MAGNUS_CONSTANT = 0.0025

var drag_coefficient := 0.47
var wind := Vector3.ZERO
var magnus_enabled := true
var in_flight := false
var counted := false
var shot_points := 2
var elapsed := 0.0
var _last_impact_ms := -10000


func _ready() -> void:
	name = "Basketball"
	mass = 0.6
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 8
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.015
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.12
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.bounce = 0.84
	physics_material_override.friction = 0.6

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS
	shape.shape = sphere
	add_child(shape)

	ASSETS.add_model(self, ASSETS.BALL_MODEL, "CustomBasketball", Vector3.ZERO, ASSETS.BALL_SCALE)
	body_entered.connect(_on_body_entered)
	store()


func configure(parameters: Dictionary) -> void:
	mass = float(parameters.get("mass", 0.6))
	physics_material_override.bounce = float(parameters.get("bounce", 0.84))
	drag_coefficient = float(parameters.get("drag", 0.47))
	gravity_scale = float(parameters.get("gravity", 9.81)) / 9.81
	wind = Vector3(float(parameters.get("wind", 0.0)), 0, 0)
	magnus_enabled = bool(parameters.get("magnus", true))


func store() -> void:
	freeze = true
	in_flight = false
	counted = false
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


func launch(velocity: Vector3, spin_radians: float, points: int) -> void:
	shot_points = points
	counted = false
	elapsed = 0.0
	in_flight = true
	collision_layer = 1
	collision_mask = 1
	freeze = false
	sleeping = false
	linear_velocity = velocity
	var horizontal := Vector3(velocity.x, 0, velocity.z).normalized()
	angular_velocity = horizontal.cross(Vector3.UP) * spin_radians


func _physics_process(delta: float) -> void:
	if not in_flight or freeze:
		return
	elapsed += delta
	var relative := linear_velocity - wind
	var speed := relative.length()
	if speed > 0.001:
		var cross_section := PI * RADIUS * RADIUS
		var force := -0.5 * AIR_DENSITY * drag_coefficient * cross_section * speed * relative
		if magnus_enabled:
			force += MAGNUS_CONSTANT * angular_velocity.cross(relative)
		apply_central_force(force)


func _on_body_entered(body: Node) -> void:
	if not in_flight:
		return
	var now := Time.get_ticks_msec()
	if now - _last_impact_ms < 95:
		return
	_last_impact_ms = now
	var speed := linear_velocity.length()
	if speed > 0.65:
		impact.emit(speed, body.name)
