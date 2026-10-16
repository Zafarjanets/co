class_name StylizedCar
extends RefCounted
## Cartoon cars in the spirit of FR Legends: smooth lofted bodies with real
## wheel arches, flared fenders, low stance and big concave wheels. Lights,
## grilles and trims are added as simple shapes on top (no brand logos).
##
## Output layout matches CarBuilder (Body, WheelFL/FR/RL/RR → Spin → Rim), so
## the physics, garage and traffic code use these cars unchanged.

const BLACK := Color("141518")
const TRIM := Color("1e2024")
const CHROME := Color("c9ced6")
const LED := Color("f4f8ff")
const AMBER := Color("ff9a2e")
const RED := Color("c3121b")
const RED_DARK := Color("6e0c10")
const PLATE := Color("f2f2ee")

const PRESETS := {
	"m5": {
		"title": "M5", "plate": "M5 F90",
		"length": 4.96, "hw": 0.955, "axle_f": -1.50, "axle_r": 1.46, "track": 0.80, "radius": 0.355, "tyre_w": 0.27,
		"sill": 0.19, "bumper_low": 0.24, "belt": 0.93, "nose_h": 0.76, "cowl_h": 0.90, "deck_h": 1.00, "tail_h": 0.97,
		"roof_h": 1.46, "roof_hw": 0.68, "ws_base": -1.02, "ws_top": -0.26, "roof_end": 0.66, "rw_base": 1.46,
		"b_pillar": 0.06, "lean_f": 0.13, "lean_r": 0.08, "paint": Color("1d1e22"), "caliper": Color("2f6fd8"),
		"front": "kidney", "rear": "l_lamps", "rim_spokes": 14,
	},
	"cls": {
		"title": "CLS", "plate": "CLS 2014",
		"length": 4.94, "hw": 0.94, "axle_f": -1.46, "axle_r": 1.42, "track": 0.79, "radius": 0.35, "tyre_w": 0.26,
		"sill": 0.19, "bumper_low": 0.22, "belt": 0.90, "nose_h": 0.70, "cowl_h": 0.86, "deck_h": 0.95, "tail_h": 0.92,
		"roof_h": 1.42, "roof_hw": 0.64, "ws_base": -1.04, "ws_top": -0.28, "roof_end": 0.28, "rw_base": 1.60,
		"b_pillar": 0.02, "lean_f": 0.15, "lean_r": 0.10, "paint": Color("f3f2ee"), "caliper": Color("c3121b"),
		"front": "wide", "rear": "slim", "rim_spokes": 18, "coupe": true,
	},
}


static func build(kind: String, paint := Color(-1, 0, 0)) -> Node3D:
	var p: Dictionary = PRESETS[kind]
	if paint.r < 0.0:
		paint = p["paint"]
	var kit := MeshKit.new()
	var shape := _Shape.new(p)
	_loft(kit, shape)
	_front(kit, shape, p)
	_rear(kit, shape, p)
	_sides(kit, shape, p)
	var root := Node3D.new()
	root.name = p["title"]
	var dims := {"length": p["length"], "width": p["hw"] * 2.0, "height": p["roof_h"] + 0.02, "axle_f": p["axle_f"],
		"axle_r": p["axle_r"], "track": p["track"], "radius": p["radius"], "tyre_w": p["tyre_w"]}
	for k in dims:
		root.set_meta(k, dims[k])
	root.set_meta("kind", kind)
	root.set_meta("stylized", true)
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = kit.build(Mats.for_car(paint))
	root.add_child(body)
	_plates(root, shape, p)
	var rim := wheel_mesh(p["radius"], p["tyre_w"], p["rim_spokes"])
	for wn in ["FL", "FR", "RL", "RR"]:
		var w := Node3D.new()
		w.name = "Wheel" + wn
		var z: float = p["axle_f"] if wn[0] == "F" else p["axle_r"]
		var x: float = p["track"] if wn[1] == "R" else -p["track"]
		w.position = Vector3(x, p["radius"], z)
		var side := Node3D.new()
		side.name = "Side"
		if wn[1] == "L":
			side.rotation.y = PI
		w.add_child(side)
		# Brake caliper does not spin with the wheel.
		var cal := MeshInstance3D.new()
		cal.name = "Caliper"
		cal.mesh = caliper_mesh(p["radius"], p["caliper"])
		side.add_child(cal)
		var spin := Node3D.new()
		spin.name = "Spin"
		w.add_child(spin)
		var r := MeshInstance3D.new()
		r.name = "Rim"
		r.mesh = rim
		if wn[1] == "L":
			r.rotation.y = PI
		spin.add_child(r)
		root.add_child(w)
	_own(root, root)
	return root


