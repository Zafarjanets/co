class_name PropBuilder
extends RefCounted
## Buildings, trees and street furniture of the district, all built from code.
##
## Buildings have their origin at the centre of the footprint on the ground and
## face -Z (entrances / shop fronts). Their main walls use the "paint" surface
## so the city can tint each instance. Metadata "footprint" (Vector2, x/z size)
## and "height" describe the collision box.

const GLASS := Color("3e5874")
const GLASS_LIT := Color("5d7d9c")
const FRAME := Color("f6f3ea")
const ROOF := Color("8d8a85")
const CONCRETE := Color("c9c4b8")
const DARK := Color("2a2b2f")
const WOOD := Color("8a5a35")
const METAL := Color("4c5560")
const LEAF := Color("4f9a3c")
const LEAF_DARK := Color("3c7f31")
const POPLAR := Color("3f8a35")
const TRUNK := Color("7a5a3c")

const CATALOG := [
	"buildings/khrushchevka_24", "buildings/khrushchevka_36", "buildings/khrushchevka_48",
	"buildings/tower_9", "buildings/tower_12", "buildings/tower_16",
	"buildings/shop_dukon", "buildings/shop_non", "buildings/chaikhana", "buildings/pharmacy",
	"buildings/garage", "buildings/ornament_wall", "buildings/rotunda", "buildings/tv_tower",
	"buildings/covered_parking",
	"props/tree_poplar", "props/tree_round", "props/bush", "props/lamp", "props/banner_pole",
	"props/bench", "props/bus_stop", "props/fence", "props/trash_bin", "props/cone",
	"props/tyre_stack", "props/fountain", "props/swing", "props/kiosk",
]


static func build(key: String) -> Node3D:
	var name := key.get_file()
	match name:
		"khrushchevka_24": return apartment(name, 24.0, 12.0, 5, true)
		"khrushchevka_36": return apartment(name, 36.0, 12.0, 5, true)
		"khrushchevka_48": return apartment(name, 48.0, 12.0, 5, true)
		"tower_9": return apartment(name, 30.0, 14.0, 9, false)
		"tower_12": return apartment(name, 24.0, 18.0, 12, false)
		"tower_16": return apartment(name, 20.0, 20.0, 16, false)
		"shop_dukon": return shop(name, "ДУКОН", Color("2fb3a8"), 14.0, 9.0)
		"shop_non": return shop(name, "НОН", Color("e0a03a"), 10.0, 8.0)
		"chaikhana": return chaikhana(name)
		"pharmacy": return shop(name, "ДОРУХОНА", Color("4fb06a"), 11.0, 8.0)
		"garage": return garage(name)
		"ornament_wall": return ornament_wall(name)
		"rotunda": return rotunda(name)
		"tv_tower": return tv_tower(name)
		"covered_parking": return covered_parking(name)
		"tree_poplar": return tree_poplar(name)
		"tree_round": return tree_round(name)
		"bush": return bush(name)
		"lamp": return lamp(name, false)
		"banner_pole": return lamp(name, true)
		"bench": return bench(name)
		"bus_stop": return bus_stop(name)
		"fence": return fence(name)
		"trash_bin": return trash_bin(name)
		"cone": return cone(name)
		"tyre_stack": return tyre_stack(name)
		"fountain": return fountain(name)
		"swing": return swing(name)
		"kiosk": return kiosk(name)
	push_error("unknown prop " + key)
	return Node3D.new()


# --- helpers ---------------------------------------------------------------

static func _node(name: String, kit: MeshKit, outline := 0.05, paint := Color.WHITE) -> Node3D:
	var root := Node3D.new()
	root.name = name.to_pascal_case()
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = kit.build(Mats.for_model(outline, paint))
	root.add_child(mi)
	mi.owner = root
	return root


static func _label(root: Node3D, text: String, pos: Vector3, size: int, col: Color, yaw := 0.0) -> void:
	var l := Label3D.new()
	l.name = "Sign"
	l.text = text
	l.font_size = size
	l.pixel_size = 0.01
	l.modulate = col
	l.outline_modulate = Color(0, 0, 0, 0.35)
	l.outline_size = 6
	l.position = pos
	l.rotation.y = yaw
	l.double_sided = false
	l.shaded = false
	root.add_child(l)
	l.owner = root


static func _meta(root: Node3D, footprint: Vector2, height: float) -> Node3D:
	root.set_meta("footprint", footprint)
	root.set_meta("height", height)
	return root


