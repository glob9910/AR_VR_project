extends Node3D
const COURT_SCRIPT = preload("res://scripts/court.gd")
const BALL_SCRIPT = preload("res://scripts/ball.gd")
const PLAYER_SCRIPT = preload("res://scripts/player.gd")
const UI_SCRIPT = preload("res://scripts/ui.gd")
const AUDIO_SCRIPT = preload("res://scripts/audio.gd")

const RIM = Vector3(0.0, 3.05, -11.0)
const HAND_OFFSET = Vector3(0.31, -0.31, -0.76)
const THREE_POINT_DISTANCE = 6.75
const MIN_THROW_SPEED = 3.5
const MAX_THROW_SPEED = 21.0
const CHARGE_SECONDS = 1.8
const GAME_DURATION = 90.0
const POOL_SIZE = 7
const POSITION_NAMES = [
	"ZA 2 PUNKTY",
	"ZA 3 / ŚRODEK",
	"ZA 3 / LEWA",
	"ZA 3 / PRAWA",
	"Z POŁOWY BOISKA"
]
const POSITION_POINTS = [2, 3, 3, 3, 3]
const SHOOT_SPOTS = [
	Vector3(0.0, 0.0, -6.55),
	Vector3(0.0, 0.0, -4.25),
	Vector3(-4.20, 0.0, -5.71),
	Vector3(4.20, 0.0, -5.71),
	Vector3(0.0, 0.0, 2.75)
]

var _ui
var _audio
var _camera: Camera3D
var _player: CharacterBody3D
var _look_yaw := 0.0
var _look_pitch := 0.0
var _free_position := false
var _balls: Array = []
var _held
var _previous: Dictionary = {}
var _preview: MultiMeshInstance3D
var _preview_mesh: MultiMesh

var _mode := "menu"
var _paused := false
var _position_index := 0
var _score := 0
var _shots := 0
var _hits := 0
var _best := 0
var _time_left := GAME_DURATION
var _spawn_delay := -1.0
var _feedback_delay := 0.0
var _charge := 0.0
var _charging := false
var _sensitivity := 1.0
var _volume := 0.75
var _clock := 0.0
var _preview_wait := 0.0

var _physics := {
	"gravity": 9.81,
	"bounce": 0.84,
	"mass": 0.60,
	"spin": 8.0,
	"wind": 0.0,
	"drag": 0.47,
	"magnus": true
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_load_data()
	var court = COURT_SCRIPT.new()
	court.name = "BasketballArena"
	court.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(court)

	_player = PLAYER_SCRIPT.new()
	_player.name = "Player"
	_player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_player)
	_player.movement_started.connect(_on_player_moved)

	_camera = Camera3D.new()
	_camera.name = "PlayerCamera"
	_camera.fov = 65.0
	_camera.near = 0.035
	_camera.far = 160.0
	add_child(_camera)
	_camera.current = true

	_audio = AUDIO_SCRIPT.new()
	_audio.name = "SoundEngine"
	add_child(_audio)
	_apply_volume()

	_ui = UI_SCRIPT.new()
	_ui.name = "Interface"
	add_child(_ui)
	_ui.start_requested.connect(_start_mode)
	_ui.position_requested.connect(_select_position)
	_ui.pause_requested.connect(_toggle_pause)
	_ui.resume_requested.connect(_resume_game)
	_ui.restart_requested.connect(_restart)
	_ui.menu_requested.connect(_return_menu)
	_ui.settings_changed.connect(_on_setting_changed)
	_ui.lab_changed.connect(_on_lab_changed)

	for i in range(POOL_SIZE):
		var ball = BALL_SCRIPT.new()
		ball.name = "Ball_%d" % i
		ball.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(ball)
		ball.impact.connect(_on_ball_impact)
		_balls.append(ball)

	_make_preview()
	_return_menu()


