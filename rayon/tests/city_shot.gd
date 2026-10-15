extends SceneTree
## Renders the city from a few viewpoints (visual check).
var frames := 0
var cam: Camera3D
var shots := []
var idx := 0
func _initialize():
	var w := Node3D.new()
	root.add_child(w)
	EnvironmentSetup.create(w)
	var t0 := Time.get_ticks_msec()
	var c := CityBuilder.new()
	w.add_child(c)
	c.build()
	print("city built in ", Time.get_ticks_msec() - t0, " ms, colliders ", c.get_node("StaticColliders").get_child_count())
	cam = Camera3D.new()
	cam.far = 3000
	cam.fov = 60
	w.add_child(cam)
	shots = [[Vector3(-60, 3, 5), Vector3(60, 4, 4)], [Vector3(-160, 120, 160), Vector3(0, 0, 0)], [Vector3(-95, 6, -2), Vector3(-95, 2, 30)], [Vector3(150, 25, -10), Vector3(195, 0, -120)], [Vector3(-20, 30, 120), Vector3(0, 0, 200)]]
func _process(d):
	frames += 1
	if frames % 6 == 1 and idx < shots.size():
		cam.look_at_from_position(shots[idx][0], shots[idx][1])
	if frames % 6 == 5:
		root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0] + "/city_%d.png" % idx)
		idx += 1
		if idx >= shots.size():
			quit()
	return false
