extends SceneTree

## Headless checks for the cash-out / multiplier loop. Run:
## godot --headless --path . --script res://tools/cash_test.gd

var _gm: Node = null
var _frame := 0
var _fails := 0


func _init() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(main)


func _check(label: String, ok: bool) -> void:
	if ok:
		print("[cashtest] PASS  ", label)
	else:
		_fails += 1
		print("[cashtest] FAIL  ", label)


func _process(_dt: float) -> bool:
	_frame += 1
	if _frame < 5:
		return false
	_gm = root.get_node("Main")
	_gm._start_game()

	# Multiplier curve: 1, 1.5, 2, 3, 4, 6, 8, 11, 14, 18.
	var want := [1.0, 1.5, 2.0, 3.0, 4.0, 6.0, 8.0, 11.0, 14.0, 18.0]
	for i in want.size():
		_check("multiplier streak %d = %s" % [i, want[i]],
				is_equal_approx(_gm._streak_multiplier(i), want[i]))

	# Cash out banks the pending pot and resets the multiplier.
	_gm._pending = 175
	_gm._streak = 5
	_gm._multiplier = 6.0
	_gm._banked = 40
	_gm._cash_out()
	_check("cash out adds pending to banked", _gm._banked == 215)
	_check("cash out clears pending", _gm._pending == 0)
	_check("cash out resets multiplier to 1", is_equal_approx(_gm._multiplier, 1.0))
	_check("cash out resets streak", _gm._streak == 0)
	_check("run continues after cash out (not game over)",
			_gm._phase != GameManager.Phase.GAME_OVER)

	# Nothing to cash: cashing out with an empty pot does nothing.
	var before: int = _gm._banked
	_gm._cash_out()
	_check("cashing an empty pot is a no-op", _gm._banked == before)

	# Can't cash while a piece is mid-fall (the exploit fix).
	var faller := StackableObject.create(ObjectCatalog.ENTRIES[0])
	_gm.add_child(faller)
	faller.drop()  # -> FALLING
	_check("tower not at rest while a piece falls", not _gm._tower_at_rest())
	_gm._pending = 100
	var b2: int = _gm._banked
	_gm._cash_out()
	_check("cash out blocked while a piece is falling", _gm._banked == b2)
	faller.queue_free()

	print("[cashtest] done: %d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)
	return true