# --- body shape ---------------------------------------------------------------------

## Body silhouette as a function of z (nose at -length/2).
class _Shape:
	var p: Dictionary
	var half_len: float
	var arch_r: float

	func _init(preset: Dictionary) -> void:
		p = preset
		half_len = p["length"] * 0.5
		arch_r = p["radius"] + 0.035

	func smooth(a: float, b: float, x: float) -> float:
		var t := clampf((x - a) / (b - a), 0.0, 1.0)
		return t * t * (3.0 - 2.0 * t)

	## Height of the top centre line (hood → windshield → roof → rear glass → boot).
	func top(z: float) -> float:
		var wsb: float = p["ws_base"]
		var wst: float = p["ws_top"]
		var re: float = p["roof_end"]
		var rwb: float = p["rw_base"]
		var roof: float = p["roof_h"]
		if z <= wsb:
			var t := clampf((z + half_len) / (wsb + half_len), 0.0, 1.0)
			return lerpf(p["nose_h"], p["cowl_h"], 1.0 - pow(1.0 - t, 2.2))
		if z <= wst:
			var t2 := (z - wsb) / (wst - wsb)
			return lerpf(p["cowl_h"], roof, 1.0 - pow(1.0 - t2, 1.7))
		if z <= re:
			var t3 := (z - wst) / maxf(re - wst, 0.01)
			return roof + sin(t3 * PI) * 0.025
		if z <= rwb:
			var t4 := (z - re) / (rwb - re)
			var e := 1.4 if p.get("coupe", false) else 1.9
			return lerpf(roof, p["deck_h"], pow(t4, e))
		var t5 := clampf((z - rwb) / (half_len - rwb), 0.0, 1.0)
		return lerpf(p["deck_h"], p["tail_h"], t5 * t5)

	## 0 on the hood / boot, 1 under the roof.
	func cabin(z: float) -> float:
		return smooth(p["belt"] + 0.03, p["belt"] + 0.24, top(z))

	func bottom(z: float) -> float:
		var y: float = p["sill"]
		var d := half_len - absf(z)
		y = lerpf(p["bumper_low"], y, smooth(0.0, 0.45, d))
		for axle in [p["axle_f"], p["axle_r"]]:
			var dz: float = z - axle
			if absf(dz) < arch_r:
				y = maxf(y, p["radius"] + sqrt(arch_r * arch_r - dz * dz))
		return y

	## Plan-view rounding of the four corners.
	func width_scale(z: float) -> float:
		var e := 0.34
		var d := half_len - absf(z)
		if d >= e:
			return 1.0
		var u := (e - d) / e
		return 0.78 + 0.22 * sqrt(maxf(0.0, 1.0 - u * u))

	func flare(z: float) -> float:
		var f := 0.0
		for axle in [p["axle_f"], p["axle_r"]]:
			var dz: float = z - axle
			f += exp(-pow(dz / (arch_r * 1.05), 2.0)) * 0.03
		return f

	func shoulder(z: float) -> float:
		var b: float = p["belt"]
		var t := top(z)
		var c := cabin(z)
		return lerpf(minf(b, t + 0.03), b, c)

	## Half cross-section: 10 points (x, y, z) from bottom centre to roof centre.
	func section(z: float) -> Array:
		var hw: float = p["hw"] * width_scale(z)
		var side := hw + flare(z)
		var yb := bottom(z)
		var sy := shoulder(z)
		var h := top(z)
		var c := cabin(z)
		var surf := h
		var roof_hw: float = p["roof_hw"] * width_scale(z)
		var pts := [
			Vector2(0.0, yb),
			Vector2(hw * 0.86, yb),
			Vector2(side * 0.985, yb + minf(0.06, (sy - yb) * 0.3)),
			Vector2(side, yb + (sy - yb) * 0.45),
			Vector2(side * 0.985, sy - minf(0.07, (sy - yb) * 0.3)),
			Vector2(hw * 0.93, sy),
			Vector2(hw * lerpf(0.84, 0.89, c), lerpf(sy + 0.02, p["belt"] + 0.035, c)),
			Vector2(lerpf(hw * 0.56, roof_hw, c), lerpf(surf + 0.035, h - 0.07, c)),
			Vector2(lerpf(hw * 0.28, roof_hw * 0.55, c), lerpf(surf + 0.05, h - 0.015, c)),
			Vector2(0.0, lerpf(surf + 0.055, h, c)),
		]
		var out := []
		var top_y: float = pts[9].y
		for q in pts:
			var zz := z
			# Lean the nose and tail fascia backwards towards the top.
			var t := clampf((q.y - yb) / maxf(top_y - yb, 0.05), 0.0, 1.0)
			var d := half_len - absf(z)
			if d < 0.12:
				var lean: float = p["lean_f"] if z < 0.0 else -p["lean_r"]
				zz += lean * t * (1.0 - d / 0.12)
			out.append(Vector3(q.x, q.y, zz))
		return out

	## z of the front fascia surface at height y.
	func front_z(y: float) -> float:
		var s: Array = section(-half_len)
		return _fascia_z(s, y)

	func rear_z(y: float) -> float:
		var s: Array = section(half_len)
		return _fascia_z(s, y)

	## Half width of the body at height y in the section at z.
	func half_width_at(z: float, y: float) -> float:
		var s: Array = section(z)
		var best := 0.0
		for i in 9:
			var a: Vector3 = s[i]
			var b: Vector3 = s[i + 1]
			if (a.y - y) * (b.y - y) <= 0.0 and absf(b.y - a.y) > 1e-5:
				var t := (y - a.y) / (b.y - a.y)
				best = maxf(best, lerpf(a.x, b.x, t))
		return best

	## Body surface z seen from the front (rear = false) or back, at (x, y).
	func surface_z(rear: bool, x: float, y: float) -> float:
		var step := 0.01
		var z := half_len - 0.001 if rear else -half_len + 0.001
		for i in 80:
			if half_width_at(z, y) >= absf(x):
				var fz := rear_z(y) if rear else front_z(y)
				return maxf(fz, z) if not rear else minf(fz, z)
			z += -step if rear else step
		return z

	func _fascia_z(s: Array, y: float) -> float:
		var yb: float = s[0].y
		var yt: float = s[9].y
		var t := clampf((y - yb) / maxf(yt - yb, 0.05), 0.0, 1.0)
		return lerpf(s[0].z, s[9].z, t)


