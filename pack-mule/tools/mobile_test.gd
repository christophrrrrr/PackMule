extends SceneTree

## Verifies the mobile (touch) build: the orbit camera, the on-screen control
## cluster, and the placement-trigger wiring. Force mobile with the `mobile`
## user arg so it runs on desktop. Run:
## godot --headless --path . --script res://tools/mobile_test.gd -- mobile

var _f := 0
var _fails := 0


func _init() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(main)


func _check(label: String, ok: bool) -> void:
	if ok:
		print("[mobiletest] PASS  ", label)
	else:
		_fails += 1
		print("[mobiletest] FAIL  ", label)


func _process(_dt: float) -> bool:
	_f += 1
	# Let the scene build and a few physics frames run first.
	if _f < 12:
		return false
	var gm := root.get_node("Main")
	var hud := gm.get_node("HUD")
	var rig := gm.get_node("CameraRig")

	_check("is_mobile() true under the mobile arg", GameSettings.is_mobile())

	# --- On-screen controls ---------------------------------------------------
	gm._start_game()  # needed so the rig is processing (look/fly active)
	_check("phase is AIMING after start", gm._phase == GameManager.Phase.AIMING)
	_check("mobile control cluster built", hud._mobile_controls != null)
	_check("control cluster visible in-run",
			hud._mobile_controls != null and hud._mobile_controls.visible)
	_check("move joystick built", hud._joy_base != null)
	_check("cash-out button starts disabled", hud._cash_btn.disabled)

	# Rotate / vertical getters mirror the held-button state.
	hud._rot_dir = 1.0
	_check("rotate_dir() reports left", hud.rotate_dir() == 1.0)
	hud._rot_dir = 0.0
	hud._vert_dir = 1.0
	_check("vert_dir() reports up", hud.vert_dir() == 1.0)
	hud._vert_dir = 0.0

	# --- Free-fly camera: joystick moves, drag looks -------------------------
	# move_vector() relays the joystick to the rig.
	hud._joy_vec = Vector2(0.4, -0.6)
	_check("move_vector reports the joystick", hud.move_vector() == Vector2(0.4, -0.6))

	# Looking up + pushing the stick forward should climb (reach high spots);
	# looking down should descend (reach the base). Start in open air so the
	# solid-avoidance bubble doesn't interfere.
	rig.position = Vector3(15.0, 18.0, 15.0)
	rig.rotation = Vector3(0.8, 0.0, 0.0)  # look up
	hud._joy_vec = Vector2(0.0, 1.0)       # stick forward
	var y_climb: float = rig.position.y
	for i in 12:
		rig._mobile_fly(0.08)
	_check("fly + look up climbs (reach high)", rig.position.y > y_climb + 0.5)

	rig.position = Vector3(15.0, 18.0, 15.0)
	rig.rotation = Vector3(-0.8, 0.0, 0.0)  # look down
	var y_dive: float = rig.position.y
	for i in 12:
		rig._mobile_fly(0.08)
	_check("fly + look down descends (reach the base)", rig.position.y < y_dive - 0.5)
	hud._joy_vec = Vector2.ZERO

	# Up button flies straight up, no matter where you look.
	rig.position = Vector3(15.0, 18.0, 15.0)
	rig.rotation = Vector3(0.0, 0.0, 0.0)  # look level
	hud._vert_dir = 1.0
	var y_up: float = rig.position.y
	for i in 10:
		rig._mobile_fly(0.08)
	_check("up button climbs straight up", rig.position.y > y_up + 0.5)
	hud._vert_dir = 0.0

	# A drag anywhere (outside the joystick) looks around.
	var yaw0: float = rig._yaw
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.pressed = true
	rig._handle_touch(press)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.relative = Vector2(60.0, 0.0)
	rig._handle_touch(drag)
	_check("drag looks around (yaw changes)", rig._yaw != yaw0)
	var lift := InputEventScreenTouch.new()
	lift.index = 0
	lift.pressed = false
	rig._handle_touch(lift)

	# --- Placement-trigger wiring --------------------------------------------
	_check("place_requested wired to _try_place",
			hud.place_requested.is_connected(gm._try_place))
	_check("tip_requested wired to _try_tip",
			hud.tip_requested.is_connected(gm._try_tip))
	_check("spin_requested wired to _try_spin",
			hud.spin_requested.is_connected(gm._try_spin))

	# Aim at the saddle and refresh the ghost, then place via the button signal
	# and confirm an object actually dropped.
	rig.position = Vector3(0.0, gm._base_top + 3.0, 4.0)
	rig.look_at(Vector3(0.0, gm._base_top, 0.0), Vector3.UP)
	gm._update_ghost()
	_check("crosshair shown while aiming on mobile", hud._crosshair.visible)
	var before := _count_objects(gm)
	if gm._ghost != null and gm._ghost.valid:
		hud.place_requested.emit()
		_check("PLACE button drops an object", _count_objects(gm) > before)
	else:
		_check("ghost valid for placement (no aim hit)", false)

	# --- Photo mode is escapable on mobile (there is no [P]/[Esc]) ------------
	hud.start_photo_mode()
	_check("photo SNAP/DONE overlay shown on mobile",
			hud._mobile_photo != null and hud._mobile_photo.visible)
	_check("entered photo mode", hud._photo)
	hud._photo_to_pause()  # what the DONE button calls
	_check("DONE leaves photo mode", not hud._photo)
	_check("photo overlay hidden after DONE", not hud._mobile_photo.visible)
	_check("pause menu shown after DONE", hud._pause != null and hud._pause.visible)

	print("[mobiletest] done: %d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)
	return true


func _count_objects(gm: Node) -> int:
	var n := 0
	for c in gm.get_children():
		if c is StackableObject:
			n += 1
	return n
