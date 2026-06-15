class_name GameManager
extends Node3D

## Pack Mule v0.1 game manager: shows a blueprint ghost of the next object,
## places the real physics object where the player clicks, and tracks
## score, strikes, and collapse.

## Set before a scene reload so "Stack Again" jumps straight back into play
## and skips the main menu. A script static, so it survives the reload.
static var _autostart := false

const STRIKES_TO_LOSE := 3
const COLLAPSE_COUNT := 3        # this many falls inside the window = collapse
const COLLAPSE_WINDOW := 2.0     # seconds
const SCORE_PER_OBJECT := 10
const AIM_RANGE := 200.0
const YAW_SPEED := 2.6           # rad/s while holding Q/E
const DONKEY_LENGTH := 3.0       # normalized donkey body length in meters
const INTEGRITY_INTERVAL := 0.4  # seconds between floating-piece sweeps

# The donkey stays at the origin; the mountain is built downward from it,
# peak under the donkey's hooves. Everything below the cloud layer is
# invisible and lethal.
const MOUNTAIN_HEIGHT := 55.0
const MOUNTAIN_WIDEN := 1.8      # horizontal scale: a steeper, more peak-like cone
const MOUNTAIN_SUMMIT_Y := -0.3  # cone apex sits just BELOW the hooves, so no rock
                                 # spike pokes through the donkey — the flat cap
                                 # (below) is what it actually stands on
const CAP_APEX_Y := 0.18         # top of the rounded rock summit, just above feet
const CAP_RADIUS := 5.5          # dome radius: gentle under the donkey, steep at
                                 # the sides so stray pieces slide off, not stick
const CLOUD_LAYER_Y := -32.0     # cloud sea far below, so tall rock stays visible
const KILL_TOP := -29.0          # reaching the cloud band = swallowed, gone
const CLOUD_DISC_RADIUS := 240.0 # how far the textured cloud puffs spread
const CLOUD_GRID_STEP := 7.0     # spacing of carpet puffs (smaller = denser)
const CLOUD_PUFF_SIZE := 13.0    # diameter of one carpet puff

enum Phase { MENU, AIMING, SETTLING, GAME_OVER }

@onready var _camera: Camera3D = $CameraRig/Camera3D
@onready var _camera_rig: CameraRig = $CameraRig
@onready var _hud: GameHud = $HUD
@onready var _ground: StaticBody3D = $Ground
@onready var _mountain: StaticBody3D = $Mountain
@onready var _clouds: Node3D = $Clouds
@onready var _donkey_base: StaticBody3D = $DonkeyBase
@onready var _kill_zone: Area3D = $KillZone

var _phase := Phase.MENU
var _banked := 0                 # money already cashed out (safe; this is your score)
var _pending := 0                # earned-but-not-cashed money (lost on collapse)
var _streak := 0                 # objects placed since the last cash out
var _multiplier := 1.0           # current multiplier (climbs per piece, resets on cash)
var _cash_ready := false         # cash out currently allowed (tower at rest, pot > 0)
var _rest_timer := 0.0           # how long the tower has been continuously at rest
var _unrooted_last := {}         # pieces that read as unrooted in the previous sweep
var _strikes := 0
var _ghost: GhostPreview
var _settling: StackableObject
var _settled: Array[StackableObject] = []
var _base_top := 1.3             # saddle height, measured in _setup_donkey
var _tower_top := 1.3
var _max_height := 0.0
var _fall_times: Array[float] = []
var _last_index := -1
var _rng := RandomNumberGenerator.new()
var _pending_mod: Dictionary = {} # wheel result, locked onto the current object
var _pending_golden := false     # the incoming object is a rare golden one
var _integrity_timer := 0.0
var _placed_count := 0           # objects the player has stacked this run
var _total_weight := 0.0         # combined mass the mule has carried (kg)
var _started := false            # the run has begun (past the main menu)
var _event_milestone := 0        # highest 10 m mark that has fired an event
var _record := 0.0               # best height ever (loaded from settings)
var _beat_record := false        # this run has already surpassed the record

const GOLDEN_CHANCE := 0.01      # 1% of objects spawn golden (cosmetic)


func _ready() -> void:
	Engine.time_scale = 1.0       # a previous run froze the scene for its photo
	add_child(GameSettings.new()) # audio buses + remappable input actions (before Sfx)
	add_child(Sfx.new())          # the procedural sound bank (Sfx.play(...))
	_rng.randomize()
	_setup_mountain()
	_setup_donkey()
	_kill_zone.body_entered.connect(_on_kill_zone_body_entered)
	_hud.restart_requested.connect(_on_restart)
	_hud.start_requested.connect(_start_game)
	_hud.to_main_menu_requested.connect(_to_main_menu)
	_hud.photo_enter_requested.connect(_enter_photo_mode)
	_hud.photo_to_pause_requested.connect(_photo_to_pause)
	_hud.cash_out_requested.connect(_cash_out)
	_hud.wheel_landed.connect(_on_wheel_landed)
	if _autostart:
		_autostart = false
		_start_game()
	else:
		# Wait on the main menu; the peak sits in the background as a backdrop.
		_phase = Phase.MENU
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_camera_rig.set_process(false)
		_hud.show_main_menu()


## Leaves the menu and begins a run: hand control to the fly camera, show
## the readouts, and spawn the first object.
func _start_game() -> void:
	if _started:
		return
	_started = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_camera_rig.set_process(true)
	_record = GameSettings.get_record()
	_event_milestone = 0
	_beat_record = false
	_banked = 0
	_pending = 0
	_streak = 0
	_multiplier = 1.0
	_hud.hide_main_menu()
	_hud.set_in_game_hud_visible(true)
	_hud.set_in_run(true)
	Sfx.stop_music()              # lobby music only — silence (just wind) in-game
	Sfx.start_wind()
	_refresh_hud()
	_refresh_modifier_label()
	_spawn_next()


