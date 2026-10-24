extends CanvasLayer
signal start_requested(mode: String)
signal position_requested(index: int)
signal pause_requested
signal resume_requested
signal restart_requested
signal menu_requested
signal settings_changed(key: String, value: float)
signal lab_changed(key: String, value: float)

const TEXT = Color("#f3f4ee")
const MUTED = Color("#a7b6bf")
const TEAL = Color("#45d6c4")
const GOLD = Color("#ffc65b")
const PANEL_BG = Color(0.03, 0.07, 0.1, 0.74)
const POSITION_LABELS = ["1", "2", "3", "4", "5"]
const POSITION_TIPS = [
	"Linia rzutów wolnych (2 pkt)", "Za 3 – środek", "Za 3 – lewe skrzydło",
	"Za 3 – prawe skrzydło", "Z połowy boiska"
]


class Crosshair extends Control:
	var charging := false

	func _draw() -> void:
		var c := size * 0.5
		var color := Color(1, 0.93, 0.7, 0.95) if charging else Color(1, 1, 1, 0.8)
		draw_arc(c, 9.0, 0.0, TAU, 32, Color(0, 0, 0, 0.35), 3.0, true)
		draw_arc(c, 9.0, 0.0, TAU, 32, color, 1.5, true)
		draw_circle(c, 1.8, color)


var root: Control
var _stat_score: Label
var _stat_clock: Label
var _stat_shots: Label
var _stat_best: Label
var _mode_label: Label
var _position_label: Label
var _position_buttons: Array[Button] = []
var _power: ProgressBar
var _power_text: Label
var _hint: Label
var _status: Label
var _cursor_hint: Label
var _crosshair: Crosshair
var _pause_overlay: Control
var _lab_panel: PanelContainer
var _lab_body: Control
var _lab_toggle: Button
var _lab_ideal: Label
var _lab_rebound: Label
var _lab_last: Label
var _settings := {"sensitivity": 1.0, "volume": 0.75, "quality": 1.0}
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
	_crosshair = null
	_position_buttons.clear()


# --- widgets -----------------------------------------------------------------

func _style(bg: Color = PANEL_BG, border: Color = Color(1, 1, 1, 0.08), radius: int = 10, margin: float = 12.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin * 0.75
	style.content_margin_bottom = margin * 0.75
	return style


func _panel(margin: float = 12.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style(PANEL_BG, Color(1, 1, 1, 0.08), 10, margin))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


func _vbox(spacing: int = 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", spacing)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


func _label(value: String, size: int = 15, color: Color = TEXT, center: bool = false) -> Label:
	var result := Label.new()
	result.text = value
	result.add_theme_color_override("font_color", color)
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	result.add_theme_constant_override("shadow_offset_y", 1)
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if center else HORIZONTAL_ALIGNMENT_LEFT
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result


func _button(text_value: String, callback: Callable, primary: bool = false, height: float = 40.0, font: int = 15) -> Button:
	var b := Button.new()
	b.text = text_value
	b.custom_minimum_size = Vector2(0, height)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font)
	b.add_theme_color_override("font_color", Color("#0b2530") if primary else TEXT)
	b.add_theme_color_override("font_hover_color", Color("#06242c") if primary else TEXT)
	b.add_theme_color_override("font_pressed_color", Color("#06242c"))
	var normal := _style(TEAL if primary else Color(0.09, 0.2, 0.26, 0.9), Color(1, 1, 1, 0.1), 7, 8)
	var hover := _style(GOLD if primary else Color(0.13, 0.31, 0.39, 0.95), TEAL, 7, 8)
	var pressed := _style(GOLD, GOLD, 7, 8)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.pressed.connect(callback)
	return b


func _background(dim: float = 0.6) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.03, 0.05, dim)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)


func _center_panel(width: float = 480.0, parent: Control = null) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent != null else root).add_child(center)
	var panel := _panel(22.0)
	panel.custom_minimum_size = Vector2(width, 0)
	center.add_child(panel)
	var content := _vbox(12)
	panel.add_child(content)
	return content


