extends Node3D
## Outdoor basketball hoop with FIBA geometry. Local origin = centre of the ring at
## its top edge (3.05 m). The court lies toward +Z, the backboard toward -Z.

const FIBA = preload("res://scripts/fiba.gd")
const NET_SHADER = preload("res://shaders/net.gdshader")
const RING_SEGMENTS = 32
const NET_STRANDS = 12
const NET_ROWS = 6
const NET_CORD = 0.0035
const POLE_BEHIND_ENDLINE = 0.6

## Callable(material: PhysicsMaterial, factor: float) - lets the court scale every
## surface's restitution from the laboratory "elasticity" slider.
var register_surface: Callable
var _net_material: ShaderMaterial
var _swish := 0.0
var _phase := 10.0
var _particles: CPUParticles3D

var _ring_radius := FIBA.RIM_RADIUS + FIBA.RIM_TUBE
var _board_face_z := -(FIBA.BOARD_TO_RIM + FIBA.RIM_RADIUS)
var _board_center_y := FIBA.BOARD_BOTTOM - FIBA.RIM_HEIGHT + FIBA.BOARD_SIZE.y * 0.5


func _ready() -> void:
	_build_ring()
	_build_board()
	_build_support()
	_build_net()
	_build_particles()


func _material(color: Color, metallic: float = 0.0, roughness: float = 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


func _visual_box(center: Vector3, size: Vector3, material: Material, basis: Basis = Basis()) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.transform = Transform3D(basis, center)
	add_child(instance)
	return instance


func _static_body(body_name: String, restitution_factor: float, group: String = "") -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	var physics := PhysicsMaterial.new()
	physics.friction = 0.6
	body.physics_material_override = physics
	if register_surface.is_valid():
		register_surface.call(physics, restitution_factor)
	if group != "":
		body.add_to_group(group)
	add_child(body)
	return body


func _collision_box(body: StaticBody3D, center: Vector3, size: Vector3, basis: Basis = Basis()) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.transform = Transform3D(basis, center)
	body.add_child(shape)


## Basis whose Z axis points from a to b (for beams).
func _beam_basis(a: Vector3, b: Vector3) -> Basis:
	var forward := (b - a).normalized()
	var side := Vector3.UP.cross(forward)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	side = side.normalized()
	return Basis(side, forward.cross(side), forward)


func _beam(a: Vector3, b: Vector3, thickness: Vector2, material: Material, body: StaticBody3D = null) -> void:
	var basis := _beam_basis(a, b)
	var size := Vector3(thickness.x, thickness.y, a.distance_to(b))
	_visual_box((a + b) * 0.5, size, material, basis)
	if body != null:
		_collision_box(body, (a + b) * 0.5, size, basis)


func _build_ring() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = FIBA.RIM_RADIUS
	torus.outer_radius = FIBA.RIM_RADIUS + 2.0 * FIBA.RIM_TUBE
	torus.rings = 48
	torus.ring_segments = 12
	var ring := MeshInstance3D.new()
	ring.name = "RingMesh"
	ring.mesh = torus
	ring.position.y = -FIBA.RIM_TUBE
	ring.material_override = _material(Color("#d4511e"), 0.55, 0.35)
	add_child(ring)

	# The ring is a polygon of thin capsules - smooth contact without a concave trimesh.
	var body := _static_body("Rim", 0.62, "rim")
	var chord := 2.0 * _ring_radius * sin(PI / RING_SEGMENTS)
	for i in range(RING_SEGMENTS):
		var angle := TAU * (float(i) + 0.5) / RING_SEGMENTS
		var tangent := Vector3(-sin(angle), 0.0, cos(angle))
		var x_axis := tangent.cross(Vector3.UP).normalized()
		var capsule := CapsuleShape3D.new()
		capsule.radius = FIBA.RIM_TUBE
		capsule.height = chord + 2.0 * FIBA.RIM_TUBE
		var shape := CollisionShape3D.new()
		shape.shape = capsule
		var mid := Vector3(cos(angle), 0.0, sin(angle)) * _ring_radius * cos(PI / RING_SEGMENTS)
		shape.transform = Transform3D(Basis(x_axis, tangent, x_axis.cross(tangent)), mid + Vector3(0, -FIBA.RIM_TUBE, 0))
		body.add_child(shape)

	# Bracket between the ring and the board.
	var bracket := _static_body("RimBracket", 0.5, "rim")
	var depth := -_ring_radius - _board_face_z
	var center := Vector3(0.0, -FIBA.RIM_TUBE - 0.012, _board_face_z + depth * 0.5)
	var size := Vector3(0.13, 0.03, depth)
	_visual_box(center, size, _material(Color("#c24a1c"), 0.5, 0.4))
	_collision_box(bracket, center, size)
	_visual_box(Vector3(0.0, -0.05, _board_face_z + 0.006), Vector3(0.26, 0.2, 0.012), _material(Color("#b8461b"), 0.5, 0.4))


func _build_board() -> void:
	var size := Vector3(FIBA.BOARD_SIZE.x, FIBA.BOARD_SIZE.y, FIBA.BOARD_THICKNESS)
	var center := Vector3(0.0, _board_center_y, _board_face_z - FIBA.BOARD_THICKNESS * 0.5)

	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.86, 0.93, 0.97, 0.22)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	glass.roughness = 0.04
	glass.metallic_specular = 0.8
	_visual_box(center, size, glass)

	var body := _static_body("Backboard", 0.72, "backboard")
	_collision_box(body, center, size)

	# White border (5 cm) and the shooter's square: bottom line level with the top of the ring.
	var paint := _material(Color("#f4f4ef"), 0.0, 0.45)
	var z := _board_face_z + 0.002
	var w := FIBA.LINE_WIDTH
	var half := FIBA.BOARD_SIZE * 0.5
	_visual_box(Vector3(0, _board_center_y + half.y - w * 0.5, z), Vector3(FIBA.BOARD_SIZE.x, w, 0.003), paint)
	_visual_box(Vector3(0, _board_center_y - half.y + w * 0.5, z), Vector3(FIBA.BOARD_SIZE.x, w, 0.003), paint)
	for side in [-1.0, 1.0]:
		_visual_box(Vector3(side * (half.x - w * 0.5), _board_center_y, z), Vector3(w, FIBA.BOARD_SIZE.y, 0.003), paint)
	var target := FIBA.TARGET_SIZE
	_visual_box(Vector3(0, -w * 0.5, z), Vector3(target.x, w, 0.003), paint)
	_visual_box(Vector3(0, target.y - w * 1.5, z), Vector3(target.x, w, 0.003), paint)
	for side in [-1.0, 1.0]:
		_visual_box(Vector3(side * (target.x * 0.5 - w * 0.5), target.y * 0.5 - w, z), Vector3(w, target.y, 0.003), paint)

	# Steel frame behind the glass.
	var steel := _material(Color("#2a2f35"), 0.75, 0.45)
	var back := _board_face_z - FIBA.BOARD_THICKNESS - 0.02
	_visual_box(Vector3(0, _board_center_y + half.y - 0.02, back), Vector3(FIBA.BOARD_SIZE.x, 0.04, 0.04), steel)
	_visual_box(Vector3(0, _board_center_y - half.y + 0.02, back), Vector3(FIBA.BOARD_SIZE.x, 0.04, 0.04), steel)
	for x in [-half.x + 0.02, -0.35, 0.35, half.x - 0.02]:
		_visual_box(Vector3(x, _board_center_y, back), Vector3(0.04, FIBA.BOARD_SIZE.y, 0.04), steel)


