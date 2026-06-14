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
	if _frames == 6 and ("play" in OS.get_cmdline_user_args() or "dust" in OS.get_cmdline_user_args()):
		(root.get_node("Main") as GameManager)._start_game()
	if _frames == 12 and "pause" in OS.get_cmdline_user_args():
		(root.get_node("Main") as GameManager)._start_game()
		(root.get_node("Main/HUD") as GameHud)._toggle_pause()
	if _frames == 6 and "birds" in OS.get_cmdline_user_args():
		var gm := root.get_node("Main") as GameManager
		gm._start_game()
		gm._event_eagles()
		gm._event_balloon()
	if _frames == 6 and "fireworks" in OS.get_cmdline_user_args():
		var gm := root.get_node("Main") as GameManager
		gm._start_game()
		gm._event_fireworks()
	if "photobar" in OS.get_cmdline_user_args():
		var gm := root.get_node("Main") as GameManager
		if _frames == 6:
			gm._start_game()
		if _frames == 12:
			(root.get_node("Main/HUD") as GameHud).start_photo_mode(true)
	if "photomode" in OS.get_cmdline_user_args():
		var gm := root.get_node("Main") as GameManager
		if _frames == 6:
			gm._start_game()
		if _frames == 12:
			(root.get_node("Main/HUD") as GameHud).start_photo_mode(false)
		if _frames == 30:
			(root.get_node("Main/HUD") as GameHud)._snap_photo()
		if _frames == 44:
			(root.get_node("Main/HUD") as GameHud)._end_photo_mode()
		if _frames == 52:
			var h := root.get_node("Main/HUD") as GameHud
			print("[photomode] after exit: paused=%s hud_visible=%s" % [
					paused, h._stats_box.visible])
	if _frames == 8 and "odds" in OS.get_cmdline_user_args():
		(root.get_node("Main/HUD") as GameHud)._open_odds()
	if _frames == 8 and "settings" in OS.get_cmdline_user_args():
		(root.get_node("Main/HUD") as GameHud)._open_settings()
	if _frames == 8 and "galleryview" in OS.get_cmdline_user_args():
		(root.get_node("Main/HUD") as GameHud)._open_gallery()
	if _frames == 14 and "dust" in OS.get_cmdline_user_args():
		var gm := root.get_node("Main") as GameManager
		gm.set_physics_process(false)
		gm._spawn_dust(Vector3(0, gm._base_top + 1.5, 0), 40, 2.5)
	if "dust" in OS.get_cmdline_user_args() and _frames == 20:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("user://shot.png")
		print("[shot] saved dust")
		quit(0)
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