func _make_preview() -> void:
	_preview = MultiMeshInstance3D.new()
	_preview.name = "PredictedTrajectory"
	var dot_mesh := SphereMesh.new()
	dot_mesh.radius = 0.037
	dot_mesh.height = 0.074
	dot_mesh.radial_segments = 8
	dot_mesh.rings = 4
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#6afde2")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = Color("#4afad2")
	material.emission_energy_multiplier = 1.8
	dot_mesh.material = material
	_preview_mesh = MultiMesh.new()
	_preview_mesh.transform_format = MultiMesh.TRANSFORM_3D
	_preview_mesh.mesh = dot_mesh
	_preview_mesh.instance_count = 65
	_preview_mesh.custom_aabb = AABB(Vector3(-20.0, -5.0, -20.0), Vector3(40.0, 25.0, 50.0))
	_preview.multimesh = _preview_mesh
	add_child(_preview)
	_preview.visible = false


func _load_data() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://hoop_lab.cfg") == OK:
		_best = int(cfg.get_value("record", "score", 0))
		_sensitivity = float(cfg.get_value("settings", "sensitivity", 1.0))
		_volume = float(cfg.get_value("settings", "volume", 0.75))


func _save_data() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("record", "score", _best)
	cfg.set_value("settings", "sensitivity", _sensitivity)
	cfg.set_value("settings", "volume", _volume)
	cfg.save("user://hoop_lab.cfg")


func _apply_volume() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(_volume, 0.001)))


func _on_setting_changed(key: String, value: float) -> void:
	match key:
		"volume":
			_volume = value
			_apply_volume()
		"sensitivity":
			_sensitivity = value
	_save_data()


func _return_menu() -> void:
	get_tree().paused = false
	_paused = false
	_mode = "menu"
	_free_position = false
	_set_game_cursor(false)
	_charging = false
	_held = null
	_spawn_delay = -1.0
	_preview.visible = false
	for ball in _balls:
		ball.store()
	_previous.clear()
	_ui.show_menu(_best, _sensitivity, _volume)
	_camera.position = Vector3(9.0, 6.5, 6.0)
	_camera.look_at(Vector3(0, 1.8, -7.0), Vector3.UP)


func _start_mode(selected: String) -> void:
	get_tree().paused = false
	_paused = false
	_mode = selected
	_free_position = false
	_set_game_cursor(true)
	# Earth conditions:
	if selected == "game":
		_physics = {
			"gravity": 9.81, "bounce": 0.84, "mass": 0.60,
			"spin": 8.0, "wind": 0.0, "drag": 0.47, "magnus": true
		}
	_score = 0
	_hits = 0
	_shots = 0
	_time_left = GAME_DURATION
	_position_index = 0
	_charging = false
	_spawn_delay = -1.0
	_feedback_delay = 0.0
	for ball in _balls:
		ball.store()
	_previous.clear()
	_ui.show_game(selected == "lab", _physics)
	_select_position(0)
	_update_ui()


func _select_position(index: int) -> void:
	if _mode != "game" and _mode != "lab":
		return
	_position_index = clampi(index, 0, SHOOT_SPOTS.size() - 1)
	_charging = false
	_free_position = false
	_set_game_cursor(true)
	_spawn_delay = -1.0
	_set_camera_for_shot()
	_prepare_ball()
	_ui.show_feedback("")