func _slider_row(parent: Control, caption: String, unit: String, minimum: float, maximum: float, step: float, value: float, on_change: Callable, digits: int = 2) -> HSlider:
	var title := _label("", 13, TEXT)
	parent.add_child(title)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = value
	slider.focus_mode = Control.FOCUS_NONE
	slider.custom_minimum_size.y = 18
	parent.add_child(slider)
	var format := "%s   %." + str(digits) + "f%s"
	title.text = format % [caption, value, unit]
	slider.value_changed.connect(func(next: float) -> void:
		title.text = format % [caption, next, unit]
		on_change.call(next)
	)
	return slider


# --- menu screens ------------------------------------------------------------

func show_menu(best: int, settings: Dictionary) -> void:
	_settings.merge(settings, true)
	_clear()
	_background(0.35)
	var v := _center_panel(460)
	v.add_child(_label("HOOP LAB", 46, TEAL, true))
	v.add_child(_label("Symulacja fizyki rzutu do kosza  •  AR/VR gr. 1, zesp. 2", 14, MUTED, true))
	v.add_child(_label("REKORD  %d PKT" % best, 18, GOLD, true))
	v.add_child(_button("GRA NA CZAS  •  90 SEKUND", func() -> void: start_requested.emit("game"), true, 46, 16))
	v.add_child(_button("LABORATORIUM FIZYKI", func() -> void: start_requested.emit("lab"), false, 42))
	v.add_child(_button("USTAWIENIA", func() -> void: show_settings(false), false, 42))
	v.add_child(_button("INSTRUKCJA", show_instructions, false, 42))
	v.add_child(_label("Godot 4.3  •  boisko FIBA w skali 1:1", 12, MUTED, true))


func show_instructions() -> void:
	_clear()
	_background(0.6)
	var v := _center_panel(620)
	v.add_child(_label("JAK GRAĆ?", 30, TEAL, true))
	for line in [
		"Mysz – celowanie. Patrz na obręcz: kąt wyrzutu to pochylenie kamery + naturalny łuk rzutu.",
		"Przytrzymaj LPM, aby ładować siłę (ok. 2,5 s), puść, żeby rzucić. PPM anuluje rzut.",
		"Zakres siły dopasowuje się do odległości od kosza. Kropki pokazują początek toru lotu.",
		"Klawisze 1–5 – pozycje rzutowe. WSAD – chodzenie, SHIFT – bieg, SPACJA – skok.",
		"Punkty (2 lub 3) liczą się od miejsca, z którego rzucasz – linia 6,75 m jak w FIBA.",
		"TAB – kursor do paneli (gra toczy się dalej), ESC – pauza, R – restart, M – menu.",
	]:
		v.add_child(_label("•  " + line, 15))
	v.add_child(_label("LABORATORIUM: grawitacja (Ziemia / Księżyc / Mars), sprężystość, masa, rotacja (efekt Magnusa), wiatr, opór powietrza. Pełny podgląd toru z odbiciami, klawisz L zwija panel.", 14, GOLD))
	v.add_child(_button("WRÓĆ DO MENU", func() -> void: menu_requested.emit(), true))


func _settings_controls(v: VBoxContainer) -> void:
	_slider_row(v, "Czułość myszy", "", 0.25, 3.0, 0.05, float(_settings["sensitivity"]), func(x: float) -> void: _emit_setting("sensitivity", x))
	_slider_row(v, "Głośność", "", 0.0, 1.0, 0.05, float(_settings["volume"]), func(x: float) -> void: _emit_setting("volume", x))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var caption := _label("Jakość grafiki", 13)
	caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(caption)
	var quality := OptionButton.new()
	quality.focus_mode = Control.FOCUS_NONE
	quality.add_item("Wysoka (cienie, SSAO, MSAA)")
	quality.add_item("Niska (słabszy laptop)")
	quality.selected = 0 if float(_settings["quality"]) > 0.5 else 1
	quality.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quality.item_selected.connect(func(index: int) -> void: _emit_setting("quality", 1.0 if index == 0 else 0.0))
	row.add_child(quality)
	v.add_child(row)


func _emit_setting(key: String, value: float) -> void:
	_settings[key] = value
	settings_changed.emit(key, value)


