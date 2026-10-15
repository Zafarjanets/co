class_name Menus
extends CanvasLayer
## Start menu, pause, settings, controls, garage, mission result and arrest
## screens. Every button here does something real.

const ACCENT := Color("2a9d93")
const DARK := Color(0.07, 0.08, 0.1, 0.92)

var main: Main
var _dim: ColorRect
var _panel: PanelContainer
var _box: VBoxContainer
var _screen := ""
var _stack: Array[String] = []
var _result: PanelContainer
var _result_title: Label
var _result_text: Label
var _theme: Theme


func setup(m: Main) -> void:
	main = m
	name = "Menus"
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_theme = _make_theme()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = _theme
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_dim = ColorRect.new()
	_dim.color = Color(0.03, 0.05, 0.08, 0.55)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_dim)
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(560, 0)
	root.add_child(_panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 10)
	_panel.add_child(_box)
	# Mission result banner (does not pause the game).
	_result = PanelContainer.new()
	_result.anchor_left = 0.5
	_result.anchor_right = 0.5
	_result.offset_left = -300
	_result.offset_right = 300
	_result.offset_top = 210
	_result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_result)
	var rb := VBoxContainer.new()
	_result.add_child(rb)
	_result_title = _title_label("", 40)
	rb.add_child(_result_title)
	_result_text = Label.new()
	_result_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rb.add_child(_result_text)
	_result.visible = false
	main.missions.finished.connect(_on_mission_finished)
	main.police.busted.connect(_on_busted)
	_hide()


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 22
	var panel := StyleBoxFlat.new()
	panel.bg_color = DARK
	panel.set_corner_radius_all(16)
	panel.set_content_margin_all(28)
	panel.border_color = ACCENT
	panel.border_width_top = 4
	t.set_stylebox("panel", "PanelContainer", panel)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var b := StyleBoxFlat.new()
		b.set_corner_radius_all(10)
		b.set_content_margin_all(12)
		match state:
			"normal":
				b.bg_color = Color(1, 1, 1, 0.08)
			"hover":
				b.bg_color = ACCENT
			"pressed":
				b.bg_color = ACCENT.darkened(0.25)
			"disabled":
				b.bg_color = Color(1, 1, 1, 0.03)
			"focus":
				b.bg_color = Color(0, 0, 0, 0)
				b.border_color = ACCENT.lightened(0.3)
				b.set_border_width_all(2)
		t.set_stylebox(state, "Button", b)
	t.set_color("font_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.35))
	t.set_color("font_color", "Label", Color("e9ecf0"))
	t.set_font_size("font_size", "Button", 22)
	return t


func is_open() -> bool:
	return _screen != ""


func _hide() -> void:
	_screen = ""
	_stack.clear()
	_dim.visible = false
	_panel.visible = false


func _clear() -> void:
	for c in _box.get_children():
		c.queue_free()


func _open(screen: String, push := true) -> void:
	if push and _screen != "" and _screen != screen:
		_stack.append(_screen)
	_screen = screen
	_dim.visible = true
	_panel.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_clear()


func _close_all() -> void:
	_hide()
	get_tree().paused = false
	if main.playing:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Esc inside menus.
func back() -> void:
	Sfx.click()
	if _screen == "main":
		return
	if _stack.is_empty():
		_close_all()
		return
	var prev: String = _stack.pop_back()
	_show(prev, false)


func _show(screen: String, push := true) -> void:
	match screen:
		"main": show_main()
		"pause": show_pause()
		"settings": show_settings(push)
		"controls": show_controls(push)
		"garage": show_garage()
		_: _close_all()


# --- widgets -------------------------------------------------------------------------

func _title_label(text: String, size := 52) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var ls := LabelSettings.new()
	ls.font_size = size
	ls.font_color = Color.WHITE
	ls.outline_size = 8
	ls.outline_color = Color(0, 0, 0, 0.6)
	l.label_settings = ls
	return l


func _text(text: String, size := 20, col := Color("c9ced6")) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _button(text: String, cb: Callable, parent: Control = null) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func():
		Sfx.click()
		cb.call())
	(parent if parent else _box).add_child(b)
	return b


# --- screens ----------------------------------------------------------------------------

func show_main() -> void:
	_stack.clear()
	_open("main", false)
	_box.add_child(_title_label("РАЙОН", 84))
	var sub := _text("R A Y O N  ·  открытый район, дрифт и погони", 20, Color("8fd8d0"))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(sub)
	_box.add_child(HSeparator.new())
	_button("Продолжить" if main.playing else "Играть", func():
		if not main.playing:
			main.start_game()
		_close_all())
	_button("Настройки", func(): show_settings())
	_button("Управление", func(): show_controls())
	_button("Сбросить прогресс", func(): _confirm_reset())
	_button("Выход", func(): get_tree().quit())
	var info := _text("Деньги: $%d   ·   Машина: %s" % [Game.money(), Game.selected_car().to_upper()], 18)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(info)