func _set_game_cursor(captured: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE
	_player.controls_enabled = captured and _mode in ["game", "lab"] and not _paused


func _set_camera_for_shot() -> void:
	_player.teleport_to(SHOOT_SPOTS[_position_index])
	var toward: Vector3 = RIM - _player.eyes_position()
	_look_yaw = -atan2(toward.x, -toward.z)
	_look_pitch = atan2(toward.y, Vector2(toward.x, toward.z).length())
	_sync_player_camera()


func _sync_player_camera() -> void:
	_camera.global_position = _player.eyes_position()
	_camera.rotation = Vector3(_look_pitch, _look_yaw, 0.0)
	_player.heading = _look_yaw
	if is_instance_valid(_held):
		_held.global_position = _hand_position()


func _hand_position() -> Vector3:
	return _camera.to_global(HAND_OFFSET)


func _on_player_moved() -> void:
	if _mode in ["game", "lab"]:
		_free_position = true


func _points_from_current_position() -> int:
	var foot: Vector3 = _player.global_position
	var distance := Vector2(foot.x - RIM.x, foot.z - RIM.z).length()
	return 3 if distance >= THREE_POINT_DISTANCE or (absf(foot.x) >= 6.6 and foot.z < -9.5) else 2


func _prepare_ball() -> void:
	if _mode != "game" and _mode != "lab":
		return
	if is_instance_valid(_held):
		_held.store()
	var candidate = null
	for ball in _balls:
		if not ball.in_flight:
			candidate = ball
			break
	if candidate == null:
		candidate = _balls[0]
		for ball in _balls:
			if ball.elapsed > candidate.elapsed:
				candidate = ball
		candidate.store()
	_previous.erase(candidate.get_instance_id())
	_held = candidate
	_held.configure(_physics)
	_held.hold_at(_hand_position())
	_charge = 0.0
	_charging = false
	_preview.visible = false


func _start_charge() -> void:
	if _mode not in ["game", "lab"] or _paused or not is_instance_valid(_held):
		return
	_charge = 0.0
	_charging = true
	_preview.visible = true
	_show_preview()


func _release_shot() -> void:
	if not _charging or not is_instance_valid(_held):
		return
	_charging = false
	var velocity := _aim_velocity(_charge)
	_held.configure(_physics)
	_held.launch(velocity, float(_physics["spin"]), _points_from_current_position())
	_previous[_held.get_instance_id()] = _held.global_position
	_shots += 1
	_held = null
	_spawn_delay = 1.40
	_preview.visible = false
	_ui.show_feedback("RZUT ODDANY", false)
	_feedback_delay = 0.7


func _shot_direction() -> Vector3:
	var forward := -_camera.global_transform.basis.z
	var focus_distance := maxf(3.0, _camera.global_position.distance_to(RIM))
	var target := _camera.global_position + forward * focus_distance
	return (target - _hand_position()).normalized()


func _aim_velocity(power: float) -> Vector3:
	var speed := lerpf(MIN_THROW_SPEED, MAX_THROW_SPEED, clampf(power, 0.0, 1.0))
	return _shot_direction() * speed


func _show_preview() -> void:
	if not is_instance_valid(_held):
		return
	var pos: Vector3 = _held.global_position
	var velocity := _aim_velocity(_charge)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).normalized()
	var rotation := horizontal.cross(Vector3.UP) * float(_physics["spin"])
	var wind := Vector3(float(_physics["wind"]), 0, 0)
	var drag := float(_physics["drag"])
	var mass := float(_physics["mass"])
	var gravity := float(_physics["gravity"])
	var preview_active := true
	const DT = 0.045
	for i in range(_preview_mesh.instance_count):
		if preview_active:
			var relative := velocity - wind
			var force := -0.5 * 1.225 * drag * (PI * 0.12 * 0.12) * relative.length() * relative
			if bool(_physics["magnus"]):
				force += 0.0025 * rotation.cross(relative)
			var acceleration := Vector3.DOWN * gravity + force / mass
			velocity += acceleration * DT
			pos += velocity * DT
			if pos.y < 0.10:
				preview_active = false
		var at := pos if preview_active else Vector3(0, -150.0, 0)
		_preview_mesh.set_instance_transform(i, Transform3D(Basis(), at))


func _physics_process(delta: float) -> void:
	if _mode not in ["game", "lab"] or _paused:
		return
	_sync_player_camera()
	if _mode == "game":
		_time_left = maxf(0.0, _time_left - delta)
		if _time_left <= 0.0:
			_finish_round()
			return

	# Detection if ball goes down direction through net
	for ball in _balls:
		if not ball.in_flight:
			continue
		var id: int = ball.get_instance_id()
		var current: Vector3 = ball.global_position
		var previous: Vector3 = _previous.get(id, current)
		if not ball.counted and previous.y >= RIM.y and current.y < RIM.y and ball.linear_velocity.y < 0.0:
			var difference := previous.y - current.y
			var t := (previous.y - RIM.y) / difference if difference > 0.0001 else 0.0
			var crossing := previous.lerp(current, t)
			var horizontal := Vector2(crossing.x - RIM.x, crossing.z - RIM.z).length()
			if horizontal <= 0.125:
				ball.counted = true
				_score += ball.shot_points
				_hits += 1
				_audio.play_score()
				_ui.show_feedback("TRAFIONY!  +%d PKT" % ball.shot_points)
				_feedback_delay = 1.6
		_previous[id] = current
		if ball.elapsed > 10.0 or current.y < -2.0:
			ball.store()
			_previous.erase(id)


