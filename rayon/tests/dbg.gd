extends Node
func _ready():
	var main: Main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(0.3, true, true).timeout
	main.menus._close_all()
	main.start_game()
	await get_tree().create_timer(1.0, true, true).timeout
	var car := main.my_car
	print("car pos ", car.global_position, " flipped ", car.is_flipped(), " vel ", car.linear_velocity, " in cars ", main.cars.has(car))
	main.player.teleport(car.global_transform * Vector3(-1.8, 0.2, 0.0))
	await get_tree().create_timer(0.3, true, true).timeout
	print("player ", main.player.global_position, " local ", car.global_transform.affine_inverse() * main.player.global_position)
	print("meta len ", car.model.get_meta("length", -1), " near ", main._nearest_enterable())
	main._interact()
	await get_tree().create_timer(0.3, true, true).timeout
	print("after enter: car ", main.player.car, " visible ", main.player.visible)
	print("exit spot ", main._free_exit_spot(car))
	main._interact()
	await get_tree().create_timer(0.3, true, true).timeout
	print("after exit: car ", main.player.car, " visible ", main.player.visible, " pos ", main.player.global_position)
	get_tree().quit()
