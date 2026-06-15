extends SceneTree

## Verifies the in-place restart (Stack Again) clears the old run and begins a
## fresh one without reloading the scene. Run:
## godot --headless --path . --script res://tools/restart_test.gd

var _gm: Node = null
var _f := 0
var _fails := 0


func _init() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(main)


func _check(label: String, ok: bool) -> void:
	if ok:
		print("[restarttest] PASS  ", label)
	else:
		_fails += 1
		print("[restarttest] FAIL  ", label)


func _process(_dt: float) -> bool:
	_f += 1
	if _f < 5:
		return false
	_gm = root.get_node("Main")
	_gm._start_game()
	# Dirty the run and leave a stray placed object behind.
	_gm._banked = 500
	_gm._strikes = 2
	_gm._placed_count = 7
	var dummy := StackableObject.create(ObjectCatalog.ENTRIES[0])
	_gm.add_child(dummy)
	# Simulate the game-over postcard having rotated/moved the camera child.
	_gm._camera.rotation = Vector3(0.5, 1.2, 0.3)
	_gm._camera.position = Vector3(3.0, 2.0, 1.0)

	_gm._on_restart()

	_check("restart clears camera-child tilt",
			_gm._camera.rotation.is_equal_approx(Vector3.ZERO))
	_check("restart recenters camera child",
			_gm._camera.position.is_equal_approx(Vector3.ZERO))

	_check("restart returns to AIMING", _gm._phase == GameManager.Phase.AIMING)
	_check("restart clears banked", _gm._banked == 0)
	_check("restart clears strikes", _gm._strikes == 0)
	_check("restart clears placed count", _gm._placed_count == 0)
	_check("restart spawns a fresh ghost", _gm._ghost != null)
	var leftover := 0
	for c in _gm.get_children():
		if c is StackableObject:
			leftover += 1
	_check("restart clears old objects", leftover == 0)

	print("[restarttest] done: %d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)
	return true
