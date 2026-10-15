class_name CameraRig
extends Node3D
## Third-person camera. On foot: free orbit around the hero. In a car: chases
## from behind, pulls back with speed, and lets the mouse look around for a
## moment before swinging back. A SpringArm3D keeps it out of buildings.

var camera: Camera3D
var arm: SpringArm3D
var yaw := 0.0
var pitch := -0.25
var target_node: Node3D
var in_car := false
var sensitivity := 1.0
var invert_y := false
var _look_timer := 0.0
var _shake := 0.0
var _dist := 4.5


func _ready() -> void:
	name = "CameraRig"
	arm = SpringArm3D.new()
	arm.collision_mask = 1
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	arm.shape = sphere
	arm.margin = 0.2
	add_child(arm)
	camera = Camera3D.new()
	camera.far = 4000.0
	camera.near = 0.1
	camera.fov = 70.0
	camera.current = true
	arm.add_child(camera)


func follow(node: Node3D, car_mode: bool) -> void:
	target_node = node
	in_car = car_mode
	_look_timer = 0.0
	if car_mode:
		yaw = node.global_rotation.y
		pitch = -0.2
	if node:
		global_position = _focus()


func add_shake(amount: float) -> void:
	_shake = clampf(_shake + amount, 0.0, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m: Vector2 = event.relative * 0.0025 * sensitivity
		yaw -= m.x
		pitch += m.y * (1.0 if invert_y else -1.0)
		pitch = clampf(pitch, -1.2, 0.45)
		if in_car:
			_look_timer = 1.6


func _focus() -> Vector3:
	if target_node == null:
		return global_position
	return target_node.global_position + Vector3(0, 1.55 if not in_car else 1.25, 0)


func _process(delta: float) -> void:
	if target_node == null or not is_instance_valid(target_node):
		return
	var focus := _focus()
	var desired_dist := 4.2
	var fov := 70.0
	if in_car:
		var car := target_node as RigidBody3D
		var v := car.linear_velocity
		var speed := Vector2(v.x, v.z).length()
		var heading := car.global_rotation.y
		# When rolling backwards keep looking the way the car faces.
		_look_timer = maxf(0.0, _look_timer - delta)
		if _look_timer <= 0.0:
			var follow_rate := 2.2 + speed * 0.06
			yaw = lerp_angle(yaw, heading, clampf(delta * follow_rate, 0.0, 1.0))
			pitch = lerpf(pitch, -0.2, clampf(delta * 1.5, 0.0, 1.0))
		desired_dist = 6.2 + clampf(speed * 0.06, 0.0, 3.0)
		fov = 70.0 + clampf(speed * 0.3, 0.0, 14.0)
		global_position = global_position.lerp(focus, clampf(delta * 14.0, 0.0, 1.0))
	else:
		global_position = global_position.lerp(focus, clampf(delta * 18.0, 0.0, 1.0))
	_dist = lerpf(_dist, desired_dist, clampf(delta * 3.0, 0.0, 1.0))
	arm.spring_length = _dist
	arm.rotation = Vector3(pitch, yaw, 0)
	camera.fov = lerpf(camera.fov, fov, clampf(delta * 3.0, 0.0, 1.0))
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.5)
		camera.h_offset = randf_range(-1, 1) * _shake * 0.25
		camera.v_offset = randf_range(-1, 1) * _shake * 0.25
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
