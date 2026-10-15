class_name Missions
extends Node3D
## The three jobs of the district.
##   delivery – take a client's car to an address before the timer runs out
##   ring     – lap the ring road through checkpoints under the time limit
##   escape   – get a wanted level and lose the police
## Each run: start at the marker (E) → goal → win / fail → retry (Enter).
## The reward is paid once per successful attempt.

signal finished(id: String, success: bool, text: String)

const START_RADIUS := 6.0
const DEFS := {
	"delivery": {"title": "Доставка", "reward": 600, "color": Color("ffb43c"),
		"start": Vector3(-112.0, CityLayout.CURB_H, 16.0)},
	"ring": {"title": "Кольцо", "reward": 800, "color": Color("3cc8ff"),
		"start": Vector3(-260.0, 0.0, 70.0)},
	"escape": {"title": "Оторвись", "reward": 1000, "color": Color("ff4b5c"),
		"start": Vector3(195.0, 0.0, -40.0)},
}
const DELIVERY_CAR_POS := Vector3(-116.0, CityLayout.CURB_H + 0.45, 30.0)
const DELIVERY_DEST := Vector3(195.0, 0.0, 127.0)
const DELIVERY_TIME := 62.0
const RING_TIME := 112.0
const RING_POINTS := [
	Vector3(-260, 0, -60), Vector3(-260, 0, -200), Vector3(-200, 0, -260), Vector3(-60, 0, -260),
	Vector3(60, 0, -260), Vector3(200, 0, -260), Vector3(260, 0, -200), Vector3(260, 0, -60),
	Vector3(260, 0, 60), Vector3(260, 0, 200), Vector3(200, 0, 260), Vector3(60, 0, 260),
	Vector3(-60, 0, 260), Vector3(-200, 0, 260), Vector3(-260, 0, 200), Vector3(-260, 0, 70),
]

var main: Main
var active := ""                 # running mission id
var phase := ""
var timer := 0.0
var elapsed := 0.0
var checkpoint := 0
var last_id := ""                # for retry
var result_timer := 0.0
var client_car: Car = null
var _awarded := false
var _away := 0.0
var _start_markers := {}
var _goal: Node3D
var _goal_label: Label3D


func setup(m: Main) -> void:
	main = m
	name = "Missions"
	for id in DEFS:
		var mk := _marker(DEFS[id]["color"], 3.0, DEFS[id]["title"] + "\n$%d" % DEFS[id]["reward"])
		mk.position = DEFS[id]["start"]
		add_child(mk)
		_start_markers[id] = mk
	_goal = _marker(Color("ffe14d"), 6.0, "")
	_goal.visible = false
	add_child(_goal)
	_goal_label = _goal.get_node("Label")
	main.police.busted.connect(_on_busted)
	main.police.escaped.connect(_on_escaped)


func _marker(col: Color, radius: float, text: String) -> Node3D:
	var root := Node3D.new()
	var ring := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.25
	cyl.radial_segments = 24
	ring.mesh = cyl
	ring.material_override = Mats.marker(Color(col.r, col.g, col.b, 0.45))
	ring.position.y = 0.15
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.name = "Ring"
	root.add_child(ring)
	var beam := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = radius * 0.92
	bm.bottom_radius = radius
	bm.height = 6.0
	bm.radial_segments = 24
	bm.cap_top = false
	bm.cap_bottom = false
	beam.mesh = bm
	beam.material_override = Mats.marker(Color(col.r, col.g, col.b, 0.16))
	beam.position.y = 3.0
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.name = "Beam"
	root.add_child(beam)
	var l := Label3D.new()
	l.name = "Label"
	l.text = text
	l.font_size = 72
	l.pixel_size = 0.012
	l.outline_size = 14
	l.modulate = Color.WHITE
	l.outline_modulate = Color(col.darkened(0.5), 1.0)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = false
	l.position.y = 4.2
	root.add_child(l)
	return root


func is_running() -> bool:
	return active != ""


## Text for the on-screen hint when standing in a start marker.
func prompt_text() -> String:
	if active != "":
		return ""
	var p := main.focus_position()
	for id in DEFS:
		var s: Vector3 = DEFS[id]["start"]
		if Vector2(p.x - s.x, p.z - s.z).length() < START_RADIUS:
			if id == "ring" and main.player.car == null:
				return "Кольцо: подъезжайте на машине"
			return "E — начать задание «%s» (награда $%d)" % [DEFS[id]["title"], DEFS[id]["reward"]]
	return ""


