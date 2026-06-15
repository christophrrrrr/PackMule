class_name StackableObject
extends RigidBody3D

## One stackable physics object, built at runtime from a .glb asset:
## the visual model is normalized to the catalog's target size and recentered,
## and a single convex hull is generated for collision.
##
## Physics is the "Sticky" feel: grippy and damped, and every object glues
## in place once it settles. The glue is breakable — a hard enough impact
## (momentum above BREAK_MOMENTUM) knocks pieces loose, and everything
## resting on them wakes too. Wheel modifiers can change size, mass,
## friction, and glue behavior per object.

signal settled
signal fell

enum State { HELD, FALLING, SETTLED, FALLEN }

const SETTLE_LINEAR_SPEED := 0.15
const SETTLE_ANGULAR_SPEED := 0.4
const SETTLE_STILL_TIME := 0.7
const SETTLE_TIMEOUT := 6.0
# A falling piece this far below the donkey's feet is unrecoverable, so it
# counts as fallen right away (the run can end promptly) even though it keeps
# tumbling toward the cloud band for the visual.
const LOST_Y := -3.0

const FRICTION := 1.6
const BOUNCE := 0.0
const LINEAR_DAMP := 0.6
const ANGULAR_DAMP := 6.0
## Glue strength: an impact with mass * speed above this knocks the hit
## glued piece loose. The duck can never crack it; a piano falling ~40 cm can.
const BREAK_MOMENTUM := 250.0

## How far the hull is shifted down when searching for supporting objects.
const SUPPORT_PROBE := 0.05
## A settled-but-unglued (Slippery) piece that drifts this far from its
## settle spot counts as knocked loose, waking everything stacked on it.
const DRIFT_BREAK := 0.2

var state := State.HELD
var display_name := ""
var half_extents := Vector3.ONE * 0.5
var no_glue := false             # Slippery: never locks in
var sound := "wood"              # impact material (see ObjectCatalog)

## Impact sounds: only above this speed, and no more often than this, so a
## tumbling tower clatters without a machine-gun of clicks.
const IMPACT_MIN_SPEED := 1.6
const IMPACT_COOLDOWN := 0.12

var _super_glue := false         # bonds instantly on first touch, unbreakable
var _model: Node3D               # visual mesh root (scaled for the landing pop)
var _model_scale := Vector3.ONE
var _impact_cooldown := 0.0
var _still_time := 0.0
var _fall_time := 0.0
var _speed_last_tick := 0.0
var _settle_pos := Vector3.ZERO
var _supporters: Array[StackableObject] = []
var _dependents: Array[StackableObject] = []
var _hull := ConvexPolygonShape3D.new()


## `modifier` is one of ModifierCatalog.ENTRIES (or {} for none) and can
## scale size and mass, override friction, and change glue behavior.
## `golden` makes the object purely cosmetically gold (a rare 1% treat).
static func create(entry: Dictionary, modifier: Dictionary = {}, golden := false) -> StackableObject:
	var obj := StackableObject.new()
	obj.display_name = entry["name"] if modifier.is_empty() \
			else "%s %s" % [modifier["name"], entry["name"]]
	obj.name = (obj.display_name as String).replace(" ", "")
	obj.mass = entry["mass"] * modifier.get("mass_mul", 1.0)
	obj.linear_damp = LINEAR_DAMP
	obj.angular_damp = ANGULAR_DAMP
	var mat := PhysicsMaterial.new()
	var friction: float = modifier.get("friction", -1.0)
	mat.friction = friction if friction >= 0.0 else FRICTION
	mat.bounce = BOUNCE
	obj.physics_material_override = mat
	obj.no_glue = modifier.get("no_glue", false)
	obj._super_glue = modifier.get("super_glue", false)
	obj.sound = entry.get("sound", "wood")
	# Impact reporting, so hard hits can break glue (and Super Glue can bond).
	obj.contact_monitor = true
	obj.max_contacts_reported = 8
	obj.body_entered.connect(obj._on_body_entered)
	obj._build_model(entry["path"], entry["size"] * modifier.get("size_mul", 1.0))
	if golden:
		obj._make_golden()
	obj._enter_held()
	return obj


## Collects simplified convex-hull vertices of every mesh in the subtree,
## transformed into the root's local space. Hull vertices share the same AABB
## as the full mesh, so they serve both collision and bounds measurement.
static func collect_hull_points(node: Node, parent_xform: Transform3D, points: PackedVector3Array) -> void:
	var xform := parent_xform
	if node is Node3D:
		xform = parent_xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var hull := (node as MeshInstance3D).mesh.create_convex_shape(true, true)
		if hull is ConvexPolygonShape3D:
			for p in (hull as ConvexPolygonShape3D).points:
				points.append(xform * p)
	for child in node.get_children():
		collect_hull_points(child, xform, points)


