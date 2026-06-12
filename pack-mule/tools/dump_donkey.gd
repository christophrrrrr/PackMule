extends SceneTree

## Dev tool: prints the normalized donkey's height profile along its body
## axis, to place the saddle platform sensibly. Run:
## godot --headless --path . --script res://tools/dump_donkey.gd

func _init() -> void:
	var model: Node3D = (load("res://assets/Donkey.glb") as PackedScene).instantiate()
	var points := PackedVector3Array()
	StackableObject.collect_hull_points(model, Transform3D.IDENTITY, points)
	var aabb := StackableObject.points_aabb(points)
	var along_x := aabb.size.x >= aabb.size.z
	var sf := 3.0 / maxf(aabb.size.x, aabb.size.z)
	var center := aabb.get_center()
	var origin_offset := Vector3(center.x, aabb.position.y, center.z)
	print("[donkey] aabb=%s along_x=%s sf=%.3f" % [aabb, along_x, sf])

	var faces := PackedVector3Array()
	_faces(model, Transform3D.IDENTITY, faces)
	# Normalize like the game does.
	var slices := {}
	for v in faces:
		var q := (v - origin_offset) * sf
		var t := q.x if along_x else q.z
		var w := q.z if along_x else q.x
		var slice := int(floor(t / 0.2))
		var cur: Array = slices.get(slice, [-INF, 0.0])
		if q.y > cur[0]:
			slices[slice] = [q.y, w]
	var keys := slices.keys()
	keys.sort()
	for k: int in keys:
		var s: Array = slices[k]
		print("[donkey] t=%5.1f..%5.1f  max_y=%5.2f (at w=%5.2f)" % [
				k * 0.2, k * 0.2 + 0.2, s[0], s[1]])
	model.free()
	quit(0)


func _faces(node: Node, parent_xform: Transform3D, faces: PackedVector3Array) -> void:
	var xform := parent_xform
	if node is Node3D:
		xform = parent_xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		for v in (node as MeshInstance3D).mesh.get_faces():
			faces.append(xform * v)
	for child in node.get_children():
		_faces(child, xform, faces)
