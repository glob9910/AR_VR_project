extends SceneTree
## Headless: loads the main scene, starts each mode and runs a few hundred frames.

var main: Node
var frame := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	process_frame.connect(_tick)


func _tick() -> void:
	frame += 1
	match frame:
		10:
			main._start_mode("game")
		30:
			main._start_charge()
		120:
			main._release_shot()
			print("SMOKE shot fired, shots=", main._shots)
		200:
			main._start_mode("lab")
			main._on_lab_changed("gravity", 1.62)
			main._start_charge()
		260:
			main._release_shot()
			main._update_lab_readout()
		320:
			main._toggle_pause()
		330:
			main._resume_game()
			main._return_menu()
		340:
			print("SMOKE OK")
			quit()
