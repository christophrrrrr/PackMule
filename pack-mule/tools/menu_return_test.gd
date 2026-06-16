extends SceneTree

## Verifies returning to the main menu happens in place (no scene reload):
## the run state clears and the menu shows, with the world reused. Run:
## godot --headless --path . --script res://tools/menu_return_test.gd

var _gm: Node = null
var _f := 0
var _fails := 0


func _init() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(main)


func _check(label: String, ok: bool) -> void:
	if ok:
		print("[menutest] PASS  ", label)
	else:
		_fails += 1
		print("[menutest] FAIL  ", label)


func _process(_dt: float) -> bool:
	_f += 1
	if _f < 5:
		return false
	_gm = root.get_node("Main")
	_gm._start_game()
	# Dirty the run and leave a placed object behind.
	_gm._banked = 1234
	var dummy := StackableObject.create(ObjectCatalog.ENTRIES[0])
	_gm.add_child(dummy)
	var donkey_kids := _gm.get_node("DonkeyBase").get_child_count()

	_gm._go_to_menu()

	_check("returns to MENU phase", _gm._phase == GameManager.Phase.MENU)
	_check("run no longer started", not _gm._started)
	_check("banked reset", _gm._banked == 0)
	var leftover := 0
	for c in _gm.get_children():
		if c is StackableObject:
			leftover += 1
	_check("tower cleared", leftover == 0)
	# The world is REUSED, not rebuilt: the donkey/base is the same instance.
	_check("world reused (donkey kept)",
			_gm.get_node("DonkeyBase").get_child_count() == donkey_kids)
	_check("cursor visible for menu", Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)

	print("[menutest] done: %d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)
	return true
