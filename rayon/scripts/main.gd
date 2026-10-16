class_name Main
extends Node3D
## Game root: builds the world, owns the hero, the cars and every system,
## and handles getting in/out of cars, recovery, pause and quality.

const EXIT_SPEED := 5.0

var layout: CityLayout
var city: CityBuilder
var sun: DirectionalLight3D
var player: Player
var rig: CameraRig
var hud: Hud
var menus: Menus
var traffic: Traffic
var police: Police
var peds: Pedestrians
var missions: Missions
var effects: Effects

var cars: Array[Car] = []
var my_car: Car = null
var playing := false              # false while in the start menu
var _recover_cooldown := 0.0
var _flip_time := 0.0
var _prompt := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var world := Node3D.new()
	world.name = "World"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	sun = EnvironmentSetup.create(world)
	city = CityBuilder.new()
	city.name = "City"
	world.add_child(city)
	city.build(true)
	layout = city.layout

	effects = Effects.new()
	world.add_child(effects)

	player = Player.new()
	world.add_child(player)
	player.teleport(CityLayout.GARAGE_APRON + Vector3(4.0, 0.1, -1.0), PI)

	rig = CameraRig.new()
	world.add_child(rig)
	rig.follow(player, false)
	rig.process_mode = Node.PROCESS_MODE_ALWAYS
	rig.menu_mode = true

	_spawn_my_car()
	_spawn_parked_cars()
	_spawn_showcase_cars()

	traffic = Traffic.new()
	world.add_child(traffic)
	traffic.setup(self)
	peds = Pedestrians.new()
	world.add_child(peds)
	peds.setup(self)
	police = Police.new()
	world.add_child(police)
	police.setup(self)
	missions = Missions.new()
	world.add_child(missions)
	missions.setup(self)

	hud = Hud.new()
	add_child(hud)
	hud.setup(self)
	menus = Menus.new()
	add_child(menus)
	menus.setup(self)

	Game.settings_changed.connect(apply_settings)
	Game.car_config_changed.connect(_on_car_config_changed)
	apply_settings()
	get_tree().paused = true
	menus.show_main()


# --- cars -----------------------------------------------------------------------

func spawn_car(kind: String, xf: Transform3D, cfg := {}) -> Car:
	var c := Car.create(kind, cfg)
	get_node("World").add_child(c)
	c.place(xf)
	cars.append(c)
	c.impact.connect(_on_car_impact.bind(c))
	effects.register(c)
	return c


func remove_car(c: Car) -> void:
	if c == null or not is_instance_valid(c):
		return
	if c == player.car:
		return
	cars.erase(c)
	effects.unregister(c)
	if c == my_car:
		my_car = null
	c.queue_free()


func _garage_car_xf() -> Transform3D:
	return Transform3D(Basis.IDENTITY, CityLayout.GARAGE_POS + Vector3(0, 0.45, 0))


func _spawn_my_car() -> void:
	var kind := Game.selected_car()
	my_car = spawn_car(kind, _garage_car_xf(), Game.car_config(kind))
	my_car.set_meta("personal", true)


func _spawn_parked_cars() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 77
	var n := 0
	for xf in city.parked_spots:
		if n >= 10:
			break
		var kind := "sado" if r.randf() < 0.5 else "chabuk"
		var cfg := {"paint": Game.PAINTS[r.randi() % Game.PAINTS.size()][1], "rims": "steel" if r.randf() < 0.6 else "sport"}
		var c := spawn_car(kind, xf, cfg)
		c.set_meta("parked", true)
		c.sleeping = true
		n += 1


## The two imported models stand next to the garage so they can be tried at once.
func _spawn_showcase_cars() -> void:
	for spot in [["m5", Vector3(-81.0, 0.7, 21.0)], ["cls", Vector3(-107.0, 0.7, 34.0)]]:
		var kind: String = spot[0]
		if kind == Game.selected_car():
			continue
		var c := spawn_car(kind, Transform3D(Basis.IDENTITY, spot[1]), {})
		c.set_meta("parked", true)
		c.set_meta("showcase", true)


