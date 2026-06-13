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
		_gm.set_physics_process(false)  # no mouse aiming
	if _gm == null:
		return false
	var base: float = _gm._base_top
	match _frame:
		15: _place("Safe", base + 0.6)
		19: _place("Washer", base + 1.5)
		23: _place("Toilet", base + 2.5)
		27: _place("Chair", base + 3.4)
		31: _place("Trashcan", base + 4.3)
		220:
			if not _go:
				_go = true
				_gm._game_over("TOWER COLLAPSED!")
	if _frame == 270:
		var img := root.get_texture().get_image()
		img.save_png("user://shot.png")
		print("[gameover_shot] saved")
		quit(0)
	return false
