extends Node
## Screenshot of the imported cars in the game world (needs a display).
func _ready():
	Game.data = Game.default_data()
	var main: Main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(0.5, true, true).timeout
	main.menus._close_all()
	main.start_game()
	main.hud.toast("", 0.0)
	main.player.teleport(Vector3(-95, 0.2, 13), PI)
	main.rig.yaw = PI + 0.15
	main.rig.pitch = -0.22
	await get_tree().create_timer(2.5, true, true).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://docs/cars_m5_cls.png")
	# Drive the M5.
	var m5: Car = null
	for c in main.cars:
		if c.kind == "m5" and c.has_meta("showcase"):
			m5 = c
	main.player.teleport(m5.global_transform * Vector3(-1.9, 0.2, 0))
	await get_tree().create_timer(0.3, true, true).timeout
	main._interact()
	m5.place(Transform3D(Basis(Vector3.UP, -PI / 2), Vector3(-150, 0.7, 6)))
	main.rig.follow(m5, true)
	Input.action_press("forward")
	await get_tree().create_timer(2.0, true, true).timeout
	Input.action_release("forward")
	await get_tree().create_timer(0.5, true, true).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://docs/drive_m5.png")
	print("in car: ", main.player.car == m5, " speed ", m5.speed_kmh())
	get_tree().quit()
