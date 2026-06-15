extends SceneTree

## Verifies a key like Space can be bound (it used to be swallowed by the
## focused button). Run:
## godot --headless --path . --script res://tools/key_test.gd

var _f := 0


func _init() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(main)


func _process(_dt: float) -> bool:
	_f += 1
	if _f < 5:
		return false
	var hud := root.get_node("Main/HUD") as GameHud
	hud._open_settings()
	hud._begin_listen("pm_up", hud._bind_buttons["pm_up"])
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.pressed = true
	hud._input(ev)
	var result := GameSettings.binding_text("pm_up")
	var ok := result == "SPACE"
	print("[keytest] %s  bound pm_up to '%s' (wanted SPACE)" % ["PASS" if ok else "FAIL", result])
	GameSettings.reset_binds()  # restore defaults
	quit(0 if ok else 1)
	return true
