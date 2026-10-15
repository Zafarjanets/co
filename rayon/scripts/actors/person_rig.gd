class_name PersonRig
extends RefCounted
## Procedural animation for PersonBuilder rigs: swings limbs, bobs the hips
## and poses the body for everyday activities.

enum Mode { IDLE, WALK, RUN, SIT, PHONE, TALK, SWEEP, WAIT, FALLEN, DRIVE, PANIC }

var root: Node3D
var hips: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var phase := 0.0
var t := 0.0
var fall := 0.0           # 0 standing → 1 lying on the ground
var _seed := 0.0


func _init(model: Node3D) -> void:
	root = model
	hips = model.get_node("Hips")
	head = hips.get_node("Head")
	arm_l = hips.get_node("ArmL")
	arm_r = hips.get_node("ArmR")
	leg_l = hips.get_node("LegL")
	leg_r = hips.get_node("LegR")
	_seed = randf() * 10.0


func update(delta: float, mode: int, speed := 0.0) -> void:
	t += delta
	var target_fall := 1.0 if mode == Mode.FALLEN else 0.0
	fall = move_toward(fall, target_fall, delta * (3.5 if target_fall > fall else 1.2))
	var hip_y := 0.92
	var al := Vector3.ZERO
	var ar := Vector3.ZERO
	var ll := Vector3.ZERO
	var lr := Vector3.ZERO
	var hr := Vector3.ZERO
	var head_r := Vector3.ZERO
	match mode:
		Mode.WALK, Mode.RUN, Mode.PANIC:
			var run := mode != Mode.WALK
			var freq := (speed * (1.25 if run else 1.9)) + 0.5
			phase += delta * freq * TAU / 2.0
			var amp := 0.95 if run else 0.55
			var s := sin(phase)
			ll.x = s * amp
			lr.x = -s * amp
			al.x = -s * amp * 0.9
			ar.x = s * amp * 0.9
			hip_y += absf(cos(phase)) * (0.08 if run else 0.035)
			hr.x = -0.18 if run else -0.03
			if run:
				al.x -= 0.4
				ar.x -= 0.4
				al.z = -0.15
				ar.z = 0.15
			if mode == Mode.PANIC:
				al = Vector3(-2.6, 0, -0.4 + sin(t * 18.0) * 0.2)
				ar = Vector3(-2.6, 0, 0.4 - sin(t * 18.0) * 0.2)
		Mode.SIT:
			hip_y = 0.50
			ll.x = -1.45
			lr.x = -1.45
			al.x = -0.5
			ar.x = -0.5
			head_r.y = sin(t * 0.4 + _seed) * 0.4
		Mode.PHONE:
			ar = Vector3(-1.9, 0, 0.45)
			al.x = -0.3
			head_r.x = -0.25
			head_r.y = 0.2
			hip_y += sin(t * 1.5 + _seed) * 0.004
		Mode.TALK:
			var g := sin(t * 3.0 + _seed)
			ar = Vector3(-0.6 + g * 0.35, 0, 0.2)
			al = Vector3(-0.3 - g * 0.2, 0, -0.1)
			head_r.y = sin(t * 0.9 + _seed) * 0.25
			head_r.x = sin(t * 2.3) * 0.05
		Mode.SWEEP:
			var sw := sin(t * 3.0 + _seed)
			ar = Vector3(-0.5 + sw * 0.25, sw * 0.4, 0.35)
			al = Vector3(-0.7 + sw * 0.25, sw * 0.4, -0.2)
			hr.x = -0.15
			hr.y = sw * 0.25
		Mode.WAIT:
			al = Vector3(0.1, 0, -0.08)
			ar = Vector3(0.1, 0, 0.08)
			head_r.y = sin(t * 0.3 + _seed) * 0.6
			hip_y += sin(t * 1.2 + _seed) * 0.004
		Mode.DRIVE:
			hip_y = 0.5
			ll.x = -1.3
			lr.x = -1.3
			al.x = -1.2
			ar.x = -1.2
		_:
			al.z = -0.06 + sin(t * 1.4 + _seed) * 0.02
			ar.z = 0.06 - sin(t * 1.4 + _seed) * 0.02
			hip_y += sin(t * 1.4 + _seed) * 0.006
			head_r.y = sin(t * 0.5 + _seed) * 0.3
	var k := clampf(delta * 12.0, 0.0, 1.0)
	_lerp_rot(arm_l, al, k)
	_lerp_rot(arm_r, ar, k)
	_lerp_rot(leg_l, ll, k)
	_lerp_rot(leg_r, lr, k)
	_lerp_rot(head, head_r, k * 0.5)
	# Falling over pivots the whole body backwards around the feet.
	hr.x = lerpf(hr.x, PI / 2.0 * 0.98, fall)
	hip_y = lerpf(hip_y, 0.18, fall)
	_lerp_rot(hips, hr, k)
	hips.position.y = lerpf(hips.position.y, hip_y, k)
	hips.position.z = lerpf(0.0, 0.55, fall)


func _lerp_rot(n: Node3D, target: Vector3, k: float) -> void:
	n.rotation = n.rotation.lerp(target, k)
