extends SceneTree

## Dev tool: verifies a stray object dropped onto the summit dome (beside
## the donkey, not on the tower) slides off instead of sticking. Run:
## godot --headless --path . --script res://tools/stray_test.gd

func _init() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(main)
	var driver := Node.new()
	driver.name = "StrayTestDriver"
	driver.set_script(load("res://tools/stray_test_driver.gd"))
	root.add_child.call_deferred(driver)
