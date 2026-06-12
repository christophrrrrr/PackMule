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

var state := State.HELD
var display_name := ""
var half_extents := Vector3.ONE * 0.5

var _still_time := 0.0
var _fall_time := 0.0


## `mode` is one of GameModes.MODES and supplies the physics feel
## (friction, bounce, damping) for the active run.
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


## Sticky mode: lock a settled object in place so the tower below can
## never wobble apart — it becomes part of the terrain.
func lock_in() -> void:
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true


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
	var shape := ConvexPolygonShape3D.new()
	shape.points = hull_points
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)


func _enter_held() -> void:
	state = State.HELD
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	# No collision while hovering, so the held object can't shove the tower.
	collision_layer = 0
	collision_mask = 0
