class_name Car
extends RigidBody3D
## Arcade car on a rigid body with four ray-cast wheels.
##
## Each wheel: spring + damper suspension, a tyre that resists sideways
## sliding up to a friction circle (mu × load), engine drive on the driven
## axle, brakes and a rear handbrake that drops grip for controlled drifts.
## Drivers (player or AI) only set throttle / brake / steer / handbrake.

signal impact(strength: float, other: Object)

const SPECS := {
	"sado": {"mass": 1200.0, "engine": 8200.0, "max_speed": 50.0, "drive": "rwd", "grip_f": 1.30, "grip_r": 1.20,
		"hb_grip": 0.36, "steer": 0.60, "spring": 36000.0, "damper": 2700.0, "brake": 11000.0, "anti_roll": 9000.0,
		"slide_keep": 0.8, "power_slide": 0.5, "drift_limit": 0.75},
	"chabuk": {"mass": 950.0, "engine": 6100.0, "max_speed": 42.0, "drive": "fwd", "grip_f": 1.42, "grip_r": 1.42,
		"hb_grip": 0.55, "steer": 0.68, "spring": 30000.0, "damper": 2200.0, "brake": 9500.0, "anti_roll": 8000.0,
		"slide_keep": 0.88, "power_slide": 0.0, "drift_limit": 0.45},
	"posbon": {"mass": 1550.0, "engine": 12500.0, "max_speed": 54.0, "drive": "rwd", "grip_f": 1.45, "grip_r": 1.42,
		"hb_grip": 0.5, "steer": 0.56, "spring": 46000.0, "damper": 3600.0, "brake": 15000.0, "anti_roll": 14000.0,
		"slide_keep": 0.88, "power_slide": 0.15, "drift_limit": 0.5},
}

const SUSP_UP := 0.30          # ray origin above the wheel centre at rest (model pose)
const REST_LEN := 0.40         # spring length when unloaded
const TRAVEL_DOWN := 0.18

# --- configuration -----------------------------------------------------------
var kind := "sado"
var spec := {}
var model: Node3D
var wheel_nodes: Array[Node3D] = []
var spin_nodes: Array[Node3D] = []
var wheel_local: Array[Vector3] = []    # wheel centre in model pose
var radius := 0.3
var is_police := false
var paint := Color.WHITE
var rims := "sport"

# --- controls (set by the driver every frame) ---------------------------------
var throttle := 0.0
var brake := 0.0
var steer_input := 0.0
var handbrake := false
var driver := ""                         # "", "player", "ai"

# --- state readable by others ----------------------------------------------------
var forward_speed := 0.0
var steer_angle := 0.0
var wheel_contact: Array[bool] = [false, false, false, false]
var wheel_slip: Array[float] = [0.0, 0.0, 0.0, 0.0]
var wheel_ground: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var skid := 0.0                          # 0..1 how hard the tyres are sliding
var rpm := 0.0                           # 0..1 fake engine speed
var gear := 1
var engine_load := 0.0
var reversing := false
var siren_on := false
var stuck_time := 0.0
var last_impact_time := -10.0

var _wheel_spin_speed: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _comp_prev: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _light_t := 0.0
var _light_red: MeshInstance3D
var _light_blue: MeshInstance3D
var _red_on: Material
var _red_off: Material
var _blue_on: Material
var _blue_off: Material
var _engine_mult := 1.0
var _grip_mult := 1.0
var _ray := PhysicsRayQueryParameters3D.new()


## Creates a ready-to-use car. cfg: {paint: Color, rims: String, engine: int, grip: int}
static func create(car_kind: String, cfg := {}) -> Car:
	var car := Car.new()
	car.kind = car_kind
	car.name = car_kind.capitalize()
	car.spec = SPECS[car_kind].duplicate()
	car.is_police = car_kind == "posbon"
	car._setup(cfg)
	return car


