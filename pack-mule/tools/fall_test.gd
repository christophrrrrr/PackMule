extends SceneTree

## Verifies a piece that drops below the tower counts as fallen right away
## (not only when it reaches the distant kill zone), so a third loss ends the
## run promptly and no further placement is possible. Run:
## godot --headless --path . --script res://tools/fall_test.gd

var _gm: Node = null
var _f := 0
var _fails := 0
var _phase := 0


func _init() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(main)


func _check(label: String, ok: bool) -> void:
	if ok:
		print("[falltest] PASS  ", label)
	else:
		_fails += 1
		print("[falltest] FAIL  ", label)


func _process(_dt: float) -> bool:
	_f += 1
	if _f < 10:
		return false
	if _phase == 0:
		_gm = root.get_node("Main")
		_gm._start_game()
		_check("starts in AIMING", _gm._phase == GameManager.Phase.AIMING)
		# Three pieces dropped below the lost line — each is unrecoverable.
		for i in 3:
			var o := StackableObject.create(ObjectCatalog.ENTRIES[0])
			_gm.add_child(o)
			o.fell.connect(_gm._on_object_fell.bind(o))  # as _place_object wires it
			o.global_position = Vector3(i * 2.0, StackableObject.LOST_Y - 1.0, 0.0)
			o.drop()
		_phase = 1
		_f = 0
		return false
	if _phase == 1 and _f >= 20:  # let physics tick the pieces past the line
		_check("third loss ends the run", _gm._phase == GameManager.Phase.GAME_OVER)
		_check("at least three strikes counted", _gm._strikes >= 3)
		print("[falltest] done: %d failure(s)" % _fails)
		quit(1 if _fails > 0 else 0)
	return false
