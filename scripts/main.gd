extends Node3D
const FIBA = preload("res://scripts/fiba.gd")
const COURT_SCRIPT = preload("res://scripts/court.gd")
const BALL_SCRIPT = preload("res://scripts/ball.gd")
const PLAYER_SCRIPT = preload("res://scripts/player.gd")
const UI_SCRIPT = preload("res://scripts/ui.gd")
const AUDIO_SCRIPT = preload("res://scripts/audio.gd")
const TRAJECTORY = preload("res://scripts/trajectory.gd")

const HAND_OFFSET = Vector3(0.24, -0.34, -0.62)
## Set point above the head (relative to the eyes, rotated only by yaw). A high
## release gives a steep entry - below ~32 degrees the ball cannot fit through the ring.
const RELEASE_OFFSET = Vector3(0.16, 0.32, -0.12)
const SET_POINT_SECONDS = 0.25
## Launch angle = camera pitch + ARC_LIFT, so looking at the ring gives a natural
## 42-54 degree shooting arc.
const ARC_LIFT = 0.63
const REFERENCE_ANGLE = 0.9
## Speed range of the power bar relative to the speed needed at the current distance.
const POWER_RANGE = Vector2(0.8, 1.2)
const CHARGE_SECONDS = 2.5
const GAME_PREVIEW_FRACTION = 0.42
const GAME_DURATION = 90.0
const POOL_SIZE = 7
const SCORE_CHECK_DEPTH = 0.25
const POSITION_NAMES = [
	"Linia rzutów wolnych  •  2 pkt",
	"Za 3 – środek  •  3 pkt",
	"Za 3 – lewe skrzydło  •  3 pkt",
	"Za 3 – prawe skrzydło  •  3 pkt",
	"Z połowy boiska  •  3 pkt"
]
## Spots relative to the main hoop (negative Z).
const SHOOT_SPOTS = [
	Vector3(0.0, 0.0, -8.0),
	Vector3(0.0, 0.0, -5.2),
	Vector3(-5.1, 0.0, -7.3),
	Vector3(5.1, 0.0, -7.3),
	Vector3(0.0, 0.0, -0.4)
]
const DEFAULT_PHYSICS = {
	"gravity": 9.81, "bounce": 0.79, "mass": 0.60, "spin": 12.0,
	"wind": 0.0, "wind_z": 0.0, "drag": 0.47, "magnus": true
}

var _ui
var _audio
var _court
var _camera: Camera3D
var _player: CharacterBody3D
var _look_yaw := 0.0
var _look_pitch := 0.0
var _free_position := false
var _cursor_free := false
var _balls: Array = []
var _held
var _previous: Dictionary = {}
var _entered: Dictionary = {}
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
var _charge_time := 0.0
var _charging := false
var _settings := {"sensitivity": 1.0, "volume": 0.75, "quality": 1.0}
var _clock := 0.0
var _preview_wait := 0.0
var _lab_wait := 0.0
var _reference_speed := 8.0
var _reference_key := Vector4(INF, 0, 0, 0)
var _last_shot: Dictionary = {}
var _tracked_ball
var _physics: Dictionary = DEFAULT_PHYSICS.duplicate()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_load_data()
	_court = COURT_SCRIPT.new()
	_court.name = "Park"
	_court.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_court)

	_player = PLAYER_SCRIPT.new()
	_player.name = "Player"
	_player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_player)
	_player.movement_started.connect(_on_player_moved)

	_camera = Camera3D.new()
	_camera.name = "PlayerCamera"
	_camera.fov = 70.0
	_camera.near = 0.03
	_camera.far = 500.0
	add_child(_camera)
	_camera.current = true

	_audio = AUDIO_SCRIPT.new()
	_audio.name = "SoundEngine"
	add_child(_audio)

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

	var rims: Array = _court.rim_centers()
	for i in range(POOL_SIZE):
		var ball = BALL_SCRIPT.new()
		ball.name = "Ball_%d" % i
		ball.process_mode = Node.PROCESS_MODE_PAUSABLE
		ball.rims = rims
		add_child(ball)
		ball.impact.connect(_on_ball_impact.bind(ball))
		_balls.append(ball)

	_make_preview()
	_apply_settings()
	_return_menu()


