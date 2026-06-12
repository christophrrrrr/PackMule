class_name GhostPreview
extends Node3D

## Translucent "blueprint" preview of the next object. Pure visuals — no
## physics body — so it can be rotated and moved freely. The game manager
## hands it the aimed surface point and it orients, snaps, and de-overlaps
## itself: tilting flush onto slopes and rotating/sliding out of collisions.

const COLOR_VALID := Color(0.35, 0.75, 1.0, 0.45)
const COLOR_INVALID := Color(1.0, 0.3, 0.25, 0.45)

const PLACE_GAP := 0.02          # clearance between hull and surface
const ADJUST_STEP := 0.05        # slide increment for the preferred pose
const MAX_ADJUST := 1.0          # how far the preferred pose may slide
const ROT_ADJUST_STEP := 0.1     # coarser slide for rotated fit candidates
const ROT_MAX_ADJUST := 0.4
const FIT_YAWS_DEG := [15.0, -15.0, 30.0, -30.0, 45.0, -45.0]
const FIT_TILTS_DEG := [10.0, -10.0, 20.0, -20.0]

var entry: Dictionary
var half_extents := Vector3.ONE * 0.5
var hull_points := PackedVector3Array()
var valid := false
## The player's manual Q/E/R rotation, kept in an upright reference frame.
## The surface alignment is applied on top of it every update, so spinning
## and tilting never fight each other.
var user_basis := Basis.IDENTITY

var _mat := StandardMaterial3D.new()
var _shape := ConvexPolygonShape3D.new()


static func create(p_entry: Dictionary) -> GhostPreview:
	var ghost := GhostPreview.new()
	ghost.name = "Ghost"
	ghost.entry = p_entry
	ghost._build()
	return ghost


func set_valid(value: bool) -> void:
	valid = value
	_mat.albedo_color = COLOR_VALID if value else COLOR_INVALID


## Q/E: spin around the surface the ghost is resting on (a world-up yaw in
## user space becomes a spin around the surface normal after alignment).
func spin(angle: float) -> void:
	user_basis = (Basis(Vector3.UP, angle) * user_basis).orthonormalized()


## R: tip 90 degrees around a world-space axis (camera-relative).
func tip(axis: Vector3, angle: float) -> void:
	user_basis = (Basis(axis, angle) * user_basis).orthonormalized()


## Minimal rotation that takes world-up onto the surface normal, so the
## object's underside tilts flush against slopes and walls.
static func align_up(normal: Vector3) -> Basis:
	var d := clampf(Vector3.UP.dot(normal), -1.0, 1.0)
	if d > 0.9999:
		return Basis.IDENTITY
	if d < -0.9999:
		return Basis(Vector3.RIGHT, PI)
	var axis := Vector3.UP.cross(normal).normalized()
	return Basis(axis, acos(d))


## Orient the ghost to the surface, snap it flush onto the hit point, and
## auto-adjust out of any overlap: first by sliding (along the normal, then
## up), then by trying small spins and tilts so it can wedge into gaps.
## Returns false only when no clear pose exists nearby; the ghost is then
## left in its canonical (unrotated, flush) pose.
func place_on(space: PhysicsDirectSpaceState3D, hit_pos: Vector3, normal: Vector3) -> bool:
	var aligned := align_up(normal) * user_basis
	for rot in _fit_rotations(normal):
		var preferred: bool = rot.is_equal_approx(Basis.IDENTITY)
		global_basis = rot * aligned
		var origin := hit_pos + normal * (bottom_offset(normal) + PLACE_GAP)
		global_position = origin
		if not overlaps(space):
			return true
		var step := ADJUST_STEP if preferred else ROT_ADJUST_STEP
		var max_dist := MAX_ADJUST if preferred else ROT_MAX_ADJUST
		for dir: Vector3 in [normal, Vector3.UP]:
			var dist := step
			while dist <= max_dist:
				global_position = origin + dir * dist
				if not overlaps(space):
					return true
				dist += step
	global_basis = aligned
	global_position = hit_pos + normal * (bottom_offset(normal) + PLACE_GAP)
	return false


## Candidate rotation deltas for the fit search, smallest change first so
## the ghost prefers poses close to what the player asked for.
func _fit_rotations(normal: Vector3) -> Array[Basis]:
	var list: Array[Basis] = [Basis.IDENTITY]
	var t1 := normal.cross(Vector3.RIGHT)
	if t1.length_squared() < 0.01:
		t1 = normal.cross(Vector3.FORWARD)
	t1 = t1.normalized()
	var t2 := normal.cross(t1).normalized()
	for deg: float in FIT_YAWS_DEG:
		list.append(Basis(normal, deg_to_rad(deg)))
	for deg: float in FIT_TILTS_DEG:
		list.append(Basis(t1, deg_to_rad(deg)))
		list.append(Basis(t2, deg_to_rad(deg)))
	return list


## Distance from the ghost's origin to its hull surface along -normal,
## i.e. how far the origin must sit from a surface for the hull to rest
## flush on it in the current rotation.
func bottom_offset(normal: Vector3) -> float:
	var b := global_transform.basis
	var lowest := INF
	for p in hull_points:
		lowest = minf(lowest, (b * p).dot(normal))
	return -lowest


## True if the hull at the ghost's current transform overlaps any world
## geometry (ground, donkey, or placed objects).
func overlaps(space: PhysicsDirectSpaceState3D) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _shape
	query.transform = global_transform
	query.collision_mask = 1 | 2
	return not space.intersect_shape(query, 1).is_empty()


func _build() -> void:
	half_extents = StackableObject.build_normalized_model(
			self, entry["path"], entry["size"], hull_points)
	_shape.points = hull_points
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = COLOR_VALID
	_apply_override(self)


func _apply_override(node: Node) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = _mat
	for child in node.get_children():
		_apply_override(child)
