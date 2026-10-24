extends Node
## Positional impact sounds (volume and pitch depend on impact strength),
## UI sounds and a looping park ambience. Recordings: assets/CREDITS.md.

const SOUND_BOUNCE = "res://assets/sounds/bounce.wav"
const SOUND_RIM = "res://assets/sounds/rim.wav"
const SOUND_RIM_2 = "res://assets/sounds/rim2.wav"
const SOUND_BACKBOARD = "res://assets/sounds/backboard.wav"
const SOUND_SWISH = "res://assets/sounds/swish.wav"
const SOUND_SCORE = "res://assets/sounds/score.wav"
const SOUND_END = "res://assets/sounds/end.wav"
const SOUND_AMBIENT = "res://assets/sounds/ambient_park.ogg"

var _players_3d: Array[AudioStreamPlayer3D] = []
var _players_2d: Array[AudioStreamPlayer] = []
var _next_3d := 0
var _next_2d := 0
var _ambient: AudioStreamPlayer
var _sounds := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in range(10):
		var player := AudioStreamPlayer3D.new()
		player.name = "Impact%d" % i
		player.unit_size = 7.0
		player.max_distance = 70.0
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(player)
		_players_3d.append(player)
	for i in range(4):
		var player := AudioStreamPlayer.new()
		player.name = "Ui%d" % i
		add_child(player)
		_players_2d.append(player)
	for key in ["bounce", "rim", "rim2", "backboard", "swish", "score", "end"]:
		_sounds[key] = _load_sound(_path_for(key))
	_ambient = AudioStreamPlayer.new()
	_ambient.name = "Ambient"
	_ambient.stream = _load_sound(SOUND_AMBIENT)
	if _ambient.stream is AudioStreamOggVorbis:
		(_ambient.stream as AudioStreamOggVorbis).loop = true
	_ambient.volume_db = -14.0
	add_child(_ambient)
	_ambient.play()


func _path_for(key: String) -> String:
	match key:
		"bounce": return SOUND_BOUNCE
		"rim": return SOUND_RIM
		"rim2": return SOUND_RIM_2
		"backboard": return SOUND_BACKBOARD
		"swish": return SOUND_SWISH
		"score": return SOUND_SCORE
		_: return SOUND_END


func _load_sound(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		push_warning("Brak dźwięku: " + path)
		return null
	return load(path) as AudioStream


func _play_at(stream: AudioStream, at: Vector3, pitch: float, volume: float) -> void:
	if stream == null:
		return
	var player := _players_3d[_next_3d]
	_next_3d = (_next_3d + 1) % _players_3d.size()
	player.stop()
	player.stream = stream
	player.global_position = at
	player.pitch_scale = pitch * randf_range(0.96, 1.04)
	player.volume_db = linear_to_db(clampf(volume, 0.01, 1.0))
	player.play()


func _play_ui(stream: AudioStream, pitch: float = 1.0, volume: float = 0.7) -> void:
	if stream == null:
		return
	var player := _players_2d[_next_2d]
	_next_2d = (_next_2d + 1) % _players_2d.size()
	player.stop()
	player.stream = stream
	player.pitch_scale = pitch
	player.volume_db = linear_to_db(clampf(volume, 0.01, 1.0))
	player.play()


func play_impact(strength: float, surface: String, at: Vector3) -> void:
	var volume := clampf(strength / 10.0, 0.08, 1.0)
	if surface.contains("Rim"):
		var stream: AudioStream = _sounds["rim"] if randf() < 0.5 else _sounds["rim2"]
		_play_at(stream, at, clampf(0.9 + strength / 30.0, 0.9, 1.2), volume)
	elif surface.contains("Backboard"):
		_play_at(_sounds["backboard"], at, clampf(0.9 + strength / 30.0, 0.85, 1.15), volume)
	elif surface.contains("Pole") or surface.contains("Fence"):
		_play_at(_sounds["rim2"], at, 0.55, volume * 0.6)
	elif surface.contains("Grass"):
		_play_at(_sounds["bounce"], at, 0.7, volume * 0.35)
	else:
		_play_at(_sounds["bounce"], at, clampf(0.85 + strength / 40.0, 0.85, 1.15), volume)


func play_swish(at: Vector3) -> void:
	_play_at(_sounds["swish"], at, 1.0, 0.9)


func play_score() -> void:
	_play_ui(_sounds["score"], 1.1, 0.35)


func play_end() -> void:
	_play_ui(_sounds["end"], 1.0, 0.8)
