class_name Sfx
extends Node

## Tiny procedural sound bank. All effects are synthesized at load — no audio
## assets — and played through a small voice pool. Used via static helpers
## (Sfx.play(...)) that route to the single instance the game creates at
## startup; this resolves at compile time even in --script tool runs, unlike
## an autoload global.

const RATE := 44100

static var _inst: Sfx

var _streams := {}
var _voices: Array[AudioStreamPlayer] = []
var _next := 0
var _wind: AudioStreamPlayer
var _enabled := true


func _ready() -> void:
	_inst = self
	# No audio device in headless test runs — stay silent but harmless.
	_enabled = DisplayServer.get_name() != "headless"
	_streams["thunk"] = _thunk()
	_streams["crash"] = _crash()
	_streams["tick"] = _tick()
	_streams["ding"] = _ding()
	_streams["sting"] = _sting()
	for i in 10:
		var v := AudioStreamPlayer.new()
		add_child(v)
		_voices.append(v)
	_wind = AudioStreamPlayer.new()
	_wind.stream = _wind_stream()
	_wind.volume_db = -26.0
	add_child(_wind)


static func play(name: String, pitch := 1.0, volume_db := 0.0) -> void:
	if _inst != null:
		_inst._play(name, pitch, volume_db)


static func start_wind() -> void:
	if _inst != null and _inst._enabled and not _inst._wind.playing:
		_inst._wind.play()


static func stop_wind() -> void:
	if _inst != null:
		_inst._wind.stop()


func _play(name: String, pitch: float, volume_db: float) -> void:
	if not _enabled or not _streams.has(name):
		return
	var v := _voices[_next]
	_next = (_next + 1) % _voices.size()
	v.stream = _streams[name]
	v.pitch_scale = pitch
	v.volume_db = volume_db
	v.play()


# --- Synthesis ---------------------------------------------------------------

func _wav(s: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = s.size() - 1
	return w


## A low "boomp" with a pitch drop — an object landing on the tower.
func _thunk() -> AudioStreamWAV:
	var dur := 0.22
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 20.0)
		var f := lerpf(175.0, 85.0, clampf(t / dur, 0.0, 1.0))
		var body := sin(TAU * f * t)
		var click := (randf() * 2.0 - 1.0) * exp(-t * 130.0) * 0.3
		s[i] = (body * 0.8 + click) * env * 0.7
	return _wav(s)


## Rumbling noise burst — a piece falling off / the tower collapsing.
func _crash() -> AudioStreamWAV:
	var dur := 0.7
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 5.0)
		var noise := randf() * 2.0 - 1.0
		var rumble := sin(TAU * 62.0 * t)
		s[i] = (noise * 0.55 + rumble * 0.45) * env * 0.85
	return _wav(s)


## A short click — one wheel segment passing the pointer.
func _tick() -> AudioStreamWAV:
	var dur := 0.03
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		s[i] = (randf() * 2.0 - 1.0) * exp(-t * 220.0) * 0.5
	return _wav(s)


## A bright two-tone — the wheel landing on its prize.
func _ding() -> AudioStreamWAV:
	var dur := 0.4
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 6.0) * (1.0 - exp(-t * 80.0))
		var f := 880.0 if t < 0.12 else 1318.0
		s[i] = sin(TAU * f * t) * env * 0.4
	return _wav(s)


## A short descending tone — game over.
func _sting() -> AudioStreamWAV:
	var dur := 0.8
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 2.6) * (1.0 - exp(-t * 35.0))
		var f := lerpf(300.0, 110.0, clampf(t / dur, 0.0, 1.0))
		var tri := asin(sin(TAU * f * t)) * (2.0 / PI)  # softer than a sine spike
		s[i] = tri * env * 0.5
	return _wav(s)


## Gentle looping wind — low-passed noise, very quiet.
func _wind_stream() -> AudioStreamWAV:
	var dur := 3.0
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var last := 0.0
	for i in n:
		last = last * 0.985 + (randf() * 2.0 - 1.0) * 0.015
		var lfo := 0.6 + 0.4 * sin(TAU * 2.0 * float(i) / n)  # whole cycles: seamless-ish
		s[i] = last * lfo * 6.0
	return _wav(s, true)
