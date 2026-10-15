class_name CityBuilder
extends Node3D
## Builds the district: ground, streets, blocks, buildings, greenery,
## colliders, the map edge and the far mountains. Also records spots used by
## other systems (pedestrian paths, benches, parked cars, mission points).



const WALL_COLORS := [Color("f1e6cc"), Color("ead9bd"), Color("efd6c8"), Color("f4f2ec"),
	Color("f3e3a8"), Color("f2cfae"), Color("d9e4ea"), Color("e6efe0")]
const ASPHALT := Color("50545b")
const PAVING := Color("d3ccbf")
const CURB := Color("b9b3a8")
const GRASS := Color("7fb85a")
const GRASS_DARK := Color("6aa64c")

var layout := CityLayout.new()
var rng := RandomNumberGenerator.new()
var high_detail := true

## Spots for other systems.
var ped_loops: Array = []            # Array[PackedVector3Array] closed loops on sidewalks
var bench_spots: Array[Transform3D] = []
var stand_spots: Array[Transform3D] = []   # bus stops, shop fronts
var parked_spots: Array[Transform3D] = []
var hide_zones: Array[AABB] = []
var drift_pad := Rect2()

var _colliders: StaticBody3D
var _multi := {}                     # model path -> Array[Transform3D]
var _marks := MeshKit.new()          # road markings + flat ground details
var _slabs := MeshKit.new()


func build(detail := true) -> void:
	high_detail = detail
	rng.seed = 20261015
	_colliders = StaticBody3D.new()
	_colliders.name = "StaticColliders"
	_colliders.collision_layer = 1
	_colliders.collision_mask = 0
	add_child(_colliders)
	_ground()
	_streets()
	for b in layout.blocks():
		_block(b)
	_outer_band()
	_edge_and_horizon()
	_flush_multimeshes()
	var m := MeshInstance3D.new()
	m.name = "Markings"
	m.mesh = _marks.build({"detail": Mats.detail(), "base": Mats.base(0.02)})
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	var s := MeshInstance3D.new()
	s.name = "Sidewalks"
	s.mesh = _slabs.build({"detail": Mats.detail(), "base": Mats.base(0.03)})
	add_child(s)


# --- ground & streets -------------------------------------------------------

func _ground() -> void:
	var k := MeshKit.new()
	k.ground_rect("detail", Vector3(0, 0, 0), CityLayout.HALF * 2 + 40, CityLayout.HALF * 2 + 40, ASPHALT)
	var mi := MeshInstance3D.new()
	mi.name = "Asphalt"
	mi.mesh = k.build({"detail": Mats.detail()})
	add_child(mi)
	_box_collider(Vector3(0, -0.5, 0), Vector3(CityLayout.HALF * 2 + 400, 1.0, CityLayout.HALF * 2 + 400))


func _streets() -> void:
	var white := Color("eeeeea")
	var yellow := Color("f0c44c")
	for e in layout.edges:
		var a: Vector3 = layout.nodes[e["a"]]
		var b: Vector3 = layout.nodes[e["b"]]
		var w: float = e["w"]
		var d := (b - a).normalized()
		var right := Vector3(-d.z, 0, d.x)
		var horizontal := absf(d.x) > 0.5
		var ca := layout.half_width_along(e["a"], not horizontal)
		var cb := layout.half_width_along(e["b"], not horizontal)
		var p0 := a + d * ca
		var p1 := b - d * cb
		var length := (p1 - p0).length()
		var yaw := atan2(d.x, d.z)
		# Edge lines.
		for s: float in [-1.0, 1.0]:
			_strip(p0 + right * s * (w * 0.5 - 0.5), p1 + right * s * (w * 0.5 - 0.5), 0.15, white)
		if w > 15.0:
			# Avenue: double centre line + dashed lane dividers.
			for s: float in [-1.0, 1.0]:
				_strip(p0 + right * s * 0.2, p1 + right * s * 0.2, 0.14, yellow)
				_dashes(p0 + right * s * 4.5, p1 + right * s * 4.5, 3.0, 6.0, 0.14, white)
		else:
			_dashes(p0, p1, 3.0, 5.0, 0.14, white)
		# Zebra crossings and stop lines at both ends.
		for end in [[p0, d], [p1, -d]]:
			var pe: Vector3 = end[0]
			var de: Vector3 = end[1]
			var n := int((w - 1.0) / 1.0)
			for i in n:
				var off := -w * 0.5 + 0.9 + i * 1.0
				_marks.ground_rect("detail", pe + de * 2.2 + right * off + Vector3(0, 0.012, 0), 0.5, 3.0, white, yaw)
			_strip(pe + de * 4.2, pe + de * 4.2 + right * (w * 0.5 - 0.6), 0.35, white, true)
		if length < 1.0:
			continue


