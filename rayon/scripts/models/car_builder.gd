class_name CarBuilder
extends RefCounted
## Builds the three original car models of RAYON from code.
##
## Every car scene has the same layout so the physics script can drive it:
##   <Car> (Node3D, metadata = dimensions)
##     Body        MeshInstance3D  (surfaces: paint, base, detail, glass, lamp)
##     WheelFL/FR/RL/RR  Node3D at the wheel centre (steering pivot)
##       Spin      Node3D (rolls around X)
##         Rim     MeshInstance3D (tyre + rim)
##     LightBar/LightRed, LightBar/LightBlue  (POSBON only)
## Forward is -Z, ground is y = 0.

const TYRE := Color("1d1d20")
const TYRE_SIDE := Color("2a2a2e")
const BLACK := Color("1b1c1f")
const TRIM := Color("26282c")
const GLASS := Color("2d3a4a")
const CHROME := Color("c9ced6")
const HEAD := Color("fff7da")
const INDICATOR := Color("ff9a2e")
const TAIL := Color("d8262a")
const PLATE := Color("f2f2ee")

# name: dimensions shared with the physics specs.
const DIMS := {
	"sado": {"length": 4.30, "width": 1.68, "axle_f": -1.27, "axle_r": 1.18, "track": 0.72, "radius": 0.31, "tyre_w": 0.21, "height": 1.36},
	"chabuk": {"length": 3.62, "width": 1.58, "axle_f": -1.06, "axle_r": 1.24, "track": 0.67, "radius": 0.28, "tyre_w": 0.18, "height": 1.38},
	"posbon": {"length": 4.62, "width": 1.78, "axle_f": -1.40, "axle_r": 1.32, "track": 0.77, "radius": 0.32, "tyre_w": 0.22, "height": 1.62},
}

const DEFAULT_PAINT := {
	"sado": Color("f4f2ec"),
	"chabuk": Color("d9a531"),
	"posbon": Color("1f2b4d"),
}

const DEFAULT_RIMS := {"sado": "sport", "chabuk": "steel", "posbon": "steel"}


static func build(kind: String, paint := Color(-1, 0, 0), rims := "") -> Node3D:
	if paint.r < 0.0:
		paint = DEFAULT_PAINT[kind]
	if rims == "":
		rims = DEFAULT_RIMS[kind]
	var d: Dictionary = DIMS[kind]
	var kit := MeshKit.new()
	match kind:
		"sado":
			_sado(kit, d)
		"chabuk":
			_chabuk(kit, d)
		"posbon":
			_posbon(kit, d)
	var root := Node3D.new()
	root.name = kind.capitalize()
	for k in d:
		root.set_meta(k, d[k])
	root.set_meta("kind", kind)
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = kit.build(Mats.for_model(0.022, paint))
	root.add_child(body)
	for wn in ["FL", "FR", "RL", "RR"]:
		var w := Node3D.new()
		w.name = "Wheel" + wn
		var z: float = d["axle_f"] if wn[0] == "F" else d["axle_r"]
		var x: float = d["track"] if wn[1] == "R" else -d["track"]
		w.position = Vector3(x, d["radius"], z)
		var spin := Node3D.new()
		spin.name = "Spin"
		w.add_child(spin)
		var rim := MeshInstance3D.new()
		rim.name = "Rim"
		rim.mesh = wheel_mesh(rims, d["radius"], d["tyre_w"])
		# Wheel meshes face outward along +X; mirror the left ones.
		if wn[1] == "L":
			rim.rotation.y = PI
		spin.add_child(rim)
		root.add_child(w)
	if kind == "posbon":
		_light_bar(root, d)
	_set_owner_recursive(root, root)
	return root


# --- wheels ----------------------------------------------------------------