func _build_support() -> void:
	var steel := _material(Color("#2c3e50"), 0.7, 0.42)
	var pole_z := -(FIBA.RIM_FROM_ENDLINE + POLE_BEHIND_ENDLINE)
	var floor_y := -FIBA.RIM_HEIGHT
	var top_y := 0.95
	var body := _static_body("HoopPole", 0.45)
	_beam(Vector3(0, floor_y, pole_z), Vector3(0, top_y, pole_z), Vector2(0.16, 0.16), steel, body)

	var board_back := _board_face_z - FIBA.BOARD_THICKNESS - 0.04
	for x in [-0.35, 0.35]:
		_beam(Vector3(x, 0.72, pole_z + 0.08), Vector3(x, 0.72, board_back), Vector2(0.06, 0.08), steel, body)
		_beam(Vector3(x, -0.75, pole_z + 0.08), Vector3(x, -0.02, board_back), Vector2(0.05, 0.05), steel)
	_beam(Vector3(-0.4, 0.72, pole_z + 0.08), Vector3(0.4, 0.72, pole_z + 0.08), Vector2(0.06, 0.08), steel)
	_beam(Vector3(-0.4, -0.75, pole_z + 0.08), Vector3(0.4, -0.75, pole_z + 0.08), Vector2(0.05, 0.05), steel)

	var pad := _static_body("PolePadding", 0.25)
	var pad_center := Vector3(0, floor_y + 1.0, pole_z)
	_visual_box(pad_center, Vector3(0.32, 2.0, 0.32), _material(Color("#1d4f91"), 0.0, 0.85))
	_collision_box(pad, pad_center, Vector3(0.32, 2.0, 0.32))
	_visual_box(Vector3(0, floor_y + 0.01, pole_z), Vector3(0.6, 0.02, 0.6), _material(Color("#4a4f55"), 0.6, 0.6))