func _process(delta: float) -> void:
	_clock += delta
	if _mode == "menu":
		_camera.position = Vector3(9.0 + sin(_clock * 0.12) * 1.7, 6.5, 6.0)
		_camera.look_at(Vector3(0, 1.8, -7.0), Vector3.UP)
		return
	if _mode not in ["game", "lab"] or _paused:
		return
	if _charging:
		_charge = minf(1.0, _charge + delta / CHARGE_SECONDS)
		_preview_wait -= delta
		if _preview_wait <= 0.0:
			_preview_wait = 0.045
			_show_preview()
	if _spawn_delay >= 0.0:
		_spawn_delay -= delta
		if _spawn_delay < 0.0 and not is_instance_valid(_held):
			_prepare_ball()
	if _feedback_delay > 0.0:
		_feedback_delay -= delta
		if _feedback_delay <= 0.0:
			_ui.show_feedback("")
	_update_ui()


func _update_ui() -> void:
	if _mode not in ["game", "lab"]:
		return
	var place: String = "SWOBODNA / ZA %d PKT" % _points_from_current_position() if _free_position else POSITION_NAMES[_position_index]
	_ui.update_hud(_score, _shots, _hits, _time_left, _best, place)
	_ui.update_aim(_charge, -rad_to_deg(_look_pitch), _aim_velocity(_charge).length(), _charging)


func _input(event: InputEvent) -> void:
	if _mode not in ["game", "lab"] or _paused:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		if _charging:
			_cancel_charge()
		_set_game_cursor(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look_yaw -= event.relative.x * _sensitivity * 0.0027
		_look_pitch = clampf(
			_look_pitch - event.relative.y * _sensitivity * 0.0027,
			deg_to_rad(-79.0),
			deg_to_rad(79.0)
		)
		_sync_player_camera()
		if _charging:
			_preview_wait = 0.0

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed and _charging:
			_release_shot()


func _cancel_charge() -> void:
	_charging = false
	_charge = 0.0
	_preview.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				if _mode in ["game", "lab"]:
					_toggle_pause()
			KEY_R:
				if _mode in ["game", "lab"] and not _paused:
					_restart()
			KEY_M:
				if _mode != "menu":
					_return_menu()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				if _mode in ["game", "lab"] and not _paused:
					_select_position(event.keycode - KEY_1)
	if _paused or _mode not in ["game", "lab"]:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_start_charge()
		else:
			_set_game_cursor(true)


func _on_ball_impact(speed: float, surface: String) -> void:
	if _mode in ["game", "lab"] and not _paused:
		_audio.play_impact(speed, surface)


func _on_lab_changed(key: String, value: float) -> void:
	if _mode != "lab":
		return
	if key == "reset":
		_physics = {
			"gravity": 9.81, "bounce": 0.84, "mass": 0.6,
			"spin": 8.0, "wind": 0.0, "drag": 0.47, "magnus": true
		}
		_ui.show_game(true, _physics)
	else:
		_physics[key] = value
	for ball in _balls:
		ball.configure(_physics)
	if _charging:
		_show_preview()
	_update_ui()


func _toggle_pause() -> void:
	if _mode not in ["game", "lab"]:
		return
	if _paused:
		_resume_game()
	else:
		_paused = true
		_cancel_charge()
		_set_game_cursor(false)
		get_tree().paused = true
		_ui.show_pause()


func _resume_game() -> void:
	get_tree().paused = false
	_paused = false
	_set_game_cursor(true)
	_ui.hide_pause()


func _restart() -> void:
	var previous_mode := _mode
	if previous_mode == "results":
		previous_mode = "game"
	if previous_mode not in ["game", "lab"]:
		previous_mode = "game"
	_start_mode(previous_mode)


func _finish_round() -> void:
	if _mode != "game":
		return
	_mode = "results"
	_set_game_cursor(false)
	_charging = false
	_preview.visible = false
	_held = null
	var is_record := _score > _best
	if is_record:
		_best = _score
		_save_data()
	for ball in _balls:
		ball.store()
	_audio.play_end()
	_ui.show_results(_score, _shots, _hits, _best, is_record)