func _strip(a: Vector3, b: Vector3, width: float, col: Color, across := false) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.01:
		return
	var yaw := atan2(d.x, d.z)
	var c := (a + b) * 0.5 + Vector3(0, 0.01, 0)
	_marks.ground_rect("detail", c, width, len, col, yaw)


func _dashes(a: Vector3, b: Vector3, dash: float, gap: float, width: float, col: Color) -> void:
	var d := b - a
	var len := d.length()
	var dir := d / len
	var t := gap * 0.5
	while t + dash < len:
		_strip(a + dir * t, a + dir * (t + dash), width, col)
		t += dash + gap


# --- blocks -----------------------------------------------------------------

func _block(b: Dictionary) -> void:
	var r: Rect2 = b["rect"]
	var key: Vector2i = b["key"]
	var cells: Array = b["cells"]
	if key == Vector2i(3, 0):
		_drift_pad(r)
		return
	_slab(r)
	ped_loops.append(_loop(r.grow(-2.0)))
	_street_trees_and_lamps(r)
	var inner := r.grow(-(CityLayout.SIDEWALK + 3.0))
	match key:
		Vector2i(2, 0):
			_park(inner)
		Vector2i(1, 1):
			_shops_north(inner)
		Vector2i(1, 2):
			_garage_block(inner)
		Vector2i(2, 1), Vector2i(3, 2):
			_towers(inner)
		Vector2i(1, 3):
			if cells.size() > 1:
				_big_courtyard(inner)
			else:
				_residential(inner)
		_:
			_residential(inner)


func _slab(r: Rect2) -> void:
	var c := Vector3(r.get_center().x, CityLayout.CURB_H * 0.5, r.get_center().y)
	_slabs.box("detail", c, Vector3(r.size.x, CityLayout.CURB_H, r.size.y), PAVING)
	# Curb stones.
	for e in _rect_edges(r):
		var a: Vector3 = e[0]
		var bb: Vector3 = e[1]
		var mid := (a + bb) * 0.5
		var len := (bb - a).length()
		var along_x := absf(bb.x - a.x) > 0.1
		var size := Vector3(len, CityLayout.CURB_H + 0.03, 0.3) if along_x else Vector3(0.3, CityLayout.CURB_H + 0.03, len)
		_slabs.box("detail", Vector3(mid.x, (CityLayout.CURB_H + 0.03) * 0.5, mid.z), size, CURB)
	_box_collider(c, Vector3(r.size.x, CityLayout.CURB_H, r.size.y))


func _rect_edges(r: Rect2) -> Array:
	var p0 := Vector3(r.position.x, 0, r.position.y)
	var p1 := Vector3(r.end.x, 0, r.position.y)
	var p2 := Vector3(r.end.x, 0, r.end.y)
	var p3 := Vector3(r.position.x, 0, r.end.y)
	return [[p0, p1], [p1, p2], [p2, p3], [p3, p0]]


func _loop(r: Rect2) -> PackedVector3Array:
	var y := CityLayout.CURB_H
	return PackedVector3Array([Vector3(r.position.x, y, r.position.y), Vector3(r.end.x, y, r.position.y),
		Vector3(r.end.x, y, r.end.y), Vector3(r.position.x, y, r.end.y)])


func _street_trees_and_lamps(r: Rect2) -> void:
	for e in _rect_edges(r):
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		var d := (b - a).normalized()
		var outward := Vector3(d.z, 0, -d.x)  # rect is clockwise in xz → this points to the street
		var len := (b - a).length()
		var avenue := absf(a.z) < 15.0 and absf(b.z) < 15.0
		var spacing := 13.0 if avenue else 19.0
		var t := 8.0
		var i := 0
		while t < len - 8.0:
			var p := a + d * t + outward * -1.3 + Vector3(0, CityLayout.CURB_H, 0)
			if _near_crossing(a + d * t):
				t += spacing
				i += 1
				continue
			if i % 3 == 1:
				var lamp := "props/banner_pole" if avenue and i % 6 == 1 else "props/lamp"
				_add_multi(lamp, Transform3D(Basis(Vector3.UP, _yaw_facing(outward)), a + d * t + outward * -0.6 + Vector3(0, CityLayout.CURB_H, 0)))
				_cyl_collider(a + d * t + outward * -0.6, 0.18, 8.0)
			else:
				var tree := "props/tree_poplar" if (avenue or rng.randf() < 0.6) else "props/tree_round"
				var s := rng.randf_range(0.85, 1.15)
				_add_multi(tree, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), p))
				_cyl_collider(p, 0.3, 4.0)
			t += spacing
			i += 1


