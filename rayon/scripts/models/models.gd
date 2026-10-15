class_name Models
extends RefCounted
## Loads models from res://models/ (built by scripts/tools/build_models.gd).
## If a file is missing the same model is generated from code, so the game
## never breaks because of a deleted or outdated model file.

static var _scenes := {}
static var _meshes := {}
static var _paint := {}


static func instance(path: String) -> Node3D:
	if not _scenes.has(path):
		var file := "res://models/%s.tscn" % path
		if ResourceLoader.exists(file):
			_scenes[path] = load(file)
		else:
			_scenes[path] = null
	var ps: PackedScene = _scenes[path]
	if ps != null:
		return ps.instantiate()
	return _build(path)


static func _build(path: String) -> Node3D:
	var dir := path.get_base_dir()
	var name := path.get_file()
	match dir:
		"cars":
			if name.begins_with("wheel_"):
				var mi := MeshInstance3D.new()
				mi.mesh = CarBuilder.wheel_mesh(name.trim_prefix("wheel_"), 0.31, 0.21)
				var n := Node3D.new()
				n.add_child(mi)
				return n
			return CarBuilder.build(name)
		"people":
			return PersonBuilder.build(name)
	return PropBuilder.build(path)


## First mesh of a model (used for MultiMesh vegetation and props).
static func mesh(path: String) -> Mesh:
	if not _meshes.has(path):
		var n := instance(path)
		var found: Mesh = null
		for c in _walk(n):
			if c is MeshInstance3D and c.mesh:
				found = c.mesh
				break
		_meshes[path] = found
		n.free()
	return _meshes[path]


## Tint the "paint" surface of every mesh under `node`.
static func tint(node: Node, color: Color, outline := 0.05) -> void:
	var key := "%s_%.3f" % [color.to_html(), outline]
	if not _paint.has(key):
		_paint[key] = Mats.paint(color, outline, false)
	var mat: Material = _paint[key]
	for c in _walk(node):
		if c is MeshInstance3D and c.mesh is ArrayMesh:
			var idx: int = (c.mesh as ArrayMesh).surface_find_by_name("paint")
			if idx >= 0:
				c.set_surface_override_material(idx, mat)


static func _walk(n: Node) -> Array:
	var out := [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out