static func _window(kit: MeshKit, center: Vector3, w: float, h: float, outward: Vector3, lit := false) -> void:
	var side := outward.cross(Vector3.UP).normalized()
	var o := outward * 0.03
	var fw := side * (w * 0.5 + 0.08)
	var fh := Vector3(0, h * 0.5 + 0.08, 0)
	kit.quad_facing("detail", center + o - fw - fh, center + o + fw - fh, center + o + fw + fh, center + o - fw + fh, outward, FRAME)
	var gw := side * (w * 0.5)
	var gh := Vector3(0, h * 0.5, 0)
	var g := center + outward * 0.05
	kit.quad_facing("detail", g - gw - gh, g + gw - gh, g + gw + gh, g - gw + gh, outward, GLASS_LIT if lit else GLASS)
	# window cross bar
	var bar := center + outward * 0.06
	kit.quad_facing("detail", bar - side * 0.035 - gh, bar + side * 0.035 - gh, bar + side * 0.035 + gh, bar - side * 0.035 + gh, outward, FRAME)


# --- apartment blocks ------------------------------------------------------

## Soviet-era panel block: `floors` storeys, entrances and balconies at the front.
static func apartment(name: String, length: float, depth: float, floors: int, balconies: bool) -> Node3D:
	var kit := MeshKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	var fh := 3.0
	var h := floors * fh + 0.6
	var hl := length * 0.5
	var hd := depth * 0.5
	# Plinth, walls, parapet.
	kit.box("base", Vector3(0, 0.3, 0), Vector3(length + 0.3, 0.6, depth + 0.3), Color("9c968c"))
	kit.box("paint", Vector3(0, 0.6 + (h - 0.6) * 0.5, 0), Vector3(length, h - 0.6, depth), Color.WHITE)
	kit.box("base", Vector3(0, h + 0.25, 0), Vector3(length + 0.25, 0.5, depth + 0.25), Color("d8d2c6"))
	kit.box("detail", Vector3(0, h + 0.51, 0), Vector3(length - 0.4, 0.02, depth - 0.4), ROOF)
	# Roof clutter.
	for i in maxi(1, int(length / 14.0)):
		var x := -hl + 6.0 + i * 14.0
		kit.box("base", Vector3(x, h + 1.1, rng.randf_range(-1.5, 1.5)), Vector3(2.4, 1.2, 2.4), Color("b8b2a6"))
	kit.cylinder("base", Vector3(hl - 4.0, h + 1.6, 1.5), 0.08, 2.2, 6, METAL)
	# Horizontal panel seams every floor.
	for f in range(1, floors):
		var y := 0.6 + f * fh
		for s: float in [-1.0, 1.0]:
			kit.quad_facing("detail", Vector3(-hl, y - 0.05, s * (hd + 0.01)), Vector3(hl, y - 0.05, s * (hd + 0.01)), Vector3(hl, y + 0.05, s * (hd + 0.01)), Vector3(-hl, y + 0.05, s * (hd + 0.01)), Vector3(0, 0, s), Color(0, 0, 0, 1).lerp(Color.WHITE, 0.82))
	var cols := int(length / 3.2)
	var col_w := length / cols
	var entrances: Array[int] = []
	if floors <= 5:
		var n_ent := maxi(1, int(length / 14.0))
		for e in n_ent:
			entrances.append(int((e + 0.5) * cols / n_ent))
	else:
		entrances.append(cols / 2)
	for f in floors:
		var y := 0.6 + f * fh + 1.6
		for c in cols:
			var x := -hl + (c + 0.5) * col_w
			var lit := rng.randf() < 0.12
			# back side: plain windows
			_window(kit, Vector3(x, y, hd), 1.3, 1.5, Vector3(0, 0, 1), lit)
			if c in entrances:
				if f > 0:
					# stairwell: narrow tall window
					_window(kit, Vector3(x, y - 0.4, -hd), 0.8, 1.0, Vector3(0, 0, -1))
				continue
			_window(kit, Vector3(x, y, -hd), 1.3, 1.5, Vector3(0, 0, -1), rng.randf() < 0.12)
			if balconies and f > 0 and c % 2 == 1:
				var bz := -hd - 0.55
				kit.box("base", Vector3(x, y - 1.55, bz), Vector3(col_w * 1.6, 0.15, 1.1), Color("d8d2c6"))
				kit.box("base", Vector3(x, y - 1.05, bz - 0.5), Vector3(col_w * 1.6, 0.85, 0.08), Color("ebe6dc") if rng.randf() < 0.7 else Color("7fb3c9"))
				for s: float in [-1.0, 1.0]:
					kit.box("detail", Vector3(x + s * col_w * 0.8, y - 1.05, bz), Vector3(0.08, 0.85, 1.0), Color("ebe6dc"))
	# Side windows on gable ends for towers.
	if not balconies:
		for f in floors:
			var y := 0.6 + f * fh + 1.6
			for s: float in [-1.0, 1.0]:
				var nw := int(depth / 4.0)
				for c in nw:
					var z := -hd + (c + 0.5) * depth / nw
					_window(kit, Vector3(s * hl, y, z), 1.2, 1.5, Vector3(s, 0, 0), rng.randf() < 0.1)
		# vertical accent stripes
		for s: float in [-1.0, 1.0]:
			kit.box("base", Vector3(s * (hl - 0.6), h * 0.5, -hd - 0.1), Vector3(1.0, h - 0.2, 0.25), Color("6f9fc0"))
	# Entrances with canopies and doors.
	for c in entrances:
		var x := -hl + (c + 0.5) * col_w
		kit.box("detail", Vector3(x, 1.65, -hd - 0.02), Vector3(1.4, 2.1, 0.05), Color("5a4636"))
		kit.box("base", Vector3(x, 2.95, -hd - 0.8), Vector3(2.4, 0.15, 1.6), Color("d8d2c6"))
		kit.box("base", Vector3(x, 0.45, -hd - 1.0), Vector3(2.6, 0.3, 2.0), CONCRETE)
	return _meta(_node(name, kit, 0.06), Vector2(length, depth), h)