## Places buildings in a row between xa and xb at depth position `z` (local frame).
func _row(frame: Transform3D, xa: float, xb: float, models: Array, gap_min := 10.0, gap_max := 16.0) -> void:
	var x := xa + rng.randf_range(1.0, 4.0)
	while true:
		var choices: Array = []
		for m in models:
			var fp: Vector2 = _footprint(m)
			if x + fp.x <= xb:
				choices.append(m)
		if choices.is_empty():
			break
		var m: String = choices[rng.randi() % choices.size()]
		var fp2: Vector2 = _footprint(m)
		_building(m, frame * Transform3D(Basis.IDENTITY, Vector3(x + fp2.x * 0.5, CityLayout.CURB_H, 0)), WALL_COLORS[rng.randi() % WALL_COLORS.size()])
		x += fp2.x + rng.randf_range(gap_min, gap_max)


var _fp_cache := {}
func _footprint(model: String) -> Vector2:
	if not _fp_cache.has(model):
		var n := Models.instance(model)
		_fp_cache[model] = n.get_meta("footprint", Vector2(10, 10))
		_fp_cache[model + "_h"] = n.get_meta("height", 10.0)
		n.free()
	return _fp_cache[model]


func _building(model: String, xf: Transform3D, color := Color(-1, 0, 0), collide := true) -> Node3D:
	var n := Models.instance(model)
	n.transform = xf
	add_child(n)
	if color.r >= 0.0:
		Models.tint(n, color, 0.06)
	if collide:
		if n.has_meta("walls"):
			for w in n.get_meta("walls"):
				_box_collider(xf * (w["pos"] as Vector3), w["size"], xf.basis)
		else:
			var fp: Vector2 = n.get_meta("footprint", Vector2(10, 10))
			var h: float = n.get_meta("height", 10.0)
			_box_collider(xf * Vector3(0, h * 0.5, 0), Vector3(fp.x, h, fp.y), xf.basis)
	return n


func _residential(inner: Rect2) -> void:
	var blocks5 := ["buildings/khrushchevka_24", "buildings/khrushchevka_36", "buildings/khrushchevka_48"]
	# North row faces the street to the north (-Z), south row faces +Z.
	var north := Transform3D(Basis.IDENTITY, Vector3(0, 0, inner.position.y + 6.0))
	_row(north, inner.position.x, inner.end.x, blocks5)
	var south := Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, inner.end.y - 6.0))
	_row(south, -inner.end.x, -inner.position.x, blocks5)
	# West side: one short block across, leaving the courtyard open on the east.
	var west := Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3(inner.position.x + 6.0, 0, 0))
	if rng.randf() < 0.7:
		var zc := inner.get_center().y
		_building("buildings/khrushchevka_24", west * Transform3D(Basis.IDENTITY, Vector3(zc + rng.randf_range(-8, 8), CityLayout.CURB_H, 0)), WALL_COLORS[rng.randi() % WALL_COLORS.size()])
	_courtyard(Rect2(inner.position.x + 16, inner.position.y + 18, inner.size.x - 28, inner.size.y - 36))