static func wheel_mesh(style: String, r: float, w: float) -> ArrayMesh:
	var kit := MeshKit.new()
	# Tyre: faceted cylinder with a slightly lighter sidewall.
	kit.cylinder("base", Vector3.ZERO, r, w, 16, TYRE, "x", -1.0, TYRE_SIDE)
	var face := w * 0.5
	if style == "sport":
		# Dark dish, five silver spokes, polished lip and centre cap.
		kit.cylinder("detail", Vector3(face - 0.004, 0, 0), r * 0.70, 0.02, 16, Color("3a3d44"), "x")
		for i in 5:
			var a := TAU * i / 5.0
			var b := Basis(Vector3.RIGHT, a)
			kit.xform = Transform3D(b, Vector3.ZERO)
			kit.taper_box("detail", Vector3(face + 0.012, r * 0.36, 0), Vector3(0.03, r * 0.56, r * 0.22), Vector2(1.0, 0.7), CHROME)
		kit.xform = Transform3D.IDENTITY
		for i in 16:
			var a := TAU * i / 16.0
			kit.xform = Transform3D(Basis(Vector3.RIGHT, a), Vector3.ZERO)
			kit.box("detail", Vector3(face + 0.008, r * 0.69, 0), Vector3(0.03, r * 0.06, r * 0.29), CHROME)
		kit.xform = Transform3D.IDENTITY
		kit.cylinder("detail", Vector3(face + 0.02, 0, 0), r * 0.17, 0.05, 10, Color("e3e7ec"), "x")
	else:
		# Painted steel wheel: grey disc, ring of holes, small hubcap.
		kit.cylinder("detail", Vector3(face - 0.002, 0, 0), r * 0.64, 0.025, 16, Color("8d939c"), "x")
		for i in 8:
			var a := TAU * i / 8.0
			kit.xform = Transform3D(Basis(Vector3.RIGHT, a), Vector3.ZERO)
			kit.box("detail", Vector3(face + 0.012, r * 0.42, 0), Vector3(0.012, r * 0.12, r * 0.12), Color("3c4047"))
		kit.xform = Transform3D.IDENTITY
		kit.cylinder("detail", Vector3(face + 0.016, 0, 0), r * 0.26, 0.035, 12, Color("b8bec7"), "x")
		for i in 4:
			var a := TAU * i / 4.0 + 0.4
			kit.xform = Transform3D(Basis(Vector3.RIGHT, a), Vector3.ZERO)
			kit.box("detail", Vector3(face + 0.036, r * 0.12, 0), Vector3(0.012, 0.025, 0.025), Color("5b6068"))
		kit.xform = Transform3D.IDENTITY
	return kit.build(Mats.for_model(0.018))


# --- shared helpers --------------------------------------------------------

static func _arches(d: Dictionary, extra := 0.08) -> Array:
	var r: float = d["radius"] + extra
	return [MeshKit.circle2d(Vector2(d["axle_f"], d["radius"]), r, 18),
		MeshKit.circle2d(Vector2(d["axle_r"], d["radius"]), r, 18)]


static func _profile_band(kit: MeshKit, surface: String, poly: PackedVector2Array, half_w: float, cuts: Array, col: Color) -> void:
	for piece in MeshKit.cut(poly, cuts):
		kit.extrude_zy(surface, piece, -half_w, half_w, col)


## Dark arch liners so the wheels never show daylight through the body.
static func _arch_liners(kit: MeshKit, d: Dictionary, half_w: float) -> void:
	var r: float = d["radius"] + 0.07
	for z: float in [d["axle_f"], d["axle_r"]]:
		for i in 9:
			var a0 := PI * i / 9.0
			var a1 := PI * (i + 1) / 9.0
			var p0 := Vector2(z + cos(a0) * r, d["radius"] + sin(a0) * r)
			var p1 := Vector2(z + cos(a1) * r, d["radius"] + sin(a1) * r)
			for s: float in [-1.0, 1.0]:
				var x0 := s * (half_w - 0.02)
				var x1 := s * (half_w - 0.30)
				kit.quad_facing("detail", Vector3(x0, p0.y, p0.x), Vector3(x1, p0.y, p0.x), Vector3(x1, p1.y, p1.x), Vector3(x0, p1.y, p1.x), Vector3(0, -(p0.y + p1.y) * 0.5 + d["radius"], -((p0.x + p1.x) * 0.5 - z)), BLACK)