func _make_preview() -> void:
	_preview = MultiMeshInstance3D.new()
	_preview.name = "PredictedTrajectory"
	var dot := SphereMesh.new()
	dot.radius = 0.03
	dot.height = 0.06
	dot.radial_segments = 8
	dot.rings = 4
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = false
	dot.material = material
	_preview_mesh = MultiMesh.new()
	_preview_mesh.transform_format = MultiMesh.TRANSFORM_3D
	_preview_mesh.use_colors = true
	_preview_mesh.mesh = dot
	_preview_mesh.instance_count = 140
	_preview_mesh.custom_aabb = AABB(Vector3(-40, -5, -40), Vector3(80, 40, 80))
	_preview.multimesh = _preview_mesh
	_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_preview)
	_preview.visible = false


# --- settings ----------------------------------------------------------------

func _load_data() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://hoop_lab.cfg") == OK:
		_best = int(cfg.get_value("record", "score", 0))
		for key in _settings.keys():
			_settings[key] = float(cfg.get_value("settings", key, _settings[key]))


func _save_data() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("record", "score", _best)
	for key in _settings.keys():
		cfg.set_value("settings", key, _settings[key])
	cfg.save("user://hoop_lab.cfg")


func _apply_settings() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(_settings["volume"]), 0.001)))
	_court.set_quality(float(_settings["quality"]) > 0.5)


func _on_setting_changed(key: String, value: float) -> void:
	_settings[key] = value
	_apply_settings()
	_save_data()


# --- modes -------------------------------------------------------------------

func _return_menu() -> void:
	get_tree().paused = false
	_paused = false
	_mode = "menu"
	_free_position = false
	_charging = false
	_held = null
	_spawn_delay = -1.0
	_preview.visible = false
	_set_cursor_free(true)
	for ball in _balls:
		ball.store()
	_previous.clear()
	_entered.clear()
	_physics = DEFAULT_PHYSICS.duplicate()
	_court.set_elasticity(float(_physics["bounce"]))
	_ui.show_menu(_best, _settings)
	_update_menu_camera()


func _start_mode(selected: String) -> void:
	get_tree().paused = false
	_paused = false
	_mode = selected
	_free_position = false
	_physics = DEFAULT_PHYSICS.duplicate()
	_court.set_elasticity(float(_physics["bounce"]))
	_score = 0
	_hits = 0
	_shots = 0
	_time_left = GAME_DURATION
	_charging = false
	_spawn_delay = -1.0
	_feedback_delay = 0.0
	_last_shot = {}
	for ball in _balls:
		ball.store()
	_previous.clear()
	_entered.clear()
	_ui.show_game(selected == "lab", _physics)
	_select_position(0)
	_update_ui()


func _in_play() -> bool:
	return _mode in ["game", "lab"]


func _select_position(index: int) -> void:
	if not _in_play():
		return
	_position_index = clampi(index, 0, SHOOT_SPOTS.size() - 1)
	_charging = false
	_free_position = false
	_set_cursor_free(false)
	_spawn_delay = -1.0
	_player.teleport_to(SHOOT_SPOTS[_position_index])
	var toward: Vector3 = FIBA.rim_center(-1.0) - _player.eyes_position()
	_look_yaw = atan2(-toward.x, -toward.z)
	_look_pitch = atan2(toward.y, Vector2(toward.x, toward.z).length())
	_sync_player_camera()
	_prepare_ball()
	_ui.show_feedback("")


func _set_cursor_free(free: bool) -> void:
	_cursor_free = free
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if free else Input.MOUSE_MODE_CAPTURED
	_player.controls_enabled = _in_play() and not _paused
	if free and _charging:
		_cancel_charge()
	_ui.set_cursor_free(free and _in_play())


func _sync_player_camera() -> void:
	_camera.global_position = _player.eyes_position()
	_camera.rotation = Vector3(_look_pitch, _look_yaw, 0.0)
	_player.heading = _look_yaw
	if is_instance_valid(_held):
		_held.global_position = _held_position()
		# At the set point the ball is above the head - out of the player's view.
		_held.visible = not (_charging and _charge_time >= SET_POINT_SECONDS)


func _hand_position() -> Vector3:
	return _camera.to_global(HAND_OFFSET)


func _release_position() -> Vector3:
	return _player.eyes_position() + Basis(Vector3.UP, _look_yaw) * RELEASE_OFFSET


## While charging the ball moves from the hands up to the set point.
func _held_position() -> Vector3:
	if not _charging:
		return _hand_position()
	return _hand_position().lerp(_release_position(), smoothstep(0.0, SET_POINT_SECONDS, _charge_time))


func _on_player_moved() -> void:
	if _in_play():
		_free_position = true


