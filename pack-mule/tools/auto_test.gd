extends SceneTree

## Dev tool: boots the main scene headless with a test driver that
## auto-drops objects, to smoke-test the full game loop without input.
## Run: godot --headless --path . --script res://tools/auto_test.gd
## Optionally pick a physics mode: ... --script res://tools/auto_test.gd -- mode=2

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("mode="):
			GameModes.selected = clampi(
					int(arg.trim_prefix("mode=")), 0, GameModes.MODES.size() - 1)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(main)
	var driver := Node.new()
	driver.name = "TestDriver"
	driver.set_script(load("res://tools/test_driver.gd"))
	root.add_child.call_deferred(driver)
