extends SceneTree

## Dev tool: headless test of the ghost's surface alignment and
## auto-adjust (place_on). Run:
## godot --headless --path . --script res://tools/ghost_test.gd

func _init() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(main)
	var driver := Node.new()
	driver.name = "GhostTestDriver"
	driver.set_script(load("res://tools/ghost_test_driver.gd"))
	root.add_child.call_deferred(driver)