static func _z_samples(sh: _Shape) -> Array:
	var p := sh.p
	var zs := []
	var hl: float = sh.half_len
	var z := -hl
	while z <= hl + 1e-4:
		zs.append(z)
		var step := 0.11
		var d := hl - absf(z)
		if d < 0.4:
			step = 0.05
		for axle in [p["axle_f"], p["axle_r"]]:
			if absf(z - axle) < sh.arch_r + 0.08:
				step = 0.035
		for key in ["ws_base", "ws_top", "roof_end", "rw_base"]:
			if absf(z - p[key]) < 0.12:
				step = minf(step, 0.05)
		z += step
	if absf(zs[zs.size() - 1] - hl) > 0.005:
		zs.append(hl)
	else:
		zs[zs.size() - 1] = hl
	return zs


## Lofts the cross-sections into a smooth body and sorts faces into paint,
## glass and black trim.
static func _loft(kit: MeshKit, sh: _Shape) -> void:
	var p := sh.p
	var zs := _z_samples(sh)
	var rings := []           # Array of Array[Vector3] (closed rings, 18 points)
	var half_idx := []        # per ring vertex: half-profile index 0..9
	for z in zs:
		var half: Array = sh.section(z)
		var ring := []
		for i in 10:
			ring.append(half[i])
		for i in range(8, 0, -1):
			var q: Vector3 = half[i]
			ring.append(Vector3(-q.x, q.y, q.z))
		rings.append(ring)
	for i in 10:
		half_idx.append(i)
	for i in range(8, 0, -1):
		half_idx.append(i)
	var n_ring: int = rings[0].size()
	var n_sec := rings.size()
	# Vertex normals from the surrounding faces.
	var normals := []
	for j in n_sec:
		var row := []
		for i in n_ring:
			row.append(Vector3.ZERO)
		normals.append(row)
	for j in n_sec - 1:
		for i in n_ring:
			var i2 := (i + 1) % n_ring
			var a: Vector3 = rings[j][i]
			var b: Vector3 = rings[j][i2]
			var c: Vector3 = rings[j + 1][i2]
			var d: Vector3 = rings[j + 1][i]
			var n := (b - a).cross(d - a) + (c - b).cross(a - b) * 0.0
			var centre := Vector3(0, (a.y + c.y) * 0.5, a.z)
			# Orient outwards.
			var mid := (a + b + c + d) * 0.25
			var out_dir := mid - Vector3(0, 0.55, mid.z)
			if n.dot(out_dir) < 0.0:
				n = -n
			for jj in [j, j + 1]:
				normals[jj][i] += n
				normals[jj][i2] += n
	# Faces.
	for j in n_sec - 1:
		var zm: float = (zs[j] + zs[j + 1]) * 0.5
		var c_cab := sh.cabin(zm)
		for i in n_ring:
			var i2 := (i + 1) % n_ring
			var k := mini(half_idx[i], half_idx[i2])   # segment index on the half profile
			var surface := _face_surface(p, k, zm, c_cab)
			var col := Color.WHITE
			if surface == "base":
				col = BLACK if k <= 1 else TRIM
			elif surface == "glass":
				col = Color("1b222b")
			var a: Vector3 = rings[j][i]
			var b: Vector3 = rings[j][i2]
			var c: Vector3 = rings[j + 1][i2]
			var d: Vector3 = rings[j + 1][i]
			var na: Vector3 = normals[j][i].normalized()
			var nb: Vector3 = normals[j][i2].normalized()
			var nc: Vector3 = normals[j + 1][i2].normalized()
			var nd: Vector3 = normals[j + 1][i].normalized()
			# Glass and trims get flat-ish normals so they read as separate panels.
			var fn := (b - a).cross(d - a).normalized()
			var mid := (a + b + c + d) * 0.25
			if fn.dot(mid - Vector3(0, 0.55, mid.z)) < 0.0:
				fn = -fn
			if surface == "glass":
				na = na.lerp(fn, 0.6).normalized()
				nb = nb.lerp(fn, 0.6).normalized()
				nc = nc.lerp(fn, 0.6).normalized()
				nd = nd.lerp(fn, 0.6).normalized()
			_quad_out(kit, surface, a, b, c, d, na, nb, nc, nd, fn, col)
	# Caps (front and rear fascia) as fans.
	for end in [0, n_sec - 1]:
		var ring: Array = rings[end]
		var centre := Vector3.ZERO
		for q in ring:
			centre += q
		centre /= ring.size()
		var outward := Vector3(0, 0, -1) if end == 0 else Vector3(0, 0, 1)
		var nrm := outward.normalized()
		for i in n_ring:
			var a2: Vector3 = ring[i]
			var b2: Vector3 = ring[(i + 1) % n_ring]
			var surf := "paint"
			var colr := Color.WHITE
			if maxf(a2.y, b2.y) < p["bumper_low"] + 0.05:
				surf = "base"
				colr = BLACK
			if (b2 - a2).cross(centre - a2).dot(outward) > 0.0:
				kit.tri_smooth(surf, a2, b2, centre, nrm, nrm, nrm, colr)
			else:
				kit.tri_smooth(surf, a2, centre, b2, nrm, nrm, nrm, colr)


