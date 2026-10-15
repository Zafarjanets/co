class_name AiDriver
extends RefCounted
## Drives a Car through the same controls the player uses.
##
## lane  – cruise along right-hand lanes, random turns at junctions
## chase – follow the street graph to a target, then go straight for it
## goto  – drive along the street graph to a point, then fall back to lane

var car: Car
var layout: CityLayout
var mode := "lane"
var cruise := 11.0
var waypoints: Array[Vector3] = []
var prev_node := -1
var cur_node := -1
var target := Vector3.ZERO
var target_vel := Vector3.ZERO
var direct := false               # chase: aim straight at the target
var blocked_time := 0.0
var _reverse := 0.0
var _reverse_steer := 0.0
var _replan := 0.0
var _rng := RandomNumberGenerator.new()


func _init(c: Car, l: CityLayout) -> void:
	car = c
	layout = l
	_rng.randomize()
	car.driver = "ai"


## Start cruising from the closest lane.
func start_lane() -> void:
	mode = "lane"
	var rp := layout.nearest_road_point(car.global_position, -car.global_basis.z)
	prev_node = rp["a"]
	cur_node = rp["b"]
	waypoints.clear()
	var pts := layout.lane_points(prev_node, cur_node)
	waypoints.append(pts[1])


func chase(pos: Vector3, vel: Vector3, can_see: bool) -> void:
	mode = "chase"
	target = pos
	target_vel = vel
	direct = can_see and car.global_position.distance_to(pos) < 60.0


func goto(pos: Vector3) -> void:
	mode = "goto"
	target = pos
	direct = false
	_replan = 0.0


func update(delta: float, obstacles: Array) -> void:
	if car == null or not is_instance_valid(car) or car.driver != "ai":
		return
	var pos := car.global_position
	var fwd := -car.global_basis.z
	var speed := car.forward_speed
	var desired_speed := cruise
	var aim := pos + fwd * 10.0

	match mode:
		"lane":
			if waypoints.size() < 2:
				_extend_route()
			aim = _follow_waypoints(pos, speed)
			desired_speed = _corner_speed(pos, cruise)
		"chase", "goto":
			_replan -= delta
			var dist := pos.distance_to(target)
			if mode == "chase" and direct:
				# Lead the target a little to cut it off.
				var lead := clampf(dist / 30.0, 0.0, 1.2)
				aim = target + target_vel * lead
				desired_speed = 48.0 if dist > 25.0 else maxf(target_vel.length() + 6.0, 10.0)
				waypoints.clear()
			else:
				if _replan <= 0.0 or waypoints.is_empty():
					_plan_to(target)
					_replan = 1.5
				aim = _follow_waypoints(pos, speed)
				desired_speed = _corner_speed(pos, 40.0 if mode == "chase" else 22.0)
				if mode == "goto" and dist < 15.0:
					start_lane()

	# Obstacles ahead (cars, people) for civilians; police only avoid at low speed.
	var brake_for := INF
	if mode == "lane":
		var inv := car.global_transform.affine_inverse()
		for o in obstacles:
			var op: Vector3 = o
			if op.distance_squared_to(pos) > 900.0:
				continue
			var lp := inv * op
			if lp.z < -1.0 and absf(lp.x) < 2.0 + clampf(-lp.z * 0.06, 0.0, 1.0):
				brake_for = minf(brake_for, -lp.z)
		var safe := 7.0 + maxf(speed, 0.0) * 0.9
		if brake_for < safe:
			desired_speed = minf(desired_speed, clampf((brake_for - 5.0) * 0.8, 0.0, cruise))
	if brake_for < 6.0:
		blocked_time += delta
	else:
		blocked_time = maxf(0.0, blocked_time - delta)

	# Steering towards the aim point.
	var local := car.global_transform.affine_inverse() * aim
	var ang := atan2(-local.x, -local.z)
	var lock: float = car.spec["steer"] / (1.0 + absf(speed) * 0.065)
	var steer := clampf(ang / maxf(lock, 0.05) * 0.9, -1.0, 1.0)
	var thr := 0.0
	var brk := 0.0
	var err := desired_speed - speed
	if err > 0.0:
		thr = clampf(err * 0.25 + 0.15, 0.0, 1.0)
		if absf(ang) > 1.2 and speed > 6.0:
			thr = 0.2
	else:
		brk = clampf(-err * 0.18, 0.0, 1.0)
	if desired_speed < 0.5 and speed < 0.5:
		thr = 0.0
		brk = 0.0

	# Unstick: back up with the wheels turned the other way.
	if _reverse > 0.0:
		_reverse -= delta
		car.set_controls(0.0, 0.8, _reverse_steer, false)
		return
	if car.stuck_time > 1.6 and (mode != "lane" or brake_for > 8.0):
		_reverse = 1.3
		_reverse_steer = -signf(steer) if absf(steer) > 0.1 else (1.0 if _rng.randf() < 0.5 else -1.0)
		car.stuck_time = 0.0
	car.set_controls(thr, brk, steer, false)