func _to_main_menu() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	_autostart = false
	get_tree().reload_current_scene()


## Photo mode: the scene freezes (tree paused) but the camera can fly so the
## player can compose a shot of their tower. Reachable from the pause menu
## or directly with the photo hotkey mid-run.
## Photo mode: the scene freezes (tree paused) but the camera flies with
## the normal captured free-look so the player can compose a shot. Reached
## from the pause menu or the photo hotkey. Exit is via Esc -> pause menu.
func _enter_photo_mode() -> void:
	get_tree().paused = true
	if _ghost != null:
		_ghost.visible = false  # no blueprint in the photo
	_camera_rig.process_mode = Node.PROCESS_MODE_ALWAYS  # fly while paused
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Photo mode -> pause menu (camera freezes again; HUD shows the menu).
func _photo_to_pause() -> void:
	_camera_rig.process_mode = Node.PROCESS_MODE_PAUSABLE


func _on_restart() -> void:
	_autostart = true
	get_tree().reload_current_scene()


func _process(delta: float) -> void:
	if _phase != Phase.AIMING or _ghost == null:
		return
	if Input.is_action_pressed("pm_rotate_left"):
		_ghost.spin(YAW_SPEED * delta)
	if Input.is_action_pressed("pm_rotate_right"):
		_ghost.spin(-YAW_SPEED * delta)


func _physics_process(delta: float) -> void:
	_integrity_timer += delta
	if _integrity_timer >= INTEGRITY_INTERVAL:
		_integrity_timer = 0.0
		_check_integrity()
	# Cash out is only offered when the tower has been settled for a moment
	# and you're about to place the next piece — never while things are still
	# falling (which would let you bank right before a collapse registers).
	# The short rest requirement also stops any 1-frame jitter from flickering
	# the prompt.
	_rest_timer = _rest_timer + delta if _tower_at_rest() else 0.0
	var ready := _phase == Phase.AIMING and _pending > 0 and _rest_timer >= 0.35
	if ready != _cash_ready:
		_cash_ready = ready
		_hud.set_cashout_ready(ready)
	if _phase != Phase.AIMING or _ghost == null:
		return
	_update_ghost()


## True when nothing is in motion — no placed piece is still falling or
## settling. Cashing out and the readiness of the cash-out prompt depend on it.
func _tower_at_rest() -> bool:
	for child in get_children():
		var obj := child as StackableObject
		if obj != null and obj.state == StackableObject.State.FALLING:
			return false
	return true


## Nothing may ever float: a glued piece only stays glued while an
## unbroken chain of touching pieces connects it to the donkey (or any
## static world). Everything else breaks loose and falls. No
## center-of-mass math — the glue stays forgiving, contact is the rule.
func _check_integrity() -> void:
	var resting: Array[StackableObject] = []
	for obj in _settled:
		if obj.state == StackableObject.State.SETTLED:
			resting.append(obj)
	if resting.is_empty():
		return
	var space := get_world_3d().direct_space_state
	var rooted := {}
	var adjacent := {}
	var queue: Array[StackableObject] = []
	for obj in resting:
		var neighbors: Array[StackableObject] = []
		for body in obj.touching_bodies(space):
			# Only the donkey anchors the tower — NOT the mountain. A piece
			# resting on bare rock is "floating" as far as the tower goes, so
			# it gets cut loose and slides off the frictionless slope.
			if body == _donkey_base and not rooted.has(obj):
				rooted[obj] = true
				queue.append(obj)
			elif body is StackableObject \
					and (body as StackableObject).state == StackableObject.State.SETTLED:
				neighbors.append(body)
		adjacent[obj] = neighbors
	while not queue.is_empty():
		var obj: StackableObject = queue.pop_back()
		for n: StackableObject in adjacent.get(obj, []):
			if not rooted.has(n):
				rooted[n] = true
				queue.append(n)
	# Debounce: a piece must read as unrooted for TWO sweeps in a row before
	# we cut it loose. A single noisy contact miss (which used to break a
	# settled piece, drop it a hair, re-glue it, and flicker forever) no
	# longer disturbs a tower that is genuinely resting.
	var still_unrooted := {}
	for obj in resting:
		if not rooted.has(obj):
			if _unrooted_last.has(obj):
				obj.break_loose(true)
			else:
				still_unrooted[obj] = true
	_unrooted_last = still_unrooted


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pm_cashout"):
		_cash_out()
		return
	if event.is_action_pressed("pm_photo"):
		# Jump straight into photo mode mid-run (also in the pause menu).
		if _phase == Phase.AIMING or _phase == Phase.SETTLING:
			_hud.start_photo_mode()
		return
	if event.is_action_pressed("pm_spin"):
		# One spin per object: the wheel unlocks again once the modified
		# object has been placed. Spinning while one settles is fine — the
		# result lands on the next object. Only during an active run.
		if (_phase == Phase.AIMING or _phase == Phase.SETTLING) \
				and _pending_mod.is_empty() and not _hud.wheel_busy():
			_hud.spin_wheel()
		return
	if _phase != Phase.AIMING or _ghost == null:
		return
	if event.is_action_pressed("pm_place"):
		if _ghost.visible and _ghost.valid:
			_place_object(_ghost.entry, _ghost.global_transform)
	elif event.is_action_pressed("pm_tip"):
		# Tip the object 90 degrees around the camera's horizontal axis,
		# so "R" always tips it left/right as seen on screen.
		var axis := _camera.global_transform.basis.x
		axis.y = 0.0
		axis = axis.normalized() if axis.length() > 0.01 else Vector3.RIGHT
		_ghost.tip(axis, PI / 2.0)