static func _quad_out(kit: MeshKit, surface: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3, fn: Vector3, col: Color) -> void:
	if (b - a).cross(c - a).dot(fn) >= 0.0:
		kit.tri_smooth(surface, a, b, c, na, nb, nc, col)
		kit.tri_smooth(surface, a, c, d, na, nc, nd, col)
	else:
		kit.tri_smooth(surface, a, c, b, na, nc, nb, col)
		kit.tri_smooth(surface, a, d, c, na, nd, nc, col)


static func _face_surface(p: Dictionary, k: int, z: float, cab: float) -> String:
	if k <= 1:
		return "base"
	var wsb: float = p["ws_base"]
	var wst: float = p["ws_top"]
	var re: float = p["roof_end"]
	var rwb: float = p["rw_base"]
	if k == 6:
		var a_end := lerpf(wsb, wst, 0.42) + 0.05
		var c_start := lerpf(re, rwb, 0.55 if p.get("coupe", false) else 0.38)
		if cab > 0.55 and z > a_end and z < c_start and absf(z - p["b_pillar"]) > 0.045:
			return "glass"
		return "paint"
	if k >= 7:
		if z > wsb + 0.05 and z < wst - 0.03:
			return "glass"
		if z > re + 0.05 and z < rwb - 0.06:
			return "glass"
	return "paint"


