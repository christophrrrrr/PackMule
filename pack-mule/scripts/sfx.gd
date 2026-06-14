class_name Sfx
extends Node

## Tiny procedural sound bank. All effects are synthesized at load — no audio
## assets — and played through a small voice pool. Used via static helpers
## (Sfx.play(...)) that route to the single instance the game creates at
## startup; this resolves at compile time even in --script tool runs, unlike
## an autoload global.

const RATE := 44100

## Beyond this distance from the listener (camera), positional sounds are
## inaudible — so an object landing far below the flying player is quiet.
const SFX_MAX_DISTANCE := 110.0
const SFX_UNIT_SIZE := 14.0

static var _inst: Sfx

var _streams := {}
var _voices: Array[AudioStreamPlayer] = []         # 2D: UI / non-positional
var _voices3d: Array[AudioStreamPlayer3D] = []     # positional: impacts
var _next := 0
var _next3d := 0
var _wind: AudioStreamPlayer
var _enabled := true


func _ready() -> void:
	_inst = self
	# No audio device in headless test runs — stay silent but harmless.
	_enabled = DisplayServer.get_name() != "headless"
	# Each sound prefers a real file in res://assets/sfx/<name>.ogg|wav and
	# falls back to the synthesized version until you add one.
	_streams["thunk"] = _file_or("wood", _thunk())
	_streams["metal"] = _file_or("metal", _metal())
	_streams["soft"] = _file_or("soft", _soft())
	_streams["glass"] = _file_or("glass", _glass())
	_streams["piano"] = _file_or("piano", _piano())
	_streams["critter"] = _file_or("critter", _critter())
	_streams["rock"] = _file_or("rock", _rock())
	_streams["crash"] = _file_or("crash", _crash())
	_streams["thunder"] = _file_or("thunder", _thunder())
	_streams["tick"] = _file_or("tick", _tick())
	_streams["ding"] = _file_or("ding", _ding())
	_streams["sting"] = _file_or("sting", _sting())
	for i in 10:
		var v := AudioStreamPlayer.new()
		v.bus = "SFX"  # bus created by GameSettings (added before Sfx)
		add_child(v)
		_voices.append(v)
	for i in 14:
		var v3 := AudioStreamPlayer3D.new()
		v3.bus = "SFX"
		v3.max_distance = SFX_MAX_DISTANCE
		v3.unit_size = SFX_UNIT_SIZE
		v3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(v3)
		_voices3d.append(v3)
	_wind = AudioStreamPlayer.new()
	_wind.stream = _file_or("wind", _wind_stream())
	_wind.volume_db = -26.0
	_wind.bus = "Ambience"
	add_child(_wind)


## Returns a real sound file from res://assets/sfx/ if present, else the
## supplied synthesized fallback. Lets the user drop in proper SFX without
## any code change.
func _file_or(name: String, fallback: AudioStream) -> AudioStream:
	for ext: String in [".ogg", ".wav"]:
		var path := "res://assets/sfx/" + name + ext
		if ResourceLoader.exists(path):
			return load(path)
	return fallback


## Non-positional (UI, wheel, stings) — same volume regardless of camera.
static func play(name: String, pitch := 1.0, volume_db := 0.0) -> void:
	if _inst != null:
		_inst._play(name, pitch, volume_db)


## Positional — plays at a world point so it fades with distance from the
## flying camera (the audio listener). Used for impacts and landings.
static func play_at(name: String, pos: Vector3, pitch := 1.0, volume_db := 0.0) -> void:
	if _inst != null:
		_inst._play_at(name, pos, pitch, volume_db)


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


func _play_at(name: String, pos: Vector3, pitch: float, volume_db: float) -> void:
	if not _enabled or not _streams.has(name):
		return
	var v := _voices3d[_next3d]
	_next3d = (_next3d + 1) % _voices3d.size()
	v.stream = _streams[name]
	v.pitch_scale = pitch
	v.volume_db = volume_db
	v.global_position = pos
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