## The wheel result applies to the current object instantly (the ghost is
## rebuilt at the modified size). If it lands while the previous object is
## still settling, the next object spawns with it.
func _on_wheel_landed(modifier: Dictionary) -> void:
	_pending_mod = modifier
	if _phase == Phase.AIMING and _ghost != null:
		var entry := _ghost.entry
		var user_basis := _ghost.user_basis
		_ghost.queue_free()
		_ghost = GhostPreview.create(entry, _pending_mod)
		_ghost.user_basis = user_basis
		_ghost.visible = false
		add_child(_ghost)
		_refresh_incoming(entry)
	_refresh_modifier_label()


## Casts the crosshair (or the cursor when freed with Esc) into the world
## and hands the hit surface to the ghost, which tilts flush onto it and
## rotates/slides itself out of any overlap. The spot is invalid only on
## the bare ground or when no clear pose exists nearby.
func _update_ghost() -> void:
	var viewport := get_viewport()
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	_hud.set_crosshair(captured)
	var mouse := viewport.get_visible_rect().size / 2.0 if captured \
			else viewport.get_mouse_position()
	var from := _camera.project_ray_origin(mouse)
	var dir := _camera.project_ray_normal(mouse)
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(from, from + dir * AIM_RANGE, 1 | 2)
	var hit := space.intersect_ray(ray)
	if hit.is_empty():
		_ghost.visible = false
		_ghost.set_valid(false)
		return
	_ghost.visible = true
	var normal: Vector3 = hit["normal"]
	var pos: Vector3 = hit["position"]
	var fits := _ghost.place_on(space, pos, normal)
	var on_terrain: bool = hit["collider"] == _ground or hit["collider"] == _mountain
	_ghost.set_valid(not on_terrain and fits)


func _spawn_next() -> void:
	var idx := _weighted_pick()
	_last_index = idx
	var entry: Dictionary = ObjectCatalog.ENTRIES[idx]
	_pending_golden = _rng.randf() < GOLDEN_CHANCE
	_ghost = GhostPreview.create(entry, _pending_mod)
	_ghost.visible = false  # hidden until the first aim raycast lands
	add_child(_ghost)
	_phase = Phase.AIMING
	_refresh_incoming(entry)
	_refresh_modifier_label()


## Picks an object index by spawn weight (rarity), avoiding an immediate
## repeat. Weights come from the player's Odds settings (or the defaults).
func _weighted_pick() -> int:
	var total := 0.0
	var weights: Array[float] = []
	for i in ObjectCatalog.ENTRIES.size():
		var w: float = GameSettings.get_weight(ObjectCatalog.ENTRIES[i]["name"])
		if i == _last_index:
			w *= 0.0001  # all but eliminate an immediate repeat
		weights.append(w)
		total += w
	if total <= 0.0:
		return _rng.randi_range(0, ObjectCatalog.ENTRIES.size() - 1)
	var roll := _rng.randf() * total
	for i in weights.size():
		roll -= weights[i]
		if roll <= 0.0:
			return i
	return weights.size() - 1


func _place_object(entry: Dictionary, xform: Transform3D) -> void:
	var obj := StackableObject.create(entry, _pending_mod, _pending_golden)
	obj.transform = xform
	add_child(obj)
	obj.drop()
	_placed_count += 1
	_total_weight += obj.mass
	# Satisfying placement feedback NOW (not when it settles): a crisp
	# material sound, a squash pop, a puff of dust, and just a hint of a
	# kick. The drop's own collision is muted so it doesn't double up.
	obj.suppress_impact()
	obj.pop()
	Sfx.play_at(obj.impact_sound(), obj.global_position,
			clampf(remap(obj.mass, 5.0, 400.0, 1.5, 0.6), 0.55, 1.6),
			clampf(remap(obj.mass, 5.0, 400.0, -6.0, 4.0), -6.0, 4.0))
	_spawn_dust(obj.global_position - Vector3(0.0, obj.half_extents.y, 0.0), 8, 0.85)
	_camera_rig.shake(clampf(remap(obj.mass, 5.0, 400.0, 0.012, 0.045), 0.012, 0.045))
	if not _pending_mod.is_empty():
		_pending_mod = {}
		_refresh_modifier_label()
	# Scoring runs once; the re-glue handler runs on every settle, because
	# pieces knocked loose by an impact settle (and re-glue) again.
	obj.settled.connect(_on_object_settled.bind(obj), CONNECT_ONE_SHOT)
	obj.settled.connect(_on_object_resettled.bind(obj))
	obj.fell.connect(_on_object_fell.bind(obj))
	_settling = obj
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	_phase = Phase.SETTLING
	_hud.set_incoming("Settling...")


## First settle of a placed object: score it, juice it, move the game along.
func _on_object_settled(obj: StackableObject) -> void:
	if _phase == Phase.GAME_OVER or obj.state != StackableObject.State.SETTLED:
		return
	_settled.append(obj)
	_recompute_tower_top()
	# Each piece earns at the CURRENT multiplier into the pending pot, then
	# the multiplier climbs for the next piece. Cashing out banks the pot and
	# resets the multiplier; a collapse loses the pending pot.
	_pending += int(round(SCORE_PER_OBJECT * _multiplier))
	_streak += 1
	_multiplier = _streak_multiplier(_streak)
	# A rising coin blip — the climb should feel rewarding.
	Sfx.play_at("coin", obj.global_position,
			clampf(1.0 + _streak * 0.05, 1.0, 2.2), -9.0)
	_refresh_hud()
	# Settling itself stays clean — the satisfying feedback fired at placement.
	if obj == _settling:
		_settling = null
	if _phase == Phase.SETTLING:
		_spawn_next()