# --- shops -----------------------------------------------------------------

static func shop(name: String, sign: String, accent: Color, w: float, d: float) -> Node3D:
	var kit := MeshKit.new()
	var h := 4.2
	var hw := w * 0.5
	var hd := d * 0.5
	kit.box("base", Vector3(0, 0.15, 0), Vector3(w + 0.4, 0.3, d + 0.4), CONCRETE)
	kit.box("paint", Vector3(0, h * 0.5 + 0.15, 0), Vector3(w, h, d), Color.WHITE)
	kit.box("base", Vector3(0, h + 0.75, -hd + 0.4), Vector3(w + 0.3, 1.3, 0.9), accent)
	kit.box("base", Vector3(0, h + 0.3, 0), Vector3(w + 0.3, 0.3, d + 0.3), accent.darkened(0.2))
	# Big glass shop front with goods on shelves.
	kit.box("detail", Vector3(0, 1.9, -hd - 0.02), Vector3(w - 1.2, 2.8, 0.05), Color("9ec8d6"))
	for row in 3:
		kit.box("detail", Vector3(-hw * 0.35, 1.0 + row * 0.8, -hd - 0.05), Vector3(w * 0.38, 0.06, 0.04), Color("f2f2f2"))
		for i in 6:
			var c: Color = [Color("e85b4a"), Color("f2c14e"), Color("5aa9e6"), Color("7cc96b")][(i + row) % 4]
			kit.box("detail", Vector3(-hw + 1.2 + i * 0.55, 1.2 + row * 0.8, -hd - 0.06), Vector3(0.35, 0.35, 0.03), c)
	kit.box("detail", Vector3(hw * 0.45, 1.5, -hd - 0.06), Vector3(1.4, 2.6, 0.05), Color("dbeef4"))
	kit.box("detail", Vector3(hw * 0.45, 1.5, -hd - 0.08), Vector3(0.06, 2.6, 0.03), FRAME)
	for i in 5:
		var x := -hw + 0.6 + i * (w - 1.2) / 4.0
		kit.box("base", Vector3(x, 1.9, -hd - 0.05), Vector3(0.18, 3.0, 0.12), FRAME)
	# Awning.
	var a0 := Vector3(-hw, 3.7, -hd - 0.05)
	var a1 := Vector3(hw, 3.7, -hd - 0.05)
	var stripes := int(w / 0.9)
	for i in stripes:
		var t0 := float(i) / stripes
		var t1 := float(i + 1) / stripes
		var p0 := a0.lerp(a1, t0)
		var p1 := a0.lerp(a1, t1)
		var col := accent if i % 2 == 0 else Color("f6f3ea")
		kit.quad_facing("base", p0, p1, p1 + Vector3(0, -0.7, -1.4), p0 + Vector3(0, -0.7, -1.4), Vector3(0, 1, -0.5), col)
	var root := _node(name, kit, 0.05, Color("f2efe6"))
	_label(root, sign, Vector3(0, h + 0.75, -hd - 0.08), 160, Color("ffffff"), PI)
	return _meta(root, Vector2(w, d), h + 1.4)