## Convex parts (raw model space) of a .glb so hollow objects (tub, toilet,
## trashcan...) get real concave hitboxes instead of a shrink-wrapped
## block. The expensive V-HACD pass is baked into HitboxLibrary; this just
## loads the parts. Cache survives scene reloads.
const LIBRARY_PATH := "res://hitboxes.res"

static var _decomp_cache := {}
static var _library: HitboxLibrary = null
static var _library_loaded := false


static func _get_library() -> HitboxLibrary:
	if not _library_loaded:
		_library_loaded = true
		if ResourceLoader.exists(LIBRARY_PATH):
			_library = load(LIBRARY_PATH)
	return _library


static func decompose(path: String) -> Dictionary:
	if _decomp_cache.has(path):
		return _decomp_cache[path]
	var parts: Array[PackedVector3Array] = []
	var lib := _get_library()
	if lib != null and lib.entries.has(path):
		for p: PackedVector3Array in lib.entries[path]:
			parts.append(p)
	else:
		# Not baked (e.g. a newly added asset): compute live this once. The
		# in-memory cache keeps it to a single hitch per session; re-run
		# tools/bake_hitboxes.gd to fold it into the library.
		push_warning("Hitbox for %s not baked; computing live (slow)" % path)
		parts = compute_parts(path)
	var all_points := PackedVector3Array()
	for part in parts:
		all_points.append_array(part)
	var result := {
		"parts": parts,
		"aabb": points_aabb(all_points) if not all_points.is_empty() else AABB(),
	}
	_decomp_cache[path] = result
	return result


## The raw V-HACD pass: instantiates the .glb and returns its convex parts
## in model space. Used by the bake tool and the not-baked fallback.
static func compute_parts(path: String) -> Array[PackedVector3Array]:
	var model: Node3D = (load(path) as PackedScene).instantiate()
	var parts: Array[PackedVector3Array] = []
	_collect_convex_parts(model, Transform3D.IDENTITY, parts)
	model.free()
	return parts


static func _collect_convex_parts(node: Node, parent_xform: Transform3D, parts: Array[PackedVector3Array]) -> void:
	var xform := parent_xform
	if node is Node3D:
		xform = parent_xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		var settings := MeshConvexDecompositionSettings.new()
		settings.max_convex_hulls = 8
		settings.max_concavity = 0.02
		settings.resolution = 200000
		mi.create_multiple_convex_collisions(settings)
		var found := false
		for child in mi.get_children():
			if child is not StaticBody3D:
				continue
			for col in child.get_children():
				if col is CollisionShape3D and (col as CollisionShape3D).shape is ConvexPolygonShape3D:
					var out := PackedVector3Array()
					for p in ((col as CollisionShape3D).shape as ConvexPolygonShape3D).points:
						out.append(xform * p)
					if out.size() >= 3:
						parts.append(out)
						found = true
		if not found:
			# Decomposition failed (degenerate mesh): single hull fallback.
			var hull := mi.mesh.create_convex_shape(true, true)
			if hull is ConvexPolygonShape3D:
				var out := PackedVector3Array()
				for p in (hull as ConvexPolygonShape3D).points:
					out.append(xform * p)
				if out.size() >= 3:
					parts.append(out)
	for child in node.get_children():
		_collect_convex_parts(child, xform, parts)


## Completely flat parts (the rug has zero height) get padded to a minimum
## thickness, centered on the original plane, so Jolt has a real volume.
static func _ensure_thickness(points: PackedVector3Array) -> PackedVector3Array:
	var aabb := points_aabb(points)
	var pad := Vector3.ZERO
	for axis in 3:
		if aabb.size[axis] < 0.04:
			pad[axis] = (0.04 - aabb.size[axis]) / 2.0
	if pad == Vector3.ZERO:
		return points
	var out := PackedVector3Array()
	for p in points:
		out.append(p - pad)
		out.append(p + pad)
	return out


static func points_aabb(points: PackedVector3Array) -> AABB:
	var aabb := AABB(points[0], Vector3.ZERO)
	for p in points:
		aabb = aabb.expand(p)
	return aabb


