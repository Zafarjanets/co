class_name Police
extends Node
## Wanted level (0–3 stars), patrols, chases, search and arrest.

signal wanted_changed(stars: int, state: int)
signal busted(fine: int)
signal escaped

enum State { NONE, CHASE, SEARCH, ESCAPED }

const PATROLS := 2
const SEE_DIST := 80.0
const HIDE_SEE_DIST := 18.0
const BUST_TIME := 3.0

var main: Main
var stars := 0
var state := State.NONE
var cops: Array[AiDriver] = []
var last_known := Vector3.ZERO
var unseen := 0.0
var bust_timer := 0.0
var chase_time := 0.0
var _escaped_timer := 0.0
var _star_cooldown := 0.0
var _spawn_timer := 0.0
var _see_timer := 0.0
var _seen := false
var _rng := RandomNumberGenerator.new()
var _ray := PhysicsRayQueryParameters3D.new()


func setup(m: Main) -> void:
	main = m
	name = "Police"
	_rng.randomize()
	_ray.collision_mask = 1


func state_text() -> String:
	match state:
		State.CHASE:
			return "ПОГОНЯ"
		State.SEARCH:
			return "ПОИСК"
		State.ESCAPED:
			return "ВЫ СКРЫЛИСЬ"
	return ""


## Time left until the search is given up (for the HUD).
func search_left() -> float:
	return maxf(0.0, _search_needed() - unseen) if state == State.SEARCH else 0.0


func _search_needed() -> float:
	return 9.0 + 5.0 * stars


func release(c: Car) -> void:
	for d in cops:
		if d.car == c:
			cops.erase(d)
			break


func is_cop(c: Object) -> bool:
	for d in cops:
		if d.car == c:
			return true
	return false


# --- crimes ----------------------------------------------------------------------

## A crime near `pos`. Severity is the minimum star level it brings.
func report_crime(kind: String, pos: Vector3, severity: int) -> void:
	var witnessed := kind in ["hit_police", "police_car"] or state == State.CHASE or _cop_sees(pos, 65.0)
	if not witnessed:
		return
	var before := stars
	if stars >= severity and stars > 0 and _star_cooldown <= 0.0 and kind in ["hit_police", "police_car", "hit_ped"]:
		stars = mini(3, stars + 1)
		_star_cooldown = 8.0
	else:
		stars = maxi(stars, mini(3, severity))
	last_known = main.focus_position()
	unseen = 0.0
	if state != State.CHASE:
		state = State.CHASE
		chase_time = 0.0
	if stars != before:
		main.hud.toast(_crime_text(kind), 2.5)
	wanted_changed.emit(stars, state)


func _crime_text(kind: String) -> String:
	match kind:
		"hit_police":
			return "Вы протаранили полицию!"
		"police_car":
			return "Угон патрульной машины!"
		"hit_ped":
			return "Наезд на пешехода!"
		"carjack":
			return "Угон машины на глазах у полиции!"
		"speeding":
			return "Превышение скорости рядом с патрулём!"
		"crash":
			return "ДТП на глазах у полиции!"
	return "Нарушение!"


## Force a wanted level (used by the «Оторвись» mission).
func force_wanted(level: int) -> void:
	stars = clampi(level, 0, 3)
	state = State.CHASE if stars > 0 else State.NONE
	last_known = main.focus_position()
	unseen = 0.0
	chase_time = 0.0
	wanted_changed.emit(stars, state)


func clear_wanted() -> void:
	stars = 0
	state = State.NONE
	bust_timer = 0.0
	unseen = 0.0
	for d in cops:
		if is_instance_valid(d.car):
			d.car.siren_on = false
			d.start_lane()
	wanted_changed.emit(stars, state)


func on_impact(c: Car, other: Object, strength: float) -> void:
	var pc := main.player.car
	if pc == null:
		return
	if c == pc and other is Car and is_cop(other):
		report_crime("hit_police", pc.global_position, 1)
	elif c == pc and other is Car and strength > 5.0:
		report_crime("crash", pc.global_position, 1)


# --- per frame ----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var focus := main.focus_position()
	_star_cooldown = maxf(0.0, _star_cooldown - delta)
	_cleanup(focus)
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = 1.0
		_spawn_needed(focus)

	# Line of sight checks a few times per second.
	_see_timer -= delta
	if _see_timer <= 0.0:
		_see_timer = 0.2
		_seen = _cop_sees(focus, SEE_DIST)
		_check_speeding(focus)

	if stars > 0:
		if _seen:
			last_known = focus
			unseen = 0.0
			if state != State.CHASE:
				state = State.CHASE
				wanted_changed.emit(stars, state)
		else:
			unseen += delta
			if state == State.CHASE and unseen > 3.0:
				state = State.SEARCH
				wanted_changed.emit(stars, state)
			if unseen > _search_needed():
				_escape()
		if state == State.CHASE:
			chase_time += delta
			if chase_time > 50.0 and stars < 3:
				stars += 1
				chase_time = 0.0
				main.hud.toast("Розыск растёт!", 2.0)
				wanted_changed.emit(stars, state)
		_check_bust(focus, delta)
	elif state == State.ESCAPED:
		_escaped_timer -= delta
		if _escaped_timer <= 0.0:
			state = State.NONE
			wanted_changed.emit(stars, state)

	# Drive the cops.
	var vel := main.focus_velocity()
	var nearest := INF
	for d in cops:
		if not is_instance_valid(d.car) or d.car.driver != "ai":
			continue
		var dist := d.car.global_position.distance_to(focus)
		if stars > 0:
			nearest = minf(nearest, dist)
			d.car.siren_on = true
			if state == State.CHASE:
				var sees := dist < 60.0 and _los(d.car.global_position + Vector3(0, 1.3, 0), focus + Vector3(0, 1.0, 0))
				d.chase(focus, vel, sees)
			elif d.mode != "goto" or d.target.distance_to(last_known) > 20.0:
				if d.mode != "lane" or d.car.global_position.distance_to(last_known) > 60.0:
					d.goto(last_known + Vector3(_rng.randf_range(-25, 25), 0, _rng.randf_range(-25, 25)))
		else:
			d.car.siren_on = false
			if d.mode != "lane":
				d.start_lane()
		if dist > 120.0 and Engine.get_physics_frames() % 3 != 0:
			continue
		d.update(delta, main.traffic.obstacles_near(d.car.global_position))
	Sfx.set_siren(stars > 0 and nearest < 200.0, nearest)


