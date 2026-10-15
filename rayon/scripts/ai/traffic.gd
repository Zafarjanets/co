class_name Traffic
extends Node
## Civilian traffic: SADO and CHABUK in random colours following the lanes.
## Cars appear out of the camera's view around the player and vanish when far.

const SPAWN_MIN := 60.0
const SPAWN_MAX := 190.0
const DESPAWN := 240.0

var main: Main
var drivers: Array[AiDriver] = []
var max_cars := 9
var _rng := RandomNumberGenerator.new()
var _spawn_timer := 0.0


func setup(m: Main) -> void:
	main = m
	_rng.seed = 1234
	name = "Traffic"


func set_quality(q: int) -> void:
	max_cars = [4, 8, 11][q]


func release(c: Car) -> void:
	for d in drivers:
		if d.car == c:
			drivers.erase(d)
			break
	c.driver = ""


func obstacles_near(p: Vector3) -> Array:
	var out: Array = []
	for c in main.cars:
		if is_instance_valid(c) and c.global_position.distance_squared_to(p) < 1600.0:
			out.append(c.global_position)
	if main.player.car == null:
		out.append(main.player.global_position)
	out.append_array(main.peds.positions_near(p, 30.0))
	return out


func _physics_process(delta: float) -> void:
	var focus := main.focus_position()
	for d: AiDriver in drivers.duplicate():
		if not is_instance_valid(d.car) or d.car.driver != "ai":
			drivers.erase(d)
			continue
		var pos := d.car.global_position
		var dist := pos.distance_to(focus)
		if dist > DESPAWN and not main.is_visible_to_camera(pos):
			drivers.erase(d)
			main.remove_car(d.car)
			continue
		# Hopelessly stuck or flipped cars that nobody watches are cleared.
		if (d.car.is_flipped() or d.blocked_time > 25.0) and not main.is_visible_to_camera(pos):
			drivers.erase(d)
			main.remove_car(d.car)
			continue
		# Far cars think less often.
		if dist > 120.0 and Engine.get_physics_frames() % 4 != 0:
			continue
		d.update(delta, obstacles_near(pos))
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = 0.6
		if drivers.size() < max_cars:
			_try_spawn(focus)


func _try_spawn(focus: Vector3) -> void:
	var layout := main.layout
	for attempt in 6:
		var e: Dictionary = layout.edges[_rng.randi() % layout.edges.size()]
		var a: int = e["a"]
		var b: int = e["b"]
		if _rng.randf() < 0.5:
			var t := a
			a = b
			b = t
		var pts := layout.lane_points(a, b)
		var p: Vector3 = pts[0].lerp(pts[1], _rng.randf_range(0.1, 0.8))
		var d := p.distance_to(focus)
		if d < SPAWN_MIN or d > SPAWN_MAX:
			continue
		if main.is_visible_to_camera(p) and d < 150.0:
			continue
		var clear := true
		for c in main.cars:
			if is_instance_valid(c) and c.global_position.distance_to(p) < 12.0:
				clear = false
				break
		if not clear:
			continue
		var dir: Vector3 = (pts[1] - pts[0]).normalized()
		var kind := "sado" if _rng.randf() < 0.5 else "chabuk"
		var cfg := {"paint": Game.PAINTS[_rng.randi() % Game.PAINTS.size()][1], "rims": "steel" if _rng.randf() < 0.65 else "sport"}
		var car := main.spawn_car(kind, Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.z)), p + Vector3(0, 0.5, 0)), cfg)
		car.linear_velocity = dir * 8.0
		var drv := AiDriver.new(car, layout)
		drv.cruise = _rng.randf_range(9.0, 13.0)
		drv.prev_node = a
		drv.cur_node = b
		drv.waypoints.append(pts[1])
		drivers.append(drv)
		return
