class_name Player
extends CharacterBody3D
## The hero on foot: walks and runs relative to the camera, animates, and
## gets in / out of cars.

const WALK := 2.3
const RUN := 6.2
const ACCEL := 14.0
const GRAVITY := 22.0

var model: Node3D
var rig: PersonRig
var cam_yaw := 0.0             # set by the camera rig
var car: Car = null            # car currently driven
var input_enabled := true
var _anim_speed := 0.0


func _ready() -> void:
	name = "Player"
	collision_layer = 4
	collision_mask = 1 | 2
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.875
	add_child(cs)
	model = Models.instance("people/hero")
	model.name = "Model"
	add_child(model)
	rig = PersonRig.new(model)


func in_car() -> bool:
	return car != null


func _physics_process(delta: float) -> void:
	if in_car():
		return
	var dir := Vector3.ZERO
	var running := false
	if input_enabled:
		var iv := Input.get_vector("left", "right", "forward", "back")
		var basis := Basis(Vector3.UP, cam_yaw)
		dir = basis * Vector3(iv.x, 0, iv.y)
		if dir.length() > 1.0:
			dir = dir.normalized()
		running = Input.is_action_pressed("run")
	var target := dir * (RUN if running else WALK)
	var hv := Vector3(velocity.x, 0, velocity.z)
	hv = hv.move_toward(target, ACCEL * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	# Step up curbs: if blocked while walking, nudge upward.
	if is_on_wall() and dir.length() > 0.1 and is_on_floor():
		var test := global_transform
		test.origin.y += 0.2
		if not test_move(test, dir * 0.15):
			global_position.y += 0.16
	var flat := Vector3(velocity.x, 0, velocity.z)
	if flat.length() > 0.3:
		var yaw := atan2(-flat.x, -flat.z)
		model.rotation.y = lerp_angle(model.rotation.y, yaw, clampf(delta * 12.0, 0.0, 1.0))
	_anim_speed = flat.length()


func _process(delta: float) -> void:
	if in_car():
		return
	var mode := PersonRig.Mode.IDLE
	if _anim_speed > 3.5:
		mode = PersonRig.Mode.RUN
	elif _anim_speed > 0.3:
		mode = PersonRig.Mode.WALK
	rig.update(delta, mode, _anim_speed)


func facing() -> Vector3:
	return model.global_basis * Vector3(0, 0, -1)


## Enter a car: hide the body and disable collisions.
func enter(c: Car) -> void:
	car = c
	visible = false
	for ch in get_children():
		if ch is CollisionShape3D:
			ch.disabled = true
	velocity = Vector3.ZERO


## Leave the car at a free spot.
func exit_to(pos: Vector3, yaw: float) -> void:
	car = null
	global_position = pos
	model.rotation.y = yaw
	velocity = Vector3.ZERO
	visible = true
	for ch in get_children():
		if ch is CollisionShape3D:
			ch.disabled = false


func teleport(pos: Vector3, yaw := 0.0) -> void:
	global_position = pos
	model.rotation.y = yaw
	velocity = Vector3.ZERO
