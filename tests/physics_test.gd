extends SceneTree
## Headless: godot --headless --path . --script res://tests/physics_test.gd
## 1. FIBA drop test on the real court surface.
## 2. Preview (trajectory.gd) vs the real rigid body.
## 3. Shots from every spot at the ideal speed, and how much speed error still scores.

const FIBA = preload("res://scripts/fiba.gd")
const TRAJECTORY = preload("res://scripts/trajectory.gd")
const BALL_SCRIPT = preload("res://scripts/ball.gd")

var main: Node


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run()


func _frames(n: int) -> void:
	for i in range(n):
		await physics_frame


func _run() -> void:
	await _frames(5)
	main._start_mode("lab")
	await _frames(5)
	await _drop_test()
	await _preview_test()
	for spot in range(main.SHOOT_SPOTS.size()):
		await _spot_test(spot)
	await _bank_test()
	quit()


func _fresh_ball():
	var ball = main._balls[0]
	for b in main._balls:
		b.store()
	main._held = null
	main._spawn_delay = -1.0
	main._forget(ball)
	ball.configure(main._physics)
	return ball


func _drop_test() -> void:
	var ball = _fresh_ball()
	ball.hold_at(Vector3(3.0, 1.8 + FIBA.BALL_RADIUS, 2.0))
	ball.launch(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	var prev_vy := 0.0
	var bounced := false
	var top := 0.0
	for i in range(300):
		await physics_frame
		var vy: float = ball.linear_velocity.y
		if not bounced and prev_vy < -1.0 and vy > -0.2:
			bounced = true
		if bounced:
			top = maxf(top, ball.global_position.y - FIBA.BALL_RADIUS)
			if vy < 0.0 and top > 0.1:
				break
		prev_vy = vy
	print("DROP 1.8 m: rebound bottom %.3f m, top of ball %.3f m (FIBA 1.2-1.4), e=%.3f" % [top, top + 2 * FIBA.BALL_RADIUS, sqrt(top / 1.8)])


func _preview_test() -> void:
	var ball = _fresh_ball()
	var start := Vector3(0, 2.0, 0)
	var velocity := Vector3(0.3, 6.5, -6.0)
	var spin := BALL_SCRIPT.backspin(velocity, 12.0)
	var predicted := TRAJECTORY.simulate(start, velocity, spin, main._physics, 1.0, 1)
	ball.hold_at(start)
	ball.launch(velocity, spin, Vector3.ZERO)
	var worst := 0.0
	for i in range(1, 100):
		await physics_frame
		worst = maxf(worst, ball.global_position.distance_to(predicted[i]))
	print("PREVIEW max deviation over 0.83 s of flight: %.4f m" % worst)


func _shoot(spot: int, speed_factor: float, aim_offset: Vector3 = Vector3.ZERO) -> String:
	main._select_position(spot)
	await _frames(3)
	var ball = _fresh_ball()
	var hand: Vector3 = main._release_position()
	var rim: Vector3 = FIBA.rim_center(-1.0) + aim_offset
	var flat := Vector3(rim.x - hand.x, 0, rim.z - hand.z).normalized()
	var angle: float = main._launch_angle()
	var ideal := TRAJECTORY.ideal_speed(hand, flat, angle, rim, 12.0, main._physics)
	var speed := ideal * speed_factor
	var velocity := flat * cos(angle) * speed + Vector3.UP * sin(angle) * speed
	ball.hold_at(hand)
	ball.launch(velocity, BALL_SCRIPT.backspin(velocity, 12.0), main._player.global_position)
	main._previous[ball.get_instance_id()] = hand
	var hits_before: int = main._hits
	var score_before: int = main._score
	for i in range(330):
		await physics_frame
		if main._hits > hits_before:
			return "IN(+%d)" % (main._score - score_before)
		if not ball.in_flight:
			break
	return "miss"


func _spot_test(spot: int) -> void:
	var results := []
	var made := 0
	for factor in [0.96, 0.97, 0.98, 0.99, 1.0, 1.01, 1.02, 1.03, 1.04]:
		var r: String = await _shoot(spot, factor)
		results.append("%.3f:%s" % [factor, r])
		if r.begins_with("IN"):
			made += 1
	print("SPOT %d (%s) angle %.0f deg: %d/9  %s" % [spot + 1, main.POSITION_NAMES[spot], rad_to_deg(main._launch_angle()), made, " ".join(results)])


func _bank_test() -> void:
	# Aim at the upper part of the shooter's square from both wings.
	var board_z: float = FIBA.rim_center(-1.0).z - FIBA.BOARD_TO_RIM - FIBA.RIM_RADIUS
	var made := 0
	var log := []
	for spot in [2, 3]:
		var side := -1.0 if spot == 2 else 1.0
		for height in [0.30, 0.36, 0.42]:
			var target := Vector3(side * 0.2, height, board_z - FIBA.rim_center(-1.0).z + FIBA.BALL_RADIUS)
			var r: String = await _shoot(spot, 1.0, target)
			log.append("spot%d h%.2f:%s" % [spot + 1, height, r])
			if r.begins_with("IN"):
				made += 1
	print("BANK SHOTS off the square: %d/6  %s" % [made, " ".join(log)])