## Handle E. Returns true if a mission started.
func interact() -> bool:
	if active != "" or prompt_text() == "" or prompt_text().begins_with("Кольцо:"):
		return false
	var p := main.focus_position()
	for id in DEFS:
		var s: Vector3 = DEFS[id]["start"]
		if Vector2(p.x - s.x, p.z - s.z).length() < START_RADIUS:
			start(id)
			return true
	return false


func start(id: String) -> void:
	active = id
	last_id = id
	_awarded = false
	elapsed = 0.0
	result_timer = 0.0
	_away = 0.0
	for k in _start_markers:
		_start_markers[k].visible = false
	match id:
		"delivery":
			phase = "board"
			timer = 30.0
			if client_car and is_instance_valid(client_car) and client_car != main.player.car:
				main.remove_car(client_car)
			client_car = main.spawn_car("chabuk", Transform3D(Basis.IDENTITY, DELIVERY_CAR_POS), {"paint": Color("7a4fb5"), "rims": "sport"})
			client_car.set_meta("client", true)
			_show_goal(client_car.global_position, "Машина клиента", 3.0)
			main.hud.toast("Клиент ждёт: сядьте в фиолетовый CHABUK", 3.0)
		"ring":
			phase = "race"
			checkpoint = 0
			timer = RING_TIME
			_show_goal(RING_POINTS[0], "1 / %d" % RING_POINTS.size(), 9.0)
			main.hud.toast("Кольцо! Проходите контрольные точки по порядку", 3.0)
		"escape":
			phase = "escape"
			timer = 0.0
			main.police.force_wanted(2)
			_goal.visible = false
			main.hud.toast("Полиция ищет вас! Оторвитесь от погони", 3.0)
	Sfx.ui_ok()


func _show_goal(pos: Vector3, text: String, radius: float) -> void:
	_goal.visible = true
	_goal.position = pos
	_goal_label.text = text
	var ring: MeshInstance3D = _goal.get_node("Ring")
	(ring.mesh as CylinderMesh).top_radius = radius
	(ring.mesh as CylinderMesh).bottom_radius = radius
	var beam: MeshInstance3D = _goal.get_node("Beam")
	(beam.mesh as CylinderMesh).top_radius = radius * 0.92
	(beam.mesh as CylinderMesh).bottom_radius = radius


func objective() -> String:
	match active:
		"delivery":
			if phase == "board":
				return "Сядьте в машину клиента (фиолетовый CHABUK)"
			return "Доставьте машину клиента к отмеченной точке"
		"ring":
			return "Кольцо: точка %d из %d" % [checkpoint + 1, RING_POINTS.size()]
		"escape":
			if main.police.stars > 0:
				return "Оторвитесь от полиции" + (" — прячьтесь! %.0f с" % main.police.search_left() if main.police.state == Police.State.SEARCH else "")
			return "Оторвитесь от полиции"
	return ""


func time_left() -> float:
	if active == "delivery" or active == "ring":
		return timer
	return -1.0


## Points for the minimap: [{pos, color}]
func map_points() -> Array:
	var out: Array = []
	if active == "":
		for id in DEFS:
			out.append({"pos": DEFS[id]["start"], "color": DEFS[id]["color"]})
	elif _goal.visible:
		out.append({"pos": _goal.position, "color": Color("ffe14d")})
	return out


func _process(delta: float) -> void:
	if result_timer > 0.0:
		result_timer -= delta
	# Gentle pulse for markers.
	var s := 1.0 + sin(Time.get_ticks_msec() / 300.0) * 0.04
	for k in _start_markers:
		_start_markers[k].get_node("Beam").scale = Vector3(s, 1, s)
	if _goal.visible and active == "delivery" and phase == "board" and client_car and is_instance_valid(client_car):
		_goal.position = client_car.global_position
	if active == "" or get_tree().paused:
		return
	elapsed += delta
	match active:
		"delivery":
			_update_delivery(delta)
		"ring":
			_update_ring(delta)


