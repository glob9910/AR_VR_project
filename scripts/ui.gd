extends CanvasLayer
signal start_requested(mode: String)
signal position_requested(index: int)
signal pause_requested
signal resume_requested
signal restart_requested
signal menu_requested
signal settings_changed(key: String, value: float)
signal lab_changed(key: String, value: float)

const TEXT = Color("#f5f5e9")
const MUTED = Color("#a3b9c6")
const TEAL = Color("#42dbc9")
const GOLD = Color("#ffc65b")

var root: Control
var _stat_score: Label
var _stat_clock: Label
var _stat_shots: Label
var _stat_accuracy: Label
var _stat_best: Label
var _status: Label
var _aim: Label
var _power: ProgressBar
var _power_text: Label
var _position_text: Label
var _instruction: Label
var _pause_overlay: Control
var _lab_panel: PanelContainer
var _menu_settings := {"sensitivity": 1.0, "volume": 0.75}
var _game_lab := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.name = "UIRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)


func _clear() -> void:
	for child in root.get_children():
		root.remove_child(child)
		child.queue_free()
	_pause_overlay = null
	_lab_panel = null


func _style_panel(bg: Color = Color(0.035, 0.09, 0.14, 0.93), accent: Color = Color("#2f6475")) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = accent
	style.set_border_width_all(1)
	style.set_corner_radius_all(15)
	style.content_margin_left = 20.0
	style.content_margin_right = 20.0
	style.content_margin_top = 17.0
	style.content_margin_bottom = 17.0
	return style


func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style_panel())
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


func _vbox(spacing: int = 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", spacing)
	return v


func _label(value: String, size: int = 18, color: Color = TEXT, center: bool = false) -> Label:
	var result := Label.new()
	result.text = value
	result.add_theme_color_override("font_color", color)
	result.add_theme_font_size_override("font_size", size)
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if center else HORIZONTAL_ALIGNMENT_LEFT
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return result


func _button(text_value: String, callback: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text_value
	b.custom_minimum_size = Vector2(0, 47)
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", Color("#0b2530") if primary else TEXT)
	b.add_theme_color_override("font_hover_color", Color("#06242c") if primary else TEXT)
	var normal := _style_panel(TEAL if primary else Color("#123446"), TEAL if primary else Color("#355a6a"))
	normal.set_corner_radius_all(9)
	normal.content_margin_top = 7
	normal.content_margin_bottom = 7
	var hover := _style_panel(GOLD if primary else Color("#20536a"), GOLD if primary else TEAL)
	hover.set_corner_radius_all(9)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.pressed.connect(callback)
	return b


func _background(dim: float = 0.70) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.012, 0.034, 0.060, dim)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)


func _center_panel(width: float = 520.0) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var panel := _panel()
	panel.custom_minimum_size = Vector2(width, 0)
	center.add_child(panel)
	var content := _vbox(15)
	panel.add_child(content)
	return content


func show_menu(best: int, sensitivity: float, volume: float) -> void:
	_menu_settings["sensitivity"] = sensitivity
	_menu_settings["volume"] = volume
	_clear()
	_background(0.72)
	var v := _center_panel(540)
	v.add_child(_label("AR/VR Projekt", 52, TEAL, true))
	v.add_child(_label("grupa 1, zespół 2", 17, GOLD, true))
	v.add_child(_label("REKORD  %d PKT" % best, 21, GOLD, true))
	v.add_child(_button("GRA NA CZAS  •  90 SEKUND", _request_start_game, true))
	v.add_child(_button("LABORATORIUM FIZYKI", _request_start_lab))
	v.add_child(_button("USTAWIENIA", _open_menu_settings))
	v.add_child(_button("INSTRUKCJA", show_instructions))
	v.add_child(_label("Godot 4.3", 13, MUTED, true))


