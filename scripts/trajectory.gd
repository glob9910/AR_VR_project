extends RefCounted
## Ball flight prediction with the same integration scheme as Godot Physics
## (semi-implicit Euler at the physics tick rate). Bounces are found with sphere
## casts against the real colliders, so the preview matches the actual shot.

const BALL = preload("res://scripts/ball.gd")
const FIBA = preload("res://scripts/fiba.gd")


static func physics_dt() -> float:
	return 1.0 / float(Engine.physics_ticks_per_second)


## Returns points sampled every `sample_every` physics steps. With `space` and
## `max_bounces` > 0 the prediction reflects off the world colliders.
## `stop_distance` > 0 ends the prediction after that horizontal distance.
static func simulate(start: Vector3, velocity: Vector3, spin: Vector3, p: Dictionary, max_time: float,
		sample_every: int = 4, space: PhysicsDirectSpaceState3D = null, max_bounces: int = 0,
		stop_distance: float = -1.0) -> PackedVector3Array:
	var dt := physics_dt()
	var gravity := Vector3.DOWN * float(p["gravity"])
	var wind := Vector3(float(p["wind"]), 0.0, float(p["wind_z"]))
	var drag := float(p["drag"])
	var mass := float(p["mass"])
	var magnus := bool(p["magnus"])
	var spin_decay := 1.0 - dt * BALL.ANGULAR_DAMP
	var pos := start
	var vel := velocity
	var w := spin
	var points := PackedVector3Array([start])
	var query: PhysicsShapeQueryParameters3D = null
	if space != null and max_bounces > 0:
		query = PhysicsShapeQueryParameters3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = FIBA.BALL_RADIUS
		query.shape = sphere
		query.collision_mask = BALL.LAYER_WORLD
	var bounces := 0
	var steps := int(max_time / dt)
	for i in range(1, steps + 1):
		vel += (gravity + BALL.air_force(vel, w, wind, drag, magnus) / mass) * dt
		w *= spin_decay
		var motion := vel * dt
		var moved := false
		if query != null:
			query.transform = Transform3D(Basis(), pos)
			query.motion = motion
			var fractions := space.cast_motion(query)
			if fractions[0] < 1.0:
				query.transform = Transform3D(Basis(), pos + motion * fractions[1])
				query.motion = Vector3.ZERO
				var info := space.get_rest_info(query)
				pos += motion * fractions[0]
				moved = true
				if not info.is_empty():
					var normal: Vector3 = info["normal"]
					var normal_speed := vel.dot(normal)
					if normal_speed < 0.0:
						var restitution := 0.0
						var collider := instance_from_id(info["collider_id"]) as PhysicsBody3D
						if collider is StaticBody3D and (collider as StaticBody3D).physics_material_override != null:
							restitution = (collider as StaticBody3D).physics_material_override.bounce
						var tangent := (vel - normal * normal_speed) * 0.85
						vel = tangent - normal * normal_speed * restitution
						bounces += 1
						if bounces > max_bounces:
							points.append(pos)
							break
		if not moved:
			pos += motion
		if i % sample_every == 0:
			points.append(pos)
		if pos.y < -0.5:
			break
		if stop_distance > 0.0 and Vector2(pos.x - start.x, pos.z - start.z).length() >= stop_distance:
			points.append(pos)
			break
	return points


## Lowest launch speed for which the ball (at the given launch angle) reaches the
## height of `target` at its horizontal distance - i.e. the speed that drops the
## ball onto the ring. Bisection over the same integrator as the preview.
static func ideal_speed(start: Vector3, horizontal_dir: Vector3, angle: float, target: Vector3, spin_radians: float, p: Dictionary) -> float:
	var distance := Vector2(target.x - start.x, target.z - start.z).length()
	var low := 1.0
	var high := 35.0
	for _i in range(18):
		var mid := (low + high) * 0.5
		if _reaches(start, horizontal_dir, angle, mid, distance, target.y, spin_radians, p):
			high = mid
		else:
			low = mid
	return high


static func _reaches(start: Vector3, dir: Vector3, angle: float, speed: float, distance: float, height: float, spin_radians: float, p: Dictionary) -> bool:
	var dt := physics_dt()
	var gravity := Vector3.DOWN * float(p["gravity"])
	var wind := Vector3(float(p["wind"]), 0.0, float(p["wind_z"]))
	var drag := float(p["drag"])
	var mass := float(p["mass"])
	var magnus := bool(p["magnus"])
	var vel := dir * cos(angle) * speed + Vector3.UP * sin(angle) * speed
	var w := BALL.backspin(vel, spin_radians)
	var spin_decay := 1.0 - dt * BALL.ANGULAR_DAMP
	var pos := start
	var previous := pos
	for _i in range(int(6.0 / dt)):
		vel += (gravity + BALL.air_force(vel, w, wind, drag, magnus) / mass) * dt
		w *= spin_decay
		previous = pos
		pos += vel * dt
		var progress := (pos - start).dot(dir)
		if progress >= distance:
			var before := (previous - start).dot(dir)
			var t := (distance - before) / maxf(progress - before, 0.0001)
			return lerpf(previous.y, pos.y, t) >= height
		if pos.y < 0.0:
			return false
	return false