## A thin glass pane following a slanted edge of the cabin profile (windshield / rear glass).
static func _slanted_glass(kit: MeshKit, a: Vector2, b: Vector2, half_w: float, outward_sign: float) -> void:
	var dir := (b - a).normalized()
	var n := Vector2(-dir.y, dir.x) * outward_sign
	var pa := a + dir * 0.05 + n * 0.012
	var pb := b - dir * 0.05 + n * 0.012
	kit.quad_facing("glass", Vector3(-half_w, pa.y, pa.x), Vector3(half_w, pa.y, pa.x), Vector3(half_w, pb.y, pb.x), Vector3(-half_w, pb.y, pb.x), Vector3(0, n.y, n.x), GLASS)


static func _side_glass(kit: MeshKit, poly: PackedVector2Array, half_w: float) -> void:
	kit.extrude_zy("glass", poly, -half_w, half_w, GLASS)


static func _mirror(kit: MeshKit, x: float, y: float, z: float, col: Color) -> void:
	var s := signf(x)
	kit.box("base", Vector3(x - s * 0.05, y - 0.02, z), Vector3(0.10, 0.04, 0.05), BLACK)
	kit.taper_box("base", Vector3(x + s * 0.03, y + 0.05, z), Vector3(0.12, 0.10, 0.07), Vector2(0.9, 0.8), col)


static func _plate(kit: MeshKit, y: float, z: float, facing: float) -> void:
	kit.box("detail", Vector3(0, y, z), Vector3(0.40, 0.11, 0.02), PLATE)
	kit.box("detail", Vector3(0, y, z + facing * 0.011), Vector3(0.30, 0.03, 0.005), Color("3a3f4a"))


# --- SADO: angular 4-door sports sedan --------------------------------------

static func _sado(kit: MeshKit, d: Dictionary) -> void:
	var hw: float = d["width"] * 0.5
	var teal := Color("1d5f5b")
	var white := Color.WHITE  # tinted by the paint material
	var arches := _arches(d, 0.09)
	# Lower kit (teal): bumpers + side skirts in one band.
	_profile_band(kit, "base", PackedVector2Array([
		Vector2(-2.17, 0.27), Vector2(-2.10, 0.19), Vector2(2.08, 0.20), Vector2(2.16, 0.27),
		Vector2(2.16, 0.50), Vector2(-2.17, 0.50)]), hw, arches, teal)
	# Upper body (paint): wedge nose, flat hood, short boot.
	_profile_band(kit, "paint", PackedVector2Array([
		Vector2(-2.14, 0.50), Vector2(2.13, 0.50), Vector2(2.13, 0.83), Vector2(2.09, 0.91),
		Vector2(1.38, 0.93), Vector2(-0.78, 0.92), Vector2(-2.05, 0.86), Vector2(-2.14, 0.80)]), hw - 0.01, arches, white)
	_arch_liners(kit, d, hw)
	# Cabin.
	var cab := PackedVector2Array([Vector2(-0.80, 0.92), Vector2(-0.08, 1.34), Vector2(0.98, 1.35), Vector2(1.42, 0.93)])
	kit.extrude_zy("paint", cab, -hw + 0.17, hw - 0.17, white)
	_side_glass(kit, PackedVector2Array([Vector2(-0.64, 0.97), Vector2(-0.05, 1.30), Vector2(0.92, 1.30), Vector2(1.26, 0.97)]), hw - 0.16)
	_slanted_glass(kit, Vector2(-0.80, 0.92), Vector2(-0.08, 1.34), hw - 0.22, 1.0)
	_slanted_glass(kit, Vector2(0.98, 1.35), Vector2(1.42, 0.93), hw - 0.22, 1.0)
	# B and C pillars over the glass.
	for s: float in [-1.0, 1.0]:
		kit.box("paint", Vector3(s * (hw - 0.15), 1.13, 0.40), Vector3(0.03, 0.36, 0.09), white)
		# door shut lines + handles
		for z: float in [-0.70, 0.40, 1.36]:
			kit.box("detail", Vector3(s * (hw + 0.002), 0.70, z), Vector3(0.01, 0.38, 0.018), Color("9da3a8"))
		for z: float in [-0.20, 0.88]:
			kit.box("detail", Vector3(s * (hw + 0.008), 0.83, z), Vector3(0.02, 0.03, 0.14), TRIM)
		# black window trim strip
		kit.box("detail", Vector3(s * (hw - 0.155), 0.955, 0.31), Vector3(0.025, 0.035, 1.92), TRIM)
		_mirror(kit, s * (hw + 0.05), 1.0, -0.62, white)
	# Front: headlights, indicators, grille.
	for s: float in [-1.0, 1.0]:
		kit.box("lamp", Vector3(s * 0.52, 0.70, -2.145), Vector3(0.44, 0.15, 0.03), HEAD)
		kit.box("lamp", Vector3(s * 0.79, 0.70, -2.14), Vector3(0.10, 0.15, 0.03), INDICATOR)
	kit.box("detail", Vector3(0, 0.70, -2.15), Vector3(0.55, 0.12, 0.03), BLACK)
	for i in 3:
		kit.box("detail", Vector3(0, 0.66 + i * 0.04, -2.163), Vector3(0.50, 0.012, 0.01), Color("3e4146"))
	kit.box("detail", Vector3(0, 0.33, -2.175), Vector3(0.9, 0.08, 0.02), Color("174f4b"))
	_plate(kit, 0.36, -2.19, -1.0)
	# Rear: wide two-tone tail lamps, plate, exhaust.
	for s: float in [-1.0, 1.0]:
		kit.box("lamp", Vector3(s * 0.56, 0.73, 2.14), Vector3(0.50, 0.17, 0.03), TAIL)
		kit.box("lamp", Vector3(s * 0.25, 0.73, 2.142), Vector3(0.12, 0.17, 0.03), INDICATOR)
	kit.box("detail", Vector3(0, 0.73, 2.14), Vector3(0.34, 0.15, 0.025), Color("e9e6df"))
	_plate(kit, 0.36, 2.17, 1.0)
	kit.cylinder("detail", Vector3(-0.45, 0.20, 2.10), 0.05, 0.22, 10, Color("9aa0a8"), "z")
	# Rear spoiler on the boot lid.
	for s: float in [-1.0, 1.0]:
		kit.box("paint", Vector3(s * 0.55, 0.98, 1.98), Vector3(0.06, 0.10, 0.10), white)
	kit.taper_box("paint", Vector3(0, 1.045, 1.99), Vector3(1.50, 0.04, 0.22), Vector2(1.0, 0.8), white)