func show_instructions() -> void:
	_clear()
	_background(0.8)
	var v := _center_panel(645)
	v.add_child(_label("JAK GRAĆ?", 34, TEAL, true))
	v.add_child(_label("1. Wybierz pozycję za pomocą przycisków lub klawiszy 1–5."))
	v.add_child(_label("2. WSAD = chodzenie, SHIFT = bieg, SPACJA = skok. Mysz obraca kamerę."))
	v.add_child(_label("3. Przytrzymaj LPM, aby ładować siłę. Celownik wskazuje kierunek rzutu."))
	v.add_child(_label("4. Zwolnij LPM, żeby rzucić piłkę z miejsca, w którym stoisz."))
	v.add_child(_label("5. Podgląd z punktów pokazuje przewidywaną trajektorię."))
	v.add_child(_label("6. Punktacja (2 lub 3) jest obliczana z aktualnej odległości od kosza."))
	v.add_child(_label("TAB = uwolnij/zablokuj kursor do paneli opcji, ESC = pauza, R = restart, M = menu."))
	v.add_child(_label("LABORATORIUM: grawitacja, masa, sprężystość, opór powietrza, rotacja i wiatr.", 16, GOLD))
	v.add_child(_button("WRÓĆ DO MENU", _request_menu, true))


func show_settings(from_pause: bool) -> void:
	_clear()
	_background(0.80)
	var v := _center_panel(520)
	v.add_child(_label("USTAWIENIA", 32, TEAL, true))
	v.add_child(_label("Czułość sterowania myszą", 17))
	_add_settings_slider(v, "sensitivity", 0.25, 3.0, 0.05)
	v.add_child(_label("Głośność dźwięku", 17))
	_add_settings_slider(v, "volume", 0.0, 1.0, 0.05)
	if from_pause:
		v.add_child(_button("WRÓĆ DO PAUZY", _request_resume, true))
	else:
		v.add_child(_button("WRÓĆ DO MENU", _request_menu, true))


func _add_settings_slider(parent: VBoxContainer, key: String, minimum: float, maximum: float, step: float) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value = float(_menu_settings[key])
	row.add_child(slider)
	var value_label := _label("%.2f" % slider.value, 16, GOLD)
	value_label.custom_minimum_size.x = 60
	row.add_child(value_label)
	slider.value_changed.connect(func(value: float) -> void:
		_menu_settings[key] = value
		value_label.text = "%.2f" % value
		settings_changed.emit(key, value)
	)


func show_game(laboratory: bool, settings: Dictionary) -> void:
	_game_lab = laboratory
	_clear()
	# Left score panel
	var left := _panel()
	left.position = Vector2(18, 17)
	left.custom_minimum_size = Vector2(325, 0)
	root.add_child(left)
	var left_v := _vbox(5)
	left.add_child(left_v)
	left_v.add_child(_label("AR/VR PROJEKT   /   " + ("LABORATORIUM" if laboratory else "GRA NA CZAS"), 15, TEAL))
	_stat_score = _label("WYNIK     0", 30, GOLD)
	left_v.add_child(_stat_score)
	_stat_clock = _label("CZAS      --:--", 20)
	left_v.add_child(_stat_clock)
	_stat_shots = _label("RZUTY     0", 17, MUTED)
	left_v.add_child(_stat_shots)
	_stat_accuracy = _label("SKUTECZNOŚĆ     0%", 17, MUTED)
	left_v.add_child(_stat_accuracy)
	_stat_best = _label("REKORD     0", 15, GOLD)
	left_v.add_child(_stat_best)

	# Selection of positions
	var positions := _panel()
	positions.position = Vector2(18, 256)
	positions.custom_minimum_size = Vector2(325, 0)
	root.add_child(positions)
	var p_v := _vbox(6)
	positions.add_child(p_v)
	p_v.add_child(_label("POZYCJA RZUTOWA", 15, TEAL))
	for i in range(5):
		var names := ["1  •  ZA 2 PUNKTY", "2  •  ZA 3  /  ŚRODEK", "3  •  ZA 3  /  LEWA", "4  •  ZA 3  /  PRAWA", "5  •  Z POŁOWY BOISKA"]
		var btn := _button(names[i], _emit_position.bind(i))
		btn.custom_minimum_size.y = 34.0
		p_v.add_child(btn)
	_position_text = _label("AKTYWNA: ZA 2 PUNKTY", 14, GOLD)
	p_v.add_child(_position_text)
	p_v.add_child(_button("PAUZA  •  ESC", _request_pause))

	# aim, communication, force
	_aim = _label("+", 32, Color("#f9ecb8"), true)
	_aim.anchor_left = 0.5
	_aim.anchor_top = 0.5
	_aim.anchor_right = 0.5
	_aim.anchor_bottom = 0.5
	_aim.offset_left = -30
	_aim.offset_top = -38
	_aim.offset_right = 30
	_aim.offset_bottom = 38
	_aim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_aim)

	_status = _label("", 30, GOLD, true)
	_status.anchor_left = 0.30
	_status.anchor_right = 0.70
	_status.anchor_top = 0.20
	_status.anchor_bottom = 0.20
	_status.offset_top = -20
	_status.offset_bottom = 35
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_status)

	var bottom := _panel()
	bottom.anchor_left = 0.5
	bottom.anchor_right = 0.5
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_left = -280
	bottom.offset_right = 280
	bottom.offset_top = -142
	bottom.offset_bottom = -18
	root.add_child(bottom)
	var b_v := _vbox(4)
	bottom.add_child(b_v)
	_power_text = _label("LPM: PRZYTRZYMAJ = SIŁA   •   MYSZ: CELOWANIE", 16, TEAL, true)
	b_v.add_child(_power_text)
	_power = ProgressBar.new()
	_power.min_value = 0
	_power.max_value = 100
	_power.value = 0
	_power.show_percentage = false
	_power.custom_minimum_size.y = 18
	b_v.add_child(_power)
	_instruction = _label("WASD: ruch  •  mysz: widok  •  TAB: panel", 14, MUTED, true)
	b_v.add_child(_instruction)
	if laboratory:
		_make_lab_panel(settings)


