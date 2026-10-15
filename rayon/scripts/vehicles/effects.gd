class_name Effects
extends Node3D
## Tyre marks and tyre smoke for sliding cars.

const MAX_MARKS := 1400
const MARK_WIDTH := 0.22

var _cars: Array[Car] = []
var _last := {}                # car -> Array[Vector3|null] last mark point per wheel
var _mm: MultiMesh
var _next := 0
var _smoke := {}               # car -> CPUParticles3D


func _ready() -> void:
	name = "Effects"
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.orientation = PlaneMesh.FACE_Y
	_mm.mesh = q
	_mm.instance_count = MAX_MARKS
	_mm.visible_instance_count = MAX_MARKS
	for i in MAX_MARKS:
		_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -100, 0)))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 1)
	q.material = mat
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.name = "SkidMarks"
	add_child(mmi)


func register(c: Car) -> void:
	_cars.append(c)
	_last[c] = [null, null, null, null]


func unregister(c: Car) -> void:
	_cars.erase(c)
	_last.erase(c)
	if _smoke.has(c):
		var p: CPUParticles3D = _smoke[c]
		if is_instance_valid(p):
			p.queue_free()
		_smoke.erase(c)


func _smoke_for(c: Car) -> CPUParticles3D:
	if _smoke.has(c) and is_instance_valid(_smoke[c]):
		return _smoke[c]
	var p := CPUParticles3D.new()
	p.amount = 36
	p.lifetime = 1.4
	p.emitting = false
	p.local_coords = false
	p.direction = Vector3(0, 1, 0)
	p.spread = 35.0
	p.gravity = Vector3(0, 0.6, 0)
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.8
	p.scale_amount_min = 0.4
	p.scale_amount_max = 0.9
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 2.4))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(0.92, 0.92, 0.92, 0.35))
	grad.set_color(1, Color(0.95, 0.95, 0.95, 0.0))
	p.color_ramp = grad
	var sphere := SphereMesh.new()
	sphere.radius = 0.35
	sphere.height = 0.6
	sphere.radial_segments = 6
	sphere.rings = 3
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	sphere.material = m
	p.mesh = sphere
	p.position = Vector3(0, 0.3, c.wheel_local[2].z)
	c.add_child(p)
	_smoke[c] = p
	return p


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	for c in _cars:
		if not is_instance_valid(c):
			continue
		var near := cam != null and cam.global_position.distance_squared_to(c.global_position) < 120.0 * 120.0
		var last: Array = _last[c]
		for i in 4:
			var slipping := near and c.wheel_contact[i] and c.wheel_slip[i] > 4.5
			if not slipping:
				last[i] = null
				continue
			var gp: Vector3 = c.wheel_ground[i] + Vector3(0, 0.025, 0)
			if last[i] == null:
				last[i] = gp
				continue
			var lp: Vector3 = last[i]
			var seg := gp - lp
			var len := seg.length()
			if len < 0.35:
				continue
			if len < 3.0:
				_add_mark(lp, gp, clampf((c.wheel_slip[i] - 4.5) / 6.0, 0.25, 0.75))
			last[i] = gp
		if near and c.skid > 0.35:
			var s := _smoke_for(c)
			s.emitting = true
		elif _smoke.has(c) and is_instance_valid(_smoke[c]):
			(_smoke[c] as CPUParticles3D).emitting = false


func _add_mark(a: Vector3, b: Vector3, alpha: float) -> void:
	var d := b - a
	var len := d.length()
	var fwd := d / len
	var right := Vector3.UP.cross(fwd).normalized()
	var basis := Basis(right * MARK_WIDTH, Vector3.UP, fwd * len)
	_mm.set_instance_transform(_next, Transform3D(basis, (a + b) * 0.5))
	_mm.set_instance_color(_next, Color(0.08, 0.08, 0.09, alpha))
	_next = (_next + 1) % MAX_MARKS