func _on_car_config_changed(kind: String) -> void:
	# Garage changed the personal car: refresh or swap the model in the garage.
	if my_car != null and is_instance_valid(my_car) and my_car.kind == Game.selected_car():
		my_car.apply_config(Game.car_config(my_car.kind))
		return
	var was_driving := my_car != null and player.car == my_car
	var xf := my_car.global_transform if my_car != null else _garage_car_xf()
	if was_driving:
		player.car = null
		my_car.driver = ""
	remove_car(my_car)
	var k := Game.selected_car()
	my_car = spawn_car(k, xf, Game.car_config(k))
	my_car.set_meta("personal", true)
	if was_driving:
		_enter_car(my_car)


func player_car() -> Car:
	return player.car


func focus_position() -> Vector3:
	return player.car.global_position if player.car else player.global_position


func focus_velocity() -> Vector3:
	return player.car.linear_velocity if player.car else player.velocity


func is_visible_to_camera(p: Vector3, margin := 4.0) -> bool:
	var cam := rig.camera
	if not cam.is_position_in_frustum(p) and not cam.is_position_in_frustum(p + Vector3(0, margin, 0)):
		return false
	return cam.global_position.distance_to(p) < 320.0


# --- frame ------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	var c := player.car
	if c != null:
		_drive(c, delta)
	_recover_cooldown = maxf(0.0, _recover_cooldown - delta)
	# Safety net: anything that falls out of the world comes back to the road.
	for car in cars:
		if is_instance_valid(car) and car.global_position.y < -6.0:
			if car == player.car:
				recover_car(car, true)
			else:
				car.place(_road_xf(car.global_position, -car.global_basis.z))


func _drive(c: Car, delta: float) -> void:
	var thr := Input.get_action_strength("forward")
	var brk := Input.get_action_strength("back")
	var st := Input.get_action_strength("left") - Input.get_action_strength("right")
	var hb := Input.is_action_pressed("handbrake")
	if not player.input_enabled:
		thr = 0.0
		brk = 0.0
		st = 0.0
		hb = true
	c.set_controls(thr, brk, st, hb)
	if c.is_flipped():
		_flip_time += delta
	else:
		_flip_time = 0.0


func _process(delta: float) -> void:
	if not playing:
		return
	rig.sensitivity = Game.setting("sensitivity")
	rig.invert_y = Game.setting("invert_y")
	player.cam_yaw = rig.yaw
	var c := player.car
	if c:
		Sfx.set_engine(true, c.rpm, c.engine_load, c.linear_velocity.length())
		Sfx.set_skid(c.skid)
		hud.set_speed(c.speed_kmh(), c.gear if not c.reversing else -1)
	else:
		Sfx.set_engine(false, 0.0, 0.0, 0.0)
		Sfx.set_skid(0.0)
		hud.set_speed(-1.0, 0)
	_update_prompt()


func _update_prompt() -> void:
	var text := ""
	var c := player.car
	if get_tree().paused:
		text = ""
	elif c:
		if c.is_flipped() and _flip_time > 1.0 or c.stuck_time > 2.5:
			text = "R — поставить машину на дорогу"
		elif missions.prompt_text() != "":
			text = missions.prompt_text()
		elif _in_garage_zone(c.global_position) and c.has_meta("personal"):
			text = "E — открыть гараж"
		elif c.linear_velocity.length() < EXIT_SPEED:
			text = "E — выйти из машины"
	else:
		var m := missions.prompt_text()
		if m != "":
			text = m
		else:
			var near := _nearest_enterable()
			if near:
				var label: String = near.kind.to_upper()
				if near.is_police:
					text = "E — сесть в %s (полиция заметит!)" % label
				elif near.driver == "ai":
					text = "E — забрать %s у водителя" % label
				else:
					text = "E — сесть в %s" % label
	if text != _prompt:
		_prompt = text
		hud.set_prompt(text)


func _unhandled_input(event: InputEvent) -> void:
	if not playing:
		return
	if event.is_action_pressed("pause"):
		if menus.is_open():
			menus.back()
		else:
			menus.show_pause()
		get_viewport().set_input_as_handled()
		return
	if get_tree().paused:
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("interact"):
		_interact()
	elif event.is_action_pressed("recover"):
		if player.car:
			recover_car(player.car, false)
	elif event.is_action_pressed("retry"):
		missions.retry()
	elif event.is_action_pressed("horn") and player.car:
		Sfx.horn()
		peds.scare(player.car.global_position, 18.0)


func _interact() -> void:
	var c := player.car
	if missions.interact():
		return
	if c:
		if _in_garage_zone(c.global_position) and c.has_meta("personal") and c.linear_velocity.length() < 3.0:
			menus.show_garage()
			return
		_try_exit(c)
	else:
		var near := _nearest_enterable()
		if near:
			_enter_car(near)


