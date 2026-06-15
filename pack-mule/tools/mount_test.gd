extends SceneTree

## Verifies every purchasable mount loads and builds a valid stacking base
## (a body collision + a saddle platform at a sensible height). Non-destructive.
## godot --headless --path . --script res://tools/mount_test.gd

var _gm: Node = null
var _frame := 0
var _fails := 0


func _init() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(main)


func _check(label: String, ok: bool) -> void:
	if ok:
		print("[mounttest] PASS  ", label)
	else:
		_fails += 1
		print("[mounttest] FAIL  ", label)


func _process(_dt: float) -> bool:
	_frame += 1
	if _frame < 5:
		return false
	_gm = root.get_node("Main")
	var base0 := GameSettings.get_base()

	for mount: Dictionary in ShopCatalog.MOUNTS:
		GameSettings.set_base(mount["id"])
		_gm._rebuild_base()
		var has_col := false
		var has_saddle_mesh := false
		for c in _gm._donkey_base.get_children():
			if c is CollisionShape3D:
				has_col = true
			if c is MeshInstance3D:
				has_saddle_mesh = true
		_check("%s builds a body collision" % mount["name"], has_col)
		_check("%s builds a saddle platform" % mount["name"], has_saddle_mesh)
		_check("%s saddle height is sane" % mount["name"], _gm._base_top > 0.3 and _gm._base_top < 12.0)

	GameSettings.set_base(base0)
	_gm._rebuild_base()
	print("[mounttest] done: %d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)
	return true
