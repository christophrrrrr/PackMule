class_name GhostPreview
extends Node3D

## Translucent "blueprint" preview of the next object. Pure visuals — no
## physics body — so it can be rotated and moved freely. The game manager
## snaps it onto surfaces and asks it whether the spot is clear.

const COLOR_VALID := Color(0.35, 0.75, 1.0, 0.45)
const COLOR_INVALID := Color(1.0, 0.3, 0.25, 0.45)

const ADJUST_STEP := 0.05
const MAX_ADJUST := 1.0

var entry: Dictionary
var half_extents := Vector3.ONE * 0.5
var hull_points := PackedVector3Array()
var valid := false

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


## Distance from the ghost's origin to its hull surface along -normal,
## i.e. how far the origin must sit from a surface for the hull to rest
## flush on it in the current rotation.
func bottom_offset(normal: Vector3) -> float:
	var b := global_transform.basis
	var lowest := INF
	for p in hull_points:
		lowest = minf(lowest, (b * p).dot(normal))
	return -lowest


## Auto-adjust: if the hull overlaps anything, nudge the ghost outward along
## the surface normal (then straight up) until it sits clear, keeping the
## player's chosen rotation. Returns false only when no clear spot exists
## within MAX_ADJUST.
func fit_clear(space: PhysicsDirectSpaceState3D, normal: Vector3) -> bool:
	if not overlaps(space):
		return true
	for dir: Vector3 in [normal, Vector3.UP]:
		var base := global_position
		var dist := ADJUST_STEP
		while dist <= MAX_ADJUST:
			global_position = base + dir * dist
			if not overlaps(space):
				return true
			dist += ADJUST_STEP
		global_position = base
	return false


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