# --- details ------------------------------------------------------------------------------

## Thin panel on the front (sign -1) or rear (sign +1) fascia.
static func _fascia_box(kit: MeshKit, sh: _Shape, rear: bool, x: float, y: float, w: float, h: float, surface: String, col: Color, depth := 0.03, out := 0.0) -> void:
	var reach := absf(x) + w * 0.5 - 0.02
	var z := sh.surface_z(rear, reach * signf(x) if absf(x) > 0.001 else w * 0.5, y)
	if rear:
		z = minf(z, sh.surface_z(rear, maxf(absf(x) - w * 0.5, 0.0), y))
	else:
		z = maxf(z, sh.surface_z(rear, maxf(absf(x) - w * 0.5, 0.0), y))
	var z2 := sh.rear_z(y + h * 0.5) if rear else sh.front_z(y + h * 0.5)
	var tilt := atan2(z2 - (sh.rear_z(y) if rear else sh.front_z(y)), h * 0.5)
	var s := 1.0 if rear else -1.0
	kit.xform = Transform3D(Basis(Vector3.RIGHT, tilt), Vector3(x, y, z + s * (out + depth * 0.25)))
	kit.box(surface, Vector3.ZERO, Vector3(w, h, depth), col)
	kit.xform = Transform3D.IDENTITY


