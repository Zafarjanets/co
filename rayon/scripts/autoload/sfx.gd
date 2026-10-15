extends Node
## Procedural audio. Engine, tyre squeal and siren are synthesised live;
## short effects (impacts, doors, UI) are generated once at start.
## Nothing plays until start() is called after the player's first action.

const RATE := 22050.0

var started := false
var _engine: AudioStreamPlayer
var _skid: AudioStreamPlayer
var _siren: AudioStreamPlayer
var _eng_pb: AudioStreamGeneratorPlayback
var _skid_pb: AudioStreamGeneratorPlayback
var _siren_pb: AudioStreamGeneratorPlayback
var _oneshots: Array[AudioStreamPlayer] = []
var _next_shot := 0
var _clips := {}

# targets set by the game
var _eng_on := false
var _rpm := 0.0
var _load := 0.0
var _skid_amt := 0.0
var _siren_on := false
var _siren_dist := 100.0

# synth state
var _ph1 := 0.0
var _ph2 := 0.0
var _ph3 := 0.0
var _lp := 0.0
var _lp2 := 0.0
var _eng_gain := 0.0
var _cur_rpm := 0.0
var _skid_gain := 0.0
var _bp1 := 0.0
var _bp2 := 0.0
var _siren_ph := 0.0
var _sq_ph := 0.0
var _siren_lfo := 0.0
var _siren_gain := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_engine = _gen_player("Engine", -4.0)
	_skid = _gen_player("Skid", -8.0)
	_siren = _gen_player("Siren", -10.0)
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.name = "Shot%d" % i
		add_child(p)
		_oneshots.append(p)
	_clips["impact"] = _make_clip(0.35, _impact_wave)
	_clips["impact_soft"] = _make_clip(0.18, _soft_wave)
	_clips["door"] = _make_clip(0.16, _door_wave)
	_clips["ok"] = _make_clip(0.32, _ok_wave)
	_clips["fail"] = _make_clip(0.5, _fail_wave)
	_clips["check"] = _make_clip(0.22, _check_wave)
	_clips["horn"] = _make_clip(0.5, _horn_wave)
	_clips["click"] = _make_clip(0.05, _click_wave)