func show_pause() -> void:
	_stack.clear()
	_open("pause", false)
	_box.add_child(_title_label("ПАУЗА", 56))
	_button("Продолжить", func(): _close_all())
	_button("Настройки", func(): show_settings())
	_button("Управление", func(): show_controls())
	if main.missions.is_running():
		_button("Отменить задание", func():
			main.missions.cancel()
			_close_all())
	_button("Главное меню", func(): show_main())


func show_settings(push := true) -> void:
	_open("settings", push)
	_box.add_child(_title_label("НАСТРОЙКИ", 44))
	# Volume.
	_box.add_child(_text("Громкость", 20, Color.WHITE))
	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value = Game.setting("volume")
	vol.custom_minimum_size = Vector2(0, 28)
	vol.value_changed.connect(func(v): Game.set_setting("volume", v))
	_box.add_child(vol)
	# Quality.
	_box.add_child(_text("Качество графики", 20, Color.WHITE))
	var q := OptionButton.new()
	q.add_item("Низкое — без теней и контуров, меньше машин", 0)
	q.add_item("Среднее", 1)
	q.add_item("Высокое", 2)
	q.selected = Game.setting("quality")
	q.item_selected.connect(func(i): Game.set_setting("quality", i))
	_box.add_child(q)
	# Mouse.
	_box.add_child(_text("Чувствительность мыши", 20, Color.WHITE))
	var sens := HSlider.new()
	sens.min_value = 0.2
	sens.max_value = 3.0
	sens.step = 0.1
	sens.value = Game.setting("sensitivity")
	sens.custom_minimum_size = Vector2(0, 28)
	sens.value_changed.connect(func(v): Game.set_setting("sensitivity", v))
	_box.add_child(sens)
	var inv := CheckBox.new()
	inv.text = "Инвертировать ось Y"
	inv.button_pressed = Game.setting("invert_y")
	inv.toggled.connect(func(on): Game.set_setting("invert_y", on))
	_box.add_child(inv)
	_button("Назад", func(): back())


func show_controls(push := true) -> void:
	_open("controls", push)
	_box.add_child(_title_label("УПРАВЛЕНИЕ", 44))
	var rows := [
		["W A S D", "движение / газ, тормоз, руль"], ["Мышь", "обзор (клик — захватить мышь)"],
		["Shift", "бег"], ["Пробел", "ручной тормоз (дрифт)"], ["E", "сесть / выйти / начать задание / гараж"],
		["R", "поставить застрявшую машину на дорогу"], ["Enter", "повторить задание после результата"],
		["H", "сигнал"], ["Esc", "пауза"], ["F3", "счётчик FPS"],
	]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	for r in rows:
		grid.add_child(_text(r[0], 20, Color("8fd8d0")))
		grid.add_child(_text(r[1], 20))
	_box.add_child(grid)
	_box.add_child(_text("Задания отмечены цветными кольцами на карте. Гараж (G) — у проспекта: заезжайте внутрь на своей машине и нажмите E.", 17))
	_button("Назад", func(): back())


func _confirm_reset() -> void:
	_open("confirm")
	_box.add_child(_title_label("СБРОС", 44))
	_box.add_child(_text("Удалить деньги, улучшения и выбор машины? Настройки останутся.", 20))
	_button("Да, сбросить", func():
		Game.reset_progress()
		main.hud.toast("Прогресс сброшен", 2.0)
		show_main())
	_button("Отмена", func(): back())


# --- garage --------------------------------------------------------------------------------