func _build_net() -> void:
	var levels: Array = []
	for k in range(NET_ROWS + 1):
		var t := float(k) / NET_ROWS
		var radius := lerpf(_ring_radius, 0.145, pow(t, 0.8))
		var y := -FIBA.RIM_TUBE - t * FIBA.NET_LENGTH
		var row: Array = []
		for i in range(NET_STRANDS):
			var angle := TAU * (float(i) + 0.5 * float(k % 2)) / NET_STRANDS
			row.append(Vector3(cos(angle) * radius, y, sin(angle) * radius))
		levels.append(row)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(NET_ROWS):
		var t0 := float(k) / NET_ROWS
		var t1 := float(k + 1) / NET_ROWS
		for i in range(NET_STRANDS):
			var a: Vector3 = levels[k][i]
			var neighbours := [i, posmod(i - 1, NET_STRANDS)] if k % 2 == 0 else [i, (i + 1) % NET_STRANDS]
			for j in neighbours:
				_add_cord(st, a, levels[k + 1][j], t0, t1)
	_net_material = ShaderMaterial.new()
	_net_material.shader = NET_SHADER
	var net := MeshInstance3D.new()
	net.name = "Net"
	net.mesh = st.commit()
	net.material_override = _net_material
	net.extra_cull_margin = 0.3
	add_child(net)


func _add_cord(st: SurfaceTool, a: Vector3, b: Vector3, t0: float, t1: float) -> void:
	var direction := (b - a).normalized()
	var radial := Vector3(a.x, 0.0, a.z).normalized()
	var s1 := direction.cross(radial).normalized() * NET_CORD
	var s2 := direction.cross(s1).normalized() * NET_CORD
	var corners := [s1, s2, -s1, -s2]
	for j in range(4):
		var c0: Vector3 = corners[j]
		var c1: Vector3 = corners[(j + 1) % 4]
		var quad := [[a + c0, c0, t0], [a + c1, c1, t0], [b + c1, c1, t1], [b + c0, c0, t1]]
		for index in [0, 1, 2, 0, 2, 3]:
			st.set_normal((quad[index][1] as Vector3).normalized())
			st.set_uv(Vector2(0.0, quad[index][2]))
			st.add_vertex(quad[index][0])


func _build_particles() -> void:
	_particles = CPUParticles3D.new()
	_particles.name = "ScoreBurst"
	_particles.position = Vector3(0, -0.25, 0)
	_particles.emitting = false
	_particles.one_shot = true
	_particles.amount = 48
	_particles.lifetime = 1.1
	_particles.explosiveness = 0.92
	_particles.direction = Vector3(0, -1, 0)
	_particles.spread = 75.0
	_particles.initial_velocity_min = 1.2
	_particles.initial_velocity_max = 3.2
	_particles.gravity = Vector3(0, -5.0, 0)
	_particles.scale_amount_min = 0.6
	_particles.scale_amount_max = 1.4
	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.035)
	var spark := StandardMaterial3D.new()
	spark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	spark.vertex_color_use_as_albedo = true
	spark.albedo_color = Color(1.0, 0.85, 0.4)
	quad.material = spark
	_particles.mesh = quad
	var colors := Gradient.new()
	colors.set_color(0, Color(1.0, 0.95, 0.7, 1.0))
	colors.set_color(1, Color(1.0, 0.6, 0.2, 0.0))
	_particles.color_ramp = colors
	add_child(_particles)


## Called when a ball passes through the ring from above.
func celebrate(strength: float) -> void:
	_swish = clampf(strength, 0.45, 1.0)
	_phase = 0.0
	_particles.restart()


## Lets the net bulge around a ball that is currently inside it.
func track_ball(global_ball: Vector3) -> void:
	var local := to_local(global_ball)
	if local.y > 0.25 or local.y < -0.8 or Vector2(local.x, local.z).length() > 0.5:
		local = Vector3(0, 10, 0)
	_net_material.set_shader_parameter("ball_local", local)


func _process(delta: float) -> void:
	_phase += delta
	_swish *= exp(-delta * 2.4)
	_net_material.set_shader_parameter("swish", _swish)
	_net_material.set_shader_parameter("phase", _phase)