func _gen_player(n: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = n
	var g := AudioStreamGenerator.new()
	g.mix_rate = RATE
	g.buffer_length = 0.12
	p.stream = g
	p.volume_db = db
	add_child(p)
	return p


func start() -> void:
	if started:
		return
	started = true
	for p in [_engine, _skid, _siren]:
		p.play()
	_eng_pb = _engine.get_stream_playback()
	_skid_pb = _skid.get_stream_playback()
	_siren_pb = _siren.get_stream_playback()


func set_volume(v: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(0, v <= 0.001)


func set_engine(on: bool, rpm: float, load: float, _speed: float) -> void:
	_eng_on = on
	_rpm = rpm
	_load = load


func set_skid(a: float) -> void:
	_skid_amt = a


func set_siren(on: bool, dist: float) -> void:
	_siren_on = on
	_siren_dist = dist


# --- one-shots ---------------------------------------------------------------------

func _play(clip: String, db := 0.0, pitch := 1.0) -> void:
	if not started:
		return
	var p := _oneshots[_next_shot]
	_next_shot = (_next_shot + 1) % _oneshots.size()
	p.stream = _clips[clip]
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


func impact(strength: float, _pos := Vector3.ZERO) -> void:
	if strength > 4.0:
		_play("impact", clampf(-14.0 + strength * 1.2, -14.0, 2.0), _rng.randf_range(0.85, 1.1))
	else:
		_play("impact_soft", -10.0, _rng.randf_range(0.9, 1.2))


func door() -> void:
	_play("door", -6.0)


func ui_ok() -> void:
	_play("ok", -6.0)


func ui_fail() -> void:
	_play("fail", -6.0)


func checkpoint() -> void:
	_play("check", -4.0)


func horn() -> void:
	_play("horn", -6.0)


func click() -> void:
	_play("click", -12.0)


# --- live synthesis -------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if not started:
		return
	var paused := get_tree().paused
	_fill_engine(paused)
	_fill_skid(paused)
	_fill_siren(paused)


func _fill_engine(paused: bool) -> void:
	var n := _eng_pb.get_frames_available()
	if n <= 0:
		return
	var buf := PackedVector2Array()
	buf.resize(n)
	var target_gain := (0.22 + 0.3 * _load) if (_eng_on and not paused) else 0.0
	for i in n:
		_cur_rpm += (_rpm - _cur_rpm) * 0.0015
		_eng_gain += (target_gain - _eng_gain) * 0.0008
		var f := 38.0 + _cur_rpm * 150.0
		_ph1 = fmod(_ph1 + f / RATE, 1.0)
		_ph2 = fmod(_ph2 + f * 0.5 / RATE, 1.0)
		_ph3 = fmod(_ph3 + f * 2.01 / RATE, 1.0)
		# Sawtooth + sub square + a buzzy harmonic, then a load-dependent low-pass.
		var s := (_ph1 * 2.0 - 1.0) * 0.55 + (1.0 if _ph2 < 0.5 else -1.0) * 0.3 + (_ph3 * 2.0 - 1.0) * 0.18 * _load
		s += _rng.randf_range(-0.08, 0.08) * (0.3 + _load)
		var cut := 0.08 + 0.25 * _load + 0.12 * _cur_rpm
		_lp += (s - _lp) * cut
		_lp2 += (_lp - _lp2) * cut
		var v := _lp2 * _eng_gain
		buf[i] = Vector2(v, v)
	_eng_pb.push_buffer(buf)


func _fill_skid(paused: bool) -> void:
	var n := _skid_pb.get_frames_available()
	if n <= 0:
		return
	var buf := PackedVector2Array()
	buf.resize(n)
	var target := 0.0 if paused else clampf(_skid_amt, 0.0, 1.0) * 0.45
	for i in n:
		_skid_gain += (target - _skid_gain) * 0.002
		var w := _rng.randf_range(-1.0, 1.0)
		# Crude band-pass around 1–2 kHz gives the squeal.
		_bp1 += (w - _bp1) * 0.35
		_bp2 += (_bp1 - _bp2) * 0.35
		var s := (_bp1 - _bp2) * 2.2
		_sq_ph = fmod(_sq_ph + (1150.0 + _skid_gain * 300.0) / RATE, 1.0)
		s += sin(_sq_ph * TAU) * 0.18
		var v := s * _skid_gain
		buf[i] = Vector2(v, v)
	_skid_pb.push_buffer(buf)


func _fill_siren(paused: bool) -> void:
	var n := _siren_pb.get_frames_available()
	if n <= 0:
		return
	var buf := PackedVector2Array()
	buf.resize(n)
	var target := 0.0
	if _siren_on and not paused:
		target = clampf(1.0 - _siren_dist / 200.0, 0.08, 1.0) * 0.35
	for i in n:
		_siren_gain += (target - _siren_gain) * 0.0008
		_siren_lfo = fmod(_siren_lfo + 0.55 / RATE, 1.0)
		var tri := absf(_siren_lfo * 2.0 - 1.0)
		var f := 620.0 + tri * 700.0
		_siren_ph = fmod(_siren_ph + f / RATE, 1.0)
		var s := (1.0 if _siren_ph < 0.5 else -1.0) * 0.4 + sin(_siren_ph * TAU) * 0.6
		var v := s * _siren_gain
		buf[i] = Vector2(v, v)
	_siren_pb.push_buffer(buf)


# --- clip generation --------------------------------------------------------------------------

func _make_clip(seconds: float, fn: Callable) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var v: float = clampf(fn.call(t, seconds), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = int(RATE)
	w.stereo = false
	w.data = data
	return w


func _impact_wave(t: float, len: float) -> float:
	var env := pow(1.0 - t / len, 3.0)
	return (sin(TAU * 55.0 * t) * 0.8 + _rng.randf_range(-1, 1) * 0.6 * exp(-t * 18.0) + sin(TAU * 140.0 * t) * 0.3) * env


func _soft_wave(t: float, len: float) -> float:
	return (sin(TAU * 90.0 * t) * 0.6 + _rng.randf_range(-1, 1) * 0.3) * pow(1.0 - t / len, 2.0)


func _door_wave(t: float, len: float) -> float:
	return (sin(TAU * 120.0 * t) * 0.6 + _rng.randf_range(-1, 1) * 0.4 * exp(-t * 40.0)) * pow(1.0 - t / len, 2.0)


func _ok_wave(t: float, _len: float) -> float:
	var f := 660.0 if t < 0.12 else 990.0
	return sin(TAU * f * t) * 0.5 * exp(-fmod(t, 0.12) * 6.0)


func _fail_wave(t: float, _len: float) -> float:
	var f := 330.0 if t < 0.2 else 220.0
	return ((1.0 if fmod(t * f, 1.0) < 0.5 else -1.0) * 0.25) * exp(-fmod(t, 0.2) * 3.0)


func _check_wave(t: float, len: float) -> float:
	return sin(TAU * 1320.0 * t) * 0.45 * (1.0 - t / len)


func _horn_wave(t: float, len: float) -> float:
	var env := minf(1.0, t * 40.0) * minf(1.0, (len - t) * 20.0)
	var a := 1.0 if fmod(t * 410.0, 1.0) < 0.5 else -1.0
	var b := 1.0 if fmod(t * 520.0, 1.0) < 0.5 else -1.0
	return (a + b) * 0.18 * env


func _click_wave(t: float, len: float) -> float:
	return sin(TAU * 1800.0 * t) * 0.4 * (1.0 - t / len)