## The multiplier after `streak` pieces since the last cash out:
## 1, 1.5, 2, 3, 4, 6, 8, 11, 14, 18, ... (gentle acceleration — increments
## come in pairs that grow: +0.5,+0.5, +1,+1, +2,+2, +3,+3, ...).
func _streak_multiplier(streak: int) -> float:
	var m := 1.0
	for step in range(1, streak + 1):
		var pair := (step + 1) / 2  # steps 1-2 -> 1, 3-4 -> 2, 5-6 -> 3, ...
		m += 0.5 if pair == 1 else float(pair - 1)
	return m


## Every settle (including pieces that re-settle after glue broke): glue
## down only if the piece is part of the tower (touching the donkey or an
## already-glued piece). A piece that merely landed on the mountainside
## is left dynamic, so the slick rock slides it away into the clouds.
func _on_object_resettled(obj: StackableObject) -> void:
	if _phase == Phase.GAME_OVER or obj.state != StackableObject.State.SETTLED:
		return
	if not obj.no_glue and _is_anchored(obj):
		obj.lock_in()
	_recompute_tower_top()
	_refresh_hud()


## True if the object rests on the donkey or on an already-glued piece —
## i.e. it belongs to the tower, not the bare mountain.
func _is_anchored(obj: StackableObject) -> bool:
	for body in obj.touching_bodies(get_world_3d().direct_space_state):
		if body == _donkey_base:
			return true
		if body is StackableObject and (body as StackableObject).is_glued():
			return true
	return false


func _on_object_fell(obj: StackableObject) -> void:
	if _phase == Phase.GAME_OVER:
		return
	# Falling juice (a tumble off the tower is dramatic).
	Sfx.play_at("crash", obj.global_position, randf_range(0.9, 1.1))
	_spawn_dust(obj.global_position, 16, 1.4)
	_camera_rig.shake(0.22)
	_settled.erase(obj)
	_strikes += 1
	var now := Time.get_ticks_msec() / 1000.0
	_fall_times.append(now)
	while _fall_times.size() > 0 and now - _fall_times[0] > COLLAPSE_WINDOW:
		_fall_times.remove_at(0)
	_recompute_tower_top()
	_refresh_hud()
	if _fall_times.size() >= COLLAPSE_COUNT:
		_game_over("TOWER COLLAPSED!")
	elif _strikes >= STRIKES_TO_LOSE:
		_game_over("TOO MANY FALLEN OBJECTS")
	elif obj == _settling:
		_settling = null
		_spawn_next()


func _on_kill_zone_body_entered(body: Node3D) -> void:
	if body is StackableObject:
		(body as StackableObject).mark_fallen()


func _recompute_tower_top() -> void:
	_tower_top = _base_top
	for obj in _settled:
		_tower_top = maxf(_tower_top, obj.top_y())
	var h := _tower_top - _base_top
	_max_height = maxf(_max_height, h)
	_check_milestones(h)


## Fires a background event at each new 10 m mark (a different one each
## time), and a one-shot RECORD celebration the moment this run passes the
## best-ever height.
func _check_milestones(h: float) -> void:
	var m := int(floor(h / 10.0))
	if m > _event_milestone:
		_event_milestone = m
		_fire_event(m)
	if not _beat_record and _record >= 1.0 and h > _record:
		_beat_record = true
		Sfx.play("ding")
		_hud.celebrate_record()


## Background flavor at altitude — a different one cycles each milestone.
func _fire_event(milestone: int) -> void:
	match (milestone - 1) % 7:
		0: _event_eagles()
		1: _event_lightning()
		2: _event_helicopter()
		3: _event_balloon()
		4: _event_star()
		5: _event_airship()
		_: _event_fireworks()


func _event_eagles() -> void:
	var sign := 1.0 if _rng.randf() < 0.5 else -1.0
	var y := _rng.randf_range(8.0, 17.0)
	var z := _rng.randf_range(-20.0, 25.0)
	var flock := Node3D.new()
	add_child(flock)
	for i in 5:
		var eagle := _make_visual("res://assets/Eagle.glb", 2.4)
		flock.add_child(eagle)
		var off := Vector3(_rng.randf_range(-8.0, 8.0), _rng.randf_range(-3.0, 3.0), _rng.randf_range(-8.0, 8.0))
		eagle.position = Vector3(-75.0 * sign, y, z) + off
		eagle.rotation.y = -PI / 2.0 * sign
		var tw := create_tween()
		tw.tween_property(eagle, "position",
				Vector3(75.0 * sign, y + _rng.randf_range(-1.5, 1.5), z) + off, _rng.randf_range(5.0, 7.0))
	get_tree().create_timer(8.0).timeout.connect(flock.queue_free)


func _event_lightning() -> void:
	_hud.flash()
	Sfx.play("thunder", _rng.randf_range(0.9, 1.1))


func _event_helicopter() -> void:
	_flyby("res://assets/Helicopter.glb", 4.5, _rng.randf_range(9.0, 17.0), 7.0)


func _event_balloon() -> void:
	# Drifts slowly across and gently rises.
	var sign := 1.0 if _rng.randf() < 0.5 else -1.0
	var y := _rng.randf_range(6.0, 12.0)
	var z := _rng.randf_range(-10.0, 30.0)
	var balloon := _make_visual("res://assets/Hot air balloon.glb", 7.0)
	add_child(balloon)
	balloon.position = Vector3(-80.0 * sign, y, z)
	var tw := create_tween()
	tw.tween_property(balloon, "position", Vector3(80.0 * sign, y + 6.0, z), 12.0)
	get_tree().create_timer(13.0).timeout.connect(balloon.queue_free)


