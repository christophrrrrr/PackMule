extends SceneTree

## Dev tool: boots the main scene headless with a test driver that
## auto-drops objects, to smoke-test the full game loop without input.
## Run: godot --headless --path . --script res://tools/auto_test.gd

func _init() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(main)
	var driver := Node.new()
	driver.name = "TestDriver"
	driver.set_script(load("res://tools/test_driver.gd"))
	root.add_child.call_deferred(driver)