func _courtyard(c: Rect2) -> void:
	if c.size.x < 10 or c.size.y < 10:
		return
	var y := CityLayout.CURB_H
	var centre := Vector3(c.get_center().x, y, c.get_center().y)
	# Lawn patches with trees and bushes.
	for i in 2:
		var lx := c.position.x + c.size.x * (0.25 + 0.5 * i)
		var lawn := Rect2(lx - c.size.x * 0.18, c.position.y + 3, c.size.x * 0.36, c.size.y - 10)
		_slabs.ground_rect("detail", Vector3(lawn.get_center().x, y + 0.012, lawn.get_center().y), lawn.size.x, lawn.size.y, GRASS)
		for k in 3:
			var p := Vector3(lawn.position.x + rng.randf() * lawn.size.x, y, lawn.position.y + rng.randf() * lawn.size.y)
			var tree := "props/tree_round" if rng.randf() < 0.65 else "props/tree_poplar"
			_add_multi(tree, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p))
			_cyl_collider(p, 0.3, 4.0)
		for k in 3:
			var p2 := Vector3(lawn.position.x + rng.randf() * lawn.size.x, y, lawn.position.y + rng.randf() * lawn.size.y)
			_add_multi("props/bush", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p2))
	# Playground and benches in the middle.
	_add_multi("props/swing", Transform3D(Basis.IDENTITY, centre + Vector3(0, 0, -4)))
	_box_collider(centre + Vector3(0, 1.2, -4), Vector3(3.4, 2.4, 1.2))
	for s: float in [-1.0, 1.0]:
		var bt := Transform3D(Basis(Vector3.UP, PI if s > 0 else 0.0), centre + Vector3(s * 5.0, 0, 3.0))
		_add_multi("props/bench", bt)
		bench_spots.append(bt)
	_add_multi("props/trash_bin", Transform3D(Basis.IDENTITY, centre + Vector3(2.5, 0, 3.5)))
	# Parking spots along the courtyard edge.
	for i in 2:
		var px := c.position.x + 6 + i * 6.0
		parked_spots.append(Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(px, y + 0.4, c.end.y - 2)))


func _towers(inner: Rect2) -> void:
	var models := ["buildings/tower_12", "buildings/tower_16", "buildings/tower_9"]
	var n := 3
	for i in n:
		var t := (i + 0.5) / n
		var x := inner.position.x + inner.size.x * t
		var m: String = models[i % models.size()]
		var fp := _footprint(m)
		var z := inner.position.y + fp.y * 0.5 + 2 if i % 2 == 0 else inner.end.y - fp.y * 0.5 - 2
		var yaw := 0.0 if i % 2 == 0 else PI
		_building(m, Transform3D(Basis(Vector3.UP, yaw), Vector3(x, CityLayout.CURB_H, z)), WALL_COLORS[rng.randi() % WALL_COLORS.size()])
	var plaza := Rect2(inner.position.x + 10, inner.get_center().y - 14, inner.size.x - 20, 28)
	_courtyard(plaza)


func _shops_north(inner: Rect2) -> void:
	# Shops line the avenue on the south edge of this block (fronts face +Z).
	var x := inner.position.x + 4.0
	for m in ["buildings/shop_dukon", "buildings/chaikhana", "buildings/kiosk", "buildings/shop_non", "buildings/pharmacy"]:
		var fp := _footprint(m)
		var xf := Transform3D(Basis(Vector3.UP, PI), Vector3(x + fp.x * 0.5, CityLayout.CURB_H, inner.end.y - fp.y * 0.5 - 1.0))
		_building(m, xf, Color("f2efe6"))
		stand_spots.append(Transform3D(Basis(Vector3.UP, 0.0), xf * Vector3(rng.randf_range(-2, 2), 0, -fp.y * 0.5 - 2.5)))
		x += fp.x + 5.0
	var north := Transform3D(Basis.IDENTITY, Vector3(0, 0, inner.position.y + 6.0))
	_row(north, inner.position.x, inner.end.x, ["buildings/khrushchevka_36", "buildings/khrushchevka_24"])
	_courtyard(Rect2(inner.position.x + 14, inner.position.y + 18, inner.size.x - 24, inner.size.y - 44))


func _garage_block(inner: Rect2) -> void:
	_building("buildings/garage", Transform3D(Basis.IDENTITY, Vector3(CityLayout.GARAGE_POS.x, CityLayout.CURB_H, CityLayout.GARAGE_POS.z)), Color("eae3d3"))
	# Asphalt apron in front of the garage.
	_slabs.ground_rect("detail", Vector3(CityLayout.GARAGE_POS.x, CityLayout.CURB_H + 0.01, 16.0), 16.0, 12.0, Color("6a6e74"))
	var x := -76.0
	for m in ["buildings/shop_dukon", "buildings/shop_non", "buildings/pharmacy"]:
		var fp := _footprint(m)
		var xf := Transform3D(Basis.IDENTITY, Vector3(x + fp.x * 0.5, CityLayout.CURB_H, inner.position.y + fp.y * 0.5 + 1.0))
		_building(m, xf, Color("f2efe6"))
		stand_spots.append(Transform3D(Basis(Vector3.UP, PI), xf * Vector3(rng.randf_range(-2, 2), 0, -fp.y * 0.5 - 2.5)))
		x += fp.x + 6.0
	# Bus stop on the avenue sidewalk.
	var bs := Transform3D(Basis(Vector3.UP, PI), Vector3(-14.0, CityLayout.CURB_H, 11.8))
	_add_multi("props/bus_stop", bs)
	_box_collider(bs * Vector3(0, 1.4, 0.62), Vector3(4.8, 2.8, 0.2), bs.basis)
	for i in 3:
		stand_spots.append(Transform3D(Basis(Vector3.UP, PI), bs * Vector3(-1.5 + i * 1.5, 0, 0.0)))
	var south := Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, inner.end.y - 6.0))
	_row(south, -inner.end.x, -inner.position.x, ["buildings/khrushchevka_36", "buildings/khrushchevka_24"])
	_courtyard(Rect2(inner.position.x + 30, inner.position.y + 34, inner.size.x - 40, inner.size.y - 52))