static func chaikhana(name: String) -> Node3D:
	var kit := MeshKit.new()
	var w := 16.0
	var d := 10.0
	kit.box("base", Vector3(0, 0.3, 0), Vector3(w + 1, 0.6, d + 1), Color("c2b49a"))
	kit.box("paint", Vector3(0, 2.4, 2.0), Vector3(w, 3.6, d - 4.0), Color.WHITE)
	# Open veranda with carved wooden columns.
	for i in 6:
		var x := -w * 0.5 + 0.6 + i * (w - 1.2) / 5.0
		kit.cylinder("base", Vector3(x, 2.2, -d * 0.5 + 0.5), 0.18, 3.2, 8, WOOD)
		kit.box("detail", Vector3(x, 3.75, -d * 0.5 + 0.5), Vector3(0.5, 0.3, 0.5), Color("a36d3f"))
	kit.box("base", Vector3(0, 4.15, 0), Vector3(w + 0.6, 0.35, d + 0.6), Color("1f7f8a"))
	for i in 12:
		kit.box("detail", Vector3(-w * 0.5 + 0.7 + i * 1.33, 3.92, -d * 0.5 - 0.31), Vector3(0.6, 0.12, 0.02), Color("e8c05a") if i % 2 == 0 else Color("c2463c"))
	# Tapchan (raised seats) with low tables.
	for s: float in [-1.0, 1.0]:
		kit.box("base", Vector3(s * 3.8, 0.9, -2.6), Vector3(3.0, 0.4, 2.2), WOOD)
		kit.box("detail", Vector3(s * 3.8, 1.12, -2.6), Vector3(2.8, 0.06, 2.0), Color("b33a3a"))
		kit.box("base", Vector3(s * 3.8, 1.3, -2.6), Vector3(1.0, 0.3, 0.7), Color("6e4527"))
	var root := _node(name, kit, 0.05, Color("f4ead6"))
	_label(root, "ЧОЙХОНА", Vector3(0, 4.9, -d * 0.5 - 0.35), 150, Color("fff3c4"), PI)
	return _meta(root, Vector2(w, d), 4.4)


static func kiosk(name: String) -> Node3D:
	var kit := MeshKit.new()
	kit.box("paint", Vector3(0, 1.3, 0), Vector3(3.0, 2.6, 2.4), Color.WHITE)
	kit.box("detail", Vector3(0, 1.5, -1.22), Vector3(2.4, 1.1, 0.04), Color("9ec8d6"))
	kit.box("base", Vector3(0, 2.75, -0.1), Vector3(3.3, 0.3, 2.9), Color("d64b3c"))
	var root := _node(name, kit, 0.04, Color("f2efe6"))
	_label(root, "МАТБУОТ", Vector3(0, 2.75, -1.56), 80, Color.WHITE, PI)
	return _meta(root, Vector2(3.0, 2.4), 2.9)


# --- garage ----------------------------------------------------------------

