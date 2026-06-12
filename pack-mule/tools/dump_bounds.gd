extends SceneTree

## Dev tool: prints the raw AABB of every .glb in assets/.
## Run: godot --headless --path . --script res://tools/dump_bounds.gd

func _init() -> void:
	var dir := DirAccess.open("res://assets")
	if dir == null:
		push_error("assets/ not found")
		quit(1)
		return
	for f in dir.get_files():
		if not f.ends_with(".glb"):
			continue
		var scene := load("res://assets/" + f) as PackedScene
		if scene == null:
			print("%s: FAILED TO LOAD" % f)
			continue
		var inst := scene.instantiate()
		var points := PackedVector3Array()
		StackableObject.collect_hull_points(inst, Transform3D.IDENTITY, points)
		if points.is_empty():
			print("%s: no mesh geometry" % f)
		else:
			var aabb := StackableObject.points_aabb(points)
			print("%-20s size=(%.2f, %.2f, %.2f) center=(%.2f, %.2f, %.2f)" % [
				f, aabb.size.x, aabb.size.y, aabb.size.z,
				aabb.get_center().x, aabb.get_center().y, aabb.get_center().z,
			])
		inst.free()
	quit(0)
