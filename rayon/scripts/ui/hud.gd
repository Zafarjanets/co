class_name Hud
extends CanvasLayer
## Minimal HUD: minimap, speed, money, wanted stars, current goal, hints.

var main: Main
var money_label: Label
var stars_label: Label
var state_label: Label
var goal_panel: PanelContainer
var goal_label: Label
var timer_label: Label
var speed_box: Control
var speed_label: Label
var unit_label: Label
var gear_label: Label
var speed_bar: ProgressBar
var prompt_label: Label
var toast_label: Label
var fps_label: Label
var minimap: Minimap
var _toast_time := 0.0
var _shown_money := 0.0


func setup(m: Main) -> void:
	main = m
	layer = 5
	name = "Hud"
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Money (top-left).
	var money_panel := _panel(Color(0.08, 0.09, 0.11, 0.72))
	money_panel.position = Vector2(24, 20)
	root.add_child(money_panel)
	money_label = _label("$ 0", 34, Color("9be37a"))
	money_panel.add_child(money_label)

	# Wanted (top-right).
	var wanted := VBoxContainer.new()
	wanted.anchor_left = 1.0
	wanted.anchor_right = 1.0
	wanted.offset_left = -260
	wanted.offset_right = -24
	wanted.offset_top = 16
	wanted.alignment = BoxContainer.ALIGNMENT_BEGIN
	wanted.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(wanted)
	stars_label = _label("☆☆☆", 46, Color("ffffff"))
	stars_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wanted.add_child(stars_label)
	state_label = _label("", 22, Color("ff5050"))
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wanted.add_child(state_label)

	# Goal (top-centre).
	goal_panel = _panel(Color(0.08, 0.09, 0.11, 0.72))
	goal_panel.anchor_left = 0.5
	goal_panel.anchor_right = 0.5
	goal_panel.offset_left = -330
	goal_panel.offset_right = 330
	goal_panel.offset_top = 18
	root.add_child(goal_panel)
	var gb := VBoxContainer.new()
	goal_panel.add_child(gb)
	goal_label = _label("", 22, Color.WHITE)
	goal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	goal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gb.add_child(goal_label)
	timer_label = _label("", 30, Color("ffe14d"))
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gb.add_child(timer_label)

	toast_label = _label("", 24, Color.WHITE)
	toast_label.anchor_left = 0.5
	toast_label.anchor_right = 0.5
	toast_label.offset_left = -420
	toast_label.offset_right = 420
	toast_label.offset_top = 150
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(toast_label)

	# Prompt (bottom-centre).
	prompt_label = _label("", 24, Color("ffffff"))
	prompt_label.anchor_left = 0.5
	prompt_label.anchor_right = 0.5
	prompt_label.anchor_top = 1.0
	prompt_label.anchor_bottom = 1.0
	prompt_label.offset_left = -400
	prompt_label.offset_right = 400
	prompt_label.offset_top = -150
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(prompt_label)

	# Minimap (bottom-left), clipped to a circle.
	var frame := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.12, 1.0)
	sb.set_corner_radius_all(130)
	sb.border_color = Color("1b1c1f")
	frame.add_theme_stylebox_override("panel", sb)
	frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	frame.anchor_top = 1.0
	frame.anchor_bottom = 1.0
	frame.offset_left = 24
	frame.offset_right = 284
	frame.offset_top = -284
	frame.offset_bottom = -24
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(frame)
	minimap = Minimap.new()
	minimap.main = m
	minimap.set_anchors_preset(Control.PRESET_FULL_RECT)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(minimap)
	var ring := Panel.new()
	var sb2 := StyleBoxFlat.new()
	sb2.draw_center = false
	sb2.set_corner_radius_all(134)
	sb2.set_border_width_all(5)
	sb2.border_color = Color("1b1c1f")
	ring.add_theme_stylebox_override("panel", sb2)
	ring.anchor_top = 1.0
	ring.anchor_bottom = 1.0
	ring.offset_left = 22
	ring.offset_right = 286
	ring.offset_top = -286
	ring.offset_bottom = -22
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(ring)

	# Speedometer (bottom-right).
	speed_box = Control.new()
	speed_box.anchor_left = 1.0
	speed_box.anchor_right = 1.0
	speed_box.anchor_top = 1.0
	speed_box.anchor_bottom = 1.0
	speed_box.offset_left = -330
	speed_box.offset_right = -24
	speed_box.offset_top = -150
	speed_box.offset_bottom = -24
	speed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(speed_box)
	var sp_bg := _panel(Color(0.08, 0.09, 0.11, 0.72))
	sp_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	speed_box.add_child(sp_bg)
	var spv := VBoxContainer.new()
	sp_bg.add_child(spv)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	spv.add_child(row)
	speed_label = _label("000", 64, Color.WHITE)
	row.add_child(speed_label)
	var unit_box := VBoxContainer.new()
	unit_box.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(unit_box)
	gear_label = _label("1", 22, Color("3cc8c0"))
	unit_box.add_child(gear_label)
	unit_label = _label("км/ч", 20, Color("c9ced6"))
	unit_box.add_child(unit_label)
	speed_bar = ProgressBar.new()
	speed_bar.show_percentage = false
	speed_bar.custom_minimum_size = Vector2(0, 8)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("3cc8c0")
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.15)
	speed_bar.add_theme_stylebox_override("fill", fill)
	speed_bar.add_theme_stylebox_override("background", bg)
	spv.add_child(speed_bar)

	fps_label = _label("", 16, Color("c9ced6"))
	fps_label.anchor_left = 0.5
	fps_label.anchor_right = 0.5
	fps_label.anchor_top = 1.0
	fps_label.anchor_bottom = 1.0
	fps_label.offset_top = -30
	fps_label.offset_left = -100
	fps_label.offset_right = 100
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fps_label.visible = false
	root.add_child(fps_label)

	_shown_money = Game.money()
	main.police.wanted_changed.connect(_on_wanted)
	_on_wanted(0, Police.State.NONE)
	set_speed(-1.0, 0)


