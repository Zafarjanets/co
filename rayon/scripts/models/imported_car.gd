class_name ImportedCar
extends RefCounted
## Turns the user's GLB car models (res://models/imported/*.glb) into the car
## layout the game expects (Body + WheelFL/FR/RL/RR → Spin → Rim).
##
## The GLBs are made of ~260 small parts each; drawing them as-is would cost
## hundreds of draw calls per car. Here every part is merged into one surface
## per material (the body) and one mesh per wheel, so a car costs about 20 draw
## calls. Geometry, scale and materials stay exactly as in the GLB.

const MODELS := {
	"m5": {"file": "res://models/imported/BMW_M5_F90.glb", "title": "M5", "paint_material": "M5 charcoal"},
	"cls": {"file": "res://models/imported/Mercedes_CLS_2014.glb", "title": "CLS", "paint_material": "CLS pearl white"},
}
const WHEELS := {"WheelFL": "Wheel_Front_Left", "WheelFR": "Wheel_Front_Right",
	"WheelRL": "Wheel_Rear_Left", "WheelRR": "Wheel_Rear_Right"}
# Measured from the GLBs (metres, nose towards -Z, ground at y = 0).
const DIMS := {"length": 4.97, "width": 1.98, "height": 1.62, "axle_f": -1.48, "axle_r": 1.43,
	"track": 0.96, "radius": 0.365, "tyre_w": 0.33}

static var _cache := {}      # kind -> {body: ArrayMesh, wheels: {name: ArrayMesh}}


static func is_imported(kind: String) -> bool:
	return MODELS.has(kind)


static func build(kind: String) -> Node3D:
	var parts := _merged(kind)
	var root := Node3D.new()
	root.name = MODELS[kind]["title"]
	for k in DIMS:
		root.set_meta(k, DIMS[k])
	root.set_meta("kind", kind)
	root.set_meta("imported", true)
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = parts["body"]
	root.add_child(body)
	for wn in WHEELS:
		var w := Node3D.new()
		w.name = wn
		w.position = parts["centres"][wn]
		var spin := Node3D.new()
		spin.name = "Spin"
		w.add_child(spin)
		var rim := MeshInstance3D.new()
		rim.name = "Rim"
		rim.mesh = parts["wheels"][wn]
		spin.add_child(rim)
		root.add_child(w)
	return root


## Loads the GLB once and merges its parts.
static func _merged(kind: String) -> Dictionary:
	if _cache.has(kind):
		return _cache[kind]
	var scene: PackedScene = load(MODELS[kind]["file"])
	var src: Node3D = scene.instantiate()
	var wheel_nodes := {}
	for wn in WHEELS:
		wheel_nodes[wn] = src.find_child(WHEELS[wn], true, false)
	var body_tools := {}            # material -> SurfaceTool
	var wheel_tools := {}           # wheel name -> {material -> SurfaceTool}
	var centres := {}
	for wn in WHEELS:
		wheel_tools[wn] = {}
		var wnode: Node3D = wheel_nodes[wn]
		centres[wn] = _xf_to(src, wnode).origin if wnode else Vector3(DIMS["track"] * (1 if wn[-1] == "R" else -1), DIMS["radius"], DIMS["axle_f"] if wn[-2] == "F" else DIMS["axle_r"])
	for mi in src.find_children("*", "MeshInstance3D", true, false):
		var owner_wheel := ""
		for wn in WHEELS:
			var wnode: Node3D = wheel_nodes[wn]
			if wnode and (mi == wnode or wnode.is_ancestor_of(mi)):
				owner_wheel = wn
				break
		var xf: Transform3D
		var tools: Dictionary
		if owner_wheel != "":
			xf = _xf_to(wheel_nodes[owner_wheel], mi)
			tools = wheel_tools[owner_wheel]
		else:
			xf = _xf_to(src, mi)
			tools = body_tools
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for si in mesh.get_surface_count():
			var mat: Material = (mi as MeshInstance3D).get_active_material(si)
			if not tools.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[mat] = st
			(tools[mat] as SurfaceTool).append_from(mesh, si, xf)
	var paint_name: String = MODELS[kind]["paint_material"]
	var body := _commit(body_tools, paint_name)
	var wheels := {}
	for wn in WHEELS:
		wheels[wn] = _commit(wheel_tools[wn], "")
	src.free()
	_cache[kind] = {"body": body, "wheels": wheels, "centres": centres}
	return _cache[kind]


static func _commit(tools: Dictionary, paint_name: String) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for mat in tools:
		var st: SurfaceTool = tools[mat]
		st.commit(mesh)
		var idx := mesh.get_surface_count() - 1
		mesh.surface_set_material(idx, mat)
		var mname: String = mat.resource_name if mat else ""
		mesh.surface_set_name(idx, "paint" if mname == paint_name and paint_name != "" else mname)
	return mesh


## Transform of `node` relative to `base` (works outside the scene tree).
static func _xf_to(base: Node, node: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur := node
	while cur != null and cur != base:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t