func _escape() -> void:
	stars = 0
	state = State.ESCAPED
	_escaped_timer = 3.5
	bust_timer = 0.0
	for d in cops:
		if is_instance_valid(d.car):
			d.car.siren_on = false
			d.start_lane()
	main.hud.toast("Вы скрылись от полиции!", 3.0)
	wanted_changed.emit(stars, state)
	escaped.emit()


func _check_bust(focus: Vector3, delta: float) -> void:
	var pc := main.player.car
	var my_speed := pc.linear_velocity.length() if pc else main.player.velocity.length()
	var near := false
	for d in cops:
		if not is_instance_valid(d.car) or d.car.driver != "ai":
			continue
		var dd := d.car.global_position.distance_to(focus)
		if dd < (8.5 if pc else 6.0) and d.car.linear_velocity.length() < 8.0:
			near = true
			break
	if near and my_speed < 2.0 and state == State.CHASE:
		bust_timer += delta
		if bust_timer >= BUST_TIME:
			_bust()
	else:
		bust_timer = maxf(0.0, bust_timer - delta * 1.5)


func _bust() -> void:
	var amount := 200 + 150 * stars
	var taken := Game.fine(amount)
	stars = 0
	state = State.NONE
	bust_timer = 0.0
	unseen = 0.0
	# The chasers stay behind; new patrols appear later away from the garage.
	for d: AiDriver in cops.duplicate():
		if is_instance_valid(d.car):
			main.remove_car(d.car)
	cops.clear()
	wanted_changed.emit(stars, state)
	busted.emit(taken)


func _check_speeding(focus: Vector3) -> void:
	var pc := main.player.car
	if pc == null or stars > 0:
		return
	if pc.speed_kmh() > 95.0 and _cop_sees(focus, 35.0):
		report_crime("speeding", focus, 1)


func _cop_sees(p: Vector3, max_dist: float) -> bool:
	var hidden := false
	for z in main.city.hide_zones:
		if z.has_point(p + Vector3(0, 0.5, 0)):
			hidden = true
	var reach := HIDE_SEE_DIST if hidden else max_dist
	for d in cops:
		if not is_instance_valid(d.car) or d.car.driver != "ai":
			continue
		var cp := d.car.global_position
		if cp.distance_to(p) > reach:
			continue
		if _los(cp + Vector3(0, 1.4, 0), p + Vector3(0, 1.0, 0)):
			return true
	return false


func _los(a: Vector3, b: Vector3) -> bool:
	_ray.from = a
	_ray.to = b
	return main.get_world_3d().direct_space_state.intersect_ray(_ray).is_empty()


# --- population --------------------------------------------------------------------------

func _cleanup(focus: Vector3) -> void:
	for d: AiDriver in cops.duplicate():
		if not is_instance_valid(d.car) or d.car.driver != "ai":
			cops.erase(d)
			continue
		var far := d.car.global_position.distance_to(focus) > (320.0 if stars > 0 else 260.0)
		var wrecked := d.car.is_flipped() or d.car.global_position.y < -3.0
		if (far or wrecked) and not main.is_visible_to_camera(d.car.global_position):
			cops.erase(d)
			main.remove_car(d.car)


func _spawn_needed(focus: Vector3) -> void:
	var want := PATROLS if stars == 0 else clampi(stars + 1, 2, 4)
	if state == State.ESCAPED:
		want = PATROLS
	if cops.size() >= want:
		return
	var near_min := 110.0 if stars > 0 else 90.0
	var near_max := 200.0
	var layout := main.layout
	for attempt in 12:
		var e: Dictionary = layout.edges[_rng.randi() % layout.edges.size()]
		var a: int = e["a"]
		var b: int = e["b"]
		var pts := layout.lane_points(a, b)
		if stars > 0:
			# Drive towards the player.
			if layout.nodes[b].distance_to(focus) > layout.nodes[a].distance_to(focus):
				var t := a
				a = b
				b = t
				pts = layout.lane_points(a, b)
		var p: Vector3 = pts[0].lerp(pts[1], _rng.randf_range(0.1, 0.6))
		var dist := p.distance_to(focus)
		if dist < near_min or dist > near_max:
			continue
		if main.is_visible_to_camera(p, 6.0):
			continue
		var clear := true
		for c in main.cars:
			if is_instance_valid(c) and c.global_position.distance_to(p) < 12.0:
				clear = false
				break
		if not clear:
			continue
		var dir: Vector3 = (pts[1] - pts[0]).normalized()
		var car := main.spawn_car("posbon", Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.z)), p + Vector3(0, 0.5, 0)), {})
		var drv := AiDriver.new(car, layout)
		drv.cruise = 12.0
		drv.prev_node = a
		drv.cur_node = b
		drv.waypoints.append(pts[1])
		cops.append(drv)
		return