## Instantiates the .glb under `host`, scales it so its longest side equals
## `target_size`, and recenters it on the host's origin. Returns
## {"half_extents": Vector3, "parts": Array[PackedVector3Array],
##  "points": PackedVector3Array} where parts are the normalized convex
## decomposition pieces and points is their union (for bounds/snapping).
## Shared by the physics object and the blueprint ghost.
static func build_normalized_model(host: Node3D, path: String, target_size: float) -> Dictionary:
	var model: Node3D = (load(path) as PackedScene).instantiate()
	host.add_child(model)
	var decomp := decompose(path)
	var raw_parts: Array[PackedVector3Array] = decomp["parts"]
	if raw_parts.is_empty():
		push_error("No mesh geometry found in %s" % path)
		return {"half_extents": Vector3.ZERO, "parts": [], "points": PackedVector3Array()}
	var aabb: AABB = decomp["aabb"]
	var longest := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	var sf := target_size / longest
	var center := aabb.get_center()
	model.scale = Vector3.ONE * sf
	model.position = -center * sf
	var parts: Array[PackedVector3Array] = []
	var union := PackedVector3Array()
	for raw in raw_parts:
		var out := PackedVector3Array()
		for p in raw:
			out.append((p - center) * sf)
		out = _ensure_thickness(out)
		parts.append(out)
		union.append_array(out)
	return {
		"half_extents": aabb.size * sf * 0.5,
		"parts": parts,
		"points": union,
		"model": model,
	}


func drop() -> void:
	if state != State.HELD:
		return
	state = State.FALLING
	collision_layer = 2
	collision_mask = 1 | 2
	freeze = false
	# The frozen kinematic body accumulates velocity from being teleported to
	# the cursor; clear it so the object falls instead of being flung.
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_still_time = 0.0
	_fall_time = 0.0


## Glue a settled object in place. The glue is breakable — see break_loose().
func lock_in() -> void:
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true


func is_glued() -> bool:
	return freeze and state == State.SETTLED


## Knocks the piece loose: it becomes dynamic again and everything that was
## resting on it wakes too (chain reaction). A loose piece that comes to
## rest settles and re-glues via the normal settle path. Super Glue pieces
## resist impacts, but `force` (used when a piece is disconnected from the
## tower — nothing may ever float) breaks even them.
func break_loose(force := false) -> void:
	if state != State.SETTLED or (_super_glue and not force):
		return
	for s in _supporters:
		s._dependents.erase(self)
	_supporters.clear()
	var deps := _dependents.duplicate()
	_dependents.clear()
	state = State.FALLING
	_still_time = 0.0
	_fall_time = 0.0
	if freeze:
		freeze = false
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
	# A long-static body is asleep; left sleeping, the settle check would
	# re-glue it the very next tick without gravity ever acting.
	sleeping = false
	for d in deps:
		d.break_loose()


## The Sfx stream name for this object's material ("wood" → the woody thunk).
func impact_sound() -> String:
	return "thunk" if sound == "wood" else sound


## Briefly mute collision impact sounds — used right after placement so the
## placement sound isn't doubled by the tiny settling drop.
func suppress_impact() -> void:
	_impact_cooldown = 0.35


## A quick squash-and-stretch on the visual mesh (collision is untouched),
## for a satisfying "landed" pop. Bigger pieces pop a touch harder.
func pop() -> void:
	if _model == null:
		return
	var squash := Vector3(_model_scale.x * 1.16, _model_scale.y * 0.84, _model_scale.z * 1.16)
	_model.scale = squash
	var tw := create_tween().set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_model, "scale", _model_scale, 0.4)


## Called by the game manager when this body enters the kill zone.
## Anything that was resting on this piece loses its support immediately.
func mark_fallen() -> void:
	if state == State.FALLEN:
		return
	state = State.FALLEN
	for s in _supporters:
		s._dependents.erase(self)
	_supporters.clear()
	var deps := _dependents.duplicate()
	_dependents.clear()
	for d: StackableObject in deps:
		d.break_loose(true)
	fell.emit()


## Bodies (static world or other stackables) the hull is touching, found
## with a small margin. Used by the integrity sweep: a glued piece that
## touches nothing anchored must fall.
func touching_bodies(space: PhysicsDirectSpaceState3D) -> Array:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _hull
	query.transform = global_transform
	query.margin = 0.18  # generous, so a glued piece with a small gap still
	                     # reads as connected (avoids false "floating" breaks)
	query.collision_mask = 1 | 2
	query.exclude = [get_rid()]
	var bodies := []
	for hit in space.intersect_shape(query, 12):
		bodies.append(hit["collider"])
	return bodies


## World-space Y of the highest point of this object's rotated bounding box.
func top_y() -> float:
	var b := global_transform.basis
	var ext := absf(b.x.y) * half_extents.x \
			+ absf(b.y.y) * half_extents.y \
			+ absf(b.z.y) * half_extents.z
	return global_position.y + ext