## The player's garage: open bay facing -Z, workbench and tyre rack inside.
static func garage(name: String) -> Node3D:
	var kit := MeshKit.new()
	var w := 14.0
	var d := 16.0
	var h := 5.5
	var hw := w * 0.5
	var hd := d * 0.5
	kit.box("detail", Vector3(0, 0.02, 0), Vector3(w - 0.4, 0.04, d - 0.4), Color("6f747a"))
	kit.box("paint", Vector3(-hw + 0.25, h * 0.5, 0), Vector3(0.5, h, d), Color.WHITE)
	kit.box("paint", Vector3(hw - 0.25, h * 0.5, 0), Vector3(0.5, h, d), Color.WHITE)
	kit.box("paint", Vector3(0, h * 0.5, hd - 0.25), Vector3(w, h, 0.5), Color.WHITE)
	kit.box("paint", Vector3(0, h - 0.7, -hd + 0.25), Vector3(w, 1.4, 0.5), Color.WHITE)
	kit.box("base", Vector3(0, h + 0.15, 0), Vector3(w + 0.4, 0.3, d + 0.4), Color("3d4b5c"))
	# Hazard stripes around the bay.
	for i in 14:
		var x := -hw + 0.5 + i
		kit.box("detail", Vector3(x, h - 1.45, -hd - 0.02), Vector3(0.5, 0.18, 0.02), Color("f2c14e") if i % 2 == 0 else DARK)
	# Roller door rolled up.
	kit.cylinder("base", Vector3(0, h - 0.95, -hd + 0.6), 0.35, w - 1.2, 10, Color("8f99a3"), "x")
	# Workbench, tyre rack, tool wall.
	kit.box("base", Vector3(-hw + 1.2, 0.5, 2.0), Vector3(1.2, 1.0, 4.5), WOOD)
	kit.box("detail", Vector3(-hw + 0.55, 2.2, 2.0), Vector3(0.05, 1.6, 4.0), Color("566270"))
	for i in 4:
		kit.cylinder("base", Vector3(hw - 1.2, 0.4 + i * 0.45, 4.0), 0.36, 0.25, 12, Color("1d1d20"), "y")
	kit.box("base", Vector3(hw - 1.2, 1.2, 1.0), Vector3(1.4, 2.4, 2.0), Color("b33a3a"))
	var root := _node(name, kit, 0.05, Color("eae3d3"))
	_label(root, "ГАРАЖ", Vector3(0, h + 0.9, -hd - 0.1), 200, Color("ffd36b"), PI)
	root.set_meta("walls", [
		{"pos": Vector3(-hw + 0.25, h * 0.5, 0), "size": Vector3(0.5, h, d)},
		{"pos": Vector3(hw - 0.25, h * 0.5, 0), "size": Vector3(0.5, h, d)},
		{"pos": Vector3(0, h * 0.5, hd - 0.25), "size": Vector3(w, h, 0.5)},
		{"pos": Vector3(0, h + 0.1, 0), "size": Vector3(w, 0.4, d)},
	])
	return _meta(root, Vector2(w, d), h)


## Concrete roof on pillars – police helicopters do not exist, but cops lose sight here.
static func covered_parking(name: String) -> Node3D:
	var kit := MeshKit.new()
	var w := 30.0
	var d := 16.0
	kit.box("base", Vector3(0, 4.2, 0), Vector3(w, 0.5, d), Color("b9b2a4"))
	kit.box("detail", Vector3(0, 4.46, 0), Vector3(w - 0.6, 0.02, d - 0.6), Color("7fa86a"))
	var pillars: Array = []
	for i in 4:
		for j in 2:
			var p := Vector3(-w * 0.5 + 1 + i * (w - 2) / 3.0, 2.0, -d * 0.5 + 1 + j * (d - 2))
			kit.box("base", p, Vector3(0.6, 4.0, 0.6), CONCRETE)
			pillars.append({"pos": p, "size": Vector3(0.6, 4.0, 0.6)})
	for i in 6:
		kit.box("detail", Vector3(-w * 0.5 + 2.5 + i * 5, 0.015, 0), Vector3(0.15, 0.02, 5.0), Color("e8e4da"))
	var root := _node(name, kit, 0.05)
	pillars.append({"pos": Vector3(0, 4.2, 0), "size": Vector3(w, 0.5, d)})
	root.set_meta("walls", pillars)
	return _meta(root, Vector2(w, d), 4.5)


# --- landmarks -------------------------------------------------------------

## Long wall with carved arch niches, like the park walls along the avenue.
static func ornament_wall(name: String) -> Node3D:
	var kit := MeshKit.new()
	var len := 24.0
	kit.box("paint", Vector3(0, 1.6, 0), Vector3(len, 3.2, 0.8), Color.WHITE)
	kit.box("base", Vector3(0, 3.35, 0), Vector3(len + 0.3, 0.3, 1.0), Color("c8b79a"))
	for i in 4:
		var x := -len * 0.5 + 3.0 + i * 6.0
		kit.box("base", Vector3(x, 1.8, -0.42), Vector3(0.7, 3.6, 0.2), Color("d9c9aa"))
		var x2 := x + 3.0
		if i < 3:
			var arch := PackedVector2Array()
			arch.append(Vector2(x2 - 1.1, 0.4))
			arch.append(Vector2(x2 + 1.1, 0.4))
			for k in 9:
				var a := PI * k / 8.0
				arch.append(Vector2(x2 + cos(a) * 1.1, 2.1 + sin(a) * 1.1))
			var poly := PackedVector2Array()
			poly.append(Vector2(x2 - 1.1, 0.4))
			poly.append(Vector2(x2 + 1.1, 0.4))
			for k in 9:
				var a := PI * k / 8.0
				poly.append(Vector2(x2 + cos(a) * 1.1, 2.1 + sin(a) * 1.1))
			var pts := PackedVector3Array()
			for v in poly:
				pts.append(Vector3(v.x, v.y, -0.41))
			# fill niche as a fan from its centre
			var c := Vector3(x2, 1.6, -0.41)
			for k in pts.size():
				var p0 := pts[k]
				var p1 := pts[(k + 1) % pts.size()]
				kit.tri("detail", c, p1, p0, Color("b7a688"))
			kit.box("detail", Vector3(x2, 1.9, -0.43), Vector3(0.5, 1.2, 0.02), Color("8d7a5c"))
	var root := _node(name, kit, 0.05, Color("e9dcc0"))
	return _meta(root, Vector2(len, 0.8), 3.5)