func show_settings(from_pause: bool) -> void:
	_clear()
	_background(0.6)
	var v := _center_panel(460)
	v.add_child(_label("USTAWIENIA", 28, TEAL, true))
	_settings_controls(v)
	if from_pause:
		v.add_child(_button("WRÓĆ DO GRY", func() -> void: resume_requested.emit(), true))
	else:
		v.add_child(_button("WRÓĆ DO MENU", func() -> void: menu_requested.emit(), true))


# --- in-game HUD -------------------------------------------------------------

func show_game(laboratory: bool, physics: Dictionary) -> void:
	_game_lab = laboratory
	_clear()
	_build_stats_panel(laboratory)
	_build_power_panel()

	_crosshair = Crosshair.new()
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.offset_left = -20
	_crosshair.offset_top = -20
	_crosshair.offset_right = 20
	_crosshair.offset_bottom = 20
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_crosshair)

	_status = _label("", 28, GOLD, true)
	_status.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_status.offset_left = -320
	_status.offset_right = 320
	_status.offset_top = 96
	root.add_child(_status)

	_cursor_hint = _label("KURSOR AKTYWNY  •  kliknij w scenę albo TAB, aby wrócić do celowania", 13, TEAL, true)
	_cursor_hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_cursor_hint.offset_left = -300
	_cursor_hint.offset_right = 300
	_cursor_hint.offset_top = 14
	_cursor_hint.visible = false
	root.add_child(_cursor_hint)

	if laboratory:
		_build_lab_panel(physics)


func _build_stats_panel(laboratory: bool) -> void:
	var panel := _panel(12.0)
	panel.position = Vector2(14, 14)
	panel.custom_minimum_size = Vector2(236, 0)
	root.add_child(panel)
	var v := _vbox(2)
	panel.add_child(v)
	_mode_label = _label("LABORATORIUM" if laboratory else "GRA NA CZAS", 12, TEAL)
	v.add_child(_mode_label)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	_stat_score = _label("0 PKT", 26, GOLD)
	_stat_score.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_stat_score)
	_stat_clock = _label("1:30", 20, TEXT)
	_stat_clock.autowrap_mode = TextServer.AUTOWRAP_OFF
	_stat_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_stat_clock)
	_stat_shots = _label("", 13, MUTED)
	v.add_child(_stat_shots)
	_stat_best = _label("", 12, MUTED)
	v.add_child(_stat_best)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(row)
	for i in range(POSITION_LABELS.size()):
		var b := _button(POSITION_LABELS[i], func() -> void: position_requested.emit(i), false, 28, 13)
		b.tooltip_text = POSITION_TIPS[i]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		row.add_child(b)
		_position_buttons.append(b)
	_position_label = _label("", 12, GOLD)
	v.add_child(_position_label)


func _build_power_panel() -> void:
	var panel := _panel(10.0)
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.offset_left = -210
	panel.offset_right = 210
	panel.offset_top = -84
	panel.offset_bottom = -14
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	var v := _vbox(4)
	panel.add_child(v)
	_power_text = _label("", 14, TEXT, true)
	v.add_child(_power_text)
	_power = ProgressBar.new()
	_power.min_value = 0
	_power.max_value = 100
	_power.show_percentage = false
	_power.custom_minimum_size.y = 10
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.12)
	bg.set_corner_radius_all(5)
	var fill := StyleBoxFlat.new()
	fill.bg_color = GOLD
	fill.set_corner_radius_all(5)
	_power.add_theme_stylebox_override("background", bg)
	_power.add_theme_stylebox_override("fill", fill)
	_power.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_power)
	_hint = _label("LPM – siła  •  PPM – anuluj  •  1–5 pozycje  •  TAB – kursor  •  ESC – pauza", 11, MUTED, true)
	v.add_child(_hint)


