extends Node3D

## Pack Mule v0.1 game manager: shows a blueprint ghost of the next object,
## places the real physics object where the player clicks, and tracks
## score, strikes, and collapse.

const STRIKES_TO_LOSE := 3
const COLLAPSE_COUNT := 3        # this many falls inside the window = collapse
const COLLAPSE_WINDOW := 2.0     # seconds
const SCORE_PER_OBJECT := 10
const HEIGHT_SCORE_PER_METER := 10.0
const AIM_RANGE := 200.0
const YAW_SPEED := 2.6           # rad/s while holding Q/E
const DONKEY_LENGTH := 3.0       # normalized donkey body length in meters

enum Phase { AIMING, SETTLING, GAME_OVER }

@onready var _camera: Camera3D = $CameraRig/Camera3D
@onready var _hud: GameHud = $HUD
@onready var _ground: StaticBody3D = $Ground
@onready var _donkey_base: StaticBody3D = $DonkeyBase
@onready var _kill_zone: Area3D = $KillZone

var _phase := Phase.AIMING
var _score := 0
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


func _ready() -> void:
	_rng.randomize()
	_setup_donkey()
	_kill_zone.body_entered.connect(_on_kill_zone_body_entered)
	_hud.restart_requested.connect(func() -> void: get_tree().reload_current_scene())
	_refresh_hud()
	_spawn_next()


func _process(delta: float) -> void:
	if _phase != Phase.AIMING or _ghost == null:
		return
	if Input.is_key_pressed(KEY_Q):
		_ghost.spin(YAW_SPEED * delta)
	if Input.is_key_pressed(KEY_E):
		_ghost.spin(-YAW_SPEED * delta)


func _physics_process(_delta: float) -> void:
	if _phase != Phase.AIMING or _ghost == null:
		return
	_update_ghost()


func _unhandled_input(event: InputEvent) -> void:
	if _phase != Phase.AIMING or _ghost == null:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if _ghost.visible and _ghost.valid:
			_place_object(_ghost.entry, _ghost.global_transform)
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_R:
		# Tip the object 90 degrees around the camera's horizontal axis,
		# so "R" always tips it left/right as seen on screen.
		var axis := _camera.global_transform.basis.x
		axis.y = 0.0
		axis = axis.normalized() if axis.length() > 0.01 else Vector3.RIGHT
		_ghost.tip(axis, PI / 2.0)


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
	var on_ground: bool = hit["collider"] == _ground
	_ghost.set_valid(not on_ground and fits)


func _spawn_next() -> void:
	var idx := _rng.randi_range(0, ObjectCatalog.ENTRIES.size() - 1)
	while idx == _last_index:
		idx = _rng.randi_range(0, ObjectCatalog.ENTRIES.size() - 1)
	_last_index = idx
	var entry: Dictionary = ObjectCatalog.ENTRIES[idx]
	_ghost = GhostPreview.create(entry)
	_ghost.visible = false  # hidden until the first aim raycast lands
	add_child(_ghost)
	_phase = Phase.AIMING
	_hud.set_incoming("Incoming: %s" % entry["name"])


func _place_object(entry: Dictionary, xform: Transform3D) -> void:
	var obj := StackableObject.create(entry)
	obj.transform = xform
	add_child(obj)
	obj.drop()
	obj.settled.connect(_on_object_settled.bind(obj), CONNECT_ONE_SHOT)
	obj.fell.connect(_on_object_fell.bind(obj))
	_settling = obj
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	_phase = Phase.SETTLING
	_hud.set_incoming("Settling...")


func _on_object_settled(obj: StackableObject) -> void:
	if _phase == Phase.GAME_OVER or obj.state != StackableObject.State.SETTLED:
		return
	_settled.append(obj)
	_score += SCORE_PER_OBJECT
	if obj == _settling:
		_settling = null
	_recompute_tower_top()
	_refresh_hud()
	if _phase == Phase.SETTLING:
		_spawn_next()


func _on_object_fell(obj: StackableObject) -> void:
	if _phase == Phase.GAME_OVER:
		return
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
	_max_height = maxf(_max_height, _tower_top - _base_top)


func _total_score() -> int:
	return _score + int(roundf(_max_height * HEIGHT_SCORE_PER_METER))


func _refresh_hud() -> void:
	_hud.set_score(_total_score())
	_hud.set_height(_tower_top - _base_top)
	_hud.set_strikes(_strikes, STRIKES_TO_LOSE)


func _game_over(reason: String) -> void:
	_phase = Phase.GAME_OVER
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE  # so the Restart button is clickable
	_hud.set_crosshair(false)
	_hud.set_incoming("")
	_hud.show_game_over(reason, _total_score(), _max_height)


## Builds the donkey base: normalized visual model plus box collision for the
## torso and a flat "saddle" platform on its back (a convex hull of the whole
## donkey would slope from head to rump, which makes stacking unfair).
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

	# The back height is the highest mesh point near the middle of the body
	# (the head sits at one end, so it is excluded by the window).
	var back_y := 0.0
	for p in points:
		var q := (p - origin_offset) * sf
		var t := q.x if along_x else q.z
		if absf(t) < DONKEY_LENGTH * 0.15:
			back_y = maxf(back_y, q.y)
	if back_y <= 0.0:
		back_y = aabb.size.y * sf * 0.6

	var width := (aabb.size.z if along_x else aabb.size.x) * sf
	var saddle_l := maxf(DONKEY_LENGTH * 0.45, 1.3)
	var saddle_w := maxf(width * 1.05, 0.9)
	var saddle_size := Vector3(saddle_l, 0.15, saddle_w) if along_x \
			else Vector3(saddle_w, 0.15, saddle_l)
	var saddle_top := back_y + 0.03
	_add_donkey_box(saddle_size, Vector3(0.0, saddle_top - saddle_size.y / 2.0, 0.0), true)

	var torso_h := back_y * 0.55
	var torso_size := Vector3(DONKEY_LENGTH * 0.6, torso_h, width * 0.9) if along_x \
			else Vector3(width * 0.9, torso_h, DONKEY_LENGTH * 0.6)
	_add_donkey_box(torso_size, Vector3(0.0, back_y - 0.05 - torso_h / 2.0, 0.0), false)

	_base_top = saddle_top
	_tower_top = saddle_top


func _add_donkey_box(size: Vector3, box_center: Vector3, visible_pad: bool) -> void:
	var box := BoxShape3D.new()
	box.size = size
	var col := CollisionShape3D.new()
	col.shape = box
	col.position = box_center
	_donkey_base.add_child(col)
	if visible_pad:
		# Show the saddle as a dark red blanket so the landing zone reads clearly.
		var bm := BoxMesh.new()
		bm.size = size
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.55, 0.15, 0.15)
		bm.material = mat
		var mesh := MeshInstance3D.new()
		mesh.mesh = bm
		mesh.position = box_center
		_donkey_base.add_child(mesh)
