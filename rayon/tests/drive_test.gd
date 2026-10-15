extends SceneTree
## Headless driving check: acceleration, cornering, handbrake drift, braking.
##   godot --headless --path . -s res://tests/drive_test.gd -- sado

var car: Car
var t := 0.0
var log_t := 0.0
var kind := "sado"
var max_slip := 0.0
var spun := false
var heading0 := 0.0
var report := []
var hit_100 := -1.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		kind = args[0]
	var w := Node3D.new()
	root.add_child(w)
	var c := CityBuilder.new()
	w.add_child(c)
	c.build(false)
	car = Car.create(kind, {})
	w.add_child(car)
	# South end of the drift pad, facing north.
	car.place(Transform3D(Basis.IDENTITY, Vector3(170, 0.6, -25)))


func _slip() -> float:
	var v := car.linear_velocity
	v.y = 0
	if v.length() < 3.0:
		return 0.0
	return rad_to_deg((-car.global_basis.z).signed_angle_to(v.normalized(), Vector3.UP))


func _physics_process(delta: float) -> bool:
	t += delta
	var thr := 0.0
	var brk := 0.0
	var st := 0.0
	var hb := false
	var phase := ""
	if t < 1.0:
		phase = "settle"
	elif t < 4.0:
		phase = "accel"
		thr = 1.0
	elif t < 6.0:
		phase = "corner"
		thr = 0.5
		st = 1.0
	elif t < 6.6:
		phase = "handbrake"
		st = 1.0
		hb = true
		thr = 0.5
	elif t < 9.5:
		phase = "drift-hold"
		thr = 0.8
		st = -0.3
	elif t < 12.0:
		phase = "brake"
		brk = 1.0
	elif t < 18.0:
		phase = "settle2"
	elif t < 19.0:
		phase = "brake"
		brk = 1.0
	elif t < 20.0:
		phase = "reverse"
		brk = 1.0
	else:
		phase = "rest"
	car.set_controls(thr, brk, st, hb)
	if hit_100 < 0 and car.speed_kmh() >= 100.0:
		hit_100 = t - 1.0
	if phase.begins_with("drift") or phase == "handbrake":
		max_slip = maxf(max_slip, absf(_slip()))
	if absf(_slip()) > 100:
		spun = true
	log_t += delta
	if log_t >= 0.5:
		log_t = 0.0
		print("%5.1fs %-10s v=%6.1f km/h slip=%6.1f° yaw=%6.1f°/s hdg=%6.1f pos=(%.0f,%.0f) y=%.3f skid=%.2f w=%d" % [t, phase, car.speed_kmh(), _slip(), rad_to_deg(car.angular_velocity.y), rad_to_deg(car.rotation.y), car.global_position.x, car.global_position.z, car.global_position.y, car.skid, car.wheels_on_ground()])
	if t > 22.0:
		print("RESULT kind=%s 0-100=%.2fs max_drift_slip=%.1f spun=%s final_speed=%.2f height=%.3f" % [kind, hit_100, max_slip, spun, car.speed_kmh(), car.global_position.y])
		quit()
	return false
