extends Node
## CPU cost check: drives the player's car around for a while with traffic,
## police and pedestrians active and reports average frame / physics time.
var main: Main
func _ready():
	Game.data = Game.default_data()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(0.3, true, true).timeout
	main.menus._close_all()
	main.start_game()
	var car := main.my_car
	car.place(Transform3D(Basis(Vector3.UP, -PI / 2), Vector3(-240, 0.6, 6)))
	main.player.enter(car)
	car.driver = "player"
	main.rig.follow(car, true)
	main.police.force_wanted(2)
	await get_tree().create_timer(3.0, true, true).timeout
	var proc := 0.0
	var phys := 0.0
	var n := 0
	Input.action_press("forward")
	for i in 600:
		await get_tree().process_frame
		if i % 120 == 60:
			Input.action_press("left")
		if i % 120 == 80:
			Input.action_release("left")
		proc += Performance.get_monitor(Performance.TIME_PROCESS)
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		n += 1
	print("PERF frames=%d avg_process=%.2f ms avg_physics_step=%.2f ms cars=%d peds=%d objects=%d" % [n, proc / n * 1000.0, phys / n * 1000.0, main.cars.size(), main.peds.peds.size(), Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	get_tree().quit()