## Metal clang — inharmonic ringing partials with a bright transient.
func _metal() -> AudioStreamWAV:
	var dur := 0.45
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var f := 520.0
	for i in n:
		var t := float(i) / RATE
		var ring := sin(TAU * f * t) * 0.5 + sin(TAU * f * 2.76 * t) * 0.3 \
				+ sin(TAU * f * 5.4 * t) * 0.2
		var click := (randf() * 2.0 - 1.0) * exp(-t * 200.0) * 0.4
		s[i] = ring * exp(-t * 9.0) * 0.55 + click
	return _wav(s)


## Soft thud — cushion / cloth / rubber: low and quickly muffled.
func _soft() -> AudioStreamWAV:
	var dur := 0.16
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp = lp * 0.8 + (randf() * 2.0 - 1.0) * 0.2
		var body := sin(TAU * 120.0 * t) * 0.5
		s[i] = (body + lp * 0.3) * exp(-t * 32.0) * 0.5
	return _wav(s)


## Ceramic / glass clink — high and bright with a fast decay.
func _glass() -> AudioStreamWAV:
	var dur := 0.3
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var ring := sin(TAU * 2100.0 * t) * 0.6 + sin(TAU * 3170.0 * t) * 0.4
		var click := (randf() * 2.0 - 1.0) * exp(-t * 400.0) * 0.25
		s[i] = ring * exp(-t * 16.0) * 0.4 + click
	return _wav(s)


## Piano — a little chord (root + fifth + octave) so dropping the piano
## actually plays a note. Decays like a struck string.
func _piano() -> AudioStreamWAV:
	var dur := 0.9
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var root := 196.0  # G3
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 4.0) * (1.0 - exp(-t * 200.0))
		var chord := sin(TAU * root * t) * 0.5 + sin(TAU * root * 1.5 * t) * 0.3 \
				+ sin(TAU * root * 2.0 * t) * 0.25
		s[i] = chord * env * 0.5
	return _wav(s)


## Critter — a soft organic "bonk" with a quick pitch drop, for animals.
func _critter() -> AudioStreamWAV:
	var dur := 0.2
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var f := lerpf(280.0, 150.0, clampf(t / dur, 0.0, 1.0))
		var body := sin(TAU * f * t)
		var grit := (randf() * 2.0 - 1.0) * exp(-t * 60.0) * 0.2
		s[i] = (body * 0.7 + grit) * exp(-t * 16.0) * 0.5
	return _wav(s)


## A dull, gritty stone thud — an object striking the bare mountain. Darker
## and crunchier than the tonal "thunk" of landing on the tower.
func _rock() -> AudioStreamWAV:
	var dur := 0.18
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 30.0)
		# Low-passed noise = a "stony" crunch rather than a white hiss.
		lp = lp * 0.6 + (randf() * 2.0 - 1.0) * 0.4
		var thud := sin(TAU * 68.0 * t) * 0.4
		s[i] = (lp * 0.7 + thud) * env * 0.6
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


## A continuous, steady wind: low-passed noise at a near-constant level,
## with the buffer's tail cross-faded into its head so the loop is
## seamless (no gap or click between repeats).
func _wind_stream() -> AudioStreamWAV:
	var dur := 4.0
	var n := int(RATE * dur)
	var fade := int(RATE * 0.4)  # crossfade length
	var raw := PackedFloat32Array()
	raw.resize(n + fade)
	var last := 0.0
	for i in raw.size():
		last = last * 0.99 + (randf() * 2.0 - 1.0) * 0.01
		# Very gentle, never-near-zero swell so it reads as steady wind.
		var swell := 0.85 + 0.15 * sin(TAU * 1.0 * float(i) / n)
		raw[i] = last * swell * 7.0
	# Cross-fade the extra tail samples back over the first `fade` samples.
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		s[i] = raw[i]
	for i in fade:
		var t := float(i) / fade
		s[i] = lerpf(raw[n + i], raw[i], t)
	return _wav(s, true)


## Lightning thunder — a sharp crack then a long low rumble.
func _thunder() -> AudioStreamWAV:
	var dur := 1.3
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp = lp * 0.92 + (randf() * 2.0 - 1.0) * 0.08
		var crack := (randf() * 2.0 - 1.0) * exp(-t * 45.0) * 0.6
		var rumble := lp * exp(-t * 2.2) * 1.4
		s[i] = clampf(crack + rumble, -1.0, 1.0) * 0.8
	return _wav(s)