func _park(inner: Rect2) -> void:
	var c := Vector3(inner.get_center().x, CityLayout.CURB_H, inner.get_center().y)
	_slabs.ground_rect("detail", c + Vector3(0, 0.012, 0), inner.size.x, inner.size.y, GRASS)
	# Paved cross paths.
	_slabs.ground_rect("detail", c + Vector3(0, 0.02, 0), 8.0, inner.size.y, PAVING.lightened(0.05))
	_slabs.ground_rect("detail", c + Vector3(0, 0.02, 0), inner.size.x, 8.0, PAVING.lightened(0.05))
	_slabs.cylinder("detail", c + Vector3(0, 0.03, 0), 14.0, 0.04, 16, PAVING.lightened(0.05))
	_building("props/fountain", Transform3D(Basis.IDENTITY, c), Color(-1, 0, 0))
	_building("buildings/rotunda", Transform3D(Basis.IDENTITY, c + Vector3(inner.size.x * 0.3, 0, -inner.size.y * 0.25)), Color("f1ece0"))
	# Carved walls along the avenue-facing and west edges, with gaps for paths.
	for i in 2:
		var x := inner.position.x + 14 + i * (inner.size.x - 28)
		_building("buildings/ornament_wall", Transform3D(Basis.IDENTITY, Vector3(x, CityLayout.CURB_H, inner.end.y - 1.0)), Color("e9dcc0"))
	for i in 18:
		var p := Vector3(inner.position.x + rng.randf() * inner.size.x, CityLayout.CURB_H, inner.position.y + rng.randf() * inner.size.y)
		if absf(p.x - c.x) < 8 or absf(p.z - c.z) < 8 or p.distance_to(c) < 16:
			continue
		_add_multi("props/tree_round", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p))
		_cyl_collider(p, 0.3, 4.0)
	for a in 8:
		var ang := TAU * a / 8.0 + 0.39
		var bt := Transform3D(Basis(Vector3.UP, -ang + PI / 2.0), c + Vector3(cos(ang), 0, sin(ang)) * 11.5)
		_add_multi("props/bench", bt)
		bench_spots.append(bt)
	ped_loops.append(_loop(Rect2(c.x - 9, c.z - 9, 18, 18)))


func _big_courtyard(inner: Rect2) -> void:
	var blocks5 := ["buildings/khrushchevka_36", "buildings/khrushchevka_48"]
	_row(Transform3D(Basis.IDENTITY, Vector3(0, 0, inner.position.y + 6.0)), inner.position.x, inner.end.x, blocks5, 16.0, 22.0)
	_row(Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, inner.end.y - 6.0)), -inner.end.x, -inner.position.x, blocks5, 16.0, 22.0)
	var c := Vector3(inner.get_center().x, CityLayout.CURB_H, inner.get_center().y)
	var cp := _building("buildings/covered_parking", Transform3D(Basis.IDENTITY, c), Color(-1, 0, 0))
	hide_zones.append(AABB(c + Vector3(-15, -1, -8), Vector3(30, 6, 16)))
	for i in 3:
		parked_spots.append(Transform3D(Basis.IDENTITY, c + Vector3(-7.5 + i * 5, 0.4, 3)))
	_courtyard(Rect2(inner.position.x + 8, c.z - 20, 40, 40))
	_courtyard(Rect2(inner.end.x - 48, c.z - 20, 40, 40))
	if cp == null:
		return