func _in_garage_zone(p: Vector3) -> bool:
	var g := CityLayout.GARAGE_POS
	return absf(p.x - g.x) < 6.0 and p.z > g.z - 9.0 and p.z < g.z + 7.0


func _nearest_enterable() -> Car:
	var best: Car = null
	var bd := INF
	for c in cars:
		if not is_instance_valid(c) or c == player.car or c.is_flipped() or c.linear_velocity.length() > 4.0:
			continue
		if c.global_position.distance_to(player.global_position) > 8.0:
			continue
		var local := c.global_transform.affine_inverse() * player.global_position
		var l: float = c.model.get_meta("length", 4.2)
		var w: float = c.model.get_meta("width", 1.7)
		if absf(local.z) < l * 0.5 + 0.9 and absf(local.x) < w * 0.5 + 1.5 and absf(local.y) < 2.5:
			var d := Vector2(local.x, local.z).length()
			if d < bd:
				best = c
				bd = d
	return best


func _enter_car(c: Car) -> void:
	if c.driver == "ai":
		var door := c.global_transform * Vector3(-1.4, 0, 0)
		traffic.release(c)
		police.release(c)
		peds.spawn_ejected(door, c.global_position)
		if not c.is_police:
			police.report_crime("carjack", c.global_position, 1)
	if c.is_police:
		police.report_crime("police_car", c.global_position, 2)
	c.remove_meta("parked")
	c.driver = "player"
	c.sleeping = false
	player.enter(c)
	rig.follow(c, true)
	Sfx.door()
	hud.set_prompt("")
	if c.is_police:
		hud.toast("Вы угнали патрульную машину!", 3.0)


func _try_exit(c: Car) -> void:
	if c.linear_velocity.length() > EXIT_SPEED:
		hud.toast("Сбавьте скорость, чтобы выйти", 1.5)
		return
	var spot := _free_exit_spot(c)
	if spot.is_empty():
		hud.toast("Нет места, чтобы выйти из машины", 2.0)
		return
	c.set_controls(0.0, 0.0, 0.0, true)
	c.driver = ""
	if c.is_police:
		c.siren_on = false
	player.exit_to(spot["pos"], spot["yaw"])
	rig.follow(player, false)
	rig.yaw = c.global_rotation.y
	Sfx.door()


## Finds a free spot next to the car for the hero (left door first).
func _free_exit_spot(c: Car) -> Dictionary:
	var w: float = c.model.get_meta("width", 1.7)
	var l: float = c.model.get_meta("length", 4.2)
	var candidates := [Vector3(-(w * 0.5 + 0.7), 0, -0.2), Vector3(w * 0.5 + 0.7, 0, -0.2),
		Vector3(0, 0, l * 0.5 + 0.9), Vector3(0, 0, -(l * 0.5 + 0.9)),
		Vector3(-(w * 0.5 + 1.6), 0, 0.5), Vector3(w * 0.5 + 1.6, 0, 0.5)]
	var space := get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = 0.32
	shape.height = 1.7
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1 | 2
	q.exclude = [c.get_rid()]
	var flat := Basis(Vector3.UP, c.global_rotation.y)
	for local in candidates:
		var p: Vector3 = c.global_position + flat * local
		# Find the ground below the spot.
		var ray := PhysicsRayQueryParameters3D.create(p + Vector3(0, 2.0, 0), p + Vector3(0, -2.0, 0), 1)
		var hit := space.intersect_ray(ray)
		if hit.is_empty():
			continue
		var ground: Vector3 = hit["position"]
		q.transform = Transform3D(Basis.IDENTITY, ground + Vector3(0, 0.95, 0))
		if space.intersect_shape(q, 1).is_empty():
			# Also make sure there's no wall between the car and the spot.
			var los := PhysicsRayQueryParameters3D.create(c.global_position + Vector3(0, 1.0, 0), ground + Vector3(0, 1.0, 0), 1)
			if space.intersect_ray(los).is_empty():
				return {"pos": ground + Vector3(0, 0.05, 0), "yaw": c.global_rotation.y}
	return {}


# --- recovery & respawn -----------------------------------------------------------------

func _road_xf(p: Vector3, heading: Vector3) -> Transform3D:
	var rp := layout.nearest_road_point(p, heading)
	var dir: Vector3 = rp["dir"]
	return Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.z)), rp["pos"] + Vector3(0, 0.6, 0))