func _event_airship() -> void:
	_flyby("res://assets/Airship.glb", 11.0, _rng.randf_range(12.0, 20.0), 11.0)


func _event_fireworks() -> void:
	var palette := [Color(1, 0.4, 0.4), Color(0.5, 0.8, 1.0), Color(1.0, 0.9, 0.4),
			Color(0.6, 1.0, 0.6), Color(1.0, 0.6, 1.0)]
	for i in 4:
		var pos := Vector3(_rng.randf_range(-30.0, 30.0), _rng.randf_range(16.0, 26.0), _rng.randf_range(-25.0, 25.0))
		var col: Color = palette[_rng.randi() % palette.size()]
		get_tree().create_timer(i * 0.5).timeout.connect(_spawn_firework.bind(pos, col))


func _spawn_firework(pos: Vector3, col: Color) -> void:
	var p := CPUParticles3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.18
	mesh.height = 0.36
	mesh.radial_segments = 5
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.emission_enabled = true
	mat.emission = col
	mesh.material = mat
	p.mesh = mesh
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 60
	p.lifetime = 1.4
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 14.0
	p.gravity = Vector3(0.0, -6.0, 0.0)
	p.color = col
	var ramp := Gradient.new()
	ramp.set_color(0, col)
	ramp.set_color(1, Color(col.r, col.g, col.b, 0.0))
	p.color_ramp = ramp
	add_child(p)
	p.position = pos
	p.emitting = true
	Sfx.play("crash", _rng.randf_range(1.6, 2.0), -8.0)
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)


## A simple straight fly-by across the sky for a vehicle/creature.
func _flyby(path: String, size: float, y: float, secs: float) -> void:
	var sign := 1.0 if _rng.randf() < 0.5 else -1.0
	var z := _rng.randf_range(-15.0, 30.0)
	var node := _make_visual(path, size)
	add_child(node)
	node.position = Vector3(-95.0 * sign, y, z)
	node.rotation.y = PI / 2.0 * sign
	var tw := create_tween()
	tw.tween_property(node, "position", Vector3(95.0 * sign, y, z), secs)
	get_tree().create_timer(secs + 1.0).timeout.connect(node.queue_free)


func _event_star() -> void:
	var star := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.95, 0.7)
	mesh.material = mat
	star.mesh = mesh
	add_child(star)
	var sign := 1.0 if _rng.randf() < 0.5 else -1.0
	var y := _rng.randf_range(18.0, 26.0)
	star.position = Vector3(-80.0 * sign, y, _rng.randf_range(-30.0, 30.0))
	var tw := create_tween()
	tw.tween_property(star, "position", Vector3(80.0 * sign, y - 12.0, star.position.z), 1.6)
	get_tree().create_timer(2.0).timeout.connect(star.queue_free)


## Loads a .glb as a plain (collision-free) visual, normalized so its
## longest side is target_size, recentered. Used for background events.
func _make_visual(path: String, target_size: float) -> Node3D:
	var holder := Node3D.new()
	var model: Node3D = (load(path) as PackedScene).instantiate()
	holder.add_child(model)
	var pts := PackedVector3Array()
	StackableObject.collect_hull_points(model, Transform3D.IDENTITY, pts)
	if not pts.is_empty():
		var aabb := StackableObject.points_aabb(pts)
		var longest := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
		model.scale = Vector3.ONE * (target_size / longest)
		model.position = -aabb.get_center() * model.scale
	return holder


func _refresh_hud() -> void:
	_hud.set_money(_banked)
	_hud.set_pending(_pending, _multiplier)
	_hud.set_height(_tower_top - _base_top)
	_hud.set_strikes(_strikes, STRIKES_TO_LOSE)


## Cash out: bank the pending pot into your safe money and reset the
## multiplier to ×1 — the run keeps going. Always available mid-run.
func _cash_out() -> void:
	# Only between placements, with the tower fully at rest — you can't bank
	# while pieces are mid-fall (that was the exploit).
	if _phase != Phase.AIMING or _pending <= 0 or not _tower_at_rest():
		return
	var amount := _pending
	_banked += amount
	_pending = 0
	_streak = 0
	_multiplier = 1.0
	Sfx.play("register")
	Sfx.play("coin")
	_hud.bank_flourish(_banked, amount)
	_hud.set_pending(_pending, _multiplier)


func _refresh_modifier_label() -> void:
	if _pending_mod.is_empty():
		_hud.set_modifier("Modifier: -   (Tab: spin the wheel)")
	else:
		_hud.set_modifier("Modifier: %s   (locked on this object)" % _pending_mod["name"])


func _refresh_incoming(entry: Dictionary) -> void:
	var label: String = entry["name"]
	if not _pending_mod.is_empty():
		label = "%s %s" % [_pending_mod["name"], label]
	if _pending_golden:
		label = "GOLDEN %s" % label
	_hud.set_incoming("INCOMING: %s" % label)


## The run ends only when the tower collapses. You keep your banked money;
## the pending (un-cashed) pot is lost — that's the risk of not cashing out.
func _game_over(reason: String) -> void:
	_phase = Phase.GAME_OVER
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	_hud.set_in_run(false)        # no pausing on the game-over screen
	get_tree().paused = false
	Sfx.stop_wind()
	Sfx.play("sting")
	var lost := _pending
	# Freeze the whole scene so the photo is crisp, then frame and shoot the
	# tower before any UI is shown.
	Engine.time_scale = 0.0
	_camera_rig.set_process(false)
	_camera_rig.set_physics_process(false)
	_hud.set_in_game_hud_visible(false)
	var photo := await _capture_tower_photo()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE  # so the buttons are clickable
	var is_record := _max_height > _record
	GameSettings.set_record(maxf(_record, _max_height))
	GameSettings.set_score_record(maxi(GameSettings.get_score_record(), _banked))
	var stats := {
		"height": _max_height,
		"objects": _placed_count,
		"weight": _total_weight,
		"score": _banked,
		"lost": lost,
		"record": maxf(_record, _max_height),
		"score_record": GameSettings.get_score_record(),
		"new_record": is_record,
	}
	_hud.show_game_over(reason, stats, photo)