func _drift_pad(r: Rect2) -> void:
	drift_pad = r.grow(-CityLayout.SIDEWALK)
	# Sidewalk ring with two entrances (west street and avenue).
	var sw := CityLayout.SIDEWALK
	var gate_w := 18.0
	var gz := -70.0
	var gx := 195.0
	_slab(Rect2(r.position.x, r.position.y, r.size.x, sw))                           # north
	_slab(Rect2(r.end.x - sw, r.position.y + sw, sw, r.size.y - sw * 2))              # east
	_slab(Rect2(r.position.x, r.end.y - sw, gx - gate_w * 0.5 - r.position.x, sw))   # south-west part
	_slab(Rect2(gx + gate_w * 0.5, r.end.y - sw, r.end.x - gx - gate_w * 0.5, sw))   # south-east part
	_slab(Rect2(r.position.x, r.position.y + sw, sw, gz - gate_w * 0.5 - r.position.y - sw))
	_slab(Rect2(r.position.x, gz + gate_w * 0.5, sw, r.end.y - sw - gz - gate_w * 0.5))
	var c := Vector3(drift_pad.get_center().x, 0, drift_pad.get_center().y)
	# Fresh dark asphalt, painted circles and tyre stacks.
	_marks.ground_rect("detail", c + Vector3(0, 0.006, 0), drift_pad.size.x, drift_pad.size.y, Color("3f4248"))
	for ring in [[c + Vector3(0, 0, -60), 22.0], [c + Vector3(0, 0, 50), 18.0]]:
		var rc: Vector3 = ring[0]
		var rr: float = ring[1]
		for i in 32:
			if i % 2 == 0:
				var a0 := TAU * i / 32.0
				var a1 := TAU * (i + 1) / 32.0
				_strip(rc + Vector3(cos(a0), 0.004, sin(a0)) * rr, rc + Vector3(cos(a1), 0.004, sin(a1)) * rr, 0.3, Color("f2c14e"))
		_add_multi("props/tyre_stack", Transform3D(Basis.IDENTITY, rc))
		_cyl_collider(rc, 0.45, 1.0)
	for i in 10:
		var p := c + Vector3(-40 + i * 9, 0, -5)
		_add_multi("props/cone", Transform3D(Basis.IDENTITY, p))
	# Low barriers of tyres along the north and east edges.
	for i in 12:
		var p2 := Vector3(drift_pad.position.x + 6 + i * 9.5, 0, drift_pad.position.y + 1.5)
		_add_multi("props/tyre_stack", Transform3D(Basis.IDENTITY, p2))
		_cyl_collider(p2, 0.45, 1.0)
	_label_floor("ДРИФТ", c + Vector3(0, 0.02, -5))


func _label_floor(text: String, pos: Vector3) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 256
	l.pixel_size = 0.04
	l.modulate = Color(1, 1, 1, 0.75)
	l.rotation = Vector3(-PI / 2, 0, 0)
	l.position = pos
	l.shaded = false
	add_child(l)


# --- outer band, edge of the map, horizon ------------------------------------

func _outer_band() -> void:
	var o := CityLayout.XS[CityLayout.XS.size() - 1] + CityLayout.ROAD_W * 0.5
	var strips := [Rect2(-CityLayout.HALF, -CityLayout.HALF, CityLayout.HALF * 2, CityLayout.HALF - o), Rect2(-CityLayout.HALF, o, CityLayout.HALF * 2, CityLayout.HALF - o),
		Rect2(-CityLayout.HALF, -o, CityLayout.HALF - o, o * 2), Rect2(o, -o, CityLayout.HALF - o, o * 2)]
	for i in strips.size():
		var r: Rect2 = strips[i]
		_slab(r)
		_street_trees_and_lamps_outer(r, i)
	# Boundary walls.
	for s: float in [-1.0, 1.0]:
		_box_collider(Vector3(s * (CityLayout.HALF + 0.5), 5, 0), Vector3(1, 10, CityLayout.HALF * 2 + 2))
		_box_collider(Vector3(0, 5, s * (CityLayout.HALF + 0.5)), Vector3(CityLayout.HALF * 2 + 2, 10, 1))
	# Fence along the very edge.
	var step := 4.0
	var n := int(CityLayout.HALF * 2 / step)
	for i in n:
		var t := -CityLayout.HALF + (i + 0.5) * step
		for s: float in [-1.0, 1.0]:
			_add_multi("props/fence", Transform3D(Basis.IDENTITY, Vector3(t, CityLayout.CURB_H, s * (CityLayout.HALF - 0.3))))
			_add_multi("props/fence", Transform3D(Basis(Vector3.UP, PI / 2), Vector3(s * (CityLayout.HALF - 0.3), CityLayout.CURB_H, t)))