func _build_lab_panel(physics: Dictionary) -> void:
	_lab_panel = _panel(12.0)
	_lab_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_lab_panel.offset_left = -278
	_lab_panel.offset_right = -14
	_lab_panel.offset_top = 14
	root.add_child(_lab_panel)
	var outer := _vbox(6)
	_lab_panel.add_child(outer)
	_lab_toggle = _button("LABORATORIUM   ▾   [L]", toggle_lab_panel, false, 30, 13)
	outer.add_child(_lab_toggle)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(240, 470)
	outer.add_child(scroll)
	_lab_body = scroll
	var v := _vbox(3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)

	var presets := OptionButton.new()
	presets.focus_mode = Control.FOCUS_NONE
	for item in ["Ziemia  •  9,81 m/s²", "Księżyc  •  1,62 m/s²", "Mars  •  3,71 m/s²", "Jowisz  •  24,79 m/s²", "Własna wartość"]:
		presets.add_item(item)
	v.add_child(presets)
	var gravity := _slider_row(v, "Grawitacja", " m/s²", 0.5, 25.0, 0.01, float(physics["gravity"]), func(x: float) -> void: lab_changed.emit("gravity", x))
	presets.item_selected.connect(func(index: int) -> void:
		var values := [9.81, 1.62, 3.71, 24.79]
		if index < values.size():
			gravity.value = values[index]
	)
	_slider_row(v, "Sprężystość nawierzchni", "", 0.2, 0.98, 0.01, float(physics["bounce"]), func(x: float) -> void:
		_update_rebound(x)
		lab_changed.emit("bounce", x))
	_lab_rebound = _label("", 11, MUTED)
	v.add_child(_lab_rebound)
	_update_rebound(float(physics["bounce"]))
	_slider_row(v, "Masa piłki", " kg", 0.3, 1.2, 0.01, float(physics["mass"]), func(x: float) -> void: lab_changed.emit("mass", x))
	_slider_row(v, "Rotacja wsteczna", " rad/s", -30.0, 30.0, 0.5, float(physics["spin"]), func(x: float) -> void: lab_changed.emit("spin", x), 1)
	var magnus := CheckButton.new()
	magnus.text = "Efekt Magnusa"
	magnus.focus_mode = Control.FOCUS_NONE
	magnus.add_theme_font_size_override("font_size", 13)
	magnus.button_pressed = bool(physics["magnus"])
	magnus.toggled.connect(func(on: bool) -> void: lab_changed.emit("magnus", 1.0 if on else 0.0))
	v.add_child(magnus)
	_slider_row(v, "Wiatr boczny (X)", " m/s", -10.0, 10.0, 0.25, float(physics["wind"]), func(x: float) -> void: lab_changed.emit("wind", x))
	_slider_row(v, "Wiatr czołowy (Z)", " m/s", -10.0, 10.0, 0.25, float(physics["wind_z"]), func(x: float) -> void: lab_changed.emit("wind_z", x))
	_slider_row(v, "Wsp. oporu Cd", "", 0.0, 1.2, 0.01, float(physics["drag"]), func(x: float) -> void: lab_changed.emit("drag", x))
	v.add_child(_button("PRZYWRÓĆ ZIEMSKIE", func() -> void: lab_changed.emit("reset", 0.0), false, 30, 13))
	v.add_child(HSeparator.new())
	_lab_ideal = _label("", 13, GOLD)
	v.add_child(_lab_ideal)
	_lab_last = _label("Ostatni rzut: –", 12, MUTED)
	v.add_child(_lab_last)


## Godot's contact solver loses ~3% of the bounce value (measured: 0.79 -> e = 0.767).
func _update_rebound(elasticity: float) -> void:
	if is_instance_valid(_lab_rebound):
		var e := elasticity * 0.971
		_lab_rebound.text = "Piłka puszczona z 1,8 m odbije się na ok. %.2f m (FIBA: 1,2–1,4 m do góry piłki), e = %.2f" % [1.8 * e * e + 0.24, e]


func toggle_lab_panel() -> void:
	if not is_instance_valid(_lab_panel):
		return
	_lab_body.visible = not _lab_body.visible
	_lab_toggle.text = "LABORATORIUM   %s   [L]" % ("▾" if _lab_body.visible else "▸")