func _setup(cfg: Dictionary) -> void:
	model = Models.instance("cars/" + kind)
	model.name = "Model"
	add_child(model)
	radius = model.get_meta("radius", 0.3)
	for wn in ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]:
		var w: Node3D = model.get_node(wn)
		wheel_nodes.append(w)
		spin_nodes.append(w.get_node("Spin"))
		wheel_local.append(w.position)
	mass = spec["mass"]
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.42, 0.05)
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.9
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.02
	can_sleep = true
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 6
	collision_layer = 2
	collision_mask = 1 | 2 | 4
	var pm := PhysicsMaterial.new()
	pm.friction = 0.35
	pm.bounce = 0.05
	physics_material_override = pm
	var length: float = model.get_meta("length", 4.2)
	var width: float = model.get_meta("width", 1.7)
	var height: float = model.get_meta("height", 1.4)
	# Lower body box and a narrower cabin box.
	var lower := CollisionShape3D.new()
	var lb := BoxShape3D.new()
	lb.size = Vector3(width, 0.62, length)
	lower.shape = lb
	lower.position = Vector3(0, 0.36 + 0.31, 0)
	add_child(lower)
	var upper := CollisionShape3D.new()
	var ub := BoxShape3D.new()
	ub.size = Vector3(width - 0.3, height - 0.98, length * 0.48)
	upper.shape = ub
	upper.position = Vector3(0, 0.98 + (height - 0.98) * 0.5, length * 0.06)
	add_child(upper)
	# Inertia of a box of this size (helps keep the car calm in the air).
	inertia = Vector3(mass * (0.9 * 0.9 + length * length) / 12.0 * 1.1,
		mass * (width * width + length * length) / 12.0 * 1.15,
		mass * (width * width + 0.9 * 0.9) / 12.0 * 1.6)
	apply_config(cfg)
	if is_police:
		var bar := model.get_node_or_null("LightBar")
		if bar:
			_light_red = bar.get_node("LightRed")
			_light_blue = bar.get_node("LightBlue")
			_red_off = Mats.glow(Color("ff2a2a").darkened(0.45))
			_red_on = Mats.glow(Color("ff5050"))
			_blue_off = Mats.glow(Color("2a63ff").darkened(0.45))
			_blue_on = Mats.glow(Color("6f9bff"))
	_ray.collision_mask = 1
	_ray.exclude = [get_rid()]
	_ray.hit_back_faces = false


## Paint colour, rims and upgrade levels (0..3).
func apply_config(cfg: Dictionary) -> void:
	if cfg.has("paint"):
		paint = cfg["paint"]
		var body: MeshInstance3D = model.get_node("Body")
		var idx := (body.mesh as ArrayMesh).surface_find_by_name("paint")
		if idx >= 0:
			body.set_surface_override_material(idx, Mats.paint(paint, 0.022))
	if cfg.has("rims") and cfg["rims"] != rims:
		rims = cfg["rims"]
		var mesh := CarBuilder.wheel_mesh(rims, radius, model.get_meta("tyre_w", 0.2))
		for s in spin_nodes:
			(s.get_node("Rim") as MeshInstance3D).mesh = mesh
	elif cfg.has("rims"):
		rims = cfg["rims"]
	_engine_mult = 1.0 + 0.14 * int(cfg.get("engine", 0))
	_grip_mult = 1.0 + 0.08 * int(cfg.get("grip", 0))


func set_controls(t: float, b: float, s: float, hb: bool) -> void:
	throttle = clampf(t, 0.0, 1.0)
	brake = clampf(b, 0.0, 1.0)
	steer_input = clampf(s, -1.0, 1.0)
	handbrake = hb
	if (t > 0.01 or b > 0.01 or absf(s) > 0.01) and sleeping:
		sleeping = false


func speed_kmh() -> float:
	return linear_velocity.length() * 3.6


func max_speed() -> float:
	return spec["max_speed"] * (1.0 + 0.04 * (_engine_mult - 1.0) / 0.14)


func engine_force() -> float:
	return spec["engine"] * _engine_mult


func grip_factor() -> float:
	return _grip_mult