func _update_menu_camera() -> void:
	var angle := _clock * 0.07
	_camera.position = Vector3(sin(angle) * 15.0, 5.2, -4.0 + cos(angle) * 13.0)
	_camera.look_at(Vector3(0, 2.2, -10.0), Vector3.UP)


# --- aiming ------------------------------------------------------------------

## Hoop the player is facing (there is one at each end of the court).
func _target_rim() -> Vector3:
	var forward := Vector3(-sin(_look_yaw), 0.0, -cos(_look_yaw))
	var best: Vector3 = FIBA.rim_center(-1.0)
	var best_dot := -INF
	for rim in _court.rim_centers():
		var to_rim: Vector3 = rim - _player.global_position
		var facing := forward.dot(Vector3(to_rim.x, 0.0, to_rim.z).normalized())
		if facing > best_dot:
			best_dot = facing
			best = rim
	return best


func _points_from(foot: Vector3, rim: Vector3) -> int:
	return 3 if FIBA.is_three_point_spot(foot, rim) else 2


func _launch_angle() -> float:
	return clampf(_look_pitch + ARC_LIFT, deg_to_rad(-10.0), deg_to_rad(82.0))


func _aim_horizontal() -> Vector3:
	var forward := Vector3(-sin(_look_yaw), 0.0, -cos(_look_yaw))
	var rim := _target_rim()
	var eye := _camera.global_position
	var distance := clampf(Vector2(rim.x - eye.x, rim.z - eye.z).length(), 2.0, 30.0)
	var aim_point := eye + forward * distance
	var release := _release_position()
	var flat := Vector3(aim_point.x - release.x, 0.0, aim_point.z - release.z)
	return flat.normalized() if flat.length() > 0.05 else forward


func _launch_velocity(speed: float) -> Vector3:
	var angle := _launch_angle()
	return _aim_horizontal() * cos(angle) * speed + Vector3.UP * sin(angle) * speed


## Speed that drops the ball into the ring for a REFERENCE_ANGLE shot from here.
## Cached - recomputed when the player moves or the lab parameters change.
func _update_reference_speed() -> void:
	var release := _release_position()
	var rim := _target_rim()
	var key := Vector4(release.x, release.y, release.z, rim.z)
	if key.distance_to(_reference_key) < 0.2:
		return
	_reference_key = key
	var flat := Vector3(rim.x - release.x, 0.0, rim.z - release.z).normalized()
	_reference_speed = TRAJECTORY.ideal_speed(release, flat, REFERENCE_ANGLE, rim, float(_physics["spin"]), _physics)


func _speed_for_charge(charge: float) -> float:
	return _reference_speed * lerpf(POWER_RANGE.x, POWER_RANGE.y, clampf(charge, 0.0, 1.0))


# --- balls -------------------------------------------------------------------

func _prepare_ball() -> void:
	if not _in_play():
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
	_forget(candidate)
	_held = candidate
	_held.configure(_physics)
	_held.hold_at(_hand_position())
	_charge = 0.0
	_charging = false
	_preview.visible = false


func _forget(ball) -> void:
	_previous.erase(ball.get_instance_id())
	_entered.erase(ball.get_instance_id())


func _start_charge() -> void:
	if not _in_play() or _paused or _cursor_free or not is_instance_valid(_held):
		return
	_reference_key = Vector4(INF, 0, 0, 0)
	_update_reference_speed()
	_charge = 0.0
	_charge_time = 0.0
	_charging = true
	_preview_wait = 0.0
	_preview.visible = true


func _release_shot() -> void:
	if not _charging or not is_instance_valid(_held):
		return
	_charging = false
	var speed := _speed_for_charge(_charge)
	var velocity := _launch_velocity(speed)
	_held.configure(_physics)
	_held.global_position = _release_position()
	_held.visible = true
	_held.launch(velocity, BALL_SCRIPT.backspin(velocity, float(_physics["spin"])), _player.global_position)
	_previous[_held.get_instance_id()] = _held.global_position
	_last_shot = {"ball": _held, "speed": speed, "angle": rad_to_deg(_launch_angle()), "apex": 0.0, "flight": 0.0}
	_shots += 1
	_held = null
	_spawn_delay = 1.1
	_preview.visible = false
	_ui.show_feedback("")


func _cancel_charge() -> void:
	_charging = false
	_charge = 0.0
	_preview.visible = false