static func rotunda(name: String) -> Node3D:
	var kit := MeshKit.new()
	kit.cylinder("base", Vector3(0, 0.5, 0), 7.0, 1.0, 16, CONCRETE)
	for i in 12:
		var a := TAU * i / 12.0
		kit.cylinder("paint", Vector3(cos(a) * 5.6, 4.0, sin(a) * 5.6), 0.35, 6.0, 8, Color.WHITE)
	kit.cylinder("paint", Vector3(0, 7.5, 0), 6.4, 1.0, 16, Color.WHITE)
	kit.ball("base", Vector3(0, 8.0, 0), Vector3(5.2, 4.2, 5.2), Color("2aa6a0"))
	kit.cylinder("base", Vector3(0, 12.6, 0), 0.15, 1.6, 6, Color("e0b74a"))
	var root := _node(name, kit, 0.06, Color("f1ece0"))
	return _meta(root, Vector2(14, 14), 13)


static func tv_tower(name: String) -> Node3D:
	var kit := MeshKit.new()
	kit.cylinder("base", Vector3(0, 30, 0), 2.6, 60, 10, Color("e8e4dc"), "y", 1.4)
	for i in 6:
		kit.box("detail", Vector3(0, 6 + i * 9, 0), Vector3(5.4 - i * 0.4, 1.2, 5.4 - i * 0.4), Color("d2473c") if i % 2 == 0 else Color("f3f1ea"))
	kit.cylinder("base", Vector3(0, 62, 0), 5.0, 4.0, 14, Color("cfd6dd"))
	kit.cylinder("detail", Vector3(0, 62, 0), 5.05, 1.5, 14, Color("4c6a88"))
	kit.cylinder("base", Vector3(0, 72, 0), 0.6, 16, 6, Color("d2473c"), "y", 0.25)
	var root := _node(name, kit, 0.15)
	return _meta(root, Vector2(6, 6), 80)


# --- vegetation ------------------------------------------------------------

## The tall pyramidal poplar that lines Dushanbe streets.
static func tree_poplar(name: String) -> Node3D:
	var kit := MeshKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	kit.cylinder("base", Vector3(0, 1.5, 0), 0.22, 3.0, 6, TRUNK, "y", 0.16)
	kit.ball("base", Vector3(0, 5.0, 0), Vector3(1.6, 3.0, 1.6), POPLAR, 0.12, rng)
	kit.ball("base", Vector3(0, 8.4, 0), Vector3(1.25, 2.8, 1.25), POPLAR.lightened(0.06), 0.12, rng)
	kit.ball("base", Vector3(0, 11.0, 0), Vector3(0.75, 1.8, 0.75), POPLAR.lightened(0.12), 0.1, rng)
	return _meta(_node(name, kit, 0.05), Vector2(0.5, 0.5), 12.5)


static func tree_round(name: String) -> Node3D:
	var kit := MeshKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	kit.cylinder("base", Vector3(0, 1.4, 0), 0.25, 2.8, 6, TRUNK, "y", 0.18)
	kit.ball("base", Vector3(0, 4.2, 0), Vector3(2.6, 2.1, 2.6), LEAF, 0.12, rng)
	kit.ball("base", Vector3(1.2, 5.2, 0.5), Vector3(1.7, 1.5, 1.7), LEAF.lightened(0.08), 0.12, rng)
	kit.ball("base", Vector3(-0.9, 5.4, -0.7), Vector3(1.6, 1.4, 1.6), LEAF_DARK.lightened(0.1), 0.12, rng)
	return _meta(_node(name, kit, 0.05), Vector2(0.5, 0.5), 7.0)


