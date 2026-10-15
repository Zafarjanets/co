class_name Pedestrians
extends Node3D
## Townsfolk going about their day: walking the sidewalks, sitting on benches,
## chatting in front of shops, waiting for the bus, sweeping the street.
## They jump out of the way of fast cars and get knocked over when hit.

const ACTIVE_RADIUS := 150.0
const VARIANTS := ["people/man_phone", "people/man_backpack", "people/man_cap", "people/woman_dress",
	"people/woman_scarf", "people/elder", "people/student"]


class Ped:
	var node: Node3D
	var rig: PersonRig
	var mode := PersonRig.Mode.WALK
	var base_mode := PersonRig.Mode.WALK
	var loop: PackedVector3Array
	var idx := 0
	var dir := 1
	var speed := 1.3
	var timer := 0.0
	var flee := Vector3.ZERO
	var home := Transform3D()
	var walker := true
	var temp := false
	var life := 0.0


var main: Main
var peds: Array = []
var max_walkers := 22
var _rng := RandomNumberGenerator.new()
var _tick := 0


func setup(m: Main) -> void:
	main = m
	name = "Pedestrians"
	_rng.seed = 555
	_populate()


func set_quality(q: int) -> void:
	max_walkers = [10, 18, 26][q]
	var n := 0
	for p in peds:
		if p.walker and not p.temp:
			n += 1
			p.node.set_meta("enabled", n <= max_walkers)


func _make(model_path: String) -> Ped:
	var p := Ped.new()
	p.node = Models.instance(model_path)
	add_child(p.node)
	p.rig = PersonRig.new(p.node)
	return p


func _populate() -> void:
	var city := main.city
	# Walkers on sidewalk loops.
	var loops: Array = city.ped_loops
	for i in 26:
		var loop: PackedVector3Array = loops[_rng.randi() % loops.size()]
		var p := _make(VARIANTS[_rng.randi() % VARIANTS.size()])
		p.loop = loop
		p.idx = _rng.randi() % loop.size()
		p.dir = 1 if _rng.randf() < 0.5 else -1
		var a := loop[p.idx]
		var b := loop[(p.idx + p.dir + loop.size()) % loop.size()]
		p.node.position = a.lerp(b, _rng.randf())
		p.speed = _rng.randf_range(1.1, 1.6)
		peds.append(p)
	# Street sweepers.
	for i in 3:
		var loop2: PackedVector3Array = loops[_rng.randi() % loops.size()]
		var s := _make("people/sweeper")
		s.loop = loop2
		s.idx = 0
		s.node.position = loop2[0]
		s.speed = 0.7
		s.base_mode = PersonRig.Mode.SWEEP
		peds.append(s)
	# People on benches.
	var benches := city.bench_spots.duplicate()
	benches.shuffle()
	for i in mini(16, benches.size()):
		var xf: Transform3D = benches[i]
		var p2 := _make(VARIANTS[_rng.randi() % VARIANTS.size()])
		# The seat faces the bench's -Z, away from the backrest, like the people model.
		p2.home = Transform3D(xf.basis, xf * Vector3(_rng.randf_range(-0.5, 0.5), 0.0, 0.0))
		p2.walker = false
		p2.base_mode = PersonRig.Mode.SIT
		p2.mode = PersonRig.Mode.SIT
		p2.node.transform = p2.home
		peds.append(p2)
	# Chatting, phoning and waiting at shops and bus stops.
	var stands := city.stand_spots
	for i in stands.size():
		var xf2: Transform3D = stands[i]
		var p3 := _make(VARIANTS[_rng.randi() % VARIANTS.size()])
		p3.walker = false
		var roll := _rng.randf()
		p3.base_mode = PersonRig.Mode.TALK if roll < 0.45 else (PersonRig.Mode.PHONE if roll < 0.75 else PersonRig.Mode.WAIT)
		p3.mode = p3.base_mode
		p3.home = xf2
		p3.node.transform = xf2
		peds.append(p3)
		if p3.base_mode == PersonRig.Mode.TALK:
			# A conversation partner facing them.
			var p4 := _make(VARIANTS[_rng.randi() % VARIANTS.size()])
			p4.walker = false
			p4.base_mode = PersonRig.Mode.TALK
			p4.mode = p4.base_mode
			var off := xf2.basis * Vector3(0, 0, -1.3)
			p4.home = Transform3D(xf2.basis.rotated(Vector3.UP, PI), xf2.origin + off)
			p4.node.transform = p4.home
			peds.append(p4)
	set_quality(Game.setting("quality"))


func positions_near(p: Vector3, r: float) -> Array:
	var out: Array = []
	var r2 := r * r
	for ped in peds:
		if ped.node.visible and ped.node.position.distance_squared_to(p) < r2:
			out.append(ped.node.position)
	return out


func scare(pos: Vector3, radius: float) -> void:
	for p in peds:
		if p.mode == PersonRig.Mode.FALLEN:
			continue
		var d: Vector3 = p.node.position - pos
		d.y = 0
		if d.length() < radius:
			_panic(p, d.normalized() if d.length() > 0.1 else Vector3.RIGHT)