func _show_preview() -> void:
	if not is_instance_valid(_held):
		return
	var start := _release_position()
	var velocity := _launch_velocity(_speed_for_charge(_charge))
	var spin := BALL_SCRIPT.backspin(velocity, float(_physics["spin"]))
	var points: PackedVector3Array
	if _mode == "lab":
		points = TRAJECTORY.simulate(start, velocity, spin, _physics, 4.0, 4, get_world_3d().direct_space_state, 3)
	else:
		var rim := _target_rim()
		var distance := Vector2(rim.x - start.x, rim.z - start.z).length()
		points = TRAJECTORY.simulate(start, velocity, spin, _physics, 3.0, 4, null, 0, distance * GAME_PREVIEW_FRACTION)
	var eye := _camera.global_position
	var first := 0
	while first < points.size() - 1 and points[first].distance_to(eye) < 1.0:
		first += 1
	var count := mini(points.size() - first, _preview_mesh.instance_count)
	for i in range(_preview_mesh.instance_count):
		if i < count:
			_preview_mesh.set_instance_transform(i, Transform3D(Basis(), points[first + i]))
			var fade := 1.0 - float(i) / float(maxi(count, 1))
			var alpha := (0.25 + 0.65 * fade) if _mode != "lab" else 0.85
			_preview_mesh.set_instance_color(i, Color(0.45, 1.0, 0.88, alpha))
		else:
			_preview_mesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -50, 0)))


# --- loop --------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _in_play() or _paused:
		return
	_sync_player_camera()
	if _mode == "game":
		_time_left = maxf(0.0, _time_left - delta)
		if _time_left <= 0.0:
			_finish_round()
			return

	var rims: Array = _court.rim_centers()
	var nearest := []
	nearest.resize(rims.size())
	nearest.fill(null)
	for ball in _balls:
		if not ball.in_flight:
			continue
		var id: int = ball.get_instance_id()
		var current: Vector3 = ball.global_position
		var previous: Vector3 = _previous.get(id, current)
		for h in range(rims.size()):
			_check_score(ball, h, rims[h], previous, current)
			if current.distance_to(rims[h]) < 0.9 and (nearest[h] == null or current.distance_to(rims[h]) < nearest[h].global_position.distance_to(rims[h])):
				nearest[h] = ball
		_previous[id] = current
		if not _last_shot.is_empty() and _last_shot["ball"] == ball:
			_last_shot["apex"] = ball.apex
			_last_shot["flight"] = ball.first_contact_time if ball.first_contact_time >= 0.0 else ball.elapsed
		var resting: bool = ball.linear_velocity.length() < 0.08 and ball.elapsed > 2.0
		if ball.elapsed > 9.0 or current.y < -2.0 or resting:
			ball.store()
			_forget(ball)
	for h in range(rims.size()):
		_court.hoops[h].track_ball(nearest[h].global_position if nearest[h] != null else Vector3(0, -100, 0))


## Two-stage detection: the ball must cross the ring plane downward inside the ring,
## then drop SCORE_CHECK_DEPTH lower without coming back up (a rim-out is not counted).
func _check_score(ball, hoop_index: int, rim: Vector3, previous: Vector3, current: Vector3) -> void:
	var id: int = ball.get_instance_id()
	if previous.y >= rim.y and current.y < rim.y:
		var t := (previous.y - rim.y) / maxf(previous.y - current.y, 0.0001)
		var crossing := previous.lerp(current, t)
		if Vector2(crossing.x - rim.x, crossing.z - rim.z).length() < FIBA.RIM_RADIUS:
			_entered[id] = hoop_index
	if _entered.get(id, -1) != hoop_index:
		return
	if current.y > rim.y + 0.05:
		_entered.erase(id)
		return
	var bottom := rim.y - SCORE_CHECK_DEPTH
	if previous.y >= bottom and current.y < bottom:
		_entered.erase(id)
		_on_score(ball, hoop_index, rim)


func _on_score(ball, hoop_index: int, rim: Vector3) -> void:
	var points := _points_from(ball.launch_foot, rim)
	_score += points
	_hits += 1
	_court.hoops[hoop_index].celebrate(clampf(absf(ball.linear_velocity.y) / 5.0, 0.4, 1.0))
	_audio.play_swish(rim + Vector3.DOWN * 0.2)
	_audio.play_score()
	var how := "CZYSTY RZUT!" if not (ball.touched_rim or ball.touched_board) else ("Z TABLICY!" if ball.touched_board else "TRAFIONY!")
	_ui.show_feedback("%s  +%d PKT" % [how, points])
	_feedback_delay = 1.6


