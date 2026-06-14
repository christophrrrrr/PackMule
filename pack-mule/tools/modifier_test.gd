extends SceneTree

## Dev tool: headless assertions on the modifier catalog applied to
## StackableObject (no physics needed). Run:
## godot --headless --path . --script res://tools/modifier_test.gd

var _fails := 0


func _check(label: String, ok: bool) -> void:
	if ok:
		print("[modtest] PASS  ", label)
	else:
		_fails += 1
		print("[modtest] FAIL  ", label)


func _entry(entry_name: String) -> Dictionary:
	for e in ObjectCatalog.ENTRIES:
		if e["name"] == entry_name:
			return e
	return {}


func _mod(mod_name: String) -> Dictionary:
	for m in ModifierCatalog.ENTRIES:
		if m["name"] == mod_name:
			return m
	return {}


func _init() -> void:
	var safe := _entry("Safe")
	_check("Traffic Cone removed", _entry("Traffic Cone").is_empty())
	_check("catalog has 20 objects", ObjectCatalog.ENTRIES.size() == 20)
	for n in ["Bear", "Grill", "Helicopter", "T-Rex", "Windmill"]:
		_check("catalog has %s" % n, not _entry(n).is_empty())

	var plain := StackableObject.create(safe)
	var tiny := StackableObject.create(safe, _mod("Tiny"))
	var massive := StackableObject.create(safe, _mod("Massive"))
	var heavy := StackableObject.create(safe, _mod("Heavy"))
	var slippery := StackableObject.create(safe, _mod("Slippery"))
	var glue := StackableObject.create(safe, _mod("Super Glue"))

	_check("plain mass 100", is_equal_approx(plain.mass, 100.0))
	_check("Tiny mass scales with volume (4.3)", is_equal_approx(tiny.mass, 4.3))
	_check("Tiny size 0.35x",
			absf(tiny.half_extents.y / plain.half_extents.y - 0.35) < 0.01)
	_check("Massive mass 410", is_equal_approx(massive.mass, 410.0))
	_check("Massive size 1.6x",
			absf(massive.half_extents.y / plain.half_extents.y - 1.6) < 0.01)
	_check("Heavy mass 300, same size", is_equal_approx(heavy.mass, 300.0)
			and is_equal_approx(heavy.half_extents.y, plain.half_extents.y))
	_check("Slippery never glues", slippery.no_glue)
	_check("Slippery low friction",
			is_equal_approx(slippery.physics_material_override.friction, 0.1))
	_check("Super Glue flag set", glue._super_glue and not glue.no_glue)
	_check("display name includes modifier", heavy.display_name == "Heavy Safe")

	# Hollow objects must decompose into several convex parts (real basins).
	var tub := StackableObject.create(_entry("Tub"))
	var tub_shapes := 0
	for child in tub.get_children():
		if child is CollisionShape3D:
			tub_shapes += 1
	_check("Tub hitbox is %d convex parts (>2)" % tub_shapes, tub_shapes > 2)

	for obj: StackableObject in [plain, tiny, massive, heavy, slippery, glue, tub]:
		obj.free()
	print("[modtest] done: %d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)
