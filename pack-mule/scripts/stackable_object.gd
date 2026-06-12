class_name StackableObject
extends RigidBody3D

## One stackable physics object, built at runtime from a .glb asset:
## the visual model is normalized to the catalog's target size and recentered,
## and a single convex hull is generated for collision.

signal settled
signal fell

enum State { HELD, FALLING, SETTLED, FALLEN }

const SETTLE_LINEAR_SPEED := 0.15
const SETTLE_ANGULAR_SPEED := 0.4
const SETTLE_STILL_TIME := 0.7
const SETTLE_TIMEOUT := 6.0

## How far the hull is shifted down when searching for supporting objects.
const SUPPORT_PROBE := 0.05

var state := State.HELD
var display_name := ""
var half_extents := Vector3.ONE * 0.5

var _still_time := 0.0
var _fall_time := 0.0
var _speed_last_tick := 0.0
var _break_momentum := 0.0       # glue strength from the mode; 0 = no glue logic
var _supporters: Array[StackableObject] = []
var _dependents: Array[StackableObject] = []
var _hull := ConvexPolygonShape3D.new()


## `mode` is one of GameModes.MODES and supplies the physics feel
## (friction, bounce, damping, glue strength) for the active run.
static func create(entry: Dictionary, mode: Dictionary) -> StackableObject:
	var obj := StackableObject.new()
	obj.display_name = entry["name"]
	obj.name = (entry["name"] as String).replace(" ", "")
	obj.mass = entry["mass"]
	obj.linear_damp = mode["linear_damp"]
	obj.angular_damp = mode["angular_damp"]
	var mat := PhysicsMaterial.new()
	mat.friction = mode["friction"]
	mat.bounce = mode["bounce"]
	obj.physics_material_override = mat
	obj._break_momentum = mode["break_momentum"]
	if mode["freeze_settled"]:
		# Glued towers need impact reporting so hard hits can break the glue.
		obj.contact_monitor = true
		obj.max_contacts_reported = 8
		obj.body_entered.connect(obj._on_body_entered)
	obj._build_model(entry["path"], entry["size"])
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


static func points_aabb(points: PackedVector3Array) -> AABB:
	var aabb := AABB(points[0], Vector3.ZERO)
	for p in points:
		aabb = aabb.expand(p)
	return aabb


## Instantiates the .glb under `host`, scales it so its longest side equals
## `target_size`, and recenters it on the host's origin. Appends the
## normalized hull vertices to `hull_out` and returns the half extents.
## Shared by the physics object and the blueprint ghost.
static func build_normalized_model(host: Node3D, path: String, target_size: float, hull_out: PackedVector3Array) -> Vector3:
	var model: Node3D = (load(path) as PackedScene).instantiate()
	host.add_child(model)
	var points := PackedVector3Array()
	collect_hull_points(model, Transform3D.IDENTITY, points)
	if points.is_empty():
		push_error("No mesh geometry found in %s" % path)
		return Vector3.ZERO
	var aabb := points_aabb(points)
	var longest := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	var sf := target_size / longest
	var center := aabb.get_center()
	model.scale = Vector3.ONE * sf
	model.position = -center * sf
	for p in points:
		hull_out.append((p - center) * sf)
	return aabb.size * sf * 0.5


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


## Sticky mode: glue a settled object in place. The glue is breakable —
## see break_loose(). Also records which settled objects this one rests
## on, so a break below can wake everything stacked above it.
func lock_in() -> void:
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	_register_supports()


func is_glued() -> bool:
	return freeze and state == State.SETTLED


## Breaks the glue: this object becomes dynamic again and everything that
## was resting on it is knocked loose too (chain reaction). A loose piece
## that comes to rest settles and re-glues via the normal settle path.
func break_loose() -> void:
	if not is_glued():
		return
	for s in _supporters:
		s._dependents.erase(self)
	_supporters.clear()
	var deps := _dependents.duplicate()
	_dependents.clear()
	state = State.FALLING
	_still_time = 0.0
	_fall_time = 0.0
	freeze = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	for d in deps:
		d.break_loose()


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
		if other != null and other.is_glued() and other not in _supporters:
			_supporters.append(other)
			other._dependents.append(self)


## A hard enough hit on a glued piece cracks its glue. Momentum of the
## moving piece (mass * speed entering this tick) is the severity measure:
## light objects can never break glue, heavy ones need real speed.
func _on_body_entered(body: Node) -> void:
	if _break_momentum <= 0.0 or state == State.HELD:
		return
	var other := body as StackableObject
	if other != null and other.is_glued() \
			and mass * _speed_last_tick >= _break_momentum:
		other.break_loose()


## Called by the game manager when this body enters the kill zone.
func mark_fallen() -> void:
	if state == State.FALLEN:
		return
	state = State.FALLEN
	fell.emit()


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
	if state != State.FALLING:
		return
	_fall_time += delta
	var is_still := linear_velocity.length() < SETTLE_LINEAR_SPEED \
			and angular_velocity.length() < SETTLE_ANGULAR_SPEED
	_still_time = _still_time + delta if is_still else 0.0
	if sleeping or _still_time >= SETTLE_STILL_TIME or _fall_time >= SETTLE_TIMEOUT:
		state = State.SETTLED
		settled.emit()


func _build_model(path: String, target_size: float) -> void:
	var hull_points := PackedVector3Array()
	half_extents = build_normalized_model(self, path, target_size, hull_points)
	if hull_points.is_empty():
		return
	_hull.points = hull_points
	var col := CollisionShape3D.new()
	col.shape = _hull
	add_child(col)


func _enter_held() -> void:
	state = State.HELD
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	# No collision while hovering, so the held object can't shove the tower.
	collision_layer = 0
	collision_mask = 0