func recover_car(c: Car, forced: bool) -> void:
	if _recover_cooldown > 0.0 and not forced:
		return
	var needs := forced or c.is_flipped() or c.stuck_time > 0.8 or c.linear_velocity.length() < 4.0
	if not needs:
		hud.toast("Остановитесь, чтобы восстановить машину", 1.5)
		return
	var fwd := -c.global_basis.z
	fwd.y = 0
	var xf := _road_xf(c.global_position, fwd)
	# Avoid dropping onto another car.
	for other in cars:
		if other != c and is_instance_valid(other) and other.global_position.distance_to(xf.origin) < 4.0:
			xf.origin += xf.basis * Vector3(0, 0, 7.0)
	c.place(xf)
	_recover_cooldown = 2.0
	_flip_time = 0.0
	hud.toast("Машина восстановлена", 1.2)


## Back to the garage after being busted (or on reset).
func respawn_at_garage() -> void:
	var c := player.car
	if c:
		c.driver = ""
		player.exit_to(CityLayout.GARAGE_APRON + Vector3(4, 0.1, -1), PI)
	else:
		player.teleport(CityLayout.GARAGE_APRON + Vector3(4, 0.1, -1), PI)
	rig.follow(player, false)
	rig.yaw = PI
	if my_car and is_instance_valid(my_car):
		my_car.place(_garage_car_xf())
	else:
		_spawn_my_car()


# --- impacts ---------------------------------------------------------------------------------

func _on_car_impact(strength: float, other: Object, c: Car) -> void:
	var near_player := c == player.car or other == player.car
	if near_player or c.global_position.distance_to(rig.camera.global_position) < 40.0:
		Sfx.impact(strength, c.global_position)
	if c == player.car:
		rig.add_shake(clampf(strength * 0.08, 0.0, 0.6))
	police.on_impact(c, other, strength)


# --- settings ----------------------------------------------------------------------------------

func apply_settings() -> void:
	var q: int = Game.setting("quality")
	var vp := get_viewport()
	match q:
		0:
			sun.shadow_enabled = false
			vp.scaling_3d_scale = 0.75
			vp.msaa_3d = Viewport.MSAA_DISABLED
			_set_outline_scale(0.0)
			rig.camera.far = 900.0
		1:
			sun.shadow_enabled = true
			sun.directional_shadow_max_distance = 90.0
			vp.scaling_3d_scale = 1.0
			vp.msaa_3d = Viewport.MSAA_DISABLED
			_set_outline_scale(1.0)
			rig.camera.far = 2500.0
		_:
			sun.shadow_enabled = true
			sun.directional_shadow_max_distance = 140.0
			vp.scaling_3d_scale = 1.0
			vp.msaa_3d = Viewport.MSAA_2X
			_set_outline_scale(1.0)
			rig.camera.far = 4000.0
	Sfx.set_volume(Game.setting("volume"))
	if traffic:
		traffic.set_quality(q)
	if peds:
		peds.set_quality(q)


## Low quality hides the dark outlines (one shared parameter per outline material).
func _set_outline_scale(v: float) -> void:
	var seen := {}
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var meshes: Array = []
		if n is MeshInstance3D and n.mesh:
			meshes.append(n.mesh)
			for i in n.get_surface_override_material_count():
				_outline_param(n.get_surface_override_material(i), v, seen)
		elif n is MultiMeshInstance3D and n.multimesh and n.multimesh.mesh:
			meshes.append(n.multimesh.mesh)
		for m in meshes:
			for i in (m as Mesh).get_surface_count():
				_outline_param((m as Mesh).surface_get_material(i), v, seen)
	Mats.outline_scale = v


func _outline_param(mat: Material, v: float, seen: Dictionary) -> void:
	while mat != null and not seen.has(mat):
		seen[mat] = true
		if mat is ShaderMaterial and (mat as ShaderMaterial).shader == Mats.OUTLINE_SHADER:
			(mat as ShaderMaterial).set_shader_parameter("outline_scale", v)
		mat = mat.next_pass


func start_game() -> void:
	playing = true
	rig.menu_mode = false
	rig.follow(player, false)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Sfx.start()
	if Game.save_error != "":
		hud.toast(Game.save_error, 5.0)
		Game.save_error = ""
	else:
		hud.toast("Добро пожаловать в РАЙОН! Садитесь в машину у гаража (E).", 5.0)
