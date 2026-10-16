class_name BlenderCar
extends RefCounted
## Cars modelled in Blender by tools/blender/build_cars.py (FR-Legends style).
##
## The GLB holds "Body", "WheelFL/FR/RL/RR" (origin at the wheel centre) and
## fixed "CaliperFL…". This turns it into the layout Car expects:
## Body + WheelXX (steering pivot) → Spin → Rim, with the caliper on the
## steering pivot so it does not roll with the wheel.

const FILES := {"m5": "res://models/cars/m5_frl.glb", "cls": "res://models/cars/cls_frl.glb"}
const DIMS := {
	"m5": {"length": 4.96, "width": 1.92, "height": 1.47, "axle_f": -1.50, "axle_r": 1.46, "track": 0.80, "radius": 0.355, "tyre_w": 0.27},
	"cls": {"length": 4.93, "width": 1.88, "height": 1.43, "axle_f": -1.46, "axle_r": 1.42, "track": 0.79, "radius": 0.35, "tyre_w": 0.26},
}

static var _cache := {}


static func available(kind: String) -> bool:
	return FILES.has(kind) and ResourceLoader.exists(FILES[kind])


static func build(kind: String) -> Node3D:
	var parts := _parts(kind)
	var root := Node3D.new()
	root.name = kind.to_upper()
	for k in DIMS[kind]:
		root.set_meta(k, DIMS[kind][k])
	root.set_meta("kind", kind)
	root.set_meta("stylized", true)
	root.set_meta("paint_surface", parts["paint_surface"])
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = parts["body"]
	root.add_child(body)
	for wn in ["FL", "FR", "RL", "RR"]:
		var w := Node3D.new()
		w.name = "Wheel" + wn
		w.position = parts["centres"][wn]
		if parts["calipers"].has(wn):
			var cal := MeshInstance3D.new()
			cal.name = "Caliper"
			cal.mesh = parts["calipers"][wn]
			w.add_child(cal)
		var spin := Node3D.new()
		spin.name = "Spin"
		w.add_child(spin)
		var rim := MeshInstance3D.new()
		rim.name = "Rim"
		rim.mesh = parts["wheels"][wn]
		spin.add_child(rim)
		root.add_child(w)
	return root


static func _parts(kind: String) -> Dictionary:
	if _cache.has(kind):
		return _cache[kind]
	var src: Node = (load(FILES[kind]) as PackedScene).instantiate()
	var out := {"body": null, "wheels": {}, "calipers": {}, "centres": {}, "paint_surface": -1}
	for mi in src.find_children("*", "MeshInstance3D", true, false):
		var n: String = mi.name
		var holder: Node3D = mi
		# glTF import may put the mesh under a node of the same name.
		if not (n.begins_with("Body") or n.begins_with("Wheel") or n.begins_with("Caliper")):
			holder = mi.get_parent()
			n = holder.name
		var xf := _xf(src, holder)
		if n.begins_with("Body"):
			out["body"] = mi.mesh
		elif n.begins_with("Wheel"):
			var wn := n.substr(5, 2)
			out["wheels"][wn] = mi.mesh
			out["centres"][wn] = xf.origin
		elif n.begins_with("Caliper"):
			out["calipers"][n.substr(7, 2)] = mi.mesh
	var body: Mesh = out["body"]
	for i in body.get_surface_count():
		var m := body.surface_get_material(i)
		if m and m.resource_name == "Paint":
			out["paint_surface"] = i
	src.free()
	_cache[kind] = out
	return out


static func _xf(base: Node, node: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur := node
	while cur != null and cur != base:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t