func _follow_waypoints(pos: Vector3, speed: float) -> Vector3:
	var reach := 4.0 + absf(speed) * 0.25
	while not waypoints.is_empty():
		var wp := waypoints[0]
		var to := Vector2(wp.x - pos.x, wp.z - pos.z)
		var fwd2 := Vector2(-car.global_basis.z.x, -car.global_basis.z.z)
		if to.length() < reach or (to.length() < 14.0 and to.dot(fwd2) < 0.0):
			waypoints.remove_at(0)
			if mode == "lane" and waypoints.size() < 2:
				_extend_route()
		else:
			break
	if waypoints.is_empty():
		return target if mode != "lane" else pos - car.global_basis.z * 10.0
	# Look a bit past the next point for smoother lines.
	var wp0 := waypoints[0]
	if waypoints.size() > 1 and Vector2(wp0.x - pos.x, wp0.z - pos.z).length() < 9.0:
		return wp0.lerp(waypoints[1], 0.35)
	return wp0


func _corner_speed(pos: Vector3, top: float) -> float:
	if waypoints.size() < 2:
		return top
	var a := waypoints[0] - pos
	var b := waypoints[1] - waypoints[0]
	a.y = 0
	b.y = 0
	if a.length() < 0.1 or b.length() < 0.1:
		return top
	var turn := a.angle_to(b)
	var d := a.length()
	if turn > 0.5 and d < 30.0:
		return lerpf(top, 7.5 if mode == "lane" else 13.0, clampf((30.0 - d) / 20.0, 0.0, 1.0))
	return top


## Lane mode: pick the next street at the junction we're heading to.
func _extend_route() -> void:
	if cur_node < 0:
		start_lane()
		return
	var options: Array = layout.neighbours(cur_node).duplicate()
	if options.size() > 1:
		options.erase(prev_node)
	var nxt: int = options[_rng.randi() % options.size()]
	var pts := layout.lane_points(cur_node, nxt)
	waypoints.append(pts[0])
	waypoints.append(pts[1])
	prev_node = cur_node
	cur_node = nxt


func _plan_to(dest: Vector3) -> void:
	waypoints.clear()
	var from := layout.nearest_node(car.global_position)
	var to := layout.nearest_node(dest)
	var path := layout.route(from, to)
	# Skip the first junction if we're already past it.
	if path.size() > 1:
		var p0 := layout.nodes[path[0]]
		var p1 := layout.nodes[path[1]]
		if (car.global_position - p0).dot(p1 - p0) > 0.0:
			path.remove_at(0)
	for i in path.size():
		if i + 1 < path.size():
			var pts := layout.lane_points(path[i], path[i + 1])
			waypoints.append(pts[0])
			waypoints.append(pts[1])
		else:
			waypoints.append(layout.nodes[path[i]])
	waypoints.append(dest)
	if path.size() >= 2:
		prev_node = path[path.size() - 2]
		cur_node = path[path.size() - 1]