func spawn_ejected(door: Vector3, car_pos: Vector3) -> void:
	var p := _make(VARIANTS[_rng.randi() % VARIANTS.size()])
	p.temp = true
	p.walker = false
	p.life = 12.0
	p.node.position = Vector3(door.x, _ground_y(door), door.z)
	var away := door - car_pos
	away.y = 0
	_panic(p, away.normalized() if away.length() > 0.1 else Vector3.RIGHT)
	p.timer = 6.0
	peds.append(p)


func _panic(p: Ped, away: Vector3) -> void:
	p.mode = PersonRig.Mode.PANIC
	p.flee = away
	p.timer = 2.5


func _ground_y(pos: Vector3) -> float:
	return 0.0 if main.layout.on_road(pos) else CityLayout.CURB_H


func _process(delta: float) -> void:
	var focus := main.focus_position()
	_tick += 1
	for p in peds.duplicate():
		var n: Node3D = p.node
		if p.temp:
			p.life -= delta
			if p.life <= 0.0 and not main.is_visible_to_camera(n.position):
				peds.erase(p)
				n.queue_free()
				continue
		var far := n.position.distance_to(focus) > ACTIVE_RADIUS
		var enabled: bool = n.get_meta("enabled", true)
		n.visible = not far and enabled
		if far or not enabled:
			continue
		_think(p, delta)
		p.rig.update(delta, p.mode, p.speed if p.mode == PersonRig.Mode.WALK else 5.0)


func _think(p: Ped, delta: float) -> void:
	var n := p.node
	if p.mode == PersonRig.Mode.FALLEN:
		p.timer -= delta
		if p.timer <= 0.0:
			p.mode = p.base_mode if p.walker else PersonRig.Mode.WALK
			p.timer = 0.0
		return
	_check_cars(p)
	if p.mode == PersonRig.Mode.PANIC:
		p.timer -= delta
		var step := p.flee * 5.0 * delta
		n.position += step
		n.position.y = lerpf(n.position.y, _ground_y(n.position), 0.3)
		n.rotation.y = lerp_angle(n.rotation.y, atan2(-p.flee.x, -p.flee.z), clampf(delta * 10.0, 0.0, 1.0))
		if p.timer <= 0.0:
			p.mode = p.base_mode
		return
	if not p.walker:
		# Stationary folks drift back to their spot after being scared.
		var to := p.home.origin - n.position
		to.y = 0
		if to.length() > 0.4:
			p.mode = PersonRig.Mode.WALK
			n.position += to.normalized() * minf(1.4 * delta, to.length())
			n.rotation.y = lerp_angle(n.rotation.y, atan2(-to.x, -to.z), clampf(delta * 8.0, 0.0, 1.0))
			n.position.y = lerpf(n.position.y, p.home.origin.y, 0.2)
		else:
			p.mode = p.base_mode
			n.transform = n.transform.interpolate_with(p.home, clampf(delta * 5.0, 0.0, 1.0))
		return
	# Walkers (and sweepers) follow their loop.
	if p.base_mode == PersonRig.Mode.SWEEP:
		p.timer -= delta
		if p.timer <= 0.0:
			p.mode = PersonRig.Mode.WALK if p.mode == PersonRig.Mode.SWEEP else PersonRig.Mode.SWEEP
			p.timer = 4.0 if p.mode == PersonRig.Mode.SWEEP else 2.5
		if p.mode == PersonRig.Mode.SWEEP:
			return
	else:
		p.mode = PersonRig.Mode.WALK
	var target := p.loop[(p.idx + p.dir + p.loop.size()) % p.loop.size()]
	var d := target - n.position
	d.y = 0
	if d.length() < 0.6:
		p.idx = (p.idx + p.dir + p.loop.size()) % p.loop.size()
		return
	var mv := d.normalized() * p.speed * delta
	n.position += mv
	n.position.y = lerpf(n.position.y, target.y, 0.2)
	n.rotation.y = lerp_angle(n.rotation.y, atan2(-d.x, -d.z), clampf(delta * 6.0, 0.0, 1.0))


func _check_cars(p: Ped) -> void:
	var n := p.node
	for c in main.cars:
		if not is_instance_valid(c):
			continue
		var v := c.linear_velocity
		var spd := v.length()
		if spd < 3.0:
			continue
		var rel := n.position - c.global_position
		if rel.length_squared() > 225.0:
			continue
		var lp := c.global_transform.affine_inverse() * n.position
		var hl: float = c.model.get_meta("length", 4.2) * 0.5
		var hw: float = c.model.get_meta("width", 1.7) * 0.5
		var moving_fwd := c.forward_speed > 0.0
		# Hit.
		if absf(lp.x) < hw + 0.25 and absf(lp.z) < hl + 0.25 and absf(lp.y) < 2.0:
			p.mode = PersonRig.Mode.FALLEN
			p.timer = 4.0
			var push := v.normalized() * 1.8
			push.y = 0
			n.position += push
			n.rotation.y = atan2(v.x, v.z)
			if c == main.player.car:
				Sfx.impact(3.0, n.position)
				main.police.report_crime("hit_ped", n.position, 1)
			return
		# About to be hit: dive away.
		var ahead := (lp.z < 0.0 and moving_fwd) or (lp.z > 0.0 and not moving_fwd)
		if ahead and absf(lp.x) < hw + 1.6 and absf(lp.z) < hl + spd * 0.8 and p.mode != PersonRig.Mode.PANIC:
			var side := c.global_basis.x * (1.0 if lp.x >= 0.0 else -1.0)
			side.y = 0
			_panic(p, side.normalized())