func _street_trees_and_lamps_outer(r: Rect2, side: int) -> void:
	# Rows of poplars between the ring road and the edge fence, plus a few blocks.
	var horizontal := side < 2
	var count := int((r.size.x if horizontal else r.size.y) / 11.0)
	for i in count:
		var t := (i + 0.5) / count
		for row in 2:
			var p: Vector3
			if horizontal:
				var z := r.position.y + (3.0 + row * 6.0 if side == 1 else r.size.y - 3.0 - row * 6.0)
				p = Vector3(r.position.x + r.size.x * t, CityLayout.CURB_H, z)
			else:
				var x := r.position.x + (3.0 + row * 6.0 if side == 3 else r.size.x - 3.0 - row * 6.0)
				p = Vector3(x, CityLayout.CURB_H, r.position.y + r.size.y * t)
			if row == 1 and i % 2 == 0:
				continue
			_add_multi("props/tree_poplar", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.9, 1.25)), p))
			_cyl_collider(p, 0.3, 4.0)
	for i in 3:
		var t2 := (i + 0.5) / 3.0
		var pos: Vector3
		var yaw := 0.0
		if horizontal:
			pos = Vector3(r.position.x + r.size.x * t2, CityLayout.CURB_H, r.get_center().y + (-5.0 if side == 0 else 5.0))
			yaw = 0.0 if side == 1 else PI
		else:
			pos = Vector3(r.get_center().x + (-5.0 if side == 2 else 5.0), CityLayout.CURB_H, r.position.y + r.size.y * t2)
			yaw = -PI / 2 if side == 2 else PI / 2
		_building("buildings/khrushchevka_24", Transform3D(Basis(Vector3.UP, yaw), pos), WALL_COLORS[rng.randi() % WALL_COLORS.size()])


func _edge_and_horizon() -> void:
	# Green hills rising beyond the fence, coarse and faceted.
	var k := MeshKit.new()
	var cell := 40.0
	var ext := 1400.0
	var n := int(ext * 2 / cell)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.004
	var hfun := func(x: float, z: float) -> float:
		var d := maxf(absf(x), absf(z))
		var rise := clampf((d - CityLayout.HALF - 8.0) / 160.0, 0.0, 1.0)
		rise = rise * rise * (3.0 - 2.0 * rise)
		return rise * (28.0 + noise.get_noise_2d(x, z) * 26.0) + maxf(0.0, d - 600.0) * 0.06 - 0.3
	for iz in n:
		for ix in n:
			var x0 := -ext + ix * cell
			var z0 := -ext + iz * cell
			if x0 >= -CityLayout.HALF and x0 + cell <= CityLayout.HALF and z0 >= -CityLayout.HALF and z0 + cell <= CityLayout.HALF:
				continue
			var p := [Vector3(x0, 0, z0), Vector3(x0 + cell, 0, z0), Vector3(x0 + cell, 0, z0 + cell), Vector3(x0, 0, z0 + cell)]
			for q in 4:
				var v: Vector3 = p[q]
				v.y = hfun.call(v.x, v.z)
				p[q] = v
			var avg: float = (p[0].y + p[1].y + p[2].y + p[3].y) * 0.25
			var col := GRASS.lerp(Color("9c9a5a"), clampf(avg / 50.0, 0.0, 1.0))
			if (ix + iz) % 2 == 0:
				col = col.darkened(0.04)
			k.quad_facing("detail", p[0], p[3], p[2], p[1], Vector3.UP, col)
	# Far mountains.
	var mrng := RandomNumberGenerator.new()
	mrng.seed = 99
	for i in 30:
		var a := TAU * i / 30.0 + mrng.randf_range(-0.05, 0.05)
		var dist := mrng.randf_range(1500, 1900)
		var base := Vector3(cos(a) * dist, 0, sin(a) * dist)
		var h := mrng.randf_range(260, 520) * (1.25 if sin(a) < -0.3 else 1.0)
		var rad := mrng.randf_range(380, 560)
		var col: Color = [Color("8f7d86"), Color("9a8576"), Color("85778f")][i % 3]
		_mountain(k, base, rad, h, col, mrng)
	# Landmarks in the distance (tower on the hills to the north).
	var tower := Models.instance("buildings/tv_tower")
	tower.position = Vector3(160, hfun.call(160, -720), -720)
	add_child(tower)
	var mi := MeshInstance3D.new()
	mi.name = "Horizon"
	mi.mesh = k.build({"detail": Mats.detail()})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_distant_city(hfun)
	_clouds()


