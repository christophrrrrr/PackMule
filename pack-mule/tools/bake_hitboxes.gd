extends SceneTree

## Bakes every catalog object's convex decomposition into
## res://hitboxes.res, so the game never runs V-HACD at spawn time.
## Re-run whenever assets are added or changed:
## godot --headless --path . --script res://tools/bake_hitboxes.gd

func _init() -> void:
	var lib := HitboxLibrary.new()
	var total := 0.0
	for entry in ObjectCatalog.ENTRIES:
		var path: String = entry["path"]
		var t0 := Time.get_ticks_usec()
		var parts := StackableObject.compute_parts(path)
		total += (Time.get_ticks_usec() - t0) / 1000.0
		var arr: Array[PackedVector3Array] = []
		for p in parts:
			arr.append(p)
		lib.entries[path] = arr
		print("baked %-16s %d parts" % [entry["name"], arr.size()])
	var err := ResourceSaver.save(lib, StackableObject.LIBRARY_PATH)
	if err != OK:
		push_error("save failed: %d" % err)
		quit(1)
		return
	print("wrote %s (%d objects, %.0f ms of work baked away)" % [
			StackableObject.LIBRARY_PATH, lib.entries.size(), total])
	quit(0)