static func bush(name: String) -> Node3D:
	var kit := MeshKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	kit.ball("base", Vector3(0, 0.55, 0), Vector3(1.0, 0.7, 1.0), LEAF_DARK, 0.15, rng)
	kit.ball("base", Vector3(0.7, 0.45, 0.2), Vector3(0.7, 0.55, 0.7), LEAF, 0.15, rng)
	return _meta(_node(name, kit, 0.03), Vector2(2.0, 2.0), 1.2)


# --- street furniture ------------------------------------------------------

## Street lamp; the banner variant carries a festive striped flag.
static func lamp(name: String, banner: bool) -> Node3D:
	var kit := MeshKit.new()
	kit.cylinder("base", Vector3(0, 0.3, 0), 0.22, 0.6, 8, Color("3b4048"))
	kit.cylinder("base", Vector3(0, 4.0, 0), 0.09, 7.6, 8, Color("5d6670"), "y", 0.07)
	kit.box("base", Vector3(0.0, 7.7, -0.8), Vector3(0.1, 0.1, 1.7), Color("5d6670"))
	kit.taper_box("base", Vector3(0.0, 7.55, -1.65), Vector3(0.45, 0.22, 0.8), Vector2(0.7, 0.8), Color("4a525c"))
	kit.box("lamp", Vector3(0.0, 7.43, -1.65), Vector3(0.36, 0.02, 0.6), Color("fff3c8"))
	if banner:
		kit.box("base", Vector3(0.0, 6.2, 0.45), Vector3(0.05, 0.05, 0.8), Color("5d6670"))
		kit.box("base", Vector3(0.0, 4.2, 0.45), Vector3(0.05, 0.05, 0.8), Color("5d6670"))
		var stripes := [Color("cc2b2b"), Color("f6f4ee"), Color("2f8f3a")]
		for i in 3:
			kit.box("detail", Vector3(0.0, 5.9 - i * 0.55, 0.62), Vector3(0.03, 0.55, 0.62), stripes[i])
		kit.box("detail", Vector3(0.0, 5.35, 0.62), Vector3(0.04, 0.2, 0.2), Color("e2b84a"))
	return _meta(_node(name, kit, 0.03), Vector2(0.4, 0.4), 8.0)


static func bench(name: String) -> Node3D:
	var kit := MeshKit.new()
	for s: float in [-1.0, 1.0]:
		kit.box("base", Vector3(s * 0.75, 0.22, 0), Vector3(0.12, 0.44, 0.45), CONCRETE.darkened(0.15))
		kit.box("base", Vector3(s * 0.75, 0.62, 0.2), Vector3(0.1, 0.4, 0.08), CONCRETE.darkened(0.15))
	for i in 3:
		kit.box("base", Vector3(0, 0.47, -0.15 + i * 0.15), Vector3(1.8, 0.05, 0.12), WOOD)
	for i in 2:
		kit.box("base", Vector3(0, 0.68 + i * 0.16, 0.24), Vector3(1.8, 0.1, 0.04), WOOD)
	return _meta(_node(name, kit, 0.02), Vector2(1.8, 0.6), 1.0)


static func bus_stop(name: String) -> Node3D:
	var kit := MeshKit.new()
	for s: float in [-1.0, 1.0]:
		kit.box("base", Vector3(s * 2.4, 1.3, 0.6), Vector3(0.12, 2.6, 0.12), METAL)
		kit.box("base", Vector3(s * 2.4, 1.3, -0.6), Vector3(0.12, 2.6, 0.12), METAL)
	kit.taper_box("base", Vector3(0, 2.7, 0), Vector3(5.4, 0.2, 1.9), Vector2(1.0, 1.0), Color("2b84b8"))
	kit.box("glass", Vector3(0, 1.4, 0.62), Vector3(4.7, 2.2, 0.05), Color("a9cbd8"))
	kit.box("base", Vector3(0, 0.5, 0.35), Vector3(3.6, 0.08, 0.45), WOOD)
	kit.box("base", Vector3(3.0, 1.6, -0.6), Vector3(0.08, 3.2, 0.08), METAL)
	kit.box("detail", Vector3(3.0, 3.0, -0.6), Vector3(0.6, 0.6, 0.04), Color("f2c14e"))
	var root := _node(name, kit, 0.03)
	_label(root, "ИСТГОҲ", Vector3(0, 2.7, -0.97), 60, Color.WHITE, PI)
	return _meta(root, Vector2(5.0, 1.4), 2.8)


