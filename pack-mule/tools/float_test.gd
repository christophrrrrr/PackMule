extends SceneTree

## Dev tool: headless test that glued pieces can never float. Run:
## godot --headless --path . --script res://tools/float_test.gd

func _init() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(main)
	var driver := Node.new()
	driver.name = "FloatTestDriver"
	driver.set_script(load("res://tools/float_test_driver.gd"))
	root.add_child.call_deferred(driver)