func _physics_process(delta: float) -> void:
	# Speed entering this tick, captured before the solver runs: body_entered
	# fires after collision response has already changed the velocity.
	_speed_last_tick = 0.0 if freeze else linear_velocity.length()
	if _impact_cooldown > 0.0:
		_impact_cooldown -= delta
	if state == State.SETTLED and not freeze \
			and global_position.distance_squared_to(_settle_pos) > DRIFT_BREAK * DRIFT_BREAK:
		# A Slippery piece slid away from where it settled: treat as a break
		# so everything stacked on it wakes up.
		break_loose()
		return
	if state != State.FALLING:
		return
	if global_position.y < LOST_Y:
		# Already past the point of recovery — count it now so a third loss
		# ends the run immediately, instead of waiting for the long fall to
		# the kill zone. It keeps falling for the visual (mark_fallen is idempotent).
		mark_fallen()
		return
	_fall_time += delta
	var is_still := linear_velocity.length() < SETTLE_LINEAR_SPEED \
			and angular_velocity.length() < SETTLE_ANGULAR_SPEED
	_still_time = _still_time + delta if is_still else 0.0
	if sleeping or _still_time >= SETTLE_STILL_TIME or _fall_time >= SETTLE_TIMEOUT:
		_settle_now()


## Marks the object settled: remembers the rest position, records what it
## is resting on (for break cascades), and notifies the game manager.
func _settle_now() -> void:
	state = State.SETTLED
	_settle_pos = global_position
	_register_supports()
	settled.emit()


## Finds the settled objects this one is resting on (hull shifted slightly
## down) and registers itself as their dependent.
func _register_supports() -> void:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _hull
	query.transform = global_transform.translated(Vector3.DOWN * SUPPORT_PROBE)
	query.collision_mask = 2
	query.exclude = [get_rid()]
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 8):
		var other := hit["collider"] as StackableObject
		if other != null and other.state == State.SETTLED and other not in _supporters:
			_supporters.append(other)
			other._dependents.append(self)


## Contact handler: Super Glue bonds the instant it touches anything, and
## a hard enough hit on a glued piece cracks its glue. Momentum of the
## moving piece (mass * speed entering this tick) is the severity measure:
## light objects can never break glue, heavy ones need real speed.
func _on_body_entered(body: Node) -> void:
	if state == State.HELD:
		return
	# Clatter when this piece hits something hard, throttled so it never
	# machine-guns. Hitting the bare mountain gives a stony "rock" thud;
	# hitting the tower / another object gives the woody "thunk".
	if _impact_cooldown <= 0.0 and _speed_last_tick >= IMPACT_MIN_SPEED:
		_impact_cooldown = IMPACT_COOLDOWN
		var pitch := clampf(remap(mass, 5.0, 400.0, 1.5, 0.6), 0.55, 1.6) * randf_range(0.95, 1.05)
		# Loudness scales with both impact speed and mass — heavy hits boom.
		var vol := clampf(remap(_speed_last_tick, 1.6, 10.0, -11.0, -3.0), -13.0, -3.0) \
				+ clampf(remap(mass, 5.0, 400.0, -4.0, 4.0), -4.0, 4.0)
		# The object's own material always plays; on bare rock, add a crunch.
		Sfx.play_at(impact_sound(), global_position, pitch, vol)
		if body.is_in_group("mountain"):
			Sfx.play_at("rock", global_position, pitch, vol - 6.0)
	if _super_glue and state == State.FALLING:
		_settle_now()
		return
	var other := body as StackableObject
	if other != null and other.is_glued() \
			and mass * _speed_last_tick >= BREAK_MOMENTUM:
		other.break_loose()


func _build_model(path: String, target_size: float) -> void:
	var built := build_normalized_model(self, path, target_size)
	half_extents = built["half_extents"]
	_model = built["model"]
	if _model != null:
		_model_scale = _model.scale
	var union: PackedVector3Array = built["points"]
	if union.is_empty():
		return
	# Real collision is the convex decomposition (one shape per part), so
	# hollow objects can hold things. The union hull stays as the cheap
	# query shape for support probes and the integrity sweep.
	_hull.points = union
	for part: PackedVector3Array in built["parts"]:
		var shape := ConvexPolygonShape3D.new()
		shape.points = part
		var col := CollisionShape3D.new()
		col.shape = shape
		add_child(col)


## Overrides every mesh with a shiny gold material (cosmetic only).
func _make_golden() -> void:
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(1.0, 0.82, 0.16)
	gold.metallic = 1.0
	gold.roughness = 0.28
	_paint(self, gold)


func _paint(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for child in node.get_children():
		_paint(child, mat)


func _enter_held() -> void:
	state = State.HELD
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	# No collision while hovering, so the held object can't shove the tower.
	collision_layer = 0
	collision_mask = 0
