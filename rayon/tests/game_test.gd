extends Node
## End-to-end check of the real game scene. Run (with a display for shots):
##   godot --path . --rendering-driver opengl3 res://tests/game_test.tscn -- <shot_dir>
## Prints PASS/FAIL lines and a summary; exits with code 1 on failure.

var main: Main
var shots := ""
var passed := 0
var failed := 0
var _fails: Array[String] = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 else ""
	# Start from a clean save so the test is repeatable.
	Game.data = Game.default_data()
	Game.data["settings"]["volume"] = 0.0
	Game.save_game()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	_run.call_deferred()


func check(cond: bool, what: String) -> void:
	if cond:
		passed += 1
		print("PASS  ", what)
	else:
		failed += 1
		_fails.append(what)
		print("FAIL  ", what)


func wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, true).timeout


func shot(name: String) -> void:
	if shots == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [shots, name])


func hold(action: String, sec: float) -> void:
	Input.action_press(action)
	await wait(sec)
	Input.action_release(action)


func _run() -> void:
	await wait(0.5)
	main.menus._close_all()
	main.start_game()
	await wait(1.0)
	await shot("01_start")

	# --- on foot ----------------------------------------------------------
	var p0 := main.player.global_position
	main.rig.yaw = 0.0
	await hold("forward", 1.2)
	check(main.player.global_position.distance_to(p0) > 1.5, "hero walks forward")
	var p1 := main.player.global_position
	Input.action_press("run")
	await hold("forward", 1.0)
	Input.action_release("run")
	check(main.player.global_position.distance_to(p1) > 3.5, "hero runs (Shift) faster than walking")

	# --- enter / exit many times -------------------------------------------
	var car := main.my_car
	check(car != null and is_instance_valid(car), "personal car spawned at the garage")
	# Inside the garage E opens the garage menu, so roll the car onto the apron.
	car.place(Transform3D(Basis.IDENTITY, CityLayout.GARAGE_APRON + Vector3(0, 0.5, 0)))
	await wait(0.5)
	var ok_cycles := 0
	for i in 5:
		main.player.teleport(car.global_transform * Vector3(-1.8, 0.2, 0.0))
		await wait(0.2)
		main._interact()
		await wait(0.3)
		var entered := main.player.car == car and not main.player.visible
		main._interact()
		await wait(0.3)
		var exited := main.player.car == null and main.player.visible
		var outside := (car.global_transform.affine_inverse() * main.player.global_position).length() > 1.0
		if entered and exited and outside:
			ok_cycles += 1
	check(ok_cycles == 5, "enter/exit 5 times in a row (%d/5)" % ok_cycles)

	main.player.teleport(car.global_transform * Vector3(-1.8, 0.2, 0.0))
	await wait(0.2)
	main._interact()
	await wait(0.2)

	# --- driving -----------------------------------------------------------
	car.place(Transform3D(Basis(Vector3.UP, -PI / 2), Vector3(-200, 0.6, 6)))
	main.rig.follow(car, true)
	await wait(0.5)
	await hold("forward", 3.5)
	var kmh := car.speed_kmh()
	check(kmh > 50.0, "car accelerates (%.0f km/h after 3.5 s)" % kmh)
	await shot("02_driving")
	await hold("back", 2.5)
	check(car.speed_kmh() < 25.0, "car brakes")
	await hold("back", 1.5)
	check(car.forward_speed < -0.5, "car reverses")
	Input.action_release("back")
	await wait(1.0)

	# --- drift on the pad ---------------------------------------------------
	car.place(Transform3D(Basis.IDENTITY, Vector3(170, 0.6, -25)))
	await wait(0.4)
	Input.action_press("forward")
	await wait(2.6)
	Input.action_press("left")
	await wait(0.7)
	Input.action_press("handbrake")
	var max_slip := 0.0
	for i in 40:
		await get_tree().physics_frame
	Input.action_release("handbrake")
	for i in 120:
		await get_tree().physics_frame
		var v := car.linear_velocity
		v.y = 0
		if v.length() > 4.0:
			max_slip = maxf(max_slip, rad_to_deg(absf((-car.global_basis.z).signed_angle_to(v.normalized(), Vector3.UP))))
		if i == 30:
			await shot("03_drift")
	Input.action_release("left")
	Input.action_release("forward")
	check(max_slip > 15.0, "handbrake starts a drift (max slip %.0f°)" % max_slip)
	check(main.effects._next > 0, "tyre marks are laid while sliding (%d)" % main.effects._next)
	await hold("back", 2.0)
	Input.action_release("back")

	# --- recovery -------------------------------------------------------------
	car.place(Transform3D(Basis(Vector3.FORWARD, PI), Vector3(160, 1.5, -60)))
	await wait(1.5)
	check(car.is_flipped(), "car can end up on its roof")
	main._recover_cooldown = 0.0
	main.recover_car(car, false)
	await wait(1.0)
	check(not car.is_flipped() and car.wheels_on_ground() >= 3, "R puts the car back on its wheels")
	check(main.layout.on_road(car.global_position, 1.0), "recovered car stands on a road")

	# --- collisions: building walls stop the car --------------------------------
	# Behind the garage, facing north straight at its back wall (z = 38).
	car.place(Transform3D(Basis.IDENTITY, Vector3(-95, 0.7, 62)))
	await wait(0.3)
	Input.action_press("forward")
	await wait(3.0)
	Input.action_release("forward")
	var gz := car.global_position.z
	check(gz > CityLayout.GARAGE_POS.z + 9.5 or absf(car.global_position.x - CityLayout.GARAGE_POS.x) > 7.5, "car cannot drive through the garage's back wall (z=%.1f)" % gz)
	check(car.global_position.y > -0.5, "car stays above the ground after the crash")
	await hold("back", 1.0)

	# --- traffic and people ---------------------------------------------------------
	car.place(Transform3D(Basis(Vector3.UP, -PI / 2), Vector3(-120, 0.6, 6)))
	await wait(6.0)
	var ai := 0
	for c in main.cars:
		if is_instance_valid(c) and c.driver == "ai" and not c.is_police:
			ai += 1
	check(ai >= 3, "civilian traffic is driving (%d cars)" % ai)
	check(main.peds.peds.size() > 20, "pedestrians populate the district (%d)" % main.peds.peds.size())
	await shot("04_street")

	# --- police chase, search, escape ------------------------------------------------------
	main.police.force_wanted(1)
	check(main.police.state == Police.State.CHASE and main.police.stars == 1, "wanted level starts a chase")
	await wait(3.0)
	var cops := main.police.cops.size()
	check(cops >= 2, "police cars dispatched (%d)" % cops)
	check(main.police.min_spawn_dist >= 90.0, "patrols spawn away from the player (closest %.0f m, out of view)" % main.police.min_spawn_dist)
	await shot("05_chase")
	# Hide under the covered parking far from the cops.
	var hide: AABB = main.city.hide_zones[0]
	car.place(Transform3D(Basis.IDENTITY, hide.get_center() + Vector3(0, -2.4, 0)))
	for d in main.police.cops:
		if d.car.global_position.distance_to(car.global_position) < 90.0:
			d.car.place(Transform3D(Basis.IDENTITY, Vector3(-250, 0.6, -250)))
	var saw_search := false
	var escaped := false
	for i in 60:
		await wait(0.5)
		if main.police.state == Police.State.SEARCH:
			saw_search = true
		if main.police.stars == 0:
			escaped = true
			break
	check(saw_search, "police switch to search when the player is out of sight")
	check(escaped, "wanted level clears after hiding long enough")

	# --- busted ------------------------------------------------------------------------------
	Game.add_money(1000)
	var money_before := Game.money()
	main.police.force_wanted(1)
	car.set_controls(0, 0, 0, true)
	var cop_xf := car.global_transform * Transform3D(Basis.IDENTITY, Vector3(3.5, 0.2, 0))
	var cop := main.spawn_car("posbon", cop_xf, {})
	var drv := AiDriver.new(cop, main.layout)
	main.police.cops.append(drv)
	var busted := [false]
	main.police.busted.connect(func(_f): busted[0] = true, CONNECT_ONE_SHOT)
	for i in 30:
		if not busted[0] and is_instance_valid(cop):
			cop.place(cop_xf)
		await wait(0.25)
		if busted[0]:
			break
	check(busted[0], "standing still next to the police ends in arrest")
	check(Game.money() < money_before, "arrest takes a fine ($%d → $%d)" % [money_before, Game.money()])
	check(main.player.global_position.distance_to(CityLayout.GARAGE_APRON) < 10.0, "after arrest the hero is back at the garage")
	main.menus._close_all()
	await wait(0.5)

	# --- mission 1: delivery (win, reward once) --------------------------------------------------
	var m := main.missions
	var money0 := Game.money()
	main.player.teleport(Missions.DEFS["delivery"]["start"] + Vector3(0, 0.2, 0))
	await wait(0.3)
	check(m.prompt_text().begins_with("E —"), "delivery marker shows a start prompt")
	main._interact()
	check(m.active == "delivery", "delivery mission starts with E")
	await wait(0.5)
	main.player.teleport(m.client_car.global_transform * Vector3(-1.8, 0.2, 0))
	await wait(0.2)
	main._interact()
	await wait(0.5)
	check(main.player.car == m.client_car and m.phase == "drive", "boarding the client's car starts the timer")
	await shot("06_delivery")
	m.client_car.place(Transform3D(Basis.IDENTITY, Missions.DELIVERY_DEST + Vector3(0, 0.6, 0)))
	await wait(1.5)
	check(m.active == "" and Game.money() == money0 + 600, "delivery completes and pays $600 (money %d)" % Game.money())
	await wait(1.0)
	check(Game.money() == money0 + 600, "reward is paid only once")
	# Retry and fail by time.
	m.retry()
	check(m.active == "delivery", "Enter restarts the finished mission")
	m.timer = 0.05
	await wait(0.5)
	check(m.active == "" and Game.money() == money0 + 600, "delivery fails when the clock runs out (no reward)")

	# --- mission 2: ring ------------------------------------------------------------------------------
	var mycar := main.my_car
	if main.player.car != mycar:
		if main.player.car:
			main._try_exit(main.player.car)
		await wait(0.3)
		main.player.teleport(mycar.global_transform * Vector3(-1.8, 0.2, 0))
		await wait(0.2)
		main._interact()
	await wait(0.3)
	mycar.place(Transform3D(Basis.IDENTITY, Missions.DEFS["ring"]["start"] + Vector3(3, 0.6, 0)))
	await wait(0.3)
	main._interact()
	check(m.active == "ring", "ring race starts in a car")
	var money1 := Game.money()
	for i in Missions.RING_POINTS.size():
		mycar.place(Transform3D(Basis.IDENTITY, Missions.RING_POINTS[i] + Vector3(0, 0.6, 0)))
		await wait(0.25)
		if i == 2:
			check(m.checkpoint == 3, "checkpoints count in order")
	await wait(0.5)
	check(m.active == "" and Game.money() == money1 + 800, "ring completes and pays $800")

	# --- mission 3: escape ---------------------------------------------------------------------------
	mycar.place(Transform3D(Basis.IDENTITY, Missions.DEFS["escape"]["start"] + Vector3(0, 0.6, 0)))
	await wait(0.3)
	main._interact()
	check(m.active == "escape" and main.police.stars == 2, "escape mission gives two stars")
	await wait(2.0)
	mycar.place(Transform3D(Basis.IDENTITY, hide.get_center() + Vector3(0, -2.4, 0)))
	var money2 := Game.money()
	var won := false
	for i in 80:
		for d in main.police.cops:
			if d.car.global_position.distance_to(mycar.global_position) < 100.0:
				d.car.place(Transform3D(Basis.IDENTITY, Vector3(250, 0.6, -250)))
		await wait(0.5)
		if m.active == "":
			won = Game.money() == money2 + 1000
			break
	check(won, "losing the police completes «Оторвись» (+$1000)")

	# --- garage: purchases really change the car ------------------------------------------------------
	Game.add_money(5000)
	var kind := Game.selected_car()
	var f0 := mycar.engine_force()
	var g0 := mycar.grip_factor()
	main.menus.show_garage()
	await wait(0.2)
	await shot("07_garage")
	var cash := Game.money()
	main.menus._upgrade_row(kind, "engine", "x", Game.PRICE_ENGINE, "")  # build row only
	if Game.spend(Game.PRICE_ENGINE[0]):
		Game.set_car_value(kind, "engine", 1)
	if Game.spend(Game.PRICE_GRIP[0]):
		Game.set_car_value(kind, "grip", 1)
	if Game.spend(Game.PRICE_PAINT):
		Game.set_car_value(kind, "paint", 2)
	if Game.spend(Game.PRICE_RIMS):
		Game.set_car_value(kind, "rims", "steel" if Game.car_setup(kind)["rims"] == "sport" else "sport")
	await wait(0.2)
	check(main.my_car.engine_force() > f0 * 1.1, "engine upgrade raises power (%.0f → %.0f)" % [f0, main.my_car.engine_force()])
	check(main.my_car.grip_factor() > g0, "grip upgrade raises tyre grip")
	check(main.my_car.paint == Game.PAINTS[2][1], "repaint applies to the car")
	check(Game.money() == cash - Game.PRICE_ENGINE[0] - Game.PRICE_GRIP[0] - Game.PRICE_PAINT - Game.PRICE_RIMS, "purchases are charged")
	main.menus._close_all()
	# Car switch.
	Game.select_car("chabuk")
	await wait(0.3)
	check(main.my_car != null and main.my_car.kind == "chabuk", "garage switches the personal car to CHABUK")

	# --- save / load ----------------------------------------------------------------------------------
	var saved_money := Game.money()
	Game.load_game()
	check(Game.money() == saved_money and Game.car_setup(kind)["engine"] == 1 and Game.selected_car() == "chabuk", "progress survives a reload")
	var f := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
	f.store_string("{ broken json ::")
	f.close()
	Game.load_game()
	check(Game.money() == Game.START_MONEY and Game.save_error != "", "a corrupt save loads safely with defaults")
	f = FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
	f.store_string('{"money": "lots", "car": "tank", "cars": {"sado": {"engine": 99, "paint": -5}}, "settings": {"quality": 7}}')
	f.close()
	Game.load_game()
	check(Game.money() == Game.START_MONEY and Game.selected_car() == "sado" and Game.car_setup("sado")["engine"] == 3 and Game.setting("quality") == 2, "invalid values are clamped on load")
	Game.reset_progress()
	check(Game.money() == Game.START_MONEY and Game.car_setup("sado")["engine"] == 0, "reset progress restores defaults")

	# --- quality switch ----------------------------------------------------------------------------------
	Game.set_setting("quality", 0)
	await wait(0.3)
	check(not main.sun.shadow_enabled, "low quality turns shadows off")
	Game.set_setting("quality", 2)
	await wait(0.3)

	print("\nSUMMARY: %d passed, %d failed" % [passed, failed])
	for x in _fails:
		print("  failed: ", x)
	get_tree().quit(1 if failed > 0 else 0)