func show_garage() -> void:
	_open("garage", _screen != "garage")
	var kind := Game.selected_car()
	var setup := Game.car_setup(kind)
	_box.add_child(_title_label("ГАРАЖ", 48))
	_box.add_child(_text("Деньги: $%d" % Game.money(), 24, Color("9be37a")))
	# Car choice.
	var cars := HBoxContainer.new()
	cars.add_theme_constant_override("separation", 10)
	_box.add_child(cars)
	for k in Game.CIVIL_CARS:
		var desc := "SADO — седан, задний привод" if k == "sado" else "CHABUK — хэтчбек, передний привод"
		var b := _button(("✔ " if k == kind else "") + desc, func():
			Game.select_car(k)
			show_garage(), cars)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Stats.
	var spec: Dictionary = Car.SPECS[kind]
	var eng := 1.0 + 0.14 * int(setup["engine"])
	var grp := 1.0 + 0.08 * int(setup["grip"])
	_box.add_child(_text("Мощность: %d Н · Макс. скорость: %d км/ч · Сцепление: %.2f" % [
		int(spec["engine"] * eng), int(spec["max_speed"] * (1.0 + 0.04 * int(setup["engine"])) * 3.6), spec["grip_r"] * grp], 18))
	# Paint.
	_box.add_child(_text("Покраска — $%d" % Game.PRICE_PAINT, 20, Color.WHITE))
	var paints := HBoxContainer.new()
	paints.add_theme_constant_override("separation", 6)
	_box.add_child(paints)
	for i in Game.PAINTS.size():
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(48, 40)
		sw.tooltip_text = Game.PAINTS[i][0]
		var sb := StyleBoxFlat.new()
		sb.bg_color = Game.PAINTS[i][1]
		sb.set_corner_radius_all(8)
		if i == setup["paint"]:
			sb.set_border_width_all(4)
			sb.border_color = Color.WHITE
		for st in ["normal", "hover", "pressed"]:
			sw.add_theme_stylebox_override(st, sb)
		var idx := i
		sw.pressed.connect(func():
			if idx == Game.car_setup(kind)["paint"]:
				return
			if Game.spend(Game.PRICE_PAINT):
				Game.set_car_value(kind, "paint", idx)
				Sfx.ui_ok()
			else:
				_no_money()
			show_garage())
		paints.add_child(sw)
	# Rims.
	_box.add_child(_text("Диски — $%d" % Game.PRICE_RIMS, 20, Color.WHITE))
	var rims := HBoxContainer.new()
	rims.add_theme_constant_override("separation", 10)
	_box.add_child(rims)
	for r in Game.RIMS:
		var rid: String = r[0]
		var b2 := _button(("✔ " if setup["rims"] == rid else "") + r[1], func():
			if Game.car_setup(kind)["rims"] == rid:
				return
			if Game.spend(Game.PRICE_RIMS):
				Game.set_car_value(kind, "rims", rid)
				Sfx.ui_ok()
			else:
				_no_money()
			show_garage(), rims)
		b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Upgrades.
	_upgrade_row(kind, "engine", "Двигатель", Game.PRICE_ENGINE, "+14% мощности, +4% скорости")
	_upgrade_row(kind, "grip", "Сцепление шин", Game.PRICE_GRIP, "+8% сцепления")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_box.add_child(row)
	var go := _button("Выехать", func(): _close_all(), row)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if main.player.car:
		var out := _button("Выйти из машины", func():
			_close_all()
			main._try_exit(main.player.car), row)
		out.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _upgrade_row(kind: String, key: String, title: String, prices: Array, effect: String) -> void:
	var lvl: int = Game.car_setup(kind)[key]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_box.add_child(row)
	var l := _text("%s: ур. %d/%d  (%s за уровень)" % [title, lvl, prices.size(), effect], 19, Color.WHITE)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	if lvl >= prices.size():
		var maxed := Button.new()
		maxed.text = "Максимум"
		maxed.disabled = true
		row.add_child(maxed)
		return
	var price: int = prices[lvl]
	var b := _button("Купить $%d" % price, func():
		if Game.spend(price):
			Game.set_car_value(kind, key, lvl + 1)
			Sfx.ui_ok()
			main.hud.toast("%s улучшен до уровня %d" % [title, lvl + 1], 2.0)
		else:
			_no_money()
		show_garage(), row)
	b.disabled = Game.money() < price


func _no_money() -> void:
	Sfx.ui_fail()
	main.hud.toast("Недостаточно денег — выполните задание", 2.0)


# --- results -------------------------------------------------------------------------------

func _on_mission_finished(id: String, success: bool, text: String) -> void:
	var title: String = Missions.DEFS[id]["title"]
	_result_title.text = ("ПОБЕДА · " if success else "ПРОВАЛ · ") + title
	_result_title.label_settings.font_color = Color("6be36b") if success else Color("ff5a5a")
	_result_text.text = text + "\nEnter — повторить задание"
	_result.visible = true
	var tw := create_tween()
	tw.tween_interval(7.5)
	tw.tween_callback(func(): _result.visible = false)


func _process(_delta: float) -> void:
	if _result.visible and main.missions.is_running():
		_result.visible = false


func _on_busted(fine_amount: int) -> void:
	main.respawn_at_garage()
	_open("busted", false)
	_box.add_child(_title_label("ЗАДЕРЖАН", 56))
	_box.add_child(_text("Полиция задержала вас. Штраф: $%d.\nВас отпустили у гаража." % fine_amount, 22, Color.WHITE))
	_button("Продолжить", func(): _close_all())
