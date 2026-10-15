class_name Minimap
extends Control
## Round minimap: real streets from CityLayout, rotated with the camera,
## with the player, police, traffic, the garage and mission targets.

var main: Main
var meters_per_px := 1.1
var _blink := 0.0
var _blocks: Array = []


func _process(delta: float) -> void:
	_blink += delta
	queue_redraw()


func _to_map(world: Vector3, focus: Vector3, yaw: float, centre: Vector2) -> Vector2:
	var d := Vector2(world.x - focus.x, world.z - focus.z) / meters_per_px
	return centre + d.rotated(-yaw)


func _draw() -> void:
	if main == null:
		return
	var size_px := size
	var centre := size_px * 0.5
	var radius := minf(size_px.x, size_px.y) * 0.5
	var focus := main.focus_position()
	var yaw := -main.rig.yaw
	# Ground.
	draw_rect(Rect2(Vector2.ZERO, size_px), Color("8fb27a"))
	# Blocks (pale) under the streets.
	if _blocks.is_empty():
		_blocks = main.layout.blocks()
	for b in _blocks:
		var r: Rect2 = b["rect"]
		var corners := [Vector3(r.position.x, 0, r.position.y), Vector3(r.end.x, 0, r.position.y),
			Vector3(r.end.x, 0, r.end.y), Vector3(r.position.x, 0, r.end.y)]
		var pts := PackedVector2Array()
		for c in corners:
			pts.append(_to_map(c, focus, yaw, centre))
		draw_colored_polygon(pts, Color("d9d2c3"))
	# Streets.
	for e in main.layout.edges:
		var a := _to_map(main.layout.nodes[e["a"]], focus, yaw, centre)
		var b2 := _to_map(main.layout.nodes[e["b"]], focus, yaw, centre)
		var w: float = e["w"] / meters_per_px
		draw_line(a, b2, Color("4e535b"), w + 2.0)
	for e in main.layout.edges:
		var a := _to_map(main.layout.nodes[e["a"]], focus, yaw, centre)
		var b2 := _to_map(main.layout.nodes[e["b"]], focus, yaw, centre)
		draw_line(a, b2, Color("6b7079"), maxf(1.0, e["w"] / meters_per_px - 3.0))
	# Drift pad and garage.
	var dp: Rect2 = main.city.drift_pad
	if dp.size.x > 0:
		var pts2 := PackedVector2Array()
		for c in [Vector3(dp.position.x, 0, dp.position.y), Vector3(dp.end.x, 0, dp.position.y), Vector3(dp.end.x, 0, dp.end.y), Vector3(dp.position.x, 0, dp.end.y)]:
			pts2.append(_to_map(c, focus, yaw, centre))
		draw_colored_polygon(pts2, Color("5b5f66"))
	var g := _to_map(CityLayout.GARAGE_POS, focus, yaw, centre)
	_icon(g, centre, radius, Color("ffd36b"), "G")
	# Cars.
	for c in main.cars:
		if not is_instance_valid(c) or c == main.player.car:
			continue
		var p := _to_map(c.global_position, focus, yaw, centre)
		if p.distance_to(centre) > radius:
			continue
		if c.is_police:
			var col := Color("ff3b3b") if fmod(_blink, 0.5) < 0.25 or not c.siren_on else Color("3b7bff")
			draw_circle(p, 4.5, Color.BLACK)
			draw_circle(p, 3.5, col)
		elif c.has_meta("client"):
			draw_circle(p, 4.5, Color("7a4fb5"))
		elif c == main.my_car:
			draw_circle(p, 4.0, Color("ffffff"))
			draw_circle(p, 2.5, Color("1d6f69"))
		else:
			draw_circle(p, 2.5, Color("e8e8e8"))
	# Mission points (clamped to the rim when far away).
	for mp in main.missions.map_points():
		var p2 := _to_map(mp["pos"], focus, yaw, centre)
		_icon(p2, centre, radius, mp["color"], "")
	# Player arrow (points to where the camera looks: up).
	var heading := 0.0
	if main.player.car:
		heading = -main.player.car.global_rotation.y - yaw
	else:
		heading = -main.player.model.global_rotation.y - yaw
	var tip := Vector2(0, -9).rotated(heading)
	var l := Vector2(-6, 7).rotated(heading)
	var r2 := Vector2(6, 7).rotated(heading)
	draw_colored_polygon(PackedVector2Array([centre + tip, centre + r2, centre + l]), Color.WHITE)
	draw_polyline(PackedVector2Array([centre + tip, centre + r2, centre + l, centre + tip]), Color("1b1c1f"), 1.5)
	# North marker.
	var n := centre + Vector2(0, -radius + 12).rotated(-yaw)
	draw_circle(n, 9, Color("1b1c1f"))
	draw_string(get_theme_default_font(), n + Vector2(-5, 5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)


func _icon(p: Vector2, centre: Vector2, radius: float, col: Color, letter: String) -> void:
	var d := p - centre
	if d.length() > radius - 10:
		p = centre + d.normalized() * (radius - 10)
	draw_circle(p, 7, Color("1b1c1f"))
	draw_circle(p, 5.5, col)
	if letter != "":
		draw_string(get_theme_default_font(), p + Vector2(-4, 5), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("1b1c1f"))
