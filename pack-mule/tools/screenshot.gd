extends SceneTree

## Dev tool: boots the main scene, waits a moment, saves a screenshot to
## user://shot.png and quits. Run (windowed, not headless):
## godot --path . --script res://tools/screenshot.gd

var _frames := 0
var _spin_wheel := false


func _init() -> void:
	_spin_wheel = "wheel" in OS.get_cmdline_user_args()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 30 and _spin_wheel:
		(root.get_node("Main/HUD") as GameHud).spin_wheel()
	if _frames == 10 and "side" in OS.get_cmdline_user_args():
		var rig: Node3D = root.get_node("Main/CameraRig")
		rig.position = Vector3(5.0, 2.0, 2.0)
		rig.look_at(Vector3(0.0, 4.5, 0.0))  # crosshair in the sky: ghost hides
		rig._yaw = rig.rotation.y
		rig._pitch = rig.rotation.x
	if _frames == 10 and "far" in OS.get_cmdline_user_args():
		var rig: Node3D = root.get_node("Main/CameraRig")
		rig.position = Vector3(20.0, 6.0, 20.0)
		rig.look_at(Vector3(0.0, -4.0, 0.0))
		rig._yaw = rig.rotation.y
		rig._pitch = rig.rotation.x
	if _frames == 10 and "feet" in OS.get_cmdline_user_args():
		var rig: Node3D = root.get_node("Main/CameraRig")
		rig.position = Vector3(4.0, 2.6, 4.0)
		rig.look_at(Vector3(0.0, 0.3, 0.0))  # look down at the hooves / peak rock
		rig._yaw = rig.rotation.y
		rig._pitch = rig.rotation.x
	if _frames == 60:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("user://shot.png")
		print("[shot] saved ", OS.get_user_data_dir(), "/shot.png")
		quit(0)
	return false
