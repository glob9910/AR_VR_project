extends SceneTree
## Windowed: godot --path . --script res://tests/screenshots.gd
## Saves screenshots of the main views into tests/screenshots/.

var main: Node
var out_dir := ProjectSettings.globalize_path("res://tests/screenshots")


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run()


func _wait(n: int) -> void:
	for i in range(n):
		await process_frame


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out_dir.path_join(file_name))
	print("SHOT ", file_name)


func _run() -> void:
	main._settings["sensitivity"] = 0.0
	await _wait(90)
	await _shot("01_menu.png")

	main._start_mode("game")
	await _wait(30)
	await _shot("02_game_free_throw.png")

	main._start_charge()
	await _wait(70)
	await _shot("03_game_charging.png")
	main._cancel_charge()

	main._start_mode("lab")
	main._select_position(2)
	await _wait(20)
	main._start_charge()
	await _wait(75)
	await _shot("04_lab_preview.png")
	main._release_shot()
	main._set_cursor_free(true)
	await _wait(40)
	await _shot("05_lab_cursor.png")

	main._set_cursor_free(false)
	main._player.teleport_to(Vector3(1.2, 0, -10.6))
	main._look_yaw = deg_to_rad(15)
	main._look_pitch = deg_to_rad(14)
	await _wait(20)
	await _shot("06_hoop_closeup.png")

	main._player.teleport_to(Vector3(6.0, 0, 8.0))
	main._look_yaw = deg_to_rad(20)
	main._look_pitch = deg_to_rad(-4)
	await _wait(20)
	await _shot("07_court_overview.png")

	main._player.teleport_to(Vector3(-3.0, 0, -3.0))
	main._look_yaw = deg_to_rad(110)
	main._look_pitch = deg_to_rad(2)
	await _wait(20)
	await _shot("08_side_props.png")

	main._toggle_pause()
	await _wait(10)
	await _shot("09_pause.png")
	main._resume_game()

	# A made shot seen from the side: ideal speed from the free-throw line.
	main._select_position(0)
	await _wait(5)
	var release: Vector3 = main._release_position()
	var rim: Vector3 = FIBA_RIM
	var flat := Vector3(rim.x - release.x, 0, rim.z - release.z).normalized()
	var angle: float = main._launch_angle()
	var speed: float = TRAJECTORY.ideal_speed(release, flat, angle, rim, 12.0, main._physics)
	main._start_charge()
	main._charge = (speed / main._reference_speed - main.POWER_RANGE.x) / (main.POWER_RANGE.y - main.POWER_RANGE.x)
	main._release_shot()
	main._camera.current = false
	var side := Camera3D.new()
	side.fov = 50
	root.add_child(side)
	side.look_at_from_position(Vector3(3.2, 3.0, -10.6), Vector3(0, 2.9, -12.2))
	side.current = true
	for i in range(140):
		await process_frame
		if main._hits > 0:
			break
	await _wait(4)
	await _shot("10_score_net.png")
	quit()


const FIBA_RIM = Vector3(0.0, 3.05, -12.425)
const TRAJECTORY = preload("res://scripts/trajectory.gd")