# --- CHABUK: compact 3-door hatch ------------------------------------------

static func _chabuk(kit: MeshKit, d: Dictionary) -> void:
	var hw: float = d["width"] * 0.5
	var arches := _arches(d, 0.08)
	var body := Color.WHITE
	_profile_band(kit, "paint", PackedVector2Array([
		Vector2(-1.78, 0.36), Vector2(1.79, 0.36), Vector2(1.80, 0.87), Vector2(1.70, 0.90),
		Vector2(-0.70, 0.89), Vector2(-1.70, 0.80), Vector2(-1.78, 0.72)]), hw, arches, body)
	# Black lower band, bumpers.
	_profile_band(kit, "base", PackedVector2Array([
		Vector2(-1.83, 0.22), Vector2(1.84, 0.22), Vector2(1.84, 0.38), Vector2(-1.83, 0.38)]), hw + 0.01, arches, BLACK)
	_arch_liners(kit, d, hw)
	kit.box("base", Vector3(0, 0.42, -1.82), Vector3(d["width"] + 0.02, 0.18, 0.12), BLACK)
	kit.box("base", Vector3(0, 0.42, 1.83), Vector3(d["width"] + 0.02, 0.18, 0.12), BLACK)
	# Tall cabin with near-vertical hatch.
	var cab := PackedVector2Array([Vector2(-0.70, 0.89), Vector2(-0.05, 1.37), Vector2(1.55, 1.38), Vector2(1.72, 0.90)])
	kit.extrude_zy("paint", cab, -hw + 0.12, hw - 0.12, body)
	_side_glass(kit, PackedVector2Array([Vector2(-0.56, 0.95), Vector2(-0.02, 1.33), Vector2(0.80, 1.33), Vector2(0.80, 0.95)]), hw - 0.11)
	_side_glass(kit, PackedVector2Array([Vector2(0.92, 0.95), Vector2(0.92, 1.33), Vector2(1.45, 1.33), Vector2(1.60, 0.95)]), hw - 0.11)
	_slanted_glass(kit, Vector2(-0.70, 0.89), Vector2(-0.05, 1.37), hw - 0.17, 1.0)
	_slanted_glass(kit, Vector2(1.55, 1.38), Vector2(1.72, 0.90), hw - 0.18, 1.0)
	for s: float in [-1.0, 1.0]:
		kit.box("detail", Vector3(s * (hw + 0.002), 0.62, 0.84), Vector3(0.01, 0.50, 0.018), Color("9b7c22"))
		kit.box("detail", Vector3(s * (hw + 0.008), 0.80, 0.62), Vector3(0.02, 0.03, 0.13), TRIM)
		kit.box("detail", Vector3(s * (hw - 0.105), 0.93, 0.45), Vector3(0.025, 0.035, 2.2), TRIM)
		_mirror(kit, s * (hw + 0.04), 0.98, -0.52, BLACK)
		# square headlights and tall tail lamps
		kit.box("lamp", Vector3(s * 0.50, 0.68, -1.785), Vector3(0.34, 0.17, 0.03), HEAD)
		kit.box("lamp", Vector3(s * 0.73, 0.68, -1.78), Vector3(0.09, 0.17, 0.03), INDICATOR)
		kit.box("lamp", Vector3(s * 0.66, 0.70, 1.81), Vector3(0.18, 0.30, 0.03), TAIL)
	kit.box("detail", Vector3(0, 0.68, -1.79), Vector3(0.62, 0.11, 0.03), BLACK)
	kit.box("detail", Vector3(0, 0.82, 1.73), Vector3(0.9, 0.05, 0.02), Color("3a3a3a"))
	_plate(kit, 0.45, -1.885, -1.0)
	_plate(kit, 0.60, 1.81, 1.0)
	kit.cylinder("detail", Vector3(0.42, 0.24, 1.80), 0.04, 0.18, 8, Color("9aa0a8"), "z")