func _process(delta: float) -> void:
	_clock += delta
	if _mode == "menu" or _mode == "results":
		_update_menu_camera()
		return
	if not _in_play() or _paused:
		return
	if _charging:
		_charge_time += delta
		_charge = minf(1.0, _charge + delta / CHARGE_SECONDS)
		_preview_wait -= delta
		if _preview_wait <= 0.0:
			_preview_wait = 0.04
			_show_preview()
	if _spawn_delay >= 0.0:
		_spawn_delay -= delta
		if _spawn_delay < 0.0 and not is_instance_valid(_held):
			_prepare_ball()
	if _feedback_delay > 0.0:
		_feedback_delay -= delta
		if _feedback_delay <= 0.0:
			_ui.show_feedback("")
	if _mode == "lab":
		_lab_wait -= delta
		if _lab_wait <= 0.0:
			_lab_wait = 0.2
			_update_lab_readout()
	_update_ui()


func _update_lab_readout() -> void:
	var release := _release_position()
	var rim := _target_rim()
	var ideal := TRAJECTORY.ideal_speed(release, _aim_horizontal(), _launch_angle(), rim, float(_physics["spin"]), _physics)
	_ui.update_lab(ideal if ideal < 34.0 else -1.0, rad_to_deg(_launch_angle()), _last_shot)


func _update_ui() -> void:
	if not _in_play():
		return
	var place: String
	if _free_position:
		place = "Pozycja swobodna  •  %d pkt" % _points_from(_player.global_position, _target_rim())
	else:
		place = POSITION_NAMES[_position_index]
	_ui.update_hud(_score, _shots, _hits, _time_left, _best, -1 if _free_position else _position_index, place)
	if not _charging:
		_update_reference_speed()
	_ui.update_aim(_charge, _speed_for_charge(_charge), rad_to_deg(_launch_angle()), _charging)


# --- input -------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not _in_play() or _paused:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		_set_cursor_free(not _cursor_free)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and not _cursor_free:
		var sensitivity := float(_settings["sensitivity"]) * 0.0024
		_look_yaw -= event.relative.x * sensitivity
		_look_pitch = clampf(_look_pitch - event.relative.y * sensitivity, deg_to_rad(-75.0), deg_to_rad(75.0))
		_sync_player_camera()
		if _charging:
			_preview_wait = 0.0
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and _charging:
		_release_shot()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				if _in_play():
					_toggle_pause()
			KEY_R:
				if _in_play() and not _paused:
					_restart()
			KEY_M:
				if _mode != "menu":
					_return_menu()
			KEY_L:
				if _mode == "lab" and not _paused:
					_ui.toggle_lab_panel()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				if _in_play() and not _paused:
					_select_position(event.keycode - KEY_1)
	if _paused or not _in_play():
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _cursor_free:
				_set_cursor_free(false)
			else:
				_start_charge()
		elif event.button_index == MOUSE_BUTTON_RIGHT and _charging:
			_cancel_charge()


func _on_ball_impact(strength: float, surface: String, ball) -> void:
	if _in_play() and not _paused:
		_audio.play_impact(strength, surface, ball.global_position)


func _on_lab_changed(key: String, value: float) -> void:
	if _mode != "lab":
		return
	if key == "reset":
		_physics = DEFAULT_PHYSICS.duplicate()
		_ui.show_game(true, _physics)
		_set_cursor_free(true)
	elif key == "magnus":
		_physics["magnus"] = value > 0.5
	else:
		_physics[key] = value
	_court.set_elasticity(float(_physics["bounce"]))
	for ball in _balls:
		ball.configure(_physics)
	_reference_key = Vector4(INF, 0, 0, 0)
	_lab_wait = 0.0
	_update_ui()


# --- pause / results ---------------------------------------------------------

func _toggle_pause() -> void:
	if not _in_play():
		return
	if _paused:
		_resume_game()
	else:
		_paused = true
		_cancel_charge()
		_set_cursor_free(true)
		get_tree().paused = true
		_ui.show_pause()


func _resume_game() -> void:
	get_tree().paused = false
	_paused = false
	_ui.hide_pause()
	if _in_play():
		_set_cursor_free(false)


func _restart() -> void:
	_start_mode("lab" if _mode == "lab" else "game")


func _finish_round() -> void:
	if _mode != "game":
		return
	_mode = "results"
	_set_cursor_free(true)
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