## Photographs the whole tower (donkey + everything stacked) side-on, as
## close as possible while still fitting every piece in frame. Fitting the
## actual extents (not a bounding sphere) keeps a tall tower large instead
## of tiny; nothing is ever cut off.
func _capture_tower_photo() -> Image:
	if DisplayServer.get_name() == "headless":
		return null  # no renderer in headless test runs
	var aabb := _tower_world_aabb()
	var center := aabb.get_center()
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / vp.y
	var v_half := deg_to_rad(_camera.fov * 0.5)        # vertical half-FOV
	var h_half := atan(tan(v_half) * aspect)           # horizontal half-FOV
	# Side-on profile of the mule. Kept nearly level (small Y) so the
	# vertical framing stays symmetric and the top never clips; a little Z
	# gives a hint of three-quarter depth.
	var dir := Vector3(1.0, 0.05, 0.22).normalized()
	# Distance that fits the tower's height (vertical) and its widest
	# horizontal spread (whichever needs the camera farther wins), with
	# generous margin so the whole tower is always inside the frame.
	var dist_v := (aabb.size.y * 0.5) / tan(v_half)
	var dist_h := (maxf(aabb.size.x, aabb.size.z) * 0.5) / tan(h_half)
	var dist := maxf(dist_v, dist_h) * 1.18
	_camera.global_position = center + dir * dist
	_camera.look_at(center, Vector3.UP)
	# Let the moved camera render before grabbing the frame.
	await get_tree().process_frame
	await get_tree().process_frame
	return get_viewport().get_texture().get_image()


var _dust_mesh: SphereMesh
var _dust_ramp: Gradient


## A one-shot puff of dust at a world position, freed after it fades.
func _spawn_dust(pos: Vector3, count: int, scale: float) -> void:
	if _dust_mesh == null:
		_dust_mesh = SphereMesh.new()
		_dust_mesh.radius = 0.16
		_dust_mesh.height = 0.32
		_dust_mesh.radial_segments = 6
		_dust_mesh.rings = 3
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_dust_mesh.material = mat
		_dust_ramp = Gradient.new()
		_dust_ramp.set_color(0, Color(0.92, 0.89, 0.83, 0.9))
		_dust_ramp.set_color(1, Color(0.92, 0.89, 0.83, 0.0))
	var p := CPUParticles3D.new()
	p.mesh = _dust_mesh
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = count
	p.lifetime = 0.7
	p.direction = Vector3.UP
	p.spread = 75.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 3.2
	p.gravity = Vector3(0.0, -5.0, 0.0)
	p.scale_amount_min = 0.5 * scale
	p.scale_amount_max = 1.3 * scale
	p.color_ramp = _dust_ramp
	add_child(p)
	p.position = pos
	p.emitting = true
	get_tree().create_timer(1.4).timeout.connect(p.queue_free)


## World-space box around the donkey and every object that belongs to the
## tower — settled pieces plus the one still coming to rest on top — so the
## photo never cuts the top off. Stray tumbling debris is excluded so it
## can't blow the framing out.
func _tower_world_aabb() -> AABB:
	# Start with the donkey/summit region so the mule is always in shot.
	var aabb := AABB(Vector3(-1.9, -0.4, -1.9), Vector3(3.8, 3.0, 3.8))
	var members: Array[StackableObject] = _settled.duplicate()
	if _settling != null and _settling not in members:
		members.append(_settling)
	for obj: StackableObject in members:
		# Only frame pieces actually at rest — a piece still tumbling far
		# below would otherwise drag the framing off the tower entirely.
		if not is_instance_valid(obj) or obj.state != StackableObject.State.SETTLED:
			continue
		var t := obj.global_transform
		var he := obj.half_extents
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					aabb = aabb.expand(t * Vector3(sx * he.x, sy * he.y, sz * he.z))
	return aabb


