extends SceneTree
## Regenerates every model in res://models/ (Godot scenes + .glb copies).
##
##   godot --headless --path . -s res://scripts/tools/build_models.gd
##
## The game loads these files; if one is missing it builds the same model
## from code at runtime, so the folder can always be rebuilt from scratch.

func _initialize() -> void:
	var out := {}
	for kind in ["sado", "chabuk", "posbon"]:
		out["cars/" + kind] = CarBuilder.build(kind)
	# m5 / cls come from the Blender GLBs (tools/blender/build_cars.py), see BlenderCar.
	for style in ["sport", "steel"]:
		var mi := MeshInstance3D.new()
		mi.name = "Wheel_" + style
		mi.mesh = CarBuilder.wheel_mesh(style, 0.31, 0.21)
		out["cars/wheel_" + style] = mi
	if ClassDB.class_exists("Node") and ResourceLoader.exists("res://scripts/models/person_builder.gd"):
		var pb = load("res://scripts/models/person_builder.gd")
		for key in pb.PRESETS:
			out["people/" + key] = pb.build(key)
	if ResourceLoader.exists("res://scripts/models/prop_builder.gd"):
		var prb = load("res://scripts/models/prop_builder.gd")
		for key in prb.CATALOG:
			out[key] = prb.build(key)
	var count := 0
	for path in out:
		var node: Node = out[path]
		var dir: String = "res://models/" + path.get_base_dir()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		_own(node, node)
		var ps := PackedScene.new()
		var err := ps.pack(node)
		if err != OK:
			push_error("pack failed for %s" % path)
			continue
		err = ResourceSaver.save(ps, "res://models/%s.tscn" % path)
		if err != OK:
			push_error("save failed for %s" % path)
			continue
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_scene(node, state) == OK:
			doc.write_to_filesystem(state, ProjectSettings.globalize_path("res://models/%s.glb" % path))
		count += 1
		node.free()
	print("RAYON: built %d models into res://models/" % count)
	quit()


func _own(node: Node, owner: Node) -> void:
	for c in node.get_children():
		c.owner = owner
		_own(c, owner)