func _panel(col: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.skew = Vector2(-0.12, 0)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font_size = size
	ls.font_color = col
	ls.outline_size = maxi(4, size / 6)
	ls.outline_color = Color(0.05, 0.05, 0.07, 0.9)
	l.label_settings = ls
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func set_speed(kmh: float, gear: int) -> void:
	speed_box.visible = kmh >= 0.0
	if kmh < 0.0:
		return
	speed_label.text = "%03d" % int(round(kmh))
	gear_label.text = "R" if gear < 0 else str(gear)
	speed_bar.value = clampf(kmh / 190.0 * 100.0, 0.0, 100.0)


func set_prompt(text: String) -> void:
	prompt_label.text = text


func toast(text: String, seconds := 2.0) -> void:
	toast_label.text = text
	_toast_time = seconds
	toast_label.modulate.a = 1.0


func _on_wanted(stars: int, state: int) -> void:
	var s := ""
	for i in 3:
		s += "★" if i < stars else "☆"
	stars_label.text = s
	stars_label.label_settings.font_color = Color("ffd23c") if stars > 0 else Color(1, 1, 1, 0.45)
	match state:
		Police.State.CHASE:
			state_label.label_settings.font_color = Color("ff4b4b")
		Police.State.SEARCH:
			state_label.label_settings.font_color = Color("ffa53c")
		Police.State.ESCAPED:
			state_label.label_settings.font_color = Color("6be36b")
	state_label.text = main.police.state_text()


func _process(delta: float) -> void:
	if main == null:
		return
	# Count money up/down smoothly.
	var target := float(Game.money())
	_shown_money = move_toward(_shown_money, target, maxf(absf(target - _shown_money) * delta * 4.0, 5.0))
	money_label.text = "$ %d" % int(round(_shown_money))
	# Goal and timers.
	var goal := main.missions.objective()
	goal_panel.visible = goal != ""
	goal_label.text = goal
	var tl := main.missions.time_left()
	timer_label.visible = tl >= 0.0
	if tl >= 0.0:
		timer_label.text = "%d:%02d" % [int(tl) / 60, int(tl) % 60]
		timer_label.label_settings.font_color = Color("ff5050") if tl < 10.0 else Color("ffe14d")
	if main.police.state == Police.State.SEARCH:
		state_label.text = "ПОИСК — %.0f с" % main.police.search_left()
	elif main.police.bust_timer > 0.2:
		state_label.text = "ЗАДЕРЖАНИЕ %.1f" % maxf(0.0, Police.BUST_TIME - main.police.bust_timer)
	elif state_label.text.begins_with("ЗАДЕРЖАНИЕ") or state_label.text.begins_with("ПОИСК"):
		state_label.text = main.police.state_text()
	# Toast fade.
	if _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time < 0.5:
			toast_label.modulate.a = maxf(0.0, _toast_time / 0.5)
	if fps_label.visible:
		fps_label.text = "FPS %d  |  машин %d" % [Engine.get_frames_per_second(), main.cars.size()]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F3:
		fps_label.visible = not fps_label.visible
