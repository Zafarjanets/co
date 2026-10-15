extends Node
## Renders a few in-game screenshots into res://docs/ (needs a display).
var main: Main
func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://docs/%s.png" % name)
	print("shot ", name)
func wait(t: float) -> void:
	await get_tree().create_timer(t, true, true).timeout
func _ready():
	Game.data = Game.default_data()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await wait(0.5)
	await shot("menu")
	main.menus._close_all()
	main.start_game()
	main.hud.toast("", 0.0)
	# Hero among shops on the avenue.
	main.player.teleport(Vector3(-62, 0.15, 13), PI * 0.85)
	main.rig.yaw = PI * 0.82
	main.rig.pitch = -0.12
	await wait(2.5)
	await shot("hero_street")
	# SADO on the avenue with traffic ahead.
	var car := main.my_car
	car.place(Transform3D(Basis(Vector3.UP, -PI / 2), Vector3(-180, 0.6, 6)))
	main.player.enter(car)
	car.driver = "player"
	main.rig.follow(car, true)
	Input.action_press("forward")
	await wait(2.5)
	Input.action_release("forward")
	await wait(0.6)
	await shot("driving")
	# Police chase.
	main.police.force_wanted(2)
	for d in main.police.cops:
		pass
	await wait(6.0)
	await shot("chase")
	main.police.clear_wanted()
	# Drift pad.
	car.place(Transform3D(Basis.IDENTITY, Vector3(175, 0.6, -30)))
	main.rig.follow(car, true)
	Input.action_press("forward")
	await wait(2.4)
	Input.action_press("left")
	await wait(0.5)
	Input.action_press("handbrake")
	await wait(0.35)
	Input.action_release("handbrake")
	await wait(0.6)
	await shot("drift")
	Input.action_release("left")
	Input.action_release("forward")
	# Garage menu.
	car.place(Transform3D(Basis.IDENTITY, CityLayout.GARAGE_POS + Vector3(0, 0.5, 0)))
	await wait(0.5)
	main.menus.show_garage()
	await wait(0.3)
	await shot("garage")
	get_tree().quit()
