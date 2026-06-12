extends SceneTree

## Dev tool: headless test of Sticky mode's breakable glue. Run:
## godot --headless --path . --script res://tools/sticky_test.gd

func _init() -> void:
	GameModes.selected = 2  # Sticky
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(main)
	var driver := Node.new()
	driver.name = "StickyTestDriver"
	driver.set_script(load("res://tools/sticky_test_driver.gd"))
	root.add_child.call_deferred(driver)