func _mountain(k: MeshKit, base: Vector3, rad: float, h: float, col: Color, r: RandomNumberGenerator) -> void:
	var seg := 7
	var ring: Array[Vector3] = []
	for i in seg:
		var a := TAU * i / seg + r.randf_range(-0.2, 0.2)
		ring.append(base + Vector3(cos(a), 0, sin(a)) * rad * r.randf_range(0.7, 1.1))
	var mid: Array[Vector3] = []
	for i in seg:
		var a2 := TAU * (i + 0.5) / seg
		mid.append(base + Vector3(cos(a2), 0, sin(a2)) * rad * 0.45 + Vector3(0, h * r.randf_range(0.45, 0.65), 0))
	var tip := base + Vector3(r.randf_range(-40, 40), h, r.randf_range(-40, 40))
	for i in seg:
		var j := (i + 1) % seg
		var c2 := col.darkened(0.08 * float(i % 2))
		_tri_out(k, ring[i], ring[j], mid[i], (ring[i] + ring[j]) * 0.5 - base, c2)
		var top_col := col.lightened(0.12)
		_tri_up(k, mid[i], mid[j], tip, top_col)
		_tri_up(k, ring[j], mid[j], mid[i], col.darkened(0.04))


func _tri_out(k: MeshKit, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, col: Color) -> void:
	if (b - a).cross(c - a).dot(outward) > 0:
		k.tri("detail", a, b, c, col)
	else:
		k.tri("detail", a, c, b, col)


func _tri_up(k: MeshKit, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	if (b - a).cross(c - a).y > 0:
		k.tri("detail", a, b, c, col)
	else:
		k.tri("detail", a, c, b, col)


func _distant_city(hfun: Callable) -> void:
	var mesh := Models.mesh("buildings/khrushchevka_36")
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	var xfs: Array[Transform3D] = []
	var cols: Array[Color] = []
	var r := RandomNumberGenerator.new()
	r.seed = 3
	for i in 70:
		var a := r.randf() * TAU
		var d := r.randf_range(380, 760)
		var p := Vector3(cos(a) * d, 0, sin(a) * d)
		if maxf(absf(p.x), absf(p.z)) < CityLayout.HALF + 60:
			continue
		p.y = hfun.call(p.x, p.z) - 0.5
		var s := r.randf_range(0.8, 1.6)
		xfs.append(Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(s, r.randf_range(0.8, 2.2), s)), p))
		cols.append(WALL_COLORS[r.randi() % WALL_COLORS.size()])
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "DistantCity"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _clouds() -> void:
	var k := MeshKit.new()
	var r := RandomNumberGenerator.new()
	r.seed = 42
	for i in 16:
		var a := r.randf() * TAU
		var d := r.randf_range(700, 1300)
		var c := Vector3(cos(a) * d, r.randf_range(260, 380), sin(a) * d)
		for j in 4:
			k.ball("detail", c + Vector3(r.randf_range(-60, 60), r.randf_range(-8, 12), r.randf_range(-25, 25)), Vector3(r.randf_range(40, 70), r.randf_range(18, 28), r.randf_range(30, 45)), Color("ffffff"), 0.1, r)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1, 1, 1)
	var mi := MeshInstance3D.new()
	mi.name = "Clouds"
	mi.mesh = k.build({"detail": m})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# --- helpers ------------------------------------------------------------------

## Keeps trees and lamps out of the zebra crossings at the block corners.
func _near_crossing(p: Vector3) -> bool:
	for n in layout.nodes:
		if absf(p.x - n.x) < 16.0 and absf(p.z - n.z) < 16.0:
			return true
	return false


func _yaw_facing(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


func _add_multi(path: String, xf: Transform3D) -> void:
	if not _multi.has(path):
		_multi[path] = []
	_multi[path].append(xf)


func _flush_multimeshes() -> void:
	for path in _multi:
		var list: Array = _multi[path]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = Models.mesh(path)
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = path.get_file().to_pascal_case() + "s"
		mmi.multimesh = mm
		add_child(mmi)
	_multi.clear()


func _box_collider(center: Vector3, size: Vector3, basis := Basis.IDENTITY) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = Transform3D(basis.orthonormalized(), center)
	_colliders.add_child(cs)


func _cyl_collider(base: Vector3, radius: float, height: float) -> void:
	var cs := CollisionShape3D.new()
	var c := CylinderShape3D.new()
	c.radius = radius
	c.height = height
	cs.shape = c
	cs.position = Vector3(base.x, CityLayout.CURB_H + height * 0.5, base.z)
	_colliders.add_child(cs)