## Builds the world: the donkey stands on a mountain peak. The peak's
## highest point is moved to the origin (so the donkey, camera, and all
## height logic stay untouched), the old green ground drops to the
## mountain's base, a cloud layer hides everything below the summit, and
## the kill zone becomes the whole volume beneath the clouds.
func _setup_mountain() -> void:
	var model: Node3D = (load("res://assets/Mountain.glb") as PackedScene).instantiate()
	_mountain.add_child(model)
	var points := PackedVector3Array()
	StackableObject.collect_hull_points(model, Transform3D.IDENTITY, points)
	if points.is_empty():
		push_error("Mountain.glb has no mesh geometry")
		return
	var aabb := StackableObject.points_aabb(points)
	var sf := MOUNTAIN_HEIGHT / aabb.size.y
	var scale := Vector3(sf * MOUNTAIN_WIDEN, sf, sf * MOUNTAIN_WIDEN)
	var peak := points[0]
	for p in points:
		if p.y > peak.y:
			peak = p
	model.scale = scale
	# Apex sits just below the hooves so no rock spike pokes through the
	# donkey; the flat cap built below is its actual footing.
	model.position = -peak * scale + Vector3(0.0, MOUNTAIN_SUMMIT_Y, 0.0)

	# Rock colour, so the peak reads as a mountain instead of blending into
	# the white clouds.
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.44, 0.41, 0.38)
	rock.roughness = 1.0
	_apply_material(model, rock)

	var faces := PackedVector3Array()
	_collect_faces(model, Transform3D.IDENTITY, faces)
	var trimesh := ConcavePolygonShape3D.new()
	trimesh.set_faces(faces)
	var col := CollisionShape3D.new()
	col.shape = trimesh
	_mountain.add_child(col)
	_mountain.add_to_group("mountain")  # so impacts here play the stony sound
	# Frictionless rock: anything that misses the tower slides off the peak
	# and down through the clouds instead of sticking to the slope.
	var slick := PhysicsMaterial.new()
	slick.friction = 0.0
	slick.bounce = 0.0
	_mountain.physics_material_override = slick

	_add_summit_cap(rock)

	# The old ground becomes the valley floor, far out of sight.
	_ground.position.y = -MOUNTAIN_HEIGHT
	# Kill volume: everything below the cloud layer, down to the valley.
	var kill_shape: CollisionShape3D = _kill_zone.get_node("KillShape")
	var kill_box := BoxShape3D.new()
	kill_box.size = Vector3(400.0, MOUNTAIN_HEIGHT, 400.0)
	kill_shape.shape = kill_box
	kill_shape.position = Vector3(0.0, KILL_TOP - MOUNTAIN_HEIGHT / 2.0, 0.0)

	_setup_clouds()
	_setup_atmosphere()


## Horizon haze + a ring of distant peaks, so beyond the cloud sea reads as
## an endless mountain range instead of empty grey sky.
func _setup_atmosphere() -> void:
	var env := ($WorldEnvironment as WorldEnvironment).environment
	if env != null:
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		env.fog_light_color = Color(0.80, 0.86, 0.93)
		env.fog_density = 0.0032
		env.fog_aerial_perspective = 0.5
		env.fog_sky_affect = 0.25
		if env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
			var sky := env.sky.sky_material as ProceduralSkyMaterial
			sky.sky_horizon_color = Color(0.82, 0.88, 0.94)
			sky.ground_horizon_color = Color(0.82, 0.88, 0.94)

	var scene := load("res://assets/Mountain.glb") as PackedScene
	var haze := Color(0.74, 0.81, 0.9)
	var rock := Color(0.46, 0.53, 0.64)
	for i in 16:
		var holder := Node3D.new()
		var model: Node3D = scene.instantiate()
		holder.add_child(model)
		var pts := PackedVector3Array()
		StackableObject.collect_hull_points(model, Transform3D.IDENTITY, pts)
		if pts.is_empty():
			holder.free()
			continue
		var aabb := StackableObject.points_aabb(pts)
		var height := _rng.randf_range(40.0, 95.0)
		var sf := height / aabb.size.y
		var peak := pts[0]
		for p in pts:
			if p.y > peak.y:
				peak = p
		var widen := _rng.randf_range(1.2, 2.2)
		model.scale = Vector3(sf * widen, sf, sf * widen)
		model.position = Vector3(-aabb.get_center().x * sf * widen, -peak.y * sf,
				-aabb.get_center().z * sf * widen)
		var ang := TAU * i / 16.0 + _rng.randf_range(-0.18, 0.18)
		var dist := _rng.randf_range(150.0, 260.0)
		holder.position = Vector3(cos(ang) * dist, _rng.randf_range(-8.0, 16.0), sin(ang) * dist)
		holder.rotation.y = _rng.randf_range(0.0, TAU)
		# Atmospheric perspective: farther peaks fade toward the haze colour.
		var tint := rock.lerp(haze, clampf((dist - 150.0) / 130.0, 0.0, 0.85))
		_apply_material(holder, _flat_material(tint))
		_clouds.add_child(holder)


func _flat_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	return mat


## A rounded rock dome at the very summit. A cone tip can't hold a 3 m
## donkey (it floats or a spike pokes through the belly) and a flat shelf
## traps stray objects; a dome is gentle under the donkey's hooves yet
## curves steeply at the sides, so anything that misses slides off. The
## collision is an exact SphereShape3D so nothing clips into the visual.
func _add_summit_cap(rock: StandardMaterial3D) -> void:
	var center := Vector3(0.0, CAP_APEX_Y - CAP_RADIUS, 0.0)
	var mesh := SphereMesh.new()
	mesh.radius = CAP_RADIUS
	mesh.height = CAP_RADIUS * 2.0
	mesh.material = rock
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = center
	_mountain.add_child(mi)

	var shape := SphereShape3D.new()
	shape.radius = CAP_RADIUS
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = center
	_mountain.add_child(col)


## Recursively overrides the material of every mesh in a subtree.
func _apply_material(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for child in node.get_children():
		_apply_material(child, mat)


## A dense white carpet of cloud puffs filling a wide disc around the peak,
## backed by a solid white plane so no gap ever reveals the valley. The
## puffs are one cloud sphere mesh drawn as a MultiMesh (hundreds of
## instances, one draw call) so the sea is cheap.
func _setup_clouds() -> void:
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.96, 0.97, 0.99)
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# A huge backstop plane: distant cloud cover stretching to the horizon,
	# fading into the sky via fog so there's no bare sky beyond the puffs.
	var plane := PlaneMesh.new()
	plane.size = Vector2(4000.0, 4000.0)
	plane.material = white
	var sea := MeshInstance3D.new()
	sea.mesh = plane
	sea.position = Vector3(0.0, CLOUD_LAYER_Y - 1.5, 0.0)
	_clouds.add_child(sea)

	var puff_mesh := _cloud_puff_mesh()
	if puff_mesh == null:
		return
	var base := CLOUD_PUFF_SIZE / maxf(puff_mesh.get_aabb().size.x, 0.001)

	# Jittered grid of puff transforms across the disc.
	var xforms: Array[Transform3D] = []
	var r := CLOUD_DISC_RADIUS
	var x := -r
	while x <= r:
		var z := -r
		while z <= r:
			if x * x + z * z <= r * r:
				var pos := Vector3(x + _rng.randf_range(-1.5, 1.5),
						CLOUD_LAYER_Y + _rng.randf_range(-1.2, 0.8),
						z + _rng.randf_range(-1.5, 1.5))
				var s := base * _rng.randf_range(0.8, 1.6)
				# Squashed a little so the carpet reads flat, not lumpy balls.
				var b := Basis.from_scale(Vector3(s, s * 0.6, s)) \
						.rotated(Vector3.UP, _rng.randf_range(0.0, TAU))
				xforms.append(Transform3D(b, pos))
			z += CLOUD_GRID_STEP
		x += CLOUD_GRID_STEP

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = puff_mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = white
	_clouds.add_child(mmi)