# --- POSBON: heavy police sedan --------------------------------------------

static func _posbon(kit: MeshKit, d: Dictionary) -> void:
	var hw: float = d["width"] * 0.5
	var navy := Color("1f2b4d")
	var white := Color("f3f3f0")
	var arches := _arches(d, 0.09)
	_profile_band(kit, "base", PackedVector2Array([
		Vector2(-2.26, 0.34), Vector2(2.26, 0.34), Vector2(2.27, 0.88), Vector2(2.20, 0.95),
		Vector2(1.50, 0.97), Vector2(-0.85, 0.96), Vector2(-2.18, 0.92), Vector2(-2.26, 0.84)]), hw, arches, navy)
	_arch_liners(kit, d, hw)
	# White doors (two-tone livery) slightly proud of the body.
	for s: float in [-1.0, 1.0]:
		kit.box("base", Vector3(s * (hw + 0.006), 0.66, 0.08), Vector3(0.012, 0.56, 1.95), white)
		kit.box("detail", Vector3(s * (hw + 0.013), 0.66, 0.08), Vector3(0.006, 0.56, 0.02), Color("a7aab0"))
		kit.box("detail", Vector3(s * (hw + 0.014), 0.86, -0.35), Vector3(0.02, 0.03, 0.14), TRIM)
		kit.box("detail", Vector3(s * (hw + 0.014), 0.86, 0.55), Vector3(0.02, 0.03, 0.14), TRIM)
		# navy stripe along the white doors
		kit.box("detail", Vector3(s * (hw + 0.014), 0.52, 0.08), Vector3(0.006, 0.07, 1.95), navy)
		_mirror(kit, s * (hw + 0.05), 1.03, -0.75, navy)
	# Black bumpers.
	kit.box("base", Vector3(0, 0.40, -2.30), Vector3(d["width"] + 0.02, 0.20, 0.14), BLACK)
	kit.box("base", Vector3(0, 0.40, 2.30), Vector3(d["width"] + 0.02, 0.20, 0.14), BLACK)
	# Cabin: navy pillars, white roof.
	var cab := PackedVector2Array([Vector2(-0.85, 0.96), Vector2(-0.15, 1.40), Vector2(1.05, 1.41), Vector2(1.52, 0.97)])
	kit.extrude_zy("base", cab, -hw + 0.16, hw - 0.16, navy)
	kit.taper_box("base", Vector3(0, 1.415, 0.45), Vector3(d["width"] - 0.36, 0.03, 1.18), Vector2(1, 1), white)
	_side_glass(kit, PackedVector2Array([Vector2(-0.70, 1.0), Vector2(-0.12, 1.36), Vector2(0.40, 1.36), Vector2(0.40, 1.0)]), hw - 0.15)
	_side_glass(kit, PackedVector2Array([Vector2(0.50, 1.0), Vector2(0.50, 1.36), Vector2(1.00, 1.36), Vector2(1.36, 1.0)]), hw - 0.15)
	_slanted_glass(kit, Vector2(-0.85, 0.96), Vector2(-0.15, 1.40), hw - 0.21, 1.0)
	_slanted_glass(kit, Vector2(1.05, 1.41), Vector2(1.52, 0.97), hw - 0.21, 1.0)
	for s: float in [-1.0, 1.0]:
		kit.box("lamp", Vector3(s * 0.56, 0.74, -2.265), Vector3(0.40, 0.15, 0.03), HEAD)
		kit.box("lamp", Vector3(s * 0.81, 0.74, -2.26), Vector3(0.10, 0.15, 0.03), INDICATOR)
		kit.box("lamp", Vector3(s * 0.60, 0.78, 2.275), Vector3(0.46, 0.16, 0.03), TAIL)
		kit.box("lamp", Vector3(s * 0.30, 0.78, 2.277), Vector3(0.14, 0.16, 0.03), INDICATOR)
	kit.box("detail", Vector3(0, 0.74, -2.27), Vector3(0.66, 0.15, 0.03), Color("15171a"))
	for i in 4:
		kit.box("detail", Vector3(0, 0.69 + i * 0.033, -2.285), Vector3(0.60, 0.01, 0.01), Color("50545b"))
	_plate(kit, 0.40, -2.38, -1.0)
	_plate(kit, 0.62, 2.29, 1.0)
	# Push bar.
	for s: float in [-1.0, 1.0]:
		kit.box("base", Vector3(s * 0.32, 0.50, -2.42), Vector3(0.05, 0.36, 0.05), BLACK)
	kit.box("base", Vector3(0, 0.62, -2.42), Vector3(0.70, 0.05, 0.05), BLACK)


