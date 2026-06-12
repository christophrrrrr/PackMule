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
	_check("new objects in catalog (15)", ObjectCatalog.ENTRIES.size() == 15)
	for n in ["Car", "Cow", "Rug", "Table", "Toilet", "Trashcan"]:
		_check("catalog has %s" % n, not _entry(n).is_empty())

	var plain := StackableObject.create(safe)
	var tiny := StackableObject.create(safe, _mod("Tiny"))
	var massive := StackableObject.create(safe, _mod("Massive"))
	var lead := StackableObject.create(safe, _mod("Lead"))
	var slippery := StackableObject.create(safe, _mod("Slippery"))
	var glue := StackableObject.create(safe, _mod("Super Glue"))

	_check("plain mass 100", is_equal_approx(plain.mass, 100.0))
	_check("Tiny mass scales with volume (16.6)", is_equal_approx(tiny.mass, 16.6))
	_check("Tiny size 0.55x",
			absf(tiny.half_extents.y / plain.half_extents.y - 0.55) < 0.01)
	_check("Massive mass 410", is_equal_approx(massive.mass, 410.0))
	_check("Massive size 1.6x",
			absf(massive.half_extents.y / plain.half_extents.y - 1.6) < 0.01)
	_check("Lead mass 300, same size", is_equal_approx(lead.mass, 300.0)
			and is_equal_approx(lead.half_extents.y, plain.half_extents.y))
	_check("Slippery never glues", slippery.no_glue)
	_check("Slippery low friction",
			is_equal_approx(slippery.physics_material_override.friction, 0.1))
	_check("Super Glue flag set", glue._super_glue and not glue.no_glue)
	_check("display name includes modifier", lead.display_name == "Lead Safe")

	for obj: StackableObject in [plain, tiny, massive, lead, slippery, glue]:
		obj.free()
	print("[modtest] done: %d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)