func update_hud(score: int, shots: int, hits: int, time_left: float, best: int, position_index: int, position_name: String) -> void:
	if not is_instance_valid(_stat_score):
		return
	_stat_score.text = "%d PKT" % score
	var seconds := int(ceil(time_left))
	_stat_clock.text = "∞" if _game_lab else "%d:%02d" % [seconds / 60, seconds % 60]
	_stat_clock.add_theme_color_override("font_color", GOLD if (not _game_lab and time_left < 10.0) else TEXT)
	_stat_shots.text = "Rzuty %d  •  trafienia %d  •  %.0f%%" % [shots, hits, 100.0 * float(hits) / float(maxi(shots, 1))]
	_stat_best.text = "Rekord %d pkt" % best
	_position_label.text = position_name
	for i in range(_position_buttons.size()):
		_position_buttons[i].set_pressed_no_signal(i == position_index)


func update_aim(charge: float, speed: float, angle_degrees: float, charging: bool) -> void:
	if not is_instance_valid(_power):
		return
	_power.value = charge * 100.0 if charging else 0.0
	if charging:
		_power_text.text = "SIŁA %.0f%%   •   %.1f m/s   •   kąt %.0f°" % [charge * 100.0, speed, angle_degrees]
	else:
		_power_text.text = "Przytrzymaj LPM   •   kąt wyrzutu %.0f°" % angle_degrees
	if is_instance_valid(_crosshair) and _crosshair.charging != charging:
		_crosshair.charging = charging
		_crosshair.queue_redraw()


func update_lab(ideal_speed: float, angle_degrees: float, last_shot: Dictionary) -> void:
	if not is_instance_valid(_lab_ideal):
		return
	_lab_ideal.text = "Idealna prędkość: %.2f m/s (kąt %.0f°)" % [ideal_speed, angle_degrees] if ideal_speed > 0.0 else "Idealna prędkość: poza zasięgiem"
	if not last_shot.is_empty():
		_lab_last.text = "Ostatni rzut: v₀ %.2f m/s, kąt %.0f°, h_max %.2f m, lot do 1. kontaktu %.2f s" % [
			last_shot["speed"], last_shot["angle"], last_shot["apex"], last_shot["flight"]]


func set_cursor_free(free: bool) -> void:
	if is_instance_valid(_cursor_hint):
		_cursor_hint.visible = free
	if is_instance_valid(_crosshair):
		_crosshair.visible = not free


func show_feedback(message: String, positive: bool = true) -> void:
	if is_instance_valid(_status):
		_status.text = message
		_status.add_theme_color_override("font_color", GOLD if positive else MUTED)


# --- pause and results -------------------------------------------------------

func show_pause() -> void:
	if is_instance_valid(_pause_overlay):
		return
	if is_instance_valid(_cursor_hint):
		_cursor_hint.visible = false
	_pause_overlay = Control.new()
	_pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_pause_overlay)
	var tint := ColorRect.new()
	tint.color = Color(0.01, 0.02, 0.04, 0.6)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.add_child(tint)
	var v := _center_panel(420, _pause_overlay)
	v.add_child(_label("PAUZA", 32, TEAL, true))
	v.add_child(_button("WZNÓW", func() -> void: resume_requested.emit(), true))
	v.add_child(_button("RESTART", func() -> void: restart_requested.emit()))
	_settings_controls(v)
	v.add_child(_button("MENU GŁÓWNE", func() -> void: menu_requested.emit()))
	v.add_child(_label("ESC – powrót do gry", 12, MUTED, true))


func hide_pause() -> void:
	if is_instance_valid(_pause_overlay):
		_pause_overlay.queue_free()
		_pause_overlay = null


func show_results(score: int, shots: int, hits: int, best: int, is_record: bool) -> void:
	_clear()
	_background(0.5)
	var v := _center_panel(440)
	v.add_child(_label("KONIEC CZASU", 30, TEAL, true))
	v.add_child(_label("%d PKT" % score, 56, GOLD, true))
	if is_record:
		v.add_child(_label("NOWY REKORD!", 20, GOLD, true))
	v.add_child(_label("Rzuty: %d   •   trafienia: %d   •   skuteczność: %.1f%%" % [shots, hits, 100.0 * float(hits) / float(maxi(shots, 1))], 16, TEXT, true))
	v.add_child(_label("Najlepszy wynik: %d pkt" % best, 15, GOLD, true))
	v.add_child(_button("ZAGRAJ PONOWNIE", func() -> void: restart_requested.emit(), true))
	v.add_child(_button("MENU GŁÓWNE", func() -> void: menu_requested.emit()))