static func fence(name: String) -> Node3D:
	var kit := MeshKit.new()
	var len := 4.0
	for s: float in [-1.0, 1.0]:
		kit.box("base", Vector3(s * len * 0.5, 0.55, 0), Vector3(0.08, 1.1, 0.08), Color("2d3a33"))
	kit.box("base", Vector3(0, 1.05, 0), Vector3(len, 0.06, 0.05), Color("2d3a33"))
	kit.box("base", Vector3(0, 0.2, 0), Vector3(len, 0.06, 0.05), Color("2d3a33"))
	for i in 15:
		kit.box("detail", Vector3(-len * 0.5 + 0.25 + i * 0.25, 0.62, 0), Vector3(0.03, 0.84, 0.03), Color("2d3a33"))
	return _meta(_node(name, kit, 0.012), Vector2(4.0, 0.15), 1.1)


static func trash_bin(name: String) -> Node3D:
	var kit := MeshKit.new()
	kit.cylinder("base", Vector3(0, 0.45, 0), 0.28, 0.9, 8, Color("3f7d4c"), "y", 0.32)
	kit.cylinder("base", Vector3(0, 0.93, 0), 0.34, 0.06, 8, Color("2e5d38"))
	return _meta(_node(name, kit, 0.02), Vector2(0.6, 0.6), 1.0)


static func cone(name: String) -> Node3D:
	var kit := MeshKit.new()
	kit.box("base", Vector3(0, 0.03, 0), Vector3(0.5, 0.06, 0.5), Color("e8582c"))
	kit.cylinder("base", Vector3(0, 0.38, 0), 0.2, 0.66, 8, Color("ff6b2e"), "y", 0.04)
	kit.cylinder("detail", Vector3(0, 0.42, 0), 0.135, 0.12, 8, Color("f4f4f4"), "y", 0.115)
	return _meta(_node(name, kit, 0.012), Vector2(0.5, 0.5), 0.7)


static func tyre_stack(name: String) -> Node3D:
	var kit := MeshKit.new()
	for i in 3:
		kit.cylinder("base", Vector3(0, 0.15 + i * 0.3, 0), 0.42, 0.28, 10, Color("202024"))
		kit.cylinder("detail", Vector3(0, 0.15 + i * 0.3 + 0.141, 0), 0.22, 0.004, 10, Color("101012"))
	kit.cylinder("detail", Vector3(0, 0.75, 0), 0.425, 0.08, 10, Color("e8e4da") if true else Color.RED)
	return _meta(_node(name, kit, 0.015), Vector2(0.9, 0.9), 0.9)


static func fountain(name: String) -> Node3D:
	var kit := MeshKit.new()
	kit.cylinder("base", Vector3(0, 0.35, 0), 5.0, 0.7, 12, CONCRETE)
	kit.cylinder("detail", Vector3(0, 0.66, 0), 4.5, 0.04, 12, Color("64b6d8"))
	kit.cylinder("base", Vector3(0, 1.5, 0), 0.5, 2.4, 8, CONCRETE)
	kit.cylinder("base", Vector3(0, 2.7, 0), 1.6, 0.25, 10, CONCRETE)
	kit.cone("detail", Vector3(0, 2.8, 0), 0.9, 1.4, 8, Color("bfe6f5"))
	return _meta(_node(name, kit, 0.03), Vector2(10, 10), 3.0)


static func swing(name: String) -> Node3D:
	var kit := MeshKit.new()
	for s: float in [-1.0, 1.0]:
		kit.box("base", Vector3(s * 1.6, 1.2, -0.5), Vector3(0.1, 2.5, 0.1), Color("d64b3c"))
		kit.box("base", Vector3(s * 1.6, 1.2, 0.5), Vector3(0.1, 2.5, 0.1), Color("d64b3c"))
	kit.box("base", Vector3(0, 2.45, 0), Vector3(3.4, 0.12, 0.12), Color("2f6fb3"))
	for s: float in [-0.7, 0.7]:
		kit.box("detail", Vector3(s - 0.2, 1.6, 0), Vector3(0.03, 1.6, 0.03), Color("888888"))
		kit.box("detail", Vector3(s + 0.2, 1.6, 0), Vector3(0.03, 1.6, 0.03), Color("888888"))
		kit.box("base", Vector3(s, 0.8, 0), Vector3(0.5, 0.06, 0.25), Color("f2c14e"))
	return _meta(_node(name, kit, 0.02), Vector2(3.4, 1.2), 2.5)