func is_flipped() -> bool:
	return global_basis.y.y < 0.35


func wheels_on_ground() -> int:
	var n := 0
	for c in wheel_contact:
		if c:
			n += 1
	return n


## Put the car back on its wheels at the given transform (used by recovery / respawn).
func place(xf: Transform3D) -> void:
	var t := xf
	t.basis = t.basis.orthonormalized()
	global_transform = t
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, t)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sleeping = false
	stuck_time = 0.0


# --- simulation ------------------------------------------------------------------

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var dt := state.step
	var xf := state.transform
	var up := xf.basis.y.normalized()
	var fwd := -xf.basis.z.normalized()
	var right := xf.basis.x.normalized()
	var vel := state.linear_velocity
	forward_speed = vel.dot(fwd)
	var speed := vel.length()
	var m: float = mass
	var mq := m * 0.25
	var g := 9.8

	# Driver intent: S brakes while rolling forward, then reverses.
	var drive_in := throttle
	var brake_in := brake
	reversing = false
	if brake > 0.05 and throttle < 0.05 and forward_speed < 1.0:
		reversing = true
		drive_in = -brake * 0.55
		brake_in = 0.0
	elif throttle > 0.05 and forward_speed < -1.0:
		brake_in = maxf(brake_in, throttle)
		drive_in = 0.0

	# Steering: less lock at speed, but full lock while sliding for counter-steer.
	var slip_angle := 0.0
	if speed > 3.0:
		var flat_v := vel - up * vel.dot(up)
		slip_angle = fwd.signed_angle_to(flat_v.normalized(), up) if flat_v.length() > 0.5 else 0.0
		if forward_speed < 0.0:
			slip_angle = 0.0
	var lock: float = spec["steer"] / (1.0 + absf(forward_speed) * 0.065)
	if absf(slip_angle) > 0.15:
		lock = maxf(lock, spec["steer"] * 0.85)
	var target_steer := steer_input * lock
	# Gentle automatic counter-steer while drifting (keeps slides controllable).
	if absf(slip_angle) > 0.12 and speed > 6.0 and not reversing:
		target_steer += clampf(slip_angle * 0.35, -0.25, 0.25)
	steer_angle = move_toward(steer_angle, clampf(target_steer, -spec["steer"], spec["steer"]), dt * 2.6)

	var engine := engine_force()
	var vmax := max_speed()
	var driven := [false, false, true, true] if spec["drive"] == "rwd" else [true, true, false, false]
	var n_driven := 2.0
	var curve := 1.0 - pow(clampf(absf(forward_speed) / vmax, 0.0, 1.0), 2.2) * 0.85
	if forward_speed > vmax and drive_in > 0.0:
		curve = 0.0
	if reversing and forward_speed < -12.0:
		curve = 0.0
	var drive_force := drive_in * engine * curve / n_driven
	engine_load = absf(drive_in)

	var comp: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var contacts: Array = [null, null, null, null]
	var any_slide := 0.0
	var space := state.get_space_state()

	# Pass 1: suspension rays.
	for i in 4:
		var wl := wheel_local[i]
		var origin := xf * (wl + Vector3(0, SUSP_UP, 0))
		_ray.from = origin
		_ray.to = origin - up * (SUSP_UP + TRAVEL_DOWN + radius)
		var hit := space.intersect_ray(_ray)
		if hit.is_empty():
			wheel_contact[i] = false
			comp[i] = 0.0
			continue
		var dist: float = origin.distance_to(hit["position"])
		var spring_len := dist - radius
		comp[i] = clampf(REST_LEN - spring_len, 0.0, REST_LEN + 0.1)
		wheel_contact[i] = comp[i] > 0.0
		contacts[i] = hit
		wheel_ground[i] = hit["position"]

	# Pass 2: forces.
	for i in 4:
		var wl := wheel_local[i]
		var front := i < 2
		if not wheel_contact[i]:
			_wheel_spin_speed[i] = lerpf(_wheel_spin_speed[i], drive_in * 30.0 if driven[i] else 0.0, dt * 2.0)
			wheel_slip[i] = 0.0
			_comp_prev[i] = 0.0
			continue
		var hit: Dictionary = contacts[i]
		var n: Vector3 = hit["normal"]
		var contact: Vector3 = hit["position"]
		var offset := contact - xf.origin
		var pv := state.get_velocity_at_local_position(offset)
		# Suspension.
		var comp_vel := (comp[i] - _comp_prev[i]) / dt
		_comp_prev[i] = comp[i]
		var fs: float = spec["spring"] * comp[i] + spec["damper"] * clampf(comp_vel, -3.0, 3.0)
		# Anti-roll bar.
		var other := i + 1 if i % 2 == 0 else i - 1
		fs += (comp[i] - comp[other]) * spec["anti_roll"]
		fs = clampf(fs, 0.0, m * g * 1.6)
		state.apply_force(up * fs, offset)
		var load := fs
		# Tyre frame.
		var wfwd := fwd
		if front:
			wfwd = fwd.rotated(up, steer_angle)
		wfwd = (wfwd - n * wfwd.dot(n)).normalized()
		var wside := n.cross(wfwd).normalized()
		var v_long := pv.dot(wfwd)
		var v_lat := pv.dot(wside)
		var grip: float = (spec["grip_f"] if front else spec["grip_r"]) * _grip_mult
		var mu := grip
		var hb := handbrake and not front
		if hb:
			mu *= spec["hb_grip"]
		# Throttle-on oversteer for rear-driven cars (power slides).
		if driven[i] and not front and drive_in > 0.6 and absf(slip_angle) > 0.12:
			mu *= 1.0 - spec["power_slide"] * 0.4
		var max_f := mu * load
		# Lateral: cancel sideways speed (stable impulse form).
		var f_lat := -v_lat * mq / dt * 0.55
		# Longitudinal.
		var f_long := 0.0
		if driven[i]:
			f_long += drive_force
		if brake_in > 0.0:
			var fb: float = spec["brake"] * 0.25 * brake_in
			f_long += -signf(v_long) * minf(fb, absf(v_long) * mq / dt)
		if hb:
			f_long += -signf(v_long) * minf(max_f * 0.9, absf(v_long) * mq / dt)
		if absf(drive_in) < 0.02 and brake_in < 0.02 and not hb:
			# rolling resistance / engine braking, and hold still when stopped
			f_long += -v_long * (35.0 if absf(v_long) > 1.0 else mq / dt * 0.25)
		var f := Vector2(f_long, f_lat)
		var sliding := false
		if f.length() > max_f:
			sliding = true
			# Sliding friction is a bit lower than peak grip.
			var keep: float = spec["slide_keep"] if not front else 0.9
			f = f.normalized() * max_f * keep
		state.apply_force(wfwd * f.x + wside * f.y, offset)
		# Wheel spin for visuals and wheel-spin / lock detection.
		var target_spin := v_long / radius
		if hb:
			target_spin = 0.0
		elif driven[i] and sliding and drive_in > 0.5:
			target_spin = (absf(v_long) + 8.0) / radius * signf(drive_in)
		_wheel_spin_speed[i] = lerpf(_wheel_spin_speed[i], target_spin, clampf(dt * 20.0, 0.0, 1.0))
		var slide_speed := absf(v_lat)
		if hb or (driven[i] and sliding and drive_in > 0.5):
			slide_speed = maxf(slide_speed, absf(v_long) * 0.6 + (4.0 if not hb else 0.0))
		wheel_slip[i] = slide_speed if sliding else slide_speed * 0.3
		any_slide = maxf(any_slide, wheel_slip[i])

	# Drift stabiliser: let the tail swing out to a playable angle, then hold it
	# there instead of spinning; yaw that would increase the angle is damped.
	if speed > 5.0 and absf(slip_angle) > 0.08 and wheels_on_ground() >= 3 and forward_speed > 0.0:
		var yaw_rate := state.angular_velocity.dot(up)
		var limit: float = spec["drift_limit"] * (1.6 if handbrake else 1.0)
		var iy := inertia.y
		var excess := absf(slip_angle) - limit
		if excess > 0.0:
			state.apply_torque(up * signf(slip_angle) * excess * iy * 14.0)
		if yaw_rate * slip_angle < 0.0:
			var k := clampf(absf(slip_angle) / limit, 0.0, 1.5)
			state.apply_torque(-up * yaw_rate * iy * 3.2 * k * k)

	# Aerodynamic drag and a little downforce.
	var drag := -vel * speed * 0.42
	state.apply_central_force(drag)
	if wheels_on_ground() >= 2:
		state.apply_central_force(-up * speed * speed * 0.9)
	# In the air: soften rotation so jumps don't turn into endless tumbling.
	if wheels_on_ground() == 0:
		state.angular_velocity *= 1.0 - clampf(dt * 0.6, 0.0, 0.1)
	skid = clampf((any_slide - 4.0) / 6.0, 0.0, 1.0) if speed > 2.0 else 0.0

	# Fake gearbox for the engine sound.
	var gears := [0.0, 9.0, 17.0, 26.0, 35.0, 46.0, 70.0]
	var sp := absf(forward_speed)
	gear = 1
	for gi in range(1, gears.size() - 1):
		if sp >= gears[gi]:
			gear = gi + 1
	var lo: float = gears[gear - 1]
	var hi: float = gears[gear]
	var target_rpm := 0.2 + 0.8 * clampf((sp - lo) / (hi - lo), 0.0, 1.0)
	if skid > 0.3 and drive_in > 0.5:
		target_rpm = maxf(target_rpm, 0.85)
	if speed < 0.5:
		target_rpm = 0.12 + 0.6 * absf(drive_in)
	rpm = lerpf(rpm, target_rpm, clampf(dt * 8.0, 0.0, 1.0))

	# Impacts.
	var now := Time.get_ticks_msec() / 1000.0
	var hits := state.get_contact_count()
	for ci in hits:
		var imp := state.get_contact_impulse(ci).length()
		var nrm := state.get_contact_local_normal(ci)
		if nrm.y > 0.75:
			continue
		if imp > mass * 1.6 and now - last_impact_time > 0.35:
			last_impact_time = now
			impact.emit(imp / mass, state.get_contact_collider_object(ci))
			break

	# Stuck detection (used by AI and the recovery hint).
	if (throttle > 0.3 or (reversing and brake > 0.3)) and speed < 1.0:
		stuck_time += dt
	else:
		stuck_time = maxf(0.0, stuck_time - dt * 2.0)


func _process(delta: float) -> void:
	# Wheel visuals: suspension travel, steering and rolling.
	for i in 4:
		var w := wheel_nodes[i]
		var base := wheel_local[i]
		var y := base.y + SUSP_UP - (REST_LEN - comp_for(i))
		w.position.y = lerpf(w.position.y, clampf(y, base.y - TRAVEL_DOWN, base.y + 0.16), clampf(delta * 25.0, 0.0, 1.0))
		if i < 2:
			w.rotation.y = steer_angle
		spin_nodes[i].rotation.x = wrapf(spin_nodes[i].rotation.x - _wheel_spin_speed[i] * delta, -PI, PI)
	if is_police and _light_red:
		if siren_on:
			_light_t += delta
			var phase := int(_light_t * 8.0) % 8
			# double flash: red red . blue blue .
			_light_red.material_override = _red_on if phase == 0 or phase == 2 else _red_off
			_light_blue.material_override = _blue_on if phase == 4 or phase == 6 else _blue_off
		else:
			_light_red.material_override = null
			_light_blue.material_override = null


## Current suspension compression of a wheel (negative when hanging in the air).
func comp_for(i: int) -> float:
	return _comp_prev[i] if wheel_contact[i] else -TRAVEL_DOWN