func _make_lab_panel(settings: Dictionary) -> void:
	_lab_panel = _panel()
	_lab_panel.anchor_left = 1.0
	_lab_panel.anchor_right = 1.0
	_lab_panel.offset_left = -334
	_lab_panel.offset_right = -18
	_lab_panel.offset_top = 17
	_lab_panel.offset_bottom = 590
	root.add_child(_lab_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_lab_panel.add_child(scroll)
	var v := _vbox(8)
	v.custom_minimum_size.x = 260
	scroll.add_child(v)
	v.add_child(_label("LABORATORIUM", 23, TEAL))
	var presets := OptionButton.new()
	presets.add_item("Ziemia   •   9,81 m/s²")
	presets.add_item("Księżyc   •   1,62 m/s²")
	presets.add_item("Mars   •   3,71 m/s²")
	presets.add_item("Własna wartość")
	presets.selected = 0
	v.add_child(presets)
	var gravity_slider := _lab_slider(v, "gravity", "Grawitacja", " m/s²", 1.0, 20.0, 0.01, settings)
	presets.item_selected.connect(func(index: int) -> void:
		var gravities := [9.81, 1.62, 3.71]
		if index < 3:
			gravity_slider.value = gravities[index]
	)
	_lab_slider(v, "bounce", "Sprężystość", "", 0.2, 0.98, 0.01, settings)
	_lab_slider(v, "mass", "Masa piłki", " kg", 0.3, 1.2, 0.01, settings)
	_lab_slider(v, "spin", "Rotacja", " rad/s", -20.0, 20.0, 0.5, settings)
	_lab_slider(v, "wind", "Wiatr w osi X", " m/s", -10.0, 10.0, 0.25, settings)
	_lab_slider(v, "drag", "Wsp. oporu Cd", "", 0.0, 1.2, 0.01, settings)
	v.add_child(_button("PRZYWRÓĆ ZIEMSKIE", _request_lab_reset))


func _lab_slider(parent: VBoxContainer, key: String, caption: String, unit: String, minimum: float, maximum: float, step: float, settings: Dictionary) -> HSlider:
	var value := float(settings.get(key, minimum))
	var title_label := _label("%s  %.2f%s" % [caption, value, unit], 14, TEXT)
	parent.add_child(title_label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = value
	parent.add_child(slider)
	slider.value_changed.connect(func(next: float) -> void:
		title_label.text = "%s  %.2f%s" % [caption, next, unit]
		lab_changed.emit(key, next)
	)
	return slider


func update_hud(score: int, shots: int, hits: int, time_left: float, best: int, position_name: String) -> void:
	if not is_instance_valid(_stat_score):
		return
	_stat_score.text = "WYNIK     %d PKT" % score
	_stat_clock.text = "CZAS      BEZ LIMITU" if _game_lab else "CZAS      %02d:%02d" % [int(ceil(time_left)) / 60, int(ceil(time_left)) % 60]
	_stat_shots.text = "RZUTY     %d   /   TRAFIENIA     %d" % [shots, hits]
	_stat_accuracy.text = "SKUTECZNOŚĆ     %.1f%%" % (100.0 * float(hits) / float(maxi(shots, 1)))
	_stat_best.text = "REKORD     %d PKT" % best
	_position_text.text = "AKTYWNA: " + position_name


func update_aim(strength: float, angle: float, speed: float, holding: bool) -> void:
	if not is_instance_valid(_power):
		return
	_power.value = strength * 100.0 if holding else 0.0
	_power_text.text = "SIŁA %.0f%%  /  PRĘDKOŚĆ %.1f m/s" % [strength * 100.0, speed] if holding else "LPM: PRZYTRZYMAJ = SIŁA   •   MYSZ: CELOWANIE"
	_instruction.text = "Kierunek kamery %.0f°   •   prędkość %.1f m/s" % [angle, speed]


func show_feedback(message: String, positive: bool = true) -> void:
	if is_instance_valid(_status):
		_status.text = message
		_status.add_theme_color_override("font_color", GOLD if positive else MUTED)


func show_pause() -> void:
	if is_instance_valid(_pause_overlay):
		return
	_pause_overlay = Control.new()
	_pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_pause_overlay)
	var tint := ColorRect.new()
	tint.color = Color(0.01, 0.02, 0.04, 0.83)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.add_child(tint)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_overlay.add_child(center)
	var panel := _panel()
	panel.custom_minimum_size.x = 445
	center.add_child(panel)
	var v := _vbox(12)
	panel.add_child(v)
	v.add_child(_label("PAUZA", 39, TEAL, true))
	v.add_child(_button("WZNÓW", _request_resume, true))
	v.add_child(_button("RESTART", _request_restart))
	v.add_child(_label("Czułość myszy", 14, MUTED))
	_add_settings_slider(v, "sensitivity", 0.25, 3.0, 0.05)
	v.add_child(_label("Głośność", 14, MUTED))
	_add_settings_slider(v, "volume", 0.0, 1.0, 0.05)
	v.add_child(_button("MENU GŁÓWNE", _request_menu))
	v.add_child(_label("ESC = powrót do gry", 14, MUTED, true))


func hide_pause() -> void:
	if is_instance_valid(_pause_overlay):
		_pause_overlay.queue_free()
		_pause_overlay = null


func show_results(score: int, shots: int, hits: int, best: int, is_record: bool) -> void:
	_clear()
	_background(0.84)
	var v := _center_panel(530)
	v.add_child(_label("KONIEC CZASU", 36, TEAL, true))
	v.add_child(_label("%d PKT" % score, 64, GOLD, true))
	if is_record:
		v.add_child(_label("NOWY REKORD!", 23, GOLD, true))
	v.add_child(_label("Oddane rzuty: %d" % shots, 20, TEXT, true))
	v.add_child(_label("Trafienia: %d" % hits, 20, TEXT, true))
	v.add_child(_label("Skuteczność: %.1f%%" % (100.0 * float(hits) / float(maxi(shots, 1))), 20, TEXT, true))
	v.add_child(_label("Najlepszy wynik: %d pkt" % best, 18, GOLD, true))
	v.add_child(_button("ZAGRAJ PONOWNIE", _request_restart, true))
	v.add_child(_button("MENU GŁÓWNE", _request_menu))


func _emit_position(index: int) -> void:
	position_requested.emit(index)


func _request_start_game() -> void:
	start_requested.emit("game")


func _request_start_lab() -> void:
	start_requested.emit("lab")


func _open_menu_settings() -> void:
	show_settings(false)


func _request_menu() -> void:
	menu_requested.emit()


func _request_pause() -> void:
	pause_requested.emit()


func _request_resume() -> void:
	resume_requested.emit()


func _request_restart() -> void:
	restart_requested.emit()


func _request_lab_reset() -> void:
	lab_changed.emit("reset", 0.0)
