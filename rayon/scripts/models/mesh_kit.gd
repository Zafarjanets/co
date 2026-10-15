class_name MeshKit
extends RefCounted
## Procedural low-poly mesh builder.
##
## Collects flat-shaded triangles grouped by surface name, each vertex with its
## own colour. Every primitive also stores a "smoothed" normal (packed into
## UV + UV2.x) that the outline shader uses to grow a closed inverted hull.

var xform := Transform3D.IDENTITY

var _surfaces := {}
var _order: Array[String] = []
var _part_start := {}


func _surf(name: String) -> Dictionary:
	if not _surfaces.has(name):
		_surfaces[name] = {
			"v": PackedVector3Array(), "n": PackedVector3Array(),
			"c": PackedColorArray(), "s": PackedVector3Array(),
		}
		_order.append(name)
	return _surfaces[name]


func has_geometry() -> bool:
	for k in _order:
		if _surfaces[k]["v"].size() > 0:
			return true
	return false


# --- low level -------------------------------------------------------------

## Triangle given counter-clockwise when seen from its front side.
func tri(surface: String, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var s := _surf(surface)
	var wa := xform * a
	var wb := xform * b
	var wc := xform * c
	var n := (wb - wa).cross(wc - wa)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	# Godot treats clockwise triangles as front faces.
	s["v"].append(wa); s["v"].append(wc); s["v"].append(wb)
	for i in 3:
		s["n"].append(n)
		s["c"].append(col)
		s["s"].append(n)


func quad(surface: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	tri(surface, a, b, c, col)
	tri(surface, a, c, d, col)


## Quad oriented so that its normal points roughly along `outward` (local space).
func quad_facing(surface: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a)
	if n.dot(outward) < 0.0:
		quad(surface, d, c, b, a, col)
	else:
		quad(surface, a, b, c, d, col)


# --- part bookkeeping for outline normals ----------------------------------

func _begin(surface: String) -> void:
	_part_start[surface] = _surf(surface)["v"].size()


func _end(surface: String) -> void:
	var s := _surf(surface)
	var start: int = _part_start.get(surface, 0)
	var acc := {}
	var verts: PackedVector3Array = s["v"]
	var norms: PackedVector3Array = s["n"]
	for i in range(start, verts.size()):
		var key := Vector3i((verts[i] * 1000.0).round())
		acc[key] = acc.get(key, Vector3.ZERO) + norms[i]
	var sm: PackedVector3Array = s["s"]
	for i in range(start, verts.size()):
		var key := Vector3i((verts[i] * 1000.0).round())
		var v: Vector3 = acc[key]
		sm[i] = v.normalized() if v.length_squared() > 1e-8 else norms[i]
	s["s"] = sm


# --- primitives ------------------------------------------------------------

## Hexahedron from 8 corners: bottom ring (4) then top ring (4), same order.
func hexa(surface: String, p: Array, col: Color) -> void:
	_begin(surface)
	var centre := Vector3.ZERO
	for q in p:
		centre += q
	centre /= 8.0
	var faces := [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]
	for f in faces:
		var a: Vector3 = p[f[0]]
		var b: Vector3 = p[f[1]]
		var c: Vector3 = p[f[2]]
		var d: Vector3 = p[f[3]]
		var fc := (a + b + c + d) * 0.25
		quad_facing(surface, a, b, c, d, fc - centre, col)
	_end(surface)


func box(surface: String, center: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	hexa(surface, [
		center + Vector3(-h.x, -h.y, -h.z), center + Vector3(h.x, -h.y, -h.z),
		center + Vector3(h.x, -h.y, h.z), center + Vector3(-h.x, -h.y, h.z),
		center + Vector3(-h.x, h.y, -h.z), center + Vector3(h.x, h.y, -h.z),
		center + Vector3(h.x, h.y, h.z), center + Vector3(-h.x, h.y, h.z),
	], col)


## Box whose top face is shrunk by `top_scale` (x, z) — roofs, cabins, trunks.
func taper_box(surface: String, center: Vector3, size: Vector3, top_scale: Vector2, col: Color, top_offset := Vector3.ZERO) -> void:
	var h := size * 0.5
	var tx := h.x * top_scale.x
	var tz := h.z * top_scale.y
	var t := center + Vector3(0, h.y, 0) + top_offset
	hexa(surface, [
		center + Vector3(-h.x, -h.y, -h.z), center + Vector3(h.x, -h.y, -h.z),
		center + Vector3(h.x, -h.y, h.z), center + Vector3(-h.x, -h.y, h.z),
		t + Vector3(-tx, 0, -tz), t + Vector3(tx, 0, -tz),
		t + Vector3(tx, 0, tz), t + Vector3(-tx, 0, tz),
	], col)


## Cylinder along an axis ("x", "y" or "z").
func cylinder(surface: String, center: Vector3, radius: float, length: float, segments: int, col: Color, axis := "y", radius_top := -1.0, cap_col := Color(-1, 0, 0)) -> void:
	_begin(surface)
	if radius_top < 0.0:
		radius_top = radius
	if cap_col.r < 0.0:
		cap_col = col
	var basis := _axis_basis(axis)
	var hl := length * 0.5
	var ring_a: Array[Vector3] = []
	var ring_b: Array[Vector3] = []
	for i in segments:
		var ang := TAU * float(i) / float(segments)
		var dir := Vector3(cos(ang), 0, sin(ang))
		ring_a.append(center + basis * (dir * radius + Vector3(0, -hl, 0)))
		ring_b.append(center + basis * (dir * radius_top + Vector3(0, hl, 0)))
	var up := basis * Vector3.UP
	var top_c := center + up * hl
	var bot_c := center - up * hl
	for i in segments:
		var j := (i + 1) % segments
		var mid := (ring_a[i] + ring_a[j] + ring_b[i] + ring_b[j]) * 0.25
		quad_facing(surface, ring_a[i], ring_a[j], ring_b[j], ring_b[i], mid - (center + up * up.dot(mid - center)), col)
		_tri_facing(surface, top_c, ring_b[i], ring_b[j], up, cap_col)
		if radius > 0.001:
			_tri_facing(surface, bot_c, ring_a[j], ring_a[i], -up, cap_col)
	_end(surface)


func cone(surface: String, base_center: Vector3, radius: float, height: float, segments: int, col: Color) -> void:
	_begin(surface)
	var tip := base_center + Vector3(0, height, 0)
	for i in segments:
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var p0 := base_center + Vector3(cos(a0), 0, sin(a0)) * radius
		var p1 := base_center + Vector3(cos(a1), 0, sin(a1)) * radius
		var mid := (p0 + p1) * 0.5
		_tri_facing(surface, p0, p1, tip, mid - base_center + Vector3(0, radius * 0.3, 0), col)
		_tri_facing(surface, base_center, p1, p0, Vector3.DOWN, col)
	_end(surface)


## Low-poly ball (icosphere level 1, optionally squashed).
func ball(surface: String, center: Vector3, radius: Vector3, col: Color, jitter := 0.0, rng: RandomNumberGenerator = null) -> void:
	_begin(surface)
	var t := (1.0 + sqrt(5.0)) / 2.0
	var verts: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var faces := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2],
		[10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11],
		[6, 2, 10], [8, 6, 7], [9, 8, 1]]
	# One subdivision for a rounder silhouette.
	var mids := {}
	var faces2 := []
	for f in faces:
		var m := []
		for e in 3:
			var a: int = f[e]
			var b: int = f[(e + 1) % 3]
			var key := "%d_%d" % [mini(a, b), maxi(a, b)]
			if not mids.has(key):
				verts.append((verts[a] + verts[b]) * 0.5)
				mids[key] = verts.size() - 1
			m.append(mids[key])
		faces2.append([f[0], m[0], m[2]])
		faces2.append([f[1], m[1], m[0]])
		faces2.append([f[2], m[2], m[1]])
		faces2.append([m[0], m[1], m[2]])
	var pts: Array[Vector3] = []
	for v in verts:
		var d := v.normalized()
		if jitter > 0.0 and rng != null:
			d *= 1.0 + rng.randf_range(-jitter, jitter)
		pts.append(center + d * radius)
	for f in faces2:
		var a: Vector3 = pts[f[0]]
		var b: Vector3 = pts[f[1]]
		var c: Vector3 = pts[f[2]]
		_tri_facing(surface, a, b, c, (a + b + c) / 3.0 - center, col)
	_end(surface)


## Extrudes a 2D profile drawn in the (z, y) plane between x0 and x1.
func extrude_zy(surface: String, poly: PackedVector2Array, x0: float, x1: float, col: Color) -> void:
	if poly.size() < 3:
		return
	_begin(surface)
	var idx := Geometry2D.triangulate_polygon(poly)
	for i in range(0, idx.size(), 3):
		var a := poly[idx[i]]
		var b := poly[idx[i + 1]]
		var c := poly[idx[i + 2]]
		_tri_facing(surface, Vector3(x1, a.y, a.x), Vector3(x1, b.y, b.x), Vector3(x1, c.y, c.x), Vector3.RIGHT, col)
		_tri_facing(surface, Vector3(x0, a.y, a.x), Vector3(x0, b.y, b.x), Vector3(x0, c.y, c.x), Vector3.LEFT, col)
	var ccw := _signed_area(poly) > 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		var d := q - p
		# Outward normal in (z, y) for a CCW polygon is (dy, -dz).
		var out2 := Vector2(d.y, -d.x) if ccw else Vector2(-d.y, d.x)
		quad_facing(surface, Vector3(x0, p.y, p.x), Vector3(x1, p.y, p.x), Vector3(x1, q.y, q.x), Vector3(x0, q.y, q.x), Vector3(0, out2.y, out2.x), col)
	_end(surface)


## Extrudes a 2D footprint drawn in the (x, z) plane between heights y0 and y1.
func extrude_xz(surface: String, poly: PackedVector2Array, y0: float, y1: float, col: Color) -> void:
	if poly.size() < 3:
		return
	_begin(surface)
	var idx := Geometry2D.triangulate_polygon(poly)
	for i in range(0, idx.size(), 3):
		var a := poly[idx[i]]
		var b := poly[idx[i + 1]]
		var c := poly[idx[i + 2]]
		_tri_facing(surface, Vector3(a.x, y1, a.y), Vector3(b.x, y1, b.y), Vector3(c.x, y1, c.y), Vector3.UP, col)
		_tri_facing(surface, Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(c.x, y0, c.y), Vector3.DOWN, col)
	var ccw := _signed_area(poly) > 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		var d := q - p
		var out2 := Vector2(d.y, -d.x) if ccw else Vector2(-d.y, d.x)
		quad_facing(surface, Vector3(p.x, y0, p.y), Vector3(q.x, y0, q.y), Vector3(q.x, y1, q.y), Vector3(p.x, y1, p.y), Vector3(out2.x, 0, out2.y), col)
	_end(surface)


## Flat quad on the ground (y), useful for road marks: rect in xz.
func ground_rect(surface: String, center: Vector3, size_x: float, size_z: float, col: Color, yaw := 0.0) -> void:
	var b := Basis(Vector3.UP, yaw)
	var hx := b * Vector3(size_x * 0.5, 0, 0)
	var hz := b * Vector3(0, 0, size_z * 0.5)
	quad_facing(surface, center - hx - hz, center + hx - hz, center + hx + hz, center - hx + hz, Vector3.UP, col)


# --- output ----------------------------------------------------------------

func build(materials: Dictionary = {}) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for name in _order:
		var s: Dictionary = _surfaces[name]
		var verts: PackedVector3Array = s["v"]
		if verts.is_empty():
			continue
		var sm: PackedVector3Array = s["s"]
		var uv := PackedVector2Array()
		var uv2 := PackedVector2Array()
		uv.resize(sm.size())
		uv2.resize(sm.size())
		for i in sm.size():
			uv[i] = Vector2(sm[i].x, sm[i].y)
			uv2[i] = Vector2(sm[i].z, 0.0)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = s["n"]
		arrays[Mesh.ARRAY_COLOR] = s["c"]
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var si := mesh.get_surface_count() - 1
		mesh.surface_set_name(si, name)
		if materials.has(name):
			mesh.surface_set_material(si, materials[name])
	return mesh


func triangle_count() -> int:
	var n := 0
	for k in _order:
		n += _surfaces[k]["v"].size() / 3
	return n


# --- helpers ---------------------------------------------------------------

func _tri_facing(surface: String, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a)
	if n.dot(outward) < 0.0:
		tri(surface, a, c, b, col)
	else:
		tri(surface, a, b, c, col)


static func _signed_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


static func _axis_basis(axis: String) -> Basis:
	match axis:
		"x":
			return Basis(Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1))
		"z":
			return Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))
	return Basis.IDENTITY


## Circle polygon in 2D (for boolean cuts such as wheel arches).
static func circle2d(center: Vector2, radius: float, segments := 20) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in segments:
		var a := TAU * float(i) / float(segments)
		p.append(center + Vector2(cos(a), sin(a)) * radius)
	return p


## Polygon minus a list of cut polygons; returns the largest remaining piece list.
static func cut(poly: PackedVector2Array, cuts: Array) -> Array:
	var pieces: Array = [poly]
	for c in cuts:
		var next: Array = []
		for piece in pieces:
			for r in Geometry2D.clip_polygons(piece, c):
				next.append(r)
		pieces = next
	return pieces
