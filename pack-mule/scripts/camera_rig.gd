class_name CameraRig
extends Node3D

## Two camera modes, chosen at startup by GameSettings.is_mobile():
##  • Desktop — always-on free-fly: the mouse looks around (cursor captured),
##    WASD flies, Space rises, Ctrl descends, Shift sprints, the wheel sets
##    fly speed. (Esc is handled by the HUD: it pauses.)
##  • Mobile — touch free-fly: a fixed on-screen joystick (bottom-left, owned
##    by the HUD) flies you toward where you look (push up = forward, so look up
##    to rise and down to descend; left/right strafes), and dragging anywhere
##    else looks around. It mirrors the desktop free-fly, so it reaches every
##    surface too.

const LOOK_SENSITIVITY := 0.0035
const DEFAULT_SPEED := 8.0
const MIN_SPEED := 2.0
const MAX_SPEED := 50.0
const SPEED_STEP := 1.25
const SPRINT_MULT := 2.5
const MAX_PITCH := 1.55  # ~89° — look (almost) straight down/up, no dead cone
const SHAKE_DECAY := 6.0

const START_POSITION := Vector3(8.0, 5.5, 11.0)
const START_LOOK_AT := Vector3(0.0, 1.0, 0.0)

# A "bubble" the camera can roam: a horizontal radius around the peak, from
# just above the clouds up to well above a tall tower. Plus solid avoidance
# so you can't fly into the mountain, donkey, or placed objects.
const BOUND_RADIUS := 35.0
const BOUND_MIN_Y := -6.0
const BOUND_MAX_Y := 55.0
const AVOID_RADIUS := 0.6

# --- Mobile (touch free-fly) — tunable after an on-device test ---------------
const TOUCH_LOOK_SENS := 0.006     # look drag -> yaw/pitch, radians per pixel
const TOUCH_MOVE_SPEED := 9.0      # joystick fly speed, meters/second

var _speed := DEFAULT_SPEED
var _yaw := 0.0
var _pitch := 0.0
var _shake := 0.0
var _avoid := SphereShape3D.new()

# Mobile state (only used when _is_mobile).
var _is_mobile := false
var _look_index := -1              # the touch index currently driving the look
var _hud: Node = null              # polled each frame for the move-joystick vector

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	_is_mobile = GameSettings.is_mobile()
	_hud = get_parent().get_node_or_null("HUD")
	_avoid.radius = AVOID_RADIUS
	reset_view()
	# The game manager owns the mouse mode (the main menu needs a visible
	# cursor); it captures the mouse when the run starts. On mobile there is
	# no cursor and input arrives as touch events handled below.