## The single sphere mesh that Cloud.glb is built from (it is 16 copies of
## one sphere); used as the carpet puff.
func _cloud_puff_mesh() -> Mesh:
	var model: Node3D = (load("res://assets/Cloud.glb") as PackedScene).instantiate()
	var found := _find_first_mesh(model)
	model.queue_free()
	if found == null:
		push_error("Cloud.glb has no mesh geometry")
	return found


func _find_first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return (node as MeshInstance3D).mesh
	for child in node.get_children():
		var found := _find_first_mesh(child)
		if found != null:
			return found
	return null


## Builds the donkey base: normalized visual model, an exact trimesh hitbox
## of the whole body (head, neck, rump — all stackable surfaces), and a
## flat red platform sitting on top of the back as the clear primary base.
func _setup_donkey() -> void:
	var model: Node3D = (load("res://assets/Donkey.glb") as PackedScene).instantiate()
	_donkey_base.add_child(model)

	var points := PackedVector3Array()
	StackableObject.collect_hull_points(model, Transform3D.IDENTITY, points)
	if points.is_empty():
		push_error("Donkey.glb has no mesh geometry")
		return
	var aabb := StackableObject.points_aabb(points)
	var along_x := aabb.size.x >= aabb.size.z
	var sf := DONKEY_LENGTH / maxf(aabb.size.x, aabb.size.z)
	var center := aabb.get_center()
	# Center the donkey on the origin with its feet at y = 0.
	var origin_offset := Vector3(center.x, aabb.position.y, center.z)
	model.scale = Vector3.ONE * sf
	model.position = -origin_offset * sf

	# Full-body collision from the actual triangles (static body, so a
	# concave shape is fine) — the player can stack on the head if they dare.
	var faces := PackedVector3Array()
	_collect_faces(model, Transform3D.IDENTITY, faces)
	var trimesh := ConcavePolygonShape3D.new()
	trimesh.set_faces(faces)
	var body_col := CollisionShape3D.new()
	body_col.shape = trimesh
	_donkey_base.add_child(body_col)

	# The platform sits over the back, biased toward the rump: the head end
	# is whichever outer third of the body reaches higher (ears beat tail).
	var axis := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
	var head_max := 0.0
	var tail_max := 0.0
	for v in faces:
		var t := v.dot(axis)
		if t > DONKEY_LENGTH * 0.25:
			head_max = maxf(head_max, v.y)
		elif t < -DONKEY_LENGTH * 0.25:
			tail_max = maxf(tail_max, v.y)
	var t_center := -0.25 if head_max >= tail_max else 0.25

	var width := (aabb.size.z if along_x else aabb.size.x) * sf
	var saddle_l := 1.0
	var saddle_w := maxf(width * 1.05, 0.9)
	# The highest body point inside the footprint decides the platform
	# height, so nothing (spine, mane, tail root) pokes up through it.
	var back_y := 0.0
	for v in faces:
		var t := v.dot(axis) - t_center
		var w := v.z if along_x else v.x
		if absf(t) < saddle_l / 2.0 and absf(w) < saddle_w / 2.0:
			back_y = maxf(back_y, v.y)
	if back_y <= 0.0:
		back_y = aabb.size.y * sf * 0.6

	# Bottom sinks 2 cm into the fur so there is no visible gap.
	var saddle_size := Vector3(saddle_l, 0.12, saddle_w) if along_x \
			else Vector3(saddle_w, 0.12, saddle_l)
	var saddle_top := back_y - 0.02 + saddle_size.y
	_add_platform(saddle_size,
			axis * t_center + Vector3(0.0, saddle_top - saddle_size.y / 2.0, 0.0))

	_base_top = saddle_top
	_tower_top = saddle_top


## Collects world triangles of every mesh in the subtree (transforms baked
## in, so the collision shape itself stays unscaled).
func _collect_faces(node: Node, parent_xform: Transform3D, faces: PackedVector3Array) -> void:
	var xform := parent_xform
	if node is Node3D:
		xform = parent_xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		for v in (node as MeshInstance3D).mesh.get_faces():
			faces.append(xform * v)
	for child in node.get_children():
		_collect_faces(child, xform, faces)


func _add_platform(size: Vector3, box_center: Vector3) -> void:
	var box := BoxShape3D.new()
	box.size = size
	var col := CollisionShape3D.new()
	col.shape = box
	col.position = box_center
	_donkey_base.add_child(col)
	# Dark red blanket so the primary landing zone reads clearly.
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.15, 0.15)
	bm.material = mat
	var mesh := MeshInstance3D.new()
	mesh.mesh = bm
	mesh.position = box_center
	_donkey_base.add_child(mesh)
