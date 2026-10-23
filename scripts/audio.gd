extends Node
const SOUND_BOUNCE = "res://assets/sounds/bounce.wav"
const SOUND_RIM = "res://assets/sounds/rim.wav"
const SOUND_BACKBOARD = "res://assets/sounds/backboard.wav"
const SOUND_SCORE = "res://assets/sounds/score.wav"
const SOUND_END = "res://assets/sounds/end.wav"

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _bounce: AudioStream
var _rim: AudioStream
var _board: AudioStream
var _score: AudioStream
var _end: AudioStream


func _ready() -> void:
	for i in range(9):
		var player := AudioStreamPlayer.new()
		player.name = "SoundChannel%d" % i
		add_child(player)
		_players.append(player)
	_bounce = _load_sound(SOUND_BOUNCE)
	_rim = _load_sound(SOUND_RIM)
	_board = _load_sound(SOUND_BACKBOARD)
	_score = _load_sound(SOUND_SCORE)
	_end = _load_sound(SOUND_END)


func _load_sound(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var resource: Resource = ResourceLoader.load(path)
	if resource is AudioStream:
		return resource as AudioStream
	push_warning("Nie można załadować dźwięku: " + path)
	return null


func _play(stream: AudioStream, pitch: float = 1.0, volume: float = 0.7) -> void:
	if stream == null or _players.is_empty():
		return
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	player.stop()
	player.stream = stream
	player.pitch_scale = pitch
	player.volume_db = linear_to_db(clampf(volume, 0.01, 1.0))
	player.play()


func play_impact(speed: float, surface: String) -> void:
	var volume := clampf(speed / 12.0, 0.12, 0.92)
	if surface.contains("Rim"):
		_play(_rim, clampf(0.78 + speed / 22.0, 0.8, 1.7), volume)
	elif surface.contains("Backboard"):
		_play(_board, clampf(0.85 + speed / 28.0, 0.8, 1.4), volume)
	else:
		_play(_bounce, clampf(0.80 + speed / 24.0, 0.78, 1.55), volume)


func play_score() -> void:
	_play(_score, 1.15, 0.83)


func play_end() -> void:
	_play(_end, 1.0, 0.74)
