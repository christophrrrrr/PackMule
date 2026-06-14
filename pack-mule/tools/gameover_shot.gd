extends SceneTree

## Dev tool (windowed): stacks a few objects, triggers game over, and
## screenshots the postcard panel to user://shot.png.
## godot --path . --script res://tools/gameover_shot.gd

var _frame := 0
var _gm: Node = null
var _go := false


func _init() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(main)


func _entry(n: String) -> Dictionary:
	for e in ObjectCatalog.ENTRIES:
		if e["name"] == n:
			return e
	return ObjectCatalog.ENTRIES[0]


func _place(n: String, y: float) -> void:
	_gm._place_object(_entry(n), Transform3D(Basis.IDENTITY, Vector3(0.0, y, 0.0)))


func _process(_dt: float) -> bool:
	_frame += 1
	if _gm == null and root.has_node("Main"):
		_gm = root.get_node("Main")
		_gm._start_game()  # skip the main menu
		_gm.set_physics_process(false)  # no mouse aiming
	if _gm == null:
		return false
	var base: float = _gm._base_top
	# Compact objects, tight gaps → a stable glued tower to test framing.
	match _frame:
		15: _place("Safe", base + 0.5)
		30: _place("Washer", base + 1.2)
		45: _place("Toilet", base + 1.9)
		60: _place("Trashcan", base + 2.6)
		75: _place("Safe", base + 3.3)
		90: _place("Washer", base + 4.0)
		105: _place("Toilet", base + 4.7)
		120: _place("Trashcan", base + 5.4)
		300:
			if not _go:
				_go = true
				if "cash" in OS.get_cmdline_user_args():
					_gm._cash_out()
				else:
					_gm._game_over("TOO MANY FALLEN OBJECTS")
	if _frame == 350:
		var img := root.get_texture().get_image()
		img.save_png("user://shot.png")
		print("[gameover_shot] saved")
		quit(0)
	return false