static func _front(kit: MeshKit, sh: _Shape, p: Dictionary) -> void:
	var low: float = p["bumper_low"]
	if p["front"] == "kidney":
		# Wide angular headlights with LED brows.
		for s: float in [-1.0, 1.0]:
			_fascia_box(kit, sh, false, s * 0.52, 0.665, 0.44, 0.15, "detail", Color("15181d"), 0.03, 0.005)
			_fascia_box(kit, sh, false, s * 0.52, 0.715, 0.40, 0.025, "lamp", LED, 0.02, 0.02)
			_fascia_box(kit, sh, false, s * 0.70, 0.665, 0.025, 0.11, "lamp", LED, 0.02, 0.02)
			_fascia_box(kit, sh, false, s * 0.52, 0.615, 0.30, 0.02, "lamp", LED, 0.02, 0.02)
			for q in 2:
				_fascia_box(kit, sh, false, s * (0.44 + q * 0.15), 0.665, 0.08, 0.07, "lamp", Color("dfe8f5"), 0.02, 0.018)
			# Kidney grille.
			_fascia_box(kit, sh, false, s * 0.15, 0.625, 0.27, 0.25, "detail", Color("2a2c31"), 0.04, 0.0)
			_fascia_box(kit, sh, false, s * 0.15, 0.625, 0.23, 0.21, "detail", BLACK, 0.04, 0.012)
			for b in 5:
				_fascia_box(kit, sh, false, s * (0.055 + b * 0.045), 0.625, 0.012, 0.19, "detail", Color("3a3d44"), 0.02, 0.02)
			# Big side intakes.
			_fascia_box(kit, sh, false, s * 0.68, 0.40, 0.26, 0.24, "detail", BLACK, 0.04, 0.008)
			_fascia_box(kit, sh, false, s * 0.68, 0.40, 0.03, 0.22, "detail", Color("2a2c31"), 0.03, 0.02)
		# Centre intake and splitter.
		_fascia_box(kit, sh, false, 0.0, 0.36, 0.82, 0.16, "detail", BLACK, 0.04, 0.008)
		_fascia_box(kit, sh, false, 0.0, low + 0.02, 1.70, 0.04, "base", BLACK, 0.12, 0.02)
	else:
		# Swept headlights.
		for s: float in [-1.0, 1.0]:
			_fascia_box(kit, sh, false, s * 0.55, 0.655, 0.44, 0.12, "detail", Color("15181d"), 0.03, 0.005)
			_fascia_box(kit, sh, false, s * 0.55, 0.69, 0.40, 0.022, "lamp", LED, 0.02, 0.02)
			_fascia_box(kit, sh, false, s * 0.62, 0.645, 0.12, 0.06, "lamp", Color("dfe8f5"), 0.02, 0.018)
			# AMG-style side intakes with a blade.
			_fascia_box(kit, sh, false, s * 0.66, 0.38, 0.30, 0.20, "detail", BLACK, 0.04, 0.008)
			_fascia_box(kit, sh, false, s * 0.66, 0.38, 0.28, 0.025, "detail", Color("2a2c31"), 0.03, 0.02)
		# Wide grille with two bars.
		_fascia_box(kit, sh, false, 0.0, 0.565, 0.70, 0.24, "detail", BLACK, 0.04, 0.008)
		_fascia_box(kit, sh, false, 0.0, 0.565, 0.66, 0.035, "detail", CHROME, 0.03, 0.02)
		kit.cylinder("detail", Vector3(0, 0.565, sh.front_z(0.565) - 0.035), 0.075, 0.03, 16, CHROME, "z")
		kit.cylinder("detail", Vector3(0, 0.565, sh.front_z(0.565) - 0.05), 0.055, 0.01, 16, BLACK, "z")
		_fascia_box(kit, sh, false, 0.0, 0.33, 0.70, 0.10, "detail", BLACK, 0.04, 0.008)
		_fascia_box(kit, sh, false, 0.0, low + 0.02, 1.66, 0.04, "base", BLACK, 0.14, 0.03)


static func _rear(kit: MeshKit, sh: _Shape, p: Dictionary) -> void:
	var low: float = p["bumper_low"]
	if p["rear"] == "l_lamps":
		for s: float in [-1.0, 1.0]:
			_fascia_box(kit, sh, true, s * 0.62, 0.86, 0.48, 0.11, "lamp", RED, 0.03, 0.005)
			_fascia_box(kit, sh, true, s * 0.62, 0.86, 0.40, 0.03, "lamp", Color("ff4048"), 0.02, 0.02)
			_fascia_box(kit, sh, true, s * 0.80, 0.80, 0.12, 0.10, "lamp", RED_DARK, 0.03, 0.006)
			# Quad exhaust.
			for q: float in [-1.0, 1.0]:
				var x := s * (0.58 + q * 0.07)
				kit.cylinder("detail", Vector3(x, 0.30, sh.rear_z(0.30) + 0.02), 0.045, 0.10, 10, CHROME, "z")
				kit.cylinder("detail", Vector3(x, 0.30, sh.rear_z(0.30) + 0.071), 0.032, 0.005, 10, BLACK, "z")
		_fascia_box(kit, sh, true, 0.0, 0.31, 1.40, 0.13, "detail", BLACK, 0.05, 0.005)
		# Boot lip spoiler.
		var zr := sh.rear_z(p["tail_h"]) - 0.06
		kit.taper_box("paint", Vector3(0, p["tail_h"] + 0.045, zr), Vector3(1.20, 0.04, 0.12), Vector2(1.0, 0.6), Color.WHITE)
	else:
		for s: float in [-1.0, 1.0]:
			_fascia_box(kit, sh, true, s * 0.60, 0.84, 0.50, 0.08, "lamp", RED, 0.03, 0.005)
			_fascia_box(kit, sh, true, s * 0.60, 0.84, 0.44, 0.02, "lamp", Color("ff4048"), 0.02, 0.02)
			for q: float in [-1.0, 1.0]:
				var x2 := s * (0.56 + q * 0.08)
				_fascia_box(kit, sh, true, x2, 0.30, 0.11, 0.06, "detail", CHROME, 0.06, 0.01)
				_fascia_box(kit, sh, true, x2, 0.30, 0.08, 0.035, "detail", BLACK, 0.06, 0.02)
		_fascia_box(kit, sh, true, 0.0, 0.31, 1.30, 0.12, "detail", BLACK, 0.05, 0.005)
		_fascia_box(kit, sh, true, 0.0, 0.80, 0.42, 0.018, "detail", CHROME, 0.02, 0.012)
	_fascia_box(kit, sh, true, 0.0, low + 0.03, 1.60, 0.04, "base", BLACK, 0.08, 0.0)


