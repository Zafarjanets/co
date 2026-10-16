extends SceneTree
## Renders a turntable-style preview of saved models to a PNG (needs a display).
##
##   godot --path . --rendering-driver opengl3 -s res://scripts/tools/preview.gd -- out.png cars/sado cars/chabuk ...

var _frames := 0
var _out := "preview.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	var names := args.slice(1)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("efe9dc")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.82, 0.9)
	e.ambient_light_energy = 0.7
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.shadow_enabled = true
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.6
	world.add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("e5ded0")
	floor.material_override = fm
	world.add_child(floor)
	var x := 0.0
	var max_w := 0.0
	var max_h := 0.0
	for n in names:
		var inst: Node3D = Models.instance(n)
		var aabb := _aabb(inst)
		world.add_child(inst)
		inst.position = Vector3(x - aabb.position.x, 0, 0)
		inst.rotation.y = float(OS.get_environment("PREVIEW_YAW")) if OS.get_environment("PREVIEW_YAW") != "" else -0.6
		x += aabb.size.x + maxf(1.0, aabb.size.x * 0.25)
		max_w = x
		max_h = maxf(max_h, aabb.size.y)
	var cam := Camera3D.new()
	world.add_child(cam)
	var centre := Vector3(max_w * 0.5 - 0.5, max_h * 0.4, 0)
	var dist := maxf(max_w * 0.75, max_h * 1.6) + 2.0
	var hk := float(OS.get_environment("PREVIEW_HEIGHT")) if OS.get_environment("PREVIEW_HEIGHT") != "" else 0.35
	cam.look_at_from_position(centre + Vector3(0, dist * hk, dist), centre)
	cam.fov = 45


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 8:
		var img := root.get_texture().get_image()
		img.save_png(_out)
		print("saved ", _out)
		return true
	return false


func _aabb(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for c in _all(node):
		if c is MeshInstance3D and c.mesh:
			var b: AABB = _global_xf(c) * c.mesh.get_aabb()
			if first:
				box = b
				first = false
			else:
				box = box.merge(b)
	return box


func _global_xf(n: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur := n
	while cur is Node3D:
		t = cur.transform * t
		cur = cur.get_parent()
	return t


func _all(n: Node) -> Array:
	var r := [n]
	for c in n.get_children():
		r.append_array(_all(c))
	return r