func _update_delivery(delta: float) -> void:
	if client_car == null or not is_instance_valid(client_car):
		_fail("Машина клиента потеряна")
		return
	timer -= delta
	if phase == "board":
		if main.player.car == client_car:
			phase = "drive"
			timer = DELIVERY_TIME
			_show_goal(DELIVERY_DEST, "Адрес клиента", 6.0)
			main.hud.toast("Везите машину по адресу! Время пошло", 2.5)
		elif timer <= 0.0:
			_fail("Клиент не дождался")
		return
	if main.player.car != client_car:
		_away += delta
		if _away > 15.0:
			_fail("Вы бросили машину клиента")
			return
	else:
		_away = 0.0
	if timer <= 0.0:
		_fail("Время вышло")
		return
	var d := client_car.global_position
	if Vector2(d.x - DELIVERY_DEST.x, d.z - DELIVERY_DEST.z).length() < 7.0 and client_car.linear_velocity.length() < 3.0:
		_succeed("Машина доставлена! Осталось %.0f с" % timer)


func _update_ring(delta: float) -> void:
	timer -= delta
	if timer <= 0.0:
		_fail("Время вышло")
		return
	var c := main.player.car
	if c == null:
		_away += delta
		if _away > 10.0:
			_fail("Нужно ехать на машине")
		return
	_away = 0.0
	var cp: Vector3 = RING_POINTS[checkpoint]
	var p := c.global_position
	if Vector2(p.x - cp.x, p.z - cp.z).length() < 10.0:
		checkpoint += 1
		Sfx.checkpoint()
		if checkpoint >= RING_POINTS.size():
			var t := elapsed
			var best: float = Game.data["stats"].get("best_ring", 0.0)
			if best <= 0.0 or t < best:
				Game.data["stats"]["best_ring"] = t
			_succeed("Круг за %.1f с" % t)
			return
		_show_goal(RING_POINTS[checkpoint], "%d / %d" % [checkpoint + 1, RING_POINTS.size()], 9.0)


func _on_escaped() -> void:
	if active == "escape":
		_succeed("Вы оторвались от полиции за %.0f с" % elapsed)


func _on_busted(_fine: int) -> void:
	if active != "":
		_fail("Вас задержали")


func _succeed(text: String) -> void:
	var id := active
	var reward: int = DEFS[id]["reward"]
	if not _awarded:
		_awarded = true
		Game.add_money(reward)
		Game.mission_done(id)
	_end()
	result_timer = 8.0
	Sfx.ui_ok()
	finished.emit(id, true, "%s\nНаграда: $%d" % [text, reward])


func _fail(text: String) -> void:
	var id := active
	_end()
	result_timer = 8.0
	Sfx.ui_fail()
	finished.emit(id, false, text)


func _end() -> void:
	active = ""
	phase = ""
	_goal.visible = false
	for k in _start_markers:
		_start_markers[k].visible = true
	if client_car and is_instance_valid(client_car):
		client_car.remove_meta("client")
		client_car.set_meta("parked", true)


## Called from the pause menu.
func cancel() -> void:
	if active == "":
		return
	_fail("Задание отменено")


## Enter: replay the last mission from its start point.
func retry() -> void:
	if active != "" or last_id == "" or result_timer <= 0.0:
		return
	var id := last_id
	var start_pos: Vector3 = DEFS[id]["start"]
	result_timer = 0.0
	if main.police.stars > 0 and id != "escape":
		main.police.clear_wanted()
	match id:
		"ring":
			var c := main.player.car if main.player.car else main.my_car
			if c == null or not is_instance_valid(c):
				return
			if main.player.car == null:
				main._enter_car(c)
			# Face north along the west ring road, just behind the start.
			c.place(Transform3D(Basis.IDENTITY, Vector3(-257.0, 0.6, 80.0)))
			main.rig.follow(c, true)
		"delivery":
			var car := main.player.car
			if car:
				car.set_controls(0.0, 0.0, 0.0, true)
				car.driver = ""
				main.player.exit_to(start_pos + Vector3(1, 0.1, 1), 0.0)
				main.rig.follow(main.player, false)
				if car != client_car:
					# Bring the hero's own car along so it isn't left across the map.
					car.place(Transform3D(Basis.IDENTITY, start_pos + Vector3(-8, 0.5, 8)))
			else:
				main.player.teleport(start_pos + Vector3(1, 0.1, 1), 0.0)
		"escape":
			if main.player.car:
				main.player.car.place(Transform3D(Basis.IDENTITY, start_pos + Vector3(0, 0.6, 0)))
			else:
				main.player.teleport(start_pos + Vector3(0, 0.1, 0), 0.0)
	start(id)