static func _sides(kit: MeshKit, sh: _Shape, p: Dictionary) -> void:
	var belt: float = p["belt"]
	var hw: float = p["hw"]
	var wsb: float = p["ws_base"]
	var mirror_z := lerpf(wsb, p["ws_top"], 0.38)
	for s: float in [-1.0, 1.0]:
		# Mirrors on the doors.
		var base_x := sh.half_width_at(mirror_z, belt + 0.05)
		var mx := s * base_x
		kit.box("detail", Vector3(mx + s * 0.03, belt + 0.07, mirror_z + 0.06), Vector3(0.08, 0.05, 0.10), BLACK)
		kit.taper_box("paint", Vector3(mx + s * 0.13, belt + 0.11, mirror_z + 0.04), Vector3(0.17, 0.10, 0.10), Vector2(0.9, 0.85), Color.WHITE)
		kit.box("detail", Vector3(mx + s * 0.13, belt + 0.11, mirror_z + 0.093), Vector3(0.14, 0.07, 0.01), Color("2c3540"))
		# Door shut lines and handles.
		var a_z := lerpf(wsb, p["ws_top"], 0.42)
		var door_lines := [a_z + 0.02, p["b_pillar"], lerpf(p["roof_end"], p["rw_base"], 0.45)]
		for z in door_lines:
			var w := sh.width_scale(z) * hw + sh.flare(z)
			var yb := sh.bottom(z)
			kit.box("detail", Vector3(s * (w + 0.003), (yb + belt) * 0.5 + 0.02, z), Vector3(0.008, belt - yb - 0.08, 0.012), Color("0d0e10"))
		for z2 in [p["b_pillar"] - 0.28, door_lines[2] - 0.30]:
			var w2 := sh.width_scale(z2) * hw + sh.flare(z2) * 0.5
			kit.box("detail", Vector3(s * (w2 + 0.01), belt - 0.07, z2), Vector3(0.025, 0.025, 0.14), CHROME if p["front"] == "wide" else Color("2a2c31"))
		# Chrome window line (CLS) or black (M5).
		var c0 := a_z + 0.05
		var c1 := lerpf(p["roof_end"], p["rw_base"], 0.55 if p.get("coupe", false) else 0.38)
		var line_col := CHROME if p["front"] == "wide" else BLACK
		kit.box("detail", Vector3(s * (hw * 0.86), belt + 0.035, (c0 + c1) * 0.5), Vector3(0.02, 0.018, c1 - c0), line_col)
		# Front fender vent.
		var vz: float = p["axle_f"] + sh.arch_r + 0.18
		kit.box("detail", Vector3(s * (sh.width_scale(vz) * hw + sh.flare(vz) + 0.004), 0.62, vz), Vector3(0.01, 0.06, 0.16), BLACK)