static func _light_bar(root: Node3D, d: Dictionary) -> void:
	var bar := Node3D.new()
	bar.name = "LightBar"
	bar.position = Vector3(0, 1.43, 0.12)
	root.add_child(bar)
	var base := MeshKit.new()
	base.box("base", Vector3(0, 0.03, 0), Vector3(1.16, 0.06, 0.26), BLACK)
	base.box("base", Vector3(-0.42, -0.005, 0), Vector3(0.05, 0.03, 0.2), BLACK)
	base.box("base", Vector3(0.42, -0.005, 0), Vector3(0.05, 0.03, 0.2), BLACK)
	base.box("detail", Vector3(0, 0.10, 0), Vector3(0.16, 0.08, 0.22), Color("e6e6e6"))
	var bm := MeshInstance3D.new()
	bm.name = "Base"
	bm.mesh = base.build(Mats.for_model(0.015))
	bar.add_child(bm)
	for side in ["Red", "Blue"]:
		var k := MeshKit.new()
		var x := -0.31 if side == "Red" else 0.31
		var col := Color("ff2a2a") if side == "Red" else Color("2a63ff")
		k.taper_box("detail", Vector3(x, 0.10, 0), Vector3(0.44, 0.09, 0.22), Vector2(0.95, 0.85), col)
		var mi := MeshInstance3D.new()
		mi.name = "Light" + side
		mi.mesh = k.build({"detail": Mats.glow(col.darkened(0.45))})
		bar.add_child(mi)


static func _set_owner_recursive(node: Node, owner: Node) -> void:
	for c in node.get_children():
		c.owner = owner
		_set_owner_recursive(c, owner)