## Touch look: a drag anywhere outside the joystick/buttons rotates the view
## (yaw + pitch), exactly like the desktop mouse-look. Only the first such
## finger drives it, so the left thumb on the joystick never fights it.
func _handle_touch(event: InputEvent) -> void:
	# Ignore touches outside of an active run (the menu camera is a static
	# backdrop; the rig stops processing then).
	if not is_processing():
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _look_index == -1:
				_look_index = touch.index
		elif touch.index == _look_index:
			_look_index = -1
	elif event is InputEventScreenDrag and (event as InputEventScreenDrag).index == _look_index:
		var drag := event as InputEventScreenDrag
		_yaw -= drag.relative.x * TOUCH_LOOK_SENS
		_pitch = clampf(_pitch - drag.relative.y * TOUCH_LOOK_SENS, -MAX_PITCH, MAX_PITCH)
		rotation = Vector3(_pitch, _yaw, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if _is_mobile:
		_handle_touch(event)
		return
	# Only act on input while flying (cursor captured). On the menu the cursor
	# is visible, and an unguarded wheel here used to silently change the fly
	# speed before a run even started.
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		_yaw -= event.relative.x * LOOK_SENSITIVITY
		_pitch = clampf(_pitch - event.relative.y * LOOK_SENSITIVITY, -MAX_PITCH, MAX_PITCH)
		rotation = Vector3(_pitch, _yaw, 0.0)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_speed = minf(MAX_SPEED, _speed * SPEED_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_speed = maxf(MIN_SPEED, _speed / SPEED_STEP)


func _process(delta: float) -> void:
	if _is_mobile:
		_mobile_fly(delta)
		_update_shake(delta)
		return
	var dir := Vector3.ZERO
	var b := transform.basis
	if Input.is_action_pressed("pm_forward"):
		dir -= b.z
	if Input.is_action_pressed("pm_back"):
		dir += b.z
	if Input.is_action_pressed("pm_left"):
		dir -= b.x
	if Input.is_action_pressed("pm_right"):
		dir += b.x
	if Input.is_action_pressed("pm_up"):
		dir += Vector3.UP
	if Input.is_action_pressed("pm_down"):
		dir -= Vector3.UP
	if dir != Vector3.ZERO:
		var speed := _speed * (SPRINT_MULT if Input.is_key_pressed(KEY_SHIFT) else 1.0)
		var move := dir.normalized() * speed * delta
		# If something (e.g. a freshly placed object) ended up around the
		# camera, let it fly out freely; otherwise slide along walls and stay
		# inside the bubble and out of solid geometry.
		var stuck := _blocked(position)
		_try_move(Vector3(move.x, 0.0, 0.0), stuck)
		_try_move(Vector3(0.0, move.y, 0.0), stuck)
		_try_move(Vector3(0.0, 0.0, move.z), stuck)
	_update_shake(delta)


## Fly from the on-screen joystick: push toward where you look. Stick Y drives
## forward/back along the view (look up + forward = rise, down = descend); stick
## X strafes. Same bubble bounds and solid-avoidance as the desktop fly.
func _mobile_fly(delta: float) -> void:
	if _hud == null:
		return
	var stick: Vector2 = _hud.move_vector() if _hud.has_method("move_vector") else Vector2.ZERO
	var vert: float = _hud.vert_dir() if _hud.has_method("vert_dir") else 0.0
	var b := transform.basis
	var dir := -b.z * stick.y + b.x * stick.x + Vector3.UP * vert
	if dir.length() < 0.001:
		return
	var move := dir.limit_length(1.0) * TOUCH_MOVE_SPEED * delta
	var stuck := _blocked(position)
	_try_move(Vector3(move.x, 0.0, 0.0), stuck)
	_try_move(Vector3(0.0, move.y, 0.0), stuck)
	_try_move(Vector3(0.0, 0.0, move.z), stuck)


## Screen shake: jitter the camera child, decaying back to centered. Shared by
## both camera modes (it only touches the Camera3D's local offset).
func _update_shake(delta: float) -> void:
	if _shake > 0.001:
		_camera.position = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0),
				randf_range(-1.0, 1.0)) * _shake
		_shake = move_toward(_shake, 0.0, SHAKE_DECAY * _shake * delta + delta)
	elif _camera.position != Vector3.ZERO:
		_camera.position = Vector3.ZERO


## Move by one axis if the destination is inside the bubble and not inside
## solid geometry — unless we're already stuck inside something, in which
## case any move is allowed so the player can get out.
func _try_move(step: Vector3, stuck: bool) -> void:
	var cand := _clamp_bounds(position + step)
	if stuck or not _blocked(cand):
		position = cand


func _clamp_bounds(p: Vector3) -> Vector3:
	var flat := Vector2(p.x, p.z)
	if flat.length() > BOUND_RADIUS:
		flat = flat.normalized() * BOUND_RADIUS
	return Vector3(flat.x, clampf(p.y, BOUND_MIN_Y, BOUND_MAX_Y), flat.y)


func _blocked(p: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	if space == null:
		return false
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _avoid
	q.transform = Transform3D(Basis.IDENTITY, p)
	q.collision_mask = 1 | 2  # static world (mountain/donkey/ground) + objects
	return not space.intersect_shape(q, 1).is_empty()


## Reset the fly speed to its default at the start of a run, so every run
## begins at the same pace regardless of any earlier wheel scrolling.
func reset_flight() -> void:
	_speed = DEFAULT_SPEED
	_shake = 0.0


## Snap the camera back to its opening pose. Yaw and pitch are computed
## directly (no look_at) so the rotation is always roll-free and identical
## every time — look_at's euler decomposition could otherwise fold in a roll
## and leave the camera tilted/flipped after a restart.
func reset_view() -> void:
	position = START_POSITION
	var dir := (START_LOOK_AT - START_POSITION).normalized()
	_pitch = asin(clampf(dir.y, -1.0, 1.0))
	_yaw = atan2(-dir.x, -dir.z)
	rotation = Vector3(_pitch, _yaw, 0.0)
	# The game-over postcard reframes the tower with _camera.look_at(), which
	# rotates the Camera3D child. The in-place restart reused this rig, so that
	# leftover tilt made the view come back flipped and "forward" point wrong.
	# Reset the child fully — it only ever carries the shake offset otherwise.
	_camera.position = Vector3.ZERO
	_camera.rotation = Vector3.ZERO
	_look_index = -1
	reset_flight()


## Kick the camera; bigger amount = bigger jolt. Used for impacts/collapses.
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)