static func _plates(root: Node3D, sh: _Shape, p: Dictionary) -> void:
	for rear in [false, true]:
		var y := 0.62 if rear else 0.50
		var kit := MeshKit.new()
		_fascia_box(kit, sh, rear, 0.0, y, 0.52, 0.12, "detail", PLATE, 0.02, 0.025)
		_fascia_box(kit, sh, rear, -0.235, y, 0.045, 0.11, "detail", Color("1f4fb8"), 0.02, 0.03)
		var mi := MeshInstance3D.new()
		mi.name = "PlateRear" if rear else "PlateFront"
		mi.mesh = kit.build(Mats.for_car(Color.WHITE, 0.0))
		root.add_child(mi)
		var l := Label3D.new()
		l.name = "PlateText"
		l.text = p["plate"]
		l.font_size = 64
		l.pixel_size = 0.0016
		l.modulate = Color("16181c")
		l.outline_size = 0
		l.shaded = false
		var z := sh.rear_z(y) if rear else sh.front_z(y)
		l.position = Vector3(0.02, y, z + (0.042 if rear else -0.042))
		l.rotation.y = 0.0 if rear else PI
		mi.add_child(l)


# --- wheels -------------------------------------------------------------------------------------

## Low-profile tyre with a big concave black multi-spoke rim, facing +X.
static func wheel_mesh(r: float, w: float, spokes: int) -> ArrayMesh:
	var kit := MeshKit.new()
	kit.cylinder("base", Vector3.ZERO, r, w, 20, Color("1b1b1e"), "x", -1.0, Color("26262a"))
	var face := w * 0.5
	var rr := r * 0.78
	# Brake disc visible behind the spokes.
	kit.cylinder("detail", Vector3(face - 0.06, 0, 0), rr * 0.82, 0.02, 18, Color("7d8188"), "x")
	kit.cylinder("detail", Vector3(face - 0.05, 0, 0), rr * 0.42, 0.025, 14, Color("4a4d53"), "x")
	# Rim lip.
	for i in 20:
		var a := TAU * i / 20.0
		kit.xform = Transform3D(Basis(Vector3.RIGHT, a), Vector3.ZERO)
		kit.box("detail", Vector3(face - 0.004, rr, 0), Vector3(0.03, r * 0.06, rr * 0.33), Color("2a2c30"))
	# Concave spokes: from the hub (deep) out to the lip.
	for i in spokes:
		var a2 := TAU * i / float(spokes)
		kit.xform = Transform3D(Basis(Vector3.RIGHT, a2), Vector3.ZERO)
		kit.hexa("detail", [
			Vector3(face - 0.03, rr * 0.22, -0.018), Vector3(face - 0.012, rr * 0.22, -0.018),
			Vector3(face - 0.012, rr * 0.22, 0.018), Vector3(face - 0.03, rr * 0.22, 0.018),
			Vector3(face - 0.012, rr * 0.98, -0.012), Vector3(face + 0.004, rr * 0.98, -0.012),
			Vector3(face + 0.004, rr * 0.98, 0.012), Vector3(face - 0.012, rr * 0.98, 0.012),
		], Color("1a1b1e"))
	kit.xform = Transform3D.IDENTITY
	kit.cylinder("detail", Vector3(face - 0.01, 0, 0), rr * 0.24, 0.04, 12, Color("232428"), "x")
	kit.cylinder("detail", Vector3(face + 0.012, 0, 0), rr * 0.10, 0.01, 10, Color("3a3c41"), "x")
	return kit.build(Mats.for_car(Color.WHITE, 0.01))


static func caliper_mesh(r: float, col: Color) -> ArrayMesh:
	var kit := MeshKit.new()
	var rr := r * 0.78
	kit.xform = Transform3D(Basis(Vector3.RIGHT, -0.6), Vector3.ZERO)
	kit.box("base", Vector3(0.05, rr * 0.66, 0), Vector3(0.05, rr * 0.30, rr * 0.55), col)
	kit.xform = Transform3D.IDENTITY
	return kit.build(Mats.for_car(Color.WHITE, 0.0))


static func _own(node: Node, owner: Node) -> void:
	for c in node.get_children():
		c.owner = owner
		_own(c, owner)
