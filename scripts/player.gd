extends CharacterBody3D
signal movement_started

const WALK_SPEED = 4.6
const RUN_SPEED = 7.4
const JUMP_SPEED = 4.2
const ACCELERATION = 17.0
const FRICTION = 22.0
const GRAVITY = 9.81
const EYE_HEIGHT = 1.66

var controls_enabled := false
var heading := 0.0


func _ready() -> void:
	name = "Player"
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.22
	var collider := CollisionShape3D.new()
	collider.name = "PlayerCollider"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.80
	collider.shape = capsule
	collider.position = Vector3(0.0, 0.9, 0.0)
	add_child(collider)


func teleport_to(foot_position: Vector3) -> void:
	global_position = foot_position + Vector3.UP * 0.04
	velocity = Vector3.ZERO


func eyes_position() -> Vector3:
	return global_position + Vector3.UP * EYE_HEIGHT


func _physics_process(delta: float) -> void:
	if not controls_enabled:
		velocity = Vector3.ZERO
		return

	var input := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		input.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		input.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		input.y += 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		input.y -= 1.0
	input = input.normalized()

	var forward := Vector3(-sin(heading), 0.0, -cos(heading))
	var right := Vector3(cos(heading), 0.0, -sin(heading))
	var direction := (right * input.x + forward * input.y)
	var speed := RUN_SPEED if Input.is_physical_key_pressed(KEY_SHIFT) else WALK_SPEED
	var target := direction * speed
	var rate := ACCELERATION if input.length_squared() > 0.0 else FRICTION
	velocity.x = move_toward(velocity.x, target.x, rate * delta)
	velocity.z = move_toward(velocity.z, target.z, rate * delta)

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif Input.is_physical_key_pressed(KEY_SPACE):
		velocity.y = JUMP_SPEED
	else:
		velocity.y = -0.1

	move_and_slide()
	if input.length_squared() > 0.0 or (velocity.y > 0.5):
		movement_started.emit()
