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
const INTEGRITY_INTERVAL := 0.4  # seconds between floating-piece sweeps

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
var _pending_mod: Dictionary = {} # wheel result, locked onto the current object
var _integrity_timer := 0.0


func _ready() -> void:
	_rng.randomize()
	_setup_donkey()
	_kill_zone.body_entered.connect(_on_kill_zone_body_entered)
	_hud.restart_requested.connect(func() -> void: get_tree().reload_current_scene())
	_hud.wheel_landed.connect(_on_wheel_landed)
	_refresh_hud()
	_refresh_modifier_label()
	_spawn_next()


func _process(delta: float) -> void:
	if _phase != Phase.AIMING or _ghost == null:
		return
	if Input.is_key_pressed(KEY_Q):
		_ghost.spin(YAW_SPEED * delta)
	if Input.is_key_pressed(KEY_E):
		_ghost.spin(-YAW_SPEED * delta)


func _physics_process(delta: float) -> void:
	_integrity_timer += delta
	if _integrity_timer >= INTEGRITY_INTERVAL:
		_integrity_timer = 0.0
		_check_integrity()
	if _phase != Phase.AIMING or _ghost == null:
		return
	_update_ghost()


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
			if body is StaticBody3D and not rooted.has(obj):
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
	for obj in resting:
		if not rooted.has(obj):
			obj.break_loose(true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_TAB:
		# One spin per object: the wheel unlocks again once the modified
		# object has been placed. Spinning while one settles is fine — the
		# result lands on the next object.
		if _phase != Phase.GAME_OVER and _pending_mod.is_empty() \
				and not _hud.wheel_busy():
			_hud.spin_wheel()
		return
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
	var on_ground: bool = hit["collider"] == _ground
	_ghost.set_valid(not on_ground and fits)


func _spawn_next() -> void:
	var idx := _rng.randi_range(0, ObjectCatalog.ENTRIES.size() - 1)
	while idx == _last_index:
		idx = _rng.randi_range(0, ObjectCatalog.ENTRIES.size() - 1)
	_last_index = idx
	var entry: Dictionary = ObjectCatalog.ENTRIES[idx]
	_ghost = GhostPreview.create(entry, _pending_mod)
	_ghost.visible = false  # hidden until the first aim raycast lands
	add_child(_ghost)
	_phase = Phase.AIMING
	_refresh_incoming(entry)
	_refresh_modifier_label()


func _place_object(entry: Dictionary, xform: Transform3D) -> void:
	var obj := StackableObject.create(entry, _pending_mod)
	obj.transform = xform
	add_child(obj)
	obj.drop()
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


## First settle of a placed object: score it and move the game along.
func _on_object_settled(obj: StackableObject) -> void:
	if _phase == Phase.GAME_OVER or obj.state != StackableObject.State.SETTLED:
		return
	_settled.append(obj)
	_score += SCORE_PER_OBJECT
	if obj == _settling:
		_settling = null
	if _phase == Phase.SETTLING:
		_spawn_next()


## Every settle (including pieces that re-settle after glue broke):
## glue down (unless Slippery) and refresh the tower height.
func _on_object_resettled(obj: StackableObject) -> void:
	if _phase == Phase.GAME_OVER or obj.state != StackableObject.State.SETTLED:
		return
	if not obj.no_glue:
		obj.lock_in()
	_recompute_tower_top()
	_refresh_hud()


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


func _refresh_modifier_label() -> void:
	if _pending_mod.is_empty():
		_hud.set_modifier("Modifier: -   (Tab: spin the wheel)")
	else:
		_hud.set_modifier("Modifier: %s   (locked on this object)" % _pending_mod["name"])


func _refresh_incoming(entry: Dictionary) -> void:
	if _pending_mod.is_empty():
		_hud.set_incoming("Incoming: %s" % entry["name"])
	else:
		_hud.set_incoming("Incoming: %s %s" % [_pending_mod["name"], entry["name"]])


func _game_over(reason: String) -> void:
	_phase = Phase.GAME_OVER
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE  # so the Restart button is clickable
	_hud.set_crosshair(false)
	_hud.set_incoming("")
	_hud.show_game_over(reason, _total_score(), _max_height)


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
